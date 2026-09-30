#import "WFRepositoryService.h"
#import "WFProcessDefinition+Repository.h"
#import "WFDecision+Repository.h"
#import "WFStore.h"
#import "WFBpmn.h"
#import "WFFlowElements.h"
#import "WFDuration.h"
#import "WFTimers.h"
#import "WFProcessEngine+Internal.h"
#import "WFCommandContext.h"

static NSError *
WFRepositoryError(WFErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:WFErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static BOOL
WFIsBpmnResource(NSString *name)
{
	return [name hasSuffix:@".bpmn"] || [name hasSuffix:@".bpmn20.xml"];
}

static BOOL
WFIsDmnResource(NSString *name)
{
	return [name hasSuffix:@".dmn"] || [name hasSuffix:@".dmn11.xml"];
}

@interface WFDeployment ()
@property (nonatomic, readwrite, copy) NSString *deploymentId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSDate *deployedAt;
@property (nonatomic, readwrite, copy) NSArray<WFProcessDefinition *> *definitions;
@property (nonatomic, readwrite, copy) NSArray<WFDecisionDefinition *> *decisions;
@end

@implementation WFDeployment
@end

/* The forms of a definition's nodes, and of the nodes of the
 * subprocesses in it, by activity id. */
static NSDictionary<NSString *, WFFormDefinition *> *
WFFormsOf(WFProcessDefinition *definition)
{
	NSMutableDictionary *forms = [NSMutableDictionary dictionary];
	for (WFFlowNode *node in [definition.nodes allValues]) {
		if (node.form != nil) {
			[forms setObject:node.form forKey:node.elementId];
		}
		if ([node isKindOfClass:[WFSubProcess class]]) {
			[forms addEntriesFromDictionary:WFFormsOf([(WFSubProcess *)node innerDefinition])];
		}
	}
	return forms;
}

@implementation WFRepositoryService
{
	WFStore *_store;
	/* Definition id to its definition. Definitions are immutable, so a
	 * cached one never goes stale. */
	NSMutableDictionary<NSString *, WFProcessDefinition *> *_cache;
	/* The same for decisions. */
	NSMutableDictionary<NSString *, WFDecisionDefinition *> *_decisions;
	void (^_didStoreDeployment)(void);
	__weak WFProcessEngine *_engine;
}

- (void)wf_setEngine:(WFProcessEngine *)engine
{
	_engine = engine;
}

- (BOOL)setSuspended:(BOOL)suspended
          definition:(NSString *)definitionId
    includeInstances:(BOOL)includeInstances
               error:(NSError **)error
{
	WFProcessEngine *engine = _engine;
	BOOL ok = [engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		[command setSuspended:suspended definition:definitionId includeInstances:includeInstances];
		return YES;
	} error:error];
	if (ok && !suspended) {
		[engine wf_reschedule];
	}
	return ok;
}

- (BOOL)suspendDefinition:(NSString *)definitionId
         includeInstances:(BOOL)includeInstances
                    error:(NSError **)error
{
	return [self setSuspended:YES definition:definitionId includeInstances:includeInstances error:error];
}

- (BOOL)activateDefinition:(NSString *)definitionId
          includeInstances:(BOOL)includeInstances
                     error:(NSError **)error
{
	return [self setSuspended:NO definition:definitionId includeInstances:includeInstances error:error];
}

- (BOOL)isDefinitionSuspended:(NSString *)definitionId
{
	return [_store definitionRecordWithId:definitionId].suspended;
}

- (void (^)(void))didStoreDeployment
{
	return _didStoreDeployment;
}

- (void)setDidStoreDeployment:(void (^)(void))block
{
	_didStoreDeployment = [block copy];
}

- (instancetype)initWithStore:(WFStore *)store
{
	self = [super init];
	if (self) {
		_store = store;
		_cache = [NSMutableDictionary dictionary];
		_decisions = [NSMutableDictionary dictionary];
	}
	return self;
}

/* Every executable process in the deployment's BPMN resources, as parsed
 * definitions paired with the resource they came from. */
- (NSArray *)parseResources:(NSDictionary<NSString *, NSData *> *)resources
                      error:(NSError **)error
{
	NSMutableArray *parsed = [NSMutableArray array];
	NSMutableSet *keys = [NSMutableSet set];
	for (NSString *name in [[resources allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if (!WFIsBpmnResource(name)) {
			continue;
		}
		NSError *parseError = nil;
		NSArray *definitions = [WFBpmnReader definitionsFromData:[resources objectForKey:name]
		                                                   error:&parseError];
		if (definitions == nil) {
			if (error != NULL) {
				*error = WFRepositoryError(WFErrorInvalidBpmn,
					[NSString stringWithFormat:@"%@: %@", name,
						[parseError localizedDescription]]);
			}
			return nil;
		}
		for (WFProcessDefinition *definition in definitions) {
			if ([keys containsObject:definition.processId]) {
				if (error != NULL) {
					*error = WFRepositoryError(WFErrorInvalidDefinition,
						[NSString stringWithFormat:
							@"process %@ is defined twice in one deployment",
							definition.processId]);
				}
				return nil;
			}
			[keys addObject:definition.processId];
			[parsed addObject:@[ definition, name ]];
		}
	}
	return parsed;
}

/* Every decision in the deployment's DMN resources, paired with the
 * resource it came from. */
- (NSArray *)parseDecisions:(NSDictionary<NSString *, NSData *> *)resources
                      error:(NSError **)error
{
	NSMutableArray *parsed = [NSMutableArray array];
	NSMutableSet *keys = [NSMutableSet set];
	for (NSString *name in [[resources allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if (!WFIsDmnResource(name)) {
			continue;
		}
		NSError *parseError = nil;
		NSArray *decisions = [WFDmnReader decisionsFromData:[resources objectForKey:name] error:&parseError];
		if (decisions == nil) {
			if (error != NULL) {
				*error = WFRepositoryError(WFErrorInvalidDmn,
					[NSString stringWithFormat:@"%@: %@", name, [parseError localizedDescription]]);
			}
			return nil;
		}
		for (WFDecisionDefinition *decision in decisions) {
			if ([keys containsObject:decision.key]) {
				if (error != NULL) {
					*error = WFRepositoryError(WFErrorInvalidDefinition, [NSString stringWithFormat:
						@"decision %@ is defined twice in one deployment", decision.key]);
				}
				return nil;
			}
			[keys addObject:decision.key];
			[parsed addObject:@[ decision, name ]];
		}
	}
	return parsed;
}

- (WFDecisionDefinition *)stampDecision:(WFDecisionDefinition *)parsed with:(WFDecisionRecord *)record
{
	WFDecisionDefinition *decision = [parsed wf_deployedCopyWithVersion:record.version
	                                                        definitionId:record.definitionId
	                                                        deploymentId:record.deploymentId
	                                                        resourceName:record.resourceName];
	@synchronized (_decisions) {
		[_decisions setObject:decision forKey:decision.definitionId];
	}
	return decision;
}

- (WFDecisionDefinition *)decisionForRecord:(WFDecisionRecord *)record error:(NSError **)error
{
	@synchronized (_decisions) {
		WFDecisionDefinition *cached = [_decisions objectForKey:record.definitionId];
		if (cached != nil) {
			return cached;
		}
	}
	WFDeploymentRecord *deployment = [_store deploymentWithId:record.deploymentId];
	NSData *bytes = [deployment.resources objectForKey:record.resourceName];
	NSArray *parsed = bytes != nil ? [WFDmnReader decisionsFromData:bytes error:error] : nil;
	for (WFDecisionDefinition *candidate in parsed) {
		if ([candidate.key isEqualToString:record.key]) {
			return [self stampDecision:candidate with:record];
		}
	}
	if ((bytes == nil || parsed != nil) && error != NULL) {
		*error = WFRepositoryError(WFErrorInvalidDefinition, [NSString stringWithFormat:
			@"resource %@ of deployment %@ no longer defines decision %@",
			record.resourceName, record.deploymentId, record.key]);
	}
	return nil;
}

- (WFDecisionDefinition *)latestDecisionForKey:(NSString *)key error:(NSError **)error
{
	return [self decisionForKey:key version:0 error:error];
}

- (WFDecisionDefinition *)decisionForKey:(NSString *)key
                                 version:(NSInteger)version
                                   error:(NSError **)error
{
	WFDecisionRecord *record = [_store decisionRecordForKey:key version:version];
	if (record == nil) {
		if (error != NULL) {
			*error = WFRepositoryError(WFErrorInvalidDefinition, version > 0
				? [NSString stringWithFormat:@"decision %@ version %ld is not deployed", key, (long)version]
				: [NSString stringWithFormat:@"decision %@ is not deployed", key]);
		}
		return nil;
	}
	return [self decisionForRecord:record error:error];
}

- (WFDecisionDefinition *)decisionWithId:(NSString *)definitionId error:(NSError **)error
{
	@synchronized (_decisions) {
		WFDecisionDefinition *cached = [_decisions objectForKey:definitionId];
		if (cached != nil) {
			return cached;
		}
	}
	WFDecisionRecord *record = [_store decisionRecordWithId:definitionId];
	if (record == nil) {
		if (error != NULL) {
			*error = WFRepositoryError(WFErrorInvalidDefinition,
				[NSString stringWithFormat:@"no decision %@", definitionId]);
		}
		return nil;
	}
	return [self decisionForRecord:record error:error];
}

- (WFDecisionDefinition *)decisionForKey:(NSString *)key
                             inDeployment:(NSString *)deploymentId
                                    error:(NSError **)error
{
	for (WFDecisionRecord *record in [_store decisionRecordsInDeployment:deploymentId]) {
		if ([record.key isEqualToString:key]) {
			return [self decisionForRecord:record error:error];
		}
	}
	if (error != NULL) {
		*error = WFRepositoryError(WFErrorInvalidDefinition, [NSString stringWithFormat:
			@"decision %@ is not in deployment %@", key, deploymentId]);
	}
	return nil;
}

- (WFProcessDefinition *)cached:(NSString *)definitionId
{
	@synchronized (_cache) {
		return [_cache objectForKey:definitionId];
	}
}

- (void)cache:(WFProcessDefinition *)definition
{
	@synchronized (_cache) {
		[_cache setObject:definition forKey:definition.definitionId];
	}
}

- (WFProcessDefinition *)stamp:(WFProcessDefinition *)parsed
                          with:(WFDefinitionRecord *)record
{
	WFProcessDefinition *definition =
		[parsed wf_deployedCopyWithVersion:record.version
		                      definitionId:record.definitionId
		                      deploymentId:record.deploymentId
		                      resourceName:record.resourceName];
	[self cache:definition];
	return definition;
}

- (WFProcessDefinition *)definitionForRecord:(WFDefinitionRecord *)record
                                       error:(NSError **)error
{
	WFProcessDefinition *definition = [self cached:record.definitionId];
	if (definition != nil) {
		return definition;
	}
	WFDeploymentRecord *deployment = [_store deploymentWithId:record.deploymentId];
	NSData *bytes = [deployment.resources objectForKey:record.resourceName];
	if (bytes == nil) {
		if (error != NULL) {
			*error = WFRepositoryError(WFErrorInvalidDefinition,
				[NSString stringWithFormat:@"resource %@ of deployment %@ is missing",
					record.resourceName, record.deploymentId]);
		}
		return nil;
	}
	NSArray *parsed = [WFBpmnReader definitionsFromData:bytes error:error];
	for (WFProcessDefinition *candidate in parsed) {
		if ([candidate.processId isEqualToString:record.key]) {
			return [self stamp:candidate with:record];
		}
	}
	if (parsed != nil && error != NULL) {
		*error = WFRepositoryError(WFErrorInvalidDefinition,
			[NSString stringWithFormat:@"%@ no longer defines process %@",
				record.resourceName, record.key]);
	}
	return nil;
}

- (WFDeployment *)deploymentFromRecord:(WFDeploymentRecord *)record
                                 error:(NSError **)error
{
	NSMutableArray *definitions = [NSMutableArray array];
	for (WFDefinitionRecord *definitionRecord in
	     [_store definitionRecordsInDeployment:record.deploymentId]) {
		WFProcessDefinition *definition = [self definitionForRecord:definitionRecord
		                                                      error:error];
		if (definition == nil) {
			return nil;
		}
		[definitions addObject:definition];
	}
	NSMutableArray *decisions = [NSMutableArray array];
	for (WFDecisionRecord *decisionRecord in [_store decisionRecordsInDeployment:record.deploymentId]) {
		WFDecisionDefinition *decision = [self decisionForRecord:decisionRecord error:error];
		if (decision == nil) {
			return nil;
		}
		[decisions addObject:decision];
	}
	WFDeployment *deployment = [[WFDeployment alloc] init];
	deployment.deploymentId = record.deploymentId;
	deployment.name = record.name;
	deployment.deployedAt = record.deployedAt;
	deployment.definitions = definitions;
	deployment.decisions = decisions;
	return deployment;
}

- (WFDeployment *)deployResources:(NSDictionary<NSString *, NSData *> *)resources
                             name:(NSString *)name
                 filterDuplicates:(BOOL)filterDuplicates
                            error:(NSError **)error
{
	if ([resources count] == 0 || [name length] == 0) {
		if (error != NULL) {
			*error = WFRepositoryError(WFErrorInvalidDefinition,
				@"a deployment needs a name and at least one resource");
		}
		return nil;
	}
	if (filterDuplicates) {
		WFDeploymentRecord *previous = [_store latestDeploymentNamed:name];
		if (previous != nil && [previous.resources isEqualToDictionary:resources]) {
			return [self deploymentFromRecord:previous error:error];
		}
	}
	/* Everything is parsed before anything is stored: a deployment with a
	 * broken resource stores nothing. */
	NSArray *parsed = [self parseResources:resources error:error];
	if (parsed == nil) {
		return nil;
	}
	NSArray *parsedDecisions = [self parseDecisions:resources error:error];
	if (parsedDecisions == nil) {
		return nil;
	}
	NSMutableArray *decisionRecords = [NSMutableArray array];
	for (NSArray *pair in parsedDecisions) {
		WFDecisionDefinition *decision = [pair objectAtIndex:0];
		WFDecisionRecord *record = [[WFDecisionRecord alloc] init];
		record.key = decision.key;
		record.name = decision.name;
		record.versionTag = decision.versionTag;
		record.resourceName = [pair objectAtIndex:1];
		[decisionRecords addObject:record];
	}
	WFDeploymentRecord *deploymentRecord = [[WFDeploymentRecord alloc] init];
	deploymentRecord.deploymentId = [[NSUUID UUID] UUIDString];
	deploymentRecord.name = name;
	deploymentRecord.deployedAt = [NSDate date];
	deploymentRecord.resources = resources;
	NSMutableArray *records = [NSMutableArray array];
	for (NSArray *pair in parsed) {
		WFProcessDefinition *definition = [pair objectAtIndex:0];
		WFDefinitionRecord *record = [[WFDefinitionRecord alloc] init];
		record.key = definition.processId;
		record.name = definition.name;
		record.resourceName = [pair objectAtIndex:1];
		record.historyTimeToLive = definition.historyTimeToLive;
		record.forms = WFFormsOf(definition);
		record.startEventId = [[definition startEvent] elementId];
		WFEvent *start = [definition startEvent];
		if (start.trigger == WFEventTriggerMessage) {
			record.messageStartName = start.messageName;
		} else if (start.trigger == WFEventTriggerSignal) {
			record.signalStartName = start.signalName;
		} else if (start.trigger == WFEventTriggerConditional) {
			record.conditionalStart = YES;
		} else if (start.trigger == WFEventTriggerTimer) {
			NSInteger attempts = WF_DEFAULT_ATTEMPTS;
			NSArray *delays = nil;
			WFParseRetryCycle(start.retryTimeCycle, &attempts, &delays);
			/* Evaluated at deployment, where there are no variables. */
			NSDate *due = nil;
			NSString *repeat = nil;
			NSError *timerError = nil;
			if (!WFTimerSchedule(start.timer, @{}, [NSDate date], &due, &repeat, &timerError)) {
				if (error != NULL) {
					*error = WFRepositoryError(WFErrorInvalidDefinition, [NSString stringWithFormat:
						@"%@: %@", start.elementId, [timerError localizedDescription]]);
				}
				return nil;
			}
			record.timerStartActivityId = start.elementId;
			record.timerStartDue = due;
			record.timerStartRepeat = repeat;
			record.timerStartAttempts = attempts;
		}
		[records addObject:record];
	}
	NSArray *stored = [_store insertDeployment:deploymentRecord
	                               definitions:records
	                                 decisions:decisionRecords
	                                     error:error];
	if (stored == nil) {
		return nil;
	}
	if (_didStoreDeployment != nil) {
		_didStoreDeployment();
	}
	NSMutableArray *definitions = [NSMutableArray array];
	for (NSUInteger i = 0; i < [stored count]; i++) {
		[definitions addObject:[self stamp:[[parsed objectAtIndex:i] objectAtIndex:0]
		                              with:[stored objectAtIndex:i]]];
	}
	NSMutableArray *decisions = [NSMutableArray array];
	for (NSUInteger i = 0; i < [decisionRecords count]; i++) {
		[decisions addObject:[self stampDecision:[[parsedDecisions objectAtIndex:i] objectAtIndex:0]
		                                    with:[decisionRecords objectAtIndex:i]]];
	}
	WFDeployment *deployment = [[WFDeployment alloc] init];
	deployment.deploymentId = deploymentRecord.deploymentId;
	deployment.name = name;
	deployment.deployedAt = deploymentRecord.deployedAt;
	deployment.definitions = definitions;
	deployment.decisions = decisions;
	return deployment;
}

- (WFDeployment *)deployDefinition:(WFProcessDefinition *)definition
                             error:(NSError **)error
{
	NSString *xml = [WFBpmnWriter XMLStringFromDefinition:definition error:error];
	if (xml == nil) {
		return nil;
	}
	NSString *resource = [definition.processId stringByAppendingString:@".bpmn"];
	return [self deployResources:@{ resource: [xml dataUsingEncoding:NSUTF8StringEncoding] }
	                        name:definition.processId
	            filterDuplicates:YES
	                       error:error];
}

- (WFDeployment *)deploymentWithId:(NSString *)deploymentId error:(NSError **)error
{
	WFDeploymentRecord *record = [_store deploymentWithId:deploymentId];
	if (record == nil) {
		if (error != NULL) {
			*error = WFRepositoryError(WFErrorUnknownElement,
				[NSString stringWithFormat:@"no deployment %@", deploymentId]);
		}
		return nil;
	}
	return [self deploymentFromRecord:record error:error];
}

- (WFProcessDefinition *)latestDefinitionForKey:(NSString *)key error:(NSError **)error
{
	return [self definitionForKey:key version:0 error:error];
}

- (WFProcessDefinition *)definitionForKey:(NSString *)key
                                  version:(NSInteger)version
                                    error:(NSError **)error
{
	WFDefinitionRecord *record = [_store definitionRecordForKey:key version:version];
	if (record == nil) {
		if (error != NULL) {
			*error = WFRepositoryError(WFErrorInvalidDefinition, version > 0
				? [NSString stringWithFormat:@"%@ version %ld is not deployed",
					key, (long)version]
				: [NSString stringWithFormat:@"%@ is not deployed", key]);
		}
		return nil;
	}
	return [self definitionForRecord:record error:error];
}

- (WFProcessDefinition *)definitionWithId:(NSString *)definitionId error:(NSError **)error
{
	WFProcessDefinition *definition = [self cached:definitionId];
	if (definition != nil) {
		return definition;
	}
	WFDefinitionRecord *record = [_store definitionRecordWithId:definitionId];
	if (record == nil) {
		if (error != NULL) {
			*error = WFRepositoryError(WFErrorInvalidDefinition,
				[NSString stringWithFormat:@"no definition %@", definitionId]);
		}
		return nil;
	}
	return [self definitionForRecord:record error:error];
}

@end

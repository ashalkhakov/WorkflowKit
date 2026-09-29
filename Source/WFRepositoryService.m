#import "WFRepositoryService.h"
#import "WFProcessDefinition+Repository.h"
#import "WFStore.h"
#import "WFBpmn.h"
#import "WFFlowElements.h"
#import "WFDuration.h"
#import "WFTimers.h"
#import "WFProcessEngine+Internal.h"

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

@interface WFDeployment ()
@property (nonatomic, readwrite, copy) NSString *deploymentId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSDate *deployedAt;
@property (nonatomic, readwrite, copy) NSArray<WFProcessDefinition *> *definitions;
@end

@implementation WFDeployment
@end

@implementation WFRepositoryService
{
	WFStore *_store;
	/* Definition id to its definition. Definitions are immutable, so a
	 * cached one never goes stale. */
	NSMutableDictionary<NSString *, WFProcessDefinition *> *_cache;
	void (^_didStoreDeployment)(void);
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
	WFDeployment *deployment = [[WFDeployment alloc] init];
	deployment.deploymentId = record.deploymentId;
	deployment.name = record.name;
	deployment.deployedAt = record.deployedAt;
	deployment.definitions = definitions;
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
		WFEvent *start = [definition startEvent];
		if (start.trigger == WFEventTriggerMessage) {
			record.messageStartName = start.messageName;
		} else if (start.trigger == WFEventTriggerSignal) {
			record.signalStartName = start.signalName;
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
	WFDeployment *deployment = [[WFDeployment alloc] init];
	deployment.deploymentId = deploymentRecord.deploymentId;
	deployment.name = name;
	deployment.deployedAt = deploymentRecord.deployedAt;
	deployment.definitions = definitions;
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

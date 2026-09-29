#import "UDRepositoryService.h"
#import "UDProcessDefinition+Repository.h"
#import "UDStore.h"
#import "UDBpmn.h"
#import "UDFlowElements.h"
#import "UDDuration.h"
#import "UDProcessEngine+Internal.h"

static NSError *
UDRepositoryError(UDWorkflowErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:UDWorkflowErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static BOOL
UDIsBpmnResource(NSString *name)
{
	return [name hasSuffix:@".bpmn"] || [name hasSuffix:@".bpmn20.xml"];
}

@interface UDDeployment ()
@property (nonatomic, readwrite, copy) NSString *deploymentId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSDate *deployedAt;
@property (nonatomic, readwrite, copy) NSArray<UDProcessDefinition *> *definitions;
@end

@implementation UDDeployment
@end

@implementation UDRepositoryService
{
	UDStore *_store;
	/* Definition id to its definition. Definitions are immutable, so a
	 * cached one never goes stale. */
	NSMutableDictionary<NSString *, UDProcessDefinition *> *_cache;
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

- (instancetype)initWithStore:(UDStore *)store
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
		if (!UDIsBpmnResource(name)) {
			continue;
		}
		NSError *parseError = nil;
		NSArray *definitions = [UDBpmnReader definitionsFromData:[resources objectForKey:name]
		                                                   error:&parseError];
		if (definitions == nil) {
			if (error != NULL) {
				*error = UDRepositoryError(UDWorkflowErrorInvalidBpmn,
					[NSString stringWithFormat:@"%@: %@", name,
						[parseError localizedDescription]]);
			}
			return nil;
		}
		for (UDProcessDefinition *definition in definitions) {
			if ([keys containsObject:definition.processId]) {
				if (error != NULL) {
					*error = UDRepositoryError(UDWorkflowErrorInvalidDefinition,
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

- (UDProcessDefinition *)cached:(NSString *)definitionId
{
	@synchronized (_cache) {
		return [_cache objectForKey:definitionId];
	}
}

- (void)cache:(UDProcessDefinition *)definition
{
	@synchronized (_cache) {
		[_cache setObject:definition forKey:definition.definitionId];
	}
}

- (UDProcessDefinition *)stamp:(UDProcessDefinition *)parsed
                          with:(UDDefinitionRecord *)record
{
	UDProcessDefinition *definition =
		[parsed ud_deployedCopyWithVersion:record.version
		                      definitionId:record.definitionId
		                      deploymentId:record.deploymentId
		                      resourceName:record.resourceName];
	[self cache:definition];
	return definition;
}

- (UDProcessDefinition *)definitionForRecord:(UDDefinitionRecord *)record
                                       error:(NSError **)error
{
	UDProcessDefinition *definition = [self cached:record.definitionId];
	if (definition != nil) {
		return definition;
	}
	UDDeploymentRecord *deployment = [_store deploymentWithId:record.deploymentId];
	NSData *bytes = [deployment.resources objectForKey:record.resourceName];
	if (bytes == nil) {
		if (error != NULL) {
			*error = UDRepositoryError(UDWorkflowErrorInvalidDefinition,
				[NSString stringWithFormat:@"resource %@ of deployment %@ is missing",
					record.resourceName, record.deploymentId]);
		}
		return nil;
	}
	NSArray *parsed = [UDBpmnReader definitionsFromData:bytes error:error];
	for (UDProcessDefinition *candidate in parsed) {
		if ([candidate.processId isEqualToString:record.key]) {
			return [self stamp:candidate with:record];
		}
	}
	if (parsed != nil && error != NULL) {
		*error = UDRepositoryError(UDWorkflowErrorInvalidDefinition,
			[NSString stringWithFormat:@"%@ no longer defines process %@",
				record.resourceName, record.key]);
	}
	return nil;
}

- (UDDeployment *)deploymentFromRecord:(UDDeploymentRecord *)record
                                 error:(NSError **)error
{
	NSMutableArray *definitions = [NSMutableArray array];
	for (UDDefinitionRecord *definitionRecord in
	     [_store definitionRecordsInDeployment:record.deploymentId]) {
		UDProcessDefinition *definition = [self definitionForRecord:definitionRecord
		                                                      error:error];
		if (definition == nil) {
			return nil;
		}
		[definitions addObject:definition];
	}
	UDDeployment *deployment = [[UDDeployment alloc] init];
	deployment.deploymentId = record.deploymentId;
	deployment.name = record.name;
	deployment.deployedAt = record.deployedAt;
	deployment.definitions = definitions;
	return deployment;
}

- (UDDeployment *)deployResources:(NSDictionary<NSString *, NSData *> *)resources
                             name:(NSString *)name
                 filterDuplicates:(BOOL)filterDuplicates
                            error:(NSError **)error
{
	if ([resources count] == 0 || [name length] == 0) {
		if (error != NULL) {
			*error = UDRepositoryError(UDWorkflowErrorInvalidDefinition,
				@"a deployment needs a name and at least one resource");
		}
		return nil;
	}
	if (filterDuplicates) {
		UDDeploymentRecord *previous = [_store latestDeploymentNamed:name];
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
	UDDeploymentRecord *deploymentRecord = [[UDDeploymentRecord alloc] init];
	deploymentRecord.deploymentId = [[NSUUID UUID] UUIDString];
	deploymentRecord.name = name;
	deploymentRecord.deployedAt = [NSDate date];
	deploymentRecord.resources = resources;
	NSMutableArray *records = [NSMutableArray array];
	for (NSArray *pair in parsed) {
		UDProcessDefinition *definition = [pair objectAtIndex:0];
		UDDefinitionRecord *record = [[UDDefinitionRecord alloc] init];
		record.key = definition.processId;
		record.name = definition.name;
		record.resourceName = [pair objectAtIndex:1];
		record.historyTimeToLive = definition.historyTimeToLive;
		UDEvent *start = [definition startEvent];
		if (start.trigger == UDEventTriggerMessage) {
			record.messageStartName = start.messageName;
		} else if (start.trigger == UDEventTriggerTimer) {
			NSInteger attempts = UD_DEFAULT_ATTEMPTS;
			NSArray *delays = nil;
			UDParseRetryCycle(start.retryTimeCycle, &attempts, &delays);
			record.timerStartActivityId = start.elementId;
			record.timerStartDelay = start.timerDuration;
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
	UDDeployment *deployment = [[UDDeployment alloc] init];
	deployment.deploymentId = deploymentRecord.deploymentId;
	deployment.name = name;
	deployment.deployedAt = deploymentRecord.deployedAt;
	deployment.definitions = definitions;
	return deployment;
}

- (UDDeployment *)deployDefinition:(UDProcessDefinition *)definition
                             error:(NSError **)error
{
	NSString *xml = [UDBpmnWriter XMLStringFromDefinition:definition error:error];
	if (xml == nil) {
		return nil;
	}
	NSString *resource = [definition.processId stringByAppendingString:@".bpmn"];
	return [self deployResources:@{ resource: [xml dataUsingEncoding:NSUTF8StringEncoding] }
	                        name:definition.processId
	            filterDuplicates:YES
	                       error:error];
}

- (UDDeployment *)deploymentWithId:(NSString *)deploymentId error:(NSError **)error
{
	UDDeploymentRecord *record = [_store deploymentWithId:deploymentId];
	if (record == nil) {
		if (error != NULL) {
			*error = UDRepositoryError(UDWorkflowErrorUnknownElement,
				[NSString stringWithFormat:@"no deployment %@", deploymentId]);
		}
		return nil;
	}
	return [self deploymentFromRecord:record error:error];
}

- (UDProcessDefinition *)latestDefinitionForKey:(NSString *)key error:(NSError **)error
{
	return [self definitionForKey:key version:0 error:error];
}

- (UDProcessDefinition *)definitionForKey:(NSString *)key
                                  version:(NSInteger)version
                                    error:(NSError **)error
{
	UDDefinitionRecord *record = [_store definitionRecordForKey:key version:version];
	if (record == nil) {
		if (error != NULL) {
			*error = UDRepositoryError(UDWorkflowErrorInvalidDefinition, version > 0
				? [NSString stringWithFormat:@"%@ version %ld is not deployed",
					key, (long)version]
				: [NSString stringWithFormat:@"%@ is not deployed", key]);
		}
		return nil;
	}
	return [self definitionForRecord:record error:error];
}

- (UDProcessDefinition *)definitionWithId:(NSString *)definitionId error:(NSError **)error
{
	UDProcessDefinition *definition = [self cached:definitionId];
	if (definition != nil) {
		return definition;
	}
	UDDefinitionRecord *record = [_store definitionRecordWithId:definitionId];
	if (record == nil) {
		if (error != NULL) {
			*error = UDRepositoryError(UDWorkflowErrorInvalidDefinition,
				[NSString stringWithFormat:@"no definition %@", definitionId]);
		}
		return nil;
	}
	return [self definitionForRecord:record error:error];
}

@end

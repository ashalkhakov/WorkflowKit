#import "UDProcessEngine+Internal.h"
#import "UDCommandContext.h"
#import "UDEntities.h"
#import "UDFlowElements.h"
#import "UDProcessDefinition.h"

NSString * const UDProcessInstanceStateActive = @"ACTIVE";
NSString * const UDProcessInstanceStateCompleted = @"COMPLETED";

static NSError *
UDServiceError(UDWorkflowErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:UDWorkflowErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

#pragma mark - Values

@interface UDProcessInstance ()
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *businessKey;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *definitionKey;
@property (nonatomic, readwrite, getter=isEnded) BOOL ended;
@end

@implementation UDProcessInstance

+ (instancetype)ud_instanceWithExecution:(UDExecutionEntity *)root
                              definition:(UDProcessDefinition *)definition
                                   ended:(BOOL)ended
{
	UDProcessInstance *instance = [[UDProcessInstance alloc] init];
	instance.processInstanceId = root.processInstanceId;
	instance.businessKey = root.businessKey;
	instance.definitionId = root.definitionId;
	instance.definitionKey = definition.processId;
	instance.ended = ended;
	return instance;
}

+ (instancetype)ud_instanceWithHistory:(UDHistoricProcessInstanceEntity *)history
{
	UDProcessInstance *instance = [[UDProcessInstance alloc] init];
	instance.processInstanceId = history.processInstanceId;
	instance.businessKey = history.businessKey;
	instance.definitionId = history.definitionId;
	instance.definitionKey = history.definitionKey;
	instance.ended = history.endTime != nil;
	return instance;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<UDProcessInstance %@ %@%@>",
		self.processInstanceId, self.definitionKey, self.ended ? @" ended" : @""];
}

@end

@interface UDWorkItem ()
@property (nonatomic, readwrite, copy) NSString *taskId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *taskDefinitionKey;
@property (nonatomic, readwrite, copy) NSString *assignee;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSDate *createdAt;
@property (nonatomic, readwrite, copy) NSDate *dueDate;
@property (nonatomic, readwrite) NSInteger priority;
@end

@implementation UDWorkItem

+ (instancetype)ud_workItemWithEntity:(UDTaskEntity *)entity
{
	UDWorkItem *task = [[UDWorkItem alloc] init];
	task.taskId = entity.taskId;
	task.name = entity.name;
	task.taskDefinitionKey = entity.taskDefinitionKey;
	task.assignee = entity.assignee;
	task.processInstanceId = entity.processInstanceId;
	task.definitionId = entity.definitionId;
	task.createdAt = entity.createdAt;
	task.dueDate = entity.dueDate;
	task.priority = entity.priority;
	return task;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<UDWorkItem %@ %@>", self.taskDefinitionKey, self.taskId];
}

@end

@interface UDHistoricProcessInstance ()
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *businessKey;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *definitionKey;
@property (nonatomic, readwrite, copy) NSDate *startTime;
@property (nonatomic, readwrite, copy) NSDate *endTime;
@property (nonatomic, readwrite, copy) NSString *state;
@end

@implementation UDHistoricProcessInstance

+ (instancetype)ud_instanceWithEntity:(UDHistoricProcessInstanceEntity *)entity
{
	UDHistoricProcessInstance *instance = [[UDHistoricProcessInstance alloc] init];
	instance.processInstanceId = entity.processInstanceId;
	instance.businessKey = entity.businessKey;
	instance.definitionId = entity.definitionId;
	instance.definitionKey = entity.definitionKey;
	instance.startTime = entity.startTime;
	instance.endTime = entity.endTime;
	instance.state = entity.state;
	return instance;
}

@end

#pragma mark - Runtime service

@implementation UDRuntimeService
{
	__weak UDProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
	}
	return self;
}

- (UDExecutionEntity *)root:(NSString *)processInstanceId in:(UDCommandContext *)command
{
	return [[command fetch:@"UDExecution"
	             predicate:[NSPredicate predicateWithFormat:
	                 @"executionId == %@ AND parent == nil", processInstanceId]
	                  sort:nil
	                 limit:1] lastObject];
}

- (NSError *)notRunning:(NSString *)processInstanceId
{
	return UDServiceError(UDWorkflowErrorUnknownElement,
		[NSString stringWithFormat:@"no running process instance %@", processInstanceId]);
}

- (UDProcessInstance *)startProcessInstanceByKey:(NSString *)key
                                       variables:(NSDictionary *)variables
                                           error:(NSError **)error
{
	return [self startProcessInstanceByKey:key businessKey:nil variables:variables error:error];
}

- (UDProcessInstance *)startProcessInstanceByKey:(NSString *)key
                                     businessKey:(NSString *)businessKey
                                       variables:(NSDictionary *)variables
                                           error:(NSError **)error
{
	UDProcessEngine *engine = _engine;
	UDProcessDefinition *definition =
		[engine.repositoryService latestDefinitionForKey:key error:error];
	if (definition == nil
	    || ![UDCommandContext areStorableVariables:variables error:error]) {
		return nil;
	}
	__block NSString *processInstanceId = nil;
	BOOL ok = [engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		UDExecutionEntity *root = [command startProcessInstance:definition
		                                            businessKey:businessKey
		                                              variables:variables
		                                             startEvent:nil];
		processInstanceId = root.processInstanceId;
		return root != nil;
	} error:error];
	if (!ok) {
		return nil;
	}
	UDProcessInstance *running = [self processInstanceWithId:processInstanceId error:NULL];
	if (running != nil) {
		return running;
	}
	/* It ran to its end within the start command. */
	return [self endedInstance:processInstanceId];
}

- (UDProcessInstance *)endedInstance:(NSString *)processInstanceId
{
	__block UDProcessInstance *instance = nil;
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		UDHistoricProcessInstanceEntity *history =
			[[command fetch:@"UDHistoricProcessInstance"
			      predicate:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
			          processInstanceId]
			           sort:nil
			          limit:1] lastObject];
		if (history != nil) {
			instance = [UDProcessInstance ud_instanceWithHistory:history];
		}
		return YES;
	} error:NULL];
	return instance;
}

- (UDProcessInstance *)processInstanceWithId:(NSString *)processInstanceId
                                       error:(NSError **)error
{
	__block UDProcessInstance *instance = nil;
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		UDExecutionEntity *root = [self root:processInstanceId in:command];
		if (root != nil) {
			instance = [UDProcessInstance ud_instanceWithExecution:root
				definition:[command definitionForExecution:root]
				ended:NO];
		}
		return YES;
	} error:NULL];
	if (instance == nil && error != NULL) {
		*error = [self notRunning:processInstanceId];
	}
	return instance;
}

- (NSArray<NSString *> *)activeActivityIdsForProcessInstance:(NSString *)processInstanceId
                                                       error:(NSError **)error
{
	__block NSArray *ids = nil;
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		NSArray *executions = [command fetch:@"UDExecution"
		                           predicate:[NSPredicate predicateWithFormat:
		                               @"processInstanceId == %@", processInstanceId]
		                                sort:nil
		                               limit:0];
		if ([executions count] > 0) {
			NSMutableSet *active = [NSMutableSet set];
			for (UDExecutionEntity *execution in executions) {
				if (execution.isActive && execution.activityId != nil) {
					[active addObject:execution.activityId];
				}
			}
			ids = [[active allObjects] sortedArrayUsingSelector:@selector(compare:)];
		}
		return YES;
	} error:NULL];
	if (ids == nil && error != NULL) {
		*error = [self notRunning:processInstanceId];
	}
	return ids;
}

- (NSDictionary *)variablesForProcessInstance:(NSString *)processInstanceId
                                        error:(NSError **)error
{
	__block NSMutableDictionary *variables = nil;
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		UDExecutionEntity *root = [self root:processInstanceId in:command];
		if (root != nil) {
			variables = [NSMutableDictionary dictionary];
			for (UDVariableEntity *variable in root.variables) {
				[variables setObject:[variable ud_value] ?: [NSNull null] forKey:variable.name];
			}
		}
		return YES;
	} error:NULL];
	if (variables == nil && error != NULL) {
		*error = [self notRunning:processInstanceId];
	}
	return variables;
}

- (BOOL)setVariables:(NSDictionary *)variables
   processInstanceId:(NSString *)processInstanceId
               error:(NSError **)error
{
	if (![UDCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDExecutionEntity *root = [self root:processInstanceId in:command];
		if (root == nil) {
			if (commandError != NULL) {
				*commandError = [self notRunning:processInstanceId];
			}
			return NO;
		}
		return [command setVariables:variables from:root];
	} error:error];
}

/* Recipients of a message: waiting subscriptions, and start subscriptions
 * unless the caller named a running instance by id or variables. */
- (NSArray *)recipientsOf:(NSString *)messageName
              businessKey:(NSString *)businessKey
          correlationKeys:(NSDictionary *)correlationKeys
        processInstanceId:(NSString *)processInstanceId
                  command:(UDCommandContext *)command
{
	NSMutableArray *recipients = [NSMutableArray array];
	NSArray *subscriptions = [command fetch:@"UDEventSubscription"
	                              predicate:[NSPredicate predicateWithFormat:
	                                  @"eventType == %@ AND eventName == %@",
	                                  UDEventTypeMessage, messageName]
	                                   sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
	                                                                           ascending:YES] ]
	                                  limit:0];
	for (UDEventSubscriptionEntity *subscription in subscriptions) {
		if (subscription.execution == nil) {
			if (processInstanceId == nil && [correlationKeys count] == 0) {
				[recipients addObject:subscription];
			}
			continue;
		}
		UDExecutionEntity *root = [subscription.execution processInstance];
		if (processInstanceId != nil
		    && ![root.processInstanceId isEqualToString:processInstanceId]) {
			continue;
		}
		if (businessKey != nil && ![root.businessKey isEqualToString:businessKey]) {
			continue;
		}
		BOOL matches = YES;
		for (NSString *key in correlationKeys) {
			id value = [[root localVariableNamed:key] ud_value];
			if (value == nil || ![value isEqual:[correlationKeys objectForKey:key]]) {
				matches = NO;
				break;
			}
		}
		if (matches) {
			[recipients addObject:subscription];
		}
	}
	return recipients;
}

- (NSArray<NSString *> *)correlate:(NSString *)messageName
                       businessKey:(NSString *)businessKey
                   correlationKeys:(NSDictionary *)correlationKeys
                 processInstanceId:(NSString *)processInstanceId
                         variables:(NSDictionary *)variables
                        exactlyOne:(BOOL)exactlyOne
                             error:(NSError **)error
{
	if (![UDCommandContext areStorableVariables:variables error:error]) {
		return nil;
	}
	UDProcessEngine *engine = _engine;
	NSMutableArray *reached = [NSMutableArray array];
	BOOL ok = [engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		NSArray *recipients = [self recipientsOf:messageName
		                             businessKey:businessKey
		                         correlationKeys:correlationKeys
		                       processInstanceId:processInstanceId
		                                 command:command];
		if ([recipients count] == 0 || (exactlyOne && [recipients count] > 1)) {
			if (commandError != NULL) {
				*commandError = UDServiceError(UDWorkflowErrorNoPath,
					[NSString stringWithFormat:@"message %@ matched %lu recipients",
						messageName, (unsigned long)[recipients count]]);
			}
			return NO;
		}
		for (UDEventSubscriptionEntity *subscription in recipients) {
			if (subscription.execution != nil) {
				[reached addObject:subscription.processInstanceId];
				[command deliverSubscription:subscription variables:variables];
				continue;
			}
			UDProcessDefinition *definition =
				[engine.repositoryService definitionWithId:subscription.definitionId
				                                     error:commandError];
			if (definition == nil) {
				return NO;
			}
			UDExecutionEntity *root = [command startProcessInstance:definition
			                                            businessKey:businessKey
			                                              variables:variables
			                                             startEvent:[definition startEvent]];
			if (root == nil) {
				return NO;
			}
			[reached addObject:root.processInstanceId];
		}
		return YES;
	} error:error];
	return ok ? reached : nil;
}

- (BOOL)correlateMessage:(NSString *)messageName
             businessKey:(NSString *)businessKey
         correlationKeys:(NSDictionary *)correlationKeys
               variables:(NSDictionary *)variables
                   error:(NSError **)error
{
	return [self correlate:messageName
	           businessKey:businessKey
	       correlationKeys:correlationKeys
	     processInstanceId:nil
	             variables:variables
	            exactlyOne:YES
	                 error:error] != nil;
}

- (NSArray<NSString *> *)correlateMessageToAll:(NSString *)messageName
                                   businessKey:(NSString *)businessKey
                               correlationKeys:(NSDictionary *)correlationKeys
                                     variables:(NSDictionary *)variables
                                         error:(NSError **)error
{
	return [self correlate:messageName
	           businessKey:businessKey
	       correlationKeys:correlationKeys
	     processInstanceId:nil
	             variables:variables
	            exactlyOne:NO
	                 error:error];
}

- (BOOL)correlateMessage:(NSString *)messageName
       processInstanceId:(NSString *)processInstanceId
               variables:(NSDictionary *)variables
                   error:(NSError **)error
{
	return [self correlate:messageName
	           businessKey:nil
	       correlationKeys:nil
	     processInstanceId:processInstanceId
	             variables:variables
	            exactlyOne:YES
	                 error:error] != nil;
}

@end

#pragma mark - Task service

@implementation UDTaskService
{
	__weak UDProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
	}
	return self;
}

- (NSArray<UDWorkItem *> *)tasksMatching:(NSPredicate *)predicate
{
	NSMutableArray *tasks = [NSMutableArray array];
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		for (UDTaskEntity *entity in [command fetch:@"UDTask"
		                                  predicate:predicate
		                                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
		                                                                               ascending:YES] ]
		                                      limit:0]) {
			[tasks addObject:[UDWorkItem ud_workItemWithEntity:entity]];
		}
		return YES;
	} error:NULL];
	return tasks;
}

- (UDWorkItem *)taskWithId:(NSString *)taskId error:(NSError **)error
{
	UDWorkItem *task = [[self tasksMatching:[NSPredicate predicateWithFormat:@"taskId == %@", taskId]]
		lastObject];
	if (task == nil && error != NULL) {
		*error = UDServiceError(UDWorkflowErrorUnknownElement,
			[NSString stringWithFormat:@"no open task %@", taskId]);
	}
	return task;
}

- (NSArray<UDWorkItem *> *)tasksForProcessInstance:(NSString *)processInstanceId
{
	return [self tasksMatching:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
		processInstanceId]];
}

- (NSArray<UDWorkItem *> *)tasksForAssignee:(NSString *)assignee
{
	return [self tasksMatching:[NSPredicate predicateWithFormat:@"assignee == %@", assignee]];
}

- (BOOL)completeTask:(NSString *)taskId
           variables:(NSDictionary *)variables
               error:(NSError **)error
{
	if (![UDCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDTaskEntity *task = [[command fetch:@"UDTask"
		                           predicate:[NSPredicate predicateWithFormat:@"taskId == %@", taskId]
		                                sort:nil
		                               limit:1] lastObject];
		if (task == nil) {
			if (commandError != NULL) {
				*commandError = UDServiceError(UDWorkflowErrorUnknownElement,
					[NSString stringWithFormat:@"no open task %@", taskId]);
			}
			return NO;
		}
		UDExecutionEntity *execution = task.execution;
		if (![command setVariables:variables from:execution]) {
			return NO;
		}
		[command.context deleteObject:task];
		[command completeActivity:execution];
		return YES;
	} error:error];
}

@end

#pragma mark - History service

@implementation UDHistoryService
{
	__weak UDProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
	}
	return self;
}

- (UDHistoricProcessInstance *)historicProcessInstanceWithId:(NSString *)processInstanceId
{
	__block UDHistoricProcessInstance *instance = nil;
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		UDHistoricProcessInstanceEntity *entity =
			[[command fetch:@"UDHistoricProcessInstance"
			      predicate:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
			          processInstanceId]
			           sort:nil
			          limit:1] lastObject];
		if (entity != nil) {
			instance = [UDHistoricProcessInstance ud_instanceWithEntity:entity];
		}
		return YES;
	} error:NULL];
	return instance;
}

- (NSDictionary *)historicVariablesForProcessInstance:(NSString *)processInstanceId
{
	NSMutableDictionary *variables = [NSMutableDictionary dictionary];
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		NSArray *rows = [command fetch:@"UDHistoricVariable"
		                     predicate:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
		                         processInstanceId]
		                          sort:nil
		                         limit:0];
		/* Local variables first, so process instance ones overwrite them. */
		for (int pass = 0; pass < 2; pass++) {
			for (UDHistoricVariableEntity *row in rows) {
				if (row.scopeIsProcessInstance == (pass == 1)) {
					[variables setObject:[row ud_value] ?: [NSNull null] forKey:row.name];
				}
			}
		}
		return YES;
	} error:NULL];
	return variables;
}

@end

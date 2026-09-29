#import "UDProcessEngine+Internal.h"
#import "UDCommandContext.h"
#import "UDEntities.h"
#import "UDFlowElements.h"
#import "UDProcessDefinition.h"

NSString * const UDProcessInstanceStateActive = @"ACTIVE";
NSString * const UDProcessInstanceStateCompleted = @"COMPLETED";
NSString * const UDProcessInstanceStateInternallyTerminated = @"INTERNALLY_TERMINATED";
NSString * const UDTaskDeleteReasonCompleted = @"completed";
NSString * const UDTaskDeleteReasonDeleted = @"deleted";
NSString * const UDIncidentStateOpen = @"open";
NSString * const UDIncidentStateResolved = @"resolved";
NSString * const UDIncidentStateDeleted = @"deleted";
NSString * const UDJobLogStateCreated = @"created";
NSString * const UDJobLogStateSuccessful = @"successful";
NSString * const UDJobLogStateFailed = @"failed";
NSString * const UDJobLogStateDeleted = @"deleted";

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
@property (nonatomic, readwrite, copy) NSString *superProcessInstanceId;
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
	instance.superProcessInstanceId = root.superProcessInstanceId;
	instance.ended = ended;
	return instance;
}

+ (instancetype)ud_endedInstance:(NSString *)processInstanceId
                     businessKey:(NSString *)businessKey
                      definition:(UDProcessDefinition *)definition
{
	UDProcessInstance *instance = [[UDProcessInstance alloc] init];
	instance.processInstanceId = processInstanceId;
	instance.businessKey = businessKey;
	instance.definitionId = definition.definitionId;
	instance.definitionKey = definition.processId;
	instance.ended = YES;
	return instance;
}

+ (instancetype)ud_instanceWithHistory:(UDHistoricProcessInstanceEntity *)history
{
	UDProcessInstance *instance = [[UDProcessInstance alloc] init];
	instance.processInstanceId = history.processInstanceId;
	instance.businessKey = history.businessKey;
	instance.definitionId = history.definitionId;
	instance.definitionKey = history.definitionKey;
	instance.superProcessInstanceId = history.superProcessInstanceId;
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
@property (nonatomic, readwrite, copy) NSString *superProcessInstanceId;
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
	instance.superProcessInstanceId = entity.superProcessInstanceId;
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
	return [self endedInstance:processInstanceId]
		?: [UDProcessInstance ud_endedInstance:processInstanceId
		                           businessKey:businessKey
		                            definition:definition];
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

- (NSArray<UDProcessInstance *> *)subProcessInstancesOf:(NSString *)processInstanceId
                                                  error:(NSError **)error
{
	__block NSMutableArray *instances = nil;
	BOOL ok = [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		instances = [NSMutableArray array];
		NSArray *roots = [command fetch:@"UDExecution"
		                      predicate:[NSPredicate predicateWithFormat:
		                          @"superProcessInstanceId == %@ AND parent == nil",
		                          processInstanceId]
		                           sort:nil
		                          limit:0];
		for (UDExecutionEntity *root in roots) {
			[instances addObject:[UDProcessInstance ud_instanceWithExecution:root
				definition:[command definitionForExecution:root]
				ended:NO]];
		}
		return YES;
	} error:error];
	if (!ok) {
		return nil;
	}
	return instances;
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

- (BOOL)signal:(NSString *)signalName
     variables:(NSDictionary *)variables
         error:(NSError **)error
{
	return [self signal:signalName processInstanceId:nil variables:variables error:error];
}

- (BOOL)signal:(NSString *)signalName
processInstanceId:(NSString *)processInstanceId
     variables:(NSDictionary *)variables
         error:(NSError **)error
{
	if (![UDCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		[command broadcastSignal:signalName variables:variables processInstanceId:processInstanceId];
		return YES;
	} error:error];
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
		[command historyTaskCompleted:task.taskId];
		[command.context deleteObject:task];
		[command completeActivity:execution];
		return YES;
	} error:error];
}

@end

#pragma mark - History service

@interface UDHistoricActivityInstance ()
@property (nonatomic, readwrite, copy) NSString *activityInstanceId;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *activityName;
@property (nonatomic, readwrite, copy) NSString *activityType;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *calledProcessInstanceId;
@property (nonatomic, readwrite, copy) NSDate *startTime;
@property (nonatomic, readwrite, copy) NSDate *endTime;
@property (nonatomic, readwrite, getter=isCanceled) BOOL canceled;
@end

@implementation UDHistoricActivityInstance
- (NSString *)description
{
	return [NSString stringWithFormat:@"<UDHistoricActivityInstance %@ %@%@>", self.activityType,
		self.activityId, self.canceled ? @" canceled" : self.endTime ? @"" : @" running"];
}
@end

@interface UDHistoricTaskInstance ()
@property (nonatomic, readwrite, copy) NSString *taskId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *taskDefinitionKey;
@property (nonatomic, readwrite, copy) NSString *assignee;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSDate *startTime;
@property (nonatomic, readwrite, copy) NSDate *endTime;
@property (nonatomic, readwrite, copy) NSString *deleteReason;
@end

@implementation UDHistoricTaskInstance
@end

@interface UDHistoricVariableUpdate ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, strong) id value;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSDate *time;
@end

@implementation UDHistoricVariableUpdate
@end

@interface UDHistoricIncident ()
@property (nonatomic, readwrite, copy) NSString *incidentId;
@property (nonatomic, readwrite, copy) NSString *incidentType;
@property (nonatomic, readwrite, copy) NSString *message;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *configuration;
@property (nonatomic, readwrite, copy) NSDate *createdAt;
@property (nonatomic, readwrite, copy) NSDate *endTime;
@property (nonatomic, readwrite, copy) NSString *state;
@end

@implementation UDHistoricIncident
@end

@interface UDHistoricJobLog ()
@property (nonatomic, readwrite, copy) NSString *jobId;
@property (nonatomic, readwrite, copy) NSString *jobType;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSDate *timestamp;
@property (nonatomic, readwrite, copy) NSString *state;
@property (nonatomic, readwrite, copy) NSString *exceptionMessage;
@property (nonatomic, readwrite) NSInteger retries;
@end

@implementation UDHistoricJobLog
@end

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

/* Rows of an entity for one instance, in order, each made into a value. */
- (NSArray *)rows:(NSString *)entity
       ofInstance:(NSString *)processInstanceId
             sort:(NSArray *)sort
            value:(id (^)(id row))value
{
	NSMutableArray *values = [NSMutableArray array];
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		for (id row in [command fetch:entity
		                    predicate:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
		                        processInstanceId ?: @""]
		                         sort:sort
		                        limit:0]) {
			[values addObject:value(row)];
		}
		return YES;
	} error:NULL];
	return values;
}

- (UDHistoricProcessInstance *)historicProcessInstanceWithId:(NSString *)processInstanceId
{
	return [[self rows:@"UDHistoricProcessInstance" ofInstance:processInstanceId sort:nil
	             value:^id(UDHistoricProcessInstanceEntity *row) {
		return [UDHistoricProcessInstance ud_instanceWithEntity:row];
	}] lastObject];
}

- (NSArray<UDHistoricActivityInstance *> *)historicActivityInstancesForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"UDHistoricActivityInstance" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES] ]
	            value:^id(UDHistoricActivityInstanceEntity *row) {
		UDHistoricActivityInstance *value = [[UDHistoricActivityInstance alloc] init];
		value.activityInstanceId = row.activityInstanceId;
		value.activityId = row.activityId;
		value.activityName = row.activityName;
		value.activityType = row.activityType;
		value.calledProcessInstanceId = row.calledProcessInstanceId;
		value.processInstanceId = row.processInstanceId;
		value.startTime = row.startTime;
		value.endTime = row.endTime;
		value.canceled = row.canceled;
		return value;
	}];
}

- (NSArray<UDHistoricTaskInstance *> *)historicTaskInstancesForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"UDHistoricTaskInstance" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"startTime" ascending:YES] ]
	            value:^id(UDHistoricTaskInstanceEntity *row) {
		UDHistoricTaskInstance *value = [[UDHistoricTaskInstance alloc] init];
		value.taskId = row.taskId;
		value.name = row.name;
		value.taskDefinitionKey = row.taskDefinitionKey;
		value.assignee = row.assignee;
		value.processInstanceId = row.processInstanceId;
		value.startTime = row.startTime;
		value.endTime = row.endTime;
		value.deleteReason = row.deleteReason;
		return value;
	}];
}

- (NSDictionary *)historicVariablesForProcessInstance:(NSString *)processInstanceId
{
	NSMutableDictionary *variables = [NSMutableDictionary dictionary];
	NSArray *rows = [self rows:@"UDHistoricVariable" ofInstance:processInstanceId sort:nil
	                     value:^id(UDHistoricVariableEntity *row) {
		return @[ row.name, [row ud_value] ?: [NSNull null],
			[NSNumber numberWithBool:row.scopeIsProcessInstance] ];
	}];
	/* Local variables first, so process instance ones overwrite them. */
	for (int pass = 0; pass < 2; pass++) {
		for (NSArray *row in rows) {
			if ([[row objectAtIndex:2] boolValue] == (pass == 1)) {
				[variables setObject:[row objectAtIndex:1] forKey:[row objectAtIndex:0]];
			}
		}
	}
	return variables;
}

- (NSArray<UDHistoricVariableUpdate *> *)historicVariableUpdatesForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"UDHistoricVariableUpdate" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES] ]
	            value:^id(UDHistoricVariableUpdateEntity *row) {
		UDHistoricVariableUpdate *value = [[UDHistoricVariableUpdate alloc] init];
		value.name = row.name;
		value.value = [row ud_value];
		value.processInstanceId = row.processInstanceId;
		value.time = row.time;
		return value;
	}];
}

- (NSArray<UDHistoricIncident *> *)historicIncidentsForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"UDHistoricIncident" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES] ]
	            value:^id(UDHistoricIncidentEntity *row) {
		UDHistoricIncident *value = [[UDHistoricIncident alloc] init];
		value.incidentId = row.incidentId;
		value.incidentType = row.incidentType;
		value.message = row.message;
		value.activityId = row.activityId;
		value.processInstanceId = row.processInstanceId;
		value.configuration = row.configuration;
		value.createdAt = row.createdAt;
		value.endTime = row.endTime;
		value.state = row.state;
		return value;
	}];
}

- (NSInteger)cleanUpHistory:(NSUInteger)batchSize error:(NSError **)error
{
	__block NSInteger removed = 0;
	NSDate *now = [NSDate date];
	BOOL ok = [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		/* Time to live per definition, read once. */
		NSMutableDictionary *ttls = [NSMutableDictionary dictionary];
		NSArray *ended = [command fetch:@"UDHistoricProcessInstance"
		                      predicate:[NSPredicate predicateWithFormat:@"endTime != nil"]
		                           sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"endTime" ascending:YES] ]
		                          limit:0];
		for (UDHistoricProcessInstanceEntity *instance in ended) {
			if (batchSize > 0 && (NSUInteger)removed >= batchSize) {
				break;
			}
			id ttl = [ttls objectForKey:instance.definitionId];
			if (ttl == nil) {
				NSManagedObject *record = [[command fetch:@"UDDefinitionRecord"
				                                predicate:[NSPredicate predicateWithFormat:
				                                    @"definitionId == %@", instance.definitionId]
				                                     sort:nil
				                                    limit:1] lastObject];
				ttl = [record valueForKey:@"historyTimeToLive"] ?: [NSNull null];
				[ttls setObject:ttl forKey:instance.definitionId];
			}
			if (ttl == [NSNull null]
			    || [[instance.endTime dateByAddingTimeInterval:[ttl doubleValue] * 86400] compare:now]
			       == NSOrderedDescending) {
				continue;
			}
			NSPredicate *mine = [NSPredicate predicateWithFormat:@"processInstanceId == %@",
				instance.processInstanceId];
			for (NSString *entity in @[ @"UDHistoricActivityInstance", @"UDHistoricTaskInstance",
			                            @"UDHistoricVariable", @"UDHistoricVariableUpdate",
			                            @"UDHistoricIncident", @"UDHistoricJobLog" ]) {
				for (NSManagedObject *row in [command fetch:entity predicate:mine sort:nil limit:0]) {
					[command.context deleteObject:row];
				}
			}
			[command.context deleteObject:instance];
			removed += 1;
		}
		return YES;
	} error:error];
	return ok ? removed : -1;
}

- (NSArray<UDHistoricJobLog *> *)historicJobLogForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"UDHistoricJobLog" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES] ]
	            value:^id(UDHistoricJobLogEntity *row) {
		UDHistoricJobLog *value = [[UDHistoricJobLog alloc] init];
		value.jobId = row.jobId;
		value.jobType = row.jobType;
		value.activityId = row.activityId;
		value.processInstanceId = row.processInstanceId;
		value.timestamp = row.timestamp;
		value.state = row.state;
		value.exceptionMessage = row.exceptionMessage;
		value.retries = row.retries;
		return value;
	}];
}

@end

#pragma mark - Management service

@interface UDJob ()
@property (nonatomic, readwrite, copy) NSString *jobId;
@property (nonatomic, readwrite, copy) NSString *jobType;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSDate *dueDate;
@property (nonatomic, readwrite) NSInteger retries;
@property (nonatomic, readwrite, copy) NSString *exceptionMessage;
@property (nonatomic, readwrite, getter=isExclusive) BOOL exclusive;
@end

@implementation UDJob

+ (instancetype)ud_jobWithEntity:(UDJobEntity *)entity
{
	UDJob *job = [[UDJob alloc] init];
	job.jobId = entity.jobId;
	job.jobType = entity.jobType;
	job.activityId = entity.activityId;
	job.processInstanceId = entity.processInstanceId;
	job.definitionId = entity.definitionId ?: entity.execution.definitionId;
	job.dueDate = entity.dueDate;
	job.retries = entity.retries;
	job.exceptionMessage = entity.exceptionMessage;
	job.exclusive = entity.exclusive;
	return job;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<UDJob %@ %@ at %@, %ld left>",
		self.jobType, self.jobId, self.activityId, (long)self.retries];
}

@end

@interface UDIncident ()
@property (nonatomic, readwrite, copy) NSString *incidentId;
@property (nonatomic, readwrite, copy) NSString *incidentType;
@property (nonatomic, readwrite, copy) NSString *message;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *configuration;
@property (nonatomic, readwrite, copy) NSDate *createdAt;
@end

@implementation UDIncident

+ (instancetype)ud_incidentWithEntity:(UDIncidentEntity *)entity
{
	UDIncident *incident = [[UDIncident alloc] init];
	incident.incidentId = entity.incidentId;
	incident.incidentType = entity.incidentType;
	incident.message = entity.message;
	incident.activityId = entity.activityId;
	incident.processInstanceId = entity.processInstanceId;
	incident.configuration = entity.configuration;
	incident.createdAt = entity.createdAt;
	return incident;
}

@end

@implementation UDManagementService
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

- (NSArray<UDJob *> *)jobsMatching:(NSPredicate *)predicate
{
	NSMutableArray *jobs = [NSMutableArray array];
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		for (UDJobEntity *entity in [command fetch:@"UDJob"
		                                 predicate:predicate
		                                      sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"dueDate"
		                                                                              ascending:YES] ]
		                                     limit:0]) {
			[jobs addObject:[UDJob ud_jobWithEntity:entity]];
		}
		return YES;
	} error:NULL];
	return jobs;
}

- (NSArray<UDJob *> *)jobsForProcessInstance:(NSString *)processInstanceId
{
	return [self jobsMatching:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
		processInstanceId]];
}

- (NSArray<UDJob *> *)jobsForDefinition:(NSString *)definitionId
{
	return [self jobsMatching:[NSPredicate predicateWithFormat:@"definitionId == %@",
		definitionId]];
}

- (UDJob *)jobWithId:(NSString *)jobId
{
	return [[self jobsMatching:[NSPredicate predicateWithFormat:@"jobId == %@", jobId]] lastObject];
}

- (NSError *)noJob:(NSString *)jobId
{
	return UDServiceError(UDWorkflowErrorUnknownElement,
		[NSString stringWithFormat:@"no job %@", jobId]);
}

- (BOOL)executeJob:(NSString *)jobId error:(NSError **)error
{
	UDJob *job = jobId == nil ? nil : [self jobWithId:jobId];
	if (job == nil) {
		if (error != NULL) {
			*error = [self noJob:jobId];
		}
		return NO;
	}
	UDProcessEngine *engine = _engine;
	__block BOOL ok = NO;
	__block NSError *localError = nil;
	/* On the instance's queue, so it does not run beside the instance's
	 * other work. */
	dispatch_sync([engine ud_queueFor:job.processInstanceId ?: job.jobId], ^{
		NSError *jobError = nil;
		ok = [engine ud_runJob:jobId force:YES error:&jobError];
		localError = jobError;
	});
	if (!ok && error != NULL) {
		*error = localError;
	}
	return ok;
}

- (BOOL)setRetries:(NSInteger)retries forJob:(NSString *)jobId error:(NSError **)error
{
	UDProcessEngine *engine = _engine;
	return [engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDJobEntity *job = [[command fetch:@"UDJob"
		                         predicate:[NSPredicate predicateWithFormat:@"jobId == %@", jobId ?: @""]
		                              sort:nil
		                             limit:1] lastObject];
		if (job == nil) {
			if (commandError != NULL) {
				*commandError = [self noJob:jobId];
			}
			return NO;
		}
		job.retries = (int32_t)MAX(retries, 0);
		if (retries > 0) {
			[command resolveIncidentsFor:jobId];
		}
		NSString *processInstanceId = job.processInstanceId;
		NSDate *due = job.dueDate;
		BOOL exclusive = job.exclusive;
		[command afterCommit:^{
			[engine ud_jobCreated:jobId processInstanceId:processInstanceId
			              dueDate:due exclusive:exclusive];
		}];
		return YES;
	} error:error];
}

- (NSArray<UDIncident *> *)incidentsForProcessInstance:(NSString *)processInstanceId
{
	NSMutableArray *incidents = [NSMutableArray array];
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		for (UDIncidentEntity *entity in [command fetch:@"UDIncident"
		                                      predicate:[NSPredicate predicateWithFormat:
		                                          @"processInstanceId == %@", processInstanceId]
		                                           sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
		                                                                                   ascending:YES] ]
		                                          limit:0]) {
			[incidents addObject:[UDIncident ud_incidentWithEntity:entity]];
		}
		return YES;
	} error:NULL];
	return incidents;
}

@end

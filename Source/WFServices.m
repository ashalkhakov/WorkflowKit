#import "WFProcessEngine+Internal.h"
#import "WFCommandContext.h"
#import "WFEntities.h"
#import "WFFlowElements.h"
#import "WFProcessDefinition.h"

NSString * const WFProcessInstanceStateActive = @"ACTIVE";
NSString * const WFProcessInstanceStateCompleted = @"COMPLETED";
NSString * const WFProcessInstanceStateInternallyTerminated = @"INTERNALLY_TERMINATED";
NSString * const WFProcessInstanceStateExternallyTerminated = @"EXTERNALLY_TERMINATED";
NSString * const WFTaskDeleteReasonCompleted = @"completed";
NSString * const WFTaskDeleteReasonDeleted = @"deleted";
NSString * const WFIncidentStateOpen = @"open";
NSString * const WFIncidentStateResolved = @"resolved";
NSString * const WFIncidentStateDeleted = @"deleted";
NSString * const WFJobLogStateCreated = @"created";
NSString * const WFJobLogStateSuccessful = @"successful";
NSString * const WFJobLogStateFailed = @"failed";
NSString * const WFJobLogStateDeleted = @"deleted";

static NSError *
WFServiceError(WFErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:WFErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

#pragma mark - Values

@interface WFProcessInstance ()
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *businessKey;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *definitionKey;
@property (nonatomic, readwrite, copy) NSString *superProcessInstanceId;
@property (nonatomic, readwrite, getter=isEnded) BOOL ended;
@property (nonatomic, readwrite, getter=isSuspended) BOOL suspended;
@end

@implementation WFProcessInstance

+ (instancetype)wf_instanceWithExecution:(WFExecutionEntity *)root
                              definition:(WFProcessDefinition *)definition
                                   ended:(BOOL)ended
{
	WFProcessInstance *instance = [[WFProcessInstance alloc] init];
	instance.processInstanceId = root.processInstanceId;
	instance.businessKey = root.businessKey;
	instance.definitionId = root.definitionId;
	instance.definitionKey = definition.processId;
	instance.superProcessInstanceId = root.superProcessInstanceId;
	instance.suspended = root.suspended;
	instance.ended = ended;
	return instance;
}

+ (instancetype)wf_endedInstance:(NSString *)processInstanceId
                     businessKey:(NSString *)businessKey
                      definition:(WFProcessDefinition *)definition
{
	WFProcessInstance *instance = [[WFProcessInstance alloc] init];
	instance.processInstanceId = processInstanceId;
	instance.businessKey = businessKey;
	instance.definitionId = definition.definitionId;
	instance.definitionKey = definition.processId;
	instance.ended = YES;
	return instance;
}

+ (instancetype)wf_instanceWithHistory:(WFHistoricProcessInstanceEntity *)history
{
	WFProcessInstance *instance = [[WFProcessInstance alloc] init];
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
	return [NSString stringWithFormat:@"<WFProcessInstance %@ %@%@>",
		self.processInstanceId, self.definitionKey, self.ended ? @" ended" : @""];
}

@end

@interface WFWorkItem ()
@property (nonatomic, readwrite, copy) NSString *taskId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *taskDefinitionKey;
@property (nonatomic, readwrite, copy) NSString *assignee;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSDate *createdAt;
@property (nonatomic, readwrite, copy) NSDate *dueDate;
@property (nonatomic, readwrite) NSInteger priority;
@property (nonatomic, readwrite, getter=isSuspended) BOOL suspended;
@property (nonatomic, readwrite, copy) NSDate *followUpDate;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *candidateUsers;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *candidateGroups;
@end

@implementation WFWorkItem

+ (instancetype)wf_workItemWithEntity:(WFTaskEntity *)entity
{
	WFWorkItem *task = [[WFWorkItem alloc] init];
	task.taskId = entity.taskId;
	task.name = entity.name;
	task.taskDefinitionKey = entity.taskDefinitionKey;
	task.assignee = entity.assignee;
	task.processInstanceId = entity.processInstanceId;
	task.definitionId = entity.definitionId;
	task.createdAt = entity.createdAt;
	task.dueDate = entity.dueDate;
	task.priority = entity.priority;
	task.suspended = entity.suspended;
	task.followUpDate = entity.followUpDate;
	NSMutableArray *users = [NSMutableArray array];
	NSMutableArray *groups = [NSMutableArray array];
	for (WFIdentityLinkEntity *link in entity.identityLinks) {
		if ([link isDeleted] || ![link.type isEqualToString:WFIdentityLinkCandidate]) {
			continue;
		}
		if (link.userId != nil) {
			[users addObject:link.userId];
		}
		if (link.groupId != nil) {
			[groups addObject:link.groupId];
		}
	}
	task.candidateUsers = [users sortedArrayUsingSelector:@selector(compare:)];
	task.candidateGroups = [groups sortedArrayUsingSelector:@selector(compare:)];
	return task;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<WFWorkItem %@ %@>", self.taskDefinitionKey, self.taskId];
}

@end

@interface WFHistoricProcessInstance ()
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *businessKey;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *definitionKey;
@property (nonatomic, readwrite, copy) NSDate *startTime;
@property (nonatomic, readwrite, copy) NSDate *endTime;
@property (nonatomic, readwrite, copy) NSString *state;
@property (nonatomic, readwrite, copy) NSString *superProcessInstanceId;
@property (nonatomic, readwrite, copy) NSString *deleteReason;
@end

@implementation WFHistoricProcessInstance

+ (instancetype)wf_instanceWithEntity:(WFHistoricProcessInstanceEntity *)entity
{
	WFHistoricProcessInstance *instance = [[WFHistoricProcessInstance alloc] init];
	instance.processInstanceId = entity.processInstanceId;
	instance.businessKey = entity.businessKey;
	instance.definitionId = entity.definitionId;
	instance.definitionKey = entity.definitionKey;
	instance.startTime = entity.startTime;
	instance.endTime = entity.endTime;
	instance.state = entity.state;
	instance.superProcessInstanceId = entity.superProcessInstanceId;
	instance.deleteReason = entity.deleteReason;
	return instance;
}

@end

#pragma mark - Runtime service

@implementation WFRuntimeService
{
	__weak WFProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
	}
	return self;
}

- (WFExecutionEntity *)root:(NSString *)processInstanceId in:(WFCommandContext *)command
{
	return [[command fetch:@"WFExecution"
	             predicate:[NSPredicate predicateWithFormat:
	                 @"executionId == %@ AND parent == nil", processInstanceId]
	                  sort:nil
	                 limit:1] lastObject];
}

- (NSError *)notRunning:(NSString *)processInstanceId
{
	return WFServiceError(WFErrorUnknownElement,
		[NSString stringWithFormat:@"no running process instance %@", processInstanceId]);
}

- (WFProcessInstance *)startProcessInstanceByKey:(NSString *)key
                                       variables:(NSDictionary *)variables
                                           error:(NSError **)error
{
	return [self startProcessInstanceByKey:key businessKey:nil variables:variables error:error];
}

- (WFProcessInstance *)startProcessInstanceByKey:(NSString *)key
                                     businessKey:(NSString *)businessKey
                                       variables:(NSDictionary *)variables
                                           error:(NSError **)error
{
	WFProcessEngine *engine = _engine;
	WFProcessDefinition *definition =
		[engine.repositoryService latestDefinitionForKey:key error:error];
	if (definition == nil
	    || ![WFCommandContext areStorableVariables:variables error:error]) {
		return nil;
	}
	__block NSString *processInstanceId = nil;
	BOOL ok = [engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		WFExecutionEntity *root = [command startProcessInstance:definition
		                                            businessKey:businessKey
		                                              variables:variables
		                                             startEvent:nil];
		processInstanceId = root.processInstanceId;
		return root != nil;
	} error:error];
	if (!ok) {
		return nil;
	}
	WFProcessInstance *running = [self processInstanceWithId:processInstanceId error:NULL];
	if (running != nil) {
		return running;
	}
	/* It ran to its end within the start command. */
	return [self endedInstance:processInstanceId]
		?: [WFProcessInstance wf_endedInstance:processInstanceId
		                           businessKey:businessKey
		                            definition:definition];
}

- (WFProcessInstance *)endedInstance:(NSString *)processInstanceId
{
	__block WFProcessInstance *instance = nil;
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		WFHistoricProcessInstanceEntity *history =
			[[command fetch:@"WFHistoricProcessInstance"
			      predicate:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
			          processInstanceId]
			           sort:nil
			          limit:1] lastObject];
		if (history != nil) {
			instance = [WFProcessInstance wf_instanceWithHistory:history];
		}
		return YES;
	} error:NULL];
	return instance;
}

- (WFProcessInstance *)processInstanceWithId:(NSString *)processInstanceId
                                       error:(NSError **)error
{
	__block WFProcessInstance *instance = nil;
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		WFExecutionEntity *root = [self root:processInstanceId in:command];
		if (root != nil) {
			instance = [WFProcessInstance wf_instanceWithExecution:root
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

- (BOOL)deleteProcessInstance:(NSString *)processInstanceId
                       reason:(NSString *)reason
                        error:(NSError **)error
{
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFExecutionEntity *root = [self root:processInstanceId in:command];
		if (root == nil) {
			if (commandError != NULL) {
				*commandError = [self notRunning:processInstanceId];
			}
			return NO;
		}
		if (root.superProcessInstanceId != nil) {
			if (commandError != NULL) {
				*commandError = WFServiceError(WFErrorInvalidState, [NSString stringWithFormat:
					@"%@ was started by a call activity of %@; delete that instance",
					processInstanceId, root.superProcessInstanceId]);
			}
			return NO;
		}
		[command deleteProcessInstance:root reason:reason];
		return YES;
	} error:error];
}

- (BOOL)setSuspended:(BOOL)suspended processInstance:(NSString *)processInstanceId error:(NSError **)error
{
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		if ([self root:processInstanceId in:command] == nil) {
			if (commandError != NULL) {
				*commandError = [self notRunning:processInstanceId];
			}
			return NO;
		}
		[command setSuspended:suspended processInstance:processInstanceId];
		return YES;
	} error:error];
}

- (BOOL)suspendProcessInstance:(NSString *)processInstanceId error:(NSError **)error
{
	return [self setSuspended:YES processInstance:processInstanceId error:error];
}

- (BOOL)activateProcessInstance:(NSString *)processInstanceId error:(NSError **)error
{
	BOOL ok = [self setSuspended:NO processInstance:processInstanceId error:error];
	if (ok) {
		/* Its jobs and external tasks are there to be taken again. */
		[_engine wf_reschedule];
	}
	return ok;
}

- (NSArray<WFProcessInstance *> *)subProcessInstancesOf:(NSString *)processInstanceId
                                                  error:(NSError **)error
{
	__block NSMutableArray *instances = nil;
	BOOL ok = [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		instances = [NSMutableArray array];
		NSArray *roots = [command fetch:@"WFExecution"
		                      predicate:[NSPredicate predicateWithFormat:
		                          @"superProcessInstanceId == %@ AND parent == nil",
		                          processInstanceId]
		                           sort:nil
		                          limit:0];
		for (WFExecutionEntity *root in roots) {
			[instances addObject:[WFProcessInstance wf_instanceWithExecution:root
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
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		NSArray *executions = [command fetch:@"WFExecution"
		                           predicate:[NSPredicate predicateWithFormat:
		                               @"processInstanceId == %@", processInstanceId]
		                                sort:nil
		                               limit:0];
		if ([executions count] > 0) {
			NSMutableSet *active = [NSMutableSet set];
			for (WFExecutionEntity *execution in executions) {
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
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		WFExecutionEntity *root = [self root:processInstanceId in:command];
		if (root != nil) {
			variables = [NSMutableDictionary dictionary];
			for (WFVariableEntity *variable in root.variables) {
				[variables setObject:[variable wf_value] ?: [NSNull null] forKey:variable.name];
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
	if (![WFCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFExecutionEntity *root = [self root:processInstanceId in:command];
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
                  command:(WFCommandContext *)command
{
	NSMutableArray *recipients = [NSMutableArray array];
	NSArray *subscriptions = [command fetch:@"WFEventSubscription"
	                              predicate:[NSPredicate predicateWithFormat:
	                                  @"eventType == %@ AND eventName == %@",
	                                  WFEventTypeMessage, messageName]
	                                   sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
	                                                                           ascending:YES] ]
	                                  limit:0];
	for (WFEventSubscriptionEntity *subscription in subscriptions) {
		if (subscription.execution == nil) {
			if (processInstanceId == nil && [correlationKeys count] == 0
			    && ![command isDefinitionSuspended:subscription.definitionId]) {
				[recipients addObject:subscription];
			}
			continue;
		}
		if (subscription.execution.suspended) {
			/* A suspended instance is passed by. */
			continue;
		}
		WFExecutionEntity *root = [subscription.execution processInstance];
		if (processInstanceId != nil
		    && ![root.processInstanceId isEqualToString:processInstanceId]) {
			continue;
		}
		if (businessKey != nil && ![root.businessKey isEqualToString:businessKey]) {
			continue;
		}
		BOOL matches = YES;
		for (NSString *key in correlationKeys) {
			id value = [[root localVariableNamed:key] wf_value];
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
	if (![WFCommandContext areStorableVariables:variables error:error]) {
		return nil;
	}
	WFProcessEngine *engine = _engine;
	NSMutableArray *reached = [NSMutableArray array];
	BOOL ok = [engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		NSArray *recipients = [self recipientsOf:messageName
		                             businessKey:businessKey
		                         correlationKeys:correlationKeys
		                       processInstanceId:processInstanceId
		                                 command:command];
		if ([recipients count] == 0 || (exactlyOne && [recipients count] > 1)) {
			if (commandError != NULL) {
				*commandError = WFServiceError(WFErrorNoPath,
					[NSString stringWithFormat:@"message %@ matched %lu recipients",
						messageName, (unsigned long)[recipients count]]);
			}
			return NO;
		}
		for (WFEventSubscriptionEntity *subscription in recipients) {
			if (subscription.execution != nil) {
				[reached addObject:subscription.processInstanceId];
				[command deliverSubscription:subscription variables:variables];
				continue;
			}
			WFProcessDefinition *definition =
				[engine.repositoryService definitionWithId:subscription.definitionId
				                                     error:commandError];
			if (definition == nil) {
				return NO;
			}
			WFExecutionEntity *root = [command startProcessInstance:definition
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
	if (![WFCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
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

@implementation WFTaskService
{
	__weak WFProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
	}
	return self;
}

- (NSArray<WFWorkItem *> *)tasksMatching:(NSPredicate *)predicate
{
	NSMutableArray *tasks = [NSMutableArray array];
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		for (WFTaskEntity *entity in [command fetch:@"WFTask"
		                                  predicate:predicate
		                                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
		                                                                               ascending:YES] ]
		                                      limit:0]) {
			[tasks addObject:[WFWorkItem wf_workItemWithEntity:entity]];
		}
		return YES;
	} error:NULL];
	return tasks;
}

- (WFWorkItem *)taskWithId:(NSString *)taskId error:(NSError **)error
{
	WFWorkItem *task = [[self tasksMatching:[NSPredicate predicateWithFormat:@"taskId == %@", taskId]]
		lastObject];
	if (task == nil && error != NULL) {
		*error = WFServiceError(WFErrorUnknownElement,
			[NSString stringWithFormat:@"no open task %@", taskId]);
	}
	return task;
}

- (NSArray<WFWorkItem *> *)tasksForProcessInstance:(NSString *)processInstanceId
{
	return [self tasksMatching:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
		processInstanceId]];
}

- (NSArray<WFWorkItem *> *)tasksForAssignee:(NSString *)assignee
{
	return [self tasksMatching:[NSPredicate predicateWithFormat:@"assignee == %@", assignee]];
}

/* Unclaimed tasks with a candidate link matching the predicate. */
- (NSArray<WFWorkItem *> *)unclaimedTasksLinked:(NSPredicate *)links
{
	NSMutableArray *tasks = [NSMutableArray array];
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		NSMutableSet *taskIds = [NSMutableSet set];
		for (WFIdentityLinkEntity *link in [command fetch:@"WFIdentityLink" predicate:links sort:nil limit:0]) {
			if (link.task.taskId != nil) {
				[taskIds addObject:link.task.taskId];
			}
		}
		if ([taskIds count] == 0) {
			return YES;
		}
		for (WFTaskEntity *entity in [command fetch:@"WFTask"
		                                  predicate:[NSPredicate predicateWithFormat:
		                                      @"taskId IN %@ AND assignee == nil", [taskIds allObjects]]
		                                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
		                                                                               ascending:YES] ]
		                                      limit:0]) {
			[tasks addObject:[WFWorkItem wf_workItemWithEntity:entity]];
		}
		return YES;
	} error:NULL];
	return tasks;
}

- (NSArray<WFWorkItem *> *)tasksForCandidateUser:(NSString *)userId groups:(NSArray<NSString *> *)groupIds
{
	return [self unclaimedTasksLinked:[NSPredicate predicateWithFormat:
		@"type == %@ AND (userId == %@ OR groupId IN %@)", WFIdentityLinkCandidate, userId ?: @"",
		groupIds ?: @[]]];
}

- (NSArray<WFWorkItem *> *)tasksForCandidateGroup:(NSString *)groupId
{
	return [self unclaimedTasksLinked:[NSPredicate predicateWithFormat:
		@"type == %@ AND groupId == %@", WFIdentityLinkCandidate, groupId ?: @""]];
}

/* Changes who has the open task; claiming fails when someone else does. */
- (BOOL)assign:(NSString *)userId task:(NSString *)taskId claim:(BOOL)claim error:(NSError **)error
{
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFTaskEntity *task = [[command fetch:@"WFTask"
		                           predicate:[NSPredicate predicateWithFormat:@"taskId == %@", taskId ?: @""]
		                                sort:nil
		                               limit:1] lastObject];
		NSError *problem = nil;
		if (task == nil) {
			problem = WFServiceError(WFErrorUnknownElement, [NSString stringWithFormat:@"no open task %@", taskId]);
		} else if (task.suspended) {
			problem = WFServiceError(WFErrorSuspended,
				[NSString stringWithFormat:@"task %@ belongs to a suspended process instance", taskId]);
		} else if (claim && task.assignee != nil && ![task.assignee isEqualToString:userId]) {
			problem = WFServiceError(WFErrorInvalidState,
				[NSString stringWithFormat:@"task %@ is claimed by %@", taskId, task.assignee]);
		}
		if (problem != nil) {
			if (commandError != NULL) {
				*commandError = problem;
			}
			return NO;
		}
		task.assignee = userId;
		[command historyTask:task.taskId assignee:userId];
		return YES;
	} error:error];
}

- (BOOL)claimTask:(NSString *)taskId user:(NSString *)userId error:(NSError **)error
{
	return [self assign:userId task:taskId claim:YES error:error];
}

- (BOOL)unclaimTask:(NSString *)taskId error:(NSError **)error
{
	return [self assign:nil task:taskId claim:NO error:error];
}

- (BOOL)setAssignee:(NSString *)userId forTask:(NSString *)taskId error:(NSError **)error
{
	return [self assign:userId task:taskId claim:NO error:error];
}

- (BOOL)completeTask:(NSString *)taskId
           variables:(NSDictionary *)variables
               error:(NSError **)error
{
	if (![WFCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFTaskEntity *task = [[command fetch:@"WFTask"
		                           predicate:[NSPredicate predicateWithFormat:@"taskId == %@", taskId]
		                                sort:nil
		                               limit:1] lastObject];
		if (task == nil) {
			if (commandError != NULL) {
				*commandError = WFServiceError(WFErrorUnknownElement,
					[NSString stringWithFormat:@"no open task %@", taskId]);
			}
			return NO;
		}
		if (task.suspended) {
			if (commandError != NULL) {
				*commandError = WFServiceError(WFErrorSuspended,
					[NSString stringWithFormat:@"task %@ belongs to a suspended process instance", taskId]);
			}
			return NO;
		}
		WFExecutionEntity *execution = task.execution;
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

@interface WFHistoricActivityInstance ()
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

@implementation WFHistoricActivityInstance
- (NSString *)description
{
	return [NSString stringWithFormat:@"<WFHistoricActivityInstance %@ %@%@>", self.activityType,
		self.activityId, self.canceled ? @" canceled" : self.endTime ? @"" : @" running"];
}
@end

@interface WFHistoricTaskInstance ()
@property (nonatomic, readwrite, copy) NSString *taskId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *taskDefinitionKey;
@property (nonatomic, readwrite, copy) NSString *assignee;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSDate *startTime;
@property (nonatomic, readwrite, copy) NSDate *endTime;
@property (nonatomic, readwrite, copy) NSString *deleteReason;
@end

@implementation WFHistoricTaskInstance
@end

@interface WFHistoricVariableUpdate ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, strong) id value;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSDate *time;
@end

@implementation WFHistoricVariableUpdate
@end

@interface WFHistoricIncident ()
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

@implementation WFHistoricIncident
@end

@interface WFHistoricJobLog ()
@property (nonatomic, readwrite, copy) NSString *jobId;
@property (nonatomic, readwrite, copy) NSString *jobType;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSDate *timestamp;
@property (nonatomic, readwrite, copy) NSString *state;
@property (nonatomic, readwrite, copy) NSString *exceptionMessage;
@property (nonatomic, readwrite) NSInteger retries;
@end

@implementation WFHistoricJobLog
@end

@implementation WFHistoryService
{
	__weak WFProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine
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
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
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

- (WFHistoricProcessInstance *)historicProcessInstanceWithId:(NSString *)processInstanceId
{
	return [[self rows:@"WFHistoricProcessInstance" ofInstance:processInstanceId sort:nil
	             value:^id(WFHistoricProcessInstanceEntity *row) {
		return [WFHistoricProcessInstance wf_instanceWithEntity:row];
	}] lastObject];
}

- (NSArray<WFHistoricActivityInstance *> *)historicActivityInstancesForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"WFHistoricActivityInstance" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES] ]
	            value:^id(WFHistoricActivityInstanceEntity *row) {
		WFHistoricActivityInstance *value = [[WFHistoricActivityInstance alloc] init];
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

- (NSArray<WFHistoricTaskInstance *> *)historicTaskInstancesForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"WFHistoricTaskInstance" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"startTime" ascending:YES] ]
	            value:^id(WFHistoricTaskInstanceEntity *row) {
		WFHistoricTaskInstance *value = [[WFHistoricTaskInstance alloc] init];
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
	NSArray *rows = [self rows:@"WFHistoricVariable" ofInstance:processInstanceId sort:nil
	                     value:^id(WFHistoricVariableEntity *row) {
		return @[ row.name, [row wf_value] ?: [NSNull null],
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

- (NSArray<WFHistoricVariableUpdate *> *)historicVariableUpdatesForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"WFHistoricVariableUpdate" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES] ]
	            value:^id(WFHistoricVariableUpdateEntity *row) {
		WFHistoricVariableUpdate *value = [[WFHistoricVariableUpdate alloc] init];
		value.name = row.name;
		value.value = [row wf_value];
		value.processInstanceId = row.processInstanceId;
		value.time = row.time;
		return value;
	}];
}

- (NSArray<WFHistoricIncident *> *)historicIncidentsForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"WFHistoricIncident" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES] ]
	            value:^id(WFHistoricIncidentEntity *row) {
		WFHistoricIncident *value = [[WFHistoricIncident alloc] init];
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
	BOOL ok = [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		/* Time to live per definition, read once. */
		NSMutableDictionary *ttls = [NSMutableDictionary dictionary];
		NSArray *ended = [command fetch:@"WFHistoricProcessInstance"
		                      predicate:[NSPredicate predicateWithFormat:@"endTime != nil"]
		                           sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"endTime" ascending:YES] ]
		                          limit:0];
		for (WFHistoricProcessInstanceEntity *instance in ended) {
			if (batchSize > 0 && (NSUInteger)removed >= batchSize) {
				break;
			}
			id ttl = [ttls objectForKey:instance.definitionId];
			if (ttl == nil) {
				NSManagedObject *record = [[command fetch:@"WFDefinitionRecord"
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
			for (NSString *entity in @[ @"WFHistoricActivityInstance", @"WFHistoricTaskInstance",
			                            @"WFHistoricVariable", @"WFHistoricVariableUpdate",
			                            @"WFHistoricIncident", @"WFHistoricJobLog" ]) {
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

- (NSArray<WFHistoricJobLog *> *)historicJobLogForProcessInstance:(NSString *)processInstanceId
{
	return [self rows:@"WFHistoricJobLog" ofInstance:processInstanceId
	             sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES] ]
	            value:^id(WFHistoricJobLogEntity *row) {
		WFHistoricJobLog *value = [[WFHistoricJobLog alloc] init];
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

@interface WFJob ()
@property (nonatomic, readwrite, copy) NSString *jobId;
@property (nonatomic, readwrite, copy) NSString *jobType;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSDate *dueDate;
@property (nonatomic, readwrite) NSInteger retries;
@property (nonatomic, readwrite, copy) NSString *exceptionMessage;
@property (nonatomic, readwrite, getter=isExclusive) BOOL exclusive;
@property (nonatomic, readwrite, getter=isSuspended) BOOL suspended;
@end

@implementation WFJob

+ (instancetype)wf_jobWithEntity:(WFJobEntity *)entity
{
	WFJob *job = [[WFJob alloc] init];
	job.jobId = entity.jobId;
	job.jobType = entity.jobType;
	job.activityId = entity.activityId;
	job.processInstanceId = entity.processInstanceId;
	job.definitionId = entity.definitionId ?: entity.execution.definitionId;
	job.dueDate = entity.dueDate;
	job.retries = entity.retries;
	job.exceptionMessage = entity.exceptionMessage;
	job.exclusive = entity.exclusive;
	job.suspended = entity.suspended;
	return job;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<WFJob %@ %@ at %@, %ld left>",
		self.jobType, self.jobId, self.activityId, (long)self.retries];
}

@end

@interface WFIncident ()
@property (nonatomic, readwrite, copy) NSString *incidentId;
@property (nonatomic, readwrite, copy) NSString *incidentType;
@property (nonatomic, readwrite, copy) NSString *message;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *configuration;
@property (nonatomic, readwrite, copy) NSDate *createdAt;
@end

@implementation WFIncident

+ (instancetype)wf_incidentWithEntity:(WFIncidentEntity *)entity
{
	WFIncident *incident = [[WFIncident alloc] init];
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

@implementation WFManagementService
{
	__weak WFProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
	}
	return self;
}

- (NSArray<WFJob *> *)jobsMatching:(NSPredicate *)predicate
{
	NSMutableArray *jobs = [NSMutableArray array];
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		for (WFJobEntity *entity in [command fetch:@"WFJob"
		                                 predicate:predicate
		                                      sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"dueDate"
		                                                                              ascending:YES] ]
		                                     limit:0]) {
			[jobs addObject:[WFJob wf_jobWithEntity:entity]];
		}
		return YES;
	} error:NULL];
	return jobs;
}

- (NSArray<WFJob *> *)jobsForProcessInstance:(NSString *)processInstanceId
{
	return [self jobsMatching:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
		processInstanceId]];
}

- (NSArray<WFJob *> *)jobsForDefinition:(NSString *)definitionId
{
	return [self jobsMatching:[NSPredicate predicateWithFormat:@"definitionId == %@",
		definitionId]];
}

- (WFJob *)jobWithId:(NSString *)jobId
{
	return [[self jobsMatching:[NSPredicate predicateWithFormat:@"jobId == %@", jobId]] lastObject];
}

- (NSError *)noJob:(NSString *)jobId
{
	return WFServiceError(WFErrorUnknownElement,
		[NSString stringWithFormat:@"no job %@", jobId]);
}

- (BOOL)executeJob:(NSString *)jobId error:(NSError **)error
{
	WFJob *job = jobId == nil ? nil : [self jobWithId:jobId];
	if (job == nil) {
		if (error != NULL) {
			*error = [self noJob:jobId];
		}
		return NO;
	}
	if (job.isSuspended) {
		if (error != NULL) {
			*error = WFServiceError(WFErrorSuspended,
				[NSString stringWithFormat:@"job %@ is suspended", jobId]);
		}
		return NO;
	}
	WFProcessEngine *engine = _engine;
	__block BOOL ok = NO;
	__block NSError *localError = nil;
	/* On the instance's queue, so it does not run beside the instance's
	 * other work. */
	dispatch_sync([engine wf_queueFor:job.processInstanceId ?: job.jobId], ^{
		NSError *jobError = nil;
		ok = [engine wf_runJob:jobId force:YES error:&jobError];
		localError = jobError;
	});
	if (!ok && error != NULL) {
		*error = localError;
	}
	return ok;
}

- (BOOL)setRetries:(NSInteger)retries forJob:(NSString *)jobId error:(NSError **)error
{
	WFProcessEngine *engine = _engine;
	return [engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFJobEntity *job = [[command fetch:@"WFJob"
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
			[engine wf_jobCreated:jobId processInstanceId:processInstanceId
			              dueDate:due exclusive:exclusive];
		}];
		return YES;
	} error:error];
}

- (NSArray<WFIncident *> *)incidentsForProcessInstance:(NSString *)processInstanceId
{
	NSMutableArray *incidents = [NSMutableArray array];
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		for (WFIncidentEntity *entity in [command fetch:@"WFIncident"
		                                      predicate:[NSPredicate predicateWithFormat:
		                                          @"processInstanceId == %@", processInstanceId]
		                                           sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
		                                                                                   ascending:YES] ]
		                                          limit:0]) {
			[incidents addObject:[WFIncident wf_incidentWithEntity:entity]];
		}
		return YES;
	} error:NULL];
	return incidents;
}

@end

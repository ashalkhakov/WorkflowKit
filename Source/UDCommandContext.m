#import "UDCommandContext.h"
#import "UDEntities.h"
#import "UDProcessEngine+Internal.h"
#import "UDFlowElements.h"
#import "UDProcessDefinition.h"
#import "UDCondition.h"

static NSString * const UDExecutionName = @"UDExecution";
static NSString * const UDVariableName = @"UDVariable";
static NSString * const UDTaskName = @"UDTask";
static NSString * const UDSubscriptionName = @"UDEventSubscription";
static NSString * const UDJobName = @"UDJob";
static NSString * const UDExternalTaskName = @"UDExternalTask";
static NSString * const UDHistoricInstanceName = @"UDHistoricProcessInstance";
static NSString * const UDHistoricVariableName = @"UDHistoricVariable";

static NSError *
UDCommandError(UDWorkflowErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:UDWorkflowErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@implementation UDCommandContext
{
	NSMutableArray *_agenda;
	NSMutableArray *_afterCommit;
	NSError *_failure;
	NSMutableDictionary *_definitions;
	NSMutableDictionary *_historicVariables;
}

- (instancetype)initWithEngine:(UDProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
		_context = [engine.store newCommandContext];
		_agenda = [NSMutableArray array];
		_afterCommit = [NSMutableArray array];
		_definitions = [NSMutableDictionary dictionary];
		_historicVariables = [NSMutableDictionary dictionary];
	}
	return self;
}

+ (NSString *)newId
{
	return [[NSUUID UUID] UUIDString];
}

+ (BOOL)isStorableValue:(id)value
{
	if (value == nil || value == [NSNull null]
	    || [value isKindOfClass:[NSString class]]
	    || [value isKindOfClass:[NSNumber class]]
	    || [value isKindOfClass:[NSDate class]]
	    || [value isKindOfClass:[NSData class]]) {
		return YES;
	}
	return ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]])
		&& [NSJSONSerialization isValidJSONObject:value];
}

+ (BOOL)areStorableVariables:(NSDictionary *)variables error:(NSError **)error
{
	for (NSString *name in variables) {
		if (![name isKindOfClass:[NSString class]]
		    || ![self isStorableValue:[variables objectForKey:name]]) {
			if (error != NULL) {
				*error = UDCommandError(UDWorkflowErrorInvalidState,
					[NSString stringWithFormat:
						@"variable %@ is not a value the engine stores", name]);
			}
			return NO;
		}
	}
	return YES;
}

#pragma mark - Running

- (void)fail:(NSError *)error
{
	if (_failure == nil) {
		_failure = error ?: UDCommandError(UDWorkflowErrorInvalidState, @"command failed");
	}
}

- (void)afterCommit:(void (^)(void))block
{
	[_afterCommit addObject:[block copy]];
}

- (void)schedule:(void (^)(void))operation
{
	[_agenda addObject:[operation copy]];
}

- (void)runAgenda
{
	while ([_agenda count] > 0 && _failure == nil) {
		void (^operation)(void) = [_agenda objectAtIndex:0];
		[_agenda removeObjectAtIndex:0];
		operation();
	}
}

- (NSError *)translateSaveError:(NSError *)error
{
	NSInteger code = [error code];
	if ([[error domain] isEqualToString:NSCocoaErrorDomain]
	    && (code == NSManagedObjectMergeError
	        || code == NSPersistentStoreSaveConflictsError
	        || code == NSManagedObjectConstraintMergeError)) {
		return [NSError errorWithDomain:UDWorkflowErrorDomain
		                           code:UDWorkflowErrorConflict
		                       userInfo:@{
			NSLocalizedDescriptionKey:
				@"another command changed the same data first; nothing was committed",
			NSUnderlyingErrorKey: error }];
	}
	return error;
}

- (BOOL)execute:(BOOL (^)(UDCommandContext *, NSError **))body error:(NSError **)error
{
	__block BOOL ok = NO;
	__block NSError *localError = nil;
	[_context performBlockAndWait:^{
		NSError *bodyError = nil;
		@try {
			ok = body(self, &bodyError);
			if (ok) {
				[self runAgenda];
				if (self->_failure != nil) {
					ok = NO;
					bodyError = self->_failure;
				}
			} else if (bodyError == nil) {
				bodyError = self->_failure;
			}
			if (ok) {
				ok = [self->_context save:&bodyError];
				if (!ok) {
					bodyError = [self translateSaveError:bodyError];
				}
			}
		} @catch (NSException *exception) {
			ok = NO;
			bodyError = UDCommandError(UDWorkflowErrorInvalidState,
				[NSString stringWithFormat:@"%@: %@", [exception name], [exception reason]]);
		}
		if (!ok) {
			[self->_context rollback];
		}
		[self->_context reset];
		localError = bodyError;
	}];
	if (ok) {
		for (void (^block)(void) in _afterCommit) {
			block();
		}
	} else if (error != NULL) {
		*error = localError;
	}
	return ok;
}

#pragma mark - Rows

- (NSArray *)fetch:(NSString *)entity
         predicate:(NSPredicate *)predicate
              sort:(NSArray *)sort
             limit:(NSUInteger)limit
{
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entity];
	[request setPredicate:predicate];
	[request setSortDescriptors:sort];
	if (limit > 0) {
		[request setFetchLimit:limit];
	}
	return [_context executeFetchRequest:request error:NULL] ?: @[];
}

- (id)insert:(NSString *)entity
{
	return [NSEntityDescription insertNewObjectForEntityForName:entity
	                                     inManagedObjectContext:_context];
}

- (void)remove:(NSManagedObject *)object
{
	[_context deleteObject:object];
}

- (UDProcessDefinition *)definitionForExecution:(UDExecutionEntity *)execution
{
	NSString *definitionId = execution.definitionId;
	UDProcessDefinition *definition = [_definitions objectForKey:definitionId];
	if (definition == nil) {
		NSError *error = nil;
		definition = [self.engine.repositoryService definitionWithId:definitionId error:&error];
		if (definition == nil) {
			[self fail:error];
			return nil;
		}
		[_definitions setObject:definition forKey:definitionId];
	}
	return definition;
}

- (UDFlowNode *)node:(NSString *)activityId of:(UDExecutionEntity *)execution
{
	UDFlowNode *node = [[self definitionForExecution:execution] flowNodeWithId:activityId];
	if (node == nil) {
		[self fail:UDCommandError(UDWorkflowErrorUnknownElement,
			[NSString stringWithFormat:@"no activity %@ in the definition", activityId])];
	}
	return node;
}

- (UDProcessDefinition *)scopeOf:(NSString *)activityId execution:(UDExecutionEntity *)execution
{
	return [[self definitionForExecution:execution] scopeOfFlowNode:activityId];
}

- (UDExecutionEntity *)newChildOf:(UDExecutionEntity *)parent concurrent:(BOOL)concurrent
{
	UDExecutionEntity *child = [self insert:UDExecutionName];
	child.executionId = [UDCommandContext newId];
	child.processInstanceId = parent.processInstanceId;
	child.definitionId = parent.definitionId;
	child.isConcurrent = concurrent;
	child.isScope = !concurrent;
	child.isActive = YES;
	child.parent = parent;
	return child;
}

/* The execution that holds the concurrent paths this one is part of. */
- (UDExecutionEntity *)levelOf:(UDExecutionEntity *)execution
{
	return execution.isConcurrent ? execution.parent : execution;
}

- (NSArray<UDExecutionEntity *> *)pathsAt:(UDExecutionEntity *)level
{
	NSArray *paths = [level concurrentChildren];
	return [paths count] > 0 ? paths : @[ level ];
}

#pragma mark - Starting and entering

- (UDExecutionEntity *)startProcessInstance:(UDProcessDefinition *)definition
                                businessKey:(NSString *)businessKey
                                  variables:(NSDictionary *)variables
                                 startEvent:(UDEvent *)startEvent
{
	UDEvent *start = startEvent ?: [definition startEvent];
	if (start == nil) {
		[self fail:UDCommandError(UDWorkflowErrorInvalidDefinition,
			@"the definition has no start event")];
		return nil;
	}
	[_definitions setObject:definition forKey:definition.definitionId];
	UDExecutionEntity *root = [self insert:UDExecutionName];
	root.executionId = [UDCommandContext newId];
	root.processInstanceId = root.executionId;
	root.definitionId = definition.definitionId;
	root.businessKey = businessKey;
	root.isScope = YES;
	root.isActive = YES;

	UDHistoricProcessInstanceEntity *history = [self insert:UDHistoricInstanceName];
	history.processInstanceId = root.processInstanceId;
	history.businessKey = businessKey;
	history.definitionId = definition.definitionId;
	history.definitionKey = definition.processId;
	history.startTime = [NSDate date];
	history.state = UDHistoricStateActive;

	if (![self setVariables:variables from:root]) {
		return nil;
	}
	[self schedule:^{
		[self enter:start execution:root];
	}];
	return root;
}

- (BOOL)isScopeActivity:(UDFlowNode *)node scope:(UDProcessDefinition *)scope
{
	if ([node isKindOfClass:[UDSubProcess class]]) {
		return YES;
	}
	return [node isKindOfClass:[UDTask class]]
		&& [[scope boundaryEventsAttachedTo:node.elementId] count] > 0;
}

/* Is this the scope execution created for a task with boundary events? */
- (BOOL)isActivityScope:(UDExecutionEntity *)execution node:(UDFlowNode *)node
{
	return execution.isScope && execution.parent != nil
		&& ![node isKindOfClass:[UDSubProcess class]]
		&& [execution.parent.activityId isEqualToString:node.elementId];
}

- (void)enter:(UDFlowNode *)node execution:(UDExecutionEntity *)execution
{
	UDProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	execution.activityId = node.elementId;
	execution.activityInstanceId = [UDCommandContext newId];
	execution.isActive = YES;
	if (![self isScopeActivity:node scope:scope]) {
		[self execute:node scope:scope execution:execution];
		return;
	}
	/* A scope activity runs in a child scope execution: its boundary
	 * subscriptions and timers hang there, and interrupting it removes
	 * exactly that subtree. */
	UDExecutionEntity *inner = [self newChildOf:execution concurrent:NO];
	execution.isActive = NO;
	if ([node isKindOfClass:[UDSubProcess class]]) {
		UDEvent *start = [[(UDSubProcess *)node innerDefinition] startEvent];
		[self schedule:^{
			[self enter:start execution:inner];
		}];
		return;
	}
	inner.activityId = node.elementId;
	inner.activityInstanceId = execution.activityInstanceId;
	for (UDEvent *boundary in [scope boundaryEventsAttachedTo:node.elementId]) {
		if (boundary.trigger == UDEventTriggerMessage) {
			[self subscribe:inner message:boundary.messageName activity:boundary.elementId];
		} else if (boundary.trigger == UDEventTriggerTimer) {
			[self timer:inner activity:boundary.elementId duration:boundary.timerDuration];
		}
	}
	[self execute:node scope:scope execution:inner];
}

- (void)execute:(UDFlowNode *)node
          scope:(UDProcessDefinition *)scope
      execution:(UDExecutionEntity *)execution
{
	if ([node isKindOfClass:[UDEvent class]]) {
		[self executeEvent:(UDEvent *)node execution:execution];
	} else if ([node isKindOfClass:[UDTask class]]) {
		[self executeTask:(UDTask *)node execution:execution];
	} else if ([node isKindOfClass:[UDGateway class]]) {
		[self executeGateway:(UDGateway *)node scope:scope execution:execution];
	} else {
		[self fail:UDCommandError(UDWorkflowErrorUnknownElement,
			[NSString stringWithFormat:@"%@ cannot be executed", node.elementId])];
	}
}

#pragma mark - Events

- (void)executeEvent:(UDEvent *)event execution:(UDExecutionEntity *)execution
{
	switch (event.kind) {
	case UDEventKindStart:
		/* However the instance was started, it has been. */
		[self leave:event execution:execution];
		return;
	case UDEventKindIntermediateThrow:
		if (event.trigger == UDEventTriggerMessage) {
			[self throwMessage:event execution:execution];
		}
		[self leave:event execution:execution];
		return;
	case UDEventKindEnd:
		if (event.trigger == UDEventTriggerMessage) {
			[self throwMessage:event execution:execution];
		}
		[self endPath:execution];
		return;
	case UDEventKindIntermediateCatch:
		if (event.trigger == UDEventTriggerMessage) {
			[self subscribe:execution message:event.messageName activity:event.elementId];
		} else if (event.trigger == UDEventTriggerTimer) {
			[self timer:execution activity:event.elementId duration:event.timerDuration];
		} else {
			[self leave:event execution:execution];
		}
		return;
	case UDEventKindBoundary:
		[self fail:UDCommandError(UDWorkflowErrorInvalidDefinition,
			[NSString stringWithFormat:@"boundary event %@ has an incoming flow",
				event.elementId])];
		return;
	}
}

- (void)throwMessage:(UDEvent *)event execution:(UDExecutionEntity *)execution
{
	NSString *name = event.messageName;
	NSDictionary *variables = [self visibleVariables:execution];
	NSString *processInstanceId = execution.processInstanceId;
	UDProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine ud_messageThrown:name variables:variables processInstanceId:processInstanceId];
	}];
}

- (void)subscribe:(UDExecutionEntity *)execution
          message:(NSString *)messageName
         activity:(NSString *)activityId
{
	UDEventSubscriptionEntity *subscription = [self insert:UDSubscriptionName];
	subscription.subscriptionId = [UDCommandContext newId];
	subscription.eventType = UDEventTypeMessage;
	subscription.eventName = messageName;
	subscription.activityId = activityId;
	subscription.processInstanceId = execution.processInstanceId;
	subscription.createdAt = [NSDate date];
	subscription.execution = execution;
}

- (void)timer:(UDExecutionEntity *)execution
     activity:(NSString *)activityId
     duration:(NSTimeInterval)duration
{
	UDJobEntity *job = [self insert:UDJobName];
	job.jobId = [UDCommandContext newId];
	job.jobType = UDJobTypeTimer;
	job.activityId = activityId;
	job.processInstanceId = execution.processInstanceId;
	job.dueDate = [NSDate dateWithTimeIntervalSinceNow:duration > 0 ? duration : 0];
	job.createdAt = [NSDate date];
	job.retries = 3;
	job.exclusive = YES;
	job.execution = execution;
	NSString *jobId = job.jobId;
	NSString *processInstanceId = job.processInstanceId;
	NSDate *due = job.dueDate;
	UDProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine ud_jobCreated:jobId processInstanceId:processInstanceId dueDate:due];
	}];
}

- (void)deliverSubscription:(UDEventSubscriptionEntity *)subscription
                  variables:(NSDictionary *)variables
{
	UDExecutionEntity *execution = subscription.execution;
	UDFlowNode *node = [self node:subscription.activityId of:execution];
	if (node == nil || ![self setVariables:variables from:execution]) {
		return;
	}
	[self event:(UDEvent *)node triggeredOn:execution subscription:subscription];
}

- (void)fireTimer:(UDJobEntity *)job
{
	UDExecutionEntity *execution = job.execution;
	UDFlowNode *node = [self node:job.activityId of:execution];
	[self remove:job];
	if (node != nil) {
		[self event:(UDEvent *)node triggeredOn:execution subscription:nil];
	}
}

- (void)event:(UDEvent *)event
  triggeredOn:(UDExecutionEntity *)execution
 subscription:(UDEventSubscriptionEntity *)subscription
{
	if (event.kind == UDEventKindBoundary) {
		[self boundary:event firedOn:execution subscription:subscription];
		return;
	}
	UDFlowNode *at = [self node:execution.activityId of:execution];
	if ([at isKindOfClass:[UDGateway class]]
	    && [(UDGateway *)at kind] == UDGatewayKindEventBased) {
		/* The first event behind an event-based gateway wins; the others
		 * stop waiting. */
		for (NSManagedObject *other in [execution.eventSubscriptions allObjects]) {
			[self remove:other];
		}
		for (NSManagedObject *other in [execution.jobs allObjects]) {
			[self remove:other];
		}
		execution.activityId = event.elementId;
		execution.activityInstanceId = [UDCommandContext newId];
	} else if (subscription != nil) {
		[self remove:subscription];
	}
	[self leave:event execution:execution];
}

/* inner is the scope execution of the activity the boundary event is on. */
- (void)boundary:(UDEvent *)boundary
         firedOn:(UDExecutionEntity *)inner
    subscription:(UDEventSubscriptionEntity *)subscription
{
	UDExecutionEntity *host = inner.parent;
	if (boundary.isInterrupting) {
		[self remove:inner];
		host.isActive = YES;
		host.activityId = boundary.elementId;
		host.activityInstanceId = [UDCommandContext newId];
		[self leave:boundary execution:host];
		return;
	}
	/* Non-interrupting: the activity goes on, and the boundary's flow runs
	 * beside it. A message boundary stays armed; a timer has fired. */
	UDExecutionEntity *path = nil;
	if (host.isConcurrent) {
		path = [self newChildOf:host.parent concurrent:YES];
	} else {
		/* The host path becomes one of two concurrent paths. */
		UDExecutionEntity *moved = [self newChildOf:host concurrent:YES];
		moved.activityId = host.activityId;
		moved.activityInstanceId = host.activityInstanceId;
		moved.isActive = NO;
		inner.parent = moved;
		host.activityId = nil;
		host.activityInstanceId = nil;
		host.isActive = NO;
		path = [self newChildOf:host concurrent:YES];
	}
	path.activityId = boundary.elementId;
	path.activityInstanceId = [UDCommandContext newId];
	[self leave:boundary execution:path];
}

- (void)throwBpmnError:(NSString *)errorCode fromExecution:(UDExecutionEntity *)execution
{
	UDFlowNode *node = [self node:execution.activityId of:execution];
	if (node == nil) {
		return;
	}
	UDProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	UDEvent *catcher = nil;
	UDEvent *catchAll = nil;
	for (UDEvent *boundary in [scope boundaryEventsAttachedTo:node.elementId]) {
		if (boundary.trigger != UDEventTriggerError) {
			continue;
		}
		NSString *ref = boundary.errorRef;
		if (ref == nil || [ref length] == 0 || [ref isEqualToString:@"*"]) {
			catchAll = catchAll ?: boundary;
		} else if ([ref isEqualToString:errorCode] && catcher == nil) {
			catcher = boundary;
		}
	}
	catcher = catcher ?: catchAll;
	BOOL activityScope = [self isActivityScope:execution node:node];
	if (catcher != nil && activityScope) {
		[self boundary:catcher firedOn:execution subscription:nil];
		return;
	}
	/* Nothing catches it: the path ends, as the reference does by default. */
	if (activityScope) {
		UDExecutionEntity *host = execution.parent;
		[self remove:execution];
		[self endPath:host];
	} else {
		[self endPath:execution];
	}
}

#pragma mark - Tasks

- (void)executeTask:(UDTask *)task execution:(UDExecutionEntity *)execution
{
	if (task.kind == UDTaskKindUser) {
		UDTaskEntity *row = [self insert:UDTaskName];
		row.taskId = [UDCommandContext newId];
		row.name = task.name;
		row.taskDefinitionKey = task.elementId;
		row.assignee = task.assignee;
		row.processInstanceId = execution.processInstanceId;
		row.definitionId = execution.definitionId;
		row.activityInstanceId = execution.activityInstanceId;
		row.createdAt = [NSDate date];
		row.priority = 50;
		row.execution = execution;
		UDWorkItem *value = [UDWorkItem ud_workItemWithEntity:row];
		UDProcessEngine *engine = self.engine;
		[self afterCommit:^{
			[engine ud_taskCreated:value];
		}];
		return;
	}
	/* Service and script tasks are external tasks under the action's
	 * topic. */
	UDExternalTaskEntity *row = [self insert:UDExternalTaskName];
	row.externalTaskId = [UDCommandContext newId];
	row.topic = task.actionKey ?: task.elementId;
	row.activityId = task.elementId;
	row.activityInstanceId = execution.activityInstanceId;
	row.processInstanceId = execution.processInstanceId;
	row.createdAt = [NSDate date];
	row.execution = execution;
	NSString *externalTaskId = row.externalTaskId;
	NSString *processInstanceId = row.processInstanceId;
	UDProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine ud_externalTaskCreated:externalTaskId processInstanceId:processInstanceId];
	}];
}

- (void)completeActivity:(UDExecutionEntity *)execution
{
	UDFlowNode *node = [self node:execution.activityId of:execution];
	if (node == nil) {
		return;
	}
	if ([self isActivityScope:execution node:node]) {
		UDExecutionEntity *host = execution.parent;
		[self remove:execution];
		host.isActive = YES;
		[self leave:node execution:host];
		return;
	}
	[self leave:node execution:execution];
}

#pragma mark - Leaving and ending

- (BOOL)condition:(UDSequenceFlow *)flow holdsFor:(UDExecutionEntity *)execution
             error:(NSError **)error
{
	id condition = flow.condition;
	if (condition == nil) {
		return YES;
	}
	NSError *conditionError = nil;
	BOOL holds = [condition evaluateWithVariables:[self visibleVariables:execution]
	                                        error:&conditionError];
	if (conditionError != nil && error != NULL) {
		*error = conditionError;
	}
	return holds;
}

/* Leaves an activity or event along every outgoing flow whose condition
 * holds; several flows are an implicit parallel split. */
- (void)leave:(UDFlowNode *)node execution:(UDExecutionEntity *)execution
{
	UDProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	NSMutableArray *flows = [NSMutableArray array];
	for (UDSequenceFlow *flow in [scope outgoingFlowsFrom:node.elementId]) {
		NSError *error = nil;
		BOOL holds = [self condition:flow holdsFor:execution error:&error];
		if (error != nil) {
			[self fail:error];
			return;
		}
		if (holds) {
			[flows addObject:flow];
		}
	}
	[self take:flows scope:scope execution:execution];
}

- (void)take:(NSArray<UDSequenceFlow *> *)flows
       scope:(UDProcessDefinition *)scope
   execution:(UDExecutionEntity *)execution
{
	if ([flows count] == 0) {
		[self endPath:execution];
		return;
	}
	NSMutableArray *paths = [NSMutableArray array];
	if ([flows count] == 1) {
		[paths addObject:execution];
	} else if (execution.isConcurrent) {
		[paths addObject:execution];
		for (NSUInteger i = 1; i < [flows count]; i++) {
			[paths addObject:[self newChildOf:execution.parent concurrent:YES]];
		}
	} else {
		/* The scope's single path splits: the scope execution steps back
		 * and holds one concurrent child per path. */
		execution.isActive = NO;
		execution.activityId = nil;
		execution.activityInstanceId = nil;
		for (NSUInteger i = 0; i < [flows count]; i++) {
			[paths addObject:[self newChildOf:execution concurrent:YES]];
		}
	}
	for (NSUInteger i = 0; i < [flows count]; i++) {
		UDFlowNode *target = [scope nodeWithId:[[flows objectAtIndex:i] targetId]];
		UDExecutionEntity *path = [paths objectAtIndex:i];
		[self schedule:^{
			[self enter:target execution:path];
		}];
	}
}

- (void)endPath:(UDExecutionEntity *)execution
{
	if (!execution.isConcurrent) {
		[self scopeEnded:execution];
		return;
	}
	UDExecutionEntity *level = execution.parent;
	[self remove:execution];
	NSArray *paths = [level concurrentChildren];
	if ([paths count] == 0) {
		[self scopeEnded:level];
		return;
	}
	if ([paths count] == 1) {
		[self compact:level into:[paths objectAtIndex:0]];
	}
	/* A path fewer may be what an inclusive join was waiting for. */
	[self retryInclusiveJoinsAt:level];
}

/* The scope has one path left: the scope execution takes it over again. */
- (void)compact:(UDExecutionEntity *)level into:(UDExecutionEntity *)path
{
	level.activityId = path.activityId;
	level.activityInstanceId = path.activityInstanceId;
	level.isActive = path.isActive;
	for (UDExecutionEntity *child in [path.children allObjects]) {
		child.parent = level;
	}
	for (UDTaskEntity *task in [path.tasks allObjects]) {
		task.execution = level;
	}
	for (UDEventSubscriptionEntity *subscription in [path.eventSubscriptions allObjects]) {
		subscription.execution = level;
	}
	for (UDJobEntity *job in [path.jobs allObjects]) {
		job.execution = level;
	}
	for (UDExternalTaskEntity *externalTask in [path.externalTasks allObjects]) {
		externalTask.execution = level;
	}
	[self remove:path];
}

- (void)scopeEnded:(UDExecutionEntity *)scopeExecution
{
	if (scopeExecution.parent == nil) {
		[self processInstanceEnded:scopeExecution];
		return;
	}
	/* An embedded subprocess has run to its end: its host path leaves it. */
	UDExecutionEntity *host = scopeExecution.parent;
	UDFlowNode *node = [self node:host.activityId of:host];
	[self remove:scopeExecution];
	host.isActive = YES;
	if (node != nil) {
		[self leave:node execution:host];
	}
}

- (void)processInstanceEnded:(UDExecutionEntity *)root
{
	UDHistoricProcessInstanceEntity *history = [[self fetch:UDHistoricInstanceName
	                                              predicate:[NSPredicate predicateWithFormat:
	                                                  @"processInstanceId == %@",
	                                                  root.processInstanceId]
	                                                   sort:nil
	                                                  limit:1] lastObject];
	history.endTime = [NSDate date];
	history.state = UDHistoricStateCompleted;
	UDProcessInstance *value = [UDProcessInstance ud_instanceWithExecution:root
		definition:[self definitionForExecution:root]
		ended:YES];
	[self remove:root];
	UDProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine ud_processInstanceEnded:value];
	}];
}

#pragma mark - Gateways

- (UDSequenceFlow *)chooseExclusive:(UDGateway *)gateway
                              scope:(UDProcessDefinition *)scope
                          execution:(UDExecutionEntity *)execution
{
	UDSequenceFlow *fallback = nil;
	for (UDSequenceFlow *flow in [self ordered:[scope outgoingFlowsFrom:gateway.elementId] scope:scope]) {
		if (flow.isDefaultFlow || [flow.elementId isEqualToString:gateway.defaultFlowId]) {
			fallback = flow;
			continue;
		}
		NSError *error = nil;
		BOOL holds = [self condition:flow holdsFor:execution error:&error];
		if (error != nil) {
			[self fail:error];
			return nil;
		}
		if (holds) {
			return flow;
		}
	}
	if (fallback == nil) {
		[self fail:UDCommandError(UDWorkflowErrorNoPath,
			[NSString stringWithFormat:@"exclusive gateway %@ matched no outgoing flow",
				gateway.elementId])];
	}
	return fallback;
}

- (NSArray *)chooseInclusive:(UDGateway *)gateway
                       scope:(UDProcessDefinition *)scope
                   execution:(UDExecutionEntity *)execution
{
	NSMutableArray *taken = [NSMutableArray array];
	UDSequenceFlow *fallback = nil;
	for (UDSequenceFlow *flow in [self ordered:[scope outgoingFlowsFrom:gateway.elementId] scope:scope]) {
		if (flow.isDefaultFlow || [flow.elementId isEqualToString:gateway.defaultFlowId]) {
			fallback = flow;
			continue;
		}
		NSError *error = nil;
		BOOL holds = [self condition:flow holdsFor:execution error:&error];
		if (error != nil) {
			[self fail:error];
			return nil;
		}
		if (holds) {
			[taken addObject:flow];
		}
	}
	if ([taken count] == 0 && fallback != nil) {
		[taken addObject:fallback];
	}
	if ([taken count] == 0) {
		[self fail:UDCommandError(UDWorkflowErrorNoPath,
			[NSString stringWithFormat:@"inclusive gateway %@ matched no outgoing flow",
				gateway.elementId])];
		return nil;
	}
	return taken;
}

/* Outgoing flows in document order, so the first matching condition of an
 * exclusive gateway is well defined. */
- (NSArray *)ordered:(NSArray<UDSequenceFlow *> *)flows scope:(UDProcessDefinition *)scope
{
	return [flows sortedArrayUsingComparator:^NSComparisonResult(UDSequenceFlow *a, UDSequenceFlow *b) {
		NSUInteger ia = [scope.flowOrder indexOfObject:a.elementId];
		NSUInteger ib = [scope.flowOrder indexOfObject:b.elementId];
		return ia < ib ? NSOrderedAscending : ia > ib ? NSOrderedDescending : NSOrderedSame;
	}];
}

- (void)executeGateway:(UDGateway *)gateway
                 scope:(UDProcessDefinition *)scope
             execution:(UDExecutionEntity *)execution
{
	NSArray *incoming = [scope incomingFlowsTo:gateway.elementId];
	NSArray *outgoing = [scope outgoingFlowsFrom:gateway.elementId];
	switch (gateway.kind) {
	case UDGatewayKindExclusive: {
		UDSequenceFlow *flow = [self chooseExclusive:gateway scope:scope execution:execution];
		if (flow != nil) {
			[self take:@[ flow ] scope:scope execution:execution];
		}
		return;
	}
	case UDGatewayKindParallel:
		if ([incoming count] > 1) {
			[self joinParallel:gateway incoming:[incoming count] scope:scope execution:execution];
		} else {
			[self take:outgoing scope:scope execution:execution];
		}
		return;
	case UDGatewayKindInclusive:
		if ([incoming count] > 1) {
			execution.isActive = NO;
			UDExecutionEntity *level = [self levelOf:execution];
			level.lockRevision += 1;
			[self tryInclusiveJoin:gateway scope:scope level:level];
		} else {
			NSArray *flows = [self chooseInclusive:gateway scope:scope execution:execution];
			if (flows != nil) {
				[self take:flows scope:scope execution:execution];
			}
		}
		return;
	case UDGatewayKindEventBased:
		for (UDSequenceFlow *flow in outgoing) {
			UDFlowNode *target = [scope nodeWithId:flow.targetId];
			UDEvent *event = [target isKindOfClass:[UDEvent class]] ? (UDEvent *)target : nil;
			if (event.kind == UDEventKindIntermediateCatch
			    && event.trigger == UDEventTriggerMessage) {
				[self subscribe:execution message:event.messageName activity:event.elementId];
			} else if (event.kind == UDEventKindIntermediateCatch
			           && event.trigger == UDEventTriggerTimer) {
				[self timer:execution activity:event.elementId duration:event.timerDuration];
			} else {
				[self fail:UDCommandError(UDWorkflowErrorInvalidDefinition,
					[NSString stringWithFormat:
						@"event-based gateway %@ may only be followed by message or timer catch events",
						gateway.elementId])];
				return;
			}
		}
		return;
	}
}

- (NSArray<UDExecutionEntity *> *)waitingAt:(UDGateway *)gateway level:(UDExecutionEntity *)level
{
	NSMutableArray *waiting = [NSMutableArray array];
	for (UDExecutionEntity *path in [self pathsAt:level]) {
		if (!path.isActive && [path.activityId isEqualToString:gateway.elementId]) {
			[waiting addObject:path];
		}
	}
	return waiting;
}

/* After a join removed the other arrivals: one path left folds back into
 * its scope execution, which carries on. */
- (UDExecutionEntity *)continueAfterJoin:(UDExecutionEntity *)survivor
                                   level:(UDExecutionEntity *)level
{
	survivor.isActive = YES;
	if (survivor.isConcurrent && [[level concurrentChildren] count] == 1) {
		[self compact:level into:survivor];
		return level;
	}
	return survivor;
}

- (void)joinParallel:(UDGateway *)gateway
            incoming:(NSUInteger)incoming
               scope:(UDProcessDefinition *)scope
           execution:(UDExecutionEntity *)execution
{
	execution.isActive = NO;
	UDExecutionEntity *level = [self levelOf:execution];
	/* Every arrival updates the scope execution, so two commands arriving
	 * at once conflict instead of each missing the other. */
	level.lockRevision += 1;
	NSArray *waiting = [self waitingAt:gateway level:level];
	if ([waiting count] < incoming) {
		return;
	}
	NSUInteger joined = 1;
	for (UDExecutionEntity *other in waiting) {
		if (other != execution && joined < incoming) {
			[self remove:other];
			joined += 1;
		}
	}
	UDExecutionEntity *path = [self continueAfterJoin:execution level:level];
	[self take:[scope outgoingFlowsFrom:gateway.elementId] scope:scope execution:path];
}

/* Can a path at from still arrive at the gateway? Follows sequence flows
 * and the flows of boundary events on the way. */
- (BOOL)canReach:(NSString *)target from:(NSString *)from scope:(UDProcessDefinition *)scope
{
	if (from == nil) {
		return NO;
	}
	NSMutableSet *seen = [NSMutableSet setWithObject:from];
	NSMutableArray *queue = [NSMutableArray arrayWithObject:from];
	while ([queue count] > 0) {
		NSString *current = [queue objectAtIndex:0];
		[queue removeObjectAtIndex:0];
		NSMutableArray *sources = [NSMutableArray arrayWithObject:current];
		for (UDEvent *boundary in [scope boundaryEventsAttachedTo:current]) {
			[sources addObject:boundary.elementId];
		}
		for (NSString *source in sources) {
			for (UDSequenceFlow *flow in [scope outgoingFlowsFrom:source]) {
				if ([flow.targetId isEqualToString:target]) {
					return YES;
				}
				if (![seen containsObject:flow.targetId]) {
					[seen addObject:flow.targetId];
					[queue addObject:flow.targetId];
				}
			}
		}
	}
	return NO;
}

- (void)tryInclusiveJoin:(UDGateway *)gateway
                   scope:(UDProcessDefinition *)scope
                   level:(UDExecutionEntity *)level
{
	NSArray *waiting = [self waitingAt:gateway level:level];
	if ([waiting count] == 0) {
		return;
	}
	for (UDExecutionEntity *path in [self pathsAt:level]) {
		if (![waiting containsObject:path]
		    && [self canReach:gateway.elementId from:path.activityId scope:scope]) {
			return;
		}
	}
	UDExecutionEntity *survivor = [waiting objectAtIndex:0];
	for (UDExecutionEntity *other in waiting) {
		if (other != survivor) {
			[self remove:other];
		}
	}
	UDExecutionEntity *path = [self continueAfterJoin:survivor level:level];
	NSArray *flows = [self chooseInclusive:gateway scope:scope execution:path];
	if (flows != nil) {
		[self take:flows scope:scope execution:path];
	}
}

- (void)retryInclusiveJoinsAt:(UDExecutionEntity *)level
{
	NSMutableSet *gateways = [NSMutableSet set];
	for (UDExecutionEntity *path in [self pathsAt:level]) {
		if (path.isActive || path.activityId == nil) {
			continue;
		}
		UDFlowNode *node = [self node:path.activityId of:path];
		if ([node isKindOfClass:[UDGateway class]]
		    && [(UDGateway *)node kind] == UDGatewayKindInclusive) {
			[gateways addObject:node.elementId];
		}
	}
	for (NSString *gatewayId in gateways) {
		UDGateway *gateway = (UDGateway *)[self node:gatewayId of:level];
		UDProcessDefinition *scope = [self scopeOf:gatewayId execution:level];
		[self schedule:^{
			[self tryInclusiveJoin:gateway scope:scope level:level];
		}];
	}
}

#pragma mark - Variables

- (NSDictionary *)visibleVariables:(UDExecutionEntity *)execution
{
	NSMutableDictionary *variables = [NSMutableDictionary dictionary];
	for (UDExecutionEntity *scope = execution; scope != nil; scope = scope.parent) {
		for (UDVariableEntity *variable in scope.variables) {
			if (![variable isDeleted] && [variables objectForKey:variable.name] == nil) {
				id value = [variable ud_value];
				[variables setObject:value ?: [NSNull null] forKey:variable.name];
			}
		}
	}
	return variables;
}

- (void)recordHistoryOf:(UDVariableEntity *)variable
{
	UDHistoricVariableEntity *history = [_historicVariables objectForKey:variable.variableId];
	if (history == nil) {
		history = [[self fetch:UDHistoricVariableName
		             predicate:[NSPredicate predicateWithFormat:@"variableId == %@",
		                 variable.variableId]
		                  sort:nil
		                 limit:1] lastObject];
	}
	if (history == nil) {
		history = [self insert:UDHistoricVariableName];
		history.variableId = variable.variableId;
		history.name = variable.name;
		history.processInstanceId = variable.processInstanceId;
		history.scopeIsProcessInstance = variable.execution.parent == nil;
	}
	[_historicVariables setObject:history forKey:variable.variableId];
	[history ud_setValue:[variable ud_value]];
	history.updatedAt = [NSDate date];
}

- (BOOL)setVariables:(NSDictionary *)variables from:(UDExecutionEntity *)execution
{
	for (NSString *name in variables) {
		id value = [variables objectForKey:name];
		UDVariableEntity *variable = nil;
		for (UDExecutionEntity *scope = execution; scope != nil && variable == nil;
		     scope = scope.parent) {
			variable = [scope localVariableNamed:name];
		}
		if (variable == nil) {
			UDExecutionEntity *root = [execution processInstance];
			variable = [self insert:UDVariableName];
			variable.variableId = [UDCommandContext newId];
			variable.name = name;
			variable.processInstanceId = root.processInstanceId;
			variable.execution = root;
		}
		if (![variable ud_setValue:value]) {
			[self fail:UDCommandError(UDWorkflowErrorInvalidState,
				[NSString stringWithFormat:@"variable %@ is not a value the engine stores",
					name])];
			return NO;
		}
		[self recordHistoryOf:variable];
	}
	return YES;
}

@end

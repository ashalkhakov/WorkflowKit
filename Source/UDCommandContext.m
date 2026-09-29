#import "UDCommandContext.h"
#import "UDEntities.h"
#import "UDProcessEngine+Internal.h"
#import "UDFlowElements.h"
#import "UDProcessDefinition.h"
#import "UDCondition.h"
#import "UDDuration.h"

static NSString * const UDExecutionName = @"UDExecution";
static NSString * const UDVariableName = @"UDVariable";
static NSString * const UDTaskName = @"UDTask";
static NSString * const UDSubscriptionName = @"UDEventSubscription";
static NSString * const UDJobName = @"UDJob";
static NSString * const UDExternalTaskName = @"UDExternalTask";
static NSString * const UDIncidentName = @"UDIncident";
static NSString * const UDHistoricInstanceName = @"UDHistoricProcessInstance";
static NSString * const UDHistoricVariableName = @"UDHistoricVariable";
static NSString * const UDHistoricActivityName = @"UDHistoricActivityInstance";
static NSString * const UDHistoricTaskName = @"UDHistoricTaskInstance";
static NSString * const UDHistoricUpdateName = @"UDHistoricVariableUpdate";
static NSString * const UDHistoricIncidentName = @"UDHistoricIncident";
static NSString * const UDHistoricJobLogName = @"UDHistoricJobLog";

/* The BPMN element a node is, as history names activity types. */
static NSString *
UDActivityType(UDFlowNode *node)
{
	if ([node isKindOfClass:[UDEvent class]]) {
		switch ([(UDEvent *)node kind]) {
		case UDEventKindStart: return @"startEvent";
		case UDEventKindEnd: return @"endEvent";
		case UDEventKindIntermediateCatch: return @"intermediateCatchEvent";
		case UDEventKindIntermediateThrow: return @"intermediateThrowEvent";
		case UDEventKindBoundary: return @"boundaryEvent";
		}
	}
	if ([node isKindOfClass:[UDTask class]]) {
		switch ([(UDTask *)node kind]) {
		case UDTaskKindUser: return @"userTask";
		case UDTaskKindService: return @"serviceTask";
		case UDTaskKindScript: return @"scriptTask";
		}
	}
	if ([node isKindOfClass:[UDGateway class]]) {
		switch ([(UDGateway *)node kind]) {
		case UDGatewayKindExclusive: return @"exclusiveGateway";
		case UDGatewayKindParallel: return @"parallelGateway";
		case UDGatewayKindInclusive: return @"inclusiveGateway";
		case UDGatewayKindEventBased: return @"eventBasedGateway";
		}
	}
	if ([node isKindOfClass:[UDCallActivity class]]) {
		return @"callActivity";
	}
	return [node isKindOfClass:[UDSubProcess class]] ? @"subProcess" : @"activity";
}

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
	NSMutableDictionary *_openActivities;
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
		_openActivities = [NSMutableDictionary dictionary];
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

/* Removed since the operation was scheduled: a terminate end event or an
 * interruption took it away. Its operations have nothing left to do. */
static BOOL
UDGone(NSManagedObject *object)
{
	return [object isDeleted] || [object managedObjectContext] == nil;
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
	return [self startProcessInstance:definition businessKey:businessKey variables:variables
	                       startEvent:startEvent superExecution:nil];
}

- (UDExecutionEntity *)startProcessInstance:(UDProcessDefinition *)definition
                                businessKey:(NSString *)businessKey
                                  variables:(NSDictionary *)variables
                                 startEvent:(UDEvent *)startEvent
                             superExecution:(UDExecutionEntity *)superExecution
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
	root.superExecution = superExecution;
	root.superProcessInstanceId = superExecution.processInstanceId;

	UDHistoricProcessInstanceEntity *history =
		[self records:UDHistoryLevelActivity] ? [self insert:UDHistoricInstanceName] : nil;
	history.processInstanceId = root.processInstanceId;
	history.businessKey = businessKey;
	history.definitionId = definition.definitionId;
	history.definitionKey = definition.processId;
	history.startTime = [NSDate date];
	history.state = UDHistoricStateActive;
	history.superProcessInstanceId = root.superProcessInstanceId;

	if (![self setVariables:variables from:root]) {
		return nil;
	}
	[self schedule:^{
		if (!UDGone(root)) {
			[self enter:start execution:root];
		}
	}];
	return root;
}

- (BOOL)isScopeActivity:(UDFlowNode *)node scope:(UDProcessDefinition *)scope
{
	if ([node isKindOfClass:[UDSubProcess class]]) {
		return YES;
	}
	return ([node isKindOfClass:[UDTask class]] || [node isKindOfClass:[UDCallActivity class]])
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
	if (node.isAsyncBefore) {
		/* The command stops here; a job enters the node. */
		execution.activityId = node.elementId;
		execution.activityInstanceId = [UDCommandContext newId];
		execution.isActive = YES;
		[self job:UDJobTypeAsyncBefore execution:execution node:node due:[NSDate date]];
		return;
	}
	[self enterNow:node execution:execution];
}

- (void)enterNow:(UDFlowNode *)node execution:(UDExecutionEntity *)execution
{
	UDProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	execution.activityId = node.elementId;
	execution.activityInstanceId = [UDCommandContext newId];
	execution.isActive = YES;
	[self activityStarted:node execution:execution];
	if (![self isScopeActivity:node scope:scope]) {
		[self execute:node scope:scope execution:execution];
		return;
	}
	/* A scope activity runs in a child scope execution: its boundary
	 * subscriptions and timers hang there, and interrupting it removes
	 * exactly that subtree. */
	UDExecutionEntity *inner = [self newChildOf:execution concurrent:NO];
	execution.isActive = NO;
	for (UDEvent *boundary in [scope boundaryEventsAttachedTo:node.elementId]) {
		if (boundary.trigger == UDEventTriggerMessage) {
			[self subscribe:inner message:boundary.messageName activity:boundary.elementId];
		} else if (boundary.trigger == UDEventTriggerSignal) {
			[self subscribe:inner type:UDEventTypeSignal name:boundary.signalName
			       activity:boundary.elementId];
		} else if (boundary.trigger == UDEventTriggerTimer) {
			[self timer:inner activity:boundary.elementId duration:boundary.timerDuration];
		}
	}
	if ([node isKindOfClass:[UDSubProcess class]]) {
		UDEvent *start = [[(UDSubProcess *)node innerDefinition] startEvent];
		[self schedule:^{
			if (!UDGone(inner)) {
				[self enter:start execution:inner];
			}
		}];
		return;
	}
	inner.activityId = node.elementId;
	inner.activityInstanceId = execution.activityInstanceId;
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
	} else if ([node isKindOfClass:[UDCallActivity class]]) {
		[self executeCall:(UDCallActivity *)node execution:execution];
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
		} else if (event.trigger == UDEventTriggerSignal) {
			[self broadcastSignal:event.signalName variables:nil processInstanceId:nil];
		}
		[self leave:event execution:execution];
		return;
	case UDEventKindEnd:
		if (event.trigger == UDEventTriggerTerminate) {
			[self terminate:execution];
			return;
		}
		if (event.trigger == UDEventTriggerMessage) {
			[self throwMessage:event execution:execution];
		} else if (event.trigger == UDEventTriggerSignal) {
			[self broadcastSignal:event.signalName variables:nil processInstanceId:nil];
		}
		[self activityEnded:execution.activityInstanceId canceled:NO];
		[self endPath:execution];
		return;
	case UDEventKindIntermediateCatch:
		if (event.trigger == UDEventTriggerMessage) {
			[self subscribe:execution message:event.messageName activity:event.elementId];
		} else if (event.trigger == UDEventTriggerSignal) {
			[self subscribe:execution type:UDEventTypeSignal name:event.signalName
			       activity:event.elementId];
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
	[self subscribe:execution type:UDEventTypeMessage name:messageName activity:activityId];
}

- (void)subscribe:(UDExecutionEntity *)execution
             type:(NSString *)eventType
             name:(NSString *)eventName
         activity:(NSString *)activityId
{
	UDEventSubscriptionEntity *subscription = [self insert:UDSubscriptionName];
	subscription.subscriptionId = [UDCommandContext newId];
	subscription.eventType = eventType;
	subscription.eventName = eventName;
	subscription.activityId = activityId;
	subscription.processInstanceId = execution.processInstanceId;
	subscription.createdAt = [NSDate date];
	subscription.execution = execution;
}

- (void)timer:(UDExecutionEntity *)execution
     activity:(NSString *)activityId
     duration:(NSTimeInterval)duration
{
	[self job:UDJobTypeTimer
	execution:execution
	     node:[self node:activityId of:execution]
	      due:[NSDate dateWithTimeIntervalSinceNow:duration > 0 ? duration : 0]];
}

/* A job on the node for the execution. Its attempts come from the node's
 * retry cycle; the engine is told once the command commits. */
- (void)job:(NSString *)type
  execution:(UDExecutionEntity *)execution
       node:(UDFlowNode *)node
        due:(NSDate *)due
{
	NSInteger attempts = UD_DEFAULT_ATTEMPTS;
	NSArray *delays = nil;
	UDParseRetryCycle(node.retryTimeCycle, &attempts, &delays);
	UDJobEntity *job = [self insert:UDJobName];
	job.jobId = [UDCommandContext newId];
	job.jobType = type;
	job.activityId = node.elementId;
	job.processInstanceId = execution.processInstanceId;
	job.dueDate = due;
	job.createdAt = [NSDate date];
	job.retries = (int32_t)attempts;
	job.exclusive = node.isExclusive;
	job.execution = execution;
	[self historyJob:job state:UDJobLogStateCreated];
	NSString *jobId = job.jobId;
	NSString *processInstanceId = job.processInstanceId;
	BOOL exclusive = job.exclusive;
	UDProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine ud_jobCreated:jobId
		    processInstanceId:processInstanceId
		              dueDate:due
		            exclusive:exclusive];
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

- (void)runJob:(UDJobEntity *)job
{
	[self historyJob:job state:UDJobLogStateSuccessful];
	NSString *type = job.jobType;
	if ([type isEqualToString:UDJobTypeTimerStart]) {
		NSError *error = nil;
		UDProcessDefinition *definition =
			[self.engine.repositoryService definitionWithId:job.definitionId error:&error];
		UDFlowNode *start = [definition flowNodeWithId:job.activityId];
		[self remove:job];
		if (definition == nil || ![start isKindOfClass:[UDEvent class]]) {
			[self fail:error ?: UDCommandError(UDWorkflowErrorInvalidDefinition,
				@"the timer start event is gone from its definition")];
			return;
		}
		[self startProcessInstance:definition businessKey:nil variables:nil
		                startEvent:(UDEvent *)start];
		return;
	}
	UDExecutionEntity *execution = job.execution;
	UDFlowNode *node = [self node:job.activityId of:execution];
	[self remove:job];
	if (node == nil) {
		return;
	}
	BOOL boundary = [node isKindOfClass:[UDEvent class]]
		&& [(UDEvent *)node kind] == UDEventKindBoundary;
	if ([type isEqualToString:UDJobTypeAsyncBefore] && boundary) {
		/* The boundary fired in an earlier command; its path now passes
		 * the event. */
		execution.activityInstanceId = [UDCommandContext newId];
		[self activityStarted:node execution:execution];
		[self leave:node execution:execution];
	} else if ([type isEqualToString:UDJobTypeAsyncBefore]) {
		[self enterNow:node execution:execution];
	} else if ([type isEqualToString:UDJobTypeAsyncAfter] && [node isKindOfClass:[UDGateway class]]) {
		[self departNow:(UDGateway *)node
		          scope:[self scopeOf:node.elementId execution:execution]
		      execution:execution];
	} else if ([type isEqualToString:UDJobTypeAsyncAfter]) {
		[self leaveNow:node execution:execution];
	} else {
		[self event:(UDEvent *)node triggeredOn:execution subscription:nil];
	}
}

- (void)raiseIncident:(NSString *)type
        configuration:(NSString *)configuration
              message:(NSString *)message
           activityId:(NSString *)activityId
    processInstanceId:(NSString *)processInstanceId
            execution:(UDExecutionEntity *)execution
{
	UDIncidentEntity *incident = [self insert:UDIncidentName];
	incident.incidentId = [UDCommandContext newId];
	incident.incidentType = type;
	incident.configuration = configuration;
	incident.message = message;
	incident.activityId = activityId;
	incident.processInstanceId = processInstanceId;
	incident.createdAt = [NSDate date];
	incident.execution = execution;
	if ([self records:UDHistoryLevelFull]) {
		UDHistoricIncidentEntity *row = [self insert:UDHistoricIncidentName];
		row.incidentId = incident.incidentId;
		row.incidentType = type;
		row.configuration = configuration;
		row.message = message;
		row.activityId = activityId;
		row.processInstanceId = processInstanceId;
		row.createdAt = incident.createdAt;
		row.state = UDIncidentStateOpen;
	}
}

- (void)resolveIncidentsFor:(NSString *)configuration
{
	for (UDIncidentEntity *incident in [self fetch:UDIncidentName
	                                     predicate:[NSPredicate predicateWithFormat:
	                                         @"configuration == %@", configuration]
	                                          sort:nil
	                                         limit:0]) {
		[self incident:incident.incidentId endedAs:UDIncidentStateResolved];
		[self remove:incident];
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
		for (UDJobEntity *other in [execution.jobs allObjects]) {
			[self historyJob:other state:UDJobLogStateDeleted];
			[self remove:other];
		}
		[self activityEnded:execution.activityInstanceId canceled:NO];
		execution.activityId = event.elementId;
		execution.activityInstanceId = [UDCommandContext newId];
		[self activityStarted:event execution:execution];
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
		[self cancelSubtree:inner];
		/* The interrupted activity's own instance: the host's, which for a
		 * subprocess is not the scope's. */
		[self activityEnded:host.activityInstanceId canceled:YES];
		[self remove:inner];
		host.isActive = YES;
		[self pass:boundary on:host];
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
	[self pass:boundary on:path];
}

/* The path has left the activity for the boundary event: it passes the
 * event now, or, with asyncBefore, in a job. */
- (void)pass:(UDEvent *)boundary on:(UDExecutionEntity *)path
{
	path.activityId = boundary.elementId;
	if (boundary.isAsyncBefore) {
		path.activityInstanceId = nil;
		[self job:UDJobTypeAsyncBefore execution:path node:boundary due:[NSDate date]];
		return;
	}
	path.activityInstanceId = [UDCommandContext newId];
	[self activityStarted:boundary execution:path];
	[self leave:boundary execution:path];
}

/* The error boundary on the node that catches the code: one for that code,
 * else a catch-all. */
- (UDEvent *)errorBoundaryOn:(UDFlowNode *)node
                       scope:(UDProcessDefinition *)scope
                        code:(NSString *)errorCode
{
	UDEvent *catchAll = nil;
	for (UDEvent *boundary in [scope boundaryEventsAttachedTo:node.elementId]) {
		if (boundary.trigger != UDEventTriggerError) {
			continue;
		}
		NSString *ref = boundary.errorRef;
		if (ref == nil || [ref length] == 0 || [ref isEqualToString:@"*"]) {
			catchAll = catchAll ?: boundary;
		} else if ([ref isEqualToString:errorCode]) {
			return boundary;
		}
	}
	return catchAll;
}

- (void)throwBpmnError:(NSString *)errorCode fromExecution:(UDExecutionEntity *)execution
{
	/* The error travels outward through the scopes around the activity --
	 * the activity's own, if it has boundary events, then each enclosing
	 * subprocess, then, out of a called instance, the call activity and the
	 * scopes around it -- and the nearest boundary that catches it wins. */
	UDProcessDefinition *definition = [self definitionForExecution:execution];
	UDExecutionEntity *scopeExecution = execution;
	while (scopeExecution != nil) {
		if (scopeExecution.parent == nil) {
			UDExecutionEntity *caller = scopeExecution.superExecution;
			if (caller == nil) {
				break;
			}
			definition = [self definitionForExecution:caller];
			UDFlowNode *call = [definition flowNodeWithId:caller.activityId];
			UDEvent *catcher = [call isKindOfClass:[UDCallActivity class]]
				? [self errorBoundaryOn:call
				                  scope:[definition scopeOfFlowNode:call.elementId]
				                   code:errorCode]
				: nil;
			if (catcher != nil) {
				/* A call activity with boundary events is a scope: the
				 * caller is its scope execution. The outputs are passed
				 * back as on a normal end. */
				NSDictionary *outputs = [self outputsOf:(UDCallActivity *)call
				                                   from:[self visibleVariables:scopeExecution]];
				if ([self setVariables:outputs from:caller]) {
					[self boundary:catcher firedOn:caller subscription:nil];
				}
				return;
			}
			scopeExecution = caller;
			continue;
		}
		if (scopeExecution.isScope) {
			NSString *ownerId = scopeExecution.parent.activityId;
			UDFlowNode *owner = [definition flowNodeWithId:ownerId];
			UDEvent *catcher = nil;
			if ([owner isKindOfClass:[UDTask class]] || [owner isKindOfClass:[UDSubProcess class]]) {
				catcher = [self errorBoundaryOn:owner
				                          scope:[definition scopeOfFlowNode:ownerId]
				                           code:errorCode];
			}
			if (catcher != nil) {
				[self boundary:catcher firedOn:scopeExecution subscription:nil];
				return;
			}
		}
		scopeExecution = scopeExecution.parent;
	}
	definition = [self definitionForExecution:execution];
	/* Nothing catches it: the path ends, as the reference does by default. */
	UDFlowNode *node = [definition flowNodeWithId:execution.activityId];
	if (node != nil && [self isActivityScope:execution node:node]) {
		UDExecutionEntity *host = execution.parent;
		[self cancelSubtree:execution];
		[self remove:execution];
		[self endPath:host];
	} else {
		[self activityEnded:execution.activityInstanceId canceled:YES];
		[self endPath:execution];
	}
}

#pragma mark - Call activities

/* The version of the called process the activity's binding picks. */
- (UDProcessDefinition *)calledDefinition:(UDCallActivity *)call
                                execution:(UDExecutionEntity *)execution
{
	UDRepositoryService *repository = self.engine.repositoryService;
	NSString *key = call.calledElement;
	NSError *error = nil;
	UDProcessDefinition *called = nil;
	switch (call.binding) {
	case UDCalledElementBindingLatest:
		called = [repository latestDefinitionForKey:key error:&error];
		break;
	case UDCalledElementBindingVersion:
		called = [repository definitionForKey:key version:call.calledElementVersion error:&error];
		break;
	case UDCalledElementBindingDeployment: {
		UDProcessDefinition *caller = [self definitionForExecution:execution];
		UDDeployment *deployment = [repository deploymentWithId:caller.deploymentId error:&error];
		for (UDProcessDefinition *candidate in deployment.definitions) {
			if ([candidate.processId isEqualToString:key]) {
				called = candidate;
			}
		}
		if (called == nil && deployment != nil) {
			error = UDCommandError(UDWorkflowErrorInvalidDefinition,
				[NSString stringWithFormat:@"%@ is not in the deployment of %@",
					key, caller.processId]);
		}
		break;
	}
	}
	if (called == nil) {
		[self fail:UDCommandError(UDWorkflowErrorInvalidDefinition,
			[NSString stringWithFormat:@"call activity %@: %@", call.elementId,
				[error localizedDescription] ?: @"no process to call"])];
	}
	return called;
}

/* The mappings applied to the variables on one side of the call. */
- (NSDictionary *)map:(NSArray<UDVariableMapping *> *)mappings from:(NSDictionary *)variables
{
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	for (UDVariableMapping *mapping in mappings) {
		if (mapping.isAllVariables) {
			[result addEntriesFromDictionary:variables];
		} else if (!mapping.isBusinessKey) {
			/* A source that does not exist passes null, as the reference
			 * does. */
			[result setObject:[variables objectForKey:mapping.source] ?: [NSNull null]
			           forKey:mapping.target];
		}
	}
	return result;
}

- (NSDictionary *)outputsOf:(UDCallActivity *)call from:(NSDictionary *)calledVariables
{
	return [self map:call.outputs from:calledVariables];
}

/* The activity starts an instance of the called process, in this command,
 * and waits for it. */
- (void)executeCall:(UDCallActivity *)call execution:(UDExecutionEntity *)execution
{
	UDProcessDefinition *called = [self calledDefinition:call execution:execution];
	if (called == nil) {
		return;
	}
	NSString *businessKey = nil;
	for (UDVariableMapping *mapping in call.inputs) {
		if (mapping.isBusinessKey) {
			businessKey = [execution processInstance].businessKey;
		}
	}
	UDExecutionEntity *child =
		[self startProcessInstance:called
		               businessKey:businessKey
		                 variables:[self map:call.inputs from:[self visibleVariables:execution]]
		                startEvent:nil
		            superExecution:execution];
	UDHistoricActivityInstanceEntity *row =
		[_openActivities objectForKey:execution.activityInstanceId ?: @""];
	row.calledProcessInstanceId = child.processInstanceId;
}

/* The called instance has ended: its outputs go to the calling process,
 * and the call activity is left. */
- (void)returnFrom:(NSDictionary *)calledVariables to:(UDExecutionEntity *)caller
{
	UDFlowNode *node = [self node:caller.activityId of:caller];
	if (![node isKindOfClass:[UDCallActivity class]]) {
		[self fail:UDCommandError(UDWorkflowErrorInvalidState,
			[NSString stringWithFormat:@"the calling execution is at %@, not a call activity",
				caller.activityId])];
		return;
	}
	if ([self setVariables:[self outputsOf:(UDCallActivity *)node from:calledVariables]
	                  from:caller]) {
		[self completeActivity:caller];
	}
}

#pragma mark - Signals and terminate

- (NSUInteger)broadcastSignal:(NSString *)signalName
                    variables:(NSDictionary *)variables
            processInstanceId:(NSString *)processInstanceId
{
	/* Everyone waiting now, as the signal is thrown: a path that comes to
	 * wait for the same signal while it is delivered does not get it. */
	NSArray *subscriptions = [self fetch:UDSubscriptionName
	                           predicate:[NSPredicate predicateWithFormat:
	                               @"eventType == %@ AND eventName == %@",
	                               UDEventTypeSignal, signalName]
	                                sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
	                                                                        ascending:YES] ]
	                               limit:0];
	NSUInteger delivered = 0;
	for (UDEventSubscriptionEntity *subscription in subscriptions) {
		if ([subscription isDeleted] || _failure != nil) {
			continue;
		}
		if (subscription.execution == nil) {
			if (processInstanceId != nil) {
				continue;
			}
			NSError *error = nil;
			UDProcessDefinition *definition =
				[self.engine.repositoryService definitionWithId:subscription.definitionId error:&error];
			UDFlowNode *start = [definition flowNodeWithId:
				[[definition startEvent] elementId]];
			if (definition == nil || ![start isKindOfClass:[UDEvent class]]) {
				[self fail:error];
				return delivered;
			}
			[self startProcessInstance:definition businessKey:nil variables:variables
			                startEvent:(UDEvent *)start];
			delivered += 1;
			continue;
		}
		if (processInstanceId != nil
		    && ![subscription.processInstanceId isEqualToString:processInstanceId]) {
			continue;
		}
		[self deliverSubscription:subscription variables:variables];
		delivered += 1;
	}
	return delivered;
}

/* A terminate end event: its scope -- the process instance or the
 * subprocess it is in -- ends now, every other path in it canceled. */
- (void)terminate:(UDExecutionEntity *)execution
{
	[self activityEnded:execution.activityInstanceId canceled:NO];
	UDExecutionEntity *scope = [execution scopeExecution];
	for (UDExecutionEntity *child in [scope.children allObjects]) {
		if (![child isDeleted]) {
			[self cancelSubtree:child];
			[self remove:child];
		}
	}
	for (NSManagedObject *leftover in [[scope.tasks setByAddingObjectsFromSet:scope.eventSubscriptions]
	         setByAddingObjectsFromSet:[scope.jobs setByAddingObjectsFromSet:scope.externalTasks]]) {
		if (![leftover isDeleted]) {
			[self remove:leftover];
		}
	}
	scope.isActive = NO;
	scope.activityId = nil;
	scope.activityInstanceId = nil;
	[self scopeEnded:scope];
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
		[self taskStarted:row];
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
	/* The task's own priority, else the process's, else 0. */
	NSNumber *priority = task.taskPriority
		?: [[self definitionForExecution:execution] defaultTaskPriority];
	row.priority = [priority longLongValue];
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
	/* The activity is done, even when an async continuation holds back
	 * the flows out of it. */
	[self activityEnded:execution.activityInstanceId canceled:NO];
	if (node.isAsyncAfter && ![node isKindOfClass:[UDGateway class]]) {
		/* The command stops here; a job takes the outgoing flows. */
		[self job:UDJobTypeAsyncAfter execution:execution node:node due:[NSDate date]];
		return;
	}
	[self leaveNow:node execution:execution];
}

- (void)leaveNow:(UDFlowNode *)node execution:(UDExecutionEntity *)execution
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
	/* Gateways leave through here directly. */
	[self activityEnded:execution.activityInstanceId canceled:NO];
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
			if (!UDGone(path)) {
				[self enter:target execution:path];
			}
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
	/* Before the path goes: removing it would take the called instance
	 * with it. */
	UDExecutionEntity *called = path.subProcessInstance;
	if (called != nil) {
		called.superExecution = level;
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
	UDExecutionEntity *caller = root.superExecution;
	NSDictionary *calledVariables = caller != nil ? [self visibleVariables:root] : nil;
	[self remove:root];
	if (caller != nil) {
		[self returnFrom:calledVariables to:caller];
	}
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
	case UDGatewayKindExclusive:
		[self depart:gateway scope:scope execution:execution];
		return;
	case UDGatewayKindParallel:
		if ([incoming count] > 1) {
			[self joinParallel:gateway incoming:[incoming count] scope:scope execution:execution];
		} else {
			[self depart:gateway scope:scope execution:execution];
		}
		return;
	case UDGatewayKindInclusive:
		if ([incoming count] > 1) {
			execution.isActive = NO;
			UDExecutionEntity *level = [self levelOf:execution];
			level.lockRevision += 1;
			[self tryInclusiveJoin:gateway scope:scope level:level];
		} else {
			[self depart:gateway scope:scope execution:execution];
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
			} else if (event.kind == UDEventKindIntermediateCatch
			           && event.trigger == UDEventTriggerSignal) {
				[self subscribe:execution type:UDEventTypeSignal name:event.signalName
				       activity:event.elementId];
			} else {
				[self fail:UDCommandError(UDWorkflowErrorInvalidDefinition,
					[NSString stringWithFormat:
						@"event-based gateway %@ may only be followed by message, timer or signal catch events",
						gateway.elementId])];
				return;
			}
		}
		return;
	}
}

/* The path leaves the gateway, after any join: by its choice of flows, or,
 * with asyncAfter, by a job that makes that choice. */
- (void)depart:(UDGateway *)gateway
         scope:(UDProcessDefinition *)scope
     execution:(UDExecutionEntity *)execution
{
	if (gateway.isAsyncAfter) {
		[self activityEnded:execution.activityInstanceId canceled:NO];
		[self job:UDJobTypeAsyncAfter execution:execution node:gateway due:[NSDate date]];
		return;
	}
	[self departNow:gateway scope:scope execution:execution];
}

- (void)departNow:(UDGateway *)gateway
            scope:(UDProcessDefinition *)scope
        execution:(UDExecutionEntity *)execution
{
	switch (gateway.kind) {
	case UDGatewayKindExclusive: {
		UDSequenceFlow *flow = [self chooseExclusive:gateway scope:scope execution:execution];
		if (flow != nil) {
			[self take:@[ flow ] scope:scope execution:execution];
		}
		return;
	}
	case UDGatewayKindParallel:
		/* Conditions on a parallel gateway's flows are ignored. */
		[self take:[scope outgoingFlowsFrom:gateway.elementId] scope:scope execution:execution];
		return;
	case UDGatewayKindInclusive: {
		NSArray *flows = [self chooseInclusive:gateway scope:scope execution:execution];
		if (flows != nil) {
			[self take:flows scope:scope execution:execution];
		}
		return;
	}
	case UDGatewayKindEventBased:
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
			[self activityEnded:other.activityInstanceId canceled:NO];
			[self remove:other];
			joined += 1;
		}
	}
	UDExecutionEntity *path = [self continueAfterJoin:execution level:level];
	[self depart:gateway scope:scope execution:path];
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
			[self activityEnded:other.activityInstanceId canceled:NO];
			[self remove:other];
		}
	}
	UDExecutionEntity *path = [self continueAfterJoin:survivor level:level];
	[self depart:gateway scope:scope execution:path];
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
			if (!UDGone(level)) {
				[self tryInclusiveJoin:gateway scope:scope level:level];
			}
		}];
	}
}

#pragma mark - History

- (BOOL)records:(UDHistoryLevel)level
{
	return self.engine.historyLevel >= level;
}

- (void)activityStarted:(UDFlowNode *)node execution:(UDExecutionEntity *)execution
{
	if (![self records:UDHistoryLevelActivity] || execution.activityInstanceId == nil) {
		return;
	}
	UDHistoricActivityInstanceEntity *row = [self insert:UDHistoricActivityName];
	row.activityInstanceId = execution.activityInstanceId;
	row.activityId = node.elementId;
	row.activityName = [node.name isEqualToString:node.elementId] ? nil : node.name;
	row.activityType = UDActivityType(node);
	row.processInstanceId = execution.processInstanceId;
	row.startTime = [NSDate date];
	row.sequence = [self.engine ud_nextSequence];
	[_openActivities setObject:row forKey:row.activityInstanceId];
}

/* Ends the activity instance, if it is still open: several ways out of an
 * activity pass here, and only the first counts. */
- (void)activityEnded:(NSString *)activityInstanceId canceled:(BOOL)canceled
{
	if (![self records:UDHistoryLevelActivity] || activityInstanceId == nil) {
		return;
	}
	UDHistoricActivityInstanceEntity *row = [_openActivities objectForKey:activityInstanceId];
	if (row == nil) {
		row = [[self fetch:UDHistoricActivityName
		         predicate:[NSPredicate predicateWithFormat:
		             @"activityInstanceId == %@ AND endTime == nil", activityInstanceId]
		              sort:nil
		             limit:1] lastObject];
	}
	if (row == nil || row.endTime != nil) {
		return;
	}
	row.endTime = [NSDate date];
	row.canceled = canceled;
	[_openActivities removeObjectForKey:activityInstanceId];
}

- (UDHistoricTaskInstanceEntity *)historicTask:(NSString *)taskId
{
	return [[self fetch:UDHistoricTaskName
	          predicate:[NSPredicate predicateWithFormat:@"taskId == %@", taskId]
	               sort:nil
	              limit:1] lastObject];
}

- (void)taskStarted:(UDTaskEntity *)task
{
	if (![self records:UDHistoryLevelActivity]) {
		return;
	}
	UDHistoricTaskInstanceEntity *row = [self insert:UDHistoricTaskName];
	row.taskId = task.taskId;
	row.name = task.name;
	row.taskDefinitionKey = task.taskDefinitionKey;
	row.assignee = task.assignee;
	row.processInstanceId = task.processInstanceId;
	row.startTime = task.createdAt;
}

- (void)task:(NSString *)taskId endedBecause:(NSString *)reason
{
	if (![self records:UDHistoryLevelActivity]) {
		return;
	}
	UDHistoricTaskInstanceEntity *row = [self historicTask:taskId];
	if (row != nil && row.endTime == nil) {
		row.endTime = [NSDate date];
		row.deleteReason = reason;
	}
}

- (void)historyTaskCompleted:(NSString *)taskId
{
	[self task:taskId endedBecause:UDTaskDeleteReasonCompleted];
}

- (void)historyJob:(UDJobEntity *)job state:(NSString *)state
{
	if (![self records:UDHistoryLevelFull]) {
		return;
	}
	UDHistoricJobLogEntity *row = [self insert:UDHistoricJobLogName];
	row.jobId = job.jobId;
	row.jobType = job.jobType;
	row.activityId = job.activityId;
	row.processInstanceId = job.processInstanceId;
	row.timestamp = [NSDate date];
	row.state = state;
	row.exceptionMessage = [state isEqualToString:UDJobLogStateFailed] ? job.exceptionMessage : nil;
	row.retries = job.retries;
	row.sequence = [self.engine ud_nextSequence];
}

- (void)incident:(NSString *)incidentId endedAs:(NSString *)state
{
	if (![self records:UDHistoryLevelFull]) {
		return;
	}
	UDHistoricIncidentEntity *row = [[self fetch:UDHistoricIncidentName
	                                   predicate:[NSPredicate predicateWithFormat:
	                                       @"incidentId == %@", incidentId]
	                                        sort:nil
	                                       limit:1] lastObject];
	if (row != nil && row.endTime == nil) {
		row.endTime = [NSDate date];
		row.state = state;
	}
}

/* Everything in the subtree is about to be removed by an interruption:
 * its activity instances are canceled, its tasks deleted, its incidents
 * and jobs gone. */
- (void)cancelSubtree:(UDExecutionEntity *)root
{
	NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
	/* The executions of instances that call activities in the subtree
	 * started. The caller removes only the subtree; these go explicitly, so
	 * that nothing still scheduled for them runs. */
	NSMutableSet *called = [NSMutableSet set];
	while ([pending count] > 0) {
		UDExecutionEntity *execution = [pending lastObject];
		[pending removeLastObject];
		[self activityEnded:execution.activityInstanceId canceled:YES];
		/* What this command already removed (a timer that just fired, a
		 * task just completed) stays in the sets until pending changes are
		 * processed. */
		for (UDTaskEntity *task in execution.tasks) {
			if (![task isDeleted]) {
				[self task:task.taskId endedBecause:UDTaskDeleteReasonDeleted];
			}
		}
		for (UDIncidentEntity *incident in execution.incidents) {
			if (![incident isDeleted]) {
				[self incident:incident.incidentId endedAs:UDIncidentStateDeleted];
			}
		}
		for (UDJobEntity *job in execution.jobs) {
			if (![job isDeleted]) {
				[self historyJob:job state:UDJobLogStateDeleted];
			}
		}
		BOOL inCalled = [called containsObject:execution];
		for (UDExecutionEntity *child in execution.children) {
			if (![child isDeleted]) {
				[pending addObject:child];
				if (inCalled) {
					[called addObject:child];
				}
			}
		}
		UDExecutionEntity *calledInstance = execution.subProcessInstance;
		if (calledInstance != nil && ![calledInstance isDeleted]) {
			[self processInstanceTerminated:calledInstance];
			[pending addObject:calledInstance];
			[called addObject:calledInstance];
		}
	}
	for (UDExecutionEntity *execution in called) {
		[self remove:execution];
	}
}

/* A called instance canceled with its call activity. */
- (void)processInstanceTerminated:(UDExecutionEntity *)instance
{
	if (![self records:UDHistoryLevelActivity]) {
		return;
	}
	UDHistoricProcessInstanceEntity *history = [[self fetch:UDHistoricInstanceName
	                                              predicate:[NSPredicate predicateWithFormat:
	                                                  @"processInstanceId == %@",
	                                                  instance.processInstanceId]
	                                                   sort:nil
	                                                  limit:1] lastObject];
	history.endTime = [NSDate date];
	history.state = UDHistoricStateInternallyTerminated;
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
	if ([self records:UDHistoryLevelFull]) {
		UDHistoricVariableUpdateEntity *update = [self insert:UDHistoricUpdateName];
		update.variableId = variable.variableId;
		update.name = variable.name;
		update.processInstanceId = variable.processInstanceId;
		update.time = [NSDate date];
		update.sequence = [self.engine ud_nextSequence];
		[update ud_setValue:[variable ud_value]];
	}
	if (![self records:UDHistoryLevelAudit]) {
		return;
	}
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

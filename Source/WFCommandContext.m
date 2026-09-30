#import "WFCommandContext.h"
#import "WFEntities.h"
#import "WFProcessEngine+Internal.h"
#import "WFFlowElements.h"
#import "WFProcessDefinition.h"
#import "WFCondition.h"
#import "WFDuration.h"
#import "WFTimers.h"
#import "WFFeelInternal.h"
#import "WFDecision.h"
#include <math.h>

static NSString * const WFExecutionName = @"WFExecution";
static NSString * const WFVariableName = @"WFVariable";
static NSString * const WFTaskName = @"WFTask";
static NSString * const WFSubscriptionName = @"WFEventSubscription";
static NSString * const WFJobName = @"WFJob";
static NSString * const WFExternalTaskName = @"WFExternalTask";
static NSString * const WFIncidentName = @"WFIncident";
static NSString * const WFHistoricInstanceName = @"WFHistoricProcessInstance";
static NSString * const WFHistoricVariableName = @"WFHistoricVariable";
static NSString * const WFHistoricActivityName = @"WFHistoricActivityInstance";
static NSString * const WFHistoricTaskName = @"WFHistoricTaskInstance";
static NSString * const WFHistoricUpdateName = @"WFHistoricVariableUpdate";
static NSString * const WFHistoricIncidentName = @"WFHistoricIncident";
static NSString * const WFHistoricJobLogName = @"WFHistoricJobLog";
static NSString * const WFDefinitionRecordName = @"WFDefinitionRecord";
static NSString * const WFIdentityLinkName = @"WFIdentityLink";

/* The BPMN element a node is, as history names activity types. */
static NSString *
WFActivityType(WFFlowNode *node)
{
	if ([node isKindOfClass:[WFEvent class]]) {
		switch ([(WFEvent *)node kind]) {
		case WFEventKindStart: return @"startEvent";
		case WFEventKindEnd: return @"endEvent";
		case WFEventKindIntermediateCatch: return @"intermediateCatchEvent";
		case WFEventKindIntermediateThrow: return @"intermediateThrowEvent";
		case WFEventKindBoundary: return @"boundaryEvent";
		}
	}
	if ([node isKindOfClass:[WFTask class]]) {
		switch ([(WFTask *)node kind]) {
		case WFTaskKindUser: return @"userTask";
		case WFTaskKindService: return @"serviceTask";
		case WFTaskKindScript: return @"scriptTask";
		case WFTaskKindSend: return @"sendTask";
		case WFTaskKindBusinessRule: return @"businessRuleTask";
		case WFTaskKindReceive: return @"receiveTask";
		case WFTaskKindManual: return @"manualTask";
		case WFTaskKindNone: return @"task";
		}
	}
	if ([node isKindOfClass:[WFGateway class]]) {
		switch ([(WFGateway *)node kind]) {
		case WFGatewayKindExclusive: return @"exclusiveGateway";
		case WFGatewayKindParallel: return @"parallelGateway";
		case WFGatewayKindInclusive: return @"inclusiveGateway";
		case WFGatewayKindEventBased: return @"eventBasedGateway";
		}
	}
	if ([node isKindOfClass:[WFCallActivity class]]) {
		return @"callActivity";
	}
	if ([node isKindOfClass:[WFSubProcess class]]) {
		return [(WFSubProcess *)node isTriggeredByEvent] ? @"eventSubProcess" : @"subProcess";
	}
	return @"activity";
}

static NSError *
WFCommandError(WFErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:WFErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@interface WFDelegateExecution ()
@property (nonatomic, weak) WFCommandContext *command;
@property (nonatomic, strong) WFExecutionEntity *execution;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *businessKey;
@property (nonatomic, readwrite, copy) NSString *processDefinitionId;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *activityInstanceId;
@property (nonatomic, readwrite, copy) NSString *eventName;
@property (nonatomic, readwrite, getter=isCanceled) BOOL canceled;
@property (nonatomic, readwrite, copy) NSDictionary *fields;
- (instancetype)initWithCommand:(WFCommandContext *)command execution:(WFExecutionEntity *)execution;
@end

@interface WFDelegateTask ()
@property (nonatomic, strong) WFTaskEntity *row;
@end

@implementation WFDelegateExecution

- (instancetype)initWithCommand:(WFCommandContext *)command execution:(WFExecutionEntity *)execution
{
	self = [super init];
	if (self) {
		_command = command;
		_execution = execution;
		_processInstanceId = [execution.processInstanceId copy];
		_businessKey = [[execution processInstance].businessKey copy];
		_processDefinitionId = [execution.definitionId copy];
		_activityInstanceId = [execution.activityInstanceId copy];
		_fields = @{};
	}
	return self;
}

- (NSDictionary *)variables
{
	return [self.command visibleVariables:self.execution];
}

- (id)variableNamed:(NSString *)name
{
	return [[self variables] objectForKey:name];
}

- (NSDictionary *)localVariables
{
	NSMutableDictionary *variables = [NSMutableDictionary dictionary];
	for (WFVariableEntity *variable in self.execution.variables) {
		if (![variable isDeleted]) {
			[variables setObject:[variable wf_value] ?: [NSNull null] forKey:variable.name];
		}
	}
	return variables;
}

- (BOOL)storable:(id)value named:(NSString *)name error:(NSError **)error
{
	if (name != nil && [WFCommandContext isStorableValue:value ?: [NSNull null]]) {
		return YES;
	}
	if (error != NULL) {
		*error = WFCommandError(WFErrorInvalidState,
			[NSString stringWithFormat:@"variable %@ is not a value the engine stores", name]);
	}
	return NO;
}

- (BOOL)setVariable:(NSString *)name value:(id)value error:(NSError **)error
{
	return [self storable:value named:name error:error]
		&& [self.command setVariables:@{ name: value ?: [NSNull null] } from:self.execution];
}

- (BOOL)setLocalVariable:(NSString *)name value:(id)value error:(NSError **)error
{
	return [self storable:value named:name error:error]
		&& [self.command setLocal:name value:value ?: [NSNull null] on:self.execution];
}

@end

@implementation WFDelegateTask

- (NSString *)taskId
{
	return self.row.taskId;
}

- (NSString *)name
{
	return self.row.name;
}

- (NSString *)taskDefinitionKey
{
	return self.row.taskDefinitionKey;
}

- (NSString *)assignee
{
	return self.row.assignee;
}

- (void)setAssignee:(NSString *)assignee
{
	self.row.assignee = assignee;
	[self.command historyTask:self.row.taskId assignee:assignee];
}

- (NSInteger)priority
{
	return self.row.priority;
}

- (void)setPriority:(NSInteger)priority
{
	self.row.priority = (int32_t)priority;
}

- (NSDate *)dueDate
{
	return self.row.dueDate;
}

- (void)setDueDate:(NSDate *)dueDate
{
	self.row.dueDate = dueDate;
}

@end

@implementation WFCommandContext
{
	NSMutableArray *_agenda;
	NSMutableArray *_afterCommit;
	NSError *_failure;
	NSMutableDictionary *_definitions;
	NSMutableDictionary *_historicVariables;
	NSMutableDictionary *_openActivities;
	/* Variable changes conditional events have yet to see: @[owner
	 * execution, name, "create" or "update"]. */
	NSMutableArray *_variableChanges;
	/* Definition id to whether it has conditional events. */
	NSMutableDictionary *_watchedDefinitions;
}

- (instancetype)initWithEngine:(WFProcessEngine *)engine
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
		_watchedDefinitions = [NSMutableDictionary dictionary];
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
				*error = WFCommandError(WFErrorInvalidState,
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
		_failure = error ?: WFCommandError(WFErrorInvalidState, @"command failed");
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
WFGone(NSManagedObject *object)
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
		return [NSError errorWithDomain:WFErrorDomain
		                           code:WFErrorConflict
		                       userInfo:@{
			NSLocalizedDescriptionKey:
				@"another command changed the same data first; nothing was committed",
			NSUnderlyingErrorKey: error }];
	}
	return error;
}

- (BOOL)execute:(BOOL (^)(WFCommandContext *, NSError **))body error:(NSError **)error
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
			bodyError = WFCommandError(WFErrorInvalidState,
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

- (WFProcessDefinition *)definitionForExecution:(WFExecutionEntity *)execution
{
	NSString *definitionId = execution.definitionId;
	WFProcessDefinition *definition = [_definitions objectForKey:definitionId];
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

- (WFFlowNode *)node:(NSString *)activityId of:(WFExecutionEntity *)execution
{
	WFFlowNode *node = [[self definitionForExecution:execution] flowNodeWithId:activityId];
	if (node == nil) {
		[self fail:WFCommandError(WFErrorUnknownElement,
			[NSString stringWithFormat:@"no activity %@ in the definition", activityId])];
	}
	return node;
}

- (WFProcessDefinition *)scopeOf:(NSString *)activityId execution:(WFExecutionEntity *)execution
{
	return [[self definitionForExecution:execution] scopeOfFlowNode:activityId];
}

- (WFExecutionEntity *)newChildOf:(WFExecutionEntity *)parent concurrent:(BOOL)concurrent
{
	WFExecutionEntity *child = [self insert:WFExecutionName];
	child.executionId = [WFCommandContext newId];
	child.processInstanceId = parent.processInstanceId;
	child.definitionId = parent.definitionId;
	child.isConcurrent = concurrent;
	child.isScope = !concurrent;
	child.isActive = YES;
	child.parent = parent;
	return child;
}

/* The execution that holds the concurrent paths this one is part of. */
- (WFExecutionEntity *)levelOf:(WFExecutionEntity *)execution
{
	return execution.isConcurrent ? execution.parent : execution;
}

- (NSArray<WFExecutionEntity *> *)pathsAt:(WFExecutionEntity *)level
{
	NSArray *paths = [level concurrentChildren];
	return [paths count] > 0 ? paths : @[ level ];
}

#pragma mark - Starting and entering

- (WFExecutionEntity *)startProcessInstance:(WFProcessDefinition *)definition
                                businessKey:(NSString *)businessKey
                                  variables:(NSDictionary *)variables
                                 startEvent:(WFEvent *)startEvent
{
	return [self startProcessInstance:definition businessKey:businessKey variables:variables
	                       startEvent:startEvent superExecution:nil];
}

- (WFExecutionEntity *)startProcessInstance:(WFProcessDefinition *)definition
                                businessKey:(NSString *)businessKey
                                  variables:(NSDictionary *)variables
                                 startEvent:(WFEvent *)startEvent
                             superExecution:(WFExecutionEntity *)superExecution
{
	WFEvent *start = startEvent ?: [definition startEvent];
	if (start == nil) {
		[self fail:WFCommandError(WFErrorInvalidDefinition,
			@"the definition has no start event")];
		return nil;
	}
	/* However it is started -- by the API, a message, a signal, a timer or
	 * a call activity -- a suspended definition starts nothing. */
	if ([self isDefinitionSuspended:definition.definitionId]) {
		[self fail:WFCommandError(WFErrorSuspended, [NSString stringWithFormat:
			@"%@ version %ld is suspended", definition.processId, (long)definition.version])];
		return nil;
	}
	[_definitions setObject:definition forKey:definition.definitionId];
	WFExecutionEntity *root = [self insert:WFExecutionName];
	root.executionId = [WFCommandContext newId];
	root.processInstanceId = root.executionId;
	root.definitionId = definition.definitionId;
	root.businessKey = businessKey;
	root.isScope = YES;
	root.isActive = YES;
	root.superExecution = superExecution;
	root.superProcessInstanceId = superExecution.processInstanceId;

	WFHistoricProcessInstanceEntity *history =
		[self records:WFHistoryLevelActivity] ? [self insert:WFHistoricInstanceName] : nil;
	history.processInstanceId = root.processInstanceId;
	history.businessKey = businessKey;
	history.definitionId = definition.definitionId;
	history.definitionKey = definition.processId;
	history.startTime = [NSDate date];
	history.state = WFHistoricStateActive;
	history.superProcessInstanceId = root.superProcessInstanceId;

	if (![self setVariables:variables from:root]
	    || ![self fire:definition.executionListeners event:WFListenerEventStart on:root activity:nil canceled:NO]) {
		return nil;
	}
	[self armEventSubProcessesOf:definition on:root];
	[self schedule:^{
		if (!WFGone(root)) {
			[self enter:start execution:root];
		}
	}];
	return root;
}

- (BOOL)isScopeActivity:(WFFlowNode *)node scope:(WFProcessDefinition *)scope
{
	if ([node isKindOfClass:[WFSubProcess class]]) {
		return YES;
	}
	if (![node isKindOfClass:[WFTask class]] && ![node isKindOfClass:[WFCallActivity class]]) {
		return NO;
	}
	/* Boundary events wait on the activity's own scope, and its mapped
	 * inputs are variables of it. */
	return [[scope boundaryEventsAttachedTo:node.elementId] count] > 0
		|| [node.inputParameters count] > 0 || [node.outputParameters count] > 0;
}

/* Is this the scope execution created for a task with boundary events? */
- (BOOL)isActivityScope:(WFExecutionEntity *)execution node:(WFFlowNode *)node
{
	return execution.isScope && execution.parent != nil
		&& ![node isKindOfClass:[WFSubProcess class]]
		&& !execution.parent.isMultiInstanceBody
		&& [execution.parent.activityId isEqualToString:node.elementId];
}

/* Is this one instance of the multi-instance activity? */
- (BOOL)isInstance:(WFExecutionEntity *)execution of:(WFFlowNode *)node
{
	return execution.isScope && execution.parent.isMultiInstanceBody
		&& [execution.parent.activityId isEqualToString:node.elementId];
}

- (void)enter:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	/* A multi-instance activity's asyncBefore is each instance's. */
	BOOL body = node.multiInstance != nil && ![self isInstance:execution of:node];
	if (node.isAsyncBefore && !body) {
		/* The command stops here; a job enters the node. */
		execution.activityId = node.elementId;
		execution.activityInstanceId = [WFCommandContext newId];
		execution.isActive = YES;
		[self job:WFJobTypeAsyncBefore execution:execution node:node due:[NSDate date]];
		return;
	}
	[self enterNow:node execution:execution];
}

- (void)enterNow:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	if ([self isInstance:execution of:node]) {
		[self startInstance:node execution:execution];
		return;
	}
	if (node.multiInstance != nil) {
		[self enterMultiInstance:node execution:execution];
		return;
	}
	WFProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	execution.activityId = node.elementId;
	execution.activityInstanceId = [WFCommandContext newId];
	execution.isActive = YES;
	[self activityStarted:node execution:execution];
	if (![self isScopeActivity:node scope:scope]) {
		if ([self fire:node.executionListeners event:WFListenerEventStart on:execution activity:node.elementId
		      canceled:NO]) {
			[self execute:node scope:scope execution:execution];
		}
		return;
	}
	/* A scope activity runs in a child scope execution: its boundary
	 * subscriptions and timers hang there, and interrupting it removes
	 * exactly that subtree. */
	WFExecutionEntity *inner = [self newChildOf:execution concurrent:NO];
	execution.isActive = NO;
	if (![self mapInputsOf:node from:execution into:inner]) {
		return;
	}
	[self armBoundaryEventsOf:node scope:scope on:inner];
	if (![self fire:node.executionListeners event:WFListenerEventStart on:inner activity:node.elementId canceled:NO]) {
		return;
	}
	if ([node isKindOfClass:[WFSubProcess class]]) {
		WFProcessDefinition *innerDefinition = [(WFSubProcess *)node innerDefinition];
		[self armEventSubProcessesOf:innerDefinition on:inner];
		WFEvent *start = [innerDefinition startEvent];
		[self schedule:^{
			if (!WFGone(inner)) {
				[self enter:start execution:inner];
			}
		}];
		return;
	}
	inner.activityId = node.elementId;
	inner.activityInstanceId = execution.activityInstanceId;
	[self execute:node scope:scope execution:inner];
}

/* The activity's message, signal and timer boundary events wait on its
 * scope execution. */
- (void)armBoundaryEventsOf:(WFFlowNode *)node
                      scope:(WFProcessDefinition *)scope
                         on:(WFExecutionEntity *)inner
{
	for (WFEvent *boundary in [scope boundaryEventsAttachedTo:node.elementId]) {
		if (boundary.trigger == WFEventTriggerMessage) {
			[self subscribe:inner message:boundary.messageName activity:boundary.elementId];
		} else if (boundary.trigger == WFEventTriggerSignal) {
			[self subscribe:inner type:WFEventTypeSignal name:boundary.signalName
			       activity:boundary.elementId];
		} else if (boundary.trigger == WFEventTriggerTimer) {
			[self timer:inner event:boundary];
		} else if (boundary.trigger == WFEventTriggerConditional) {
			[self waitForCondition:boundary on:inner];
		}
	}
}

- (void)execute:(WFFlowNode *)node
          scope:(WFProcessDefinition *)scope
      execution:(WFExecutionEntity *)execution
{
	if ([node isKindOfClass:[WFEvent class]]) {
		[self executeEvent:(WFEvent *)node execution:execution];
	} else if ([node isKindOfClass:[WFTask class]]) {
		[self executeTask:(WFTask *)node execution:execution];
	} else if ([node isKindOfClass:[WFGateway class]]) {
		[self executeGateway:(WFGateway *)node scope:scope execution:execution];
	} else if ([node isKindOfClass:[WFCallActivity class]]) {
		[self executeCall:(WFCallActivity *)node execution:execution];
	} else {
		[self fail:WFCommandError(WFErrorUnknownElement,
			[NSString stringWithFormat:@"%@ cannot be executed", node.elementId])];
	}
}

#pragma mark - Events

- (void)executeEvent:(WFEvent *)event execution:(WFExecutionEntity *)execution
{
	switch (event.kind) {
	case WFEventKindStart:
		/* However the instance was started, it has been. */
		[self leave:event execution:execution];
		return;
	case WFEventKindIntermediateThrow:
		if (event.trigger == WFEventTriggerEscalation) {
			[self throwEscalation:event execution:execution];
			return;
		}
		if (event.trigger == WFEventTriggerCompensation) {
			[self throwCompensation:event execution:execution];
			return;
		}
		if (event.trigger == WFEventTriggerLink) {
			[self jump:event execution:execution];
			return;
		}
		if (event.trigger == WFEventTriggerMessage) {
			[self throwMessage:event execution:execution];
		} else if (event.trigger == WFEventTriggerSignal) {
			[self broadcastSignal:event.signalName variables:nil processInstanceId:nil];
		}
		[self leave:event execution:execution];
		return;
	case WFEventKindEnd:
		if (![self fire:event.executionListeners event:WFListenerEventEnd on:execution activity:event.elementId
		      canceled:NO]) {
			return;
		}
		if (event.trigger == WFEventTriggerTerminate) {
			[self terminate:execution];
			return;
		}
		if (event.trigger == WFEventTriggerEscalation) {
			[self throwEscalation:event execution:execution];
			return;
		}
		if (event.trigger == WFEventTriggerCompensation) {
			[self throwCompensation:event execution:execution];
			return;
		}
		if (event.trigger == WFEventTriggerError) {
			[self activityEnded:execution.activityInstanceId canceled:NO];
			if (![self propagate:WFEventTriggerError code:event.errorRef from:execution]) {
				/* Uncaught, as an end event its path ends all the same. */
				[self endPath:execution];
			}
			return;
		}
		if (event.trigger == WFEventTriggerMessage) {
			[self throwMessage:event execution:execution];
		} else if (event.trigger == WFEventTriggerSignal) {
			[self broadcastSignal:event.signalName variables:nil processInstanceId:nil];
		}
		[self activityEnded:execution.activityInstanceId canceled:NO];
		[self endPath:execution];
		return;
	case WFEventKindIntermediateCatch:
		if (event.trigger == WFEventTriggerMessage) {
			[self subscribe:execution message:event.messageName activity:event.elementId];
		} else if (event.trigger == WFEventTriggerSignal) {
			[self subscribe:execution type:WFEventTypeSignal name:event.signalName
			       activity:event.elementId];
		} else if (event.trigger == WFEventTriggerTimer) {
			[self timer:execution event:event];
		} else if (event.trigger == WFEventTriggerConditional) {
			/* Holding already, it does not wait. */
			if ([self conditionOf:event holdsOn:execution]) {
				[self leave:event execution:execution];
			} else if (_failure == nil) {
				[self subscribe:execution type:WFEventTypeConditional name:event.elementId
				       activity:event.elementId];
			}
		} else {
			/* A link catch event: the path has jumped here. */
			[self leave:event execution:execution];
		}
		return;
	case WFEventKindBoundary:
		[self fail:WFCommandError(WFErrorInvalidDefinition,
			[NSString stringWithFormat:@"boundary event %@ has an incoming flow",
				event.elementId])];
		return;
	}
}

- (void)throwMessage:(WFEvent *)event execution:(WFExecutionEntity *)execution
{
	NSString *name = event.messageName;
	NSDictionary *variables = [self visibleVariables:execution];
	NSString *processInstanceId = execution.processInstanceId;
	WFProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine wf_messageThrown:name variables:variables processInstanceId:processInstanceId];
	}];
}

/* A link throw event: the path goes on at the catch event of the same
 * name in its scope. */
- (void)jump:(WFEvent *)event execution:(WFExecutionEntity *)execution
{
	WFProcessDefinition *scope = [self scopeOf:event.elementId execution:execution];
	WFFlowNode *target = nil;
	for (WFFlowNode *node in [scope.nodes allValues]) {
		if ([node isKindOfClass:[WFEvent class]] && [(WFEvent *)node trigger] == WFEventTriggerLink
		    && [(WFEvent *)node kind] == WFEventKindIntermediateCatch
		    && [[(WFEvent *)node linkName] isEqualToString:event.linkName]) {
			target = node;
		}
	}
	if (![self fire:event.executionListeners event:WFListenerEventEnd on:execution activity:event.elementId
	      canceled:NO]) {
		return;
	}
	[self activityEnded:execution.activityInstanceId canceled:NO];
	[self schedule:^{
		if (!WFGone(execution)) {
			[self enter:target execution:execution];
		}
	}];
}

#pragma mark - Delegates and listeners

/* The reference's fields, evaluated over the variables on the path. */
- (NSDictionary *)fieldsOf:(WFDelegateReference *)reference execution:(WFExecutionEntity *)execution
{
	if ([reference.fields count] == 0) {
		return @{};
	}
	NSDictionary *variables = [self visibleVariables:execution];
	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	for (WFParameter *field in reference.fields) {
		[fields setObject:[field.expression valueWithVariables:variables] forKey:field.name];
	}
	return fields;
}

/* Finds what the reference names and calls it; NO, with an error, when it
 * cannot be found, fails, or raises. */
- (BOOL)call:(WFDelegateReference *)reference
    protocol:(Protocol *)protocol
      fields:(NSDictionary *)fields
       error:(NSError **)error
      invoke:(BOOL (^)(id delegate, NSError **error))invoke
{
	NSError *problem = nil;
	id delegate = [self.engine wf_delegateFor:reference protocol:protocol error:&problem];
	BOOL ok = NO;
	if (delegate != nil) {
		@try {
			/* A fresh instance of a class is given its fields as well. */
			if (reference.className != nil) {
				for (NSString *name in fields) {
					NSString *setter = [NSString stringWithFormat:@"set%@%@:",
						[[name substringToIndex:1] uppercaseString], [name substringFromIndex:1]];
					if ([delegate respondsToSelector:NSSelectorFromString(setter)]) {
						id value = [fields objectForKey:name];
						[delegate setValue:value == [NSNull null] ? nil : value forKey:name];
					}
				}
			}
			ok = invoke(delegate, &problem);
		} @catch (NSException *exception) {
			problem = WFCommandError(WFErrorHandler, [NSString stringWithFormat:@"%@ raised %@: %@",
				reference, [exception name], [exception reason]]);
			ok = NO;
		}
		if (!ok && problem == nil) {
			problem = WFCommandError(WFErrorHandler, [NSString stringWithFormat:@"%@ failed without saying why", reference]);
		}
	}
	if (!ok && error != NULL) {
		*error = problem;
	}
	return ok;
}

/* The listeners for the event, in order, on the path. NO, with the
 * command failed, when one fails. */
- (BOOL)fire:(NSArray<WFListener *> *)listeners
       event:(WFListenerEvent)event
          on:(WFExecutionEntity *)execution
    activity:(NSString *)activityId
    canceled:(BOOL)canceled
{
	for (WFListener *listener in listeners) {
		if (listener.event != event || _failure != nil) {
			continue;
		}
		WFDelegateExecution *context = [[WFDelegateExecution alloc] initWithCommand:self execution:execution];
		context.activityId = activityId;
		context.eventName = [WFListener nameOfEvent:event];
		context.canceled = canceled;
		context.fields = [self fieldsOf:listener.delegate execution:execution];
		NSError *error = nil;
		if (![self call:listener.delegate protocol:@protocol(WFExecutionListener) fields:context.fields error:&error
		         invoke:^BOOL(id delegate, NSError **callError) {
			return [delegate notifyWithExecution:context error:callError];
		}]) {
			[self fail:WFCommandError(WFErrorHandler, [NSString stringWithFormat:@"the %@ listener on %@: %@",
				context.eventName, activityId ?: [[self definitionForExecution:execution] processId],
				[error localizedDescription]])];
			return NO;
		}
	}
	return _failure == nil;
}

/* A user task's listeners for the event. */
- (BOOL)fireTaskListeners:(WFListenerEvent)event task:(WFTaskEntity *)row
{
	WFExecutionEntity *execution = row.execution;
	WFFlowNode *node = [self node:row.taskDefinitionKey of:execution];
	if (![node isKindOfClass:[WFTask class]]) {
		return YES;
	}
	for (WFListener *listener in [(WFTask *)node taskListeners]) {
		if (listener.event != event || _failure != nil) {
			continue;
		}
		WFDelegateTask *context = [[WFDelegateTask alloc] initWithCommand:self execution:execution];
		context.row = row;
		context.activityId = row.taskDefinitionKey;
		context.eventName = [WFListener nameOfEvent:event];
		context.fields = [self fieldsOf:listener.delegate execution:execution];
		NSError *error = nil;
		if (![self call:listener.delegate protocol:@protocol(WFTaskListener) fields:context.fields error:&error
		         invoke:^BOOL(id delegate, NSError **callError) {
			return [delegate notifyWithTask:context error:callError];
		}]) {
			[self fail:WFCommandError(WFErrorHandler, [NSString stringWithFormat:@"the %@ task listener on %@: %@",
				context.eventName, row.taskDefinitionKey, [error localizedDescription]])];
			return NO;
		}
	}
	return _failure == nil;
}

- (BOOL)taskAssigned:(WFTaskEntity *)row
{
	return [self fireTaskListeners:WFListenerEventAssignment task:row];
}

- (BOOL)taskCompleting:(WFTaskEntity *)row
{
	return [self fireTaskListeners:WFListenerEventComplete task:row];
}

/* A service, send or business rule task's delegate: done, the task is
 * left; a BPMN error is thrown from it; any other failure fails the
 * command. */
- (void)runDelegateOf:(WFTask *)task execution:(WFExecutionEntity *)execution
{
	WFDelegateExecution *context = [[WFDelegateExecution alloc] initWithCommand:self execution:execution];
	context.activityId = task.elementId;
	context.fields = [self fieldsOf:task.delegate execution:execution];
	NSError *error = nil;
	BOOL ok = [self call:task.delegate protocol:@protocol(WFActivityDelegate) fields:context.fields error:&error
	              invoke:^BOOL(id delegate, NSError **callError) {
		return [delegate executeWithExecution:context error:callError];
	}];
	if (_failure != nil) {
		return;
	}
	if (ok) {
		[self completeActivity:execution];
		return;
	}
	NSString *code = [[error userInfo] objectForKey:WFErrorRefKey];
	if (code != nil) {
		[self throwBpmnError:code fromExecution:execution];
		return;
	}
	[self fail:WFCommandError(WFErrorHandler, [NSString stringWithFormat:@"%@: %@", task.elementId,
		[error localizedDescription]])];
}

/* An activity's end listeners as it is canceled: once per activity
 * instance, on the execution that holds it, and per instance of a
 * multi-instance activity rather than for its body. */
- (void)fireCanceledEndOf:(WFExecutionEntity *)execution
{
	NSString *activityInstanceId = execution.activityInstanceId;
	if (execution.activityId == nil || activityInstanceId == nil
	    || [execution.parent.activityInstanceId isEqualToString:activityInstanceId]) {
		return;
	}
	WFFlowNode *node = [self node:execution.activityId of:execution];
	if (node == nil || (node.multiInstance != nil && ![self isInstance:execution of:node])) {
		return;
	}
	[self fire:node.executionListeners event:WFListenerEventEnd on:execution activity:node.elementId canceled:YES];
}

#pragma mark - Conditional events

/* Whether the event's condition holds over the variables visible there.
 * A condition that cannot be evaluated fails the command. */
- (BOOL)conditionOf:(WFEvent *)event holdsOn:(WFExecutionEntity *)execution
{
	NSError *error = nil;
	BOOL holds = [event.condition.expression evaluateWithVariables:[self visibleVariables:execution]
	                                                          error:&error];
	if (error != nil) {
		[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:@"%@: %@",
			event.elementId, [error localizedDescription]])];
		return NO;
	}
	return holds;
}

/* A boundary event, an event subprocess's start or an event after an
 * event-based gateway starts waiting for its condition: it may hold
 * already, which is seen once what armed it is done. */
- (void)waitForCondition:(WFEvent *)event on:(WFExecutionEntity *)execution
{
	WFEventSubscriptionEntity *subscription =
		[self subscribe:execution type:WFEventTypeConditional name:event.elementId activity:event.elementId];
	[self schedule:^{
		if (!WFGone(subscription) && !WFGone(execution) && [self conditionOf:event holdsOn:execution]) {
			[self event:event triggeredOn:execution subscription:subscription];
		}
	}];
}

/* Whether any event in the definition, or in its subprocesses, waits for
 * a condition: most do not, and their variables need no watching. */
static BOOL
WFHasConditionalEvents(WFProcessDefinition *definition)
{
	for (WFFlowNode *node in [definition.nodes allValues]) {
		if ([node isKindOfClass:[WFEvent class]] && [(WFEvent *)node trigger] == WFEventTriggerConditional) {
			return YES;
		}
		if ([node isKindOfClass:[WFSubProcess class]]
		    && WFHasConditionalEvents([(WFSubProcess *)node innerDefinition])) {
			return YES;
		}
	}
	return NO;
}

/* A variable was set: conditional events that see it look again, once
 * the operation that set it is done. */
- (void)variable:(WFVariableEntity *)variable changedBy:(NSString *)change
{
	if (variable.execution == nil) {
		return;
	}
	WFProcessDefinition *definition = [self definitionForExecution:variable.execution];
	NSNumber *watched = definition.definitionId != nil ? [_watchedDefinitions objectForKey:definition.definitionId] : nil;
	if (watched == nil) {
		watched = [NSNumber numberWithBool:WFHasConditionalEvents(definition)];
		if (definition.definitionId != nil) {
			[_watchedDefinitions setObject:watched forKey:definition.definitionId];
		}
	}
	if (![watched boolValue]) {
		return;
	}
	if (_variableChanges == nil) {
		_variableChanges = [NSMutableArray array];
		[self schedule:^{
			[self dispatchVariableChanges];
		}];
	}
	[_variableChanges addObject:@[ variable.execution, variable.name, change ]];
}

- (BOOL)change:(NSArray *)change concerns:(WFEvent *)event on:(WFExecutionEntity *)execution
{
	WFEventCondition *condition = event.condition;
	if ((condition.variableName != nil && ![condition.variableName isEqualToString:[change objectAtIndex:1]])
	    || (condition.variableEvents != nil && ![condition.variableEvents containsObject:[change objectAtIndex:2]])) {
		return NO;
	}
	/* Only where the variable is visible: in the subtree of the execution
	 * it belongs to. */
	WFExecutionEntity *owner = [change objectAtIndex:0];
	for (WFExecutionEntity *scope = execution; scope != nil; scope = scope.parent) {
		if (scope == owner) {
			return YES;
		}
	}
	return NO;
}

/* Each conditional event waiting where a changed variable is visible is
 * evaluated, oldest first; each whose condition holds fires. */
- (void)dispatchVariableChanges
{
	NSArray *changes = _variableChanges;
	_variableChanges = nil;
	NSMutableSet *instances = [NSMutableSet set];
	for (NSArray *change in changes) {
		WFExecutionEntity *owner = [change objectAtIndex:0];
		if (!WFGone(owner) && owner.processInstanceId != nil) {
			[instances addObject:owner.processInstanceId];
		}
	}
	for (NSString *processInstanceId in instances) {
		NSArray *waiting = [self fetch:WFSubscriptionName
		                     predicate:[NSPredicate predicateWithFormat:
		                         @"eventType == %@ AND processInstanceId == %@",
		                         WFEventTypeConditional, processInstanceId]
		                          sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES] ]
		                         limit:0];
		for (WFEventSubscriptionEntity *subscription in waiting) {
			WFExecutionEntity *execution = subscription.execution;
			if (_failure != nil) {
				return;
			}
			if (WFGone(subscription) || execution == nil || WFGone(execution) || execution.suspended) {
				continue;
			}
			WFFlowNode *node = [self node:subscription.activityId of:execution];
			if (![node isKindOfClass:[WFEvent class]]) {
				continue;
			}
			WFEvent *event = (WFEvent *)node;
			BOOL concerned = NO;
			for (NSArray *change in changes) {
				concerned = concerned || [self change:change concerns:event on:execution];
			}
			if (concerned && [self conditionOf:event holdsOn:execution]) {
				[self event:event triggeredOn:execution subscription:subscription];
			}
		}
	}
}

- (void)subscribe:(WFExecutionEntity *)execution
          message:(NSString *)messageName
         activity:(NSString *)activityId
{
	[self subscribe:execution type:WFEventTypeMessage name:messageName activity:activityId];
}

- (WFEventSubscriptionEntity *)subscribe:(WFExecutionEntity *)execution
                                    type:(NSString *)eventType
                                    name:(NSString *)eventName
                                activity:(NSString *)activityId
{
	WFEventSubscriptionEntity *subscription = [self insert:WFSubscriptionName];
	subscription.subscriptionId = [WFCommandContext newId];
	subscription.eventType = eventType;
	subscription.eventName = eventName;
	subscription.activityId = activityId;
	subscription.processInstanceId = execution.processInstanceId;
	subscription.createdAt = [NSDate date];
	subscription.sequence = [self.engine wf_nextSequence];
	subscription.execution = execution;
	return subscription;
}

/* Arms the event's timer on the execution: its expression is evaluated
 * now, over the variables visible there. */
- (void)timer:(WFExecutionEntity *)execution event:(WFEvent *)event
{
	NSDate *due = nil;
	NSString *repeat = nil;
	NSError *error = nil;
	if (!WFTimerSchedule(event.timer, [self visibleVariables:execution], [NSDate date], &due, &repeat, &error)) {
		[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:@"%@: %@",
			event.elementId, [error localizedDescription]])];
		return;
	}
	WFJobEntity *job = [self job:WFJobTypeTimer execution:execution node:event due:due];
	job.repeat = repeat;
}

/* Whether a firing timer's cycle goes on: on a non-interrupting boundary
 * event, or a non-interrupting event subprocess's start. */
- (BOOL)timerRepeats:(WFFlowNode *)node
{
	if (![node isKindOfClass:[WFEvent class]]) {
		return NO;
	}
	WFEvent *event = (WFEvent *)node;
	return !event.isInterrupting
		&& (event.kind == WFEventKindBoundary || event.kind == WFEventKindStart);
}

/* A job on the node for the execution. Its attempts come from the node's
 * retry cycle; the engine is told once the command commits. */
- (WFJobEntity *)job:(NSString *)type
          execution:(WFExecutionEntity *)execution
               node:(WFFlowNode *)node
                due:(NSDate *)due
{
	NSInteger attempts = WF_DEFAULT_ATTEMPTS;
	NSArray *delays = nil;
	WFParseRetryCycle(node.retryTimeCycle, &attempts, &delays);
	WFJobEntity *job = [self insert:WFJobName];
	job.jobId = [WFCommandContext newId];
	job.jobType = type;
	job.activityId = node.elementId;
	job.processInstanceId = execution.processInstanceId;
	job.dueDate = due;
	job.createdAt = [NSDate date];
	job.retries = (int32_t)attempts;
	job.exclusive = node.isExclusive;
	job.execution = execution;
	[self historyJob:job state:WFJobLogStateCreated];
	NSString *jobId = job.jobId;
	NSString *processInstanceId = job.processInstanceId;
	BOOL exclusive = job.exclusive;
	WFProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine wf_jobCreated:jobId
		    processInstanceId:processInstanceId
		              dueDate:due
		            exclusive:exclusive];
	}];
	return job;
}

- (void)deliverSubscription:(WFEventSubscriptionEntity *)subscription
                  variables:(NSDictionary *)variables
{
	WFExecutionEntity *execution = subscription.execution;
	WFFlowNode *node = [self node:subscription.activityId of:execution];
	if (node == nil || ![self setVariables:variables from:execution]) {
		return;
	}
	[self event:node triggeredOn:execution subscription:subscription];
}

- (void)runJob:(WFJobEntity *)job
{
	[self historyJob:job state:WFJobLogStateSuccessful];
	NSString *type = job.jobType;
	NSString *repeat = job.repeat;
	NSDate *last = job.dueDate ?: [NSDate date];
	if ([type isEqualToString:WFJobTypeTimerStart]) {
		NSError *error = nil;
		WFProcessDefinition *definition =
			[self.engine.repositoryService definitionWithId:job.definitionId error:&error];
		WFFlowNode *start = [definition flowNodeWithId:job.activityId];
		[self remove:job];
		if (definition == nil || ![start isKindOfClass:[WFEvent class]]) {
			[self fail:error ?: WFCommandError(WFErrorInvalidDefinition,
				@"the timer start event is gone from its definition")];
			return;
		}
		if (repeat != nil) {
			[self repeatTimerStart:start definition:definition after:last repeat:repeat];
		}
		[self startProcessInstance:definition businessKey:nil variables:nil
		                startEvent:(WFEvent *)start];
		return;
	}
	WFExecutionEntity *execution = job.execution;
	WFFlowNode *node = [self node:job.activityId of:execution];
	[self remove:job];
	if (node == nil) {
		return;
	}
	if ([type isEqualToString:WFJobTypeTimer] && repeat != nil && [self timerRepeats:node]) {
		/* The cycle's next firing waits on the same execution. */
		NSDate *due = nil;
		NSString *remaining = nil;
		if (WFTimerNextDue(repeat, last, &due, &remaining)) {
			WFJobEntity *next = [self job:WFJobTypeTimer execution:execution node:node due:due];
			next.repeat = remaining;
		}
	}
	BOOL boundary = [node isKindOfClass:[WFEvent class]]
		&& [(WFEvent *)node kind] == WFEventKindBoundary;
	if ([type isEqualToString:WFJobTypeAsyncBefore] && boundary) {
		/* The boundary fired in an earlier command; its path now passes
		 * the event. */
		execution.activityInstanceId = [WFCommandContext newId];
		[self activityStarted:node execution:execution];
		[self leave:node execution:execution];
	} else if ([type isEqualToString:WFJobTypeAsyncBefore]) {
		[self enterNow:node execution:execution];
	} else if ([type isEqualToString:WFJobTypeAsyncAfter] && [node isKindOfClass:[WFGateway class]]) {
		[self departNow:(WFGateway *)node
		          scope:[self scopeOf:node.elementId execution:execution]
		      execution:execution];
	} else if ([type isEqualToString:WFJobTypeAsyncAfter]) {
		[self leaveNow:node execution:execution];
	} else {
		[self event:(WFEvent *)node triggeredOn:execution subscription:nil];
	}
}

/* A timer start event's cycle: the next job that starts an instance. */
- (void)repeatTimerStart:(WFFlowNode *)start
              definition:(WFProcessDefinition *)definition
                   after:(NSDate *)last
                  repeat:(NSString *)repeat
{
	NSDate *due = nil;
	NSString *remaining = nil;
	if (!WFTimerNextDue(repeat, last, &due, &remaining)) {
		return;
	}
	NSInteger attempts = WF_DEFAULT_ATTEMPTS;
	NSArray *delays = nil;
	WFParseRetryCycle(start.retryTimeCycle, &attempts, &delays);
	WFJobEntity *job = [self insert:WFJobName];
	job.jobId = [WFCommandContext newId];
	job.jobType = WFJobTypeTimerStart;
	job.activityId = start.elementId;
	job.definitionId = definition.definitionId;
	job.dueDate = due;
	job.createdAt = [NSDate date];
	job.retries = (int32_t)attempts;
	job.exclusive = YES;
	job.repeat = remaining;
	[self historyJob:job state:WFJobLogStateCreated];
	NSString *jobId = job.jobId;
	WFProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine wf_jobCreated:jobId processInstanceId:nil dueDate:due exclusive:YES];
	}];
}

- (void)raiseIncident:(NSString *)type
        configuration:(NSString *)configuration
              message:(NSString *)message
           activityId:(NSString *)activityId
    processInstanceId:(NSString *)processInstanceId
            execution:(WFExecutionEntity *)execution
{
	WFIncidentEntity *incident = [self insert:WFIncidentName];
	incident.incidentId = [WFCommandContext newId];
	incident.incidentType = type;
	incident.configuration = configuration;
	incident.message = message;
	incident.activityId = activityId;
	incident.processInstanceId = processInstanceId;
	incident.createdAt = [NSDate date];
	incident.execution = execution;
	if ([self records:WFHistoryLevelFull]) {
		WFHistoricIncidentEntity *row = [self insert:WFHistoricIncidentName];
		row.incidentId = incident.incidentId;
		row.incidentType = type;
		row.configuration = configuration;
		row.message = message;
		row.activityId = activityId;
		row.processInstanceId = processInstanceId;
		row.createdAt = incident.createdAt;
		row.state = WFIncidentStateOpen;
	}
}

- (void)resolveIncidentsFor:(NSString *)configuration
{
	for (WFIncidentEntity *incident in [self fetch:WFIncidentName
	                                     predicate:[NSPredicate predicateWithFormat:
	                                         @"configuration == %@", configuration]
	                                          sort:nil
	                                         limit:0]) {
		[self incident:incident.incidentId endedAs:WFIncidentStateResolved];
		[self remove:incident];
	}
}

/* What a path waits for has come: an event, or a receive task's
 * message. */
- (void)event:(WFFlowNode *)node
  triggeredOn:(WFExecutionEntity *)execution
 subscription:(WFEventSubscriptionEntity *)subscription
{
	WFEvent *event = [node isKindOfClass:[WFEvent class]] ? (WFEvent *)node : nil;
	if (event != nil && event.kind == WFEventKindStart) {
		[self eventSubProcessStarted:event on:execution];
		return;
	}
	if (event != nil && event.kind == WFEventKindBoundary) {
		[self boundary:event firedOn:execution subscription:subscription];
		return;
	}
	WFFlowNode *at = [self node:execution.activityId of:execution];
	if ([at isKindOfClass:[WFGateway class]]
	    && [(WFGateway *)at kind] == WFGatewayKindEventBased) {
		/* The first event behind an event-based gateway wins; the others
		 * stop waiting. Only the gateway's: an event subprocess of the
		 * scope may be waiting on the same execution. */
		NSMutableSet *targets = [NSMutableSet set];
		WFProcessDefinition *scope = [self scopeOf:at.elementId execution:execution];
		for (WFSequenceFlow *flow in [scope outgoingFlowsFrom:at.elementId]) {
			[targets addObject:flow.targetId];
		}
		for (WFEventSubscriptionEntity *other in [execution.eventSubscriptions allObjects]) {
			if ([targets containsObject:other.activityId]) {
				[self remove:other];
			}
		}
		for (WFJobEntity *other in [execution.jobs allObjects]) {
			if ([targets containsObject:other.activityId]) {
				[self historyJob:other state:WFJobLogStateDeleted];
				[self remove:other];
			}
		}
		if (![self fire:at.executionListeners event:WFListenerEventEnd on:execution activity:at.elementId
		      canceled:NO]) {
			return;
		}
		[self activityEnded:execution.activityInstanceId canceled:NO];
		execution.activityId = node.elementId;
		execution.activityInstanceId = [WFCommandContext newId];
		[self activityStarted:node execution:execution];
	} else {
		if (subscription != nil) {
			[self remove:subscription];
		}
		if (event == nil) {
			/* A receive task, which may be a scope of its own. */
			[self completeActivity:execution];
			return;
		}
	}
	[self leave:node execution:execution];
}

/* inner is the scope execution of the activity the boundary event is on. */
- (void)boundary:(WFEvent *)boundary
         firedOn:(WFExecutionEntity *)inner
    subscription:(WFEventSubscriptionEntity *)subscription
{
	WFExecutionEntity *host = inner.parent;
	if (boundary.isInterrupting) {
		[self cancelSubtree:inner];
		[self fireCanceledEndOf:host];
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
	WFExecutionEntity *path = nil;
	if (host.isConcurrent) {
		path = [self newChildOf:host.parent concurrent:YES];
	} else {
		/* The host path becomes one of two concurrent paths. */
		WFExecutionEntity *moved = [self newChildOf:host concurrent:YES];
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
- (void)pass:(WFEvent *)boundary on:(WFExecutionEntity *)path
{
	path.activityId = boundary.elementId;
	if (boundary.isAsyncBefore) {
		path.activityInstanceId = nil;
		[self job:WFJobTypeAsyncBefore execution:path node:boundary due:[NSDate date]];
		return;
	}
	path.activityInstanceId = [WFCommandContext newId];
	[self activityStarted:boundary execution:path];
	[self leave:boundary execution:path];
}

/* The boundary on the node that catches a thrown error or escalation
 * with the code: one for that code, else a catch-all. */
- (WFEvent *)catcherOn:(WFFlowNode *)node
                 scope:(WFProcessDefinition *)scope
               trigger:(WFEventTrigger)trigger
                  code:(NSString *)code
{
	WFEvent *catchAll = nil;
	for (WFEvent *boundary in [scope boundaryEventsAttachedTo:node.elementId]) {
		if (boundary.trigger != trigger) {
			continue;
		}
		NSString *ref = boundary.errorRef;
		if (ref == nil || [ref length] == 0 || [ref isEqualToString:@"*"]) {
			catchAll = catchAll ?: boundary;
		} else if ([ref isEqualToString:code]) {
			return boundary;
		}
	}
	return catchAll;
}

/* The catching event's code variable gets the code it caught. */
- (BOOL)caught:(NSString *)code by:(WFEvent *)catcher on:(WFExecutionEntity *)execution
{
	if (catcher.codeVariable == nil) {
		return YES;
	}
	return [self setVariables:@{ catcher.codeVariable: code ?: [NSNull null] } from:execution];
}

/* A thrown error or escalation travels outward through the scopes around
 * the thrower -- the activity's own, if it has boundary events, then each
 * enclosing subprocess, then, out of a called instance, the call activity
 * and the scopes around it. At each scope its event subprocesses catch it
 * first, inside the boundary events of the activity around the scope --
 * unless it comes out of one of them. NO when nothing caught it. */
- (BOOL)propagate:(WFEventTrigger)trigger code:(NSString *)code from:(WFExecutionEntity *)execution
{
	WFProcessDefinition *definition = [self definitionForExecution:execution];
	WFExecutionEntity *scopeExecution = execution;
	/* The execution it came up through, just below this one. */
	WFExecutionEntity *below = nil;
	while (scopeExecution != nil) {
		WFProcessDefinition *inner = scopeExecution.isScope ? [self definitionScopeOf:scopeExecution] : nil;
		if (inner != nil && ![self isEventSubProcess:scopeExecution.activityId in:inner]
		    && ![self isEventSubProcess:below.activityId in:inner]) {
			WFSubProcess *handler = [self eventSubProcessIn:inner catching:trigger code:code];
			if (handler != nil) {
				WFEvent *start = [handler.innerDefinition startEvent];
				if (![self caught:code by:start on:scopeExecution]) {
					return YES;
				}
				if (start.isInterrupting) {
					[self interruptScope:scopeExecution];
					[self enterNow:handler execution:scopeExecution];
				} else {
					WFExecutionEntity *path = [self pathBeside:scopeExecution
					                                   keeping:[self scopeWaitsOf:inner]];
					[self enterNow:handler execution:path];
				}
				return YES;
			}
		}
		if (scopeExecution.parent == nil) {
			WFExecutionEntity *caller = scopeExecution.superExecution;
			if (caller == nil) {
				return NO;
			}
			definition = [self definitionForExecution:caller];
			WFFlowNode *call = [definition flowNodeWithId:caller.activityId];
			WFEvent *catcher = [call isKindOfClass:[WFCallActivity class]]
				? [self catcherOn:call scope:[definition scopeOfFlowNode:call.elementId]
				          trigger:trigger code:code]
				: nil;
			if (catcher != nil) {
				/* A call activity with boundary events is a scope: the
				 * caller is its scope execution, or, for one instance of a
				 * multi-instance call activity, the instance under the
				 * body that has them. The outputs are passed back as on a
				 * normal end. */
				NSDictionary *outputs = [self outputsOf:(WFCallActivity *)call
				                                   from:[self visibleVariables:scopeExecution]];
				WFExecutionEntity *scopeOfCall = [self isInstance:caller of:call]
					? caller.parent : caller;
				if ([self setVariables:outputs from:caller] && [self caught:code by:catcher on:caller]) {
					[self boundary:catcher firedOn:scopeOfCall subscription:nil];
				}
				return YES;
			}
			below = nil;
			scopeExecution = caller;
			continue;
		}
		if (scopeExecution.isScope && !scopeExecution.parent.isMultiInstanceBody) {
			/* An instance's boundary events are its body's, which is next. */
			NSString *ownerId = scopeExecution.parent.activityId;
			WFFlowNode *owner = [definition flowNodeWithId:ownerId];
			WFEvent *catcher = nil;
			if ([owner isKindOfClass:[WFTask class]] || [owner isKindOfClass:[WFSubProcess class]]) {
				catcher = [self catcherOn:owner scope:[definition scopeOfFlowNode:ownerId]
				                  trigger:trigger code:code];
			}
			if (catcher != nil) {
				if ([self caught:code by:catcher on:scopeExecution]) {
					[self boundary:catcher firedOn:scopeExecution subscription:nil];
				}
				return YES;
			}
		}
		below = scopeExecution;
		scopeExecution = scopeExecution.parent;
	}
	return NO;
}

- (void)throwBpmnError:(NSString *)errorCode fromExecution:(WFExecutionEntity *)execution
{
	if ([self propagate:WFEventTriggerError code:errorCode from:execution]) {
		return;
	}
	/* Nothing catches it: the path ends, as the reference does by default. */
	WFProcessDefinition *definition = [self definitionForExecution:execution];
	WFFlowNode *node = [definition flowNodeWithId:execution.activityId];
	if (node != nil && [self isActivityScope:execution node:node]) {
		WFExecutionEntity *host = execution.parent;
		[self cancelSubtree:execution];
		[self remove:execution];
		[self endPath:host];
	} else {
		[self activityEnded:execution.activityInstanceId canceled:YES];
		[self endPath:execution];
	}
}

/* An escalation from a throw or end event. Unlike an error it is not
 * critical: uncaught, or caught without interrupting the thrower, an
 * intermediate throw goes on and an end event ends its path. */
- (void)throwEscalation:(WFEvent *)event execution:(WFExecutionEntity *)execution
{
	NSString *instance = execution.activityInstanceId;
	WFExecutionEntity *level = execution;
	[self propagate:WFEventTriggerEscalation code:event.escalationCode from:execution];
	/* A non-interrupting catch in this scope may have moved the throwing
	 * path into a concurrent child; an interrupting one removed it. */
	WFExecutionEntity *thrower = nil;
	if (!WFGone(execution) && [execution.activityInstanceId isEqualToString:instance]) {
		thrower = execution;
	} else if (!WFGone(level)) {
		for (WFExecutionEntity *child in [level concurrentChildren]) {
			if ([child.activityInstanceId isEqualToString:instance]) {
				thrower = child;
			}
		}
	}
	if (thrower == nil) {
		return;
	}
	if (event.kind == WFEventKindEnd) {
		[self activityEnded:thrower.activityInstanceId canceled:NO];
		[self endPath:thrower];
	} else {
		[self leave:event execution:thrower];
	}
}

#pragma mark - Compensation

/* The activity's compensation boundary event, if it has one. */
- (WFEvent *)compensationBoundaryOf:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	WFProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	for (WFEvent *boundary in [scope boundaryEventsAttachedTo:node.elementId]) {
		if (boundary.trigger == WFEventTriggerCompensation) {
			return boundary;
		}
	}
	return nil;
}

/* The scope execution in which the node's flow runs, from an execution
 * at or under it. */
- (WFExecutionEntity *)scopeExecutionFor:(WFFlowNode *)node from:(WFExecutionEntity *)execution
{
	WFProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	for (WFExecutionEntity *at = execution; at != nil; at = at.parent) {
		if ([self definitionScopeOf:at] == scope) {
			return at;
		}
	}
	return nil;
}

- (void)compensation:(NSString *)activityId
                 via:(NSString *)subProcessId
                  on:(WFExecutionEntity *)scopeExecution
{
	[self subscribe:scopeExecution type:WFEventTypeCompensate name:subProcessId ?: @"" activity:activityId];
}

/* An activity with a compensation handler completed: the handler waits on
 * its scope until compensation is thrown there, or the scope ends. */
- (void)recordCompensationFor:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	if (![node isKindOfClass:[WFTask class]] && ![node isKindOfClass:[WFSubProcess class]]
	    && ![node isKindOfClass:[WFCallActivity class]]) {
		return;
	}
	if ([self compensationBoundaryOf:node execution:execution] == nil) {
		return;
	}
	WFExecutionEntity *scopeExecution = [self scopeExecutionFor:node from:execution];
	if (scopeExecution != nil) {
		[self compensation:node.elementId via:nil on:scopeExecution];
	}
}

- (NSArray<WFEventSubscriptionEntity *> *)compensationsOn:(WFExecutionEntity *)execution
{
	return [self subscriptions:WFEventTypeCompensate on:execution];
}

- (NSArray<WFEventSubscriptionEntity *> *)subscriptions:(NSString *)type on:(WFExecutionEntity *)execution
{
	NSMutableArray *found = [NSMutableArray array];
	for (WFEventSubscriptionEntity *subscription in execution.eventSubscriptions) {
		if (![subscription isDeleted] && [subscription.eventType isEqualToString:type]) {
			[found addObject:subscription];
		}
	}
	/* Newest first: compensation undoes in reverse. */
	return [found sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"sequence"
	                                                                            ascending:NO] ]];
}

/* A subprocess completed: the handlers waiting in it move up to the
 * scope around it -- unless it has a handler of its own, which stands for
 * them. */
- (void)carryCompensationsOutOf:(WFExecutionEntity *)inner node:(WFFlowNode *)node host:(WFExecutionEntity *)host
{
	NSArray *waiting = [self compensationsOn:inner];
	if ([waiting count] == 0) {
		return;
	}
	WFExecutionEntity *outer = [self compensationBoundaryOf:node execution:host] == nil
		? [self scopeExecutionFor:node from:host] : nil;
	/* Oldest first, keeping their order. */
	for (WFEventSubscriptionEntity *subscription in [[waiting reverseObjectEnumerator] allObjects]) {
		if (outer != nil) {
			subscription.execution = outer;
			subscription.eventName = node.elementId;
			subscription.sequence = [self.engine wf_nextSequence];
		} else {
			[self remove:subscription];
		}
	}
}

/* A compensation throw or end event: the handlers of the completed
 * activities in its scope -- the one named, or all -- run one after
 * another, newest first, and the thrower waits for them. */
- (void)throwCompensation:(WFEvent *)event execution:(WFExecutionEntity *)execution
{
	WFExecutionEntity *scopeExecution = [self scopeExecutionFor:event from:execution];
	NSString *target = event.activityRef;
	for (WFEventSubscriptionEntity *subscription in [self compensationsOn:scopeExecution]) {
		if (target == nil || [subscription.activityId isEqualToString:target]
		    || [subscription.eventName isEqualToString:target]) {
			/* Queued on the thrower, which works through them. */
			subscription.eventType = WFEventTypeCompensating;
			subscription.execution = execution;
		}
	}
	execution.isActive = NO;
	[self compensateNext:execution];
}

- (void)compensateNext:(WFExecutionEntity *)thrower
{
	WFEventSubscriptionEntity *next = [[self subscriptions:WFEventTypeCompensating on:thrower] firstObject];
	if (next == nil) {
		/* Done: the thrower goes on, or its path ends. */
		thrower.isActive = YES;
		WFFlowNode *event = [self node:thrower.activityId of:thrower];
		if (event == nil) {
			return;
		}
		if ([(WFEvent *)event kind] == WFEventKindEnd) {
			[self activityEnded:thrower.activityInstanceId canceled:NO];
			[self endPath:thrower];
		} else {
			[self leave:event execution:thrower];
		}
		return;
	}
	WFFlowNode *activity = [self node:next.activityId of:thrower];
	WFEvent *boundary = activity != nil ? [self compensationBoundaryOf:activity execution:thrower] : nil;
	WFFlowNode *handler = boundary != nil ? [self node:boundary.compensationHandlerId of:thrower] : nil;
	[self remove:next];
	if (handler == nil) {
		[self compensateNext:thrower];
		return;
	}
	WFExecutionEntity *compensating = [self newChildOf:thrower concurrent:NO];
	compensating.isCompensation = YES;
	[self schedule:^{
		if (!WFGone(compensating)) {
			[self enter:handler execution:compensating];
		}
	}];
}

#pragma mark - Call activities

/* The version of the called process the activity's binding picks. */
- (WFProcessDefinition *)calledDefinition:(WFCallActivity *)call
                                execution:(WFExecutionEntity *)execution
{
	WFRepositoryService *repository = self.engine.repositoryService;
	NSString *key = call.calledElement;
	NSError *error = nil;
	WFProcessDefinition *called = nil;
	switch (call.binding) {
	case WFCalledElementBindingLatest:
		called = [repository latestDefinitionForKey:key error:&error];
		break;
	case WFCalledElementBindingVersion:
		called = [repository definitionForKey:key version:call.calledElementVersion error:&error];
		break;
	case WFCalledElementBindingDeployment: {
		WFProcessDefinition *caller = [self definitionForExecution:execution];
		WFDeployment *deployment = [repository deploymentWithId:caller.deploymentId error:&error];
		for (WFProcessDefinition *candidate in deployment.definitions) {
			if ([candidate.processId isEqualToString:key]) {
				called = candidate;
			}
		}
		if (called == nil && deployment != nil) {
			error = WFCommandError(WFErrorInvalidDefinition,
				[NSString stringWithFormat:@"%@ is not in the deployment of %@",
					key, caller.processId]);
		}
		break;
	}
	}
	if (called == nil) {
		[self fail:WFCommandError(WFErrorInvalidDefinition,
			[NSString stringWithFormat:@"call activity %@: %@", call.elementId,
				[error localizedDescription] ?: @"no process to call"])];
	}
	return called;
}

/* The mappings applied to the variables on one side of the call. */
- (NSDictionary *)map:(NSArray<WFVariableMapping *> *)mappings from:(NSDictionary *)variables
{
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	for (WFVariableMapping *mapping in mappings) {
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

- (NSDictionary *)outputsOf:(WFCallActivity *)call from:(NSDictionary *)calledVariables
{
	return [self map:call.outputs from:calledVariables];
}

/* The activity starts an instance of the called process, in this command,
 * and waits for it. */
- (void)executeCall:(WFCallActivity *)call execution:(WFExecutionEntity *)execution
{
	WFProcessDefinition *called = [self calledDefinition:call execution:execution];
	if (called == nil) {
		return;
	}
	NSString *businessKey = nil;
	for (WFVariableMapping *mapping in call.inputs) {
		if (mapping.isBusinessKey) {
			businessKey = [execution processInstance].businessKey;
		}
	}
	WFExecutionEntity *child =
		[self startProcessInstance:called
		               businessKey:businessKey
		                 variables:[self map:call.inputs from:[self visibleVariables:execution]]
		                startEvent:nil
		            superExecution:execution];
	WFHistoricActivityInstanceEntity *row =
		[_openActivities objectForKey:execution.activityInstanceId ?: @""];
	row.calledProcessInstanceId = child.processInstanceId;
}

/* The called instance has ended: its outputs go to the calling process,
 * and the call activity is left. */
- (void)returnFrom:(NSDictionary *)calledVariables to:(WFExecutionEntity *)caller
{
	WFFlowNode *node = [self node:caller.activityId of:caller];
	if (![node isKindOfClass:[WFCallActivity class]]) {
		[self fail:WFCommandError(WFErrorInvalidState,
			[NSString stringWithFormat:@"the calling execution is at %@, not a call activity",
				caller.activityId])];
		return;
	}
	if ([self setVariables:[self outputsOf:(WFCallActivity *)node from:calledVariables]
	                  from:caller]) {
		[self completeActivity:caller];
	}
}

#pragma mark - Multi-instance

static NSString * const WFNrOfInstances = @"nrOfInstances";
static NSString * const WFNrOfActiveInstances = @"nrOfActiveInstances";
static NSString * const WFNrOfCompletedInstances = @"nrOfCompletedInstances";
static NSString * const WFLoopCounter = @"loopCounter";

/* The instances' items, for a collection, or as many NSNulls as the
 * cardinality says; nil, with the command failed, for a value that is
 * neither a list nor a whole number of zero or more. */
- (NSArray *)itemsOf:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	WFMultiInstance *loop = node.multiInstance;
	NSDictionary *variables = [self visibleVariables:execution];
	if (loop.collection != nil) {
		id items = [loop.collection valueWithVariables:variables];
		if (![items isKindOfClass:[NSArray class]]) {
			[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:
				@"%@: the collection %@ is not a list", node.elementId,
				[loop.collection expressionString]])];
			return nil;
		}
		return items;
	}
	id count = [loop.loopCardinality valueWithVariables:variables];
	NSInteger whole = [count isKindOfClass:[NSNumber class]] ? [count integerValue] : -1;
	if (whole < 0 || whole > 100000 || [count doubleValue] != (double)whole) {
		[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:
			@"%@: the loop cardinality %@ is not a whole number of instances", node.elementId,
			[loop.loopCardinality expressionString]])];
		return nil;
	}
	NSMutableArray *items = [NSMutableArray array];
	for (NSInteger i = 0; i < whole; i++) {
		[items addObject:[NSNull null]];
	}
	return items;
}

- (NSInteger)count:(NSString *)name of:(WFExecutionEntity *)body
{
	return [[[body localVariableNamed:name] wf_value] integerValue];
}

- (void)setCount:(NSString *)name to:(NSInteger)value on:(WFExecutionEntity *)body
{
	[self setLocal:name value:[NSNumber numberWithInteger:value] on:body];
}

/* The path arrives at a multi-instance activity: the body starts, with
 * the activity's boundary events on it, and its first instances. */
- (void)enterMultiInstance:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	WFProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	execution.activityId = node.elementId;
	execution.activityInstanceId = [WFCommandContext newId];
	[self bodyStarted:node execution:execution];
	NSArray *items = [self itemsOf:node execution:execution];
	if (items == nil) {
		return;
	}
	WFExecutionEntity *body = [self newChildOf:execution concurrent:NO];
	body.isMultiInstanceBody = YES;
	body.activityId = node.elementId;
	body.isActive = NO;
	execution.isActive = NO;
	[self armBoundaryEventsOf:node scope:scope on:body];
	NSUInteger count = [items count];
	BOOL sequential = node.multiInstance.isSequential;
	NSUInteger first = sequential ? MIN(count, (NSUInteger)1) : count;
	[self setCount:WFNrOfInstances to:(NSInteger)count on:body];
	[self setCount:WFNrOfActiveInstances to:(NSInteger)first on:body];
	[self setCount:WFNrOfCompletedInstances to:0 on:body];
	if (count == 0) {
		[self completeBody:body node:node];
		return;
	}
	for (NSUInteger i = 0; i < first; i++) {
		[self newInstance:i of:node body:body item:[items objectAtIndex:i]];
	}
}

- (void)newInstance:(NSUInteger)index
                 of:(WFFlowNode *)node
               body:(WFExecutionEntity *)body
               item:(id)item
{
	WFExecutionEntity *instance = [self newChildOf:body concurrent:NO];
	instance.activityId = node.elementId;
	[self setLocal:WFLoopCounter value:[NSNumber numberWithUnsignedInteger:index] on:instance];
	NSString *elementVariable = node.multiInstance.elementVariable;
	if (elementVariable != nil) {
		[self setLocal:elementVariable value:item on:instance];
	}
	[self schedule:^{
		if (!WFGone(instance)) {
			[self enter:node execution:instance];
		}
	}];
}

/* One instance runs the activity as it would run once, less the boundary
 * events, which are its body's. */
- (void)startInstance:(WFFlowNode *)node execution:(WFExecutionEntity *)instance
{
	instance.activityId = node.elementId;
	instance.activityInstanceId = [WFCommandContext newId];
	instance.isActive = YES;
	[self activityStarted:node execution:instance];
	if (![self mapInputsOf:node from:instance into:instance]
	    || ![self fire:node.executionListeners event:WFListenerEventStart on:instance activity:node.elementId
	           canceled:NO]) {
		return;
	}
	if ([node isKindOfClass:[WFSubProcess class]]) {
		WFExecutionEntity *inner = [self newChildOf:instance concurrent:NO];
		instance.isActive = NO;
		WFProcessDefinition *innerDefinition = [(WFSubProcess *)node innerDefinition];
		[self armEventSubProcessesOf:innerDefinition on:inner];
		WFEvent *start = [innerDefinition startEvent];
		[self schedule:^{
			if (!WFGone(inner)) {
				[self enter:start execution:inner];
			}
		}];
		return;
	}
	[self execute:node scope:[self scopeOf:node.elementId execution:instance] execution:instance];
}

/* An instance has finished: the body counts it, and either starts the
 * next (sequential), or, when the completion condition holds or no
 * instance is left, ends. */
- (void)instanceCompleted:(WFExecutionEntity *)instance node:(WFFlowNode *)node
{
	WFExecutionEntity *body = instance.parent;
	[self activityEnded:instance.activityInstanceId canceled:NO];
	if (![self mapOutputsOf:node from:instance to:body]) {
		return;
	}
	[self remove:instance];
	/* Two instances finishing at once both update the body's counts, so
	 * their commands conflict rather than each missing the other. */
	body.lockRevision += 1;
	NSInteger completed = [self count:WFNrOfCompletedInstances of:body] + 1;
	NSInteger active = [self count:WFNrOfActiveInstances of:body] - 1;
	NSInteger total = [self count:WFNrOfInstances of:body];
	[self setCount:WFNrOfCompletedInstances to:completed on:body];
	[self setCount:WFNrOfActiveInstances to:active on:body];

	WFFeelExpression *condition = node.multiInstance.completionCondition;
	if (condition != nil) {
		NSError *error = nil;
		BOOL done = [condition evaluateWithVariables:[self visibleVariables:body] error:&error];
		if (error != nil) {
			[self fail:error];
			return;
		}
		if (done) {
			/* Enough have finished: the others are canceled. */
			for (WFExecutionEntity *other in [body.children allObjects]) {
				if (![other isDeleted]) {
					[self cancelSubtree:other];
					[self remove:other];
				}
			}
			[self setCount:WFNrOfActiveInstances to:0 on:body];
			[self completeBody:body node:node];
			return;
		}
	}
	if (node.multiInstance.isSequential && completed < total) {
		/* The collection is read again, as it is now. */
		NSArray *items = [self itemsOf:node execution:body.parent];
		if (items == nil) {
			return;
		}
		id item = (NSUInteger)completed < [items count] ? [items objectAtIndex:(NSUInteger)completed]
			: [NSNull null];
		[self setCount:WFNrOfActiveInstances to:1 on:body];
		[self newInstance:(NSUInteger)completed of:node body:body item:item];
		return;
	}
	if (active <= 0) {
		[self completeBody:body node:node];
	}
}

/* Every instance is done: the path that arrived leaves the activity. */
- (void)completeBody:(WFExecutionEntity *)body node:(WFFlowNode *)node
{
	WFExecutionEntity *path = body.parent;
	[self remove:body];
	path.isActive = YES;
	[self activityEnded:path.activityInstanceId canceled:NO];
	[self leaveNow:node execution:path];
}

#pragma mark - Event subprocesses

/* The part of the definition whose flow runs directly in this scope
 * execution: the process for an instance, a subprocess's inside for its
 * scope; nil for an activity's own scope, which has no flow of its own. */
- (WFProcessDefinition *)definitionScopeOf:(WFExecutionEntity *)execution
{
	if (execution.parent == nil) {
		return [self definitionForExecution:execution];
	}
	if (!execution.isScope || execution.isMultiInstanceBody || execution.parent.isMultiInstanceBody) {
		return nil;
	}
	WFFlowNode *owner = [[self definitionForExecution:execution] flowNodeWithId:execution.parent.activityId];
	return [owner isKindOfClass:[WFSubProcess class]] ? [(WFSubProcess *)owner innerDefinition] : nil;
}

- (NSArray<WFSubProcess *> *)eventSubProcessesIn:(WFProcessDefinition *)scope
{
	NSMutableArray *found = [NSMutableArray array];
	for (WFFlowNode *node in [scope.nodes allValues]) {
		if ([node isKindOfClass:[WFSubProcess class]] && [(WFSubProcess *)node isTriggeredByEvent]) {
			[found addObject:node];
		}
	}
	/* A stable order, for the error catch-all below. */
	return [found sortedArrayUsingComparator:^NSComparisonResult(WFFlowNode *a, WFFlowNode *b) {
		return [a.elementId compare:b.elementId];
	}];
}

- (BOOL)isEventSubProcess:(NSString *)activityId in:(WFProcessDefinition *)scope
{
	WFFlowNode *node = activityId != nil ? [scope nodeWithId:activityId] : nil;
	return [node isKindOfClass:[WFSubProcess class]] && [(WFSubProcess *)node isTriggeredByEvent];
}

/* The scope's event subprocess whose error or escalation start catches
 * the code: one for that code, else a catch-all. */
- (WFSubProcess *)eventSubProcessIn:(WFProcessDefinition *)scope
                           catching:(WFEventTrigger)trigger
                               code:(NSString *)code
{
	WFSubProcess *catchAll = nil;
	for (WFSubProcess *handler in [self eventSubProcessesIn:scope]) {
		WFEvent *start = [handler.innerDefinition startEvent];
		if (start.trigger != trigger) {
			continue;
		}
		NSString *ref = start.errorRef;
		if (ref == nil || [ref length] == 0 || [ref isEqualToString:@"*"]) {
			catchAll = catchAll ?: handler;
		} else if ([ref isEqualToString:code]) {
			return handler;
		}
	}
	return catchAll;
}

/* What the scope execution waits for on its own account: its event
 * subprocesses' starts. */
- (NSSet *)scopeWaitsOf:(WFProcessDefinition *)scope
{
	NSMutableSet *starts = [NSMutableSet set];
	for (WFSubProcess *other in [self eventSubProcessesIn:scope]) {
		[starts addObject:[other.innerDefinition startEvent].elementId];
	}
	return starts;
}

/* A scope starts: its event subprocesses' message, signal and conditional
 * starts subscribe, and their timers are set, on the scope execution, for
 * as long as it lasts. Error starts are found when an error is thrown. */
- (void)armEventSubProcessesOf:(WFProcessDefinition *)scope on:(WFExecutionEntity *)execution
{
	for (WFSubProcess *handler in [self eventSubProcessesIn:scope]) {
		[self armEventSubProcessStart:[handler.innerDefinition startEvent] on:execution];
	}
}

- (void)armEventSubProcessStart:(WFEvent *)start on:(WFExecutionEntity *)execution
{
	if (start.trigger == WFEventTriggerMessage) {
		[self subscribe:execution message:start.messageName activity:start.elementId];
	} else if (start.trigger == WFEventTriggerSignal) {
		[self subscribe:execution type:WFEventTypeSignal name:start.signalName activity:start.elementId];
	} else if (start.trigger == WFEventTriggerTimer) {
		[self timer:execution event:start];
	} else if (start.trigger == WFEventTriggerConditional) {
		[self waitForCondition:start on:execution];
	}
}

/* An event subprocess's start event has fired on its scope execution. */
- (void)eventSubProcessStarted:(WFEvent *)start on:(WFExecutionEntity *)scopeExecution
{
	WFProcessDefinition *scope = [self definitionScopeOf:scopeExecution];
	WFSubProcess *handler = nil;
	for (WFSubProcess *candidate in [self eventSubProcessesIn:scope]) {
		if ([[candidate.innerDefinition startEvent].elementId isEqualToString:start.elementId]) {
			handler = candidate;
		}
	}
	if (handler == nil) {
		[self fail:WFCommandError(WFErrorUnknownElement, [NSString stringWithFormat:
			@"%@ starts no event subprocess of its scope", start.elementId])];
		return;
	}
	if (start.isInterrupting) {
		/* Everything else in the scope stops; the scope goes on in the
		 * event subprocess and ends with it. */
		[self interruptScope:scopeExecution];
		[self enterNow:handler execution:scopeExecution];
		return;
	}
	/* Beside the scope's other paths; a message or signal start stays
	 * armed for the next one. */
	WFExecutionEntity *path = [self pathBeside:scopeExecution keeping:[self scopeWaitsOf:scope]];
	[self enterNow:handler execution:path];
}

/* Cancels everything in the scope -- its paths, and what the scope
 * execution itself was doing or waiting for -- leaving the scope
 * execution to go on. */
- (void)interruptScope:(WFExecutionEntity *)scopeExecution
{
	[self cancelSubtree:scopeExecution];
	for (WFExecutionEntity *child in [scopeExecution.children allObjects]) {
		if (![child isDeleted]) {
			[self remove:child];
		}
	}
	NSArray *rows = [[[[[scopeExecution.tasks allObjects]
		arrayByAddingObjectsFromArray:[scopeExecution.externalTasks allObjects]]
		arrayByAddingObjectsFromArray:[scopeExecution.jobs allObjects]]
		arrayByAddingObjectsFromArray:[scopeExecution.eventSubscriptions allObjects]]
		arrayByAddingObjectsFromArray:[scopeExecution.incidents allObjects]];
	for (NSManagedObject *row in rows) {
		if (![row isDeleted]) {
			[self remove:row];
		}
	}
	scopeExecution.activityId = nil;
	scopeExecution.activityInstanceId = nil;
	scopeExecution.isActive = YES;
}

/* A new concurrent path in the scope. When the scope execution is itself
 * the scope's one path, what that path is doing moves into a concurrent
 * child first -- everything but the scope's own waits: the event
 * subprocesses' starts, and the boundary events of its activity. */
- (WFExecutionEntity *)pathBeside:(WFExecutionEntity *)scopeExecution keeping:(NSSet *)scopeWaits
{
	/* The boundary events of the activity whose scope this is wait on the
	 * scope too. */
	WFExecutionEntity *host = scopeExecution.parent;
	if (host.activityId != nil) {
		NSMutableSet *waits = [scopeWaits mutableCopy] ?: [NSMutableSet set];
		for (WFEvent *boundary in [[self scopeOf:host.activityId execution:host]
		         boundaryEventsAttachedTo:host.activityId]) {
			[waits addObject:boundary.elementId];
		}
		scopeWaits = waits;
	}
	if ([[scopeExecution concurrentChildren] count] == 0
	    && (scopeExecution.activityId != nil || [scopeExecution.children count] > 0)) {
		NSArray *children = [scopeExecution.children allObjects];
		WFExecutionEntity *moved = [self newChildOf:scopeExecution concurrent:YES];
		moved.activityId = scopeExecution.activityId;
		moved.activityInstanceId = scopeExecution.activityInstanceId;
		moved.isActive = scopeExecution.isActive;
		for (WFExecutionEntity *child in children) {
			if (![child isDeleted]) {
				child.parent = moved;
			}
		}
		for (WFTaskEntity *task in [scopeExecution.tasks allObjects]) {
			task.execution = moved;
		}
		for (WFExternalTaskEntity *externalTask in [scopeExecution.externalTasks allObjects]) {
			externalTask.execution = moved;
		}
		for (WFIncidentEntity *incident in [scopeExecution.incidents allObjects]) {
			incident.execution = moved;
		}
		for (WFJobEntity *job in [scopeExecution.jobs allObjects]) {
			if (![scopeWaits containsObject:job.activityId]) {
				job.execution = moved;
			}
		}
		for (WFEventSubscriptionEntity *subscription in [scopeExecution.eventSubscriptions allObjects]) {
			/* Completed activities' handlers belong to the scope too. */
			if (![scopeWaits containsObject:subscription.activityId]
			    && ![subscription.eventType isEqualToString:WFEventTypeCompensate]) {
				subscription.execution = moved;
			}
		}
		WFExecutionEntity *called = scopeExecution.subProcessInstance;
		if (called != nil) {
			called.superExecution = moved;
		}
		scopeExecution.activityId = nil;
		scopeExecution.activityInstanceId = nil;
		scopeExecution.isActive = NO;
	}
	return [self newChildOf:scopeExecution concurrent:YES];
}

#pragma mark - Suspending and deleting

- (BOOL)isDefinitionSuspended:(NSString *)definitionId
{
	if (definitionId == nil) {
		return NO;
	}
	NSManagedObject *record = [[self fetch:WFDefinitionRecordName
	                             predicate:[NSPredicate predicateWithFormat:@"definitionId == %@", definitionId]
	                                  sort:nil
	                                 limit:1] lastObject];
	return [[record valueForKey:@"suspended"] boolValue];
}

/* The instance and the instances its call activities started, and theirs:
 * every execution, task, job and external task. */
- (void)setSuspended:(BOOL)suspended processInstance:(NSString *)processInstanceId
{
	NSPredicate *mine = [NSPredicate predicateWithFormat:@"processInstanceId == %@", processInstanceId];
	for (NSString *entity in @[ WFExecutionName, WFTaskName, WFJobName, WFExternalTaskName ]) {
		for (NSManagedObject *row in [self fetch:entity predicate:mine sort:nil limit:0]) {
			[row setValue:[NSNumber numberWithBool:suspended] forKey:@"suspended"];
		}
	}
	for (WFExecutionEntity *called in [self fetch:WFExecutionName
	                                    predicate:[NSPredicate predicateWithFormat:
	                                        @"superProcessInstanceId == %@ AND parent == nil", processInstanceId]
	                                         sort:nil
	                                        limit:0]) {
		[self setSuspended:suspended processInstance:called.processInstanceId];
	}
}

- (void)setSuspended:(BOOL)suspended definition:(NSString *)definitionId includeInstances:(BOOL)instances
{
	NSManagedObject *record = [[self fetch:WFDefinitionRecordName
	                             predicate:[NSPredicate predicateWithFormat:@"definitionId == %@", definitionId]
	                                  sort:nil
	                                 limit:1] lastObject];
	if (record == nil) {
		[self fail:WFCommandError(WFErrorUnknownElement,
			[NSString stringWithFormat:@"no definition %@", definitionId])];
		return;
	}
	[record setValue:[NSNumber numberWithBool:suspended] forKey:@"suspended"];
	/* Its timer start event waits too. */
	for (WFJobEntity *job in [self fetch:WFJobName
	                           predicate:[NSPredicate predicateWithFormat:
	                               @"jobType == %@ AND definitionId == %@", WFJobTypeTimerStart, definitionId]
	                                sort:nil
	                               limit:0]) {
		job.suspended = suspended;
	}
	if (instances) {
		for (WFExecutionEntity *root in [self fetch:WFExecutionName
		                                  predicate:[NSPredicate predicateWithFormat:
		                                      @"definitionId == %@ AND parent == nil", definitionId]
		                                       sort:nil
		                                      limit:0]) {
			[self setSuspended:suspended processInstance:root.processInstanceId];
		}
	}
}

/* Everything in the instance is canceled -- its tasks deleted, the
 * instances it called terminated -- and its history ends as externally
 * terminated, with the reason. */
- (void)deleteProcessInstance:(WFExecutionEntity *)root reason:(NSString *)reason
{
	[self cancelSubtree:root];
	[self fire:[[self definitionForExecution:root] executionListeners] event:WFListenerEventEnd on:root
	  activity:nil canceled:YES];
	WFHistoricProcessInstanceEntity *history = [[self fetch:WFHistoricInstanceName
	                                              predicate:[NSPredicate predicateWithFormat:
	                                                  @"processInstanceId == %@", root.processInstanceId]
	                                                   sort:nil
	                                                  limit:1] lastObject];
	history.endTime = [NSDate date];
	history.state = WFHistoricStateExternallyTerminated;
	history.deleteReason = reason;
	[self remove:root];
}

#pragma mark - Modification

/* The root and every execution under it. */
- (NSArray<WFExecutionEntity *> *)executionsUnder:(WFExecutionEntity *)root
{
	NSMutableArray *all = [NSMutableArray array];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
	while ([pending count] > 0) {
		WFExecutionEntity *execution = [pending lastObject];
		[pending removeLastObject];
		if (WFGone(execution)) {
			continue;
		}
		[all addObject:execution];
		[pending addObjectsFromArray:[execution.children allObjects]];
	}
	return all;
}

/* The execution that holds an activity instance: the topmost of those
 * that carry its id -- a scope activity's host, not its inner scope. */
- (WFExecutionEntity *)executionOfActivityInstance:(NSString *)activityInstanceId under:(WFExecutionEntity *)root
{
	for (WFExecutionEntity *execution in [self executionsUnder:root]) {
		if (execution.activityId != nil && [execution.activityInstanceId isEqualToString:activityInstanceId]
		    && ![execution.parent.activityInstanceId isEqualToString:activityInstanceId]) {
			return execution;
		}
	}
	return nil;
}

- (NSDictionary *)activityInstanceTreeOf:(WFExecutionEntity *)root
{
	NSMutableDictionary *top = [@{ @"activityInstanceId": root.processInstanceId,
		@"activityId": [[self definitionForExecution:root] processId] ?: @"",
		@"children": [NSMutableArray array] } mutableCopy];
	NSMutableSet *seen = [NSMutableSet set];
	[self addActivityInstancesOf:root to:top seen:seen];
	return top;
}

- (void)addActivityInstancesOf:(WFExecutionEntity *)execution
                            to:(NSMutableDictionary *)parent
                          seen:(NSMutableSet *)seen
{
	NSMutableDictionary *node = parent;
	NSString *activityInstanceId = execution.activityInstanceId;
	if (execution.activityId != nil && activityInstanceId != nil && ![seen containsObject:activityInstanceId]) {
		BOOL body = NO;
		for (WFExecutionEntity *child in execution.children) {
			body = body || child.isMultiInstanceBody;
		}
		node = [@{ @"activityInstanceId": activityInstanceId,
			@"activityId": body ? [execution.activityId stringByAppendingString:@"#multiInstanceBody"]
				: execution.activityId,
			@"parentActivityInstanceId": [parent objectForKey:@"activityInstanceId"],
			@"children": [NSMutableArray array] } mutableCopy];
		[[parent objectForKey:@"children"] addObject:node];
		[seen addObject:activityInstanceId];
	}
	NSArray *children = [[execution.children allObjects] sortedArrayUsingComparator:
		^NSComparisonResult(WFExecutionEntity *a, WFExecutionEntity *b) {
			return [a.executionId compare:b.executionId];
		}];
	for (WFExecutionEntity *child in children) {
		if (!WFGone(child)) {
			[self addActivityInstancesOf:child to:node seen:seen];
		}
	}
}

/* Everything the execution holds is canceled and removed; it stays,
 * doing nothing. */
- (void)clearExecution:(WFExecutionEntity *)execution
{
	[self cancelSubtree:execution];
	for (WFExecutionEntity *child in [execution.children allObjects]) {
		if (!WFGone(child)) {
			[self remove:child];
		}
	}
	NSArray *rows = [[[[[execution.tasks allObjects]
		arrayByAddingObjectsFromArray:[execution.externalTasks allObjects]]
		arrayByAddingObjectsFromArray:[execution.jobs allObjects]]
		arrayByAddingObjectsFromArray:[execution.eventSubscriptions allObjects]]
		arrayByAddingObjectsFromArray:[execution.incidents allObjects]];
	for (NSManagedObject *row in rows) {
		if (!WFGone(row)) {
			[self remove:row];
		}
	}
	execution.activityId = nil;
	execution.activityInstanceId = nil;
	execution.isActive = NO;
}

/* An execution left with nothing to do goes; a scope it empties is
 * canceled in turn, up to the process instance, which is only checked
 * once every instruction has run. */
- (void)detachEmpty:(WFExecutionEntity *)execution
{
	WFExecutionEntity *parent = execution.parent;
	if (parent == nil) {
		return;
	}
	if (execution.isConcurrent) {
		[self remove:execution];
		NSArray *paths = [parent concurrentChildren];
		if ([paths count] == 0) {
			[self detachEmpty:parent];
		} else {
			if ([paths count] == 1) {
				[self compact:parent into:[paths objectAtIndex:0]];
			}
			[self retryInclusiveJoinsAt:parent];
		}
		return;
	}
	[self remove:execution];
	if (parent.isMultiInstanceBody) {
		/* One instance fewer; with none left, the activity is canceled. */
		[self setCount:WFNrOfActiveInstances to:MAX(0, [self count:WFNrOfActiveInstances of:parent] - 1) on:parent];
		if ([parent.children count] == 0 && parent.parent.activityInstanceId != nil) {
			[self cancelActivityInstance:parent.parent.activityInstanceId under:[parent processInstance]];
		}
		return;
	}
	if (parent.activityInstanceId != nil && parent.activityId != nil) {
		/* The inner scope of a subprocess or a scope activity: the activity
		 * instance around it is canceled. */
		[self cancelActivityInstance:parent.activityInstanceId under:[parent processInstance]];
		return;
	}
	[self clearExecution:parent];
	[self detachEmpty:parent];
}

- (BOOL)cancelActivityInstance:(NSString *)activityInstanceId under:(WFExecutionEntity *)root
{
	WFExecutionEntity *execution = [self executionOfActivityInstance:activityInstanceId under:root];
	if (execution == nil) {
		[self fail:WFCommandError(WFErrorUnknownElement, [NSString stringWithFormat:
			@"process instance %@ has no activity instance %@", root.processInstanceId, activityInstanceId])];
		return NO;
	}
	[self clearExecution:execution];
	[self detachEmpty:execution];
	return YES;
}

/* The subprocess whose inside the scope is. */
- (WFSubProcess *)containerOf:(WFProcessDefinition *)scope in:(WFProcessDefinition *)definition
{
	for (WFFlowNode *node in [definition.nodes allValues]) {
		if (![node isKindOfClass:[WFSubProcess class]]) {
			continue;
		}
		WFProcessDefinition *inner = [(WFSubProcess *)node innerDefinition];
		if (inner == scope) {
			return (WFSubProcess *)node;
		}
		WFSubProcess *nested = [self containerOf:scope in:inner];
		if (nested != nil) {
			return nested;
		}
	}
	return nil;
}

/* A subprocess instance opened without its start event: its inputs
 * mapped, its boundary events and event subprocesses armed, and its inner
 * scope, empty, answered for work to start in. */
- (WFExecutionEntity *)openScope:(WFSubProcess *)container on:(WFExecutionEntity *)path
{
	WFProcessDefinition *scope = [self scopeOf:container.elementId execution:path];
	path.activityId = container.elementId;
	path.activityInstanceId = [WFCommandContext newId];
	[self activityStarted:container execution:path];
	WFExecutionEntity *inner = [self newChildOf:path concurrent:NO];
	path.isActive = NO;
	if (![self mapInputsOf:container from:path into:inner]) {
		return nil;
	}
	[self armBoundaryEventsOf:container scope:scope on:inner];
	[self armEventSubProcessesOf:container.innerDefinition on:inner];
	if (![self fire:container.executionListeners event:WFListenerEventStart on:inner activity:container.elementId
	      canceled:NO]) {
		return nil;
	}
	return inner;
}

/* Somewhere new to start in the scope: the scope execution itself when it
 * holds nothing, else a path beside what it holds. */
- (WFExecutionEntity *)newPathIn:(WFExecutionEntity *)scopeExecution
{
	if (scopeExecution.activityId == nil && [scopeExecution.children count] == 0) {
		scopeExecution.isActive = YES;
		return scopeExecution;
	}
	return [self pathBeside:scopeExecution keeping:[self scopeWaitsOf:[self definitionScopeOf:scopeExecution]]];
}

- (BOOL)execution:(WFExecutionEntity *)execution isUnder:(NSString *)activityInstanceId
{
	for (WFExecutionEntity *scope = execution; scope != nil; scope = scope.parent) {
		if ([scope.activityInstanceId isEqualToString:activityInstanceId]) {
			return YES;
		}
	}
	return NO;
}

/* The scope execution the node's flow runs in: the subprocess instances
 * around it, found or opened, the ancestor saying which when there are
 * several. nil, with the command failed, when that cannot be. */
- (WFExecutionEntity *)scopeExecutionFor:(WFFlowNode *)node
                                    root:(WFExecutionEntity *)root
                                ancestor:(NSString *)ancestor
{
	WFProcessDefinition *definition = [self definitionForExecution:root];
	NSMutableArray *chain = [NSMutableArray array];
	for (WFProcessDefinition *scope = [definition scopeOfFlowNode:node.elementId];
	     scope != nil && scope != definition; ) {
		WFSubProcess *container = [self containerOf:scope in:definition];
		if (container == nil) {
			break;
		}
		[chain insertObject:container atIndex:0];
		scope = [definition scopeOfFlowNode:container.elementId];
	}
	WFExecutionEntity *current = root;
	for (WFSubProcess *container in chain) {
		if (container.multiInstance != nil || container.isTriggeredByEvent) {
			[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:
				@"%@ is inside %@, and instances cannot be started inside a %@ subprocess",
				node.elementId, container.elementId, container.multiInstance != nil ? @"multi-instance" : @"event"])];
			return nil;
		}
		NSMutableArray *hosts = [NSMutableArray array];
		for (WFExecutionEntity *execution in [self executionsUnder:current]) {
			if ([execution.activityId isEqualToString:container.elementId] && execution.activityInstanceId != nil
			    && ![execution.parent.activityInstanceId isEqualToString:execution.activityInstanceId]
			    && (ancestor == nil || [self execution:execution isUnder:ancestor]
			        || [self executionOfActivityInstance:ancestor under:execution] != nil)) {
				[hosts addObject:execution];
			}
		}
		if ([hosts count] > 1) {
			[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:
				@"%@ has %lu instances; name the ancestor activity instance to start %@ in",
				container.elementId, (unsigned long)[hosts count], node.elementId])];
			return nil;
		}
		if ([hosts count] == 1) {
			WFExecutionEntity *inner = nil;
			for (WFExecutionEntity *child in [[hosts firstObject] children]) {
				if (child.isScope && !child.isConcurrent && !WFGone(child)) {
					inner = child;
				}
			}
			current = inner ?: current;
			continue;
		}
		current = [self openScope:container on:[self newPathIn:current]];
		if (current == nil) {
			return nil;
		}
	}
	return current;
}

- (WFSequenceFlow *)flowWithId:(NSString *)flowId in:(WFProcessDefinition *)definition
{
	WFSequenceFlow *flow = [definition flowWithId:flowId];
	for (WFFlowNode *node in [definition.nodes allValues]) {
		if (flow == nil && [node isKindOfClass:[WFSubProcess class]]) {
			flow = [self flowWithId:flowId in:[(WFSubProcess *)node innerDefinition]];
		}
	}
	return flow;
}

- (void)startBefore:(NSString *)activityId
           ancestor:(NSString *)ancestor
          variables:(NSDictionary *)variables
               root:(WFExecutionEntity *)root
{
	WFFlowNode *node = [[self definitionForExecution:root] flowNodeWithId:activityId];
	if (node == nil || ([node isKindOfClass:[WFEvent class]] && [(WFEvent *)node kind] == WFEventKindBoundary)) {
		[self fail:WFCommandError(WFErrorUnknownElement, [NSString stringWithFormat:node == nil
			? @"the process has no activity %@" : @"%@ is a boundary event; start after it instead", activityId])];
		return;
	}
	WFExecutionEntity *scopeExecution = [self scopeExecutionFor:node root:root ancestor:ancestor];
	if (scopeExecution == nil) {
		return;
	}
	WFExecutionEntity *path = [self newPathIn:scopeExecution];
	for (NSString *name in variables) {
		if (![self setLocal:name value:[variables objectForKey:name] on:path]) {
			return;
		}
	}
	[self schedule:^{
		if (!WFGone(path)) {
			[self enter:node execution:path];
		}
	}];
}

- (void)startTransition:(NSString *)flowId root:(WFExecutionEntity *)root
{
	WFProcessDefinition *definition = [self definitionForExecution:root];
	WFSequenceFlow *flow = [self flowWithId:flowId in:definition];
	WFFlowNode *source = [definition flowNodeWithId:flow.sourceId];
	if (flow == nil || source == nil) {
		[self fail:WFCommandError(WFErrorUnknownElement, [NSString stringWithFormat:
			@"the process has no sequence flow %@", flowId])];
		return;
	}
	WFExecutionEntity *scopeExecution = [self scopeExecutionFor:source root:root ancestor:nil];
	if (scopeExecution == nil) {
		return;
	}
	[self take:@[ flow ] scope:[definition scopeOfFlowNode:source.elementId] execution:[self newPathIn:scopeExecution]];
}

- (void)modifyProcessInstance:(WFExecutionEntity *)root instructions:(NSArray<NSDictionary *> *)instructions
{
	if (root.suspended) {
		[self fail:WFCommandError(WFErrorSuspended, [NSString stringWithFormat:
			@"process instance %@ is suspended", root.processInstanceId])];
		return;
	}
	WFProcessDefinition *definition = [self definitionForExecution:root];
	for (NSDictionary *instruction in instructions) {
		if (_failure != nil) {
			return;
		}
		NSString *type = [instruction objectForKey:@"type"];
		NSString *target = [instruction objectForKey:@"target"];
		if ([type isEqualToString:@"startBefore"]) {
			[self startBefore:target ancestor:[instruction objectForKey:@"ancestor"]
			        variables:[instruction objectForKey:@"variables"] root:root];
		} else if ([type isEqualToString:@"startAfter"]) {
			WFFlowNode *node = [definition flowNodeWithId:target];
			NSArray *outgoing = [[definition scopeOfFlowNode:target] outgoingFlowsFrom:target];
			if (node == nil || [outgoing count] != 1) {
				[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:node == nil
					? @"the process has no activity %@" : @"%@ has %lu outgoing flows; start after an activity with one",
					target, (unsigned long)[outgoing count]])];
				return;
			}
			[self startTransition:[[outgoing firstObject] elementId] root:root];
		} else if ([type isEqualToString:@"startTransition"]) {
			[self startTransition:target root:root];
		} else if ([type isEqualToString:@"cancel"]) {
			[self cancelActivityInstance:target under:root];
		} else if ([type isEqualToString:@"cancelAll"]) {
			NSMutableArray *instances = [NSMutableArray array];
			for (WFExecutionEntity *execution in [self executionsUnder:root]) {
				if ([execution.activityId isEqualToString:target] && execution.activityInstanceId != nil
				    && ![instances containsObject:execution.activityInstanceId]) {
					[instances addObject:execution.activityInstanceId];
				}
			}
			for (NSString *activityInstanceId in instances) {
				/* An instance inside one canceled before it is gone already. */
				if ([self executionOfActivityInstance:activityInstanceId under:root] != nil) {
					[self cancelActivityInstance:activityInstanceId under:root];
				}
			}
		}
		/* Each instruction's work is done before the next looks. */
		[self runAgenda];
	}
	if (_failure == nil && !WFGone(root) && root.activityId == nil && [root.children count] == 0) {
		[self deleteProcessInstance:root reason:@"all activity instances were canceled"];
	}
}

#pragma mark - Migration

/* Whether two nodes are of one kind, as migration needs them to be. */
static BOOL
WFSameKind(WFFlowNode *a, WFFlowNode *b)
{
	if ([a class] != [b class] || (a.multiInstance == nil) != (b.multiInstance == nil)) {
		return NO;
	}
	if ([a isKindOfClass:[WFTask class]]) {
		return [(WFTask *)a kind] == [(WFTask *)b kind];
	}
	if ([a isKindOfClass:[WFEvent class]]) {
		return [(WFEvent *)a kind] == [(WFEvent *)b kind] && [(WFEvent *)a trigger] == [(WFEvent *)b trigger];
	}
	if ([a isKindOfClass:[WFGateway class]]) {
		return [(WFGateway *)a kind] == [(WFGateway *)b kind];
	}
	if ([a isKindOfClass:[WFSubProcess class]]) {
		return [(WFSubProcess *)a isTriggeredByEvent] == [(WFSubProcess *)b isTriggeredByEvent];
	}
	return YES;
}

/* The id of the subprocess a node is in; nil at the process's level. */
- (NSString *)containerIdOf:(NSString *)nodeId in:(WFProcessDefinition *)definition
{
	WFProcessDefinition *scope = [definition scopeOfFlowNode:nodeId];
	return scope == definition ? nil : [[self containerOf:scope in:definition] elementId];
}

- (void)collectNodesOf:(WFProcessDefinition *)definition into:(NSMutableArray *)nodes
{
	for (WFFlowNode *node in [definition.nodes allValues]) {
		[nodes addObject:node];
		if ([node isKindOfClass:[WFSubProcess class]]) {
			[self collectNodesOf:[(WFSubProcess *)node innerDefinition] into:nodes];
		}
	}
}

- (NSDictionary<NSString *, NSDictionary *> *)migrationFrom:(WFProcessDefinition *)source
                                                          to:(WFProcessDefinition *)target
                                                    mappings:(NSArray<NSDictionary *> *)mappings
                                                    mapEqual:(BOOL)mapEqual
{
	NSMutableDictionary *resolved = [NSMutableDictionary dictionary];
	NSMutableArray *problems = [NSMutableArray array];
	for (NSDictionary *mapping in mappings) {
		NSString *from = [mapping objectForKey:@"source"];
		NSString *to = [mapping objectForKey:@"target"];
		WFFlowNode *a = [source flowNodeWithId:from];
		WFFlowNode *b = [target flowNodeWithId:to];
		if (a == nil || b == nil) {
			[problems addObject:[NSString stringWithFormat:@"%@ -> %@: %@ is not in the %@ definition",
				from, to, a == nil ? from : to, a == nil ? @"source" : @"target"]];
		} else if ([resolved objectForKey:from] != nil) {
			[problems addObject:[NSString stringWithFormat:@"%@ is mapped twice", from]];
		} else if (!WFSameKind(a, b)) {
			[problems addObject:[NSString stringWithFormat:@"%@ -> %@: they are not the same kind of activity", from, to]];
		} else {
			[resolved setObject:@{ @"target": b,
				@"updateEventTrigger": [mapping objectForKey:@"updateEventTrigger"] ?: @NO } forKey:from];
		}
	}
	if (mapEqual) {
		NSMutableArray *nodes = [NSMutableArray array];
		[self collectNodesOf:source into:nodes];
		for (WFFlowNode *a in nodes) {
			WFFlowNode *b = [target flowNodeWithId:a.elementId];
			NSString *containerA = [self containerIdOf:a.elementId in:source];
			NSString *containerB = b != nil ? [self containerIdOf:b.elementId in:target] : nil;
			if ([resolved objectForKey:a.elementId] == nil && b != nil && WFSameKind(a, b)
			    && (containerA == containerB || [containerA isEqualToString:containerB])) {
				[resolved setObject:@{ @"target": b, @"updateEventTrigger": @NO } forKey:a.elementId];
			}
		}
	}
	/* Each mapping stays in corresponding scopes, and a boundary event
	 * with its activity. */
	for (NSString *from in resolved) {
		WFFlowNode *b = [[resolved objectForKey:from] objectForKey:@"target"];
		NSString *containerA = [self containerIdOf:from in:source];
		NSString *containerB = [self containerIdOf:b.elementId in:target];
		NSString *mappedContainer = containerA != nil
			? [[[resolved objectForKey:containerA] objectForKey:@"target"] elementId] : nil;
		if (!(containerA == nil && containerB == nil) && ![mappedContainer isEqualToString:containerB]) {
			[problems addObject:[NSString stringWithFormat:
				@"%@ -> %@: the subprocess around %@ must be mapped to the one around %@", from, b.elementId,
				from, b.elementId]];
		}
		WFFlowNode *a = [source flowNodeWithId:from];
		if ([a isKindOfClass:[WFEvent class]] && [(WFEvent *)a kind] == WFEventKindBoundary) {
			NSString *host = [[[resolved objectForKey:[(WFEvent *)a attachedToId]] objectForKey:@"target"] elementId];
			if (![host isEqualToString:[(WFEvent *)b attachedToId]]) {
				[problems addObject:[NSString stringWithFormat:
					@"%@ -> %@: a boundary event's activity must be mapped to the target's", from, b.elementId]];
			}
		}
	}
	if ([problems count] > 0) {
		[self fail:WFCommandError(WFErrorInvalidDefinition, [NSString stringWithFormat:@"migration plan from %@ to %@: %@",
			source.definitionId, target.definitionId,
			[[problems sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"; "]])];
		return nil;
	}
	return resolved;
}

- (BOOL)migrate:(WFExecutionEntity *)root
      mappings:(NSDictionary<NSString *, NSDictionary *> *)mappings
        source:(WFProcessDefinition *)source
        target:(WFProcessDefinition *)target
{
	if (![root.definitionId isEqualToString:source.definitionId]) {
		[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:
			@"process instance %@ runs on %@, not on the plan's %@", root.processInstanceId,
			root.definitionId, source.definitionId])];
		return NO;
	}
	NSArray *executions = [self executionsUnder:root];
	NSMutableArray *problems = [NSMutableArray array];
	for (WFExecutionEntity *execution in executions) {
		NSString *activityId = execution.activityId;
		if (activityId == nil) {
			continue;
		}
		WFFlowNode *b = [[mappings objectForKey:activityId] objectForKey:@"target"];
		if (b == nil) {
			[problems addObject:[NSString stringWithFormat:@"%@ is not mapped", activityId]];
			continue;
		}
		WFFlowNode *a = [source flowNodeWithId:activityId];
		if ([self isScopeActivity:a scope:[source scopeOfFlowNode:activityId]]
		    != [self isScopeActivity:b scope:[target scopeOfFlowNode:b.elementId]]) {
			[problems addObject:[NSString stringWithFormat:
				@"%@ -> %@: one has boundary events or parameters and the other not", activityId, b.elementId]];
		}
	}
	if ([problems count] > 0) {
		NSArray *distinct = [[[NSSet setWithArray:problems] allObjects] sortedArrayUsingSelector:@selector(compare:)];
		[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:
			@"process instance %@ cannot be migrated: %@", root.processInstanceId,
			[distinct componentsJoinedByString:@"; "]])];
		return NO;
	}
	NSString *(^mapped)(NSString *) = ^NSString *(NSString *activityId) {
		return activityId == nil ? nil : [[[mappings objectForKey:activityId] objectForKey:@"target"] elementId];
	};
	NSPredicate *mine = [NSPredicate predicateWithFormat:@"processInstanceId == %@", root.processInstanceId];
	for (WFExecutionEntity *execution in executions) {
		execution.definitionId = target.definitionId;
		execution.activityId = mapped(execution.activityId) ?: execution.activityId;
	}
	for (WFTaskEntity *task in [self fetch:WFTaskName predicate:mine sort:nil limit:0]) {
		task.taskDefinitionKey = mapped(task.taskDefinitionKey) ?: task.taskDefinitionKey;
		task.definitionId = target.definitionId;
	}
	for (WFExternalTaskEntity *externalTask in [self fetch:WFExternalTaskName predicate:mine sort:nil limit:0]) {
		externalTask.activityId = mapped(externalTask.activityId) ?: externalTask.activityId;
	}
	for (WFIncidentEntity *incident in [self fetch:WFIncidentName predicate:mine sort:nil limit:0]) {
		incident.activityId = mapped(incident.activityId) ?: incident.activityId;
	}
	/* Waits for events that were not mapped go; those mapped keep their
	 * trigger unless the mapping updates it. */
	for (WFJobEntity *job in [self fetch:WFJobName predicate:mine sort:nil limit:0]) {
		NSDictionary *mapping = [mappings objectForKey:job.activityId];
		WFFlowNode *b = [mapping objectForKey:@"target"];
		if (b == nil) {
			[self historyJob:job state:WFJobLogStateDeleted];
			[self remove:job];
			continue;
		}
		job.activityId = b.elementId;
		if ([[mapping objectForKey:@"updateEventTrigger"] boolValue] && [job.jobType isEqualToString:WFJobTypeTimer]
		    && [b isKindOfClass:[WFEvent class]] && [(WFEvent *)b timer] != nil) {
			WFExecutionEntity *execution = job.execution;
			[self historyJob:job state:WFJobLogStateDeleted];
			[self remove:job];
			[self timer:execution event:(WFEvent *)b];
		}
	}
	for (WFEventSubscriptionEntity *subscription in [self fetch:WFSubscriptionName predicate:mine sort:nil limit:0]) {
		NSDictionary *mapping = [mappings objectForKey:subscription.activityId];
		WFFlowNode *b = [mapping objectForKey:@"target"];
		if (b == nil) {
			[self remove:subscription];
			continue;
		}
		subscription.activityId = b.elementId;
		if ([subscription.eventType isEqualToString:WFEventTypeCompensate]
		    || [subscription.eventType isEqualToString:WFEventTypeCompensating]) {
			subscription.eventName = mapped(subscription.eventName) ?: subscription.eventName;
		} else if ([subscription.eventType isEqualToString:WFEventTypeConditional]) {
			subscription.eventName = b.elementId;
		} else if ([[mapping objectForKey:@"updateEventTrigger"] boolValue]) {
			NSString *name = [b isKindOfClass:[WFTask class]] ? [(WFTask *)b messageName]
				: [subscription.eventType isEqualToString:WFEventTypeSignal] ? [(WFEvent *)b signalName]
				: [(WFEvent *)b messageName];
			subscription.eventName = name ?: subscription.eventName;
		}
	}
	[self armWhatTheTargetAdds:executions target:target];
	if ([self records:WFHistoryLevelActivity]) {
		WFHistoricProcessInstanceEntity *history = [[self fetch:WFHistoricInstanceName predicate:mine sort:nil limit:1]
			lastObject];
		history.definitionId = target.definitionId;
		history.definitionKey = target.processId;
		for (WFHistoricActivityInstanceEntity *activity in [self fetch:WFHistoricActivityName
		         predicate:[NSPredicate predicateWithFormat:@"processInstanceId == %@ AND endTime == nil",
		             root.processInstanceId]
		              sort:nil
		             limit:0]) {
			NSString *activityId = activity.activityId;
			BOOL body = [activityId hasSuffix:@"#multiInstanceBody"];
			NSString *plain = body ? [activityId substringToIndex:[activityId length] - 18] : activityId;
			NSString *moved = mapped(plain);
			if (moved != nil) {
				activity.activityId = body ? [moved stringByAppendingString:@"#multiInstanceBody"] : moved;
			}
		}
	}
	return _failure == nil;
}

/* Boundary events and event subprocesses the target has and the source
 * did not: armed where their activity or scope is running. */
- (void)armWhatTheTargetAdds:(NSArray<WFExecutionEntity *> *)executions target:(WFProcessDefinition *)target
{
	for (WFExecutionEntity *execution in executions) {
		if (WFGone(execution)) {
			continue;
		}
		NSMutableSet *armed = [NSMutableSet set];
		for (WFEventSubscriptionEntity *subscription in execution.eventSubscriptions) {
			if (!WFGone(subscription) && subscription.activityId != nil) {
				[armed addObject:subscription.activityId];
			}
		}
		for (WFJobEntity *job in execution.jobs) {
			if (!WFGone(job) && job.activityId != nil) {
				[armed addObject:job.activityId];
			}
		}
		WFProcessDefinition *scope = [self definitionScopeOf:execution];
		if (scope != nil) {
			for (WFSubProcess *handler in [self eventSubProcessesIn:scope]) {
				WFEvent *start = [handler.innerDefinition startEvent];
				if (![armed containsObject:start.elementId]) {
					[self armEventSubProcessStart:start on:execution];
				}
			}
		}
		/* The execution a scope activity's boundary events wait on: its
		 * host's inner scope, or a multi-instance body. */
		WFExecutionEntity *host = execution.parent;
		if (host == nil || !execution.isScope || execution.isConcurrent || host.activityId == nil
		    || execution.parent.isMultiInstanceBody) {
			continue;
		}
		WFFlowNode *node = [target flowNodeWithId:host.activityId];
		WFProcessDefinition *nodeScope = [target scopeOfFlowNode:host.activityId];
		if (node == nil || (node.multiInstance != nil && !execution.isMultiInstanceBody)
		    || (node.multiInstance == nil && ![self isScopeActivity:node scope:nodeScope])) {
			continue;
		}
		for (WFEvent *boundary in [nodeScope boundaryEventsAttachedTo:node.elementId]) {
			if ([armed containsObject:boundary.elementId]) {
				continue;
			}
			if (boundary.trigger == WFEventTriggerMessage) {
				[self subscribe:execution message:boundary.messageName activity:boundary.elementId];
			} else if (boundary.trigger == WFEventTriggerSignal) {
				[self subscribe:execution type:WFEventTypeSignal name:boundary.signalName activity:boundary.elementId];
			} else if (boundary.trigger == WFEventTriggerTimer) {
				[self timer:execution event:boundary];
			} else if (boundary.trigger == WFEventTriggerConditional) {
				[self waitForCondition:boundary on:execution];
			}
		}
	}
}

#pragma mark - Signals and terminate

- (NSUInteger)broadcastSignal:(NSString *)signalName
                    variables:(NSDictionary *)variables
            processInstanceId:(NSString *)processInstanceId
{
	/* Everyone waiting now, as the signal is thrown: a path that comes to
	 * wait for the same signal while it is delivered does not get it. */
	NSArray *subscriptions = [self fetch:WFSubscriptionName
	                           predicate:[NSPredicate predicateWithFormat:
	                               @"eventType == %@ AND eventName == %@",
	                               WFEventTypeSignal, signalName]
	                                sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
	                                                                        ascending:YES] ]
	                               limit:0];
	NSUInteger delivered = 0;
	for (WFEventSubscriptionEntity *subscription in subscriptions) {
		if ([subscription isDeleted] || _failure != nil) {
			continue;
		}
		if (subscription.execution.suspended) {
			continue;
		}
		if (subscription.execution == nil) {
			if (processInstanceId != nil || [self isDefinitionSuspended:subscription.definitionId]) {
				continue;
			}
			NSError *error = nil;
			WFProcessDefinition *definition =
				[self.engine.repositoryService definitionWithId:subscription.definitionId error:&error];
			WFFlowNode *start = [definition flowNodeWithId:
				[[definition startEvent] elementId]];
			if (definition == nil || ![start isKindOfClass:[WFEvent class]]) {
				[self fail:error];
				return delivered;
			}
			[self startProcessInstance:definition businessKey:nil variables:variables
			                startEvent:(WFEvent *)start];
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
- (void)terminate:(WFExecutionEntity *)execution
{
	[self activityEnded:execution.activityInstanceId canceled:NO];
	WFExecutionEntity *scope = [execution scopeExecution];
	for (WFExecutionEntity *child in [scope.children allObjects]) {
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

#pragma mark - Input and output parameters

/* The activity's inputs, evaluated where the path arrives, become local
 * variables of its scope. */
- (BOOL)mapInputsOf:(WFFlowNode *)node from:(WFExecutionEntity *)outer into:(WFExecutionEntity *)scope
{
	if ([node.inputParameters count] == 0) {
		return YES;
	}
	NSDictionary *variables = [self visibleVariables:outer];
	for (WFParameter *parameter in node.inputParameters) {
		id value = parameter.expression != nil ? [parameter.expression valueWithVariables:variables]
			: [NSNull null];
		if (![self setLocal:parameter.name value:value on:scope]) {
			return NO;
		}
	}
	return YES;
}

/* The activity's outputs, evaluated in its scope as it completes, are set
 * where it is. */
- (BOOL)mapOutputsOf:(WFFlowNode *)node from:(WFExecutionEntity *)scope to:(WFExecutionEntity *)outer
{
	if ([node.outputParameters count] == 0) {
		return YES;
	}
	NSDictionary *variables = [self visibleVariables:scope];
	NSMutableDictionary *outputs = [NSMutableDictionary dictionary];
	for (WFParameter *parameter in node.outputParameters) {
		[outputs setObject:parameter.expression != nil ? [parameter.expression valueWithVariables:variables]
			: [NSNull null] forKey:parameter.name];
	}
	return [self setVariables:outputs from:outer];
}

#pragma mark - Tasks

/* One of a user task's assignment attributes evaluated, or nil with the
 * command failed when its value is not what the attribute takes. */
- (id)evaluate:(WFFeelExpression *)expression
      variables:(NSDictionary *)variables
           task:(WFTask *)task
      attribute:(NSString *)attribute
          check:(id (^)(id value))check
{
	id value = [expression valueWithVariables:variables];
	if (value == [NSNull null]) {
		return [NSNull null];
	}
	id checked = check(value);
	if (checked == nil) {
		[self fail:WFCommandError(WFErrorInvalidState, [NSString stringWithFormat:@"%@: %@ %@ is %@",
			task.elementId, attribute, [expression expressionString], value])];
	}
	return checked;
}

- (NSArray *)names:(id)value
{
	if ([value isKindOfClass:[NSString class]]) {
		NSMutableArray *names = [NSMutableArray array];
		for (NSString *part in [value componentsSeparatedByString:@","]) {
			NSString *name = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if ([name length] > 0) {
				[names addObject:name];
			}
		}
		return names;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		for (id item in value) {
			if (![item isKindOfClass:[NSString class]]) {
				return nil;
			}
		}
		return value;
	}
	return nil;
}

/* A user task's assignee, candidates, dates and priority, worked out over
 * the variables visible where it is created. */
- (BOOL)assign:(WFTask *)task to:(WFTaskEntity *)row
{
	NSDictionary *variables = [self visibleVariables:row.execution];
	id (^date)(id) = ^id(id value) {
		if ([value isKindOfClass:[NSDate class]]) {
			return value;
		}
		return [value isKindOfClass:[NSString class]] ? WFFeelParseDateTime(value) : nil;
	};
	if (task.assigneeExpression != nil) {
		id assignee = [self evaluate:task.assigneeExpression variables:variables task:task attribute:@"assignee"
		                       check:^id(id value) {
			return [value isKindOfClass:[NSString class]] ? value : nil;
		}];
		if (assignee == nil) {
			return NO;
		}
		row.assignee = assignee == [NSNull null] ? nil : assignee;
	}
	NSArray *kinds = @[ @[ @"candidateUsers", task.candidateUsers ?: [NSNull null], @"userId" ],
	                    @[ @"candidateGroups", task.candidateGroups ?: [NSNull null], @"groupId" ] ];
	for (NSArray *kind in kinds) {
		if ([kind objectAtIndex:1] == [NSNull null]) {
			continue;
		}
		id names = [self evaluate:[kind objectAtIndex:1] variables:variables task:task
		                attribute:[kind objectAtIndex:0] check:^id(id value) { return [self names:value]; }];
		if (names == nil) {
			return NO;
		}
		for (NSString *name in names == [NSNull null] ? @[] : names) {
			WFIdentityLinkEntity *link = [self insert:WFIdentityLinkName];
			link.type = WFIdentityLinkCandidate;
			[link setValue:name forKey:[kind objectAtIndex:2]];
			link.processInstanceId = row.processInstanceId;
			link.task = row;
		}
	}
	if (task.dueDate != nil) {
		id due = [self evaluate:task.dueDate variables:variables task:task attribute:@"dueDate" check:date];
		if (due == nil) {
			return NO;
		}
		row.dueDate = due == [NSNull null] ? nil : due;
	}
	if (task.followUpDate != nil) {
		id followUp = [self evaluate:task.followUpDate variables:variables task:task attribute:@"followUpDate"
		                       check:date];
		if (followUp == nil) {
			return NO;
		}
		row.followUpDate = followUp == [NSNull null] ? nil : followUp;
	}
	if (task.priority != nil) {
		id priority = [self evaluate:task.priority variables:variables task:task attribute:@"priority"
		                       check:^id(id value) {
			return [value isKindOfClass:[NSNumber class]] && [value doubleValue] == floor([value doubleValue])
				? value : nil;
		}];
		if (priority == nil) {
			return NO;
		}
		row.priority = priority == [NSNull null] ? 50 : (int32_t)[priority intValue];
	}
	return YES;
}

- (void)executeTask:(WFTask *)task execution:(WFExecutionEntity *)execution
{
	if (task.kind == WFTaskKindManual || task.kind == WFTaskKindNone) {
		[self completeActivity:execution];
		return;
	}
	if (task.kind == WFTaskKindReceive) {
		[self subscribe:execution message:task.messageName activity:task.elementId];
		return;
	}
	if (task.kind == WFTaskKindBusinessRule && task.decisionRef != nil) {
		[self evaluateDecisionOf:task execution:execution];
		return;
	}
	if (task.delegate != nil) {
		[self runDelegateOf:task execution:execution];
		return;
	}
	if (task.kind == WFTaskKindUser) {
		WFTaskEntity *row = [self insert:WFTaskName];
		row.taskId = [WFCommandContext newId];
		row.name = task.name;
		row.taskDefinitionKey = task.elementId;
		row.assignee = task.assignee;
		row.processInstanceId = execution.processInstanceId;
		row.definitionId = execution.definitionId;
		row.activityInstanceId = execution.activityInstanceId;
		row.createdAt = [NSDate date];
		row.priority = 50;
		row.execution = execution;
		row.processInstance = [execution processInstance];
		if (task.form != nil) {
			row.form = [[self fetch:@"WFFormRecord"
			              predicate:[NSPredicate predicateWithFormat:@"formId == %@",
			                  [NSString stringWithFormat:@"%@:%@", execution.definitionId, task.elementId]]
			                   sort:nil
			                  limit:1] lastObject];
		}
		if (![self assign:task to:row]) {
			return;
		}
		[self taskStarted:row];
		if (![self fireTaskListeners:WFListenerEventCreate task:row]
		    || (row.assignee != nil && ![self fireTaskListeners:WFListenerEventAssignment task:row])) {
			return;
		}
		WFWorkItem *value = [WFWorkItem wf_workItemWithEntity:row];
		WFProcessEngine *engine = self.engine;
		[self afterCommit:^{
			[engine wf_taskCreated:value];
		}];
		return;
	}
	/* Service, send, business rule and script tasks are external tasks
	 * under the action's topic. */
	WFExternalTaskEntity *row = [self insert:WFExternalTaskName];
	row.externalTaskId = [WFCommandContext newId];
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
	WFProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine wf_externalTaskCreated:externalTaskId processInstanceId:processInstanceId];
	}];
}

#pragma mark - Decisions

/* A value history can keep as JSON: dates as ISO-8601 text. */
static id
WFJSONValue(id value)
{
	if ([value isKindOfClass:[NSDate class]]) {
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		[formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
		[formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
		[formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
		return [formatter stringFromDate:value];
	}
	if ([value isKindOfClass:[NSArray class]]) {
		NSMutableArray *items = [NSMutableArray array];
		for (id item in value) {
			[items addObject:WFJSONValue(item)];
		}
		return items;
	}
	if ([value isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *entries = [NSMutableDictionary dictionary];
		for (id key in value) {
			[entries setObject:WFJSONValue([value objectForKey:key]) forKey:[key description]];
		}
		return entries;
	}
	if (value == nil || [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]
	    || value == [NSNull null]) {
		return value ?: [NSNull null];
	}
	return [value description];
}

- (WFDecisionResult *)evaluateDecision:(WFDecisionDefinition *)decision
                             variables:(NSDictionary *)variables
                             execution:(WFExecutionEntity *)execution
{
	NSMutableDictionary *inputs = [NSMutableDictionary dictionary];
	NSError *error = nil;
	WFDecisionResult *result = [decision evaluateWithVariables:variables inputs:inputs error:&error];
	if (result == nil) {
		[self fail:error];
		return nil;
	}
	if ([self records:WFHistoryLevelFull]) {
		NSManagedObject *row = [self insert:@"WFHistoricDecisionInstance"];
		[row setValue:[WFCommandContext newId] forKey:@"decisionInstanceId"];
		[row setValue:decision.definitionId forKey:@"decisionDefinitionId"];
		[row setValue:decision.key forKey:@"decisionKey"];
		[row setValue:execution.processInstanceId forKey:@"processInstanceId"];
		[row setValue:execution.activityId forKey:@"activityId"];
		[row setValue:execution.activityInstanceId forKey:@"activityInstanceId"];
		[row setValue:[NSDate date] forKey:@"evaluationTime"];
		[row setValue:[NSNumber numberWithLongLong:[self.engine wf_nextSequence]] forKey:@"sequence"];
		[row setValue:[NSJSONSerialization dataWithJSONObject:WFJSONValue(inputs) options:0 error:NULL]
		       forKey:@"inputs"];
		[row setValue:[NSJSONSerialization dataWithJSONObject:WFJSONValue(result.resultList) options:0 error:NULL]
		       forKey:@"outputs"];
	}
	return result;
}

/* The version of the task's decision its binding picks. */
- (WFDecisionDefinition *)decisionOf:(WFTask *)task execution:(WFExecutionEntity *)execution
{
	NSError *error = nil;
	WFRepositoryService *repository = self.engine.repositoryService;
	WFDecisionDefinition *decision = nil;
	switch (task.decisionBinding) {
	case WFCalledElementBindingLatest:
		decision = [repository latestDecisionForKey:task.decisionRef error:&error];
		break;
	case WFCalledElementBindingDeployment:
		decision = [repository decisionForKey:task.decisionRef
		                          inDeployment:[[self definitionForExecution:execution] deploymentId]
		                                 error:&error];
		break;
	case WFCalledElementBindingVersion:
		decision = [repository decisionForKey:task.decisionRef version:task.decisionVersion error:&error];
		break;
	}
	if (decision == nil) {
		[self fail:WFCommandError(WFErrorInvalidDefinition, [NSString stringWithFormat:@"%@: %@",
			task.elementId, [error localizedDescription]])];
	}
	return decision;
}

/* A business rule task with a decision: evaluated now, its result kept as
 * the task maps it, and the task done. */
- (void)evaluateDecisionOf:(WFTask *)task execution:(WFExecutionEntity *)execution
{
	WFDecisionDefinition *decision = [self decisionOf:task execution:execution];
	WFDecisionResult *result = decision != nil
		? [self evaluateDecision:decision variables:[self visibleVariables:execution] execution:execution] : nil;
	if (result == nil) {
		return;
	}
	if (task.resultVariable != nil) {
		NSError *error = nil;
		id value = nil;
		switch (task.mapDecisionResult) {
		case WFDecisionResultMappingResultList:
			value = result.resultList;
			break;
		case WFDecisionResultMappingSingleResult:
			value = [result singleResult:&error];
			break;
		case WFDecisionResultMappingSingleEntry:
			value = [result singleEntry:&error];
			break;
		case WFDecisionResultMappingCollectEntries: {
			NSMutableSet *names = [NSMutableSet set];
			for (NSDictionary *each in result.resultList) {
				[names addObjectsFromArray:[each allKeys]];
			}
			if ([names count] > 1) {
				error = WFCommandError(WFErrorDecision, [NSString stringWithFormat:
					@"collectEntries needs a single output, and the result has %@",
					[[[names allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]]);
			}
			value = [result collectEntries:[names anyObject]];
			break;
		}
		}
		if (error != nil) {
			[self fail:WFCommandError(WFErrorDecision, [NSString stringWithFormat:@"%@: %@",
				task.elementId, [error localizedDescription]])];
			return;
		}
		if (![self setVariables:@{ task.resultVariable: value ?: [NSNull null] } from:execution]) {
			return;
		}
	}
	[self completeActivity:execution];
}

- (void)completeActivity:(WFExecutionEntity *)execution
{
	WFFlowNode *node = [self node:execution.activityId of:execution];
	if (node == nil) {
		return;
	}
	if ([self isActivityScope:execution node:node]) {
		WFExecutionEntity *host = execution.parent;
		if (![self mapOutputsOf:node from:execution to:host]) {
			return;
		}
		[self remove:execution];
		host.isActive = YES;
		[self leave:node execution:host];
		return;
	}
	[self leave:node execution:execution];
}

#pragma mark - Leaving and ending

- (BOOL)condition:(WFSequenceFlow *)flow holdsFor:(WFExecutionEntity *)execution
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
- (void)leave:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	if (![self fire:node.executionListeners event:WFListenerEventEnd on:execution activity:node.elementId
	      canceled:NO]) {
		return;
	}
	[self recordCompensationFor:node execution:execution];
	/* The activity is done, even when an async continuation holds back
	 * the flows out of it. */
	[self activityEnded:execution.activityInstanceId canceled:NO];
	if (node.isAsyncAfter && ![node isKindOfClass:[WFGateway class]]) {
		/* The command stops here; a job takes the outgoing flows. */
		[self job:WFJobTypeAsyncAfter execution:execution node:node due:[NSDate date]];
		return;
	}
	[self leaveNow:node execution:execution];
}

- (void)leaveNow:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	if ([self isInstance:execution of:node]) {
		/* An instance does not take the flows: its body counts it. */
		[self instanceCompleted:execution node:node];
		return;
	}
	WFProcessDefinition *scope = [self scopeOf:node.elementId execution:execution];
	NSMutableArray *flows = [NSMutableArray array];
	for (WFSequenceFlow *flow in [scope outgoingFlowsFrom:node.elementId]) {
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

- (void)take:(NSArray<WFSequenceFlow *> *)flows
       scope:(WFProcessDefinition *)scope
   execution:(WFExecutionEntity *)execution
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
		WFSequenceFlow *flow = [flows objectAtIndex:i];
		WFFlowNode *target = [scope nodeWithId:flow.targetId];
		WFExecutionEntity *path = [paths objectAtIndex:i];
		if (![self fire:flow.listeners event:WFListenerEventTake on:path activity:flow.elementId canceled:NO]) {
			return;
		}
		[self schedule:^{
			if (!WFGone(path)) {
				[self enter:target execution:path];
			}
		}];
	}
}

- (void)endPath:(WFExecutionEntity *)execution
{
	if (!execution.isConcurrent) {
		[self scopeEnded:execution];
		return;
	}
	WFExecutionEntity *level = execution.parent;
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
- (void)compact:(WFExecutionEntity *)level into:(WFExecutionEntity *)path
{
	level.activityId = path.activityId;
	level.activityInstanceId = path.activityInstanceId;
	level.isActive = path.isActive;
	for (WFExecutionEntity *child in [path.children allObjects]) {
		child.parent = level;
	}
	for (WFTaskEntity *task in [path.tasks allObjects]) {
		task.execution = level;
	}
	for (WFEventSubscriptionEntity *subscription in [path.eventSubscriptions allObjects]) {
		subscription.execution = level;
	}
	for (WFJobEntity *job in [path.jobs allObjects]) {
		job.execution = level;
	}
	for (WFExternalTaskEntity *externalTask in [path.externalTasks allObjects]) {
		externalTask.execution = level;
	}
	for (WFIncidentEntity *incident in [path.incidents allObjects]) {
		incident.execution = level;
	}
	/* Before the path goes: removing it would take the called instance
	 * with it. */
	WFExecutionEntity *called = path.subProcessInstance;
	if (called != nil) {
		called.superExecution = level;
	}
	[self remove:path];
}

- (void)scopeEnded:(WFExecutionEntity *)scopeExecution
{
	if (scopeExecution.parent == nil) {
		[self processInstanceEnded:scopeExecution];
		return;
	}
	if (scopeExecution.isCompensation) {
		/* One handler has run: the thrower goes on to the next. */
		WFExecutionEntity *thrower = scopeExecution.parent;
		[self remove:scopeExecution];
		[self compensateNext:thrower];
		return;
	}
	if (scopeExecution.parent.isMultiInstanceBody) {
		/* An instance whose path ended without leaving the activity -- an
		 * uncaught error -- is done all the same. */
		WFFlowNode *node = [self node:scopeExecution.parent.activityId of:scopeExecution];
		if (node != nil) {
			[self instanceCompleted:scopeExecution node:node];
		}
		return;
	}
	/* An embedded subprocess has run to its end: its host path leaves it. */
	WFExecutionEntity *host = scopeExecution.parent;
	WFFlowNode *node = [self node:host.activityId of:host];
	if (node != nil) {
		if (![self mapOutputsOf:node from:scopeExecution to:host]) {
			return;
		}
		[self carryCompensationsOutOf:scopeExecution node:node host:host];
	}
	[self remove:scopeExecution];
	host.isActive = YES;
	if (node != nil) {
		[self leave:node execution:host];
	}
}

- (void)processInstanceEnded:(WFExecutionEntity *)root
{
	if (![self fire:[[self definitionForExecution:root] executionListeners] event:WFListenerEventEnd on:root
	      activity:nil canceled:NO]) {
		return;
	}
	WFHistoricProcessInstanceEntity *history = [[self fetch:WFHistoricInstanceName
	                                              predicate:[NSPredicate predicateWithFormat:
	                                                  @"processInstanceId == %@",
	                                                  root.processInstanceId]
	                                                   sort:nil
	                                                  limit:1] lastObject];
	history.endTime = [NSDate date];
	history.state = WFHistoricStateCompleted;
	WFProcessInstance *value = [WFProcessInstance wf_instanceWithExecution:root
		definition:[self definitionForExecution:root]
		ended:YES];
	WFExecutionEntity *caller = root.superExecution;
	NSDictionary *calledVariables = caller != nil ? [self visibleVariables:root] : nil;
	[self remove:root];
	if (caller != nil) {
		[self returnFrom:calledVariables to:caller];
	}
	WFProcessEngine *engine = self.engine;
	[self afterCommit:^{
		[engine wf_processInstanceEnded:value];
	}];
}

#pragma mark - Gateways

- (WFSequenceFlow *)chooseExclusive:(WFGateway *)gateway
                              scope:(WFProcessDefinition *)scope
                          execution:(WFExecutionEntity *)execution
{
	WFSequenceFlow *fallback = nil;
	for (WFSequenceFlow *flow in [self ordered:[scope outgoingFlowsFrom:gateway.elementId] scope:scope]) {
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
		[self fail:WFCommandError(WFErrorNoPath,
			[NSString stringWithFormat:@"exclusive gateway %@ matched no outgoing flow",
				gateway.elementId])];
	}
	return fallback;
}

- (NSArray *)chooseInclusive:(WFGateway *)gateway
                       scope:(WFProcessDefinition *)scope
                   execution:(WFExecutionEntity *)execution
{
	NSMutableArray *taken = [NSMutableArray array];
	WFSequenceFlow *fallback = nil;
	for (WFSequenceFlow *flow in [self ordered:[scope outgoingFlowsFrom:gateway.elementId] scope:scope]) {
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
		[self fail:WFCommandError(WFErrorNoPath,
			[NSString stringWithFormat:@"inclusive gateway %@ matched no outgoing flow",
				gateway.elementId])];
		return nil;
	}
	return taken;
}

/* Outgoing flows in document order, so the first matching condition of an
 * exclusive gateway is well defined. */
- (NSArray *)ordered:(NSArray<WFSequenceFlow *> *)flows scope:(WFProcessDefinition *)scope
{
	return [flows sortedArrayUsingComparator:^NSComparisonResult(WFSequenceFlow *a, WFSequenceFlow *b) {
		NSUInteger ia = [scope.flowOrder indexOfObject:a.elementId];
		NSUInteger ib = [scope.flowOrder indexOfObject:b.elementId];
		return ia < ib ? NSOrderedAscending : ia > ib ? NSOrderedDescending : NSOrderedSame;
	}];
}

- (void)executeGateway:(WFGateway *)gateway
                 scope:(WFProcessDefinition *)scope
             execution:(WFExecutionEntity *)execution
{
	NSArray *incoming = [scope incomingFlowsTo:gateway.elementId];
	NSArray *outgoing = [scope outgoingFlowsFrom:gateway.elementId];
	switch (gateway.kind) {
	case WFGatewayKindExclusive:
		[self depart:gateway scope:scope execution:execution];
		return;
	case WFGatewayKindParallel:
		if ([incoming count] > 1) {
			[self joinParallel:gateway incoming:[incoming count] scope:scope execution:execution];
		} else {
			[self depart:gateway scope:scope execution:execution];
		}
		return;
	case WFGatewayKindInclusive:
		if ([incoming count] > 1) {
			execution.isActive = NO;
			WFExecutionEntity *level = [self levelOf:execution];
			level.lockRevision += 1;
			[self tryInclusiveJoin:gateway scope:scope level:level];
		} else {
			[self depart:gateway scope:scope execution:execution];
		}
		return;
	case WFGatewayKindEventBased:
		for (WFSequenceFlow *flow in outgoing) {
			WFFlowNode *target = [scope nodeWithId:flow.targetId];
			WFEvent *event = [target isKindOfClass:[WFEvent class]] ? (WFEvent *)target : nil;
			if (event.kind == WFEventKindIntermediateCatch
			    && event.trigger == WFEventTriggerMessage) {
				[self subscribe:execution message:event.messageName activity:event.elementId];
			} else if (event.kind == WFEventKindIntermediateCatch
			           && event.trigger == WFEventTriggerTimer) {
				[self timer:execution event:event];
			} else if (event.kind == WFEventKindIntermediateCatch
			           && event.trigger == WFEventTriggerSignal) {
				[self subscribe:execution type:WFEventTypeSignal name:event.signalName
				       activity:event.elementId];
			} else if (event.kind == WFEventKindIntermediateCatch
			           && event.trigger == WFEventTriggerConditional) {
				[self waitForCondition:event on:execution];
			} else if ([self isPlainReceiveTask:target scope:scope]) {
				[self subscribe:execution message:[(WFTask *)target messageName] activity:target.elementId];
			} else {
				[self fail:WFCommandError(WFErrorInvalidDefinition,
					[NSString stringWithFormat:
						@"event-based gateway %@ may only be followed by message, timer, signal or conditional "
						@"catch events, and receive tasks without boundary events, loops or parameters",
						gateway.elementId])];
				return;
			}
		}
		return;
	}
}

/* A receive task an event-based gateway can wait for: one that is not a
 * scope of its own, since the gateway's path passes it without entering. */
- (BOOL)isPlainReceiveTask:(WFFlowNode *)node scope:(WFProcessDefinition *)scope
{
	return [node isKindOfClass:[WFTask class]] && [(WFTask *)node kind] == WFTaskKindReceive
		&& ![self isScopeActivity:node scope:scope] && node.multiInstance == nil && !node.isAsyncBefore;
}

/* The path leaves the gateway, after any join: by its choice of flows, or,
 * with asyncAfter, by a job that makes that choice. */
- (void)depart:(WFGateway *)gateway
         scope:(WFProcessDefinition *)scope
     execution:(WFExecutionEntity *)execution
{
	if (![self fire:gateway.executionListeners event:WFListenerEventEnd on:execution activity:gateway.elementId
	      canceled:NO]) {
		return;
	}
	if (gateway.isAsyncAfter) {
		[self activityEnded:execution.activityInstanceId canceled:NO];
		[self job:WFJobTypeAsyncAfter execution:execution node:gateway due:[NSDate date]];
		return;
	}
	[self departNow:gateway scope:scope execution:execution];
}

- (void)departNow:(WFGateway *)gateway
            scope:(WFProcessDefinition *)scope
        execution:(WFExecutionEntity *)execution
{
	switch (gateway.kind) {
	case WFGatewayKindExclusive: {
		WFSequenceFlow *flow = [self chooseExclusive:gateway scope:scope execution:execution];
		if (flow != nil) {
			[self take:@[ flow ] scope:scope execution:execution];
		}
		return;
	}
	case WFGatewayKindParallel:
		/* Conditions on a parallel gateway's flows are ignored. */
		[self take:[scope outgoingFlowsFrom:gateway.elementId] scope:scope execution:execution];
		return;
	case WFGatewayKindInclusive: {
		NSArray *flows = [self chooseInclusive:gateway scope:scope execution:execution];
		if (flows != nil) {
			[self take:flows scope:scope execution:execution];
		}
		return;
	}
	case WFGatewayKindEventBased:
		return;
	}
}

- (NSArray<WFExecutionEntity *> *)waitingAt:(WFGateway *)gateway level:(WFExecutionEntity *)level
{
	NSMutableArray *waiting = [NSMutableArray array];
	for (WFExecutionEntity *path in [self pathsAt:level]) {
		if (!path.isActive && [path.activityId isEqualToString:gateway.elementId]) {
			[waiting addObject:path];
		}
	}
	return waiting;
}

/* After a join removed the other arrivals: one path left folds back into
 * its scope execution, which carries on. */
- (WFExecutionEntity *)continueAfterJoin:(WFExecutionEntity *)survivor
                                   level:(WFExecutionEntity *)level
{
	survivor.isActive = YES;
	if (survivor.isConcurrent && [[level concurrentChildren] count] == 1) {
		[self compact:level into:survivor];
		return level;
	}
	return survivor;
}

- (void)joinParallel:(WFGateway *)gateway
            incoming:(NSUInteger)incoming
               scope:(WFProcessDefinition *)scope
           execution:(WFExecutionEntity *)execution
{
	execution.isActive = NO;
	WFExecutionEntity *level = [self levelOf:execution];
	/* Every arrival updates the scope execution, so two commands arriving
	 * at once conflict instead of each missing the other. */
	level.lockRevision += 1;
	NSArray *waiting = [self waitingAt:gateway level:level];
	if ([waiting count] < incoming) {
		return;
	}
	NSUInteger joined = 1;
	for (WFExecutionEntity *other in waiting) {
		if (other != execution && joined < incoming) {
			[self activityEnded:other.activityInstanceId canceled:NO];
			[self remove:other];
			joined += 1;
		}
	}
	WFExecutionEntity *path = [self continueAfterJoin:execution level:level];
	[self depart:gateway scope:scope execution:path];
}

/* Can a path at from still arrive at the gateway? Follows sequence flows
 * and the flows of boundary events on the way. */
- (BOOL)canReach:(NSString *)target from:(NSString *)from scope:(WFProcessDefinition *)scope
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
		for (WFEvent *boundary in [scope boundaryEventsAttachedTo:current]) {
			[sources addObject:boundary.elementId];
		}
		for (NSString *source in sources) {
			for (WFSequenceFlow *flow in [scope outgoingFlowsFrom:source]) {
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

- (void)tryInclusiveJoin:(WFGateway *)gateway
                   scope:(WFProcessDefinition *)scope
                   level:(WFExecutionEntity *)level
{
	NSArray *waiting = [self waitingAt:gateway level:level];
	if ([waiting count] == 0) {
		return;
	}
	for (WFExecutionEntity *path in [self pathsAt:level]) {
		if (![waiting containsObject:path]
		    && [self canReach:gateway.elementId from:path.activityId scope:scope]) {
			return;
		}
	}
	WFExecutionEntity *survivor = [waiting objectAtIndex:0];
	for (WFExecutionEntity *other in waiting) {
		if (other != survivor) {
			[self activityEnded:other.activityInstanceId canceled:NO];
			[self remove:other];
		}
	}
	WFExecutionEntity *path = [self continueAfterJoin:survivor level:level];
	[self depart:gateway scope:scope execution:path];
}

- (void)retryInclusiveJoinsAt:(WFExecutionEntity *)level
{
	NSMutableSet *gateways = [NSMutableSet set];
	for (WFExecutionEntity *path in [self pathsAt:level]) {
		if (path.isActive || path.activityId == nil) {
			continue;
		}
		WFFlowNode *node = [self node:path.activityId of:path];
		if ([node isKindOfClass:[WFGateway class]]
		    && [(WFGateway *)node kind] == WFGatewayKindInclusive) {
			[gateways addObject:node.elementId];
		}
	}
	for (NSString *gatewayId in gateways) {
		WFGateway *gateway = (WFGateway *)[self node:gatewayId of:level];
		WFProcessDefinition *scope = [self scopeOf:gatewayId execution:level];
		[self schedule:^{
			if (!WFGone(level)) {
				[self tryInclusiveJoin:gateway scope:scope level:level];
			}
		}];
	}
}

#pragma mark - History

- (BOOL)records:(WFHistoryLevel)level
{
	return self.engine.historyLevel >= level;
}

- (void)activityStarted:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	[self activityStarted:node execution:execution body:NO];
}

/* A multi-instance activity's body is an activity instance of its own,
 * as the reference records it: id#multiInstanceBody. */
- (void)bodyStarted:(WFFlowNode *)node execution:(WFExecutionEntity *)execution
{
	[self activityStarted:node execution:execution body:YES];
}

- (void)activityStarted:(WFFlowNode *)node execution:(WFExecutionEntity *)execution body:(BOOL)body
{
	if (![self records:WFHistoryLevelActivity] || execution.activityInstanceId == nil) {
		return;
	}
	WFHistoricActivityInstanceEntity *row = [self insert:WFHistoricActivityName];
	row.activityInstanceId = execution.activityInstanceId;
	row.activityId = body ? [node.elementId stringByAppendingString:@"#multiInstanceBody"]
		: node.elementId;
	row.activityName = [node.name isEqualToString:node.elementId] ? nil : node.name;
	row.activityType = body ? @"multiInstanceBody" : WFActivityType(node);
	row.processInstanceId = execution.processInstanceId;
	row.startTime = [NSDate date];
	row.sequence = [self.engine wf_nextSequence];
	[_openActivities setObject:row forKey:row.activityInstanceId];
}

/* Ends the activity instance, if it is still open: several ways out of an
 * activity pass here, and only the first counts. */
- (void)activityEnded:(NSString *)activityInstanceId canceled:(BOOL)canceled
{
	if (![self records:WFHistoryLevelActivity] || activityInstanceId == nil) {
		return;
	}
	WFHistoricActivityInstanceEntity *row = [_openActivities objectForKey:activityInstanceId];
	if (row == nil) {
		row = [[self fetch:WFHistoricActivityName
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

- (WFHistoricTaskInstanceEntity *)historicTask:(NSString *)taskId
{
	return [[self fetch:WFHistoricTaskName
	          predicate:[NSPredicate predicateWithFormat:@"taskId == %@", taskId]
	               sort:nil
	              limit:1] lastObject];
}

- (void)taskStarted:(WFTaskEntity *)task
{
	if (![self records:WFHistoryLevelActivity]) {
		return;
	}
	WFHistoricTaskInstanceEntity *row = [self insert:WFHistoricTaskName];
	row.taskId = task.taskId;
	row.name = task.name;
	row.taskDefinitionKey = task.taskDefinitionKey;
	row.assignee = task.assignee;
	row.processInstanceId = task.processInstanceId;
	row.startTime = task.createdAt;
}

- (void)task:(NSString *)taskId endedBecause:(NSString *)reason
{
	if (![self records:WFHistoryLevelActivity]) {
		return;
	}
	WFHistoricTaskInstanceEntity *row = [self historicTask:taskId];
	if (row != nil && row.endTime == nil) {
		row.endTime = [NSDate date];
		row.deleteReason = reason;
	}
}

- (void)historyTask:(NSString *)taskId assignee:(NSString *)assignee
{
	if ([self records:WFHistoryLevelActivity]) {
		[self historicTask:taskId].assignee = assignee;
	}
}

- (void)historyTaskCompleted:(NSString *)taskId
{
	[self task:taskId endedBecause:WFTaskDeleteReasonCompleted];
}

- (void)historyJob:(WFJobEntity *)job state:(NSString *)state
{
	if (![self records:WFHistoryLevelFull]) {
		return;
	}
	WFHistoricJobLogEntity *row = [self insert:WFHistoricJobLogName];
	row.logId = [WFCommandContext newId];
	row.jobId = job.jobId;
	row.jobType = job.jobType;
	row.activityId = job.activityId;
	row.processInstanceId = job.processInstanceId;
	row.timestamp = [NSDate date];
	row.state = state;
	row.exceptionMessage = [state isEqualToString:WFJobLogStateFailed] ? job.exceptionMessage : nil;
	row.retries = job.retries;
	row.sequence = [self.engine wf_nextSequence];
}

- (void)incident:(NSString *)incidentId endedAs:(NSString *)state
{
	if (![self records:WFHistoryLevelFull]) {
		return;
	}
	WFHistoricIncidentEntity *row = [[self fetch:WFHistoricIncidentName
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
- (void)cancelSubtree:(WFExecutionEntity *)root
{
	NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
	/* The executions of instances that call activities in the subtree
	 * started. The caller removes only the subtree; these go explicitly, so
	 * that nothing still scheduled for them runs. */
	NSMutableSet *called = [NSMutableSet set];
	/* Canceled activities end innermost first, once what they held is. */
	NSMutableArray *ending = [NSMutableArray array];
	while ([pending count] > 0) {
		WFExecutionEntity *execution = [pending lastObject];
		[pending removeLastObject];
		/* What this command already removed (a timer that just fired, a
		 * task just completed) stays in the sets until pending changes are
		 * processed. */
		for (WFTaskEntity *task in execution.tasks) {
			if (![task isDeleted]) {
				[self fireTaskListeners:WFListenerEventDelete task:task];
				[self task:task.taskId endedBecause:WFTaskDeleteReasonDeleted];
			}
		}
		[ending addObject:execution];
		[self activityEnded:execution.activityInstanceId canceled:YES];
		for (WFIncidentEntity *incident in execution.incidents) {
			if (![incident isDeleted]) {
				[self incident:incident.incidentId endedAs:WFIncidentStateDeleted];
			}
		}
		for (WFJobEntity *job in execution.jobs) {
			if (![job isDeleted]) {
				[self historyJob:job state:WFJobLogStateDeleted];
			}
		}
		BOOL inCalled = [called containsObject:execution];
		for (WFExecutionEntity *child in execution.children) {
			if (![child isDeleted]) {
				[pending addObject:child];
				if (inCalled) {
					[called addObject:child];
				}
			}
		}
		WFExecutionEntity *calledInstance = execution.subProcessInstance;
		if (calledInstance != nil && ![calledInstance isDeleted]) {
			[self processInstanceTerminated:calledInstance];
			[pending addObject:calledInstance];
			[called addObject:calledInstance];
		}
	}
	for (WFExecutionEntity *execution in [ending reverseObjectEnumerator]) {
		[self fireCanceledEndOf:execution];
	}
	for (WFExecutionEntity *execution in called) {
		[self remove:execution];
	}
}

/* A called instance canceled with its call activity. */
- (void)processInstanceTerminated:(WFExecutionEntity *)instance
{
	[self fire:[[self definitionForExecution:instance] executionListeners] event:WFListenerEventEnd on:instance
	  activity:nil canceled:YES];
	if (![self records:WFHistoryLevelActivity]) {
		return;
	}
	WFHistoricProcessInstanceEntity *history = [[self fetch:WFHistoricInstanceName
	                                              predicate:[NSPredicate predicateWithFormat:
	                                                  @"processInstanceId == %@",
	                                                  instance.processInstanceId]
	                                                   sort:nil
	                                                  limit:1] lastObject];
	history.endTime = [NSDate date];
	history.state = WFHistoricStateInternallyTerminated;
}

#pragma mark - Variables

- (NSDictionary *)visibleVariables:(WFExecutionEntity *)execution
{
	NSMutableDictionary *variables = [NSMutableDictionary dictionary];
	for (WFExecutionEntity *scope = execution; scope != nil; scope = scope.parent) {
		for (WFVariableEntity *variable in scope.variables) {
			if (![variable isDeleted] && [variables objectForKey:variable.name] == nil) {
				id value = [variable wf_value];
				[variables setObject:value ?: [NSNull null] forKey:variable.name];
			}
		}
	}
	return variables;
}

- (void)recordHistoryOf:(WFVariableEntity *)variable
{
	if ([self records:WFHistoryLevelFull]) {
		WFHistoricVariableUpdateEntity *update = [self insert:WFHistoricUpdateName];
		update.updateId = [WFCommandContext newId];
		update.variableId = variable.variableId;
		update.name = variable.name;
		update.processInstanceId = variable.processInstanceId;
		update.time = [NSDate date];
		update.sequence = [self.engine wf_nextSequence];
		[update wf_setValue:[variable wf_value]];
	}
	if (![self records:WFHistoryLevelAudit]) {
		return;
	}
	WFHistoricVariableEntity *history = [_historicVariables objectForKey:variable.variableId];
	if (history == nil) {
		history = [[self fetch:WFHistoricVariableName
		             predicate:[NSPredicate predicateWithFormat:@"variableId == %@",
		                 variable.variableId]
		                  sort:nil
		                 limit:1] lastObject];
	}
	if (history == nil) {
		history = [self insert:WFHistoricVariableName];
		history.variableId = variable.variableId;
		history.name = variable.name;
		history.processInstanceId = variable.processInstanceId;
		history.scopeIsProcessInstance = variable.execution.parent == nil;
	}
	[_historicVariables setObject:history forKey:variable.variableId];
	[history wf_setValue:[variable wf_value]];
	history.updatedAt = [NSDate date];
}

/* A variable of that execution's own, whatever its parents have. */
- (BOOL)setLocal:(NSString *)name value:(id)value on:(WFExecutionEntity *)execution
{
	WFVariableEntity *variable = [execution localVariableNamed:name];
	NSString *change = variable == nil ? @"create" : @"update";
	if (variable == nil) {
		variable = [self insert:WFVariableName];
		variable.variableId = [WFCommandContext newId];
		variable.name = name;
		variable.processInstanceId = execution.processInstanceId;
		variable.execution = execution;
	}
	if (![variable wf_setValue:value]) {
		[self fail:WFCommandError(WFErrorInvalidState,
			[NSString stringWithFormat:@"variable %@ is not a value the engine stores", name])];
		return NO;
	}
	[self recordHistoryOf:variable];
	[self variable:variable changedBy:change];
	return YES;
}

- (BOOL)setVariables:(NSDictionary *)variables from:(WFExecutionEntity *)execution
{
	for (NSString *name in variables) {
		id value = [variables objectForKey:name];
		WFVariableEntity *variable = nil;
		for (WFExecutionEntity *scope = execution; scope != nil && variable == nil;
		     scope = scope.parent) {
			variable = [scope localVariableNamed:name];
		}
		NSString *change = variable == nil ? @"create" : @"update";
		if (variable == nil) {
			WFExecutionEntity *root = [execution processInstance];
			variable = [self insert:WFVariableName];
			variable.variableId = [WFCommandContext newId];
			variable.name = name;
			variable.processInstanceId = root.processInstanceId;
			variable.execution = root;
		}
		if (![variable wf_setValue:value]) {
			[self fail:WFCommandError(WFErrorInvalidState,
				[NSString stringWithFormat:@"variable %@ is not a value the engine stores",
					name])];
			return NO;
		}
		[self recordHistoryOf:variable];
		[self variable:variable changedBy:change];
	}
	return YES;
}

- (void)removeVariables:(NSArray<NSString *> *)names from:(WFExecutionEntity *)execution
{
	for (NSString *name in names) {
		WFVariableEntity *variable = [execution localVariableNamed:name];
		if (variable != nil) {
			/* History keeps the last value it had. */
			[self variable:variable changedBy:@"delete"];
			[self remove:variable];
		}
	}
}

@end

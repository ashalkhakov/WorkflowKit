#import "WFFlowElements.h"
#import "WFFeel.h"

@interface WFProcessDefinition : NSObject

/* The BPMN process id: the key versions are counted under. */
@property (nonatomic, readonly, copy) NSString *processId;
@property (nonatomic, readonly, copy) NSString *name;
/* Assigned by the repository when the definition is deployed: 0, and nil
 * ids, for a definition that was only built or parsed. */
@property (nonatomic, readonly) NSInteger version;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSString *deploymentId;
@property (nonatomic, readonly, copy) NSString *resourceName;
/* camunda:taskPriority on the process: the external tasks' priority where
 * a task sets none. nil when not set; 0 then. */
@property (nonatomic, readonly, strong) NSNumber *defaultTaskPriority;
/* camunda:historyTimeToLive, in days: how long history of an ended
 * instance is kept. nil keeps it. */
@property (nonatomic, readonly, strong) NSNumber *historyTimeToLive;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, WFFlowNode *> *nodes;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, WFSequenceFlow *> *flows;
@property (nonatomic, readonly, copy) NSArray<NSString *> *flowOrder;

- (instancetype)init NS_UNAVAILABLE;
- (WFEvent *)startEvent;
- (WFFlowNode *)nodeWithId:(NSString *)elementId;
- (WFSequenceFlow *)flowWithId:(NSString *)flowId;
- (NSArray<WFSequenceFlow *> *)outgoingFlowsFrom:(NSString *)nodeId;
- (NSArray<WFSequenceFlow *> *)incomingFlowsTo:(NSString *)nodeId;
- (NSArray *)boundaryEventsAttachedTo:(NSString *)taskId;
/* Any node in the process, embedded subprocesses included: BPMN ids are
 * unique across the whole document. */
- (WFFlowNode *)flowNodeWithId:(NSString *)elementId;
/* The definition, this one or a subprocess's, whose nodes include it. */
- (WFProcessDefinition *)scopeOfFlowNode:(NSString *)elementId;

@end

@interface WFDefinitionBuilder : NSObject

+ (instancetype)process:(NSString *)processId;
+ (instancetype)process:(NSString *)processId name:(NSString *)name;

- (instancetype)addStart:(NSString *)elementId;
- (instancetype)addMessageStart:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addTimerStart:(NSString *)elementId duration:(NSTimeInterval)duration;
- (instancetype)addEnd:(NSString *)elementId;
- (instancetype)addMessageEnd:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addMessageCatch:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addTimerCatch:(NSString *)elementId duration:(NSTimeInterval)duration;
- (instancetype)addMessageThrow:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addSignalStart:(NSString *)elementId signal:(NSString *)signalName;
- (instancetype)addSignalCatch:(NSString *)elementId signal:(NSString *)signalName;
- (instancetype)addSignalThrow:(NSString *)elementId signal:(NSString *)signalName;
- (instancetype)addSignalEnd:(NSString *)elementId signal:(NSString *)signalName;
- (instancetype)addBoundarySignal:(NSString *)elementId
                           onTask:(NSString *)taskId
                           signal:(NSString *)signalName
                     interrupting:(BOOL)interrupting;
/* Ends its scope -- the process instance, or the subprocess it is in --
 * with every path in it. */
- (instancetype)addTerminateEnd:(NSString *)elementId;
/* A none intermediate throw event: a milestone the token passes. */
- (instancetype)addIntermediateThrow:(NSString *)elementId;
- (instancetype)addBoundaryMessage:(NSString *)elementId
                            onTask:(NSString *)taskId
                           message:(NSString *)messageName
                      interrupting:(BOOL)interrupting;
- (instancetype)addBoundaryTimer:(NSString *)elementId
                          onTask:(NSString *)taskId
                        duration:(NSTimeInterval)duration
                    interrupting:(BOOL)interrupting;

- (instancetype)addUserTask:(NSString *)elementId
                       name:(NSString *)name
                   assignee:(NSString *)assignee;
- (instancetype)addServiceTask:(NSString *)elementId
                        action:(NSString *)actionKey;
- (instancetype)addScriptTask:(NSString *)elementId
                       action:(NSString *)actionKey;
/* A send or business rule task: an external task under the topic, as a
 * service task is. */
- (instancetype)addSendTask:(NSString *)elementId action:(NSString *)topic;
- (instancetype)addBusinessRuleTask:(NSString *)elementId action:(NSString *)topic;
/* A business rule task evaluating the latest version of the decision,
 * its result kept in the variable as the mapping says (none when
 * resultVariable is nil); the binding picks another version. */
- (instancetype)addBusinessRuleTask:(NSString *)elementId
                           decision:(NSString *)decisionRef
                     resultVariable:(NSString *)resultVariable
                            mapping:(WFDecisionResultMapping)mapping;
- (instancetype)setDecisionBinding:(WFCalledElementBinding)binding
                           version:(NSInteger)version
                        forElement:(NSString *)elementId;
/* Waits for the message, as a message catch event does. */
- (instancetype)addReceiveTask:(NSString *)elementId message:(NSString *)messageName;
/* A manual task, or a plain task: the path passes through. */
- (instancetype)addManualTask:(NSString *)elementId;
- (instancetype)addTask:(NSString *)elementId;
/* Link events: a throw goes on at the catch of the same name in its
 * scope. A throw has no outgoing flow, a catch no incoming one. */
- (instancetype)addLinkThrow:(NSString *)elementId link:(NSString *)linkName;
- (instancetype)addLinkCatch:(NSString *)elementId link:(NSString *)linkName;
/* Conditional events, on a FEEL condition such as "amount > 1000". A
 * process's conditional start event starts it from
 * -[WFRuntimeService evaluateStartConditions:error:]; an event
 * subprocess's starts it while its scope is active. */
- (instancetype)addConditionalStart:(NSString *)elementId condition:(NSString *)condition;
- (instancetype)addConditionalCatch:(NSString *)elementId condition:(NSString *)condition;
- (instancetype)addBoundaryConditional:(NSString *)elementId
                                onTask:(NSString *)taskId
                             condition:(NSString *)condition
                          interrupting:(BOOL)interrupting;
/* A conditional event's condition, replacing the one it was added with. */
- (instancetype)setCondition:(WFEventCondition *)condition forElement:(NSString *)elementId;

- (instancetype)addExclusive:(NSString *)elementId
                 defaultFlow:(NSString *)defaultFlowId;
- (instancetype)addParallel:(NSString *)elementId;
- (instancetype)addInclusive:(NSString *)elementId
                 defaultFlow:(NSString *)defaultFlowId;
- (instancetype)addEventBased:(NSString *)elementId;
- (instancetype)addSubProcess:(NSString *)elementId
                         name:(NSString *)name
                        inner:(WFProcessDefinition *)inner;
/* Calls the latest version of the process with that key; the binding,
 * inputs and outputs are set afterwards. */
- (instancetype)addCallActivity:(NSString *)elementId
                  calledElement:(NSString *)processKey;
/* version is only read for WFCalledElementBindingVersion. */
- (instancetype)setBinding:(WFCalledElementBinding)binding
                   version:(NSInteger)version
                forElement:(NSString *)elementId;
- (instancetype)addInput:(WFVariableMapping *)mapping forElement:(NSString *)elementId;
- (instancetype)addOutput:(WFVariableMapping *)mapping forElement:(NSString *)elementId;
/* An event subprocess: inner's start event is its trigger. It takes no
 * sequence flows. */
- (instancetype)addEventSubProcess:(NSString *)elementId
                              name:(NSString *)name
                             inner:(WFProcessDefinition *)inner;
/* An event subprocess's start on a BPMN error with that code; nil (or
 * "*") catches any. Always interrupting. */
- (instancetype)addErrorStart:(NSString *)elementId errorRef:(NSString *)errorRef;
/* Throws a BPMN error with that code, caught as a service task's is;
 * uncaught, its path ends. */
- (instancetype)addErrorEnd:(NSString *)elementId errorRef:(NSString *)errorRef;
/* A user task's assignment, as Camunda's attributes have it: keys
 * assignee, candidateUsers, candidateGroups, dueDate, followUpDate and
 * priority, each literal text (ann; ann,bob; 2030-01-01T09:00:00Z; 70) or
 * an expression (${reviewer}, =owner.manager). Text that is neither
 * fails -build:. */
- (instancetype)setAssignment:(NSDictionary<NSString *, NSString *> *)attributes
                   forElement:(NSString *)elementId;
/* An activity's input or output parameter: the value as Camunda writes it
 * -- text, ${...} or =FEEL; nil for null -- or as an expression. Text
 * that is neither fails -build:. */
- (instancetype)addInputParameter:(NSString *)name value:(NSString *)value forElement:(NSString *)elementId;
- (instancetype)addOutputParameter:(NSString *)name value:(NSString *)value forElement:(NSString *)elementId;
- (instancetype)addInputParameter:(NSString *)name
                       expression:(WFFeelExpression *)expression
                       forElement:(NSString *)elementId;
- (instancetype)addOutputParameter:(NSString *)name
                        expression:(WFFeelExpression *)expression
                        forElement:(NSString *)elementId;
/* A timer event's timer, replacing the duration it was added with. */
- (instancetype)setTimer:(WFTimer *)timer forElement:(NSString *)elementId;
/* The same from FEEL: "due", "@\"R3/PT10M\"", "now() + duration(wait)".
 * Text that is not FEEL fails -build:. */
- (instancetype)setTimer:(WFTimerKind)kind expression:(NSString *)expression forElement:(NSString *)elementId;
/* Escalation: thrown by an intermediate throw or end event, caught by a
 * boundary event or an event subprocess's start. A catch's nil code (or
 * "*") catches any. */
- (instancetype)addEscalationThrow:(NSString *)elementId code:(NSString *)code;
- (instancetype)addEscalationEnd:(NSString *)elementId code:(NSString *)code;
- (instancetype)addEscalationStart:(NSString *)elementId code:(NSString *)code;
- (instancetype)addBoundaryEscalation:(NSString *)elementId
                               onTask:(NSString *)taskId
                                 code:(NSString *)code
                         interrupting:(BOOL)interrupting;
/* Compensation: a boundary event on an activity names its handler, an
 * activity (added before or after) that then has no sequence flows; a
 * throw or end event compensates the activity named, or with nil every
 * completed one in its scope, newest first, and waits for them. */
- (instancetype)addBoundaryCompensation:(NSString *)elementId
                                 onTask:(NSString *)taskId
                                handler:(NSString *)handlerId;
- (instancetype)addCompensationThrow:(NSString *)elementId activity:(NSString *)activityId;
- (instancetype)addCompensationEnd:(NSString *)elementId activity:(NSString *)activityId;
/* camunda:errorCodeVariable or escalationCodeVariable on a catch. */
- (instancetype)setCodeVariable:(NSString *)name forElement:(NSString *)elementId;
/* isForCompensation, as a file says it; -addBoundaryCompensation:... sets
 * it on its handler. */
- (instancetype)setForCompensation:(BOOL)forCompensation forElement:(NSString *)elementId;
/* The association from a compensation boundary event to its handler. */
- (instancetype)setCompensationHandler:(NSString *)handlerId forBoundary:(NSString *)boundaryId;
/* An event subprocess's start event: whether it interrupts the scope. */
- (instancetype)setInterrupting:(BOOL)interrupting forElement:(NSString *)elementId;
- (instancetype)addBoundaryError:(NSString *)elementId
                          onTask:(NSString *)taskId
                        errorRef:(NSString *)errorRef
                    interrupting:(BOOL)interrupting;
/* Transaction boundaries and job settings of a node already added. */
- (instancetype)setAsyncBefore:(BOOL)asyncBefore
                    asyncAfter:(BOOL)asyncAfter
                     exclusive:(BOOL)exclusive
                    forElement:(NSString *)elementId;
- (instancetype)setRetryTimeCycle:(NSString *)cycle forElement:(NSString *)elementId;
- (instancetype)setTaskPriority:(NSInteger)priority forElement:(NSString *)elementId;
/* Makes an activity already added -- a task, subprocess or call activity
 * -- multi-instance. */
- (instancetype)setMultiInstance:(WFMultiInstance *)multiInstance forElement:(NSString *)elementId;
/* The same from FEEL text: cardinality or collection (the other nil),
 * and optionally the element variable and completion condition. Text
 * that is not FEEL fails -build:. */
- (instancetype)setMultiInstanceSequential:(BOOL)sequential
                           loopCardinality:(NSString *)loopCardinality
                                collection:(NSString *)collection
                           elementVariable:(NSString *)elementVariable
                       completionCondition:(NSString *)completionCondition
                                forElement:(NSString *)elementId;
/* Process-level settings. */
- (instancetype)setDefaultTaskPriority:(NSInteger)priority;
- (instancetype)setHistoryTimeToLive:(NSInteger)days;
/* Names a node or a sequence flow already added. */
- (instancetype)setName:(NSString *)name forElement:(NSString *)elementId;
- (instancetype)setBoundsFor:(NSString *)elementId
                           x:(double)x
                           y:(double)y
                       width:(double)width
                      height:(double)height;

- (instancetype)connect:(NSString *)sourceId to:(NSString *)targetId;
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                 flowId:(NSString *)flowId;
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
              condition:(id<WFCondition>)condition;
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                 flowId:(NSString *)flowId
              condition:(id<WFCondition>)condition;
/* A flow taken when the FEEL condition holds: "amount > 1000". A
 * condition that is not FEEL fails -build:. */
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                   when:(NSString *)condition;

- (WFProcessDefinition *)build:(NSError **)error;

@end

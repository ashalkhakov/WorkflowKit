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

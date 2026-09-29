#import "WFTypes.h"

@class WFFeelExpression;
@class WFMultiInstance;
@class WFParameter;

@protocol WFFlowElement <NSObject>
@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@end

@interface WFFlowNode : NSObject <WFFlowElement>

@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSArray<NSString *> *incomingFlowIds;
@property (nonatomic, readonly, copy) NSArray<NSString *> *outgoingFlowIds;
@property (nonatomic) double boundsX;
@property (nonatomic) double boundsY;
@property (nonatomic) double boundsWidth;
@property (nonatomic) double boundsHeight;
/* Transaction boundaries, as camunda:asyncBefore and camunda:asyncAfter:
 * the command stops before entering, or after leaving, the node, and a job
 * carries on from there. */
@property (nonatomic, readonly, getter=isAsyncBefore) BOOL asyncBefore;
@property (nonatomic, readonly, getter=isAsyncAfter) BOOL asyncAfter;
/* camunda:exclusive: whether the node's jobs run one after another with the
 * instance's other work. YES unless set otherwise. */
@property (nonatomic, readonly, getter=isExclusive) BOOL exclusive;
/* camunda:failedJobRetryTimeCycle: "R5/PT5M", or a list of ISO-8601
 * durations, one per retry. nil for the default of three attempts. */
@property (nonatomic, readonly, copy) NSString *retryTimeCycle;
/* camunda:taskPriority: an external task's priority, over the process's.
 * nil when not set. */
@property (nonatomic, readonly, strong) NSNumber *taskPriority;
/* multiInstanceLoopCharacteristics: nil for an activity that runs once. */
@property (nonatomic, readonly, strong) WFMultiInstance *multiInstance;
/* isForCompensation: a compensation handler, run only when compensation
 * is thrown for the activity whose compensation boundary event names it.
 * It has no sequence flows. */
@property (nonatomic, readonly, getter=isForCompensation) BOOL forCompensation;
/* camunda:inputOutput on an activity. Inputs are evaluated where the path
 * arrives, before the activity starts, and become its local variables;
 * outputs are evaluated in the activity when it completes and set where
 * it is -- where each variable exists, else on the process instance. An
 * activity interrupted by a boundary event maps no outputs. */
@property (nonatomic, readonly, copy) NSArray<WFParameter *> *inputParameters;
@property (nonatomic, readonly, copy) NSArray<WFParameter *> *outputParameters;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_DESIGNATED_INITIALIZER;

@end

/*
 * A multi-instance activity's loop: how many instances, one after
 * another or side by side, and when enough of them have finished.
 *
 * The instances run under a body that holds nrOfInstances,
 * nrOfActiveInstances and nrOfCompletedInstances; each instance has its
 * own loopCounter (from 0) and, over a collection, the element variable.
 * The completion condition is evaluated each time an instance finishes;
 * when it holds, the instances still running are canceled and the
 * activity is left. Boundary events on the activity are on the body.
 */
@interface WFMultiInstance : NSObject
@property (nonatomic, readonly, getter=isSequential) BOOL sequential;
/* A whole number of instances; nil over a collection. */
@property (nonatomic, readonly, strong) WFFeelExpression *loopCardinality;
/* A list, one instance per item; nil for a cardinality. */
@property (nonatomic, readonly, strong) WFFeelExpression *collection;
/* The name each instance sees its item under; nil for none. */
@property (nonatomic, readonly, copy) NSString *elementVariable;
@property (nonatomic, readonly, strong) WFFeelExpression *completionCondition;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initSequential:(BOOL)sequential
               loopCardinality:(WFFeelExpression *)loopCardinality
                    collection:(WFFeelExpression *)collection
               elementVariable:(NSString *)elementVariable
           completionCondition:(WFFeelExpression *)completionCondition NS_DESIGNATED_INITIALIZER;
@end

typedef NS_ENUM(NSInteger, WFTimerKind) {
	/* timeDate: at a date and time. */
	WFTimerKindDate = 0,
	/* timeDuration: that long after the timer is armed. */
	WFTimerKindDuration,
	/* timeCycle: R3/PT10M, R/PT1H (forever), R2/2024-01-01T09:00:00Z/P1D. */
	WFTimerKindCycle
};

/*
 * When a timer event fires: a date, a duration or a cycle, as an
 * expression evaluated over the variables when the timer is armed -- often
 * a literal, @"PT5M" or "R3/PT10M". A date and time is an NSDate or its
 * ISO-8601 text, a duration a FEEL duration or its text, a cycle its text.
 * A cycle repeats on a timer start event, a non-interrupting boundary
 * event and a non-interrupting event subprocess; elsewhere a timer fires
 * once.
 */
@interface WFTimer : NSObject
@property (nonatomic, readonly) WFTimerKind kind;
@property (nonatomic, readonly, strong) WFFeelExpression *expression;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithKind:(WFTimerKind)kind
                  expression:(WFFeelExpression *)expression NS_DESIGNATED_INITIALIZER;
/* A fixed duration. */
+ (instancetype)duration:(NSTimeInterval)seconds;
/* ISO-8601 text of that kind -- a date and time, a duration (weeks
 * included), or a cycle -- as a literal; nil when it is not one. */
+ (instancetype)timerWithKind:(WFTimerKind)kind text:(NSString *)text;
@end

@interface WFEvent : WFFlowNode
@property (nonatomic, readonly) WFEventKind kind;
@property (nonatomic, readonly) WFEventTrigger trigger;
/* The message's name for a message event, the signal's for a signal
 * event. */
@property (nonatomic, readonly, copy) NSString *messageName;
@property (nonatomic, readonly, copy) NSString *signalName;
/* A timer event's timer; nil for other events. */
@property (nonatomic, readonly, strong) WFTimer *timer;
/* An escalation event's escalationCode; nil (or "*") on a catch catches
 * any. */
@property (nonatomic, readonly, copy) NSString *escalationCode;
/* A compensation throw's activityRef: the activity to compensate; nil
 * for every completed one in the scope. */
@property (nonatomic, readonly, copy) NSString *activityRef;
/* A compensation boundary event's handler, the activity its association
 * points at. */
@property (nonatomic, readonly, copy) NSString *compensationHandlerId;
/* camunda:errorCodeVariable, camunda:escalationCodeVariable: where a
 * catching error or escalation event puts the code it caught. */
@property (nonatomic, readonly, copy) NSString *codeVariable;
@property (nonatomic, readonly, copy) NSString *attachedToId;
@property (nonatomic, readonly, copy) NSString *errorRef;
/* A boundary event's cancelActivity, or an event subprocess's start
 * event's isInterrupting. */
@property (nonatomic, readonly, getter=isInterrupting) BOOL interrupting;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(WFEventKind)kind
                          trigger:(WFEventTrigger)trigger
                      messageName:(NSString *)messageName
                            timer:(WFTimer *)timer
                     attachedToId:(NSString *)attachedToId
                         errorRef:(NSString *)errorRef
                     interrupting:(BOOL)interrupting NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(WFEventKind)kind;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface WFTask : WFFlowNode
@property (nonatomic, readonly) WFTaskKind kind;
@property (nonatomic, readonly, copy) NSString *actionKey;
/* A user task's assignee when it is literal text; nil when it is computed
 * or not set. */
@property (nonatomic, readonly, copy) NSString *assignee;
/* A user task's assignment, each evaluated over the variables when the
 * task is created; nil when not set. camunda:assignee (a user),
 * candidateUsers and candidateGroups (a list, or text separated by
 * commas), dueDate and followUpDate (a date and time, a date, or its
 * text), priority (a whole number; 50 when not set). */
@property (nonatomic, readonly, strong) WFFeelExpression *assigneeExpression;
@property (nonatomic, readonly, strong) WFFeelExpression *candidateUsers;
@property (nonatomic, readonly, strong) WFFeelExpression *candidateGroups;
@property (nonatomic, readonly, strong) WFFeelExpression *dueDate;
@property (nonatomic, readonly, strong) WFFeelExpression *followUpDate;
@property (nonatomic, readonly, strong) WFFeelExpression *priority;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(WFTaskKind)kind
                        actionKey:(NSString *)actionKey
                         assignee:(NSString *)assignee NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface WFGateway : WFFlowNode
@property (nonatomic, readonly) WFGatewayKind kind;
@property (nonatomic, readonly, copy) NSString *defaultFlowId;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(WFGatewayKind)kind
                    defaultFlowId:(NSString *)defaultFlowId NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@class WFProcessDefinition;

@interface WFSubProcess : WFFlowNode
@property (nonatomic, readonly, strong) WFProcessDefinition *innerDefinition;
/* An event subprocess (triggeredByEvent): no flows in or out; its start
 * event -- message, timer, signal or error -- starts it while the scope
 * around it is active, interrupting that scope or running beside it. */
@property (nonatomic, readonly, getter=isTriggeredByEvent) BOOL triggeredByEvent;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                 innerDefinition:(WFProcessDefinition *)innerDefinition NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

/* One input or output parameter: a name and the expression its value
 * comes from; nil for null. */
@interface WFParameter : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, strong) WFFeelExpression *expression;
+ (instancetype)parameter:(NSString *)name expression:(WFFeelExpression *)expression;
- (instancetype)init NS_UNAVAILABLE;
@end

/* Which version of the called process a call activity starts, as
 * camunda:calledElementBinding. */
typedef NS_ENUM(NSInteger, WFCalledElementBinding) {
	/* The latest version deployed when the activity is entered. */
	WFCalledElementBindingLatest = 0,
	/* The version deployed together with the calling process. */
	WFCalledElementBindingDeployment,
	/* The version camunda:calledElementVersion names. */
	WFCalledElementBindingVersion
};

/* One camunda:in or camunda:out of a call activity: a variable copied to
 * another name, every variable, or the business key. */
@interface WFVariableMapping : NSObject
/* nil for all variables or the business key. */
@property (nonatomic, readonly, copy) NSString *source;
@property (nonatomic, readonly, copy) NSString *target;
/* variables="all": every variable, under its own name. */
@property (nonatomic, readonly, getter=isAllVariables) BOOL allVariables;
/* businessKey="#{execution.processBusinessKey}": the calling instance's
 * business key becomes the called one's. Inputs only. */
@property (nonatomic, readonly, getter=isBusinessKey) BOOL businessKey;
+ (instancetype)mappingFrom:(NSString *)source to:(NSString *)target;
+ (instancetype)allVariables;
+ (instancetype)businessKey;
- (instancetype)init NS_UNAVAILABLE;
@end

/*
 * Starts an instance of another process and waits for it to end. The
 * inputs are evaluated against the variables visible at the activity and
 * become the called instance's; when it ends, the outputs are evaluated
 * against its variables and set as the process's (where they exist, else
 * on the process instance).
 */
@interface WFCallActivity : WFFlowNode
/* The called process's key. */
@property (nonatomic, readonly, copy) NSString *calledElement;
@property (nonatomic, readonly) WFCalledElementBinding binding;
/* For WFCalledElementBindingVersion; 0 otherwise. */
@property (nonatomic, readonly) NSInteger calledElementVersion;
@property (nonatomic, readonly, copy) NSArray<WFVariableMapping *> *inputs;
@property (nonatomic, readonly, copy) NSArray<WFVariableMapping *> *outputs;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                    calledElement:(NSString *)calledElement NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface WFSequenceFlow : NSObject <WFFlowElement>

@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *sourceId;
@property (nonatomic, readonly, copy) NSString *targetId;
@property (nonatomic, readonly, strong) id condition;
@property (nonatomic, readonly, getter=isDefaultFlow) BOOL defaultFlow;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                         sourceId:(NSString *)sourceId
                         targetId:(NSString *)targetId
                        condition:(id)condition
                      defaultFlow:(BOOL)defaultFlow NS_DESIGNATED_INITIALIZER;

@end

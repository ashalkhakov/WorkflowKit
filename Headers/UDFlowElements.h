#import "UDTypes.h"

@class UDFeelExpression;
@class UDMultiInstance;

@protocol UDFlowElement <NSObject>
@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@end

@interface UDFlowNode : NSObject <UDFlowElement>

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
@property (nonatomic, readonly, strong) UDMultiInstance *multiInstance;

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
@interface UDMultiInstance : NSObject
@property (nonatomic, readonly, getter=isSequential) BOOL sequential;
/* A whole number of instances; nil over a collection. */
@property (nonatomic, readonly, strong) UDFeelExpression *loopCardinality;
/* A list, one instance per item; nil for a cardinality. */
@property (nonatomic, readonly, strong) UDFeelExpression *collection;
/* The name each instance sees its item under; nil for none. */
@property (nonatomic, readonly, copy) NSString *elementVariable;
@property (nonatomic, readonly, strong) UDFeelExpression *completionCondition;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initSequential:(BOOL)sequential
               loopCardinality:(UDFeelExpression *)loopCardinality
                    collection:(UDFeelExpression *)collection
               elementVariable:(NSString *)elementVariable
           completionCondition:(UDFeelExpression *)completionCondition NS_DESIGNATED_INITIALIZER;
@end

typedef NS_ENUM(NSInteger, UDTimerKind) {
	/* timeDate: at a date and time. */
	UDTimerKindDate = 0,
	/* timeDuration: that long after the timer is armed. */
	UDTimerKindDuration,
	/* timeCycle: R3/PT10M, R/PT1H (forever), R2/2024-01-01T09:00:00Z/P1D. */
	UDTimerKindCycle
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
@interface UDTimer : NSObject
@property (nonatomic, readonly) UDTimerKind kind;
@property (nonatomic, readonly, strong) UDFeelExpression *expression;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithKind:(UDTimerKind)kind
                  expression:(UDFeelExpression *)expression NS_DESIGNATED_INITIALIZER;
/* A fixed duration. */
+ (instancetype)duration:(NSTimeInterval)seconds;
/* ISO-8601 text of that kind -- a date and time, a duration (weeks
 * included), or a cycle -- as a literal; nil when it is not one. */
+ (instancetype)timerWithKind:(UDTimerKind)kind text:(NSString *)text;
@end

@interface UDEvent : UDFlowNode
@property (nonatomic, readonly) UDEventKind kind;
@property (nonatomic, readonly) UDEventTrigger trigger;
/* The message's name for a message event, the signal's for a signal
 * event. */
@property (nonatomic, readonly, copy) NSString *messageName;
@property (nonatomic, readonly, copy) NSString *signalName;
/* A timer event's timer; nil for other events. */
@property (nonatomic, readonly, strong) UDTimer *timer;
@property (nonatomic, readonly, copy) NSString *attachedToId;
@property (nonatomic, readonly, copy) NSString *errorRef;
/* A boundary event's cancelActivity, or an event subprocess's start
 * event's isInterrupting. */
@property (nonatomic, readonly, getter=isInterrupting) BOOL interrupting;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDEventKind)kind
                          trigger:(UDEventTrigger)trigger
                      messageName:(NSString *)messageName
                            timer:(UDTimer *)timer
                     attachedToId:(NSString *)attachedToId
                         errorRef:(NSString *)errorRef
                     interrupting:(BOOL)interrupting NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDEventKind)kind;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface UDTask : UDFlowNode
@property (nonatomic, readonly) UDTaskKind kind;
@property (nonatomic, readonly, copy) NSString *actionKey;
@property (nonatomic, readonly, copy) NSString *assignee;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDTaskKind)kind
                        actionKey:(NSString *)actionKey
                         assignee:(NSString *)assignee NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface UDGateway : UDFlowNode
@property (nonatomic, readonly) UDGatewayKind kind;
@property (nonatomic, readonly, copy) NSString *defaultFlowId;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDGatewayKind)kind
                    defaultFlowId:(NSString *)defaultFlowId NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@class UDProcessDefinition;

@interface UDSubProcess : UDFlowNode
@property (nonatomic, readonly, strong) UDProcessDefinition *innerDefinition;
/* An event subprocess (triggeredByEvent): no flows in or out; its start
 * event -- message, timer, signal or error -- starts it while the scope
 * around it is active, interrupting that scope or running beside it. */
@property (nonatomic, readonly, getter=isTriggeredByEvent) BOOL triggeredByEvent;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                 innerDefinition:(UDProcessDefinition *)innerDefinition NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

/* Which version of the called process a call activity starts, as
 * camunda:calledElementBinding. */
typedef NS_ENUM(NSInteger, UDCalledElementBinding) {
	/* The latest version deployed when the activity is entered. */
	UDCalledElementBindingLatest = 0,
	/* The version deployed together with the calling process. */
	UDCalledElementBindingDeployment,
	/* The version camunda:calledElementVersion names. */
	UDCalledElementBindingVersion
};

/* One camunda:in or camunda:out of a call activity: a variable copied to
 * another name, every variable, or the business key. */
@interface UDVariableMapping : NSObject
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
@interface UDCallActivity : UDFlowNode
/* The called process's key. */
@property (nonatomic, readonly, copy) NSString *calledElement;
@property (nonatomic, readonly) UDCalledElementBinding binding;
/* For UDCalledElementBindingVersion; 0 otherwise. */
@property (nonatomic, readonly) NSInteger calledElementVersion;
@property (nonatomic, readonly, copy) NSArray<UDVariableMapping *> *inputs;
@property (nonatomic, readonly, copy) NSArray<UDVariableMapping *> *outputs;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                    calledElement:(NSString *)calledElement NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface UDSequenceFlow : NSObject <UDFlowElement>

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

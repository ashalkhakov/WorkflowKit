#import "WFTypes.h"

@class WFProcessEngine;
@class WFParameter;

/*
 * Code the engine calls by name, as Camunda's delegates and listeners: a
 * class (camunda:class), of which a new instance is made for each call,
 * or an object the host registered under a name
 * (camunda:delegateExpression="${name}"). Fields (camunda:field) are
 * evaluated for each call; an instance of a class is also given them by
 * key-value coding where it has the key.
 */
@interface WFDelegateReference : NSObject
@property (nonatomic, readonly, copy) NSString *className;
@property (nonatomic, readonly, copy) NSString *delegateName;
/* camunda:field: each a name and the expression its value comes from. */
@property (nonatomic, readonly, copy) NSArray<WFParameter *> *fields;
+ (instancetype)referenceToClass:(NSString *)className fields:(NSArray<WFParameter *> *)fields;
+ (instancetype)referenceToDelegate:(NSString *)delegateName fields:(NSArray<WFParameter *> *)fields;
- (instancetype)init NS_UNAVAILABLE;
@end

typedef NS_ENUM(NSInteger, WFListenerEvent) {
	/* Execution listeners: an activity, an event or the process starts or
	 * ends -- completed or canceled -- or a sequence flow is taken. */
	WFListenerEventStart = 0,
	WFListenerEventEnd,
	WFListenerEventTake,
	/* Task listeners: a user task is created, assigned, completed, or
	 * deleted without being completed. */
	WFListenerEventCreate,
	WFListenerEventAssignment,
	WFListenerEventComplete,
	WFListenerEventDelete
};

/* camunda:executionListener or camunda:taskListener. */
@interface WFListener : NSObject
@property (nonatomic, readonly) WFListenerEvent event;
@property (nonatomic, readonly, strong) WFDelegateReference *delegate;
+ (instancetype)listenerOn:(WFListenerEvent)event delegate:(WFDelegateReference *)delegate;
- (instancetype)init NS_UNAVAILABLE;
/* "start", "end", "take", "create", "assignment", "complete", "delete". */
+ (NSString *)nameOfEvent:(WFListenerEvent)event;
@end

/*
 * What a delegate or listener sees of the path it is called on. It is
 * valid only during the call, which runs inside the engine's command: what
 * it sets is committed with the command, or not at all. Calling the
 * engine's services from a delegate runs separate commands.
 */
@interface WFDelegateExecution : NSObject
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *businessKey;
@property (nonatomic, readonly, copy) NSString *processDefinitionId;
/* The activity, event, gateway or flow called for; nil for the process. */
@property (nonatomic, readonly, copy) NSString *activityId;
@property (nonatomic, readonly, copy) NSString *activityInstanceId;
/* A listener's event, "start", "end", "take", ...; nil for a delegate. */
@property (nonatomic, readonly, copy) NSString *eventName;
/* An end listener called because its activity or process was canceled. */
@property (nonatomic, readonly, getter=isCanceled) BOOL canceled;
/* The fields, evaluated. */
@property (nonatomic, readonly, copy) NSDictionary *fields;
- (instancetype)init NS_UNAVAILABLE;
/* The variables visible on the path, and one of them; nil when unset. */
- (NSDictionary *)variables;
- (id)variableNamed:(NSString *)name;
- (NSDictionary *)localVariables;
/* Sets the variable where it is visible, else on the process instance;
 * or as the path's own. NO, with an error, for a value the engine does not
 * store. */
- (BOOL)setVariable:(NSString *)name value:(id)value error:(NSError **)error;
- (BOOL)setLocalVariable:(NSString *)name value:(id)value error:(NSError **)error;
@end

/* What a task listener sees: the task, and the path it is on. */
@interface WFDelegateTask : WFDelegateExecution
@property (nonatomic, readonly, copy) NSString *taskId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *taskDefinitionKey;
/* Settable in a create or assignment listener. */
@property (nonatomic, copy) NSString *assignee;
@property (nonatomic) NSInteger priority;
@property (nonatomic, copy) NSDate *dueDate;
@end

/*
 * A service, send or business rule task's code. NO, with an error, fails
 * the activity: an error whose userInfo carries WFErrorRefKey is a BPMN
 * error, which its boundary events and event subprocesses catch; any other
 * fails the command -- in a job, the job's attempt, retried as its retry
 * cycle says.
 */
@protocol WFActivityDelegate <NSObject>
- (BOOL)executeWithExecution:(WFDelegateExecution *)execution error:(NSError **)error;
@end

/* NO, with an error, fails the command, as a delegate's does. */
@protocol WFExecutionListener <NSObject>
- (BOOL)notifyWithExecution:(WFDelegateExecution *)execution error:(NSError **)error;
@end

@protocol WFTaskListener <NSObject>
- (BOOL)notifyWithTask:(WFDelegateTask *)task error:(NSError **)error;
@end

/*
 * Code that brings delegates and listeners to an engine: compiled into the
 * host and added with -[WFProcessEngine addPlugin:], or a loadable bundle
 * whose principal class conforms, loaded with
 * -[WFProcessEngine loadPluginsInDirectory:error:]. It registers what it
 * brings; the classes a bundle holds are also found by name once loaded.
 */
@protocol WFEnginePlugin <NSObject>
- (void)registerWithEngine:(WFProcessEngine *)engine;
@end

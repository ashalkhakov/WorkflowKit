#import "WFTypes.h"

@class WFProcessEngine;

/* A running process instance, as last committed. */
@interface WFProcessInstance : NSObject
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *businessKey;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSString *definitionKey;
/* The instance whose call activity started this one; nil otherwise. */
@property (nonatomic, readonly, copy) NSString *superProcessInstanceId;
/* Suspended: its tasks cannot be completed, its jobs and external tasks
 * wait, and messages and signals pass it by, until it is activated. */
@property (nonatomic, readonly, getter=isSuspended) BOOL suspended;
/* YES once the instance has reached its end: it is then only in history. */
@property (nonatomic, readonly, getter=isEnded) BOOL ended;
@end

/* An activity instance of a running process instance, in its tree: the
 * process instance at the root (its activityId the process's), and a
 * subprocess or multi-instance body (activityId "task#multiInstanceBody")
 * holding the activity instances inside it. */
@interface WFActivityInstance : NSObject
@property (nonatomic, readonly, copy) NSString *activityInstanceId;
@property (nonatomic, readonly, copy) NSString *activityId;
/* nil at the root. */
@property (nonatomic, readonly, copy) NSString *parentActivityInstanceId;
@property (nonatomic, readonly, copy) NSArray<WFActivityInstance *> *childActivityInstances;
/* The activity instances of that activity in the tree, depth first. */
- (NSArray<WFActivityInstance *> *)activityInstancesForActivity:(NSString *)activityId;
@end

/*
 * Instructions that change where a running process instance is, for
 * -[WFRuntimeService modifyProcessInstance:error:]. They run in order, in
 * one command:
 *
 * A start instruction starts a new path: before an activity, which is
 * entered as a sequence flow would enter it (an asyncBefore stops at a
 * job); after an activity with one outgoing flow; or on a sequence flow.
 * The subprocesses around it that have no instance get one, their start
 * event skipped, their inputs mapped and their boundary events and event
 * subprocesses armed; a subprocess with several instances needs the
 * ancestor activity instance to start in. Paths cannot be started inside
 * a multi-instance or event subprocess, nor at a boundary event.
 *
 * A cancel instruction cancels an activity instance with everything in
 * it; a subprocess or multi-instance body left with nothing is canceled
 * in turn. An instance with nothing left once every instruction has run
 * ends, externally terminated.
 */
@interface WFProcessInstanceModification : NSObject
@property (nonatomic, readonly, copy) NSString *processInstanceId;
+ (instancetype)modificationOfProcessInstance:(NSString *)processInstanceId;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)startBeforeActivity:(NSString *)activityId;
/* The variables are the new path's own. */
- (instancetype)startBeforeActivity:(NSString *)activityId
                           ancestor:(NSString *)ancestorActivityInstanceId
                          variables:(NSDictionary *)variables;
- (instancetype)startAfterActivity:(NSString *)activityId;
- (instancetype)startTransition:(NSString *)flowId;
- (instancetype)cancelActivityInstance:(NSString *)activityInstanceId;
- (instancetype)cancelAllForActivity:(NSString *)activityId;
@end

/*
 * How running instances move from one deployed definition to another, for
 * -[WFRuntimeService migrateProcessInstances:plan:error:]: each source
 * activity mapped to a target activity of the same kind -- the same class
 * of task, event (kind and trigger) or gateway, multi-instance or not --
 * in corresponding scopes (the subprocesses around them mapped to each
 * other), a boundary event with its activity. mapEqualActivities adds a
 * mapping for every activity of the same id, kind and scope.
 *
 * Migrated, an instance keeps its paths, tasks, jobs and variables: they
 * move to the mapped activities. Every activity it is in must be mapped,
 * and be a scope (with boundary events or parameters) in both definitions
 * or in neither. Waits for events whose activities are not mapped go;
 * boundary events and event subprocesses the target adds are armed. A
 * mapped event keeps the trigger it has -- its message, signal or timer --
 * unless its mapping updates it to the target's.
 */
@interface WFMigrationPlan : NSObject
@property (nonatomic, readonly, copy) NSString *sourceDefinitionId;
@property (nonatomic, readonly, copy) NSString *targetDefinitionId;
+ (instancetype)planFromDefinition:(NSString *)sourceDefinitionId toDefinition:(NSString *)targetDefinitionId;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)mapActivity:(NSString *)sourceActivityId toActivity:(NSString *)targetActivityId;
- (instancetype)mapActivity:(NSString *)sourceActivityId
                 toActivity:(NSString *)targetActivityId
         updateEventTrigger:(BOOL)updateEventTrigger;
- (instancetype)mapEqualActivities;
@end

/*
 * Process instances, messages and variables.
 *
 * Every call is one command: it runs until each path of the instance is at
 * a wait state or has ended, and commits once. When a call returns, what it
 * did is durable. A call that loses a race with another command on the
 * same instance fails with WFErrorConflict, having changed nothing.
 *
 * Variables are strings, numbers, dates, data, NSNull, or arrays and
 * dictionaries of JSON values.
 */
@interface WFRuntimeService : NSObject

- (instancetype)init NS_UNAVAILABLE;

/* Starts the latest version of the process. */
- (WFProcessInstance *)startProcessInstanceByKey:(NSString *)key
                                       variables:(NSDictionary *)variables
                                           error:(NSError **)error;
- (WFProcessInstance *)startProcessInstanceByKey:(NSString *)key
                                     businessKey:(NSString *)businessKey
                                       variables:(NSDictionary *)variables
                                           error:(NSError **)error;

/* nil, with an error, for an instance that has ended or never existed. */
- (WFProcessInstance *)processInstanceWithId:(NSString *)processInstanceId
                                       error:(NSError **)error;
/* Ends the instance now: everything in it is canceled -- its tasks
 * deleted, the instances it called terminated -- and its history ends as
 * externally terminated, with the reason. An instance a call activity
 * started is deleted by deleting the one that called it. */
- (BOOL)deleteProcessInstance:(NSString *)processInstanceId
                       reason:(NSString *)reason
                        error:(NSError **)error;
/* Suspends the instance and the instances it called, or activates them
 * again. */
- (BOOL)suspendProcessInstance:(NSString *)processInstanceId error:(NSError **)error;
- (BOOL)activateProcessInstance:(NSString *)processInstanceId error:(NSError **)error;

/* The running instances the instance's call activities started, in no
 * particular order. */
- (NSArray<WFProcessInstance *> *)subProcessInstancesOf:(NSString *)processInstanceId
                                                  error:(NSError **)error;
/* The instance's activity instance tree; nil, with an error, for an
 * instance that is not running. */
- (WFActivityInstance *)activityInstanceTreeOfProcessInstance:(NSString *)processInstanceId
                                                        error:(NSError **)error;
/* Runs the modification's instructions: all of them, or, with an error,
 * none. A suspended instance cannot be modified. */
- (BOOL)modifyProcessInstance:(WFProcessInstanceModification *)modification error:(NSError **)error;

/* Checks the plan against its two definitions: YES, or NO with an error
 * saying what cannot be mapped. */
- (BOOL)validateMigrationPlan:(WFMigrationPlan *)plan error:(NSError **)error;
/* Migrates the instances, all in one command: every one of them, or, with
 * an error, none. */
- (BOOL)migrateProcessInstances:(NSArray<NSString *> *)processInstanceIds
                           plan:(WFMigrationPlan *)plan
                          error:(NSError **)error;

/* The activities the instance's paths are active in, sorted. A path
 * waiting at a join is not active. */
- (NSArray<NSString *> *)activeActivityIdsForProcessInstance:(NSString *)processInstanceId
                                                       error:(NSError **)error;
/* The process instance's own variables. */
- (NSDictionary *)variablesForProcessInstance:(NSString *)processInstanceId
                                        error:(NSError **)error;
- (BOOL)setVariables:(NSDictionary *)variables
   processInstanceId:(NSString *)processInstanceId
               error:(NSError **)error;

/* Starts each process whose conditional start event's condition holds
 * over the variables -- the latest version of each, unless it is
 * suspended -- with those variables and the business key, and answers the
 * instances started, perhaps none. It is an error when no deployed process
 * has a conditional start event. */
- (NSArray<WFProcessInstance *> *)evaluateStartConditions:(NSDictionary *)variables
                                              businessKey:(NSString *)businessKey
                                                    error:(NSError **)error;

/*
 * Delivers a message to exactly one recipient: a path waiting on a catch
 * or boundary event for that message name, or, when neither the business
 * key's instance nor correlation keys narrow it to a running instance, a
 * process whose start event is that message. Recipients are narrowed by
 * business key and by correlationKeys, process instance variables that
 * must be equal. Zero or several matches are an error. The variables are
 * set on the receiving process instance.
 */
- (BOOL)correlateMessage:(NSString *)messageName
             businessKey:(NSString *)businessKey
         correlationKeys:(NSDictionary *)correlationKeys
               variables:(NSDictionary *)variables
                   error:(NSError **)error;
/* The same, to every match. Answers the process instances it reached. */
- (NSArray<NSString *> *)correlateMessageToAll:(NSString *)messageName
                                   businessKey:(NSString *)businessKey
                               correlationKeys:(NSDictionary *)correlationKeys
                                     variables:(NSDictionary *)variables
                                         error:(NSError **)error;
/*
 * Sends a signal: every path waiting for it, in every process instance,
 * receives it, and every process whose start event it is starts. Nobody
 * waiting is not an error. The variables are set on each receiver.
 */
- (BOOL)signal:(NSString *)signalName
     variables:(NSDictionary *)variables
         error:(NSError **)error;
/* To the paths of one instance waiting for it. */
- (BOOL)signal:(NSString *)signalName
processInstanceId:(NSString *)processInstanceId
     variables:(NSDictionary *)variables
         error:(NSError **)error;

/* To a waiting path of that instance. */
- (BOOL)correlateMessage:(NSString *)messageName
       processInstanceId:(NSString *)processInstanceId
               variables:(NSDictionary *)variables
                   error:(NSError **)error;

@end

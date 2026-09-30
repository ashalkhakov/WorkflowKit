#import <CoreData/CoreData.h>
#import "WFTypes.h"

@class WFProcessEngine;
@class WFProcessDefinition;
@class WFEvent;
@class WFExecutionEntity;
@class WFEventSubscriptionEntity;
@class WFJobEntity;

/*
 * One command: a Core Data context of its own, the agenda of operations
 * that advance executions, and what to do once the command has committed.
 *
 * -execute:error: runs the body, then the agenda until it is empty -- at
 * which point every path is at a wait state or has ended -- then saves.
 * Anything that fails rolls the whole command back; nothing it scheduled
 * after commit happens.
 */
@class WFDecisionDefinition;
@class WFTaskEntity;
@class WFDecisionResult;

@interface WFCommandContext : NSObject

@property (nonatomic, readonly, weak) WFProcessEngine *engine;
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;

- (instancetype)initWithEngine:(WFProcessEngine *)engine;

- (BOOL)execute:(BOOL (^)(WFCommandContext *command, NSError **error))body
          error:(NSError **)error;

/* Fails the command: the agenda stops and nothing is saved. */
- (void)fail:(NSError *)error;
/* Runs on the calling thread after a successful save, in order. */
- (void)afterCommit:(void (^)(void))block;

+ (NSString *)newId;
/* Whether the engine can store the value as a variable. */
+ (BOOL)isStorableValue:(id)value;
+ (BOOL)areStorableVariables:(NSDictionary *)variables error:(NSError **)error;

- (NSArray *)fetch:(NSString *)entity
         predicate:(NSPredicate *)predicate
              sort:(NSArray *)sort
             limit:(NSUInteger)limit;
- (id)insert:(NSString *)entity;
- (WFProcessDefinition *)definitionForExecution:(WFExecutionEntity *)execution;

/* The runtime operations commands are made of. */
- (WFExecutionEntity *)startProcessInstance:(WFProcessDefinition *)definition
                                businessKey:(NSString *)businessKey
                                  variables:(NSDictionary *)variables
                                 startEvent:(WFEvent *)startEvent;
/* The execution's wait state is over (its user or external task is done):
 * it leaves the activity. */
- (void)completeActivity:(WFExecutionEntity *)execution;
/* A BPMN error with that code, raised at the execution's activity. */
- (void)throwBpmnError:(NSString *)errorCode fromExecution:(WFExecutionEntity *)execution;
- (void)deliverSubscription:(WFEventSubscriptionEntity *)subscription
                  variables:(NSDictionary *)variables;
/* Delivers the signal to every path waiting for it and starts every
 * process whose start event it is -- or, with processInstanceId, only to
 * that instance's paths. Answers how many it reached. */
- (NSUInteger)broadcastSignal:(NSString *)signalName
                    variables:(NSDictionary *)variables
            processInstanceId:(NSString *)processInstanceId;
/* Deletes the job and does what it was for: triggers its timer event,
 * starts an instance for a timer start event, or continues an async
 * continuation. */
- (void)runJob:(WFJobEntity *)job;
/* Suspension, of an instance with the instances it called, or of a
 * definition (its timer start too) and, optionally, its instances. */
- (BOOL)isDefinitionSuspended:(NSString *)definitionId;
- (void)setSuspended:(BOOL)suspended processInstance:(NSString *)processInstanceId;
- (void)setSuspended:(BOOL)suspended definition:(NSString *)definitionId includeInstances:(BOOL)instances;
- (void)deleteProcessInstance:(WFExecutionEntity *)root reason:(NSString *)reason;
/* Modification: each instruction a dictionary -- type (startBefore,
 * startAfter, startTransition, cancel, cancelAll), target, and for
 * startBefore an ancestor and variables -- run in order. An instance left
 * with nothing ends, externally terminated. */
- (void)modifyProcessInstance:(WFExecutionEntity *)root instructions:(NSArray<NSDictionary *> *)instructions;
/* Migration: the plan's mappings -- each a dictionary of source, target
 * and updateEventTrigger -- resolved and checked against the two
 * definitions; with mapEqual, activities of the same id, type and scope
 * are added. nil, with the command failed, for a plan that cannot be. */
- (NSDictionary<NSString *, NSDictionary *> *)migrationFrom:(WFProcessDefinition *)source
                                                          to:(WFProcessDefinition *)target
                                                    mappings:(NSArray<NSDictionary *> *)mappings
                                                    mapEqual:(BOOL)mapEqual;
/* Moves the instance onto the target definition as the resolved
 * mappings say; NO, with the command failed, when it cannot be. */
- (BOOL)migrate:(WFExecutionEntity *)root
      mappings:(NSDictionary<NSString *, NSDictionary *> *)mappings
        source:(WFProcessDefinition *)source
        target:(WFProcessDefinition *)target;
/* The activity instance tree: nested dictionaries of activityInstanceId,
 * activityId and children, the process instance at the root. */
- (NSDictionary *)activityInstanceTreeOf:(WFExecutionEntity *)root;
/* A job or external task that ran out of retries. */
- (void)raiseIncident:(NSString *)type
        configuration:(NSString *)configuration
              message:(NSString *)message
           activityId:(NSString *)activityId
    processInstanceId:(NSString *)processInstanceId
            execution:(WFExecutionEntity *)execution;
- (void)resolveIncidentsFor:(NSString *)configuration;

/* History, at the engine's level. */
- (void)historyJob:(WFJobEntity *)job state:(NSString *)state;
- (void)historyTaskCompleted:(NSString *)taskId;
- (void)historyTask:(NSString *)taskId assignee:(NSString *)assignee;

/* Variables visible from the execution: its scope chain, nearest first. */
/* Evaluates the decision over the variables, recording it at history
 * level full; nil, with the command failed, when it cannot be. The
 * execution is the business rule task's, nil for the decision service. */
- (WFDecisionResult *)evaluateDecision:(WFDecisionDefinition *)decision
                             variables:(NSDictionary *)variables
                             execution:(WFExecutionEntity *)execution;
/* A user task's assignment and completion listeners; NO, with the
 * command failed, when one fails. */
- (BOOL)taskAssigned:(WFTaskEntity *)row;
- (BOOL)taskCompleting:(WFTaskEntity *)row;
- (BOOL)setLocal:(NSString *)name value:(id)value on:(WFExecutionEntity *)execution;
- (NSDictionary *)visibleVariables:(WFExecutionEntity *)execution;
/* Each one where it exists in the scope chain, else on the process
 * instance. NO, with the command failed, for a value that cannot be
 * stored. */
- (BOOL)setVariables:(NSDictionary *)variables from:(WFExecutionEntity *)execution;
/* Removes the execution's own variables of those names; others are left. */
- (void)removeVariables:(NSArray<NSString *> *)names from:(WFExecutionEntity *)execution;

@end

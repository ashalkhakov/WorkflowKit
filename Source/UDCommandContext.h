#ifndef UDCommandContext_h
#define UDCommandContext_h

#import <CoreData/CoreData.h>
#import "UDTypes.h"

@class UDProcessEngine;
@class UDProcessDefinition;
@class UDEvent;
@class UDExecutionEntity;
@class UDEventSubscriptionEntity;
@class UDJobEntity;

/*
 * One command: a Core Data context of its own, the agenda of operations
 * that advance executions, and what to do once the command has committed.
 *
 * -execute:error: runs the body, then the agenda until it is empty -- at
 * which point every path is at a wait state or has ended -- then saves.
 * Anything that fails rolls the whole command back; nothing it scheduled
 * after commit happens.
 */
@interface UDCommandContext : NSObject

@property (nonatomic, readonly, weak) UDProcessEngine *engine;
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;

- (instancetype)initWithEngine:(UDProcessEngine *)engine;

- (BOOL)execute:(BOOL (^)(UDCommandContext *command, NSError **error))body
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
- (UDProcessDefinition *)definitionForExecution:(UDExecutionEntity *)execution;

/* The runtime operations commands are made of. */
- (UDExecutionEntity *)startProcessInstance:(UDProcessDefinition *)definition
                                businessKey:(NSString *)businessKey
                                  variables:(NSDictionary *)variables
                                 startEvent:(UDEvent *)startEvent;
/* The execution's wait state is over (its user or external task is done):
 * it leaves the activity. */
- (void)completeActivity:(UDExecutionEntity *)execution;
/* A BPMN error with that code, raised at the execution's activity. */
- (void)throwBpmnError:(NSString *)errorCode fromExecution:(UDExecutionEntity *)execution;
- (void)deliverSubscription:(UDEventSubscriptionEntity *)subscription
                  variables:(NSDictionary *)variables;
/* Deletes the job and triggers its timer event. */
- (void)fireTimer:(UDJobEntity *)job;

/* Variables visible from the execution: its scope chain, nearest first. */
- (NSDictionary *)visibleVariables:(UDExecutionEntity *)execution;
/* Each one where it exists in the scope chain, else on the process
 * instance. NO, with the command failed, for a value that cannot be
 * stored. */
- (BOOL)setVariables:(NSDictionary *)variables from:(UDExecutionEntity *)execution;

@end

#endif /* UDCommandContext_h */

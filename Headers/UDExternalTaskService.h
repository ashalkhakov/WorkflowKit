#import "UDTypes.h"

/* A service task's work, waiting under a topic for a worker. */
@interface UDExternalTask : NSObject
@property (nonatomic, readonly, copy) NSString *externalTaskId;
@property (nonatomic, readonly, copy) NSString *topic;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSString *businessKey;
@property (nonatomic, readonly, copy) NSString *activityId;
/* The worker holding the lock, and until when; nil when unlocked. A
 * failed task waiting out its retry timeout has no worker but an
 * expiration. */
@property (nonatomic, readonly, copy) NSString *workerId;
@property (nonatomic, readonly, copy) NSDate *lockExpiration;
/* nil until a worker reports a failure; then the attempts left. 0: the
 * task has an incident and is not fetched. */
@property (nonatomic, readonly, strong) NSNumber *retries;
@property (nonatomic, readonly, copy) NSString *errorMessage;
@property (nonatomic, readonly) NSInteger priority;
/* The variables visible at the task, for a task just fetched; nil
 * otherwise. */
@property (nonatomic, readonly, copy) NSDictionary *variables;
@end

/*
 * External tasks: work handed to workers outside the engine's
 * transaction -- in another process, another language, or the engine's
 * own in-process worker, which uses this service like any other.
 *
 * A worker fetches and locks tasks by topic, does the work, and then
 * completes the task, reports a failure, or reports a BPMN error. Only the
 * worker holding the lock may do so; a lock that runs out lets another
 * worker fetch the task.
 */
@interface UDExternalTaskService : NSObject

- (instancetype)init NS_UNAVAILABLE;

/* Up to maxTasks unlocked tasks of the topics, highest priority first,
 * then oldest first, each locked for its topic's duration in seconds.
 * Tasks whose retries have run out are not fetched. */
- (NSArray<UDExternalTask *> *)fetchAndLock:(NSUInteger)maxTasks
                                   workerId:(NSString *)workerId
                                     topics:(NSDictionary<NSString *, NSNumber *> *)lockDurations
                                      error:(NSError **)error;
/* The same, with the variables to return per topic; a topic not in
 * variableNames gets all of them. */
- (NSArray<UDExternalTask *> *)fetchAndLock:(NSUInteger)maxTasks
                                   workerId:(NSString *)workerId
                                     topics:(NSDictionary<NSString *, NSNumber *> *)lockDurations
                              variableNames:(NSDictionary<NSString *, NSArray<NSString *> *> *)variableNames
                                      error:(NSError **)error;

/* The activity is done: the variables are set on the process (where they
 * exist, else on the process instance) and its path continues. */
- (BOOL)complete:(NSString *)externalTaskId
        workerId:(NSString *)workerId
       variables:(NSDictionary *)variables
           error:(NSError **)error;

/* The work failed. The task gets retries attempts more, fetchable again
 * after retryTimeout seconds; with 0 it raises an incident and waits. */
- (BOOL)handleFailure:(NSString *)externalTaskId
             workerId:(NSString *)workerId
         errorMessage:(NSString *)errorMessage
              retries:(NSInteger)retries
         retryTimeout:(NSTimeInterval)retryTimeout
                error:(NSError **)error;

/* A business error with that code, for the activity's error boundary
 * events; uncaught, it ends the path. The variables are set first. */
- (BOOL)handleBpmnError:(NSString *)externalTaskId
               workerId:(NSString *)workerId
              errorCode:(NSString *)errorCode
              variables:(NSDictionary *)variables
                  error:(NSError **)error;

/* Keeps the task for another duration seconds from now. The lock must
 * still be the worker's. */
- (BOOL)extendLock:(NSString *)externalTaskId
          workerId:(NSString *)workerId
          duration:(NSTimeInterval)duration
             error:(NSError **)error;

/* Releases a lock, whoever holds it. */
- (BOOL)unlock:(NSString *)externalTaskId error:(NSError **)error;

/* Gives a task attempts again; above 0 resolves its incident. */
- (BOOL)setRetries:(NSInteger)retries
   forExternalTask:(NSString *)externalTaskId
             error:(NSError **)error;

- (UDExternalTask *)externalTaskWithId:(NSString *)externalTaskId;
- (NSArray<UDExternalTask *> *)externalTasksForProcessInstance:(NSString *)processInstanceId;

@end

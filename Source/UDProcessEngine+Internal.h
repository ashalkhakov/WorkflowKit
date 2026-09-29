#ifndef UDProcessEngine_Internal_h
#define UDProcessEngine_Internal_h

#import "UDProcessEngine.h"

@class UDCommandContext;
@class UDProcessDefinition;
@class UDExecutionEntity;
@class UDTaskEntity;
@class UDHistoricProcessInstanceEntity;

/* What commands tell the engine after they commit, and how services run
 * commands. */
@interface UDProcessEngine (UDInternal)
- (BOOL)ud_runCommand:(BOOL (^)(UDCommandContext *command, NSError **error))body
                error:(NSError **)error;
- (void)ud_taskCreated:(UDWorkItem *)task;
- (void)ud_processInstanceEnded:(UDProcessInstance *)instance;
- (void)ud_messageThrown:(NSString *)messageName
               variables:(NSDictionary *)variables
       processInstanceId:(NSString *)processInstanceId;
- (void)ud_externalTaskCreated:(NSString *)externalTaskId
             processInstanceId:(NSString *)processInstanceId;
- (void)ud_jobCreated:(NSString *)jobId
    processInstanceId:(NSString *)processInstanceId
              dueDate:(NSDate *)dueDate
            exclusive:(BOOL)exclusive;
/* Runs one job on the calling thread: acquire, then run, then on failure
 * record it. force ignores the due date, retries and other owners' locks. */
- (BOOL)ud_runJob:(NSString *)jobId force:(BOOL)force error:(NSError **)error;
- (void)ud_reschedule;
/* Orders history written in the same instant. */
- (int64_t)ud_nextSequence;
/* The serial queue a process instance's work runs on. */
- (dispatch_queue_t)ud_queueFor:(NSString *)key;
@end

@interface UDExternalTaskService (UDInternal)
- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine;
/* Locks that one task, if it is available: how the in-process worker
 * takes a task the moment it is created. */
- (UDExternalTask *)ud_lockTask:(NSString *)externalTaskId
                       workerId:(NSString *)workerId
                       duration:(NSTimeInterval)duration;
@end

@interface UDManagementService (UDInternal)
- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine;
@end

@interface UDRepositoryService (UDInternal)
/* Called after each stored deployment: a timer start event may have added
 * a job. */
@property (nonatomic, copy) void (^didStoreDeployment)(void);
@end

@interface UDWorkItem (UDInternal)
+ (instancetype)ud_workItemWithEntity:(UDTaskEntity *)entity;
@end

@interface UDProcessInstance (UDInternal)
+ (instancetype)ud_instanceWithExecution:(UDExecutionEntity *)root
                              definition:(UDProcessDefinition *)definition
                                   ended:(BOOL)ended;
+ (instancetype)ud_instanceWithHistory:(UDHistoricProcessInstanceEntity *)history;
/* An instance that ended within the command that started it, when there
 * is no history to read it back from. */
+ (instancetype)ud_endedInstance:(NSString *)processInstanceId
                     businessKey:(NSString *)businessKey
                      definition:(UDProcessDefinition *)definition;
@end

@interface UDHistoricProcessInstance (UDInternal)
+ (instancetype)ud_instanceWithEntity:(UDHistoricProcessInstanceEntity *)entity;
@end

@interface UDRuntimeService (UDInternal)
- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine;
@end

@interface UDTaskService (UDInternal)
- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine;
@end

@interface UDHistoryService (UDInternal)
- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine;
@end

#endif /* UDProcessEngine_Internal_h */

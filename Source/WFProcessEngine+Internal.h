#import "WFProcessEngine.h"

@class WFCommandContext;
@class WFProcessDefinition;
@class WFExecutionEntity;
@class WFTaskEntity;
@class WFHistoricProcessInstanceEntity;

/* What commands tell the engine after they commit, and how services run
 * commands. */
@interface WFProcessEngine (WFInternal)
- (BOOL)wf_runCommand:(BOOL (^)(WFCommandContext *command, NSError **error))body
                error:(NSError **)error;
- (void)wf_taskCreated:(WFWorkItem *)task;
- (void)wf_processInstanceEnded:(WFProcessInstance *)instance;
- (void)wf_messageThrown:(NSString *)messageName
               variables:(NSDictionary *)variables
       processInstanceId:(NSString *)processInstanceId;
- (void)wf_externalTaskCreated:(NSString *)externalTaskId
             processInstanceId:(NSString *)processInstanceId;
- (void)wf_jobCreated:(NSString *)jobId
    processInstanceId:(NSString *)processInstanceId
              dueDate:(NSDate *)dueDate
            exclusive:(BOOL)exclusive;
/* Runs one job on the calling thread: acquire, then run, then on failure
 * record it. force ignores the due date, retries and other owners' locks. */
- (BOOL)wf_runJob:(NSString *)jobId force:(BOOL)force error:(NSError **)error;
- (void)wf_reschedule;
/* Orders history written in the same instant. */
- (int64_t)wf_nextSequence;
/* The serial queue a process instance's work runs on. */
- (dispatch_queue_t)wf_queueFor:(NSString *)key;
@end

@interface WFExternalTaskService (WFInternal)
- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine;
/* Locks that one task, if it is available: how the in-process worker
 * takes a task the moment it is created. */
- (WFExternalTask *)wf_lockTask:(NSString *)externalTaskId
                       workerId:(NSString *)workerId
                       duration:(NSTimeInterval)duration;
@end

@interface WFManagementService (WFInternal)
- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine;
@end

@interface WFRepositoryService (WFInternal)
/* Called after each stored deployment: a timer start event may have added
 * a job. */
@property (nonatomic, copy) void (^didStoreDeployment)(void);
/* The engine whose commands suspend and activate definitions. */
- (void)wf_setEngine:(WFProcessEngine *)engine;
@end

@interface WFWorkItem (WFInternal)
+ (instancetype)wf_workItemWithEntity:(WFTaskEntity *)entity;
@end

@interface WFProcessInstance (WFInternal)
+ (instancetype)wf_instanceWithExecution:(WFExecutionEntity *)root
                              definition:(WFProcessDefinition *)definition
                                   ended:(BOOL)ended;
+ (instancetype)wf_instanceWithHistory:(WFHistoricProcessInstanceEntity *)history;
/* An instance that ended within the command that started it, when there
 * is no history to read it back from. */
+ (instancetype)wf_endedInstance:(NSString *)processInstanceId
                     businessKey:(NSString *)businessKey
                      definition:(WFProcessDefinition *)definition;
@end

@interface WFHistoricProcessInstance (WFInternal)
+ (instancetype)wf_instanceWithEntity:(WFHistoricProcessInstanceEntity *)entity;
@end

@interface WFRuntimeService (WFInternal)
- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine;
@end

@interface WFTaskService (WFInternal)
- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine;
@end

@interface WFHistoryService (WFInternal)
- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine;
@end

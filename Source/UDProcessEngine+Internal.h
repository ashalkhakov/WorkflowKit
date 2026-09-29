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
              dueDate:(NSDate *)dueDate;
@end

@interface UDWorkItem (UDInternal)
+ (instancetype)ud_workItemWithEntity:(UDTaskEntity *)entity;
@end

@interface UDProcessInstance (UDInternal)
+ (instancetype)ud_instanceWithExecution:(UDExecutionEntity *)root
                              definition:(UDProcessDefinition *)definition
                                   ended:(BOOL)ended;
+ (instancetype)ud_instanceWithHistory:(UDHistoricProcessInstanceEntity *)history;
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

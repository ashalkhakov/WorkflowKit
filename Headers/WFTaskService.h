#import "WFTypes.h"

/* An open user task: a work item for a person. */
@interface WFWorkItem : NSObject
@property (nonatomic, readonly, copy) NSString *taskId;
@property (nonatomic, readonly, copy) NSString *name;
/* The user task's id in the BPMN. */
@property (nonatomic, readonly, copy) NSString *taskDefinitionKey;
@property (nonatomic, readonly, copy) NSString *assignee;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSDate *createdAt;
@property (nonatomic, readonly, copy) NSDate *dueDate;
@property (nonatomic, readonly) NSInteger priority;
@end

/* User tasks. */
@interface WFTaskService : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (WFWorkItem *)taskWithId:(NSString *)taskId error:(NSError **)error;
- (NSArray<WFWorkItem *> *)tasksForProcessInstance:(NSString *)processInstanceId;
- (NSArray<WFWorkItem *> *)tasksForAssignee:(NSString *)assignee;

/* Completes the task and continues its path, as one command. The
 * variables are set on the process: existing ones where they are, new
 * ones on the process instance. */
- (BOOL)completeTask:(NSString *)taskId
           variables:(NSDictionary *)variables
               error:(NSError **)error;

@end

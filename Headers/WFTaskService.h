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
@property (nonatomic, readonly, copy) NSDate *followUpDate;
@property (nonatomic, readonly) NSInteger priority;
/* Who it is offered to, until someone claims it. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *candidateUsers;
@property (nonatomic, readonly, copy) NSArray<NSString *> *candidateGroups;
/* Its process instance is suspended: it cannot be completed. */
@property (nonatomic, readonly, getter=isSuspended) BOOL suspended;
@end

/* User tasks. */
@interface WFTaskService : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (WFWorkItem *)taskWithId:(NSString *)taskId error:(NSError **)error;
- (NSArray<WFWorkItem *> *)tasksForProcessInstance:(NSString *)processInstanceId;
- (NSArray<WFWorkItem *> *)tasksForAssignee:(NSString *)assignee;
/* Unclaimed tasks offered to the user, or to one of the groups -- the
 * user's own, which the engine does not know: there is no identity
 * service. */
- (NSArray<WFWorkItem *> *)tasksForCandidateUser:(NSString *)userId groups:(NSArray<NSString *> *)groupIds;
- (NSArray<WFWorkItem *> *)tasksForCandidateGroup:(NSString *)groupId;

/* Takes the task: it becomes the user's. Fails when someone else has it. */
- (BOOL)claimTask:(NSString *)taskId user:(NSString *)userId error:(NSError **)error;
/* Gives it back to its candidates. */
- (BOOL)unclaimTask:(NSString *)taskId error:(NSError **)error;
/* Gives it to the user, or with nil to nobody, whoever had it. */
- (BOOL)setAssignee:(NSString *)userId forTask:(NSString *)taskId error:(NSError **)error;

/* Completes the task and continues its path, as one command. The
 * variables are set on the process: existing ones where they are, new
 * ones on the process instance. */
- (BOOL)completeTask:(NSString *)taskId
           variables:(NSDictionary *)variables
               error:(NSError **)error;

@end

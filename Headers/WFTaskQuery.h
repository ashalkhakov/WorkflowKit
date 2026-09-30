#import "WFTypes.h"

/* How a condition compares a value. */
typedef NS_ENUM(NSInteger, WFQueryOperator) {
	WFQueryEqual = 0,
	WFQueryNotEqual,
	WFQueryGreater,
	WFQueryGreaterOrEqual,
	WFQueryLess,
	WFQueryLessOrEqual,
	/* A string matching a pattern: % stands for any run of characters, _
	 * for any one. */
	WFQueryLike
};

typedef NS_ENUM(NSInteger, WFTaskOrder) {
	WFTaskOrderCreated = 0,
	WFTaskOrderDueDate,
	WFTaskOrderFollowUpDate,
	WFTaskOrderPriority,
	WFTaskOrderName,
	WFTaskOrderAssignee
};

/*
 * Which open user tasks to find, for -[WFTaskService tasksMatching:...]:
 * every condition set holds. Each method sets one and answers the query,
 * so they chain:
 *
 *   [[[WFTaskQuery query] candidateUser:@"ann" groups:@[ @"sales" ]]
 *       processVariable:@"amount" operator:WFQueryGreater value:@1000]
 *
 * The whole query is one fetch, evaluated by the store.
 */
@interface WFTaskQuery : NSObject <NSCopying>

+ (instancetype)query;

- (instancetype)processInstanceId:(NSString *)processInstanceId;
- (instancetype)businessKey:(NSString *)businessKey;
- (instancetype)processDefinitionId:(NSString *)definitionId;
/* Of any version of the process. */
- (instancetype)processDefinitionKey:(NSString *)key;
/* The user task's id in the BPMN. */
- (instancetype)taskDefinitionKey:(NSString *)key;
- (instancetype)nameLike:(NSString *)pattern;

- (instancetype)assignee:(NSString *)userId;
- (instancetype)unassigned;
- (instancetype)assigned;
/* Unclaimed, and offered to the user or to one of the groups. */
- (instancetype)candidateUser:(NSString *)userId groups:(NSArray<NSString *> *)groupIds;
/* Unclaimed, and offered to the group. */
- (instancetype)candidateGroup:(NSString *)groupId;

- (instancetype)minPriority:(NSInteger)priority;
- (instancetype)maxPriority:(NSInteger)priority;
- (instancetype)dueBefore:(NSDate *)date;
- (instancetype)dueAfter:(NSDate *)date;
- (instancetype)followUpBefore:(NSDate *)date;
/* Of a suspended process instance, or of an active one. */
- (instancetype)suspended:(BOOL)suspended;

/*
 * A variable of the task's process instance -- one set on the instance
 * itself, not in a scope inside it -- compared with a value: a string, a
 * number, a boolean, a date, or nil (NSNull) for a variable set to null.
 * A number matches a whole or a real number; eq and ne match a boolean;
 * like matches a string. ne matches a variable that is set to another
 * value, of any type; a task whose instance has no such variable matches
 * no condition on it. One the engine cannot evaluate -- a boolean ordered,
 * a data value -- fails the query (WFErrorInvalidQuery).
 */
- (instancetype)processVariable:(NSString *)name operator:(WFQueryOperator)op value:(id)value;

/* Sorted by each ordering in turn, then by when they were created; by
 * default by creation alone. Where a task has no due date, follow-up date,
 * name or assignee, the store says whether it sorts first or last. */
- (instancetype)orderBy:(WFTaskOrder)order ascending:(BOOL)ascending;

@end

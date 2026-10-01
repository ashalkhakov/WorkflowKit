#import <CoreData/CoreData.h>

/* What WFExecution's generated properties name. */
@class WFEventSubscriptionEntity, WFExternalTaskEntity, WFIncidentEntity, WFJobEntity, WFTaskEntity, WFVariableEntity;

/*
 * One path of the execution tree. A process instance is its root; one
 * started by a call activity has superProcessInstanceId and
 * superExecution, the execution at the call activity, whose
 * subProcessInstance it is. A multi-instance body's activity is the
 * multi-instance activity, its children the instances; a compensation
 * execution runs one handler for the throw its parent waits at.
 * lockRevision is bumped to make concurrent commands on a scope conflict.
 */
@interface WFExecutionEntity : NSManagedObject
- (BOOL)isProcessInstance;
- (WFExecutionEntity *)processInstance;
/* This execution if it is a scope, else the nearest scope above it. */
- (WFExecutionEntity *)scopeExecution;
- (NSArray<WFExecutionEntity *> *)concurrentChildren;
- (WFVariableEntity *)localVariableNamed:(NSString *)name;
@end

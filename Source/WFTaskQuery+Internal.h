#import "WFTaskQuery.h"

@interface WFTaskQuery (Internal)
/* The key a query asks for, whose definitions' ids the caller fetches. */
@property (nonatomic, readonly, copy) NSString *wf_processDefinitionKey;
/* The predicate over WFTask rows, with the definitions of the key given;
 * nil, with an error, for a condition the engine cannot evaluate. */
- (NSPredicate *)wf_predicateWithDefinitionIds:(NSArray<NSString *> *)definitionIds error:(NSError **)error;
- (NSArray<NSSortDescriptor *> *)wf_sortDescriptors;
@end

/*
 * A variable condition over rows that reach variables by the key path
 * (processInstance.variables from a task, variables from a process
 * instance): some variable of that name holds a value the operator
 * matches. nil, with an error, for one the engine cannot evaluate.
 */
NSPredicate *WFVariablePredicate(NSString *variablesKeyPath, NSString *name, WFQueryOperator op, id value,
                                 NSError **error);

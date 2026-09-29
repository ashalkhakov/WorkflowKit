#import "WFTypes.h"

/* A sequence flow's condition. */
@protocol WFCondition <NSObject>
/* YES when it holds over the variables. NO when it does not, or when it
 * has no truth (FEEL's null); NO with an error when it is not a condition
 * at all -- its value is a number, say. */
- (BOOL)evaluateWithVariables:(NSDictionary *)variables
                        error:(NSError **)error;
/* The condition as FEEL. */
- (NSString *)expressionString;
@end

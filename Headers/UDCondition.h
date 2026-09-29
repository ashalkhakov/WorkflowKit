#import "UDTypes.h"

@protocol UDCondition <NSObject>
- (BOOL)evaluateWithVariables:(NSDictionary *)variables
                        error:(NSError **)error;
@end

@interface UDComparisonCondition : NSObject <UDCondition>

@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly) UDComparisonOp op;
@property (nonatomic, readonly, strong) id value;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithKey:(NSString *)key
                         op:(UDComparisonOp)op
                      value:(id)value NS_DESIGNATED_INITIALIZER;

+ (instancetype)key:(NSString *)key equals:(id)value;
+ (instancetype)key:(NSString *)key greaterThan:(id)value;
/* `key op value`, the comparison subset of FEEL: operators = != > >= < <=
 * (== is accepted too), values numbers, true/false, or double-quoted
 * strings. */
+ (instancetype)conditionWithExpression:(NSString *)expression
                                  error:(NSError **)error;
/* The condition as FEEL. */
- (NSString *)expressionString;

@end

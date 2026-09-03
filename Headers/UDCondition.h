#ifndef UDCondition_h
#define UDCondition_h

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
+ (instancetype)conditionWithExpression:(NSString *)expression
                                  error:(NSError **)error;
- (NSString *)expressionString;

@end

/*
 * Target-action condition.
 * Action signature:
 *   - (BOOL)evaluateCondition:(UDActionCondition *)condition
 *                   variables:(NSDictionary *)variables
 *                       error:(NSError **)error;
 */
@interface UDActionCondition : NSObject <UDCondition>

@property (nonatomic, readonly, weak) id target;
@property (nonatomic, readonly) SEL action;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTarget:(id)target
                        action:(SEL)action NS_DESIGNATED_INITIALIZER;

@end

#endif /* UDCondition_h */

#import "WFFeelInternal.h"

@interface WFFeelExpression ()
@property (nonatomic, strong) WFFeelNode *root;
- (instancetype)initWithRoot:(WFFeelNode *)root;
@end

@implementation WFFeelExpression

+ (instancetype)expressionWithString:(NSString *)text camunda7:(BOOL)camunda7 error:(NSError **)error
{
	WFFeelNode *root = WFFeelParse(text, camunda7, error);
	if (root == nil) {
		return nil;
	}
	return [[self alloc] initWithRoot:root];
}

+ (instancetype)expressionWithString:(NSString *)text error:(NSError **)error
{
	return [self expressionWithString:text camunda7:NO error:error];
}

+ (instancetype)expressionWithCamunda7String:(NSString *)text error:(NSError **)error
{
	return [self expressionWithString:text camunda7:YES error:error];
}

- (instancetype)initWithRoot:(WFFeelNode *)root
{
	self = [super init];
	if (self) {
		_root = root;
	}
	return self;
}

- (id)valueWithVariables:(NSDictionary *)variables
{
	return WFFeelPublicValue(WFFeelEvaluate(self.root, variables ?: @{}));
}

- (BOOL)evaluateWithVariables:(NSDictionary *)variables error:(NSError **)error
{
	id value = [self valueWithVariables:variables];
	if (WFFeelIsBoolean(value)) {
		return [value boolValue];
	}
	if (!WFFeelIsNull(value) && error != NULL) {
		*error = [NSError errorWithDomain:WFErrorDomain
		                             code:WFErrorCondition
		                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:
			@"condition \"%@\" is %@, not true or false", [self expressionString],
			WFFeelLiteralText(value)] }];
	}
	return NO;
}

- (NSString *)expressionString
{
	return [self.root description];
}

- (NSString *)description
{
	return [self expressionString];
}

@end

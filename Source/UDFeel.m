#import "UDFeelInternal.h"

@interface UDFeelExpression ()
@property (nonatomic, strong) UDFeelNode *root;
- (instancetype)initWithRoot:(UDFeelNode *)root;
@end

@implementation UDFeelExpression

+ (instancetype)expressionWithString:(NSString *)text camunda7:(BOOL)camunda7 error:(NSError **)error
{
	UDFeelNode *root = UDFeelParse(text, camunda7, error);
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

- (instancetype)initWithRoot:(UDFeelNode *)root
{
	self = [super init];
	if (self) {
		_root = root;
	}
	return self;
}

- (id)valueWithVariables:(NSDictionary *)variables
{
	return UDFeelEvaluate(self.root, variables ?: @{});
}

- (BOOL)evaluateWithVariables:(NSDictionary *)variables error:(NSError **)error
{
	id value = [self valueWithVariables:variables];
	if (UDFeelIsBoolean(value)) {
		return [value boolValue];
	}
	if (!UDFeelIsNull(value) && error != NULL) {
		*error = [NSError errorWithDomain:UDWorkflowErrorDomain
		                             code:UDWorkflowErrorCondition
		                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:
			@"condition \"%@\" is %@, not true or false", [self expressionString],
			UDFeelLiteralText(value)] }];
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

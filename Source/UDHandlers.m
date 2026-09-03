#import "UDHandlers.h"

@implementation UDServiceResult
@end

@implementation UDServiceInvocation

- (instancetype)initWithActionKey:(NSString *)actionKey
                        variables:(NSDictionary *)variables
                          tokenId:(NSString *)tokenId
                         instance:(UDProcessInstance *)instance
{
	self = [super init];
	if (self) {
		_actionKey = [actionKey copy];
		_variables = [variables copy];
		_tokenId = [tokenId copy];
		_instance = instance;
	}
	return self;
}

- (void)finishWithVariables:(NSDictionary *)outVars error:(NSError *)error
{
	id target = self.target;
	if (target == nil || self.action == NULL) {
		return;
	}
	if (![target respondsToSelector:self.action]) {
		return;
	}

	UDServiceResult *result = [[UDServiceResult alloc] init];
	result.actionKey = self.actionKey;
	result.variables = outVars;
	result.error = error;

	NSMethodSignature *sig = [target methodSignatureForSelector:self.action];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
	[invocation setTarget:target];
	[invocation setSelector:self.action];
	UDServiceInvocation *request = self;
	[invocation setArgument:&request atIndex:2];
	[invocation setArgument:&result atIndex:3];
	[invocation invoke];
}

@end

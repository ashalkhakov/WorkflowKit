#import "UDHandlers.h"

@implementation UDServiceResult
@end

@implementation UDServiceInvocation

- (instancetype)initWithJobId:(NSString *)jobId
                    actionKey:(NSString *)actionKey
                    variables:(NSDictionary *)variables
                   instanceId:(NSString *)instanceId
                      tokenId:(NSString *)tokenId
{
	self = [super init];
	if (self) {
		_jobId = [jobId copy];
		_actionKey = [actionKey copy];
		_variables = [variables copy];
		_instanceId = [instanceId copy];
		_tokenId = [tokenId copy];
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

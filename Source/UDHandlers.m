#import "UDHandlers.h"

@implementation UDServiceResult
@end

@implementation UDServiceInvocation

- (instancetype)initWithExternalTaskId:(NSString *)externalTaskId
                                 topic:(NSString *)topic
                             variables:(NSDictionary *)variables
                     processInstanceId:(NSString *)processInstanceId
                            activityId:(NSString *)activityId
{
	self = [super init];
	if (self) {
		_externalTaskId = [externalTaskId copy];
		_topic = [topic copy];
		_variables = [variables copy];
		_processInstanceId = [processInstanceId copy];
		_activityId = [activityId copy];
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
	result.topic = self.topic;
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

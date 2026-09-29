#import "UDRuntimeState.h"
#import "UDProcessDefinition.h"
#import <dispatch/dispatch.h>

@implementation UDToken

- (NSString *)description
{
	NSString *state = @"ready";
	if (self.state == UDTokenStateWaiting) {
		state = @"waiting";
	} else if (self.state == UDTokenStateCompleted) {
		state = @"completed";
	}
	return [NSString stringWithFormat:@"<UDToken %@ node=%@ %@>",
		self.tokenId, self.nodeId, state];
}

@end

@implementation UDProcessInstance

- (instancetype)init
{
	self = [super init];
	if (self) {
		_variables = [NSMutableDictionary dictionary];
		_correlationKeys = [NSMutableDictionary dictionary];
		_forkExpected = [NSMutableDictionary dictionary];
		_tokens = [NSMutableArray array];
		_children = [NSMutableDictionary dictionary];
		_tokenSerial = 0;
		_pendingServices = 0;
		_pendingTimers = 0;
		_quiesce = dispatch_semaphore_create(0);
	}
	return self;
}

- (void)dealloc
{
	if (_queue != NULL) {
		UDDispatchRelease(_queue);
	}
	if (_quiesce != NULL) {
		UDDispatchRelease(_quiesce);
	}
}

- (void)setQueue:(dispatch_queue_t)queue
{
	if (queue == _queue) {
		return;
	}
	if (queue != NULL) {
		UDDispatchRetain(queue);
	}
	if (_queue != NULL) {
		UDDispatchRelease(_queue);
	}
	_queue = queue;
}

- (void)setQuiesce:(dispatch_semaphore_t)quiesce
{
	if (quiesce == _quiesce) {
		return;
	}
	if (quiesce != NULL) {
		UDDispatchRetain(quiesce);
	}
	if (_quiesce != NULL) {
		UDDispatchRelease(_quiesce);
	}
	_quiesce = quiesce;
}

- (UDToken *)nextReadyToken
{
	for (UDToken *token in self.tokens) {
		if (token.state == UDTokenStateReady) {
			return token;
		}
	}
	return nil;
}

- (NSArray<UDToken *> *)tokensAtNode:(NSString *)nodeId
                               state:(UDTokenState)state
{
	NSMutableArray *result = [NSMutableArray array];
	for (UDToken *token in self.tokens) {
		if (token.state == state && [token.nodeId isEqualToString:nodeId]) {
			[result addObject:token];
		}
	}
	return result;
}

- (UDToken *)tokenWithId:(NSString *)tokenId
{
	for (UDToken *token in self.tokens) {
		if ([token.tokenId isEqualToString:tokenId]) {
			return token;
		}
	}
	return nil;
}

- (UDToken *)makeTokenOnNode:(NSString *)nodeId
              arrivedViaFlow:(NSString *)flowId
                      parent:(UDToken *)parent
{
	self.tokenSerial += 1;
	UDToken *token = [[UDToken alloc] init];
	token.tokenId = [NSString stringWithFormat:@"t%lu",
		(unsigned long)self.tokenSerial];
	token.nodeId = nodeId;
	token.arrivedViaFlowId = flowId;
	token.state = UDTokenStateReady;
	if (parent != nil) {
		token.parentTokenId = parent.tokenId;
		token.forkId = parent.forkId;
		token.joinExpected = parent.joinExpected;
	}
	[self.tokens addObject:token];
	return token;
}

@end

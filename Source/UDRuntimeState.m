#import "UDRuntimeState.h"
#import "UDProcessDefinition.h"

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

- (NSDictionary *)stateDictionary
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	[dict setObject:self.tokenId forKey:@"id"];
	[dict setObject:self.nodeId forKey:@"node"];
	[dict setObject:[NSNumber numberWithInteger:self.state] forKey:@"state"];
	if (self.arrivedViaFlowId != nil) {
		[dict setObject:self.arrivedViaFlowId forKey:@"via"];
	}
	if (self.parentTokenId != nil) {
		[dict setObject:self.parentTokenId forKey:@"parent"];
	}
	if (self.forkId != nil) {
		[dict setObject:self.forkId forKey:@"fork"];
	}
	if (self.joinExpected != 0) {
		[dict setObject:[NSNumber numberWithUnsignedInteger:self.joinExpected]
		         forKey:@"join"];
	}
	if (self.dueAt != nil) {
		[dict setObject:self.dueAt forKey:@"due"];
	}
	return dict;
}

+ (instancetype)tokenWithStateDictionary:(NSDictionary *)dict
{
	NSString *tokenId = [dict objectForKey:@"id"];
	NSString *nodeId = [dict objectForKey:@"node"];
	if (![tokenId isKindOfClass:[NSString class]]
	    || ![nodeId isKindOfClass:[NSString class]]) {
		return nil;
	}
	UDToken *token = [[UDToken alloc] init];
	token.tokenId = tokenId;
	token.nodeId = nodeId;
	token.state = [[dict objectForKey:@"state"] integerValue];
	token.arrivedViaFlowId = [dict objectForKey:@"via"];
	token.parentTokenId = [dict objectForKey:@"parent"];
	token.forkId = [dict objectForKey:@"fork"];
	token.joinExpected = [[dict objectForKey:@"join"] unsignedIntegerValue];
	token.dueAt = [dict objectForKey:@"due"];
	return token;
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
	}
	return self;
}

- (UDProcessInstance *)rootInstance
{
	UDProcessInstance *root = self;
	while (root.parent != nil) {
		root = root.parent;
	}
	return root;
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

- (UDToken *)findTokenWithId:(NSString *)tokenId
                       scope:(UDProcessInstance **)scope
{
	UDToken *token = [self tokenWithId:tokenId];
	if (token != nil) {
		if (scope != NULL) {
			*scope = self;
		}
		return token;
	}
	for (UDProcessInstance *child in [self.children allValues]) {
		token = [child findTokenWithId:tokenId scope:scope];
		if (token != nil) {
			return token;
		}
	}
	return nil;
}

- (UDToken *)makeTokenOnNode:(NSString *)nodeId
              arrivedViaFlow:(NSString *)flowId
                      parent:(UDToken *)parent
{
	UDProcessInstance *root = [self rootInstance];
	root.tokenSerial += 1;
	UDToken *token = [[UDToken alloc] init];
	token.tokenId = [NSString stringWithFormat:@"t%lu",
		(unsigned long)root.tokenSerial];
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

- (void)pruneCompletedTokens
{
	NSIndexSet *done = [self.tokens indexesOfObjectsPassingTest:
		^BOOL(UDToken *token, NSUInteger idx, BOOL *stop) {
			(void)idx;
			(void)stop;
			return token.state == UDTokenStateCompleted;
		}];
	[self.tokens removeObjectsAtIndexes:done];
	for (UDProcessInstance *child in [self.children allValues]) {
		[child pruneCompletedTokens];
	}
}

- (NSDictionary *)stateDictionary
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	[dict setObject:self.instanceId forKey:@"id"];
	[dict setObject:[self.variables copy] forKey:@"variables"];
	[dict setObject:[self.correlationKeys copy] forKey:@"correlation"];
	[dict setObject:[self.forkExpected copy] forKey:@"forks"];
	[dict setObject:[NSNumber numberWithUnsignedInteger:self.tokenSerial]
	         forKey:@"serial"];
	[dict setObject:[NSNumber numberWithBool:self.completed] forKey:@"completed"];
	[dict setObject:[NSNumber numberWithBool:self.failed] forKey:@"failed"];
	if (self.hostTokenId != nil) {
		[dict setObject:self.hostTokenId forKey:@"host"];
	}
	if (self.error != nil) {
		NSMutableDictionary *err = [NSMutableDictionary dictionary];
		[err setObject:[self.error domain] forKey:@"domain"];
		[err setObject:[NSNumber numberWithInteger:[self.error code]] forKey:@"code"];
		[err setObject:[self.error localizedDescription] forKey:@"message"];
		NSString *ref = [[self.error userInfo] objectForKey:UDWorkflowErrorRefKey];
		if ([ref isKindOfClass:[NSString class]]) {
			[err setObject:ref forKey:@"ref"];
		}
		[dict setObject:err forKey:@"error"];
	}
	NSMutableArray *tokens = [NSMutableArray array];
	for (UDToken *token in self.tokens) {
		[tokens addObject:[token stateDictionary]];
	}
	[dict setObject:tokens forKey:@"tokens"];
	NSMutableDictionary *children = [NSMutableDictionary dictionary];
	for (NSString *hostId in self.children) {
		[children setObject:[[self.children objectForKey:hostId] stateDictionary]
		             forKey:hostId];
	}
	[dict setObject:children forKey:@"children"];
	return dict;
}

+ (NSError *)corruptStateError:(NSString *)detail
{
	return [NSError errorWithDomain:UDWorkflowErrorDomain
	                           code:UDWorkflowErrorInvalidState
	                       userInfo:@{ NSLocalizedDescriptionKey:
		[NSString stringWithFormat:@"stored instance state is unreadable: %@",
			detail] }];
}

+ (instancetype)instanceWithStateDictionary:(NSDictionary *)state
                                 definition:(UDProcessDefinition *)definition
                                      error:(NSError **)error
{
	if (![state isKindOfClass:[NSDictionary class]]
	    || ![[state objectForKey:@"id"] isKindOfClass:[NSString class]]) {
		if (error != NULL) {
			*error = [self corruptStateError:@"no instance id"];
		}
		return nil;
	}
	UDProcessInstance *instance = [[UDProcessInstance alloc] init];
	instance.instanceId = [state objectForKey:@"id"];
	instance.definition = definition;
	[instance.variables addEntriesFromDictionary:[state objectForKey:@"variables"]];
	[instance.correlationKeys addEntriesFromDictionary:[state objectForKey:@"correlation"]];
	[instance.forkExpected addEntriesFromDictionary:[state objectForKey:@"forks"]];
	instance.tokenSerial = [[state objectForKey:@"serial"] unsignedIntegerValue];
	instance.completed = [[state objectForKey:@"completed"] boolValue];
	instance.failed = [[state objectForKey:@"failed"] boolValue];
	instance.hostTokenId = [state objectForKey:@"host"];
	NSDictionary *err = [state objectForKey:@"error"];
	if ([err isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		if ([err objectForKey:@"message"] != nil) {
			[info setObject:[err objectForKey:@"message"]
			         forKey:NSLocalizedDescriptionKey];
		}
		if ([err objectForKey:@"ref"] != nil) {
			[info setObject:[err objectForKey:@"ref"] forKey:UDWorkflowErrorRefKey];
		}
		instance.error = [NSError errorWithDomain:[err objectForKey:@"domain"]
		                                     code:[[err objectForKey:@"code"] integerValue]
		                                 userInfo:info];
	}
	for (NSDictionary *saved in [state objectForKey:@"tokens"]) {
		UDToken *token = [UDToken tokenWithStateDictionary:saved];
		if (token == nil) {
			if (error != NULL) {
				*error = [self corruptStateError:@"bad token"];
			}
			return nil;
		}
		[instance.tokens addObject:token];
	}
	NSDictionary *children = [state objectForKey:@"children"];
	for (NSString *hostId in children) {
		UDToken *host = [instance tokenWithId:hostId];
		id node = [definition nodeWithId:host.nodeId];
		if (![node isKindOfClass:[UDSubProcess class]]) {
			if (error != NULL) {
				*error = [self corruptStateError:
					[NSString stringWithFormat:@"no subprocess hosts %@", hostId]];
			}
			return nil;
		}
		UDProcessInstance *child = [self instanceWithStateDictionary:
				[children objectForKey:hostId]
			definition:[(UDSubProcess *)node innerDefinition]
			error:error];
		if (child == nil) {
			return nil;
		}
		child.parent = instance;
		[instance.children setObject:child forKey:hostId];
	}
	return instance;
}

@end

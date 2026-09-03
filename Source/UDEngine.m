#import "UDEngine.h"
#import "UDFlowElements.h"
#import "UDCondition.h"
#import "UDMemoryStore.h"
#import <dispatch/dispatch.h>

@interface UDEngine ()
@property (nonatomic, strong) NSMutableSet *inflight;
@property (nonatomic, strong) NSMutableDictionary *timers;
- (void)serviceInvocation:(UDServiceInvocation *)invocation
                didFinish:(UDServiceResult *)result;
@end

@implementation UDEngine

- (instancetype)init
{
	self = [super init];
	if (self) {
		_workerQueue = dispatch_get_global_queue(
			DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
		_inflight = [NSMutableSet set];
		_timers = [NSMutableDictionary dictionary];
	}
	return self;
}

- (void)logInstance:(UDProcessInstance *)instance format:(NSString *)format, ...
{
	id<UDEngineDelegate> delegate = self.delegate;
	if (delegate == nil
	    || ![delegate respondsToSelector:@selector(engine:instance:didTrace:)]) {
		return;
	}
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[delegate engine:self instance:instance didTrace:message];
}

- (void)notifyFinished:(UDProcessInstance *)instance
{
	id<UDEngineDelegate> delegate = self.delegate;
	if (delegate == nil
	    || ![delegate respondsToSelector:@selector(engine:instanceDidFinish:error:)]) {
		return;
	}
	[delegate engine:self instanceDidFinish:instance error:instance.error];
}

- (void)notifyPaused:(UDProcessInstance *)instance
{
	id<UDEngineDelegate> delegate = self.delegate;
	if (delegate == nil
	    || ![delegate respondsToSelector:@selector(engine:instanceDidPause:)]) {
		return;
	}
	[delegate engine:self instanceDidPause:instance];
}

- (void)persist:(UDProcessInstance *)instance
{
	if (self.store == nil) {
		return;
	}
	[self.store saveInstance:instance error:NULL];
}

- (void)failInstance:(UDProcessInstance *)instance error:(NSError *)error
{
	instance.failed = YES;
	instance.error = error;
	[self logInstance:instance format:@"failed: %@",
		[error localizedDescription]];
	[self persist:instance];
	[self signalQuiesce:instance];
	[self notifyFinished:instance];
	[self finishHostIfNeeded:instance];
}

- (BOOL)isExternallyWaiting:(UDProcessInstance *)instance
{
	BOOL anyWait = NO;
	for (UDToken *token in instance.tokens) {
		if (token.state == UDTokenStateReady) {
			return NO;
		}
		if (token.state == UDTokenStateWaiting) {
			UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
			if ([node isKindOfClass:[UDTask class]]
			    && [(UDTask *)node kind] == UDTaskKindUser) {
				anyWait = YES;
				continue;
			}
			if ([node isKindOfClass:[UDGateway class]]) {
				anyWait = YES;
				continue;
			}
			return NO;
		}
	}
	return anyWait || instance.pendingServices == 0;
}

- (void)signalQuiesce:(UDProcessInstance *)instance
{
	if (instance.isCompleted || instance.isFailed
	    || (instance.pendingServices == 0
	        && instance.pendingTimers == 0
	        && [instance nextReadyToken] == nil)) {
		dispatch_semaphore_signal(instance.quiesce);
	}
}

- (void)checkCompletion:(UDProcessInstance *)instance
{
	if (instance.isFailed || instance.isCompleted) {
		[self signalQuiesce:instance];
		return;
	}
	for (UDToken *token in instance.tokens) {
		if (token.state == UDTokenStateReady
		    || token.state == UDTokenStateWaiting) {
			[self signalQuiesce:instance];
			return;
		}
	}
	instance.completed = YES;
	[self logInstance:instance format:@"instance completed"];
	[self persist:instance];
	[self signalQuiesce:instance];
	[self notifyFinished:instance];
	[self finishHostIfNeeded:instance];
}

- (NSArray<UDSequenceFlow *> *)orderedOutgoing:(UDProcessDefinition *)def
                                        fromId:(NSString *)nodeId
{
	NSMutableArray *flows = [NSMutableArray array];
	NSArray *outgoing = [def outgoingFlowsFrom:nodeId];
	for (NSString *flowId in def.flowOrder) {
		for (UDSequenceFlow *flow in outgoing) {
			if ([flow.elementId isEqualToString:flowId]) {
				[flows addObject:flow];
			}
		}
	}
	if ([flows count] == 0) {
		return outgoing;
	}
	return flows;
}

- (UDSequenceFlow *)chooseExclusiveFlow:(UDGateway *)gateway
                               instance:(UDProcessInstance *)instance
                                  error:(NSError **)error
{
	UDSequenceFlow *fallback = nil;
	NSArray *outgoing = [self orderedOutgoing:instance.definition
	                                   fromId:gateway.elementId];

	for (UDSequenceFlow *flow in outgoing) {
		if (flow.isDefaultFlow
		    || [flow.elementId isEqualToString:gateway.defaultFlowId]) {
			fallback = flow;
			continue;
		}
		id cond = flow.condition;
		if (cond == nil) {
			return flow;
		}
		if (![cond conformsToProtocol:@protocol(UDCondition)]) {
			if (error != NULL) {
				*error = [NSError errorWithDomain:UDWorkflowErrorDomain
				                             code:UDWorkflowErrorCondition
				                         userInfo:@{ NSLocalizedDescriptionKey:
					@"flow condition is not UDCondition" }];
			}
			return nil;
		}
		NSError *condError = nil;
		BOOL ok = [cond evaluateWithVariables:instance.variables
		                                error:&condError];
		if (condError != nil) {
			if (error != NULL) {
				*error = condError;
			}
			return nil;
		}
		if (ok) {
			return flow;
		}
	}
	if (fallback != nil) {
		return fallback;
	}
	if (error != NULL) {
		*error = [NSError errorWithDomain:UDWorkflowErrorDomain
		                             code:UDWorkflowErrorNoPath
		                         userInfo:@{ NSLocalizedDescriptionKey:
			[NSString stringWithFormat:
				@"exclusive gateway %@ matched no outgoing flow",
				gateway.elementId] }];
	}
	return nil;
}

- (void)advanceToken:(UDToken *)token
            instance:(UDProcessInstance *)instance
              along:(UDSequenceFlow *)flow
{
	token.state = UDTokenStateCompleted;
	UDToken *child = [instance makeTokenOnNode:flow.targetId
	                            arrivedViaFlow:flow.elementId
	                                    parent:token];
	[self logInstance:instance format:@"%@ --%@--> %@",
		token.nodeId, flow.elementId, child.nodeId];
}

- (void)advanceToken:(UDToken *)token
            instance:(UDProcessInstance *)instance
             alongAll:(NSArray<UDSequenceFlow *> *)flows
               forkId:(NSString *)forkId
{
	token.state = UDTokenStateCompleted;
	NSUInteger i = 0;
	for (UDSequenceFlow *flow in flows) {
		UDToken *child = [instance makeTokenOnNode:flow.targetId
		                            arrivedViaFlow:flow.elementId
		                                    parent:token];
		if (forkId != nil) {
			child.forkId = forkId;
		}
		[self logInstance:instance format:@"%@ --%@--> %@ (branch %lu)",
			token.nodeId, flow.elementId, child.nodeId,
			(unsigned long)i];
		i += 1;
	}
}

- (BOOL)joinParallel:(UDGateway *)gateway
               token:(UDToken *)token
            instance:(UDProcessInstance *)instance
{
	token.state = UDTokenStateWaiting;

	NSArray *incoming = [instance.definition incomingFlowsTo:gateway.elementId];
	NSMutableSet *needed = [NSMutableSet set];
	for (UDSequenceFlow *flow in incoming) {
		[needed addObject:flow.elementId];
	}

	NSMutableSet *arrived = [NSMutableSet set];
	NSMutableArray *cohort = [NSMutableArray array];
	for (UDToken *candidate in instance.tokens) {
		if (![candidate.nodeId isEqualToString:gateway.elementId]) {
			continue;
		}
		if (candidate.state != UDTokenStateWaiting
		    && candidate.state != UDTokenStateReady) {
			continue;
		}
		if (token.forkId != nil || candidate.forkId != nil) {
			if (token.forkId == nil
			    || candidate.forkId == nil
			    || ![candidate.forkId isEqualToString:token.forkId]) {
				continue;
			}
		}
		if (candidate.arrivedViaFlowId != nil) {
			[arrived addObject:candidate.arrivedViaFlowId];
		}
		[cohort addObject:candidate];
	}

	if ([arrived count] < [needed count]) {
		[self logInstance:instance format:@"join %@ waiting %lu/%lu",
			gateway.elementId,
			(unsigned long)[arrived count],
			(unsigned long)[needed count]];
		return NO;
	}

	for (UDToken *member in cohort) {
		member.state = UDTokenStateCompleted;
	}

	NSArray *outgoing = [instance.definition outgoingFlowsFrom:gateway.elementId];
	UDToken *seed = token;
	seed.state = UDTokenStateCompleted;
	if ([outgoing count] == 0) {
		return YES;
	}
	if ([outgoing count] == 1) {
		UDSequenceFlow *flow = [outgoing objectAtIndex:0];
		UDToken *child = [instance makeTokenOnNode:flow.targetId
		                            arrivedViaFlow:flow.elementId
		                                    parent:seed];
		child.forkId = nil;
		[self logInstance:instance format:@"join %@ --%@--> %@",
			gateway.elementId, flow.elementId, child.nodeId];
		return YES;
	}

	NSString *newFork = [NSString stringWithFormat:@"fork-%@", seed.tokenId];
	[self advanceToken:seed instance:instance alongAll:outgoing forkId:newFork];
	return YES;
}

- (NSArray *)chooseInclusiveFlows:(UDGateway *)gateway
                         instance:(UDProcessInstance *)instance
                            error:(NSError **)error
{
	NSMutableArray *taken = [NSMutableArray array];
	UDSequenceFlow *fallback = nil;
	NSArray *outgoing = [self orderedOutgoing:instance.definition
	                                   fromId:gateway.elementId];
	for (UDSequenceFlow *flow in outgoing) {
		if (flow.isDefaultFlow
		    || [flow.elementId isEqualToString:gateway.defaultFlowId]) {
			fallback = flow;
			continue;
		}
		id cond = flow.condition;
		if (cond == nil) {
			[taken addObject:flow];
			continue;
		}
		if (![cond conformsToProtocol:@protocol(UDCondition)]) {
			if (error != NULL) {
				*error = [NSError errorWithDomain:UDWorkflowErrorDomain
				                             code:UDWorkflowErrorCondition
				                         userInfo:@{ NSLocalizedDescriptionKey:
						@"inclusive condition is not UDCondition" }];
			}
			return nil;
		}
		NSError *condError = nil;
		if ([cond evaluateWithVariables:instance.variables error:&condError]) {
			[taken addObject:flow];
		} else if (condError != nil) {
			if (error != NULL) {
				*error = condError;
			}
			return nil;
		}
	}
	if ([taken count] == 0) {
		if (fallback != nil) {
			[taken addObject:fallback];
		} else {
			if (error != NULL) {
				*error = [NSError errorWithDomain:UDWorkflowErrorDomain
				                             code:UDWorkflowErrorNoPath
				                         userInfo:@{ NSLocalizedDescriptionKey:
						@"inclusive gateway matched no flow" }];
			}
			return nil;
		}
	}
	return taken;
}

- (BOOL)joinInclusive:(UDGateway *)gateway
                token:(UDToken *)token
             instance:(UDProcessInstance *)instance
{
	token.state = UDTokenStateWaiting;
	NSUInteger expected = token.joinExpected;
	NSNumber *stored = nil;
	if (token.forkId != nil) {
		stored = [instance.forkExpected objectForKey:token.forkId];
	}
	if (stored != nil) {
		expected = [stored unsignedIntegerValue];
	}
	if (expected == 0) {
		expected = [[instance.definition incomingFlowsTo:gateway.elementId] count];
	}

	NSMutableArray *cohort = [NSMutableArray array];
	for (UDToken *candidate in instance.tokens) {
		if (![candidate.nodeId isEqualToString:gateway.elementId]) {
			continue;
		}
		if (candidate.state != UDTokenStateWaiting
		    && candidate.state != UDTokenStateReady) {
			continue;
		}
		if (token.forkId != nil && candidate.forkId != nil
		    && ![candidate.forkId isEqualToString:token.forkId]) {
			continue;
		}
		[cohort addObject:candidate];
	}

	if ([cohort count] < expected) {
		[self logInstance:instance format:@"inclusive join %@ waiting %lu/%lu",
			gateway.elementId,
			(unsigned long)[cohort count],
			(unsigned long)expected];
		return YES;
	}

	for (UDToken *member in cohort) {
		member.state = UDTokenStateCompleted;
	}
	NSArray *outgoing = [instance.definition outgoingFlowsFrom:gateway.elementId];
	if ([outgoing count] == 0) {
		return YES;
	}
	UDSequenceFlow *flow = [outgoing objectAtIndex:0];
	UDToken *child = [instance makeTokenOnNode:flow.targetId
	                            arrivedViaFlow:flow.elementId
	                                    parent:token];
	child.forkId = nil;
	child.joinExpected = 0;
	[self logInstance:instance format:@"inclusive join %@ --%@--> %@",
		gateway.elementId, flow.elementId, child.nodeId];
	return YES;
}

- (BOOL)fireEventBased:(UDGateway *)gateway
                 token:(UDToken *)token
              instance:(UDProcessInstance *)instance
                 error:(NSError **)error
{
	NSArray *outgoing = [instance.definition outgoingFlowsFrom:gateway.elementId];
	if ([outgoing count] == 0) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorNoPath
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"event-based gateway has no outgoing flow" }];
		}
		return NO;
	}
	NSString *forkId = [NSString stringWithFormat:@"egw-%@", token.tokenId];
	token.forkId = forkId;
	[self advanceToken:token instance:instance alongAll:outgoing forkId:forkId];
	return YES;
}

- (void)cancelEventGatewaySiblings:(UDToken *)winner instance:(UDProcessInstance *)instance
{
	if (winner.forkId == nil
	    || ![winner.forkId hasPrefix:@"egw-"]) {
		return;
	}
	for (UDToken *token in instance.tokens) {
		if (token == winner) {
			continue;
		}
		if (token.forkId == nil
		    || ![token.forkId isEqualToString:winner.forkId]) {
			continue;
		}
		if (token.state == UDTokenStateCompleted) {
			continue;
		}
		[self cancelTimerForToken:token.tokenId instance:instance];
		token.state = UDTokenStateCompleted;
		[self logInstance:instance format:@"event-gw cancel %@", token.nodeId];
	}
}

- (BOOL)fireGateway:(UDGateway *)gateway
              token:(UDToken *)token
           instance:(UDProcessInstance *)instance
              error:(NSError **)error
{
	NSArray *incoming = [instance.definition incomingFlowsTo:gateway.elementId];
	NSArray *outgoing = [instance.definition outgoingFlowsFrom:gateway.elementId];

	if (gateway.kind == UDGatewayKindEventBased) {
		return [self fireEventBased:gateway
		                       token:token
		                    instance:instance
		                       error:error];
	}

	if (gateway.kind == UDGatewayKindInclusive) {
		if ([incoming count] > 1 && [outgoing count] <= 1) {
			return [self joinInclusive:gateway token:token instance:instance];
		}
		NSArray *chosen = [self chooseInclusiveFlows:gateway
		                                    instance:instance
		                                       error:error];
		if (chosen == nil) {
			return NO;
		}
		if ([chosen count] == 1) {
			[self advanceToken:token instance:instance along:[chosen objectAtIndex:0]];
			return YES;
		}
		NSString *forkId = [NSString stringWithFormat:@"or-%@", token.tokenId];
		[instance.forkExpected setObject:[NSNumber numberWithUnsignedInteger:[chosen count]]
		                          forKey:forkId];
		token.forkId = forkId;
		token.joinExpected = [chosen count];
		[self advanceToken:token instance:instance alongAll:chosen forkId:forkId];
		return YES;
	}

	if (gateway.kind == UDGatewayKindExclusive) {
		if ([outgoing count] <= 1) {
			if ([outgoing count] == 1) {
				[self advanceToken:token
				          instance:instance
				             along:[outgoing objectAtIndex:0]];
			} else {
				token.state = UDTokenStateCompleted;
			}
			return YES;
		}
		UDSequenceFlow *chosen = [self chooseExclusiveFlow:gateway
		                                          instance:instance
		                                             error:error];
		if (chosen == nil) {
			return NO;
		}
		[self advanceToken:token instance:instance along:chosen];
		return YES;
	}

	/* Parallel */
	if ([incoming count] > 1) {
		return [self joinParallel:gateway token:token instance:instance];
	}
	if ([outgoing count] > 1) {
		NSString *forkId = [NSString stringWithFormat:@"fork-%@", token.tokenId];
		token.forkId = forkId;
		[self advanceToken:token
		          instance:instance
		          alongAll:outgoing
		            forkId:forkId];
		return YES;
	}
	if ([outgoing count] == 1) {
		[self advanceToken:token
		          instance:instance
		             along:[outgoing objectAtIndex:0]];
	} else {
		token.state = UDTokenStateCompleted;
	}
	return YES;
}

- (void)cancelTimerForToken:(NSString *)tokenId instance:(UDProcessInstance *)instance
{
	dispatch_source_t source = [self.timers objectForKey:tokenId];
	if (source != nil) {
		dispatch_source_cancel(source);
		[self.timers removeObjectForKey:tokenId];
		if (instance.pendingTimers > 0) {
			instance.pendingTimers -= 1;
		}
	}
}

- (void)leaveEvent:(UDEvent *)event
             token:(UDToken *)token
          instance:(UDProcessInstance *)instance
           payload:(NSDictionary *)payload
{
	[self cancelTimerForToken:token.tokenId instance:instance];
	[self cancelEventGatewaySiblings:token instance:instance];
	if (payload != nil) {
		[instance.variables addEntriesFromDictionary:payload];
	}
	NSArray *outgoing = [instance.definition outgoingFlowsFrom:event.elementId];
	if ([outgoing count] == 0) {
		token.state = UDTokenStateCompleted;
		if (event.kind == UDEventKindEnd) {
			[self logInstance:instance format:@"end %@", event.elementId];
		}
		return;
	}
	[self advanceToken:token instance:instance along:[outgoing objectAtIndex:0]];
}

- (void)throwMessage:(UDEvent *)event instance:(UDProcessInstance *)instance
{
	id<UDEngineDelegate> delegate = self.delegate;
	if (delegate != nil
	    && [delegate respondsToSelector:@selector(engine:instance:didThrowMessage:payload:)]) {
		[delegate engine:self
		         instance:instance
		  didThrowMessage:event.messageName
		          payload:[instance.variables copy]];
	}
	[self logInstance:instance format:@"throw message %@", event.messageName];
}

- (void)disarmBoundariesOn:(NSString *)taskId instance:(UDProcessInstance *)instance
{
	NSArray *boundaries = [instance.definition boundaryEventsAttachedTo:taskId];
	for (UDEvent *event in boundaries) {
		for (UDToken *token in [instance tokensAtNode:event.elementId
		                                       state:UDTokenStateWaiting]) {
			[self cancelTimerForToken:token.tokenId instance:instance];
			token.state = UDTokenStateCompleted;
		}
	}
}

- (void)timerFiredForToken:(NSString *)tokenId
                  instance:(UDProcessInstance *)instance
{
	UDToken *token = [instance tokenWithId:tokenId];
	UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
	if (token == nil || token.state != UDTokenStateWaiting
	    || ![node isKindOfClass:[UDEvent class]]) {
		[self signalQuiesce:instance];
		return;
	}
	UDEvent *event = (UDEvent *)node;
	[self logInstance:instance format:@"timer %@", event.elementId];
	if (event.kind == UDEventKindBoundary && event.isInterrupting
	    && event.attachedToId != nil) {
		for (UDToken *activity in [instance tokensAtNode:event.attachedToId
		                                          state:UDTokenStateWaiting]) {
			activity.state = UDTokenStateCompleted;
		}
		for (UDToken *activity in [instance tokensAtNode:event.attachedToId
		                                          state:UDTokenStateReady]) {
			activity.state = UDTokenStateCompleted;
		}
		[self disarmBoundariesOn:event.attachedToId instance:instance];
	}
	[self leaveEvent:event token:token instance:instance payload:nil];
	[self persist:instance];
	[self drainInstance:instance];
}

- (void)scheduleTimer:(UDEvent *)event
                token:(UDToken *)token
             instance:(UDProcessInstance *)instance
{
	token.state = UDTokenStateWaiting;
	instance.pendingTimers += 1;
	NSTimeInterval duration = event.timerDuration;
	if (duration < 0) {
		duration = 0;
	}
	int64_t nsec = (int64_t)(duration * (NSTimeInterval)NSEC_PER_SEC);
	dispatch_source_t source = dispatch_source_create(
		DISPATCH_SOURCE_TYPE_TIMER, 0, 0, instance.queue);
	dispatch_source_set_timer(source,
		dispatch_time(DISPATCH_TIME_NOW, nsec),
		DISPATCH_TIME_FOREVER,
		0);
	NSString *tokenId = token.tokenId;
	dispatch_source_set_event_handler(source, ^{
		[self cancelTimerForToken:tokenId instance:instance];
		[self timerFiredForToken:tokenId instance:instance];
	});
	[self.timers setObject:source forKey:token.tokenId];
	dispatch_resume(source);
	[self logInstance:instance format:@"timer %@ in %.3fs",
		event.elementId, duration];
}

- (void)armBoundariesForTask:(UDTask *)task
                       token:(UDToken *)activity
                    instance:(UDProcessInstance *)instance
{
	NSArray *boundaries = [instance.definition boundaryEventsAttachedTo:task.elementId];
	for (UDEvent *event in boundaries) {
		UDToken *armed = [instance makeTokenOnNode:event.elementId
		                            arrivedViaFlow:nil
		                                    parent:activity];
		armed.forkId = activity.forkId;
		if (event.trigger == UDEventTriggerTimer) {
			[self scheduleTimer:event token:armed instance:instance];
		} else {
			armed.state = UDTokenStateWaiting;
			[self logInstance:instance format:@"boundary %@ waiting message %@",
				event.elementId, event.messageName];
		}
	}
}

- (BOOL)fireEvent:(UDEvent *)event
            token:(UDToken *)token
         instance:(UDProcessInstance *)instance
            error:(NSError **)error
{
	if (event.kind == UDEventKindBoundary) {
		/* Armed explicitly; a Ready boundary token is a resume re-arm. */
		if (event.trigger == UDEventTriggerTimer) {
			[self scheduleTimer:event token:token instance:instance];
			return YES;
		}
		token.state = UDTokenStateWaiting;
		return YES;
	}

	if (event.trigger == UDEventTriggerTimer
	    && (event.kind == UDEventKindStart
	        || event.kind == UDEventKindIntermediateCatch)) {
		[self scheduleTimer:event token:token instance:instance];
		return YES;
	}

	if (event.trigger == UDEventTriggerMessage
	    && (event.kind == UDEventKindStart
	        || event.kind == UDEventKindIntermediateCatch)) {
		token.state = UDTokenStateWaiting;
		[self logInstance:instance format:@"catch message %@ on %@",
			event.messageName, event.elementId];
		return YES;
	}

	if (event.trigger == UDEventTriggerMessage
	    && (event.kind == UDEventKindIntermediateThrow
	        || event.kind == UDEventKindEnd)) {
		[self throwMessage:event instance:instance];
		[self leaveEvent:event token:token instance:instance payload:nil];
		return YES;
	}

	if (event.kind == UDEventKindStart
	    || event.kind == UDEventKindIntermediateCatch
	    || event.kind == UDEventKindIntermediateThrow) {
		NSArray *outgoing =
			[instance.definition outgoingFlowsFrom:event.elementId];
		if ([outgoing count] == 0) {
			if (error != NULL) {
				*error = [NSError errorWithDomain:UDWorkflowErrorDomain
				                             code:UDWorkflowErrorNoPath
				                         userInfo:@{ NSLocalizedDescriptionKey:
					@"event has no outgoing flow" }];
			}
			return NO;
		}
		[self advanceToken:token
		          instance:instance
		             along:[outgoing objectAtIndex:0]];
		return YES;
	}

	token.state = UDTokenStateCompleted;
	[self logInstance:instance format:@"end %@", event.elementId];
	return YES;
}

- (void)applyServiceResult:(UDServiceResult *)result
                     token:(UDToken *)token
                      task:(UDTask *)task
                  instance:(UDProcessInstance *)instance
{
	if (instance.pendingServices > 0) {
		instance.pendingServices -= 1;
	}
	if (result.error != nil) {
		NSString *ref = [[result.error userInfo] objectForKey:UDWorkflowErrorRefKey];
		if ([self takeErrorBoundary:ref
		                      task:task
		                     token:token
		                  instance:instance]) {
			[self persist:instance];
			[self drainInstance:instance];
			return;
		}
		[self failInstance:instance error:result.error];
		return;
	}
	if (result.variables != nil) {
		[instance.variables addEntriesFromDictionary:result.variables];
	}
	[self disarmBoundariesOn:task.elementId instance:instance];
	NSArray *outgoing = [instance.definition outgoingFlowsFrom:task.elementId];
	if ([outgoing count] == 0) {
		token.state = UDTokenStateCompleted;
	} else {
		[self advanceToken:token
		          instance:instance
		             along:[outgoing objectAtIndex:0]];
	}
	[self persist:instance];
	[self drainInstance:instance];
}

- (void)serviceInvocation:(UDServiceInvocation *)invocation
                didFinish:(UDServiceResult *)result
{
	UDProcessInstance *instance = invocation.instance;
	if (instance == nil) {
		return;
	}
	dispatch_async(instance.queue, ^{
		[self.inflight removeObject:invocation];
		UDToken *token = [instance tokenWithId:invocation.tokenId];
		UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
		if (token == nil || ![node isKindOfClass:[UDTask class]]) {
			NSError *error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                                     code:UDWorkflowErrorInvalidState
			                                 userInfo:@{ NSLocalizedDescriptionKey:
					@"service finished for a missing token" }];
			[self failInstance:instance error:error];
			return;
		}
		[self applyServiceResult:result
		                   token:token
		                    task:(UDTask *)node
		                instance:instance];
	});
}

- (void)runServiceAction:(UDTask *)task
                   token:(UDToken *)token
                instance:(UDProcessInstance *)instance
{
	token.state = UDTokenStateWaiting;
	instance.pendingServices += 1;

	UDServiceInvocation *invocation =
		[[UDServiceInvocation alloc] initWithActionKey:task.actionKey
		                                     variables:[instance.variables copy]
		                                       tokenId:token.tokenId
		                                      instance:instance];
	invocation.target = self;
	invocation.action = @selector(serviceInvocation:didFinish:);
	[self.inflight addObject:invocation];

	if (self.serviceHandler == nil) {
		[self logInstance:instance format:@"%@ no-op action %@",
			task.elementId, task.actionKey];
		[invocation finishWithVariables:nil error:nil];
		return;
	}

	id<UDServiceTaskHandler> handler = self.serviceHandler;
	dispatch_async(self.workerQueue, ^{
		[handler performInvocation:invocation];
	});
}

- (BOOL)fireTask:(UDTask *)task
           token:(UDToken *)token
        instance:(UDProcessInstance *)instance
           error:(NSError **)error
{
	[self armBoundariesForTask:task token:token instance:instance];
	if (task.kind == UDTaskKindUser) {
		token.state = UDTokenStateWaiting;
		[self logInstance:instance format:@"user task %@ assignee=%@",
			task.elementId, task.assignee];
		if (self.userTaskPort != nil) {
			[self.userTaskPort publishWorkItemForToken:token
			                                  instance:instance
			                                      task:task];
		}
		return YES;
	}

	[self logInstance:instance format:@"%@ action %@",
		task.elementId, task.actionKey];
	[self runServiceAction:task token:token instance:instance];
	return YES;
}

- (UDEvent *)errorBoundaryOnTask:(NSString *)taskId
                        errorRef:(NSString *)errorRef
                        instance:(UDProcessInstance *)instance
{
	for (UDEvent *event in [instance.definition boundaryEventsAttachedTo:taskId]) {
		if (event.trigger != UDEventTriggerError) {
			continue;
		}
		if (event.errorRef == nil || [event.errorRef length] == 0
		    || [event.errorRef isEqualToString:@"*"]
		    || (errorRef != nil && [event.errorRef isEqualToString:errorRef])) {
			return event;
		}
	}
	return nil;
}

- (BOOL)takeErrorBoundary:(NSString *)errorRef
                     task:(UDTask *)task
                    token:(UDToken *)token
                 instance:(UDProcessInstance *)instance
{
	UDEvent *boundary = [self errorBoundaryOnTask:task.elementId
	                                     errorRef:errorRef
	                                     instance:instance];
	if (boundary == nil) {
		return NO;
	}
	token.state = UDTokenStateCompleted;
	[self disarmBoundariesOn:task.elementId instance:instance];
	UDToken *armed = nil;
	NSArray *waiting = [instance tokensAtNode:boundary.elementId
	                                    state:UDTokenStateWaiting];
	if ([waiting count] > 0) {
		armed = [waiting objectAtIndex:0];
	} else {
		armed = [instance makeTokenOnNode:boundary.elementId
		                   arrivedViaFlow:nil
		                           parent:token];
	}
	[self logInstance:instance format:@"error %@ on %@",
		errorRef ?: @"*", task.elementId];
	[self leaveEvent:boundary token:armed instance:instance
	             payload:errorRef ? @{ @"errorRef": errorRef } : nil];
	return YES;
}

- (void)finishHostIfNeeded:(UDProcessInstance *)child
{
	UDProcessInstance *parent = child.parent;
	if (parent == nil || child.hostTokenId == nil) {
		return;
	}
	dispatch_async(parent.queue, ^{
		if (parent.pendingServices > 0) {
			parent.pendingServices -= 1;
		}
		UDToken *host = [parent tokenWithId:child.hostTokenId];
		if (host == nil) {
			[self signalQuiesce:parent];
			return;
		}
		if (child.isFailed) {
			[self failInstance:parent error:child.error];
			return;
		}
		[parent.variables addEntriesFromDictionary:child.variables];
		UDFlowNode *node = [parent.definition nodeWithId:host.nodeId];
		NSArray *outgoing =
			[parent.definition outgoingFlowsFrom:host.nodeId];
		if ([outgoing count] == 0) {
			host.state = UDTokenStateCompleted;
		} else {
			[self advanceToken:host instance:parent along:[outgoing objectAtIndex:0]];
		}
		(void)node;
		[self persist:parent];
		[self drainInstance:parent];
	});
}

- (BOOL)fireSubProcess:(UDSubProcess *)node
                 token:(UDToken *)token
              instance:(UDProcessInstance *)instance
                 error:(NSError **)error
{
	if (node.innerDefinition == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidDefinition
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"subprocess has no inner definition" }];
		}
		return NO;
	}
	token.state = UDTokenStateWaiting;
	instance.pendingServices += 1;
	NSError *childError = nil;
	UDProcessInstance *child = [self prepareInstance:node.innerDefinition]
	                                       variables:instance.variables
	                                           error:&childError];
	if (child == nil) {
		if (error != NULL) {
			*error = childError;
		}
		return NO;
	}
	child.parent = instance;
	child.hostTokenId = token.tokenId;
	child.queue = instance.queue;
	[self logInstance:instance format:@"enter subprocess %@", node.elementId];
	[self drainInstance:child];
	return YES;
}

- (BOOL)fireToken:(UDToken *)token
         instance:(UDProcessInstance *)instance
            error:(NSError **)error
{
	UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
	if (node == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorUnknownElement
			                         userInfo:@{ NSLocalizedDescriptionKey:
				[NSString stringWithFormat:@"unknown node %@", token.nodeId] }];
		}
		return NO;
	}

	if ([node isKindOfClass:[UDEvent class]]) {
		return [self fireEvent:(UDEvent *)node
		                 token:token
		              instance:instance
		                 error:error];
	}
	if ([node isKindOfClass:[UDTask class]]) {
		return [self fireTask:(UDTask *)node
		                token:token
		             instance:instance
		                error:error];
	}
	if ([node isKindOfClass:[UDGateway class]]) {
		return [self fireGateway:(UDGateway *)node
		                   token:token
		                instance:instance
		                   error:error];
	}
	if ([node isKindOfClass:[UDSubProcess class]]) {
		return [self fireSubProcess:(UDSubProcess *)node
		                      token:token
		                   instance:instance
		                      error:error];
	}

	if (error != NULL) {
		*error = [NSError errorWithDomain:UDWorkflowErrorDomain
		                             code:UDWorkflowErrorUnknownElement
		                         userInfo:@{ NSLocalizedDescriptionKey:
				@"unsupported flow node" }];
	}
	return NO;
}

- (void)drainInstance:(UDProcessInstance *)instance
{
	if (instance.isFailed || instance.isCompleted) {
		return;
	}

	UDToken *token = nil;
	while ((token = [instance nextReadyToken]) != nil) {
		NSError *error = nil;
		BOOL ok = [self fireToken:token instance:instance error:&error];
		if (!ok) {
			[self failInstance:instance error:error];
			return;
		}
		[self persist:instance];
	}
	[self checkCompletion:instance];
	if (!instance.isCompleted && !instance.isFailed
	    && instance.pendingServices == 0
	    && instance.pendingTimers == 0
	    && [instance nextReadyToken] == nil) {
		[self notifyPaused:instance];
	}
}

- (UDProcessInstance *)prepareInstance:(UDProcessDefinition *)definition
                             variables:(NSDictionary *)variables
                                 error:(NSError **)error
{
	UDEvent *start = [definition startEvent];
	if (start == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidDefinition
			                         userInfo:@{ NSLocalizedDescriptionKey:
				@"definition has no start event" }];
		}
		return nil;
	}

	UDProcessInstance *instance = [[UDProcessInstance alloc] init];
	instance.instanceId = [[NSUUID UUID] UUIDString];
	instance.definition = definition;
	if (variables != nil) {
		[instance.variables addEntriesFromDictionary:variables];
	}
	instance.queue = dispatch_queue_create(
		[[NSString stringWithFormat:@"ud.workflow.%@", instance.instanceId]
			UTF8String],
		DISPATCH_QUEUE_SERIAL);
	[instance makeTokenOnNode:start.elementId arrivedViaFlow:nil parent:nil];
	[self logInstance:instance format:@"start %@ v%ld",
		definition.processId, (long)definition.version];
	[self persist:instance];
	return instance;
}

- (UDProcessInstance *)enqueueProcess:(UDProcessDefinition *)definition
                            variables:(NSDictionary *)variables
                                error:(NSError **)error
{
	UDProcessInstance *instance = [self prepareInstance:definition
	                                          variables:variables
	                                              error:error];
	if (instance == nil) {
		return nil;
	}
	dispatch_async(instance.queue, ^{
		[self drainInstance:instance];
	});
	return instance;
}

- (void)waitUntilQuiet:(UDProcessInstance *)instance
{
	for (;;) {
		dispatch_semaphore_wait(instance.quiesce, DISPATCH_TIME_FOREVER);
		if (instance.isCompleted || instance.isFailed) {
			break;
		}
		if (instance.pendingServices == 0
		    && instance.pendingTimers == 0
		    && [instance nextReadyToken] == nil) {
			break;
		}
	}
}

- (UDProcessInstance *)startProcess:(UDProcessDefinition *)definition
                          variables:(NSDictionary *)variables
                              error:(NSError **)error
{
	UDProcessInstance *instance = [self enqueueProcess:definition
	                                         variables:variables
	                                             error:error];
	if (instance == nil) {
		return nil;
	}
	[self waitUntilQuiet:instance];
	if (instance.isFailed && error != NULL) {
		*error = instance.error;
	}
	return instance;
}

- (BOOL)resumeInstance:(UDProcessInstance *)instance error:(NSError **)error
{
	if (instance == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidState
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"no instance to resume" }];
		}
		return NO;
	}
	if (instance.queue == nil) {
		instance.queue = dispatch_queue_create(
			[[NSString stringWithFormat:@"ud.workflow.%@", instance.instanceId]
				UTF8String],
			DISPATCH_QUEUE_SERIAL);
	}
	if (instance.quiesce == nil) {
		instance.quiesce = dispatch_semaphore_create(0);
	}
	[self logInstance:instance format:@"resume %@", instance.instanceId];
	dispatch_async(instance.queue, ^{
		for (UDToken *token in instance.tokens) {
			if (token.state != UDTokenStateWaiting) {
				continue;
			}
			UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
			if (![node isKindOfClass:[UDEvent class]]) {
				continue;
			}
			UDEvent *event = (UDEvent *)node;
			if (event.trigger == UDEventTriggerTimer
			    && [self.timers objectForKey:token.tokenId] == nil) {
				[self scheduleTimer:event token:token instance:instance];
			}
		}
		[self drainInstance:instance];
	});
	[self waitUntilQuiet:instance];
	if (instance.isFailed && error != NULL) {
		*error = instance.error;
	}
	return !instance.isFailed;
}

- (BOOL)completeUserTask:(NSString *)tokenId
                instance:(UDProcessInstance *)instance
               variables:(NSDictionary *)variables
                   error:(NSError **)error
{
	__block BOOL ok = NO;
	__block NSError *localError = nil;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_async(instance.queue, ^{
		UDToken *token = [instance tokenWithId:tokenId];
		if (token == nil || token.state != UDTokenStateWaiting) {
			localError = [NSError errorWithDomain:UDWorkflowErrorDomain
			                                 code:UDWorkflowErrorInvalidState
			                             userInfo:@{ NSLocalizedDescriptionKey:
					@"token is not a waiting user task" }];
			dispatch_semaphore_signal(done);
			return;
		}
		UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
		if (![node isKindOfClass:[UDTask class]]
		    || [(UDTask *)node kind] != UDTaskKindUser) {
			localError = [NSError errorWithDomain:UDWorkflowErrorDomain
			                                 code:UDWorkflowErrorInvalidState
			                             userInfo:@{ NSLocalizedDescriptionKey:
					@"token is not parked on a user task" }];
			dispatch_semaphore_signal(done);
			return;
		}
		if (variables != nil) {
			[instance.variables addEntriesFromDictionary:variables];
		}
		[self disarmBoundariesOn:token.nodeId instance:instance];
		NSArray *outgoing =
			[instance.definition outgoingFlowsFrom:token.nodeId];
		if ([outgoing count] == 0) {
			token.state = UDTokenStateCompleted;
		} else {
			[self advanceToken:token
			          instance:instance
			             along:[outgoing objectAtIndex:0]];
		}
		[self persist:instance];
		[self drainInstance:instance];
		ok = !instance.isFailed;
		localError = instance.error;
		dispatch_semaphore_signal(done);
	});
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
	if (!ok && error != NULL) {
		*error = localError;
	}
	return ok;
}

- (BOOL)deliverMessage:(NSString *)messageName
               payload:(NSDictionary *)payload
              instance:(UDProcessInstance *)instance
                 error:(NSError **)error
{
	__block BOOL delivered = NO;
	__block NSError *localError = nil;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_async(instance.queue, ^{
		NSMutableArray *targets = [NSMutableArray array];
		for (UDToken *token in instance.tokens) {
			if (token.state != UDTokenStateWaiting) {
				continue;
			}
			UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
			if (![node isKindOfClass:[UDEvent class]]) {
				continue;
			}
			UDEvent *event = (UDEvent *)node;
			if (event.trigger != UDEventTriggerMessage) {
				continue;
			}
			if (![event.messageName isEqualToString:messageName]) {
				continue;
			}
			[targets addObject:token];
		}
		if ([targets count] == 0) {
			localError = [NSError errorWithDomain:UDWorkflowErrorDomain
			                                 code:UDWorkflowErrorNoPath
			                             userInfo:@{ NSLocalizedDescriptionKey:
					[NSString stringWithFormat:@"no catch for message %@",
						messageName] }];
			dispatch_semaphore_signal(done);
			return;
		}
		for (UDToken *token in targets) {
			UDEvent *event = (UDEvent *)[instance.definition nodeWithId:token.nodeId];
			if (event.kind == UDEventKindBoundary && event.isInterrupting
			    && event.attachedToId != nil) {
				for (UDToken *activity in [instance tokensAtNode:event.attachedToId
				                                          state:UDTokenStateWaiting]) {
					activity.state = UDTokenStateCompleted;
				}
				[self disarmBoundariesOn:event.attachedToId instance:instance];
			}
			[self leaveEvent:event token:token instance:instance payload:payload];
			delivered = YES;
		}
		[self persist:instance];
		[self drainInstance:instance];
		dispatch_semaphore_signal(done);
	});
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
	if (!delivered && error != NULL) {
		*error = localError;
	}
	return delivered;
}

- (BOOL)deliverMessage:(NSString *)messageName
               payload:(NSDictionary *)payload
       correlationKey:(NSString *)correlationKey
                value:(id)value
                error:(NSError **)error
{
	if (![self.store isKindOfClass:[UDMemoryStore class]]) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidState
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"correlation lookup needs UDMemoryStore" }];
		}
		return NO;
	}
	UDMemoryStore *store = (UDMemoryStore *)self.store;
	NSArray *matches = [store instancesWithCorrelationKey:correlationKey
	                                                value:value
	                                                error:error];
	if ([matches count] == 0) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorNoPath
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"no instance for correlation key" }];
		}
		return NO;
	}
	BOOL any = NO;
	for (UDProcessInstance *instance in matches) {
		if ([self deliverMessage:messageName
		                   payload:payload
		                  instance:instance
		                     error:error]) {
			any = YES;
		}
	}
	return any;
}

- (BOOL)throwError:(NSString *)errorRef
          instance:(UDProcessInstance *)instance
             error:(NSError **)error
{
	__block BOOL taken = NO;
	__block NSError *localError = nil;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_async(instance.queue, ^{
		for (UDToken *token in [instance.tokens copy]) {
			if (token.state != UDTokenStateWaiting) {
				continue;
			}
			UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
			if (![node isKindOfClass:[UDTask class]]) {
				continue;
			}
			if ([self takeErrorBoundary:errorRef
			                      task:(UDTask *)node
			                     token:token
			                  instance:instance]) {
				taken = YES;
			}
		}
		if (!taken) {
			localError = [NSError errorWithDomain:UDWorkflowErrorDomain
			                                 code:UDWorkflowErrorNoPath
			                             userInfo:@{
				NSLocalizedDescriptionKey: @"no error boundary",
				UDWorkflowErrorRefKey: errorRef ?: @"*"
			}];
			[self failInstance:instance error:localError];
		} else {
			[self persist:instance];
			[self drainInstance:instance];
		}
		dispatch_semaphore_signal(done);
	});
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
	if (!taken && error != NULL) {
		*error = localError;
	}
	return taken;
}

@end

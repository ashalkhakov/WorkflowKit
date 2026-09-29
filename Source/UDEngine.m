#import "UDEngine.h"
#import "UDFlowElements.h"
#import "UDCondition.h"
#import "UDRepositoryService.h"
#import <dispatch/dispatch.h>
#include <time.h>

/* Units of work run on a fixed set of serial queues, an instance always on
 * the same one: serial per instance, bounded in number however many
 * instances there are. */
#define UD_STRIPES 8

/* Timer jobs taken per scheduler pass. */
#define UD_TIMER_BATCH 64

static NSString * const UDUnitKey = @"UDWorkflow.unit";

/*
 * What one unit of work produced besides the new marking: callbacks for
 * the delegate and the user-task port, in the order they happened. Traces
 * go out whether or not the unit commits; everything else only if it does.
 */
@interface UDUnit : NSObject
@property (nonatomic, strong) NSMutableArray *effects;
@property (nonatomic, strong) NSMutableArray *effectsNeedCommit;
@property (nonatomic) BOOL committed;
@end

@implementation UDUnit
- (instancetype)init
{
	self = [super init];
	if (self) {
		_effects = [NSMutableArray array];
		_effectsNeedCommit = [NSMutableArray array];
	}
	return self;
}
@end

/* The unit running on this thread. A unit runs start to finish inside one
 * block on its stripe queue, so the thread identifies it. */
static UDUnit *
UDCurrentUnit(void)
{
	return [[[NSThread currentThread] threadDictionary] objectForKey:UDUnitKey];
}

static void
UDAddEffect(BOOL needsCommit, void (^effect)(void))
{
	UDUnit *unit = UDCurrentUnit();
	if (unit == nil) {
		return;
	}
	[unit.effects addObject:[effect copy]];
	[unit.effectsNeedCommit addObject:[NSNumber numberWithBool:needsCommit]];
}

/* What a binary property list can hold. Checked here rather than with
 * +propertyList:isValidForFormat:, which gnustep-base answers NO for valid
 * dictionaries. */
static BOOL
UDIsPropertyList(id object)
{
	if (object == nil
	    || [object isKindOfClass:[NSString class]]
	    || [object isKindOfClass:[NSNumber class]]
	    || [object isKindOfClass:[NSDate class]]
	    || [object isKindOfClass:[NSData class]]) {
		return YES;
	}
	if ([object isKindOfClass:[NSArray class]]) {
		for (id element in object) {
			if (!UDIsPropertyList(element)) {
				return NO;
			}
		}
		return YES;
	}
	if ([object isKindOfClass:[NSDictionary class]]) {
		for (id key in object) {
			if (![key isKindOfClass:[NSString class]]
			    || !UDIsPropertyList([object objectForKey:key])) {
				return NO;
			}
		}
		return YES;
	}
	return NO;
}

static NSError *
UDError(UDWorkflowErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:UDWorkflowErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

typedef BOOL (^UDUnitInput)(UDProcessInstance *root, NSError **error);

@interface UDEngine ()
- (void)serviceInvocation:(UDServiceInvocation *)invocation
                didFinish:(UDServiceResult *)result;
@end

@implementation UDEngine
{
	dispatch_queue_t _stripes[UD_STRIPES];
	dispatch_queue_t _schedulerQueue;
	dispatch_source_t _scheduler;
	NSDate *_backoffUntil;
	BOOL _closed;
	NSCondition *_settle;
	NSMutableDictionary *_busy;
}

- (instancetype)initWithStore:(UDStore *)store
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_store = store;
	_repositoryService = [[UDRepositoryService alloc] initWithStore:store];
	_settle = [[NSCondition alloc] init];
	_busy = [NSMutableDictionary dictionary];
	self.workerQueue = dispatch_get_global_queue(
		DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	{
		dispatch_queue_t q = dispatch_queue_create("ud.workflow.callbacks",
			DISPATCH_QUEUE_SERIAL);
		self.callbackQueue = q;
		UDDispatchRelease(q);
	}
	for (NSUInteger i = 0; i < UD_STRIPES; i++) {
		_stripes[i] = dispatch_queue_create("ud.workflow.instances",
			DISPATCH_QUEUE_SERIAL);
	}
	_schedulerQueue = dispatch_queue_create("ud.workflow.scheduler",
		DISPATCH_QUEUE_SERIAL);
	_scheduler = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
		_schedulerQueue);
	__weak UDEngine *weakSelf = self;
	dispatch_source_set_event_handler(_scheduler, ^{
		[weakSelf schedulerFired];
	});
	dispatch_source_set_timer(_scheduler, DISPATCH_TIME_FOREVER,
		DISPATCH_TIME_FOREVER, 0);
	dispatch_resume(_scheduler);
	return self;
}

- (void)dealloc
{
	[self close];
	UDDispatchRelease(_scheduler);
	UDDispatchRelease(_schedulerQueue);
	for (NSUInteger i = 0; i < UD_STRIPES; i++) {
		UDDispatchRelease(_stripes[i]);
	}
	if (_workerQueue != NULL) {
		UDDispatchRelease(_workerQueue);
	}
	if (_callbackQueue != NULL) {
		UDDispatchRelease(_callbackQueue);
	}
}

- (void)setWorkerQueue:(dispatch_queue_t)workerQueue
{
	if (workerQueue == _workerQueue) {
		return;
	}
	if (workerQueue != NULL) {
		UDDispatchRetain(workerQueue);
	}
	if (_workerQueue != NULL) {
		UDDispatchRelease(_workerQueue);
	}
	_workerQueue = workerQueue;
}

- (void)setCallbackQueue:(dispatch_queue_t)callbackQueue
{
	if (callbackQueue == _callbackQueue) {
		return;
	}
	if (callbackQueue != NULL) {
		UDDispatchRetain(callbackQueue);
	}
	if (_callbackQueue != NULL) {
		UDDispatchRelease(_callbackQueue);
	}
	_callbackQueue = callbackQueue;
}

- (dispatch_queue_t)stripeFor:(NSString *)instanceId
{
	return _stripes[[instanceId hash] % UD_STRIPES];
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
	UDAddEffect(NO, ^{
		[delegate engine:self instance:instance didTrace:message];
	});
}

#pragma mark - Settling

- (void)beginWork:(NSString *)instanceId
{
	[_settle lock];
	NSUInteger count = [[_busy objectForKey:instanceId] unsignedIntegerValue];
	[_busy setObject:[NSNumber numberWithUnsignedInteger:count + 1]
	          forKey:instanceId];
	[_settle unlock];
}

- (void)endWork:(NSString *)instanceId
{
	[_settle lock];
	NSUInteger count = [[_busy objectForKey:instanceId] unsignedIntegerValue];
	if (count <= 1) {
		[_busy removeObjectForKey:instanceId];
	} else {
		[_busy setObject:[NSNumber numberWithUnsignedInteger:count - 1]
		          forKey:instanceId];
	}
	[_settle broadcast];
	[_settle unlock];
}

- (BOOL)waitUntilSettled:(NSString *)instanceId timeout:(NSTimeInterval)timeout
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	BOOL settled = YES;
	[_settle lock];
	while ([_busy objectForKey:instanceId] != nil) {
		if (![_settle waitUntilDate:deadline]) {
			settled = [_busy objectForKey:instanceId] == nil;
			break;
		}
	}
	[_settle unlock];
	return settled;
}

#pragma mark - Loading and committing

- (UDProcessInstance *)loadInstance:(NSString *)instanceId error:(NSError **)error
{
	UDInstanceRecord *record = [self.store instanceRecord:instanceId error:error];
	if (record == nil) {
		return nil;
	}
	UDProcessDefinition *definition =
		[self.repositoryService definitionForKey:record.processId
		                                 version:record.version
		                                   error:error];
	if (definition == nil) {
		return nil;
	}
	NSDictionary *state = [NSPropertyListSerialization
		propertyListWithData:record.state
		             options:NSPropertyListImmutable
		              format:NULL
		               error:error];
	if (state == nil) {
		return nil;
	}
	return [UDProcessInstance instanceWithStateDictionary:state
	                                           definition:definition
	                                                error:error];
}

/* The jobs the marking needs: a service call per token waiting on a
 * service or script task, a timer per token waiting on a timer event. */
- (void)collectJobs:(NSMutableArray *)jobs scope:(UDProcessInstance *)scope
{
	for (UDToken *token in scope.tokens) {
		if (token.state != UDTokenStateWaiting) {
			continue;
		}
		UDFlowNode *node = [scope.definition nodeWithId:token.nodeId];
		UDJobRecord *job = nil;
		if ([node isKindOfClass:[UDTask class]]
		    && [(UDTask *)node kind] != UDTaskKindUser) {
			job = [[UDJobRecord alloc] init];
			job.kind = UDJobKindService;
			job.actionKey = [(UDTask *)node actionKey];
		} else if ([node isKindOfClass:[UDEvent class]]
		           && [(UDEvent *)node trigger] == UDEventTriggerTimer
		           && token.dueAt != nil) {
			job = [[UDJobRecord alloc] init];
			job.kind = UDJobKindTimer;
			job.dueAt = token.dueAt;
		}
		if (job != nil) {
			job.tokenId = token.tokenId;
			[jobs addObject:job];
		}
	}
	for (UDProcessInstance *child in [scope.children allValues]) {
		[self collectJobs:jobs scope:child];
	}
}

- (NSArray<UDJobRecord *> *)commit:(UDProcessInstance *)root error:(NSError **)error
{
	[root pruneCompletedTokens];
	NSData *state = [NSPropertyListSerialization
		dataWithPropertyList:[root stateDictionary]
		              format:NSPropertyListBinaryFormat_v1_0
		             options:0
		               error:error];
	if (state == nil) {
		return nil;
	}
	UDInstanceRecord *record = [[UDInstanceRecord alloc] init];
	record.instanceId = root.instanceId;
	record.processId = root.definition.processId;
	record.version = root.definition.version;
	record.state = state;
	record.status = root.isFailed ? UDInstanceStatusFailed
		: root.isCompleted ? UDInstanceStatusCompleted
		: UDInstanceStatusActive;
	BOOL active = record.status == UDInstanceStatusActive;
	NSMutableArray *jobs = [NSMutableArray array];
	if (active) {
		[self collectJobs:jobs scope:root];
	}
	return [self.store commitInstance:record
	                             jobs:jobs
	                  correlationKeys:active ? root.correlationKeys : @{}
	                            error:error];
}

#pragma mark - Gateways

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
		return YES;
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

#pragma mark - Events

- (void)failInstance:(UDProcessInstance *)instance error:(NSError *)error
{
	instance.failed = YES;
	instance.error = error;
	[self logInstance:instance format:@"failed: %@",
		[error localizedDescription]];
}

- (void)leaveEvent:(UDEvent *)event
             token:(UDToken *)token
          instance:(UDProcessInstance *)instance
           payload:(NSDictionary *)payload
{
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
	NSString *name = event.messageName;
	NSDictionary *payload = [instance.variables copy];
	if (delegate != nil
	    && [delegate respondsToSelector:@selector(engine:instance:didThrowMessage:payload:)]) {
		UDAddEffect(YES, ^{
			[delegate engine:self
			         instance:instance
			  didThrowMessage:name
			          payload:payload];
		});
	}
	[self logInstance:instance format:@"throw message %@", name];
}

- (void)disarmBoundariesOn:(NSString *)taskId instance:(UDProcessInstance *)instance
{
	NSArray *boundaries = [instance.definition boundaryEventsAttachedTo:taskId];
	for (UDEvent *event in boundaries) {
		for (UDToken *token in [instance tokensAtNode:event.elementId
		                                       state:UDTokenStateWaiting]) {
			token.state = UDTokenStateCompleted;
		}
	}
}

/* Interrupting boundary: the host activity's tokens end and its other
 * boundaries are disarmed. */
- (void)interruptHostOf:(UDEvent *)event instance:(UDProcessInstance *)instance
{
	if (event.kind != UDEventKindBoundary || !event.isInterrupting
	    || event.attachedToId == nil) {
		return;
	}
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

- (void)timerFired:(UDToken *)token
             event:(UDEvent *)event
          instance:(UDProcessInstance *)instance
{
	[self logInstance:instance format:@"timer %@", event.elementId];
	token.dueAt = nil;
	[self interruptHostOf:event instance:instance];
	[self leaveEvent:event token:token instance:instance payload:nil];
}

/* The token waits for its due time; the commit turns that into a timer
 * job, and the scheduler brings it back. */
- (void)scheduleTimer:(UDEvent *)event
                token:(UDToken *)token
             instance:(UDProcessInstance *)instance
{
	NSTimeInterval duration = event.timerDuration;
	if (duration < 0) {
		duration = 0;
	}
	token.state = UDTokenStateWaiting;
	token.dueAt = [NSDate dateWithTimeIntervalSinceNow:duration];
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
		/* Armed explicitly when the host task is entered. */
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
		/* A timer that is already due fires in this step rather than
		 * after a round trip through the scheduler. */
		if (event.timerDuration <= 0) {
			[self logInstance:instance format:@"timer %@ due", event.elementId];
			[self leaveEvent:event token:token instance:instance payload:nil];
			return YES;
		}
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
				*error = UDError(UDWorkflowErrorNoPath, @"event has no outgoing flow");
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

#pragma mark - Tasks

- (void)leaveTask:(NSString *)taskId
            token:(UDToken *)token
         instance:(UDProcessInstance *)instance
{
	[self disarmBoundariesOn:taskId instance:instance];
	NSArray *outgoing = [instance.definition outgoingFlowsFrom:taskId];
	if ([outgoing count] == 0) {
		token.state = UDTokenStateCompleted;
	} else {
		[self advanceToken:token
		          instance:instance
		             along:[outgoing objectAtIndex:0]];
	}
}

- (BOOL)fireTask:(UDTask *)task
           token:(UDToken *)token
        instance:(UDProcessInstance *)instance
           error:(NSError **)error
{
	[self armBoundariesForTask:task token:token instance:instance];
	token.state = UDTokenStateWaiting;
	if (task.kind == UDTaskKindUser) {
		[self logInstance:instance format:@"user task %@ assignee=%@",
			task.elementId, task.assignee];
		id<UDUserTaskPort> port = self.userTaskPort;
		if (port != nil) {
			UDAddEffect(YES, ^{
				[port publishWorkItemForToken:token
				                     instance:instance
				                         task:task];
			});
		}
		return YES;
	}
	/* The commit turns the waiting token into a service job. */
	[self logInstance:instance format:@"%@ action %@",
		task.elementId, task.actionKey];
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
	UDToken *armed = [instance makeTokenOnNode:boundary.elementId
	                            arrivedViaFlow:nil
	                                    parent:token];
	[self logInstance:instance format:@"error %@ on %@",
		errorRef ?: @"*", task.elementId];
	[self leaveEvent:boundary token:armed instance:instance
	         payload:errorRef ? @{ @"errorRef": errorRef } : nil];
	return YES;
}

- (void)applyServiceResult:(UDServiceResult *)result
                     token:(UDToken *)token
                      task:(UDTask *)task
                  instance:(UDProcessInstance *)instance
{
	NSError *failure = result.error;
	if (failure == nil && !UDIsPropertyList(result.variables)) {
		failure = UDError(UDWorkflowErrorHandler,
			[NSString stringWithFormat:
				@"%@ returned variables that are not property-list values",
				task.actionKey]);
	}
	if (failure != nil) {
		NSString *ref = [[failure userInfo] objectForKey:UDWorkflowErrorRefKey];
		if (![self takeErrorBoundary:ref task:task token:token instance:instance]) {
			[self failInstance:instance error:failure];
		}
		return;
	}
	if (result.variables != nil) {
		[instance.variables addEntriesFromDictionary:result.variables];
	}
	[self leaveTask:task.elementId token:token instance:instance];
}

#pragma mark - Subprocesses

- (BOOL)fireSubProcess:(UDSubProcess *)node
                 token:(UDToken *)token
              instance:(UDProcessInstance *)instance
                 error:(NSError **)error
{
	UDEvent *start = [node.innerDefinition startEvent];
	if (start == nil) {
		if (error != NULL) {
			*error = UDError(UDWorkflowErrorInvalidDefinition,
				@"subprocess has no inner definition or no start event");
		}
		return NO;
	}
	token.state = UDTokenStateWaiting;
	UDProcessInstance *child = [[UDProcessInstance alloc] init];
	child.instanceId = [NSString stringWithFormat:@"%@/%@",
		instance.instanceId, token.tokenId];
	child.definition = node.innerDefinition;
	[child.variables addEntriesFromDictionary:instance.variables];
	child.parent = instance;
	child.hostTokenId = token.tokenId;
	[instance.children setObject:child forKey:token.tokenId];
	[child makeTokenOnNode:start.elementId arrivedViaFlow:nil parent:nil];
	[self logInstance:instance format:@"enter subprocess %@", node.elementId];
	return YES;
}

/* A finished subprocess hands its variables, or its failure, back to the
 * token waiting on it. */
- (void)finishHost:(UDProcessInstance *)child
{
	UDProcessInstance *parent = child.parent;
	[parent.children removeObjectForKey:child.hostTokenId];
	UDToken *host = [parent tokenWithId:child.hostTokenId];
	if (host == nil) {
		return;
	}
	if (child.isFailed) {
		[self failInstance:parent error:child.error];
		return;
	}
	[parent.variables addEntriesFromDictionary:child.variables];
	[self logInstance:parent format:@"leave subprocess %@", host.nodeId];
	NSArray *outgoing = [parent.definition outgoingFlowsFrom:host.nodeId];
	if ([outgoing count] == 0) {
		host.state = UDTokenStateCompleted;
	} else {
		[self advanceToken:host instance:parent along:[outgoing objectAtIndex:0]];
	}
}

#pragma mark - Firing

- (BOOL)fireToken:(UDToken *)token
         instance:(UDProcessInstance *)instance
            error:(NSError **)error
{
	UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
	if ([node isKindOfClass:[UDEvent class]]) {
		return [self fireEvent:(UDEvent *)node token:token instance:instance error:error];
	}
	if ([node isKindOfClass:[UDTask class]]) {
		return [self fireTask:(UDTask *)node token:token instance:instance error:error];
	}
	if ([node isKindOfClass:[UDGateway class]]) {
		return [self fireGateway:(UDGateway *)node token:token instance:instance error:error];
	}
	if ([node isKindOfClass:[UDSubProcess class]]) {
		return [self fireSubProcess:(UDSubProcess *)node token:token instance:instance error:error];
	}
	if (error != NULL) {
		*error = UDError(UDWorkflowErrorUnknownElement, node == nil
			? [NSString stringWithFormat:@"unknown node %@", token.nodeId]
			: @"unsupported flow node");
	}
	return NO;
}

- (void)checkCompletion:(UDProcessInstance *)instance
{
	if (instance.isFailed || instance.isCompleted
	    || [instance.children count] > 0) {
		return;
	}
	for (UDToken *token in instance.tokens) {
		if (token.state != UDTokenStateCompleted) {
			return;
		}
	}
	instance.completed = YES;
	[self logInstance:instance format:@"instance completed"];
}

/* Fires tokens until none is ready, here and in every subprocess, and
 * hands finished subprocesses back to their hosts. */
- (void)runScope:(UDProcessInstance *)scope
{
	for (;;) {
		if (scope.isFailed || scope.isCompleted) {
			return;
		}
		UDToken *token = nil;
		while ((token = [scope nextReadyToken]) != nil) {
			NSError *error = nil;
			if (![self fireToken:token instance:scope error:&error]) {
				[self failInstance:scope error:error];
				return;
			}
		}
		BOOL progressed = NO;
		for (NSString *hostId in [scope.children allKeys]) {
			UDProcessInstance *child = [scope.children objectForKey:hostId];
			[self runScope:child];
			if (child.isCompleted || child.isFailed) {
				[self finishHost:child];
				progressed = YES;
				if (scope.isFailed) {
					return;
				}
			}
		}
		if (!progressed) {
			break;
		}
	}
	[self checkCompletion:scope];
}

- (BOOL)hasServiceInFlight:(UDProcessInstance *)scope
{
	for (UDToken *token in scope.tokens) {
		UDFlowNode *node = [scope.definition nodeWithId:token.nodeId];
		if (token.state == UDTokenStateWaiting
		    && [node isKindOfClass:[UDTask class]]
		    && [(UDTask *)node kind] != UDTaskKindUser) {
			return YES;
		}
	}
	for (UDProcessInstance *child in [scope.children allValues]) {
		if ([self hasServiceInFlight:child]) {
			return YES;
		}
	}
	return NO;
}

#pragma mark - Units of work

- (void)deliverEffects:(UDUnit *)unit
{
	NSMutableArray *effects = [NSMutableArray array];
	NSUInteger count = [unit.effects count];
	for (NSUInteger i = 0; i < count; i++) {
		if (unit.committed
		    || ![[unit.effectsNeedCommit objectAtIndex:i] boolValue]) {
			[effects addObject:[unit.effects objectAtIndex:i]];
		}
	}
	if ([effects count] == 0) {
		return;
	}
	dispatch_async(self.callbackQueue, ^{
		for (void (^effect)(void) in effects) {
			effect();
		}
	});
}

- (void)sendServiceJob:(UDJobRecord *)job root:(UDProcessInstance *)root
{
	UDProcessInstance *scope = nil;
	UDToken *token = [root findTokenWithId:job.tokenId scope:&scope];
	if (token == nil) {
		return;
	}
	UDServiceInvocation *invocation =
		[[UDServiceInvocation alloc] initWithJobId:job.jobId
		                                 actionKey:job.actionKey
		                                 variables:[scope.variables copy]
		                                instanceId:root.instanceId
		                                   tokenId:job.tokenId];
	invocation.target = self;
	invocation.action = @selector(serviceInvocation:didFinish:);
	[self beginWork:root.instanceId];
	id<UDServiceTaskHandler> handler = self.serviceHandler;
	dispatch_async(self.workerQueue, ^{
		if (handler == nil) {
			[invocation finishWithVariables:nil error:nil];
		} else {
			[handler performInvocation:invocation];
		}
	});
}

- (void)afterCommit:(UDProcessInstance *)root
           inserted:(NSArray<UDJobRecord *> *)inserted
          wasActive:(BOOL)wasActive
{
	id<UDEngineDelegate> delegate = self.delegate;
	BOOL finished = root.isCompleted || root.isFailed;
	if (wasActive && finished) {
		if ([delegate respondsToSelector:@selector(engine:instanceDidFinish:error:)]) {
			UDAddEffect(YES, ^{
				[delegate engine:self instanceDidFinish:root error:root.error];
			});
		}
	} else if (!finished && ![self hasServiceInFlight:root]) {
		if ([delegate respondsToSelector:@selector(engine:instanceDidPause:)]) {
			UDAddEffect(YES, ^{
				[delegate engine:self instanceDidPause:root];
			});
		}
	}
	BOOL timers = NO;
	for (UDJobRecord *job in inserted) {
		if (job.kind == UDJobKindService) {
			[self sendServiceJob:job root:root];
		} else {
			timers = YES;
		}
	}
	if (timers) {
		[self reschedule];
	}
}

/*
 * One unit of work, on the instance's stripe. fresh is a new instance not
 * yet in the store; otherwise the instance is loaded. input applies the
 * outside event and answers NO to reject it, in which case nothing is
 * committed. *committed says whether the unit reached the store.
 */
- (BOOL)unitOn:(NSString *)instanceId
         fresh:(UDProcessInstance *)fresh
         input:(UDUnitInput)input
     committed:(BOOL *)committed
         error:(NSError **)error
{
	*committed = NO;
	UDProcessInstance *root = fresh;
	if (root == nil) {
		root = [self loadInstance:instanceId error:error];
		if (root == nil) {
			return NO;
		}
	}
	BOOL wasActive = !root.isCompleted && !root.isFailed;
	if (input != nil && !input(root, error)) {
		return NO;
	}
	if (wasActive) {
		[self runScope:root];
	}
	NSError *commitError = nil;
	NSArray *inserted = [self commit:root error:&commitError];
	if (inserted == nil) {
		id<UDEngineDelegate> delegate = self.delegate;
		if ([delegate respondsToSelector:@selector(engine:instanceId:didFailToCommit:)]) {
			UDAddEffect(NO, ^{
				[delegate engine:self instanceId:instanceId didFailToCommit:commitError];
			});
		}
		if (error != NULL) {
			*error = commitError;
		}
		return NO;
	}
	*committed = YES;
	UDCurrentUnit().committed = YES;
	[self afterCommit:root inserted:inserted wasActive:wasActive];
	if (root.isFailed) {
		if (error != NULL) {
			*error = root.error;
		}
		return NO;
	}
	return YES;
}

/* Runs a unit on the calling thread. The caller is on the stripe. */
- (BOOL)runUnitHere:(NSString *)instanceId
              fresh:(UDProcessInstance *)fresh
              input:(UDUnitInput)input
          committed:(BOOL *)committed
              error:(NSError **)error
{
	UDUnit *unit = [[UDUnit alloc] init];
	NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
	[threadDictionary setObject:unit forKey:UDUnitKey];
	BOOL ok = [self unitOn:instanceId
	                 fresh:fresh
	                 input:input
	             committed:committed
	                 error:error];
	[threadDictionary removeObjectForKey:UDUnitKey];
	[self deliverEffects:unit];
	return ok;
}

- (BOOL)runUnit:(NSString *)instanceId
          fresh:(UDProcessInstance *)fresh
          input:(UDUnitInput)input
      committed:(BOOL *)committed
          error:(NSError **)error
{
	__block BOOL ok = NO;
	__block BOOL didCommit = NO;
	__block NSError *localError = nil;
	dispatch_sync([self stripeFor:instanceId], ^{
		NSError *unitError = nil;
		ok = [self runUnitHere:instanceId
		                 fresh:fresh
		                 input:input
		             committed:&didCommit
		                 error:&unitError];
		localError = unitError;
	});
	if (committed != NULL) {
		*committed = didCommit;
	}
	if (!ok && error != NULL) {
		*error = localError;
	}
	return ok;
}

#pragma mark - Service results

- (void)serviceInvocation:(UDServiceInvocation *)invocation
                didFinish:(UDServiceResult *)result
{
	NSString *instanceId = invocation.instanceId;
	NSString *tokenId = invocation.tokenId;
	dispatch_async([self stripeFor:instanceId], ^{
		BOOL committed = NO;
		[self runUnitHere:instanceId fresh:nil input:^BOOL(UDProcessInstance *root, NSError **error) {
			(void)error;
			UDProcessInstance *scope = nil;
			UDToken *token = [root findTokenWithId:tokenId scope:&scope];
			UDFlowNode *node = [scope.definition nodeWithId:token.nodeId];
			if (token == nil || token.state != UDTokenStateWaiting
			    || ![node isKindOfClass:[UDTask class]]
			    || [(UDTask *)node kind] == UDTaskKindUser) {
				/* The token moved on meanwhile (a boundary event took
				 * it): the result is stale. Committing anyway drops the
				 * job. */
				[self logInstance:root format:@"stale result for %@", tokenId];
				return YES;
			}
			[self applyServiceResult:result
			                   token:token
			                    task:(UDTask *)node
			                instance:scope];
			return YES;
		} committed:&committed error:NULL];
		[self endWork:instanceId];
	});
}

#pragma mark - Timers

- (void)reschedule
{
	dispatch_async(_schedulerQueue, ^{
		[self rearmScheduler];
	});
}

/* On the scheduler queue. */
- (void)rearmScheduler
{
	if (_closed) {
		return;
	}
	NSDate *due = [self.store earliestTimerDue];
	if (due != nil && _backoffUntil != nil
	    && [due compare:_backoffUntil] == NSOrderedAscending) {
		due = _backoffUntil;
	}
	if (due == nil) {
		dispatch_source_set_timer(_scheduler, DISPATCH_TIME_FOREVER,
			DISPATCH_TIME_FOREVER, 0);
		return;
	}
	NSTimeInterval seconds = [due timeIntervalSince1970];
	struct timespec when;
	when.tv_sec = (time_t)seconds;
	when.tv_nsec = (long)((seconds - (double)when.tv_sec) * (double)NSEC_PER_SEC);
	dispatch_source_set_timer(_scheduler, dispatch_walltime(&when, 0),
		DISPATCH_TIME_FOREVER, 5 * NSEC_PER_MSEC);
}

/* On the scheduler queue: runs the due timer jobs, then aims at the next. */
- (void)schedulerFired
{
	if (_closed) {
		return;
	}
	NSArray *jobs = [self.store jobsOfKind:UDJobKindTimer
	                             dueBefore:[NSDate date]
	                                 limit:UD_TIMER_BATCH];
	BOOL stuck = NO;
	for (UDJobRecord *job in jobs) {
		NSString *tokenId = job.tokenId;
		BOOL committed = NO;
		NSError *error = nil;
		[self runUnit:job.instanceId fresh:nil input:^BOOL(UDProcessInstance *root, NSError **inputError) {
			(void)inputError;
			UDProcessInstance *scope = nil;
			UDToken *token = [root findTokenWithId:tokenId scope:&scope];
			UDFlowNode *node = [scope.definition nodeWithId:token.nodeId];
			if (token != nil && token.state == UDTokenStateWaiting
			    && [node isKindOfClass:[UDEvent class]]
			    && [(UDEvent *)node trigger] == UDEventTriggerTimer
			    && [token.dueAt timeIntervalSinceNow] <= 0) {
				[self timerFired:token event:(UDEvent *)node instance:scope];
			}
			return YES;
		} committed:&committed error:&error];
		if (!committed) {
			if ([error code] == UDWorkflowErrorUnknownElement
			    && [[error domain] isEqualToString:UDWorkflowErrorDomain]) {
				/* The instance is gone: so is the reason for the job. */
				[self.store deleteJob:job.jobId error:NULL];
			} else {
				stuck = YES;
			}
		}
	}
	_backoffUntil = stuck ? [NSDate dateWithTimeIntervalSinceNow:1.0] : nil;
	[self rearmScheduler];
}

#pragma mark - Lifecycle

- (BOOL)openWithError:(NSError **)error
{
	NSError *firstError = nil;
	for (UDJobRecord *job in [self.store jobsOfKind:UDJobKindService
	                                      dueBefore:nil
	                                          limit:0]) {
		__block NSError *loadError = nil;
		dispatch_sync([self stripeFor:job.instanceId], ^{
			NSError *unitError = nil;
			UDProcessInstance *root = [self loadInstance:job.instanceId error:&unitError];
			if (root == nil) {
				loadError = unitError;
				return;
			}
			[self sendServiceJob:job root:root];
		});
		if (loadError != nil && firstError == nil) {
			firstError = loadError;
		}
	}
	[self reschedule];
	if (firstError != nil) {
		if (error != NULL) {
			*error = firstError;
		}
		return NO;
	}
	return YES;
}

- (void)close
{
	if (_closed) {
		return;
	}
	_closed = YES;
	dispatch_source_cancel(_scheduler);
}

#pragma mark - Inputs

- (NSString *)startProcess:(NSString *)processId
                 variables:(NSDictionary *)variables
                     error:(NSError **)error
{
	return [self startProcess:processId
	                variables:variables
	          correlationKeys:nil
	                    error:error];
}

- (NSString *)startProcess:(NSString *)processId
                 variables:(NSDictionary *)variables
           correlationKeys:(NSDictionary *)correlationKeys
                     error:(NSError **)error
{
	if (!UDIsPropertyList(variables)) {
		if (error != NULL) {
			*error = UDError(UDWorkflowErrorInvalidState,
				@"variables must be property-list values");
		}
		return nil;
	}
	for (id value in [correlationKeys allValues]) {
		if (![value isKindOfClass:[NSString class]]
		    && ![value isKindOfClass:[NSNumber class]]) {
			if (error != NULL) {
				*error = UDError(UDWorkflowErrorInvalidState,
					@"correlation values must be strings or numbers");
			}
			return nil;
		}
	}
	UDProcessDefinition *definition =
		[self.repositoryService latestDefinitionForKey:processId error:error];
	if (definition == nil) {
		return nil;
	}
	UDEvent *start = [definition startEvent];
	if (start == nil) {
		if (error != NULL) {
			*error = UDError(UDWorkflowErrorInvalidDefinition,
				@"definition has no start event");
		}
		return nil;
	}
	UDProcessInstance *instance = [[UDProcessInstance alloc] init];
	instance.instanceId = [[NSUUID UUID] UUIDString];
	instance.definition = definition;
	[instance.variables addEntriesFromDictionary:variables];
	[instance.correlationKeys addEntriesFromDictionary:correlationKeys];
	[instance makeTokenOnNode:start.elementId arrivedViaFlow:nil parent:nil];
	BOOL ok = [self runUnit:instance.instanceId fresh:instance input:^BOOL(UDProcessInstance *root, NSError **inputError) {
		(void)inputError;
		[self logInstance:root format:@"start %@ v%ld",
			definition.processId, (long)definition.version];
		return YES;
	} committed:NULL error:error];
	return ok ? instance.instanceId : nil;
}

- (BOOL)completeUserTask:(NSString *)tokenId
              instanceId:(NSString *)instanceId
               variables:(NSDictionary *)variables
                   error:(NSError **)error
{
	if (!UDIsPropertyList(variables)) {
		if (error != NULL) {
			*error = UDError(UDWorkflowErrorInvalidState,
				@"variables must be property-list values");
		}
		return NO;
	}
	return [self runUnit:instanceId fresh:nil input:^BOOL(UDProcessInstance *root, NSError **inputError) {
		UDProcessInstance *scope = nil;
		UDToken *token = [root findTokenWithId:tokenId scope:&scope];
		UDFlowNode *node = [scope.definition nodeWithId:token.nodeId];
		if (token == nil || token.state != UDTokenStateWaiting
		    || ![node isKindOfClass:[UDTask class]]
		    || [(UDTask *)node kind] != UDTaskKindUser) {
			if (inputError != NULL) {
				*inputError = UDError(UDWorkflowErrorInvalidState,
					@"token is not a waiting user task");
			}
			return NO;
		}
		if (variables != nil) {
			[scope.variables addEntriesFromDictionary:variables];
		}
		[self leaveTask:token.nodeId token:token instance:scope];
		return YES;
	} committed:NULL error:error];
}

/* Tokens waiting on a catch for the message, anywhere in the tree. */
- (void)collectCatches:(NSMutableArray *)catches
               message:(NSString *)messageName
                 scope:(UDProcessInstance *)scope
{
	for (UDToken *token in scope.tokens) {
		if (token.state != UDTokenStateWaiting) {
			continue;
		}
		UDFlowNode *node = [scope.definition nodeWithId:token.nodeId];
		if ([node isKindOfClass:[UDEvent class]]
		    && [(UDEvent *)node trigger] == UDEventTriggerMessage
		    && [[(UDEvent *)node messageName] isEqualToString:messageName]) {
			[catches addObject:@[ token, scope ]];
		}
	}
	for (UDProcessInstance *child in [scope.children allValues]) {
		[self collectCatches:catches message:messageName scope:child];
	}
}

- (BOOL)deliverMessage:(NSString *)messageName
               payload:(NSDictionary *)payload
            instanceId:(NSString *)instanceId
                 error:(NSError **)error
{
	if (!UDIsPropertyList(payload)) {
		if (error != NULL) {
			*error = UDError(UDWorkflowErrorInvalidState,
				@"payload must be property-list values");
		}
		return NO;
	}
	return [self runUnit:instanceId fresh:nil input:^BOOL(UDProcessInstance *root, NSError **inputError) {
		NSMutableArray *catches = [NSMutableArray array];
		[self collectCatches:catches message:messageName scope:root];
		if ([catches count] == 0) {
			if (inputError != NULL) {
				*inputError = UDError(UDWorkflowErrorNoPath,
					[NSString stringWithFormat:@"no catch for message %@",
						messageName]);
			}
			return NO;
		}
		for (NSArray *pair in catches) {
			UDToken *token = [pair objectAtIndex:0];
			UDProcessInstance *scope = [pair objectAtIndex:1];
			if (token.state != UDTokenStateWaiting) {
				/* An earlier catch in this delivery cancelled it. */
				continue;
			}
			UDEvent *event = (UDEvent *)[scope.definition nodeWithId:token.nodeId];
			[self interruptHostOf:event instance:scope];
			[self leaveEvent:event token:token instance:scope payload:payload];
		}
		return YES;
	} committed:NULL error:error];
}

- (BOOL)deliverMessage:(NSString *)messageName
               payload:(NSDictionary *)payload
        correlationKey:(NSString *)correlationKey
                 value:(id)value
                 error:(NSError **)error
{
	NSArray *ids = [self.store instanceIdsForCorrelationKey:correlationKey
	                                                  value:value];
	if ([ids count] == 0) {
		if (error != NULL) {
			*error = UDError(UDWorkflowErrorNoPath, @"no instance for correlation key");
		}
		return NO;
	}
	BOOL any = NO;
	for (NSString *instanceId in ids) {
		if ([self deliverMessage:messageName
		                 payload:payload
		              instanceId:instanceId
		                   error:error]) {
			any = YES;
		}
	}
	return any;
}

- (void)collectWaitingTasks:(NSMutableArray *)tasks scope:(UDProcessInstance *)scope
{
	for (UDToken *token in scope.tokens) {
		if (token.state == UDTokenStateWaiting
		    && [[scope.definition nodeWithId:token.nodeId] isKindOfClass:[UDTask class]]) {
			[tasks addObject:@[ token, scope ]];
		}
	}
	for (UDProcessInstance *child in [scope.children allValues]) {
		[self collectWaitingTasks:tasks scope:child];
	}
}

- (BOOL)throwError:(NSString *)errorRef
        instanceId:(NSString *)instanceId
             error:(NSError **)error
{
	return [self runUnit:instanceId fresh:nil input:^BOOL(UDProcessInstance *root, NSError **inputError) {
		(void)inputError;
		NSMutableArray *tasks = [NSMutableArray array];
		[self collectWaitingTasks:tasks scope:root];
		BOOL taken = NO;
		for (NSArray *pair in tasks) {
			UDToken *token = [pair objectAtIndex:0];
			UDProcessInstance *scope = [pair objectAtIndex:1];
			UDTask *task = (UDTask *)[scope.definition nodeWithId:token.nodeId];
			if ([self takeErrorBoundary:errorRef task:task token:token instance:scope]) {
				taken = YES;
			}
		}
		if (!taken) {
			[self failInstance:root error:[NSError errorWithDomain:UDWorkflowErrorDomain
			                                                  code:UDWorkflowErrorNoPath
			                                              userInfo:@{
				NSLocalizedDescriptionKey: @"no error boundary",
				UDWorkflowErrorRefKey: errorRef ?: @"*"
			}]];
		}
		return YES;
	} committed:NULL error:error];
}

- (UDProcessInstance *)instanceWithId:(NSString *)instanceId error:(NSError **)error
{
	return [self loadInstance:instanceId error:error];
}

@end

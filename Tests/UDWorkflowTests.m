#import <XCTest/XCTest.h>
#import "UDWorkflow.h"

@interface UDMapHandler : NSObject <UDServiceTaskHandler>
@property (nonatomic, strong) NSMutableDictionary *results;
@property (nonatomic, strong) NSMutableSet *failures;
/* Invocations taken and never finished, as if the process died mid-call. */
@property (nonatomic) BOOL drops;
@property (nonatomic, strong) NSMutableArray *jobIds;
@end

@implementation UDMapHandler
- (instancetype)init
{
	self = [super init];
	if (self) {
		_results = [NSMutableDictionary dictionary];
		_failures = [NSMutableSet set];
		_jobIds = [NSMutableArray array];
	}
	return self;
}
- (void)performInvocation:(UDServiceInvocation *)invocation
{
	@synchronized (self) {
		[self.jobIds addObject:invocation.jobId];
	}
	if (self.drops) {
		return;
	}
	if ([self.failures containsObject:invocation.actionKey]) {
		NSError *error = [NSError errorWithDomain:UDWorkflowErrorDomain
		                                     code:UDWorkflowErrorHandler
		                                 userInfo:@{ UDWorkflowErrorRefKey: invocation.actionKey }];
		[invocation finishWithVariables:nil error:error];
		return;
	}
	NSDictionary *out = [self.results objectForKey:invocation.actionKey];
	[invocation finishWithVariables:out error:nil];
}
@end

@interface UDWorkflowTests : XCTestCase
@end

@implementation UDWorkflowTests

- (UDEngine *)engineWithHandler:(UDMapHandler *)handler
{
	NSError *error = nil;
	UDStore *store = [UDStore inMemoryStore:&error];
	XCTAssertNotNil(store, @"%@", error);
	UDEngine *engine = [[UDEngine alloc] initWithStore:store];
	engine.serviceHandler = handler;
	return engine;
}

- (NSURL *)temporarySQLiteURL
{
	NSString *name = [NSString stringWithFormat:@"udworkflow-%@.sqlite",
		[[NSUUID UUID] UUIDString]];
	return [NSURL fileURLWithPath:
		[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (UDEngine *)SQLiteEngineAtURL:(NSURL *)url handler:(UDMapHandler *)handler
{
	NSError *error = nil;
	UDStore *store = [UDStore SQLiteStoreAtURL:url error:&error];
	XCTAssertNotNil(store, @"%@", error);
	UDEngine *engine = [[UDEngine alloc] initWithStore:store];
	engine.serviceHandler = handler;
	return engine;
}

/* Starts the latest deployed version and waits for its service calls. */
- (UDProcessInstance *)run:(UDProcessDefinition *)definition
                    engine:(UDEngine *)engine
                 variables:(NSDictionary *)variables
{
	NSError *error = nil;
	XCTAssertTrue([engine deployDefinition:definition error:&error], @"%@", error);
	NSString *instanceId = [engine startProcess:definition.processId
	                                  variables:variables
	                                      error:&error];
	XCTAssertNotNil(instanceId, @"%@", error);
	if (instanceId == nil) {
		return nil;
	}
	XCTAssertTrue([engine waitUntilSettled:instanceId timeout:10.0]);
	UDProcessInstance *instance = [engine instanceWithId:instanceId error:&error];
	XCTAssertNotNil(instance, @"%@", error);
	return instance;
}

/* Polls the store: timers are waits, not work, so there is nothing to
 * settle on. */
- (UDProcessInstance *)instance:(NSString *)instanceId
                         engine:(UDEngine *)engine
             completesWithin:(NSTimeInterval)seconds
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
	UDProcessInstance *instance = nil;
	do {
		[engine waitUntilSettled:instanceId timeout:1.0];
		instance = [engine instanceWithId:instanceId error:NULL];
		if (instance.isCompleted || instance.isFailed) {
			break;
		}
		[NSThread sleepForTimeInterval:0.02];
	} while ([deadline timeIntervalSinceNow] > 0);
	return instance;
}

- (UDToken *)waitingUserToken:(UDProcessInstance *)instance
{
	for (UDToken *token in instance.tokens) {
		UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
		if (token.state == UDTokenStateWaiting
		    && [node isKindOfClass:[UDTask class]]
		    && [(UDTask *)node kind] == UDTaskKindUser) {
			return token;
		}
	}
	return nil;
}

- (UDProcessDefinition *)approvalDefinition
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"approval" version:1];
	[[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"]
		addServiceTask:@"book" action:@"book"] addEnd:@"end"];
	[[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"book"]
		connect:@"book" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

#pragma mark - Gateways, tasks, events

- (void)testExclusiveAutoApprove
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"xor" version:1];
	[[[[b addStart:@"start"] addExclusive:@"g" defaultFlow:@"low"] addServiceTask:@"hi" action:@"hi"]
		addServiceTask:@"lo" action:@"lo"];
	[b addEnd:@"end"];
	[b connect:@"start" to:@"g"];
	[b connect:@"g" to:@"hi" key:@"amount" op:UDComparisonOpGreater value:@1000];
	[b connect:@"g" to:@"lo" flowId:@"low"];
	[[b connect:@"hi" to:@"end"] connect:@"lo" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);

	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"path": @"lo" } forKey:@"lo"];
	[h.results setObject:@{ @"path": @"hi" } forKey:@"hi"];
	UDProcessInstance *inst = [self run:def
	                             engine:[self engineWithHandler:h]
	                          variables:@{ @"amount": @50 }];
	XCTAssertTrue(inst.isCompleted);
	XCTAssertEqualObjects([inst.variables objectForKey:@"path"], @"lo");
}

- (void)testParallelJoin
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"and" version:1];
	[[[[b addStart:@"start"] addParallel:@"fork"] addServiceTask:@"a" action:@"a"]
		addServiceTask:@"b" action:@"b"];
	[[b addParallel:@"join"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"a"] connect:@"fork" to:@"b"];
	[[b connect:@"a" to:@"join"] connect:@"b" to:@"join"];
	[b connect:@"join" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);

	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"a": @YES } forKey:@"a"];
	[h.results setObject:@{ @"b": @YES } forKey:@"b"];
	UDProcessInstance *inst = [self run:def engine:[self engineWithHandler:h] variables:nil];
	XCTAssertTrue(inst.isCompleted, @"%@", inst.error);
	XCTAssertTrue([[inst.variables objectForKey:@"a"] boolValue]);
	XCTAssertTrue([[inst.variables objectForKey:@"b"] boolValue]);
}

- (void)testInclusiveTwoBranches
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"or" version:1];
	[[[[b addStart:@"start"] addInclusive:@"split" defaultFlow:@"d"]
		addServiceTask:@"audit" action:@"audit"] addServiceTask:@"ship" action:@"ship"];
	[[b addInclusive:@"join" defaultFlow:nil] addEnd:@"end"];
	[b connect:@"start" to:@"split"];
	[b connect:@"split" to:@"audit" key:@"audit" op:UDComparisonOpEqual value:@YES];
	[b connect:@"split" to:@"ship" key:@"ship" op:UDComparisonOpEqual value:@YES];
	[b connect:@"split" to:@"ship" flowId:@"d"];
	[[b connect:@"audit" to:@"join"] connect:@"ship" to:@"join"];
	[b connect:@"join" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);

	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"audited": @YES } forKey:@"audit"];
	[h.results setObject:@{ @"shipped": @YES } forKey:@"ship"];
	UDProcessInstance *inst = [self run:def
	                             engine:[self engineWithHandler:h]
	                          variables:@{ @"audit": @YES, @"ship": @YES }];
	XCTAssertTrue(inst.isCompleted, @"%@", inst.error);
	XCTAssertTrue([[inst.variables objectForKey:@"audited"] boolValue]);
	XCTAssertTrue([[inst.variables objectForKey:@"shipped"] boolValue]);
}

- (void)testMessageAndTimer
{
	NSError *error = nil;
	UDEngine *engine = [self engineWithHandler:nil];
	UDDefinitionBuilder *tb = [UDDefinitionBuilder process:@"t" version:1];
	[[[tb addStart:@"start"] addTimerCatch:@"wait" duration:0] addEnd:@"end"];
	[[tb connect:@"start" to:@"wait"] connect:@"wait" to:@"end"];
	UDProcessInstance *timed = [self run:[tb build:&error] engine:engine variables:nil];
	XCTAssertTrue(timed.isCompleted, @"%@", timed.error);

	UDDefinitionBuilder *mb = [UDDefinitionBuilder process:@"m" version:1];
	[[[mb addStart:@"start"] addMessageCatch:@"go" message:@"go"] addEnd:@"end"];
	[[mb connect:@"start" to:@"go"] connect:@"go" to:@"end"];
	UDProcessInstance *waiting = [self run:[mb build:&error] engine:engine variables:nil];
	XCTAssertFalse(waiting.isCompleted);
	XCTAssertTrue([engine deliverMessage:@"go" payload:@{ @"ok": @YES }
	                          instanceId:waiting.instanceId error:&error], @"%@", error);
	UDProcessInstance *done = [engine instanceWithId:waiting.instanceId error:&error];
	XCTAssertTrue(done.isCompleted);
	XCTAssertEqualObjects([done.variables objectForKey:@"ok"], @YES);
}

- (UDProcessDefinition *)raceDefinition:(NSTimeInterval)timeout
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"egw" version:1];
	[[[[b addStart:@"start"] addEventBased:@"choice"]
		addMessageCatch:@"msg" message:@"arrive"]
		addTimerCatch:@"timeout" duration:timeout];
	[[b addEnd:@"arrived"] addEnd:@"timedOut"];
	[b connect:@"start" to:@"choice"];
	[[b connect:@"choice" to:@"msg"] connect:@"choice" to:@"timeout"];
	[[b connect:@"msg" to:@"arrived"] connect:@"timeout" to:@"timedOut"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testEventBasedGatewayMessageWins
{
	NSError *error = nil;
	UDEngine *engine = [self engineWithHandler:nil];
	UDProcessInstance *inst = [self run:[self raceDefinition:30] engine:engine variables:nil];
	XCTAssertFalse(inst.isCompleted);
	XCTAssertTrue([engine deliverMessage:@"arrive" payload:nil
	                          instanceId:inst.instanceId error:&error], @"%@", error);
	UDProcessInstance *done = [engine instanceWithId:inst.instanceId error:&error];
	XCTAssertTrue(done.isCompleted, @"%@", done.error);
	/* The losing timer's job went with the token. */
	XCTAssertEqual([[engine.store jobsOfKind:UDJobKindTimer dueBefore:nil limit:0] count],
		(NSUInteger)0);
}

- (void)testEventBasedGatewayTimerWins
{
	NSError *error = nil;
	UDEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine openWithError:&error], @"%@", error);
	UDProcessInstance *inst = [self run:[self raceDefinition:0.2] engine:engine variables:nil];
	XCTAssertFalse(inst.isCompleted);
	UDProcessInstance *done = [self instance:inst.instanceId
	                                  engine:engine
	                         completesWithin:5.0];
	XCTAssertTrue(done.isCompleted, @"%@", done.error);
	XCTAssertFalse([engine deliverMessage:@"arrive" payload:nil
	                           instanceId:inst.instanceId error:&error]);
}

- (void)testErrorBoundary
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"err" version:1];
	[[[[b addStart:@"start"] addServiceTask:@"work" action:@"boom"]
		addBoundaryError:@"onerr" onTask:@"work" errorRef:@"boom" interrupting:YES]
		addEnd:@"ok"];
	[b addEnd:@"failed"];
	[b connect:@"start" to:@"work"];
	[b connect:@"work" to:@"ok"];
	[b connect:@"onerr" to:@"failed"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);

	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.failures addObject:@"boom"];
	UDProcessInstance *inst = [self run:def engine:[self engineWithHandler:h] variables:nil];
	XCTAssertTrue(inst.isCompleted, @"%@", inst.error);
	XCTAssertFalse(inst.isFailed);
	XCTAssertEqualObjects([inst.variables objectForKey:@"errorRef"], @"boom");
}

- (void)testUnhandledServiceErrorFailsInstance
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"unhandled" version:1];
	[[[b addStart:@"start"] addServiceTask:@"work" action:@"boom"] addEnd:@"end"];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.failures addObject:@"boom"];
	UDEngine *engine = [self engineWithHandler:h];
	UDProcessInstance *inst = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertTrue(inst.isFailed);
	XCTAssertEqualObjects([[inst.error userInfo] objectForKey:UDWorkflowErrorRefKey], @"boom");
	XCTAssertEqualObjects([engine.store instanceIdsWithStatus:UDInstanceStatusFailed],
		@[ inst.instanceId ]);
}

- (void)testSubProcess
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"inner" version:1];
	[[inner addStart:@"s"] addServiceTask:@"step" action:@"step"];
	[inner addEnd:@"e"];
	[[inner connect:@"s" to:@"step"] connect:@"step" to:@"e"];
	UDProcessDefinition *innerDef = [inner build:&error];
	XCTAssertNotNil(innerDef, @"%@", error);

	UDDefinitionBuilder *outer = [UDDefinitionBuilder process:@"outer" version:1];
	[[[outer addStart:@"s"] addSubProcess:@"sub" name:@"sub" inner:innerDef] addEnd:@"e"];
	[[outer connect:@"s" to:@"sub"] connect:@"sub" to:@"e"];
	UDProcessDefinition *outerDef = [outer build:&error];
	XCTAssertNotNil(outerDef, @"%@", error);

	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"inner": @YES } forKey:@"step"];
	UDProcessInstance *inst = [self run:outerDef engine:[self engineWithHandler:h] variables:nil];
	XCTAssertTrue(inst.isCompleted, @"%@", inst.error);
	XCTAssertTrue([[inst.variables objectForKey:@"inner"] boolValue]);
}

- (void)testSubProcessUserTaskAddressedFromOutside
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"review" version:1];
	[[[inner addStart:@"s"] addUserTask:@"check" name:@"Check" assignee:@"qa"] addEnd:@"e"];
	[[inner connect:@"s" to:@"check"] connect:@"check" to:@"e"];
	UDDefinitionBuilder *outer = [UDDefinitionBuilder process:@"release" version:1];
	[[[outer addStart:@"s"] addSubProcess:@"sub" name:@"sub" inner:[inner build:&error]]
		addEnd:@"e"];
	[[outer connect:@"s" to:@"sub"] connect:@"sub" to:@"e"];
	UDEngine *engine = [self engineWithHandler:nil];
	UDProcessInstance *inst = [self run:[outer build:&error] engine:engine variables:nil];
	XCTAssertFalse(inst.isCompleted);
	UDProcessInstance *child = [[inst.children allValues] lastObject];
	UDToken *check = [self waitingUserToken:child];
	XCTAssertNotNil(check);
	XCTAssertTrue([engine completeUserTask:check.tokenId
	                            instanceId:inst.instanceId
	                             variables:@{ @"checked": @YES }
	                                 error:&error], @"%@", error);
	UDProcessInstance *done = [engine instanceWithId:inst.instanceId error:&error];
	XCTAssertTrue(done.isCompleted, @"%@", done.error);
	XCTAssertEqualObjects([done.variables objectForKey:@"checked"], @YES);
}

- (void)testCorrelationKey
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"corr" version:1];
	[[[b addStart:@"start"] addMessageCatch:@"pay" message:@"paid"] addEnd:@"end"];
	[[b connect:@"start" to:@"pay"] connect:@"pay" to:@"end"];
	UDEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine deployDefinition:[b build:&error] error:&error], @"%@", error);
	NSString *other = [engine startProcess:@"corr" variables:nil
	                        correlationKeys:@{ @"orderId": @"SO-8" } error:&error];
	NSString *mine = [engine startProcess:@"corr" variables:nil
	                       correlationKeys:@{ @"orderId": @"SO-9" } error:&error];
	XCTAssertNotNil(mine, @"%@", error);
	XCTAssertTrue([engine deliverMessage:@"paid"
	                             payload:@{ @"paid": @YES }
	                      correlationKey:@"orderId"
	                               value:@"SO-9"
	                               error:&error], @"%@", error);
	XCTAssertTrue([engine instanceWithId:mine error:&error].isCompleted);
	XCTAssertFalse([engine instanceWithId:other error:&error].isCompleted);
	/* A finished instance no longer correlates. */
	XCTAssertEqual([[engine.store instanceIdsForCorrelationKey:@"orderId" value:@"SO-9"] count],
		(NSUInteger)0);
}

- (void)testVariablesMustBePropertyLists
{
	NSError *error = nil;
	UDEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine deployDefinition:[self approvalDefinition] error:&error]);
	XCTAssertNil([engine startProcess:@"approval"
	                        variables:@{ @"who": [NSObject new] }
	                            error:&error]);
	XCTAssertEqual([error code], (NSInteger)UDWorkflowErrorInvalidState);
}

- (void)testRedeployingChangedVersionFails
{
	NSError *error = nil;
	UDEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine deployDefinition:[self approvalDefinition] error:&error]);
	XCTAssertTrue([engine deployDefinition:[self approvalDefinition] error:&error],
		@"the same content again is fine: %@", error);
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"approval" version:1];
	[[b addStart:@"start"] addEnd:@"end"];
	[b connect:@"start" to:@"end"];
	XCTAssertFalse([engine deployDefinition:[b build:&error] error:&error]);
}

#pragma mark - Durability

- (void)testUserTaskSurvivesRestart
{
	NSError *error = nil;
	NSURL *url = [self temporarySQLiteURL];
	NSString *instanceId = nil;
	@autoreleasepool {
		UDEngine *first = [self SQLiteEngineAtURL:url handler:nil];
		XCTAssertTrue([first deployDefinition:[self approvalDefinition] error:&error]);
		instanceId = [first startProcess:@"approval" variables:@{ @"amount": @2500 } error:&error];
		XCTAssertNotNil(instanceId, @"%@", error);
		[first close];
	}

	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"booked": @YES } forKey:@"book"];
	UDEngine *second = [self SQLiteEngineAtURL:url handler:h];
	XCTAssertTrue([second deployDefinition:[self approvalDefinition] error:&error]);
	XCTAssertTrue([second openWithError:&error], @"%@", error);
	UDProcessInstance *restored = [second instanceWithId:instanceId error:&error];
	XCTAssertEqualObjects([restored.variables objectForKey:@"amount"], @2500);
	UDToken *approve = [self waitingUserToken:restored];
	XCTAssertEqualObjects(approve.nodeId, @"approve");
	XCTAssertTrue([second completeUserTask:approve.tokenId
	                            instanceId:instanceId
	                             variables:@{ @"approved": @YES }
	                                 error:&error], @"%@", error);
	XCTAssertTrue([second waitUntilSettled:instanceId timeout:10.0]);
	UDProcessInstance *done = [second instanceWithId:instanceId error:&error];
	XCTAssertTrue(done.isCompleted, @"%@", done.error);
	XCTAssertEqualObjects([done.variables objectForKey:@"booked"], @YES);
	[second close];
}

- (void)testServiceJobIsResentAfterRestart
{
	NSError *error = nil;
	NSURL *url = [self temporarySQLiteURL];
	UDProcessDefinition *def = [self approvalDefinition];
	NSString *instanceId = nil;
	NSString *jobId = nil;
	@autoreleasepool {
		UDMapHandler *dropping = [[UDMapHandler alloc] init];
		dropping.drops = YES;
		UDEngine *first = [self SQLiteEngineAtURL:url handler:dropping];
		XCTAssertTrue([first deployDefinition:def error:&error]);
		instanceId = [first startProcess:@"approval" variables:nil error:&error];
		UDToken *approve = [self waitingUserToken:[first instanceWithId:instanceId error:&error]];
		XCTAssertTrue([first completeUserTask:approve.tokenId
		                           instanceId:instanceId
		                            variables:nil
		                                error:&error], @"%@", error);
		/* The call went out, and the process "died" before answering. */
		XCTAssertFalse([first waitUntilSettled:instanceId timeout:0.2]);
		@synchronized (dropping) {
			jobId = [dropping.jobIds lastObject];
		}
		XCTAssertNotNil(jobId);
		[first close];
	}

	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"booked": @YES } forKey:@"book"];
	UDEngine *second = [self SQLiteEngineAtURL:url handler:h];
	XCTAssertTrue([second deployDefinition:def error:&error]);
	XCTAssertTrue([second openWithError:&error], @"%@", error);
	XCTAssertTrue([second waitUntilSettled:instanceId timeout:10.0]);
	UDProcessInstance *done = [second instanceWithId:instanceId error:&error];
	XCTAssertTrue(done.isCompleted, @"%@", done.error);
	/* The same job, so the handler can tell it is a repeat. */
	XCTAssertEqualObjects(h.jobIds, @[ jobId ]);
	XCTAssertEqual([[second.store jobsOfKind:UDJobKindService dueBefore:nil limit:0] count],
		(NSUInteger)0);
	[second close];
}

- (void)testTimerKeepsItsDueTimeAcrossRestart
{
	NSError *error = nil;
	NSURL *url = [self temporarySQLiteURL];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"sleepy" version:1];
	[[[b addStart:@"start"] addTimerCatch:@"nap" duration:1.0] addEnd:@"end"];
	[[b connect:@"start" to:@"nap"] connect:@"nap" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	NSString *instanceId = nil;
	NSDate *due = nil;
	@autoreleasepool {
		UDEngine *first = [self SQLiteEngineAtURL:url handler:nil];
		XCTAssertTrue([first deployDefinition:def error:&error]);
		instanceId = [first startProcess:@"sleepy" variables:nil error:&error];
		due = [first.store earliestTimerDue];
		XCTAssertNotNil(due);
		[first close];
	}
	[NSThread sleepForTimeInterval:0.5];

	UDEngine *second = [self SQLiteEngineAtURL:url handler:nil];
	XCTAssertTrue([second deployDefinition:def error:&error]);
	XCTAssertEqualWithAccuracy([[second.store earliestTimerDue] timeIntervalSince1970],
		[due timeIntervalSince1970], 0.01);
	XCTAssertTrue([second openWithError:&error], @"%@", error);
	UDProcessInstance *done = [self instance:instanceId engine:second completesWithin:5.0];
	XCTAssertTrue(done.isCompleted, @"%@", done.error);
	/* Fired at the stored due time, not a full duration after the restart. */
	XCTAssertLessThan([[NSDate date] timeIntervalSinceDate:due], 0.9);
	[second close];
}

- (void)testCallbacksMayCallBackIntoTheEngine
{
	NSError *error = nil;
	UDEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine deployDefinition:[self approvalDefinition] error:&error]);
	NSString *instanceId = [engine startProcess:@"approval" variables:nil error:&error];
	/* On a callback queue, as a delegate would be: no deadlock. */
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	__block BOOL completed = NO;
	dispatch_async(engine.callbackQueue, ^{
		UDProcessInstance *inst = [engine instanceWithId:instanceId error:NULL];
		UDToken *approve = [self waitingUserToken:inst];
		completed = [engine completeUserTask:approve.tokenId
		                          instanceId:instanceId
		                           variables:nil
		                               error:NULL];
		dispatch_semaphore_signal(done);
	});
	XCTAssertEqual(dispatch_semaphore_wait(done,
		dispatch_time(DISPATCH_TIME_NOW, 5 * (int64_t)NSEC_PER_SEC)), 0L);
	UDDispatchRelease(done);
	XCTAssertTrue(completed);
}

#pragma mark - BPMN

- (void)testBpmnRoundTripXor
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"rt" name:@"RT" version:2];
	[[[[b addStart:@"start"] addExclusive:@"g" defaultFlow:@"d"] addEnd:@"a"] addEnd:@"b"];
	[b connect:@"start" to:@"g"];
	[b connect:@"g" to:@"a" key:@"ok" op:UDComparisonOpEqual value:@YES];
	[b connect:@"g" to:@"b" flowId:@"d"];
	[b setBoundsFor:@"start" x:10 y:20 width:36 height:36];
	UDProcessDefinition *def = [b build:&error];
	NSString *xml = [UDBpmnWriter XMLStringFromDefinition:def error:&error];
	XCTAssertNotNil(xml, @"%@", error);
	UDProcessDefinition *again = [UDBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(again, @"%@", error);
	XCTAssertEqual([again.nodes count], [def.nodes count]);
	XCTAssertEqual([again.flows count], [def.flows count]);
	XCTAssertEqualWithAccuracy([again startEvent].boundsX, 10.0, 0.01);
}

- (void)testComparisonExpression
{
	NSError *error = nil;
	UDComparisonCondition *c =
		[UDComparisonCondition conditionWithExpression:@"amount > 10" error:&error];
	XCTAssertNotNil(c, @"%@", error);
	XCTAssertTrue([c evaluateWithVariables:@{ @"amount": @11 } error:NULL]);
	XCTAssertFalse([c evaluateWithVariables:@{ @"amount": @3 } error:NULL]);
	XCTAssertEqualObjects([c expressionString], @"amount > 10");
}

@end

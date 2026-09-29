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
	XCTAssertTrue(([engine.repositoryService deployDefinition:definition error:&error] != nil), @"%@", error);
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"approval"];
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"xor"];
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"and"];
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"or"];
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
	UDDefinitionBuilder *tb = [UDDefinitionBuilder process:@"t"];
	[[[tb addStart:@"start"] addTimerCatch:@"wait" duration:0] addEnd:@"end"];
	[[tb connect:@"start" to:@"wait"] connect:@"wait" to:@"end"];
	UDProcessInstance *timed = [self run:[tb build:&error] engine:engine variables:nil];
	XCTAssertTrue(timed.isCompleted, @"%@", timed.error);

	UDDefinitionBuilder *mb = [UDDefinitionBuilder process:@"m"];
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"egw"];
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"err"];
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"unhandled"];
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
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"inner"];
	[[inner addStart:@"s"] addServiceTask:@"step" action:@"step"];
	[inner addEnd:@"e"];
	[[inner connect:@"s" to:@"step"] connect:@"step" to:@"e"];
	UDProcessDefinition *innerDef = [inner build:&error];
	XCTAssertNotNil(innerDef, @"%@", error);

	UDDefinitionBuilder *outer = [UDDefinitionBuilder process:@"outer"];
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
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"review"];
	[[[inner addStart:@"s"] addUserTask:@"check" name:@"Check" assignee:@"qa"] addEnd:@"e"];
	[[inner connect:@"s" to:@"check"] connect:@"check" to:@"e"];
	UDDefinitionBuilder *outer = [UDDefinitionBuilder process:@"release"];
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"corr"];
	[[[b addStart:@"start"] addMessageCatch:@"pay" message:@"paid"] addEnd:@"end"];
	[[b connect:@"start" to:@"pay"] connect:@"pay" to:@"end"];
	UDEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue(([engine.repositoryService deployDefinition:[b build:&error] error:&error] != nil), @"%@", error);
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
	XCTAssertTrue(([engine.repositoryService deployDefinition:[self approvalDefinition] error:&error] != nil));
	XCTAssertNil([engine startProcess:@"approval"
	                        variables:@{ @"who": [NSObject new] }
	                            error:&error]);
	XCTAssertEqual([error code], (NSInteger)UDWorkflowErrorInvalidState);
}

- (void)testDeploymentsAreVersioned
{
	NSError *error = nil;
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"booked": @YES } forKey:@"book"];
	UDEngine *engine = [self engineWithHandler:h];
	UDRepositoryService *repository = engine.repositoryService;
	UDDeployment *first = [repository deployDefinition:[self approvalDefinition] error:&error];
	XCTAssertNotNil(first, @"%@", error);
	XCTAssertEqual([[first.definitions lastObject] version], (NSInteger)1);
	NSString *running = [engine startProcess:@"approval" variables:nil error:&error];

	/* The same content again is not a new version. */
	UDDeployment *again = [repository deployDefinition:[self approvalDefinition] error:&error];
	XCTAssertEqualObjects(again.deploymentId, first.deploymentId);

	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"approval"];
	[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"] addEnd:@"end"];
	[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"end"];
	UDDeployment *second = [repository deployDefinition:[b build:&error] error:&error];
	XCTAssertEqual([[second.definitions lastObject] version], (NSInteger)2);
	XCTAssertEqual([[repository latestDefinitionForKey:@"approval" error:&error] version],
		(NSInteger)2);

	/* The instance started on version 1 finishes on version 1: it still
	 * reaches the booking service, which version 2 no longer has. */
	UDToken *approve = [self waitingUserToken:[engine instanceWithId:running error:&error]];
	XCTAssertTrue([engine completeUserTask:approve.tokenId instanceId:running
	                             variables:nil error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:running timeout:10.0]);
	UDProcessInstance *done = [engine instanceWithId:running error:&error];
	XCTAssertTrue(done.isCompleted, @"%@", done.error);
	XCTAssertEqual(done.definition.version, (NSInteger)1);
	XCTAssertEqualObjects([done.variables objectForKey:@"booked"], @YES);
}

- (void)testBrokenDeploymentStoresNothing
{
	NSError *error = nil;
	UDEngine *engine = [self engineWithHandler:nil];
	NSString *xml =
		@"<definitions xmlns=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" id=\"d\">"
		 @"<process id=\"calls\" isExecutable=\"true\">"
		 @"<startEvent id=\"s\"/><callActivity id=\"other\" calledElement=\"x\"/><endEvent id=\"e\"/>"
		 @"<sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"other\"/>"
		 @"<sequenceFlow id=\"f2\" sourceRef=\"other\" targetRef=\"e\"/>"
		 @"</process></definitions>";
	XCTAssertNil([engine.repositoryService
		deployResources:@{ @"calls.bpmn": [xml dataUsingEncoding:NSUTF8StringEncoding] }
		           name:@"calls"
		filterDuplicates:YES
		          error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"callActivity"].location
		!= NSNotFound, @"%@", error);
	XCTAssertNil([engine.repositoryService latestDefinitionForKey:@"calls" error:NULL]);
}

#pragma mark - Durability

- (void)testUserTaskSurvivesRestart
{
	NSError *error = nil;
	NSURL *url = [self temporarySQLiteURL];
	NSString *instanceId = nil;
	@autoreleasepool {
		UDEngine *first = [self SQLiteEngineAtURL:url handler:nil];
		XCTAssertTrue(([first.repositoryService deployDefinition:[self approvalDefinition] error:&error] != nil));
		instanceId = [first startProcess:@"approval" variables:@{ @"amount": @2500 } error:&error];
		XCTAssertNotNil(instanceId, @"%@", error);
		[first close];
	}

	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"booked": @YES } forKey:@"book"];
	UDEngine *second = [self SQLiteEngineAtURL:url handler:h];
	/* Nothing deployed: the definition comes back from the store. */
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
		XCTAssertTrue(([first.repositoryService deployDefinition:def error:&error] != nil));
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
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"sleepy"];
	[[[b addStart:@"start"] addTimerCatch:@"nap" duration:1.0] addEnd:@"end"];
	[[b connect:@"start" to:@"nap"] connect:@"nap" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	NSString *instanceId = nil;
	NSDate *due = nil;
	@autoreleasepool {
		UDEngine *first = [self SQLiteEngineAtURL:url handler:nil];
		XCTAssertTrue(([first.repositoryService deployDefinition:def error:&error] != nil));
		instanceId = [first startProcess:@"sleepy" variables:nil error:&error];
		due = [first.store earliestTimerDue];
		XCTAssertNotNil(due);
		[first close];
	}
	[NSThread sleepForTimeInterval:0.5];

	UDEngine *second = [self SQLiteEngineAtURL:url handler:nil];
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
	XCTAssertTrue(([engine.repositoryService deployDefinition:[self approvalDefinition] error:&error] != nil));
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

- (void)assertNode:(UDFlowNode *)a matches:(UDFlowNode *)b
{
	XCTAssertEqualObjects(NSStringFromClass([a class]), NSStringFromClass([b class]), @"%@", a.elementId);
	XCTAssertEqualObjects(a.name, b.name, @"%@", a.elementId);
	XCTAssertEqualObjects([NSSet setWithArray:a.incomingFlowIds],
		[NSSet setWithArray:b.incomingFlowIds], @"%@", a.elementId);
	XCTAssertEqualObjects([NSSet setWithArray:a.outgoingFlowIds],
		[NSSet setWithArray:b.outgoingFlowIds], @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsX, b.boundsX, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsY, b.boundsY, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsWidth, b.boundsWidth, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsHeight, b.boundsHeight, 0.001, @"%@", a.elementId);
	if ([a isKindOfClass:[UDEvent class]]) {
		UDEvent *x = (UDEvent *)a, *y = (UDEvent *)b;
		XCTAssertEqual(x.kind, y.kind, @"%@", a.elementId);
		XCTAssertEqual(x.trigger, y.trigger, @"%@", a.elementId);
		if (x.trigger == UDEventTriggerMessage) {
			XCTAssertEqualObjects(x.messageName, y.messageName, @"%@", a.elementId);
		}
		if (x.trigger == UDEventTriggerError) {
			XCTAssertEqualObjects(x.errorRef, y.errorRef, @"%@", a.elementId);
		}
		XCTAssertEqualWithAccuracy(x.timerDuration, y.timerDuration, 0.001, @"%@", a.elementId);
		XCTAssertEqualObjects(x.attachedToId, y.attachedToId, @"%@", a.elementId);
		if (x.kind == UDEventKindBoundary) {
			XCTAssertEqual(x.isInterrupting, y.isInterrupting, @"%@", a.elementId);
		}
	} else if ([a isKindOfClass:[UDTask class]]) {
		UDTask *x = (UDTask *)a, *y = (UDTask *)b;
		XCTAssertEqual(x.kind, y.kind, @"%@", a.elementId);
		XCTAssertEqualObjects(x.assignee, y.assignee, @"%@", a.elementId);
		if (x.kind != UDTaskKindUser) {
			XCTAssertEqualObjects(x.actionKey, y.actionKey, @"%@", a.elementId);
		}
	} else if ([a isKindOfClass:[UDGateway class]]) {
		XCTAssertEqual([(UDGateway *)a kind], [(UDGateway *)b kind], @"%@", a.elementId);
		XCTAssertEqualObjects([(UDGateway *)a defaultFlowId], [(UDGateway *)b defaultFlowId],
			@"%@", a.elementId);
	} else if ([a isKindOfClass:[UDSubProcess class]]) {
		[self assertDefinition:[(UDSubProcess *)a innerDefinition]
		               matches:[(UDSubProcess *)b innerDefinition]];
	}
}

- (void)assertDefinition:(UDProcessDefinition *)a matches:(UDProcessDefinition *)b
{
	XCTAssertEqualObjects(a.processId, b.processId);
	XCTAssertEqualObjects(a.name, b.name);
	XCTAssertEqualObjects([NSSet setWithArray:[a.nodes allKeys]],
		[NSSet setWithArray:[b.nodes allKeys]]);
	XCTAssertEqualObjects([NSSet setWithArray:[a.flows allKeys]],
		[NSSet setWithArray:[b.flows allKeys]]);
	for (NSString *nodeId in a.nodes) {
		UDFlowNode *other = [b nodeWithId:nodeId];
		if (other != nil) {
			[self assertNode:[a nodeWithId:nodeId] matches:other];
		}
	}
	for (NSString *flowId in a.flows) {
		UDSequenceFlow *x = [a flowWithId:flowId];
		UDSequenceFlow *y = [b flowWithId:flowId];
		XCTAssertEqualObjects(x.sourceId, y.sourceId, @"%@", flowId);
		XCTAssertEqualObjects(x.targetId, y.targetId, @"%@", flowId);
		XCTAssertEqualObjects(x.name, y.name, @"%@", flowId);
		XCTAssertEqualObjects([x.condition expressionString], [y.condition expressionString],
			@"%@", flowId);
	}
}

/* Every construct the engine runs, subprocess included. */
- (UDProcessDefinition *)everyConstruct
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"manual" name:@"Manual review"];
	[[[[[inner addStart:@"ms"] addInclusive:@"or1" defaultFlow:@"f_or_b"]
		addUserTask:@"review" name:@"Review" assignee:@"clerk"]
		addUserTask:@"review2" name:@"Second look" assignee:nil]
		addInclusive:@"or2" defaultFlow:nil];
	[[inner addEnd:@"me"] addEnd:@"reminded"];
	[inner addBoundaryTimer:@"remind" onTask:@"review" duration:90 interrupting:NO];
	[inner connect:@"ms" to:@"or1"];
	[inner connect:@"or1" to:@"review" flowId:@"f_or_a"
	     condition:[UDComparisonCondition key:@"urgent" equals:@YES]];
	[inner connect:@"or1" to:@"review2" flowId:@"f_or_b"];
	[[[inner connect:@"review" to:@"or2"] connect:@"review2" to:@"or2"] connect:@"or2" to:@"me"];
	[inner connect:@"remind" to:@"reminded"];
	[inner setBoundsFor:@"review" x:40 y:30 width:100 height:80];
	UDProcessDefinition *manual = [inner build:&error];
	XCTAssertNotNil(manual, @"%@", error);

	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"everything" name:@"Everything"];
	[[[[b addStart:@"start"] addUserTask:@"fill" name:@"Fill in" assignee:@"requester"]
		addParallel:@"split"] addServiceTask:@"check" action:@"credit.check"];
	[[[b addScriptTask:@"audit" action:@"audit.log"] addParallel:@"join"]
		addExclusive:@"choice" defaultFlow:@"toManual"];
	[[[b addIntermediateThrow:@"milestone"] addSubProcess:@"manual" name:@"Manual review" inner:manual]
		addEventBased:@"race"];
	[[[b addMessageCatch:@"paid" message:@"Payment received"] addMessageThrow:@"notify" message:@"shipped"]
		addMessageEnd:@"done" message:@"closed"];
	[[[b addTimerCatch:@"timeout" duration:7 * 86400] addEnd:@"late"] addEnd:@"badCredit"];
	[[b addEnd:@"anyError"] addEnd:@"cancelled"];
	[b addBoundaryError:@"onBad" onTask:@"check" errorRef:@"BAD_CREDIT" interrupting:YES];
	[b addBoundaryError:@"onAny" onTask:@"audit" errorRef:nil interrupting:YES];
	[b addBoundaryMessage:@"onCancel" onTask:@"fill" message:@"cancel" interrupting:YES];
	[[b connect:@"start" to:@"fill"] connect:@"fill" to:@"split"];
	[[b connect:@"split" to:@"check"] connect:@"split" to:@"audit"];
	[[b connect:@"check" to:@"join"] connect:@"audit" to:@"join"];
	[b connect:@"join" to:@"choice"];
	[b connect:@"choice" to:@"milestone" key:@"amount" op:UDComparisonOpLessOrEqual value:@1000];
	[b connect:@"choice" to:@"manual" flowId:@"toManual"];
	[[b connect:@"milestone" to:@"race"] connect:@"manual" to:@"race"];
	[[b connect:@"race" to:@"paid"] connect:@"race" to:@"timeout"];
	[[b connect:@"paid" to:@"notify"] connect:@"notify" to:@"done"];
	[b connect:@"timeout" to:@"late"];
	[[[b connect:@"onBad" to:@"badCredit"] connect:@"onAny" to:@"anyError"]
		connect:@"onCancel" to:@"cancelled"];
	[b setName:@"Request received" forElement:@"start"];
	[b setName:@"needs review" forElement:@"toManual"];
	[b setBoundsFor:@"start" x:10 y:20 width:36 height:36];
	[b setBoundsFor:@"fill" x:100 y:8 width:100 height:80];
	[b setBoundsFor:@"manual" x:300 y:200 width:350.5 height:200];
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testBpmnRoundTripsEveryConstruct
{
	NSError *error = nil;
	UDProcessDefinition *definition = [self everyConstruct];
	NSString *xml = [UDBpmnWriter XMLStringFromDefinition:definition error:&error];
	XCTAssertNotNil(xml, @"%@", error);
	XCTAssertTrue([xml rangeOfString:@"<bpmn:timeDuration xsi:type=\"bpmn:tFormalExpression\">P7D</bpmn:timeDuration>"].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"PT1M30S"].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"camunda:topic=\"credit.check\""].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"<bpmndi:BPMNShape"].location != NSNotFound);
	UDProcessDefinition *again = [UDBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(again, @"%@\n%@", error, xml);
	[self assertDefinition:definition matches:again];
	/* Writing what was read gives the same document. */
	XCTAssertEqualObjects([UDBpmnWriter XMLStringFromDefinition:again error:&error], xml);
}

static NSString * const UDModelerInvoice =
	@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	 @"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
	 @"xmlns:bpmndi=\"http://www.omg.org/spec/BPMN/20100524/DI\" "
	 @"xmlns:dc=\"http://www.omg.org/spec/DD/20100524/DC\" "
	 @"xmlns:di=\"http://www.omg.org/spec/DD/20100524/DI\" "
	 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" "
	 @"xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
	 @"xmlns:modeler=\"http://camunda.org/schema/modeler/1.0\" id=\"Definitions_1\" "
	 @"targetNamespace=\"http://bpmn.io/schema/bpmn\" exporter=\"Camunda Modeler\" "
	 @"exporterVersion=\"5.20.0\" modeler:executionPlatform=\"Camunda Platform\" "
	 @"modeler:executionPlatformVersion=\"7.20.0\">\n"
	 @"  <bpmn:process id=\"invoice\" name=\"Invoice\" isExecutable=\"true\" camunda:historyTimeToLive=\"180\">\n"
	 @"    <bpmn:documentation>Pays invoices.</bpmn:documentation>\n"
	 @"    <bpmn:startEvent id=\"StartEvent_1\" name=\"Invoice received\">\n"
	 @"      <bpmn:outgoing>Flow_1</bpmn:outgoing>\n"
	 @"    </bpmn:startEvent>\n"
	 @"    <bpmn:exclusiveGateway id=\"Gateway_amount\" name=\"Amount?\" default=\"Flow_small\">\n"
	 @"      <bpmn:incoming>Flow_1</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_big</bpmn:outgoing>\n"
	 @"      <bpmn:outgoing>Flow_small</bpmn:outgoing>\n"
	 @"    </bpmn:exclusiveGateway>\n"
	 @"    <bpmn:userTask id=\"Task_approve\" name=\"Approve invoice\" camunda:assignee=\"demo\" camunda:candidateGroups=\"accounting\">\n"
	 @"      <bpmn:extensionElements>\n"
	 @"        <camunda:properties><camunda:property name=\"sla\" value=\"2d\" /></camunda:properties>\n"
	 @"      </bpmn:extensionElements>\n"
	 @"      <bpmn:incoming>Flow_big</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_approved</bpmn:outgoing>\n"
	 @"    </bpmn:userTask>\n"
	 @"    <bpmn:boundaryEvent id=\"Event_reminder\" name=\"5 minutes\" cancelActivity=\"false\" attachedToRef=\"Task_approve\">\n"
	 @"      <bpmn:outgoing>Flow_remind</bpmn:outgoing>\n"
	 @"      <bpmn:timerEventDefinition id=\"TimerEventDefinition_1\">\n"
	 @"        <bpmn:timeDuration xsi:type=\"bpmn:tFormalExpression\">PT5M</bpmn:timeDuration>\n"
	 @"      </bpmn:timerEventDefinition>\n"
	 @"    </bpmn:boundaryEvent>\n"
	 @"    <bpmn:serviceTask id=\"Task_remind\" name=\"Remind\" camunda:type=\"external\" camunda:topic=\"reminder\">\n"
	 @"      <bpmn:incoming>Flow_remind</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_reminded</bpmn:outgoing>\n"
	 @"    </bpmn:serviceTask>\n"
	 @"    <bpmn:endEvent id=\"Event_reminded\">\n"
	 @"      <bpmn:incoming>Flow_reminded</bpmn:incoming>\n"
	 @"    </bpmn:endEvent>\n"
	 @"    <bpmn:serviceTask id=\"Task_pay\" name=\"Pay\" camunda:asyncBefore=\"true\" camunda:type=\"external\" camunda:topic=\"payments.pay\">\n"
	 @"      <bpmn:incoming>Flow_small</bpmn:incoming>\n"
	 @"      <bpmn:incoming>Flow_approved</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_paid</bpmn:outgoing>\n"
	 @"    </bpmn:serviceTask>\n"
	 @"    <bpmn:intermediateCatchEvent id=\"Event_confirmed\" name=\"Bank confirmed\">\n"
	 @"      <bpmn:incoming>Flow_paid</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_done</bpmn:outgoing>\n"
	 @"      <bpmn:messageEventDefinition id=\"MessageEventDefinition_1\" messageRef=\"Message_confirm\" />\n"
	 @"    </bpmn:intermediateCatchEvent>\n"
	 @"    <bpmn:endEvent id=\"Event_paid\" name=\"Invoice paid\">\n"
	 @"      <bpmn:incoming>Flow_done</bpmn:incoming>\n"
	 @"    </bpmn:endEvent>\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_1\" sourceRef=\"StartEvent_1\" targetRef=\"Gateway_amount\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_big\" name=\"over 1000\" sourceRef=\"Gateway_amount\" targetRef=\"Task_approve\">\n"
	 @"      <bpmn:conditionExpression xsi:type=\"bpmn:tFormalExpression\">${amount &gt; 1000}</bpmn:conditionExpression>\n"
	 @"    </bpmn:sequenceFlow>\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_small\" sourceRef=\"Gateway_amount\" targetRef=\"Task_pay\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_approved\" sourceRef=\"Task_approve\" targetRef=\"Task_pay\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_remind\" sourceRef=\"Event_reminder\" targetRef=\"Task_remind\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_reminded\" sourceRef=\"Task_remind\" targetRef=\"Event_reminded\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_paid\" sourceRef=\"Task_pay\" targetRef=\"Event_confirmed\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_done\" sourceRef=\"Event_confirmed\" targetRef=\"Event_paid\" />\n"
	 @"  </bpmn:process>\n"
	 @"  <bpmn:message id=\"Message_confirm\" name=\"PaymentConfirmed\" />\n"
	 @"  <bpmndi:BPMNDiagram id=\"BPMNDiagram_1\">\n"
	 @"    <bpmndi:BPMNPlane id=\"BPMNPlane_1\" bpmnElement=\"invoice\">\n"
	 @"      <bpmndi:BPMNShape id=\"_BPMNShape_StartEvent_2\" bpmnElement=\"StartEvent_1\">\n"
	 @"        <dc:Bounds x=\"179\" y=\"99\" width=\"36\" height=\"36\" />\n"
	 @"        <bpmndi:BPMNLabel><dc:Bounds x=\"155\" y=\"142\" width=\"84\" height=\"14\" /></bpmndi:BPMNLabel>\n"
	 @"      </bpmndi:BPMNShape>\n"
	 @"      <bpmndi:BPMNShape id=\"Activity_approve_di\" bpmnElement=\"Task_approve\">\n"
	 @"        <dc:Bounds x=\"370\" y=\"77\" width=\"100\" height=\"80\" />\n"
	 @"      </bpmndi:BPMNShape>\n"
	 @"      <bpmndi:BPMNEdge id=\"Flow_1_di\" bpmnElement=\"Flow_1\">\n"
	 @"        <di:waypoint x=\"215\" y=\"117\" />\n"
	 @"        <di:waypoint x=\"265\" y=\"117\" />\n"
	 @"      </bpmndi:BPMNEdge>\n"
	 @"    </bpmndi:BPMNPlane>\n"
	 @"  </bpmndi:BPMNDiagram>\n"
	 @"</bpmn:definitions>\n";

- (void)testRunsACamundaModelerFile
{
	NSError *error = nil;
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"paid": @YES } forKey:@"payments.pay"];
	UDEngine *engine = [self engineWithHandler:h];
	UDDeployment *deployment = [engine.repositoryService
		deployResources:@{ @"invoice.bpmn": [UDModelerInvoice dataUsingEncoding:NSUTF8StringEncoding] }
		           name:@"invoice"
		filterDuplicates:YES
		          error:&error];
	XCTAssertNotNil(deployment, @"%@", error);
	UDProcessDefinition *definition = [deployment.definitions lastObject];
	XCTAssertEqualObjects(definition.name, @"Invoice");
	XCTAssertEqualObjects([[definition nodeWithId:@"StartEvent_1"] name], @"Invoice received");
	XCTAssertEqualWithAccuracy([[definition nodeWithId:@"Task_approve"] boundsX], 370.0, 0.001);
	XCTAssertEqualObjects([(UDTask *)[definition nodeWithId:@"Task_approve"] assignee], @"demo");
	XCTAssertEqualObjects([[definition flowWithId:@"Flow_big"].condition expressionString],
		@"amount > 1000");
	XCTAssertEqualObjects([(UDEvent *)[definition nodeWithId:@"Event_confirmed"] messageName],
		@"PaymentConfirmed");
	XCTAssertEqualWithAccuracy([(UDEvent *)[definition nodeWithId:@"Event_reminder"] timerDuration],
		300.0, 0.001);

	NSString *big = [engine startProcess:@"invoice" variables:@{ @"amount": @5000 } error:&error];
	UDToken *approve = [self waitingUserToken:[engine instanceWithId:big error:&error]];
	XCTAssertEqualObjects(approve.nodeId, @"Task_approve");
	XCTAssertTrue([engine completeUserTask:approve.tokenId instanceId:big
	                             variables:nil error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:big timeout:10.0]);
	XCTAssertTrue([engine deliverMessage:@"PaymentConfirmed" payload:nil
	                          instanceId:big error:&error], @"%@", error);
	UDProcessInstance *done = [engine instanceWithId:big error:&error];
	XCTAssertTrue(done.isCompleted, @"%@", done.error);
	XCTAssertEqualObjects([done.variables objectForKey:@"paid"], @YES);

	UDProcessInstance *small = [self run:definition engine:engine variables:@{ @"amount": @200 }];
	XCTAssertNil([self waitingUserToken:small], @"under 1000 skips approval");
}

- (void)testFeelComparisons
{
	NSError *error = nil;
	UDComparisonCondition *c =
		[UDComparisonCondition conditionWithExpression:@"amount > 10" error:&error];
	XCTAssertNotNil(c, @"%@", error);
	XCTAssertTrue([c evaluateWithVariables:@{ @"amount": @11 } error:NULL]);
	XCTAssertFalse([c evaluateWithVariables:@{ @"amount": @3 } error:NULL]);
	XCTAssertEqualObjects([c expressionString], @"amount > 10");

	UDComparisonCondition *approved =
		[UDComparisonCondition conditionWithExpression:@"approved = true" error:&error];
	XCTAssertTrue([approved evaluateWithVariables:@{ @"approved": @YES } error:NULL]);
	XCTAssertEqualObjects([approved expressionString], @"approved = true");
	XCTAssertEqualObjects([[UDComparisonCondition key:@"name" equals:@"x"] expressionString],
		@"name = \"x\"");
}

@end

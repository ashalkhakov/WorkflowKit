#import <XCTest/XCTest.h>
#import "UDWorkflow.h"

@interface UDMapHandler : NSObject <UDServiceTaskHandler>
@property (nonatomic, strong) NSMutableDictionary *results;
@property (nonatomic, strong) NSMutableSet *failures;
@end

@implementation UDMapHandler
- (instancetype)init
{
	self = [super init];
	if (self) {
		_results = [NSMutableDictionary dictionary];
		_failures = [NSMutableSet set];
	}
	return self;
}
- (void)performInvocation:(UDServiceInvocation *)invocation
{
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

- (UDEngine *)engineWithHandler:(UDMapHandler *)handler store:(UDMemoryStore *)store
{
	UDEngine *engine = [[UDEngine alloc] init];
	engine.serviceHandler = handler;
	engine.store = store;
	return engine;
}

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
	UDEngine *engine = [self engineWithHandler:h store:nil];
	UDProcessInstance *inst = [engine startProcess:def
	                                     variables:@{ @"amount": @50 }
	                                         error:&error];
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
	UDEngine *engine = [self engineWithHandler:h store:nil];
	UDProcessInstance *inst = [engine startProcess:def variables:nil error:&error];
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
	UDEngine *engine = [self engineWithHandler:h store:nil];
	UDProcessInstance *inst = [engine startProcess:def
	                                     variables:@{ @"audit": @YES, @"ship": @YES }
	                                         error:&error];
	XCTAssertTrue(inst.isCompleted, @"%@", inst.error);
	XCTAssertTrue([[inst.variables objectForKey:@"audited"] boolValue]);
	XCTAssertTrue([[inst.variables objectForKey:@"shipped"] boolValue]);
}

- (void)testMessageAndTimer
{
	NSError *error = nil;
	UDDefinitionBuilder *tb = [UDDefinitionBuilder process:@"t" version:1];
	[[[tb addStart:@"start"] addTimerCatch:@"wait" duration:0] addEnd:@"end"];
	[[tb connect:@"start" to:@"wait"] connect:@"wait" to:@"end"];
	UDProcessDefinition *td = [tb build:&error];
	UDEngine *engine = [self engineWithHandler:nil store:nil];
	UDProcessInstance *timed = [engine startProcess:td variables:nil error:&error];
	XCTAssertTrue(timed.isCompleted, @"%@", timed.error);

	UDDefinitionBuilder *mb = [UDDefinitionBuilder process:@"m" version:1];
	[[[mb addStart:@"start"] addMessageCatch:@"go" message:@"go"] addEnd:@"end"];
	[[mb connect:@"start" to:@"go"] connect:@"go" to:@"end"];
	UDProcessDefinition *md = [mb build:&error];
	UDProcessInstance *waiting = [engine startProcess:md variables:nil error:&error];
	XCTAssertFalse(waiting.isCompleted);
	XCTAssertTrue([engine deliverMessage:@"go" payload:@{ @"ok": @YES }
	                            instance:waiting error:&error]);
	XCTAssertTrue(waiting.isCompleted);
	XCTAssertEqualObjects([waiting.variables objectForKey:@"ok"], @YES);
}

- (void)testEventBasedGatewayMessageWins
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"egw" version:1];
	[[[[b addStart:@"start"] addEventBased:@"choice"]
		addMessageCatch:@"msg" message:@"arrive"]
		addTimerCatch:@"timeout" duration:30];
	[b addEnd:@"end"];
	[b connect:@"start" to:@"choice"];
	[[b connect:@"choice" to:@"msg"] connect:@"choice" to:@"timeout"];
	[[b connect:@"msg" to:@"end"] connect:@"timeout" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	UDEngine *engine = [self engineWithHandler:nil store:nil];
	UDProcessInstance *inst = [engine startProcess:def variables:nil error:&error];
	XCTAssertFalse(inst.isCompleted);
	XCTAssertTrue([engine deliverMessage:@"arrive" payload:nil instance:inst error:&error]);
	XCTAssertTrue(inst.isCompleted, @"%@", inst.error);
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
	UDEngine *engine = [self engineWithHandler:h store:nil];
	UDProcessInstance *inst = [engine startProcess:def variables:nil error:&error];
	XCTAssertTrue(inst.isCompleted, @"%@", inst.error);
	XCTAssertFalse(inst.isFailed);
	BOOL reachedFail = NO;
	for (UDToken *token in inst.tokens) {
		if ([token.nodeId isEqualToString:@"failed"]
		    && token.state == UDTokenStateCompleted) {
			reachedFail = YES;
		}
	}
	XCTAssertTrue(reachedFail);
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
	UDEngine *engine = [self engineWithHandler:h store:nil];
	UDProcessInstance *inst = [engine startProcess:outerDef variables:nil error:&error];
	XCTAssertTrue(inst.isCompleted, @"%@", inst.error);
	XCTAssertTrue([[inst.variables objectForKey:@"inner"] boolValue]);
}

- (void)testCorrelationKey
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"corr" version:1];
	[[[b addStart:@"start"] addMessageCatch:@"pay" message:@"paid"] addEnd:@"end"];
	[[b connect:@"start" to:@"pay"] connect:@"pay" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	UDMemoryStore *store = [[UDMemoryStore alloc] init];
	[store registerDefinition:def];
	UDEngine *engine = [self engineWithHandler:nil store:store];
	UDProcessInstance *inst = [engine startProcess:def variables:nil error:&error];
	[inst.correlationKeys setObject:@"SO-9" forKey:@"orderId"];
	XCTAssertTrue([store saveInstance:inst error:&error]);
	XCTAssertTrue([engine deliverMessage:@"paid"
	                             payload:@{ @"paid": @YES }
	                     correlationKey:@"orderId"
	                              value:@"SO-9"
	                              error:&error]);
	UDProcessInstance *again = [store loadInstance:inst.instanceId error:&error];
	XCTAssertTrue(again.isCompleted || inst.isCompleted);
}

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
	XCTAssertEqualWithAccuracy([again startEvent].boundsX, 10, 0.01);
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

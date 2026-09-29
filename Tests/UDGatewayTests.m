#import "UDWorkflowTestCase.h"

@interface UDGatewayTests : UDWorkflowTestCase
@end

@implementation UDGatewayTests

#pragma mark - Gateways

- (void)testExclusiveAutoApprove
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"xor"];
	[[[[b addStart:@"start"] addExclusive:@"g" defaultFlow:@"low"] addServiceTask:@"hi" action:@"hi"]
		addServiceTask:@"lo" action:@"lo"];
	[b addEnd:@"end"];
	[b connect:@"start" to:@"g"];
	[b connect:@"g" to:@"hi" when:@"amount > 1000"];
	[b connect:@"g" to:@"lo" flowId:@"low"];
	[[b connect:@"hi" to:@"end"] connect:@"lo" to:@"end"];
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"path": @"lo" } forKey:@"lo"];
	[h.results setObject:@{ @"path": @"hi" } forKey:@"hi"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"amount": @50 }];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"path"], @"lo");
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
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"a": @YES } forKey:@"a"];
	[h.results setObject:@{ @"b": @YES } forKey:@"b"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	NSDictionary *vars = [self variables:pid engine:engine];
	XCTAssertEqualObjects([vars objectForKey:@"a"], @YES);
	XCTAssertEqualObjects([vars objectForKey:@"b"], @YES);
}

- (void)testParallelJoinWaitsForBothUserTasks
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"review"];
	[[[[b addStart:@"start"] addParallel:@"fork"]
		addUserTask:@"legal" name:@"Legal" assignee:@"ann"]
		addUserTask:@"finance" name:@"Finance" assignee:@"bob"];
	[[[b addParallel:@"join"] addUserTask:@"sign" name:@"Sign" assignee:@"cat"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"legal"] connect:@"fork" to:@"finance"];
	[[b connect:@"legal" to:@"join"] connect:@"finance" to:@"join"];
	[[b connect:@"join" to:@"sign"] connect:@"sign" to:@"end"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"finance", @"legal" ]));
	XCTAssertEqual([[engine.taskService tasksForAssignee:@"ann"] count], (NSUInteger)1);
	[self complete:@"legal" of:pid engine:engine variables:nil];
	/* Waiting at the join is not active. */
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"finance" ]);
	[self complete:@"finance" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"sign" ]);
	/* One path again: the tree is back to the process instance alone. */
	XCTAssertEqual([[self rows:@"UDExecution" engine:engine] count], (NSUInteger)1);
	[self complete:@"sign" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"UDExecution" engine:engine] count], (NSUInteger)0);
}

- (UDProcessDefinition *)inclusiveDefinition
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"or"];
	[[[[b addStart:@"start"] addInclusive:@"split" defaultFlow:@"d"]
		addServiceTask:@"audit" action:@"audit"] addServiceTask:@"ship" action:@"ship"];
	[[b addInclusive:@"join" defaultFlow:nil] addEnd:@"end"];
	[b connect:@"start" to:@"split"];
	[b connect:@"split" to:@"audit" when:@"audit = true"];
	[b connect:@"split" to:@"ship" when:@"ship = true"];
	[b connect:@"split" to:@"ship" flowId:@"d"];
	[[b connect:@"audit" to:@"join"] connect:@"ship" to:@"join"];
	[b connect:@"join" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testInclusiveTwoBranches
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"audited": @YES } forKey:@"audit"];
	[h.results setObject:@{ @"shipped": @YES } forKey:@"ship"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self inclusiveDefinition] engine:engine
	                variables:@{ @"audit": @YES, @"ship": @YES }];
	XCTAssertTrue([self ended:pid engine:engine]);
	NSDictionary *vars = [self variables:pid engine:engine];
	XCTAssertEqualObjects([vars objectForKey:@"audited"], @YES);
	XCTAssertEqualObjects([vars objectForKey:@"shipped"], @YES);
}

- (void)testInclusiveJoinWithOneBranchTaken
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"audited": @YES } forKey:@"audit"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self inclusiveDefinition] engine:engine
	                variables:@{ @"audit": @YES, @"ship": @NO }];
	/* Nothing else can reach the join, so it does not wait for "ship". */
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertNil([[self variables:pid engine:engine] objectForKey:@"shipped"]);
}

#pragma mark - Jobs

- (void)testConcurrentCompletionsJoinOnce
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"race"];
	[[[[b addStart:@"start"] addParallel:@"fork"]
		addUserTask:@"left" name:@"Left" assignee:@"a"] addUserTask:@"right" name:@"Right" assignee:@"b"];
	[[[b addParallel:@"join"] addUserTask:@"after" name:@"After" assignee:@"c"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"left"] connect:@"fork" to:@"right"];
	[[b connect:@"left" to:@"join"] connect:@"right" to:@"join"];
	[[b connect:@"join" to:@"after"] connect:@"after" to:@"end"];
	UDProcessDefinition *definition = [b build:&error];
	UDProcessEngine *engine = [self SQLiteEngineAtURL:[self temporarySQLiteURL] handler:nil];
	[self deploy:definition engine:engine];
	__block NSUInteger conflicts = 0;
	for (int round = 0; round < 20; round++) {
		NSString *pid = [engine.runtimeService startProcessInstanceByKey:@"race"
		                                                        variables:nil error:&error].processInstanceId;
		NSArray *tasks = [engine.taskService tasksForProcessInstance:pid];
		XCTAssertEqual([tasks count], (NSUInteger)2);
		dispatch_group_t group = dispatch_group_create();
		for (UDWorkItem *task in tasks) {
			dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				NSError *completeError = nil;
				/* A lost race changed nothing: the caller tries again. */
				while (![engine.taskService completeTask:task.taskId variables:nil error:&completeError]) {
					if ([completeError code] != UDWorkflowErrorConflict) {
						break;
					}
					@synchronized (self) {
						conflicts += 1;
					}
				}
			});
		}
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		UDDispatchRelease(group);
		/* The join fired exactly once. */
		XCTAssertEqualObjects([[engine.taskService tasksForProcessInstance:pid]
			valueForKey:@"taskDefinitionKey"], @[ @"after" ], @"round %d", round);
	}
	NSLog(@"conflicts resolved by retrying: %lu", (unsigned long)conflicts);
}

@end

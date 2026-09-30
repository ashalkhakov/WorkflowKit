/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Gateways

- (void)testExclusiveAutoApprove
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"xor"];
	[[[[b addStart:@"start"] addExclusive:@"g" defaultFlow:@"low"] addServiceTask:@"hi" action:@"hi"]
		addServiceTask:@"lo" action:@"lo"];
	[b addEnd:@"end"];
	[b connect:@"start" to:@"g"];
	[b connect:@"g" to:@"hi" when:@"amount > 1000"];
	[b connect:@"g" to:@"lo" flowId:@"low"];
	[[b connect:@"hi" to:@"end"] connect:@"lo" to:@"end"];
	WFMapHandler *h = [[WFMapHandler alloc] init];
	[h.results setObject:@{ @"path": @"lo" } forKey:@"lo"];
	[h.results setObject:@{ @"path": @"hi" } forKey:@"hi"];
	WFProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"amount": @50 }];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"path"], @"lo");
}

- (void)testParallelJoin
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"and"];
	[[[[b addStart:@"start"] addParallel:@"fork"] addServiceTask:@"a" action:@"a"]
		addServiceTask:@"b" action:@"b"];
	[[b addParallel:@"join"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"a"] connect:@"fork" to:@"b"];
	[[b connect:@"a" to:@"join"] connect:@"b" to:@"join"];
	[b connect:@"join" to:@"end"];
	WFMapHandler *h = [[WFMapHandler alloc] init];
	[h.results setObject:@{ @"a": @YES } forKey:@"a"];
	[h.results setObject:@{ @"b": @YES } forKey:@"b"];
	WFProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	NSDictionary *vars = [self variables:pid engine:engine];
	XCTAssertEqualObjects([vars objectForKey:@"a"], @YES);
	XCTAssertEqualObjects([vars objectForKey:@"b"], @YES);
}

- (void)testParallelJoinWaitsForBothUserTasks
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"review"];
	[[[[b addStart:@"start"] addParallel:@"fork"]
		addUserTask:@"legal" name:@"Legal" assignee:@"ann"]
		addUserTask:@"finance" name:@"Finance" assignee:@"bob"];
	[[[b addParallel:@"join"] addUserTask:@"sign" name:@"Sign" assignee:@"cat"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"legal"] connect:@"fork" to:@"finance"];
	[[b connect:@"legal" to:@"join"] connect:@"finance" to:@"join"];
	[[b connect:@"join" to:@"sign"] connect:@"sign" to:@"end"];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"finance", @"legal" ]));
	XCTAssertEqual([[engine.taskService tasksForAssignee:@"ann"] count], (NSUInteger)1);
	[self complete:@"legal" of:pid engine:engine variables:nil];
	/* Waiting at the join is not active. */
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"finance" ]);
	[self complete:@"finance" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"sign" ]);
	/* One path again: the tree is back to the process instance alone. */
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)1);
	[self complete:@"sign" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)0);
}

- (WFProcessDefinition *)inclusiveDefinition
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"or"];
	[[[[b addStart:@"start"] addInclusive:@"split" defaultFlow:@"d"]
		addServiceTask:@"audit" action:@"audit"] addServiceTask:@"ship" action:@"ship"];
	[[b addInclusive:@"join" defaultFlow:nil] addEnd:@"end"];
	[b connect:@"start" to:@"split"];
	[b connect:@"split" to:@"audit" when:@"audit = true"];
	[b connect:@"split" to:@"ship" when:@"ship = true"];
	[b connect:@"split" to:@"ship" flowId:@"d"];
	[[b connect:@"audit" to:@"join"] connect:@"ship" to:@"join"];
	[b connect:@"join" to:@"end"];
	WFProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testInclusiveTwoBranches
{
	WFMapHandler *h = [[WFMapHandler alloc] init];
	[h.results setObject:@{ @"audited": @YES } forKey:@"audit"];
	[h.results setObject:@{ @"shipped": @YES } forKey:@"ship"];
	WFProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self inclusiveDefinition] engine:engine
	                variables:@{ @"audit": @YES, @"ship": @YES }];
	XCTAssertTrue([self ended:pid engine:engine]);
	NSDictionary *vars = [self variables:pid engine:engine];
	XCTAssertEqualObjects([vars objectForKey:@"audited"], @YES);
	XCTAssertEqualObjects([vars objectForKey:@"shipped"], @YES);
}

- (void)testInclusiveJoinWithOneBranchTaken
{
	WFMapHandler *h = [[WFMapHandler alloc] init];
	[h.results setObject:@{ @"audited": @YES } forKey:@"audit"];
	WFProcessEngine *engine = [self engineWithHandler:h];
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
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"race"];
	[[[[b addStart:@"start"] addParallel:@"fork"]
		addUserTask:@"left" name:@"Left" assignee:@"a"] addUserTask:@"right" name:@"Right" assignee:@"b"];
	[[[b addParallel:@"join"] addUserTask:@"after" name:@"After" assignee:@"c"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"left"] connect:@"fork" to:@"right"];
	[[b connect:@"left" to:@"join"] connect:@"right" to:@"join"];
	[[b connect:@"join" to:@"after"] connect:@"after" to:@"end"];
	WFProcessDefinition *definition = [b build:&error];
	WFProcessEngine *engine = [self durableEngineAtURL:[self temporaryStoreURL] handler:nil];
	[self deploy:definition engine:engine];
	__block NSUInteger conflicts = 0;
	for (int round = 0; round < 20; round++) {
		NSString *pid = [engine.runtimeService startProcessInstanceByKey:@"race"
		                                                        variables:nil error:&error].processInstanceId;
		NSArray *tasks = [engine.taskService tasksForProcessInstance:pid];
		XCTAssertEqual([tasks count], (NSUInteger)2);
		dispatch_group_t group = dispatch_group_create();
		for (WFWorkItem *task in tasks) {
			/* In a pool of its own, as the engine's own blocks are: on
			 * GNUstep a worker thread drains only when it goes idle. */
			dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ @autoreleasepool {
				NSError *completeError = nil;
				/* A lost race changed nothing: the caller tries again. */
				while (![engine.taskService completeTask:task.taskId variables:nil error:&completeError]) {
					if ([completeError code] != WFErrorConflict) {
						break;
					}
					@synchronized (self) {
						conflicts += 1;
					}
				}
			}});
		}
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		WFDispatchRelease(group);
		/* The join fired exactly once. */
		XCTAssertEqualObjects([[engine.taskService tasksForProcessInstance:pid]
			valueForKey:@"taskDefinitionKey"], @[ @"after" ], @"round %d", round);
	}
	NSLog(@"conflicts resolved by retrying: %lu", (unsigned long)conflicts);
}

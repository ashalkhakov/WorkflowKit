/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Task queries

/* start -> review (a user task for the sales group, at the instance's
 * priority) -> end */
- (WFProcessDefinition *)review
{
	return [self reviewNamed:@"Review order"];
}

- (WFProcessDefinition *)reviewNamed:(NSString *)name
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"review"];
	[[[b addStart:@"start"] addUserTask:@"review" name:name assignee:nil] addEnd:@"end"];
	[[b connect:@"start" to:@"review"] connect:@"review" to:@"end"];
	[b setAssignment:@{ @"candidateGroups": @"sales", @"priority": @"${priority}" } forElement:@"review"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

/* Instances a to d of review, by business key, with variables of each
 * type: a's and b's amount a whole and a real number, c's a string, and d
 * has none but its priority. */
- (NSDictionary *)startReviews:(WFProcessEngine *)engine
{
	NSDate *date2030 = [NSDate dateWithTimeIntervalSince1970:1893456000];
	NSDate *date2031 = [NSDate dateWithTimeIntervalSince1970:1924992000];
	NSDictionary *variables = @{
		@"a": @{ @"priority": @70, @"amount": @100, @"customer": @"Acme Corp", @"urgent": @YES,
		         @"deadline": date2030, @"note": [NSNull null] },
		@"b": @{ @"priority": @40, @"amount": @250.5, @"customer": @"Beta", @"urgent": @NO, @"deadline": date2031 },
		@"c": @{ @"priority": @90, @"amount": @"many", @"customer": @"Acme Inc" },
		@"d": @{ @"priority": @30 },
	};
	[self deploy:[self review] engine:engine];
	NSMutableDictionary *keys = [NSMutableDictionary dictionary];
	for (NSString *key in [[variables allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSError *error = nil;
		WFProcessInstance *instance = [engine.runtimeService startProcessInstanceByKey:@"review" businessKey:key
		                                                                      variables:[variables objectForKey:key]
		                                                                          error:&error];
		XCTAssertNotNil(instance, @"%@", error);
		[keys setObject:key forKey:instance.processInstanceId];
	}
	return keys;
}

/* The business keys of the tasks found, in their order. */
- (NSArray *)keysOf:(WFTaskQuery *)query in:(NSDictionary *)keys engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	NSArray *tasks = [engine.taskService tasksMatching:query first:0 max:0 error:&error];
	XCTAssertNotNil(tasks, @"%@", error);
	NSMutableArray *found = [NSMutableArray array];
	for (WFWorkItem *task in tasks) {
		[found addObject:[keys objectForKey:task.processInstanceId] ?: task.processInstanceId];
	}
	return found;
}

- (NSArray *)sortedKeysOf:(WFTaskQuery *)query in:(NSDictionary *)keys engine:(WFProcessEngine *)engine
{
	return [[self keysOf:query in:keys engine:engine] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)testQueriesByProcessVariables
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSDictionary *keys = [self startReviews:engine];
	NSArray *(^where)(NSString *, WFQueryOperator, id) = ^NSArray *(NSString *name, WFQueryOperator op, id value) {
		return [self sortedKeysOf:[[WFTaskQuery query] processVariable:name operator:op value:value] in:keys engine:engine];
	};
	/* Numbers, whole or real, and not a string. */
	XCTAssertEqualObjects(where(@"amount", WFQueryGreater, @99), (@[ @"a", @"b" ]));
	XCTAssertEqualObjects(where(@"amount", WFQueryLessOrEqual, @100), @[ @"a" ]);
	XCTAssertEqualObjects(where(@"amount", WFQueryEqual, @250.5), @[ @"b" ]);
	XCTAssertEqualObjects(where(@"amount", WFQueryGreaterOrEqual, @100.5), @[ @"b" ]);
	/* ne: set, to anything else; d has no amount. */
	XCTAssertEqualObjects(where(@"amount", WFQueryNotEqual, @100), (@[ @"b", @"c" ]));
	/* Strings. */
	XCTAssertEqualObjects(where(@"customer", WFQueryEqual, @"Beta"), @[ @"b" ]);
	XCTAssertEqualObjects(where(@"customer", WFQueryLike, @"Acme%"), (@[ @"a", @"c" ]));
	XCTAssertEqualObjects(where(@"customer", WFQueryLike, @"Acme _nc"), @[ @"c" ]);
	XCTAssertEqualObjects(where(@"customer", WFQueryLess, @"B"), (@[ @"a", @"c" ]));
	XCTAssertEqualObjects(where(@"amount", WFQueryEqual, @"many"), @[ @"c" ]);
	/* Booleans, dates and null. */
	XCTAssertEqualObjects(where(@"urgent", WFQueryEqual, @YES), @[ @"a" ]);
	XCTAssertEqualObjects(where(@"urgent", WFQueryNotEqual, @YES), @[ @"b" ]);
	XCTAssertEqualObjects(where(@"deadline", WFQueryLess, [NSDate dateWithTimeIntervalSince1970:1900000000]), @[ @"a" ]);
	XCTAssertEqualObjects(where(@"note", WFQueryEqual, nil), @[ @"a" ]);
	XCTAssertEqualObjects(where(@"note", WFQueryNotEqual, [NSNull null]), @[]);
	XCTAssertEqualObjects(where(@"missing", WFQueryEqual, @1), @[]);

	/* Several conditions all hold. */
	WFTaskQuery *both = [[[WFTaskQuery query] processVariable:@"amount" operator:WFQueryGreater value:@50]
		processVariable:@"customer" operator:WFQueryLike value:@"Acme%"];
	XCTAssertEqualObjects([self sortedKeysOf:both in:keys engine:engine], @[ @"a" ]);
	XCTAssertEqual([engine.taskService countOfTasksMatching:both error:&error], (NSUInteger)1, @"%@", error);

	/* What the variables are now. */
	NSString *d = [[keys allKeysForObject:@"d"] lastObject];
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"amount": @500 } processInstanceId:d error:&error], @"%@", error);
	XCTAssertEqualObjects(where(@"amount", WFQueryGreater, @99), (@[ @"a", @"b", @"d" ]));

	/* Conditions the engine cannot evaluate. */
	NSArray *invalid = @[ [[WFTaskQuery query] processVariable:@"urgent" operator:WFQueryGreater value:@YES],
	                      [[WFTaskQuery query] processVariable:@"amount" operator:WFQueryLike value:@1],
	                      [[WFTaskQuery query] processVariable:@"note" operator:WFQueryLess value:nil],
	                      [[WFTaskQuery query] processVariable:@"blob" operator:WFQueryEqual
	                                                     value:[@"x" dataUsingEncoding:NSUTF8StringEncoding]] ];
	for (WFTaskQuery *query in invalid) {
		error = nil;
		XCTAssertNil([engine.taskService tasksMatching:query first:0 max:0 error:&error]);
		XCTAssertEqual([error code], (NSInteger)WFErrorInvalidQuery, @"%@", error);
		XCTAssertEqual([engine.taskService countOfTasksMatching:query error:NULL], (NSUInteger)NSNotFound);
	}
}

/* Only the process instance's own variables: not those of a scope in it. */
- (void)testQueriesAskTheProcessInstancesVariables
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *inner = [WFDefinitionBuilder process:@"inner"];
	[[[inner addStart:@"s"] addUserTask:@"work" name:@"Work" assignee:@"ann"] addEnd:@"e"];
	[[inner connect:@"s" to:@"work"] connect:@"work" to:@"e"];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"scoped"];
	[[[b addStart:@"start"] addSubProcess:@"stage" name:@"Stage" inner:[inner build:&error]] addEnd:@"end"];
	[[b connect:@"start" to:@"stage"] connect:@"stage" to:@"end"];
	[b addInputParameter:@"level" value:@"=2" forElement:@"stage"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"owner": @"ann" }];
	WFTaskQuery *owner = [[WFTaskQuery query] processVariable:@"owner" operator:WFQueryEqual value:@"ann"];
	XCTAssertEqual([[engine.taskService tasksMatching:owner first:0 max:0 error:&error] count], (NSUInteger)1,
		@"%@", error);
	WFTaskQuery *level = [[WFTaskQuery query] processVariable:@"level" operator:WFQueryEqual value:@2];
	XCTAssertEqual([[engine.taskService tasksMatching:level first:0 max:0 error:&error] count], (NSUInteger)0,
		@"the subprocess's own");
	[self complete:@"work" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testQueriesByTask
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSDictionary *keys = [self startReviews:engine];
	NSString *a = [[keys allKeysForObject:@"a"] lastObject];
	NSString *definitionId = [[engine.runtimeService processInstanceWithId:a error:NULL] definitionId];

	XCTAssertEqualObjects([self keysOf:[[WFTaskQuery query] businessKey:@"b"] in:keys engine:engine], @[ @"b" ]);
	XCTAssertEqualObjects([self keysOf:[[WFTaskQuery query] processInstanceId:a] in:keys engine:engine], @[ @"a" ]);
	XCTAssertEqual([[self keysOf:[[WFTaskQuery query] taskDefinitionKey:@"review"] in:keys engine:engine] count],
		(NSUInteger)4);
	XCTAssertEqual([[self keysOf:[[WFTaskQuery query] nameLike:@"Review%"] in:keys engine:engine] count], (NSUInteger)4);
	XCTAssertEqualObjects([self keysOf:[[WFTaskQuery query] nameLike:@"Approve%"] in:keys engine:engine], @[]);
	XCTAssertEqualObjects([self sortedKeysOf:[[WFTaskQuery query] minPriority:70] in:keys engine:engine],
		(@[ @"a", @"c" ]));
	XCTAssertEqualObjects([self sortedKeysOf:[[[WFTaskQuery query] minPriority:30] maxPriority:40] in:keys engine:engine],
		(@[ @"b", @"d" ]));

	/* Offered and claimed. */
	XCTAssertEqual([[self keysOf:[[WFTaskQuery query] candidateGroup:@"sales"] in:keys engine:engine] count],
		(NSUInteger)4);
	WFWorkItem *task = [self task:@"review" of:a engine:engine];
	XCTAssertTrue([engine.taskService claimTask:task.taskId user:@"ann" error:&error], @"%@", error);
	XCTAssertEqualObjects([self sortedKeysOf:[[WFTaskQuery query] candidateUser:@"cy" groups:@[ @"sales" ]]
	                                      in:keys engine:engine], (@[ @"b", @"c", @"d" ]));
	XCTAssertEqualObjects([self keysOf:[[WFTaskQuery query] candidateUser:@"cy" groups:@[ @"staff" ]] in:keys engine:engine],
		@[]);
	XCTAssertEqualObjects([self keysOf:[[WFTaskQuery query] assignee:@"ann"] in:keys engine:engine], @[ @"a" ]);
	XCTAssertEqualObjects([self keysOf:[[WFTaskQuery query] assigned] in:keys engine:engine], @[ @"a" ]);
	XCTAssertEqual([[self keysOf:[[WFTaskQuery query] unassigned] in:keys engine:engine] count], (NSUInteger)3);

	/* Suspended with their instance. */
	XCTAssertTrue([engine.runtimeService suspendProcessInstance:a error:&error], @"%@", error);
	XCTAssertEqualObjects([self keysOf:[[WFTaskQuery query] suspended:YES] in:keys engine:engine], @[ @"a" ]);
	XCTAssertEqual([[self keysOf:[[WFTaskQuery query] suspended:NO] in:keys engine:engine] count], (NSUInteger)3);

	/* By the process, any version of it, or one. */
	[self deploy:[self reviewNamed:@"Review the order"] engine:engine];
	NSError *startError = nil;
	XCTAssertNotNil([engine.runtimeService startProcessInstanceByKey:@"review" businessKey:@"e"
	                                                        variables:@{ @"priority": @1 } error:&startError],
		@"%@", startError);
	XCTAssertEqual([engine.taskService countOfTasksMatching:[[WFTaskQuery query] processDefinitionKey:@"review"]
	                                                  error:&error], (NSUInteger)5, @"%@", error);
	XCTAssertEqual([engine.taskService countOfTasksMatching:[[WFTaskQuery query] processDefinitionId:definitionId]
	                                                  error:&error], (NSUInteger)4, @"%@", error);
	XCTAssertEqual([engine.taskService countOfTasksMatching:[[WFTaskQuery query] processDefinitionKey:@"other"]
	                                                  error:&error], (NSUInteger)0, @"%@", error);
	XCTAssertEqual([engine.taskService countOfTasksMatching:[WFTaskQuery query] error:&error], (NSUInteger)5);
}

- (void)testQueriesInOrderAndInPages
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSDictionary *keys = [self startReviews:engine];
	/* By priority, highest first, then as they were created. */
	WFTaskQuery *byPriority = [[WFTaskQuery query] orderBy:WFTaskOrderPriority ascending:NO];
	XCTAssertEqualObjects([self keysOf:byPriority in:keys engine:engine], (@[ @"c", @"a", @"b", @"d" ]));
	NSMutableArray *paged = [NSMutableArray array];
	for (NSUInteger first = 0; first < 4; first += 3) {
		NSError *error = nil;
		NSArray *page = [engine.taskService tasksMatching:byPriority first:first max:3 error:&error];
		XCTAssertNotNil(page, @"%@", error);
		for (WFWorkItem *task in page) {
			[paged addObject:[keys objectForKey:task.processInstanceId]];
		}
	}
	XCTAssertEqualObjects(paged, (@[ @"c", @"a", @"b", @"d" ]));
	/* A copy is a query of its own. */
	WFTaskQuery *low = [[byPriority copy] maxPriority:40];
	XCTAssertEqualObjects([self keysOf:low in:keys engine:engine], (@[ @"b", @"d" ]));
	XCTAssertEqual([[self keysOf:byPriority in:keys engine:engine] count], (NSUInteger)4);
}

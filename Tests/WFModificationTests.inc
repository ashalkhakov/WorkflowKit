/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Process instance modification

/* start -> review -> check -> ship -> end, where check is a subprocess
 * (inspect -> file) with an input and an interrupting boundary message
 * recall -> recalled. */
- (WFProcessDefinition *)modifiable
{
	NSError *error = nil;
	WFDefinitionBuilder *inner = [WFDefinitionBuilder process:@"inside"];
	[[[[inner addStart:@"s"] addUserTask:@"inspect" name:@"Inspect" assignee:@"ann"]
		addUserTask:@"file" name:@"File" assignee:@"ann"] addEnd:@"e"];
	[[[inner connect:@"s" to:@"inspect"] connect:@"inspect" to:@"file"] connect:@"file" to:@"e"];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"order"];
	[[[[b addStart:@"start"] addUserTask:@"review" name:@"Review" assignee:@"ann"]
		addSubProcess:@"check" name:@"Check" inner:[inner build:&error]]
		addUserTask:@"ship" name:@"Ship" assignee:@"ann"];
	[[[b addEnd:@"end"] addBoundaryMessage:@"recall" onTask:@"check" message:@"recall" interrupting:YES]
		addEnd:@"recalled"];
	[[[b connect:@"start" to:@"review"] connect:@"review" to:@"check"] connect:@"check" to:@"ship"];
	[[b connect:@"ship" to:@"end"] connect:@"recall" to:@"recalled"];
	[b addInputParameter:@"inspector" value:@"=\"bob\"" forElement:@"check"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (NSArray *)openTasks:(NSString *)pid engine:(WFProcessEngine *)engine
{
	return [[[engine.taskService tasksForProcessInstance:pid] valueForKey:@"taskDefinitionKey"]
		sortedArrayUsingSelector:@selector(compare:)];
}

- (BOOL)modify:(WFProcessInstanceModification *)modification engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	BOOL ok = [engine.runtimeService modifyProcessInstance:modification error:&error];
	XCTAssertTrue(ok, @"%@", error);
	return ok;
}

- (WFActivityInstance *)tree:(NSString *)pid engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	WFActivityInstance *tree = [engine.runtimeService activityInstanceTreeOfProcessInstance:pid error:&error];
	XCTAssertNotNil(tree, @"%@", error);
	return tree;
}

- (void)testStartBeforeAfterAndOnATransition
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFProcessDefinition *definition = [self modifiable];
	NSString *pid = [self run:definition engine:engine variables:nil];
	XCTAssertEqualObjects([self openTasks:pid engine:engine], @[ @"review" ]);
	NSString *checkToShip = [[[definition outgoingFlowsFrom:@"check"] firstObject] elementId];
	XCTAssertTrue([self modify:[[[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		startBeforeActivity:@"ship"] startAfterActivity:@"review"] startTransition:checkToShip] engine:engine]);
	/* After review is the subprocess, which starts at inspect. */
	XCTAssertEqualObjects([self openTasks:pid engine:engine], (@[ @"inspect", @"review", @"ship", @"ship" ]));
	WFActivityInstance *tree = [self tree:pid engine:engine];
	XCTAssertEqualObjects(tree.activityInstanceId, pid);
	XCTAssertEqualObjects(tree.activityId, @"order");
	XCTAssertEqual([[tree activityInstancesForActivity:@"ship"] count], (NSUInteger)2);
	WFActivityInstance *check = [[tree activityInstancesForActivity:@"check"] firstObject];
	XCTAssertEqualObjects([check.childActivityInstances valueForKey:@"activityId"], @[ @"inspect" ]);
	XCTAssertEqualObjects(check.parentActivityInstanceId, pid);
}

- (void)testStartingInsideASubprocessOpensIt
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self modifiable] engine:engine variables:nil];
	XCTAssertTrue([self modify:[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		startBeforeActivity:@"file"] engine:engine]);
	/* Its start event and inspect are skipped; its input is mapped. */
	XCTAssertEqualObjects([self openTasks:pid engine:engine], (@[ @"file", @"review" ]));
	WFActivityInstance *check = [[[self tree:pid engine:engine] activityInstancesForActivity:@"check"] firstObject];
	XCTAssertEqualObjects([check.childActivityInstances valueForKey:@"activityId"], @[ @"file" ]);
	XCTAssertEqualObjects([[engine.historyService historicVariablesForProcessInstance:pid] objectForKey:@"inspector"],
		@"bob");

	/* A second instance of the subprocess makes where to start ambiguous. */
	XCTAssertTrue([self modify:[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		startBeforeActivity:@"check"] engine:engine]);
	XCTAssertFalse([engine.runtimeService modifyProcessInstance:[[WFProcessInstanceModification
		modificationOfProcessInstance:pid] startBeforeActivity:@"file"] error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"ancestor"].location != NSNotFound, @"%@", error);
	XCTAssertTrue([self modify:[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		startBeforeActivity:@"file" ancestor:check.activityInstanceId variables:@{ @"urgent": @YES }] engine:engine]);
	for (WFActivityInstance *each in [[self tree:pid engine:engine] activityInstancesForActivity:@"check"]) {
		BOOL first = [each.activityInstanceId isEqualToString:check.activityInstanceId];
		XCTAssertEqual([[each activityInstancesForActivity:@"file"] count], first ? (NSUInteger)2 : (NSUInteger)0);
		XCTAssertEqual([[each activityInstancesForActivity:@"inspect"] count], first ? (NSUInteger)0 : (NSUInteger)1);
	}

	/* The boundary message armed on the opened subprocess takes both. */
	XCTAssertTrue([engine.runtimeService correlateMessageToAll:@"recall" businessKey:nil correlationKeys:nil
	                                                 variables:nil error:&error] != nil, @"%@", error);
	XCTAssertEqualObjects([self openTasks:pid engine:engine], @[ @"review" ]);
}

- (void)testCancelingActivityInstances
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self modifiable] engine:engine variables:nil];
	XCTAssertTrue([self modify:[[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		startBeforeActivity:@"inspect"] startBeforeActivity:@"ship"] engine:engine]);
	NSString *inspect = [[[[self tree:pid engine:engine] activityInstancesForActivity:@"inspect"] firstObject]
		activityInstanceId];

	/* The subprocess left with nothing is canceled too, its boundary
	 * message with it. */
	XCTAssertTrue([self modify:[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		cancelActivityInstance:inspect] engine:engine]);
	XCTAssertEqualObjects([self openTasks:pid engine:engine], (@[ @"review", @"ship" ]));
	XCTAssertEqual([[[self tree:pid engine:engine] activityInstancesForActivity:@"check"] count], (NSUInteger)0);
	XCTAssertFalse([engine.runtimeService correlateMessage:@"recall" processInstanceId:pid variables:nil error:&error]);
	NSArray *canceled = [[[engine.historyService historicActivityInstancesForProcessInstance:pid]
		filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"canceled == YES"]] valueForKey:@"activityId"];
	XCTAssertEqualObjects([canceled sortedArrayUsingSelector:@selector(compare:)], (@[ @"check", @"inspect" ]));

	/* The remaining paths go on as before. */
	[self complete:@"review" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self openTasks:pid engine:engine], (@[ @"inspect", @"ship" ]));
}

- (void)testAnInstanceLeftWithNothingEnds
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self modifiable] engine:engine variables:nil];
	/* Canceled and started again in one modification, it goes on. */
	XCTAssertTrue([self modify:[[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		cancelAllForActivity:@"review"] startBeforeActivity:@"ship"] engine:engine]);
	XCTAssertEqualObjects([self openTasks:pid engine:engine], @[ @"ship" ]);
	XCTAssertTrue([self modify:[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		cancelAllForActivity:@"ship"] engine:engine]);
	XCTAssertNil([engine.runtimeService processInstanceWithId:pid error:NULL]);
	WFHistoricProcessInstance *history = [engine.historyService historicProcessInstanceWithId:pid];
	XCTAssertEqualObjects(history.state, WFProcessInstanceStateExternallyTerminated);
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)0);
	XCTAssertEqual([[self rows:@"WFTask" engine:engine] count], (NSUInteger)0);
}

- (void)testModificationsThatCannotBeDoneChangeNothing
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self modifiable] engine:engine variables:nil];
	NSArray *refused = @[
		[[[WFProcessInstanceModification modificationOfProcessInstance:pid] startBeforeActivity:@"ship"]
			startBeforeActivity:@"nothing"],
		[[WFProcessInstanceModification modificationOfProcessInstance:pid] startBeforeActivity:@"recall"],
		[[WFProcessInstanceModification modificationOfProcessInstance:pid] startAfterActivity:@"end"],
		[[WFProcessInstanceModification modificationOfProcessInstance:pid] cancelActivityInstance:@"nothing"],
	];
	for (WFProcessInstanceModification *modification in refused) {
		XCTAssertFalse([engine.runtimeService modifyProcessInstance:modification error:&error]);
		XCTAssertEqualObjects([self openTasks:pid engine:engine], @[ @"review" ], @"%@", error);
	}
	XCTAssertTrue([engine.runtimeService suspendProcessInstance:pid error:&error]);
	XCTAssertFalse([engine.runtimeService modifyProcessInstance:[[WFProcessInstanceModification
		modificationOfProcessInstance:pid] startBeforeActivity:@"ship"] error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorSuspended);
}

- (void)testStartingBeforeAnAsyncActivityMakesAJob
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"slow"];
	[[[[b addStart:@"start"] addUserTask:@"wait" name:@"Wait" assignee:@"ann"]
		addUserTask:@"later" name:@"Later" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"wait"] connect:@"wait" to:@"later"] connect:@"later" to:@"end"];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"later"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertTrue([self modify:[[WFProcessInstanceModification modificationOfProcessInstance:pid]
		startBeforeActivity:@"later"] engine:engine]);
	XCTAssertEqualObjects([self openTasks:pid engine:engine], @[ @"wait" ]);
	WFJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(job.activityId, @"later");
	XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@", error);
	XCTAssertEqualObjects([self openTasks:pid engine:engine], (@[ @"later", @"wait" ]));
}

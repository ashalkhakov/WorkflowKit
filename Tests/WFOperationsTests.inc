/* Included into a class of each backend's suite: see WFTestCase.h. */

/* start -> review (a user task) -> end, waiting also for a message
 * "nudge" on the way, beside the task. */
- (WFProcessDefinition *)reviewProcess:(NSString *)key
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:key];
	[[[b addStart:@"start"] addParallel:@"fork"] addUserTask:@"review" name:@"Review" assignee:@"ann"];
	[[[b addMessageCatch:@"nudged" message:@"nudge"] addParallel:@"join"] addEnd:@"end"];
	[[b connect:@"start" to:@"fork"] connect:@"fork" to:@"review"];
	[[b connect:@"fork" to:@"nudged"] connect:@"review" to:@"join"];
	[[b connect:@"nudged" to:@"join"] connect:@"join" to:@"end"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testDeletingAnInstanceCancelsItAndWhatItCalled
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self reviewProcess:@"child"] engine:engine];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"parent"];
	[[[b addStart:@"start"] addCallActivity:@"call" calledElement:@"child"] addEnd:@"end"];
	[[b connect:@"start" to:@"call"] connect:@"call" to:@"end"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	NSString *childId = [[[engine.runtimeService subProcessInstancesOf:pid error:NULL] lastObject]
		processInstanceId];
	XCTAssertNotNil(childId);

	/* Only through the instance that called it. */
	XCTAssertFalse([engine.runtimeService deleteProcessInstance:childId reason:@"no" error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorInvalidState);

	XCTAssertTrue([engine.runtimeService deleteProcessInstance:pid reason:@"ordered by mistake"
	                                                     error:&error], @"%@", error);
	XCTAssertNil([engine.runtimeService processInstanceWithId:pid error:NULL]);
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)0);
	XCTAssertEqual([[self rows:@"WFTask" engine:engine] count], (NSUInteger)0);
	XCTAssertEqual([[self rows:@"WFEventSubscription" engine:engine] count], (NSUInteger)0);
	WFHistoricProcessInstance *history = [engine.historyService historicProcessInstanceWithId:pid];
	XCTAssertEqualObjects(history.state, WFProcessInstanceStateExternallyTerminated);
	XCTAssertEqualObjects(history.deleteReason, @"ordered by mistake");
	XCTAssertNotNil(history.endTime);
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:childId] state],
		WFProcessInstanceStateInternallyTerminated);
	XCTAssertEqualObjects([[[engine.historyService historicTaskInstancesForProcessInstance:childId]
		lastObject] deleteReason], WFTaskDeleteReasonDeleted);
	XCTAssertFalse([engine.runtimeService deleteProcessInstance:pid reason:nil error:&error]);
}

- (void)testASuspendedInstanceWaits
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self reviewProcess:@"review"] engine:engine variables:nil];
	XCTAssertTrue([engine.runtimeService suspendProcessInstance:pid error:&error], @"%@", error);
	XCTAssertTrue([[engine.runtimeService processInstanceWithId:pid error:NULL] isSuspended]);

	WFWorkItem *task = [self task:@"review" of:pid engine:engine];
	XCTAssertTrue(task.isSuspended);
	XCTAssertFalse([engine.taskService completeTask:task.taskId variables:nil error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorSuspended);
	/* Messages and signals pass it by. */
	XCTAssertFalse([engine.runtimeService correlateMessage:@"nudge" processInstanceId:pid
	                                             variables:nil error:&error]);

	XCTAssertTrue([engine.runtimeService activateProcessInstance:pid error:&error], @"%@", error);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"nudge" processInstanceId:pid
	                                            variables:nil error:&error], @"%@", error);
	[self complete:@"review" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testSuspendedJobsAndExternalTasksWait
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"slow"];
	[[[[b addStart:@"start"] addTimerCatch:@"wait" duration:3600] addServiceTask:@"work" action:@"work"]
		addEnd:@"end"];
	[[[b connect:@"start" to:@"wait"] connect:@"wait" to:@"work"] connect:@"work" to:@"end"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertTrue([engine.runtimeService suspendProcessInstance:pid error:&error], @"%@", error);
	WFJob *timer = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertTrue(timer.isSuspended);
	XCTAssertFalse([engine.managementService executeJob:timer.jobId error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorSuspended);

	XCTAssertTrue([engine.runtimeService activateProcessInstance:pid error:&error], @"%@", error);
	XCTAssertTrue([engine.managementService executeJob:timer.jobId error:&error], @"%@", error);
	XCTAssertTrue([engine.runtimeService suspendProcessInstance:pid error:&error], @"%@", error);
	XCTAssertEqual([[engine.externalTaskService fetchAndLock:10 workerId:@"w" topics:@{ @"work": @60 }
	                                                  error:&error] count], (NSUInteger)0);
	XCTAssertTrue([engine.runtimeService activateProcessInstance:pid error:&error], @"%@", error);
	NSArray *tasks = [engine.externalTaskService fetchAndLock:10 workerId:@"w" topics:@{ @"work": @60 }
	                                                    error:&error];
	XCTAssertEqual([tasks count], (NSUInteger)1);
	XCTAssertTrue([engine.externalTaskService complete:[[tasks lastObject] externalTaskId] workerId:@"w"
	                                         variables:nil error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testASuspendedDefinitionStartsNothing
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *running = [self run:[self reviewProcess:@"review"] engine:engine variables:nil];
	NSString *definitionId = [[engine.repositoryService latestDefinitionForKey:@"review" error:NULL]
		definitionId];

	XCTAssertTrue([engine.repositoryService suspendDefinition:definitionId includeInstances:NO
	                                                   error:&error], @"%@", error);
	XCTAssertTrue([engine.repositoryService isDefinitionSuspended:definitionId]);
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"review" variables:nil error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorSuspended);
	/* Its running instances go on unless they are included. */
	XCTAssertFalse([[engine.runtimeService processInstanceWithId:running error:NULL] isSuspended]);

	/* Nor does a call activity start it. */
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"caller"];
	[[[b addStart:@"start"] addCallActivity:@"call" calledElement:@"review"] addEnd:@"end"];
	[[b connect:@"start" to:@"call"] connect:@"call" to:@"end"];
	[self deploy:[b build:&error] engine:engine];
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"caller" variables:nil error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorSuspended);

	XCTAssertTrue([engine.repositoryService suspendDefinition:definitionId includeInstances:YES
	                                                   error:&error], @"%@", error);
	XCTAssertTrue([[engine.runtimeService processInstanceWithId:running error:NULL] isSuspended]);
	XCTAssertTrue([engine.repositoryService activateDefinition:definitionId includeInstances:YES
	                                                    error:&error], @"%@", error);
	XCTAssertFalse([[engine.runtimeService processInstanceWithId:running error:NULL] isSuspended]);
	XCTAssertNotNil([engine.runtimeService startProcessInstanceByKey:@"review" variables:nil error:&error],
		@"%@", error);
}

- (void)testASuspendedDefinitionsMessageAndTimerStartsWait
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"onOrder"];
	[[[b addMessageStart:@"start" message:@"order"] addUserTask:@"handle" name:@"Handle" assignee:@"ann"]
		addEnd:@"end"];
	[[b connect:@"start" to:@"handle"] connect:@"handle" to:@"end"];
	[self deploy:[b build:&error] engine:engine];
	b = [WFDefinitionBuilder process:@"daily"];
	[[[b addTimerStart:@"tick" duration:60] addUserTask:@"look" name:@"Look" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"tick" to:@"look"] connect:@"look" to:@"end"];
	[self deploy:[b build:&error] engine:engine];
	NSString *onOrder = [[engine.repositoryService latestDefinitionForKey:@"onOrder" error:NULL] definitionId];
	NSString *daily = [[engine.repositoryService latestDefinitionForKey:@"daily" error:NULL] definitionId];
	XCTAssertTrue([engine.repositoryService suspendDefinition:onOrder includeInstances:NO error:&error]);
	XCTAssertTrue([engine.repositoryService suspendDefinition:daily includeInstances:NO error:&error]);

	XCTAssertFalse([engine.runtimeService correlateMessage:@"order" businessKey:nil correlationKeys:nil
	                                             variables:nil error:&error]);
	WFJob *tick = [[engine.managementService jobsForDefinition:daily] lastObject];
	XCTAssertTrue(tick.isSuspended);
	XCTAssertFalse([engine.managementService executeJob:tick.jobId error:&error]);

	XCTAssertTrue([engine.repositoryService activateDefinition:daily includeInstances:NO error:&error]);
	XCTAssertTrue([engine.managementService executeJob:tick.jobId error:&error], @"%@", error);
	XCTAssertEqual([[self rows:@"WFTask" engine:engine] count], (NSUInteger)1);
}

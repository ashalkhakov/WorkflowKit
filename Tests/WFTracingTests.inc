/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Tracing

- (void)testACommandIsASpanNamedForItsMethod
{
	NSError *error = nil;
	WFRecordingTracer *tracer = [[WFRecordingTracer alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.tracer = tracer;
	NSString *pid = [self run:[self approvalDefinition] engine:engine variables:@{ @"amount": @10 }];
	WFRecordedSpan *start = [[tracer spansNamed:@"startProcessInstanceByKey"] lastObject];
	XCTAssertNotNil(start, @"%@", [tracer.spans valueForKey:@"name"]);
	XCTAssertTrue(start.ended);
	XCTAssertNil(start.error);
	XCTAssertEqualObjects([start.attributes objectForKey:@"code.namespace"], @"WFRuntimeService");
	XCTAssertEqualObjects([start.attributes objectForKey:@"code.function"], @"startProcessInstanceByKey:businessKey:variables:error:");
	XCTAssertEqualObjects([start.attributes objectForKey:@"workflow.process_definition.key"], [self approvalDefinition].processId);
	XCTAssertEqualObjects([start.attributes objectForKey:@"workflow.process_instance.id"], pid);
	/* Every span ends, and the scheduler's polling makes none. */
	XCTAssertEqual([[tracer.spans filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"ended == NO"]] count],
	               (NSUInteger)0);
	XCTAssertEqual([[tracer spansNamed:@"nextWakeUp"] count], (NSUInteger)0);
	(void)error;
}

- (void)testAFailedCommandRecordsItsError
{
	NSError *error = nil;
	WFRecordingTracer *tracer = [[WFRecordingTracer alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.tracer = tracer;
	XCTAssertFalse([engine.runtimeService setVariables:@{ @"a": @1 } processInstanceId:@"nothing" error:&error]);
	WFRecordedSpan *span = [[tracer spansNamed:@"setVariables"] lastObject];
	XCTAssertTrue(span.ended);
	XCTAssertNotNil(span.error);
	XCTAssertEqualObjects([span.error domain], [error domain]);
	XCTAssertEqual([span.error code], [error code]);
}

- (void)testAJobIsASpanOverItsCommands
{
	NSError *error = nil;
	WFRecordingTracer *tracer = [[WFRecordingTracer alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.tracer = tracer;
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self fragileDefinition:nil] engine:engine variables:nil];
	NSString *jobId = [[[engine.managementService jobsForProcessInstance:pid] lastObject] jobId];
	XCTAssertFalse([engine.managementService executeJob:jobId error:&error]);

	WFRecordedSpan *job = [[tracer spansNamed:@"runJob"] lastObject];
	XCTAssertTrue(job.ended);
	XCTAssertEqualObjects([job.attributes objectForKey:@"workflow.job.id"], jobId);
	XCTAssertEqual([job.error code], (NSInteger)WFErrorNoPath);
	WFRecordedSpan *execute = [[tracer spansNamed:@"executeJob"] lastObject];
	XCTAssertEqual(execute.parent, job);
	XCTAssertEqualObjects([execute.attributes objectForKey:@"workflow.job.type"], WFJobTypeAsyncBeforeName);
	XCTAssertEqualObjects([execute.attributes objectForKey:@"workflow.activity.id"], @"route");
	XCTAssertEqualObjects([execute.attributes objectForKey:@"workflow.process_instance.id"], pid);
	XCTAssertNotNil(execute.error);
	XCTAssertEqual([[tracer spansNamed:@"acquireJob"] lastObject].parent, job);
	XCTAssertEqual([[tracer spansNamed:@"recordJobFailure"] lastObject].parent, job);
}

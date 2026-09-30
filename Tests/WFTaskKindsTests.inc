/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Task kinds

- (void)testManualAndPlainTasksArePassedThrough
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"pass"];
	[[[[b addStart:@"start"] addManualTask:@"sign"] addTask:@"note"] addEnd:@"end"];
	[[[b connect:@"start" to:@"sign"] connect:@"sign" to:@"note"] connect:@"note" to:@"end"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	NSArray *activities = [engine.historyService historicActivityInstancesForProcessInstance:pid];
	NSDictionary *types = [NSDictionary dictionaryWithObjects:[activities valueForKey:@"activityType"]
	                                                  forKeys:[activities valueForKey:@"activityId"]];
	XCTAssertEqualObjects([types objectForKey:@"sign"], @"manualTask");
	XCTAssertEqualObjects([types objectForKey:@"note"], @"task");
}

- (void)testSendAndBusinessRuleTasksAreExternalTasks
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"external"];
	[[[[b addStart:@"start"] addSendTask:@"notify" action:@"mail"] addBusinessRuleTask:@"rate" action:@"rating"]
		addEnd:@"end"];
	[[[b connect:@"start" to:@"notify"] connect:@"notify" to:@"rate"] connect:@"rate" to:@"end"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	for (NSString *topic in @[ @"mail", @"rating" ]) {
		NSArray *tasks = [engine.externalTaskService fetchAndLock:1 workerId:@"w" topics:@{ topic: @60 }
		                                                    error:&error];
		XCTAssertEqual([tasks count], (NSUInteger)1, @"%@: %@", topic, error);
		XCTAssertTrue([engine.externalTaskService complete:[[tasks lastObject] externalTaskId] workerId:@"w"
		                                         variables:@{ topic: @YES } error:&error], @"%@", error);
	}
	XCTAssertTrue([self ended:pid engine:engine]);
}

/* start -> receive (waits for "paid", mapped outputs) -> end, or on the
 * boundary timer -> late */
- (WFProcessDefinition *)payment
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"payment"];
	[[[[b addStart:@"start"] addReceiveTask:@"receive" message:@"paid"] addEnd:@"end"] addEnd:@"late"];
	[b addBoundaryTimer:@"deadline" onTask:@"receive" duration:3600 interrupting:YES];
	[[[b connect:@"start" to:@"receive"] connect:@"receive" to:@"end"] connect:@"deadline" to:@"late"];
	[b addOutputParameter:@"received" value:@"=amount" forElement:@"receive"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testReceiveTaskWaitsForItsMessage
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self payment] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"receive" ]);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"paid" processInstanceId:pid
	                                            variables:@{ @"amount": @12 } error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[engine.historyService historicVariablesForProcessInstance:pid]
		objectForKey:@"received"], @12);
	XCTAssertEqual([[self rows:@"WFJob" engine:engine] count], (NSUInteger)0);

	/* The deadline passes first: the task stops waiting. */
	NSString *late = [self run:[self payment] engine:engine variables:nil];
	WFJob *deadline = [[engine.managementService jobsForProcessInstance:late] lastObject];
	XCTAssertTrue([engine.managementService executeJob:deadline.jobId error:&error], @"%@", error);
	XCTAssertTrue([self ended:late engine:engine]);
	XCTAssertFalse([engine.runtimeService correlateMessage:@"paid" processInstanceId:late
	                                             variables:nil error:&error]);
}

- (void)testAnEventBasedGatewayWaitsForAReceiveTask
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"race"];
	[[[[b addStart:@"start"] addEventBased:@"choice"] addReceiveTask:@"receive" message:@"reply"]
		addTimerCatch:@"timeout" duration:3600];
	[[b addEnd:@"answered"] addEnd:@"timedOut"];
	[[b connect:@"start" to:@"choice"] connect:@"choice" to:@"receive"];
	[[b connect:@"choice" to:@"timeout"] connect:@"receive" to:@"answered"];
	[b connect:@"timeout" to:@"timedOut"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"choice" ]);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"reply" processInstanceId:pid
	                                            variables:nil error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"WFJob" engine:engine] count], (NSUInteger)0);
	NSArray *ended = [[engine.historyService historicActivityInstancesForProcessInstance:pid]
		valueForKey:@"activityId"];
	XCTAssertTrue([ended containsObject:@"receive"]);
	XCTAssertFalse([ended containsObject:@"timeout"]);
}

- (void)testReadsAndWritesTheTaskKinds
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\">"
		 @"<bpmn:message id=\"Message_1\" name=\"paid\"/>"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\"><bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:sendTask id=\"send\" camunda:type=\"external\" camunda:topic=\"mail\"/>"
		 @"<bpmn:businessRuleTask id=\"rule\" camunda:type=\"external\" camunda:topic=\"rating\"/>"
		 @"<bpmn:receiveTask id=\"receive\" messageRef=\"Message_1\"/>"
		 @"<bpmn:manualTask id=\"manual\"/><bpmn:task id=\"plain\"/><bpmn:endEvent id=\"e\"/>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"send\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"send\" targetRef=\"rule\"/>"
		 @"<bpmn:sequenceFlow id=\"f3\" sourceRef=\"rule\" targetRef=\"receive\"/>"
		 @"<bpmn:sequenceFlow id=\"f4\" sourceRef=\"receive\" targetRef=\"manual\"/>"
		 @"<bpmn:sequenceFlow id=\"f5\" sourceRef=\"manual\" targetRef=\"plain\"/>"
		 @"<bpmn:sequenceFlow id=\"f6\" sourceRef=\"plain\" targetRef=\"e\"/>"
		 @"</bpmn:process></bpmn:definitions>";
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	XCTAssertEqual([(WFTask *)[definition nodeWithId:@"send"] kind], WFTaskKindSend);
	XCTAssertEqualObjects([(WFTask *)[definition nodeWithId:@"rule"] actionKey], @"rating");
	XCTAssertEqualObjects([(WFTask *)[definition nodeWithId:@"receive"] messageName], @"paid");
	XCTAssertEqual([(WFTask *)[definition nodeWithId:@"plain"] kind], WFTaskKindNone);

	NSString *written = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
	WFProcessDefinition *again = [WFBpmnReader definitionFromXMLString:written error:&error];
	XCTAssertNotNil(again, @"%@\n%@", error, written);
	for (NSString *nodeId in @[ @"send", @"rule", @"receive", @"manual", @"plain" ]) {
		WFTask *before = (WFTask *)[definition nodeWithId:nodeId];
		WFTask *after = (WFTask *)[again nodeWithId:nodeId];
		XCTAssertEqual(before.kind, after.kind, @"%@", nodeId);
		XCTAssertEqualObjects(before.actionKey, after.actionKey, @"%@", nodeId);
		XCTAssertEqualObjects(before.messageName, after.messageName, @"%@", nodeId);
	}

	NSString *internal = [xml stringByReplacingOccurrencesOfString:@"<bpmn:sendTask id=\"send\" camunda:type=\"external\" camunda:topic=\"mail\"/>"
	                                                    withString:@"<bpmn:sendTask id=\"send\" camunda:class=\"Mailer\"/>"];
	XCTAssertNil([WFBpmnReader definitionFromXMLString:internal error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"external"].location != NSNotFound, @"%@", error);
	NSString *instantiating = [xml stringByReplacingOccurrencesOfString:@"messageRef=\"Message_1\""
	                                                         withString:@"messageRef=\"Message_1\" instantiate=\"true\""];
	XCTAssertNil([WFBpmnReader definitionFromXMLString:instantiating error:&error]);
}

/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Delegates and listeners

/* start -> check (a service task running the delegate) -> end, with an
 * error boundary "rejected" -> refused. */
- (WFProcessDefinition *)checking:(WFDelegateReference *)delegate
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"checking"];
	[[[[b addStart:@"start"] addServiceTask:@"check" delegate:delegate] addEnd:@"end"]
		addBoundaryError:@"rejected" onTask:@"check" errorRef:@"REJECTED" interrupting:YES];
	[[b addEnd:@"refused"] connect:@"start" to:@"check"];
	[[b connect:@"check" to:@"end"] connect:@"rejected" to:@"refused"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (WFParameter *)field:(NSString *)name feel:(NSString *)feel
{
	return [WFParameter parameter:name expression:[WFFeelExpression expressionWithString:feel error:NULL]];
}

- (void)testAClassDelegateRunsInTheCommand
{
	[WFTestRecorder reset];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDelegateReference *delegate = [WFDelegateReference referenceToClass:@"WFApproveDelegate"
		fields:@[ [self field:@"limit" feel:@"base * 2"] ]];
	NSString *pid = [self run:[self checking:delegate] engine:engine variables:@{ @"amount": @150, @"base": @100 }];
	XCTAssertTrue([self ended:pid engine:engine]);
	/* The field, 200, was set on the instance by key. */
	XCTAssertEqualObjects([[engine.historyService historicVariablesForProcessInstance:pid] objectForKey:@"approved"], @YES);
	XCTAssertEqualObjects([WFTestRecorder entries], @[ @"approve" ]);
}

- (void)testRegisteredDelegatesClassesAndPlugins
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFProcessDefinition *byName = [self checking:[WFDelegateReference referenceToDelegate:@"approver"
		fields:@[ [self field:@"limit" feel:@"10"] ]]];
	[self deploy:byName engine:engine];
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"checking" variables:@{ @"amount": @1 }
	                                                       error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"approver"].location != NSNotFound, @"%@", error);

	[engine addPlugin:[[WFTestPlugin alloc] init]];
	NSString *pid = [self run:byName engine:engine variables:@{ @"amount": @50 }];
	/* A registered object gets its fields through the execution. */
	XCTAssertEqualObjects([[engine.historyService historicVariablesForProcessInstance:pid] objectForKey:@"approved"], @NO);

	/* A Camunda file's Java class, answered by a registered class. */
	[engine registerDelegateClass:[WFApproveDelegate class] forName:@"org.acme.Approve"];
	pid = [self run:[self checking:[WFDelegateReference referenceToClass:@"org.acme.Approve" fields:nil]]
	         engine:engine variables:@{ @"amount": @5 }];
	XCTAssertEqualObjects([[engine.historyService historicVariablesForProcessInstance:pid] objectForKey:@"approved"], @YES);

	NSURL *directory = [[self temporaryStoreURL] URLByDeletingPathExtension];
	NSURL *fake = [directory URLByAppendingPathComponent:@"Broken.plugin"];
	XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:fake withIntermediateDirectories:YES
	                                                        attributes:nil error:&error], @"%@", error);
	XCTAssertFalse([engine loadPluginsInDirectory:directory error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"Broken.plugin"].location != NSNotFound, @"%@", error);
	[[NSFileManager defaultManager] removeItemAtURL:directory error:NULL];
}

- (void)testADelegatesErrors
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	/* A BPMN error is caught by the boundary. */
	NSString *pid = [self run:[self checking:[WFDelegateReference referenceToClass:@"WFFailingDelegate"
		fields:@[ [self field:@"mode" feel:@"\"bpmn\""] ]]] engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	NSArray *passed = [[engine.historyService historicActivityInstancesForProcessInstance:pid] valueForKey:@"activityId"];
	XCTAssertTrue([passed containsObject:@"refused"], @"%@", passed);

	/* Any other error fails the command: nothing starts. */
	[self deploy:[self checking:[WFDelegateReference referenceToClass:@"WFFailingDelegate" fields:nil]] engine:engine];
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"checking" variables:nil error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"the service is down"].location != NSNotFound, @"%@", error);

	/* In a job, it fails the attempt, which is retried. */
	engine.jobExecutorActive = NO;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"async"];
	[[[b addStart:@"start"] addServiceTask:@"check" delegate:[WFDelegateReference referenceToClass:@"WFFailingDelegate"
		fields:nil]] addEnd:@"end"];
	[[b connect:@"start" to:@"check"] connect:@"check" to:@"end"];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"check"];
	pid = [self run:[b build:&error] engine:engine variables:nil];
	WFJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertFalse([engine.managementService executeJob:job.jobId error:&error]);
	job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqual(job.retries, (NSInteger)2);
	XCTAssertTrue([job.exceptionMessage rangeOfString:@"the service is down"].location != NSNotFound, @"%@", job.exceptionMessage);
}

/* start -> review (a user task) -> end, listened to throughout, with an
 * interrupting boundary message "withdraw" -> withdrawn. */
- (WFProcessDefinition *)listened
{
	NSError *error = nil;
	WFDelegateReference *recorder = [WFDelegateReference referenceToDelegate:@"recorder" fields:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"listened"];
	[[[[b addStart:@"start"] addUserTask:@"review" name:@"Review" assignee:nil] addEnd:@"end"]
		addBoundaryMessage:@"withdraw" onTask:@"review" message:@"withdraw" interrupting:YES];
	[[b addEnd:@"withdrawn"] connect:@"start" to:@"review"];
	[[b connect:@"review" to:@"end" flowId:@"done" condition:nil] connect:@"withdraw" to:@"withdrawn"];
	for (NSNumber *event in @[ @(WFListenerEventStart), @(WFListenerEventEnd) ]) {
		WFListener *listener = [WFListener listenerOn:(WFListenerEvent)[event integerValue] delegate:recorder];
		[[b addListener:listener forElement:@"listened"] addListener:listener forElement:@"review"];
	}
	[b addListener:[WFListener listenerOn:WFListenerEventTake delegate:recorder] forElement:@"done"];
	[b addListener:[WFListener listenerOn:WFListenerEventEnd delegate:recorder] forElement:@"end"];
	WFDelegateReference *assigning = [WFDelegateReference referenceToClass:@"WFRecordingListener"
		fields:@[ [self field:@"assignee" feel:@"\"bob\""] ]];
	for (NSNumber *event in @[ @(WFListenerEventCreate), @(WFListenerEventAssignment), @(WFListenerEventComplete),
	                           @(WFListenerEventDelete) ]) {
		[b addListener:[WFListener listenerOn:(WFListenerEvent)[event integerValue] delegate:assigning]
		    forElement:@"review"];
	}
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testExecutionAndTaskListeners
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[engine addPlugin:[[WFTestPlugin alloc] init]];
	[WFTestRecorder reset];
	NSString *pid = [self run:[self listened] engine:engine variables:nil];
	XCTAssertEqualObjects([WFTestRecorder entries],
		(@[ @"start@process", @"start@review", @"create@review", @"assignment@review" ]));
	/* The create listener assigned it. */
	XCTAssertEqualObjects([self task:@"review" of:pid engine:engine].assignee, @"bob");
	[WFTestRecorder reset];
	[self complete:@"review" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([WFTestRecorder entries],
		(@[ @"complete@review", @"end@review", @"take@done", @"end@end", @"end@process" ]));
}

- (void)testCanceledActivitiesEndToo
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[engine addPlugin:[[WFTestPlugin alloc] init]];
	NSString *pid = [self run:[self listened] engine:engine variables:nil];
	[WFTestRecorder reset];
	XCTAssertTrue([engine.runtimeService correlateMessage:@"withdraw" processInstanceId:pid variables:nil error:&error],
		@"%@", error);
	XCTAssertEqualObjects([WFTestRecorder entries],
		(@[ @"delete@review", @"end@review canceled", @"end@process" ]));

	NSString *deleted = [self run:[self listened] engine:engine variables:nil];
	[WFTestRecorder reset];
	XCTAssertTrue([engine.runtimeService deleteProcessInstance:deleted reason:@"test" error:&error], @"%@", error);
	XCTAssertEqualObjects([WFTestRecorder entries],
		(@[ @"delete@review", @"end@review canceled", @"end@process canceled" ]));
}

- (void)testReadsAndWritesDelegatesAndListeners
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\"><bpmn:extensionElements>"
		 @"<camunda:executionListener class=\"org.acme.Audit\" event=\"start\"/></bpmn:extensionElements>"
		 @"<bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:serviceTask id=\"call\" camunda:class=\"org.acme.Call\"><bpmn:extensionElements>"
		 @"<camunda:field name=\"url\"><camunda:string>https://example.org</camunda:string></camunda:field>"
		 @"<camunda:field name=\"retries\" expression=\"${tries + 1}\"/>"
		 @"<camunda:executionListener delegateExpression=\"${recorder}\" event=\"end\"/>"
		 @"</bpmn:extensionElements></bpmn:serviceTask>"
		 @"<bpmn:userTask id=\"t\"><bpmn:extensionElements>"
		 @"<camunda:taskListener delegateExpression=\"${recorder}\" event=\"create\">"
		 @"<camunda:field name=\"assignee\" stringValue=\"ann\"/></camunda:taskListener>"
		 @"</bpmn:extensionElements></bpmn:userTask><bpmn:endEvent id=\"e\"/>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"call\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"call\" targetRef=\"t\"><bpmn:extensionElements>"
		 @"<camunda:executionListener class=\"org.acme.Take\"/></bpmn:extensionElements></bpmn:sequenceFlow>"
		 @"<bpmn:sequenceFlow id=\"f3\" sourceRef=\"t\" targetRef=\"e\"/></bpmn:process></bpmn:definitions>";
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	NSString *written = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
	WFProcessDefinition *again = [WFBpmnReader definitionFromXMLString:written error:&error];
	XCTAssertNotNil(again, @"%@\n%@", error, written);
	for (WFProcessDefinition *each in @[ definition, again ]) {
		XCTAssertEqualObjects([[each.executionListeners firstObject] delegate].className, @"org.acme.Audit");
		WFTask *call = (WFTask *)[each nodeWithId:@"call"];
		XCTAssertEqualObjects(call.delegate.className, @"org.acme.Call");
		XCTAssertEqualObjects([call.delegate.fields valueForKey:@"name"], (@[ @"url", @"retries" ]));
		XCTAssertEqualObjects([[[call.delegate.fields lastObject] expression] expressionString], @"tries + 1");
		XCTAssertEqual([[call.executionListeners firstObject] event], WFListenerEventEnd);
		XCTAssertEqualObjects([[[call.executionListeners firstObject] delegate] delegateName], @"recorder");
		WFListener *created = [[(WFTask *)[each nodeWithId:@"t"] taskListeners] firstObject];
		XCTAssertEqual(created.event, WFListenerEventCreate);
		XCTAssertEqualObjects([[[created.delegate.fields firstObject] expression] valueWithVariables:@{}], @"ann");
		WFListener *take = [[[each flowWithId:@"f2"] listeners] firstObject];
		XCTAssertEqual(take.event, WFListenerEventTake);
		XCTAssertEqualObjects(take.delegate.className, @"org.acme.Take");
	}
	NSDictionary *refused = @{
		@"camunda:class=\"org.acme.Call\"": @"camunda:expression=\"${service.call(execution)}\"",
		@"delegateExpression=\"${recorder}\" event=\"end\"": @"delegateExpression=\"${beans.get('x')}\" event=\"end\"",
		@"event=\"create\"": @"event=\"timeout\"",
	};
	for (NSString *original in refused) {
		NSString *bad = [xml stringByReplacingOccurrencesOfString:original withString:[refused objectForKey:original]];
		XCTAssertNil([WFBpmnReader definitionFromXMLString:bad error:&error], @"%@", [refused objectForKey:original]);
	}
}

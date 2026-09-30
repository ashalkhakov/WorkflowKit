/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Link events

- (void)testALinkThrowGoesOnAtItsCatch
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"jump"];
	[[[b addStart:@"start"] addLinkThrow:@"toReview" link:@"review"] addLinkCatch:@"fromStart" link:@"review"];
	[[b addUserTask:@"check" name:@"Check" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"start" to:@"toReview"] connect:@"fromStart" to:@"check"];
	[b connect:@"check" to:@"end"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"check" ]);
	NSArray *passed = [[engine.historyService historicActivityInstancesForProcessInstance:pid]
		valueForKey:@"activityId"];
	XCTAssertTrue([passed containsObject:@"toReview"]);
	XCTAssertTrue([passed containsObject:@"fromStart"]);
	[self complete:@"check" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testLinksStayInTheirScope
{
	NSError *error = nil;
	WFDefinitionBuilder *inner = [WFDefinitionBuilder process:@"inner"];
	[[[[inner addStart:@"s"] addLinkThrow:@"out" link:@"elsewhere"] addLinkCatch:@"land" link:@"here"] addEnd:@"e"];
	[[inner connect:@"s" to:@"out"] connect:@"land" to:@"e"];
	XCTAssertNil([inner build:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"elsewhere"].location != NSNotFound, @"%@", error);

	WFDefinitionBuilder *twice = [WFDefinitionBuilder process:@"twice"];
	[[[[twice addStart:@"s"] addLinkThrow:@"go" link:@"a"] addLinkCatch:@"one" link:@"a"] addLinkCatch:@"two" link:@"a"];
	[[twice addEnd:@"e"] connect:@"s" to:@"go"];
	[[twice connect:@"one" to:@"e"] connect:@"two" to:@"e"];
	XCTAssertNil([twice build:&error]);

	WFDefinitionBuilder *entered = [WFDefinitionBuilder process:@"entered"];
	[[[[entered addStart:@"s"] addLinkThrow:@"go" link:@"a"] addLinkCatch:@"c" link:@"a"] addEnd:@"e"];
	[[[entered connect:@"s" to:@"go"] connect:@"s" to:@"c"] connect:@"c" to:@"e"];
	XCTAssertNil([entered build:&error]);
}

- (void)testReadsAndWritesLinkEvents
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\"><bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:intermediateThrowEvent id=\"go\"><bpmn:linkEventDefinition id=\"l1\" name=\"on\"/>"
		 @"</bpmn:intermediateThrowEvent>"
		 @"<bpmn:intermediateCatchEvent id=\"land\"><bpmn:linkEventDefinition id=\"l2\" name=\"on\"/>"
		 @"</bpmn:intermediateCatchEvent><bpmn:endEvent id=\"e\"/>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"go\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"land\" targetRef=\"e\"/>"
		 @"</bpmn:process></bpmn:definitions>";
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	XCTAssertEqualObjects([(WFEvent *)[definition nodeWithId:@"go"] linkName], @"on");
	NSString *written = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
	WFProcessDefinition *again = [WFBpmnReader definitionFromXMLString:written error:&error];
	XCTAssertNotNil(again, @"%@\n%@", error, written);
	XCTAssertEqual([(WFEvent *)[again nodeWithId:@"land"] trigger], WFEventTriggerLink);
	XCTAssertEqualObjects([(WFEvent *)[again nodeWithId:@"land"] linkName], @"on");
}

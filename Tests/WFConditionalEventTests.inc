/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Conditional events

/* start -> ready (waits for the condition) -> end */
- (WFProcessDefinition *)waitFor:(WFEventCondition *)condition
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"gate"];
	[[[[b addStart:@"start"] addConditionalCatch:@"ready" condition:@"stock > 0"] addEnd:@"end"]
		setCondition:condition forElement:@"ready"];
	[[b connect:@"start" to:@"ready"] connect:@"ready" to:@"end"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (WFEventCondition *)condition:(NSString *)text variable:(NSString *)name events:(NSArray *)events
{
	return [[WFEventCondition alloc] initWithExpression:[WFFeelExpression expressionWithString:text error:NULL]
	                                       variableName:name
	                                     variableEvents:events];
}

- (void)testACatchWaitsUntilItsConditionHolds
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFProcessDefinition *definition = [self waitFor:[self condition:@"stock > 0" variable:nil events:nil]];
	NSString *pid = [self run:definition engine:engine variables:@{ @"stock": @0 }];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"ready" ]);
	XCTAssertTrue([engine.runtimeService setVariables:(@{ @"stock": @0, @"other": @1 }) processInstanceId:pid
	                                            error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"ready" ]);
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"stock": @3 } processInstanceId:pid
	                                            error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"WFEventSubscription" engine:engine] count], (NSUInteger)0);

	/* Holding already, it does not wait. */
	NSString *stocked = [self run:definition engine:engine variables:@{ @"stock": @5 }];
	XCTAssertTrue([self ended:stocked engine:engine]);
}

- (void)testVariableNameAndEventsNarrowWhatIsSeen
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	/* Only a change to "stock" makes it look. */
	NSString *pid = [self run:[self waitFor:[self condition:@"stock > 0 and open" variable:@"stock" events:nil]]
	                   engine:engine variables:@{ @"stock": @1, @"open": @NO }];
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"open": @YES } processInstanceId:pid error:&error]);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"ready" ]);
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"stock": @2 } processInstanceId:pid error:&error]);
	XCTAssertTrue([self ended:pid engine:engine]);

	/* Only a variable's creation. */
	NSString *created = [self run:[self waitFor:[self condition:@"stock > 0" variable:nil events:@[ @"create" ]]]
	                       engine:engine variables:@{ @"stock": @0 }];
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"stock": @4 } processInstanceId:created error:&error]);
	XCTAssertEqualObjects([self active:created engine:engine], @[ @"ready" ]);
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"restocked": @YES } processInstanceId:created
	                                            error:&error]);
	XCTAssertTrue([self ended:created engine:engine]);
}

/* A variable removed is gone, and its removal is a "delete" change. */
- (void)testRemovingVariables
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self waitFor:[self condition:@"hold = null" variable:@"hold" events:@[ @"delete" ]]]
	                   engine:engine variables:@{ @"hold": @YES, @"kept": @1 }];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"ready" ]);
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"hold": [NSNull null] } processInstanceId:pid error:&error]);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"ready" ], @"an update is not a removal");
	XCTAssertTrue([engine.runtimeService removeVariables:(@[ @"hold", @"never" ]) processInstanceId:pid error:&error],
		@"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);

	NSString *other = [self run:[self waitFor:[self condition:@"false" variable:nil events:nil]] engine:engine
	                  variables:@{ @"a": @1, @"b": @2 }];
	XCTAssertTrue([engine.runtimeService removeVariables:@[ @"a" ] processInstanceId:other error:&error], @"%@", error);
	XCTAssertEqualObjects([engine.runtimeService variablesForProcessInstance:other error:NULL], @{ @"b": @2 });
	XCTAssertEqualObjects([[self variables:other engine:engine] objectForKey:@"a"], @1, @"history keeps it");
	XCTAssertFalse([engine.runtimeService removeVariables:@[ @"b" ] processInstanceId:@"nothing" error:&error]);
}

/* start -> work (a user task with a conditional boundary event) -> end;
 * the boundary -> escalated */
- (WFProcessDefinition *)watched:(BOOL)interrupting
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"watched"];
	[[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"] addEnd:@"end"]
		addUserTask:@"escalated" name:@"Escalated" assignee:@"boss"];
	[[b addBoundaryConditional:@"urgent" onTask:@"work" condition:@"priority >= 3" interrupting:interrupting]
		addEnd:@"handled"];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[[b connect:@"urgent" to:@"escalated"] connect:@"escalated" to:@"handled"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testAnInterruptingBoundaryConditionCancelsTheActivity
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self watched:YES] engine:engine variables:@{ @"priority": @1 }];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"work" ]);
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"priority": @5 } processInstanceId:pid
	                                            error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"escalated" ]);

	/* Holding as the activity starts, it fires at once. */
	NSString *urgent = [self run:[self watched:YES] engine:engine variables:@{ @"priority": @4 }];
	XCTAssertEqualObjects([self active:urgent engine:engine], @[ @"escalated" ]);
}

- (void)testANonInterruptingBoundaryConditionFiresOnEachChange
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self watched:NO] engine:engine variables:@{ @"priority": @1 }];
	for (NSNumber *priority in @[ @3, @4 ]) {
		XCTAssertTrue([engine.runtimeService setVariables:@{ @"priority": priority } processInstanceId:pid
		                                            error:&error], @"%@", error);
	}
	NSArray *tasks = [[engine.taskService tasksForProcessInstance:pid] valueForKey:@"taskDefinitionKey"];
	XCTAssertEqualObjects([tasks sortedArrayUsingSelector:@selector(compare:)], (@[ @"escalated", @"escalated", @"work" ]));
	[self complete:@"work" of:pid engine:engine variables:nil];
	/* Its activity done, the event is no longer armed. */
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"priority": @9 } processInstanceId:pid error:&error]);
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:pid] count], (NSUInteger)2);
}

- (void)testATaskCompletionsVariablesAreSeen
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"beside"];
	[[[[b addStart:@"start"] addParallel:@"fork"] addUserTask:@"enter" name:@"Enter" assignee:@"ann"]
		addConditionalCatch:@"entered" condition:@"total != null"];
	[[[b addParallel:@"join"] addEnd:@"end"] connect:@"start" to:@"fork"];
	[[[b connect:@"fork" to:@"enter"] connect:@"fork" to:@"entered"] connect:@"enter" to:@"join"];
	[[b connect:@"entered" to:@"join"] connect:@"join" to:@"end"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"enter", @"entered" ]));
	[self complete:@"enter" of:pid engine:engine variables:@{ @"total": @10 }];
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testConditionalEventSubprocesses
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	for (NSNumber *interrupting in @[ @YES, @NO ]) {
		WFDefinitionBuilder *handler = [WFDefinitionBuilder process:@"onCancel"];
		[[[handler addConditionalStart:@"canceled" condition:@"cancel = true"]
			addUserTask:@"refund" name:@"Refund" assignee:@"ann"] addEnd:@"refunded"];
		[[handler connect:@"canceled" to:@"refund"] connect:@"refund" to:@"refunded"];
		[handler setInterrupting:[interrupting boolValue] forElement:@"canceled"];
		WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"order"];
		[[[b addStart:@"start"] addUserTask:@"ship" name:@"Ship" assignee:@"ann"] addEnd:@"end"];
		[[b connect:@"start" to:@"ship"] connect:@"ship" to:@"end"];
		[b addEventSubProcess:@"onCancel" name:@"On cancel" inner:[handler build:&error]];
		NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"cancel": @NO }];
		XCTAssertTrue([engine.runtimeService setVariables:@{ @"cancel": @YES } processInstanceId:pid
		                                            error:&error], @"%@", error);
		NSArray *expected = [interrupting boolValue] ? @[ @"refund" ] : @[ @"refund", @"ship" ];
		XCTAssertEqualObjects([self active:pid engine:engine], expected, @"interrupting %@", interrupting);
	}
}

- (void)testAConditionBehindAnEventBasedGateway
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"either"];
	[[[[b addStart:@"start"] addEventBased:@"choice"] addMessageCatch:@"told" message:@"stop"]
		addConditionalCatch:@"approved" condition:@"approved"];
	[[b addEnd:@"stopped"] addEnd:@"done"];
	[[[b connect:@"start" to:@"choice"] connect:@"choice" to:@"told"] connect:@"choice" to:@"approved"];
	[[b connect:@"told" to:@"stopped"] connect:@"approved" to:@"done"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"approved": @NO }];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"choice" ]);
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"approved": @YES } processInstanceId:pid
	                                            error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"WFEventSubscription" engine:engine] count], (NSUInteger)0);
}

- (void)testConditionalStartEvents
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	XCTAssertNil([engine.runtimeService evaluateStartConditions:@{} businessKey:nil error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorNoPath);

	for (NSArray *process in @[ @[ @"big", @"amount > 1000" ], @[ @"small", @"amount <= 1000" ] ]) {
		WFDefinitionBuilder *b = [WFDefinitionBuilder process:[process firstObject]];
		[[[b addConditionalStart:@"start" condition:[process lastObject]]
			addUserTask:@"review" name:@"Review" assignee:@"ann"] addEnd:@"end"];
		[[b connect:@"start" to:@"review"] connect:@"review" to:@"end"];
		[self deploy:[b build:&error] engine:engine];
	}
	NSArray *started = [engine.runtimeService evaluateStartConditions:@{ @"amount": @5000 } businessKey:@"o-1"
	                                                            error:&error];
	XCTAssertEqual([started count], (NSUInteger)1, @"%@", error);
	WFProcessInstance *instance = [started lastObject];
	XCTAssertEqualObjects(instance.businessKey, @"o-1");
	XCTAssertEqualObjects([[self variables:instance.processInstanceId engine:engine] objectForKey:@"amount"], @5000);
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:instance.processInstanceId]
		definitionKey], @"big");

	/* A suspended definition is passed by; none holding is no error. */
	NSString *small = [[engine.repositoryService latestDefinitionForKey:@"small" error:NULL] definitionId];
	XCTAssertTrue([engine.repositoryService suspendDefinition:small includeInstances:NO error:&error]);
	started = [engine.runtimeService evaluateStartConditions:@{ @"amount": @5 } businessKey:nil error:&error];
	XCTAssertNotNil(started, @"%@", error);
	XCTAssertEqual([started count], (NSUInteger)0);
}

- (void)testReadsAndWritesConditionalEvents
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" "
		 @"xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\"><bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:intermediateCatchEvent id=\"wait\">"
		 @"<bpmn:conditionalEventDefinition id=\"c1\" camunda:variableName=\"stock\" "
		 @"camunda:variableEvents=\"create, update\">"
		 @"<bpmn:condition xsi:type=\"bpmn:tFormalExpression\">${stock &gt; 0}</bpmn:condition>"
		 @"</bpmn:conditionalEventDefinition></bpmn:intermediateCatchEvent>"
		 @"<bpmn:userTask id=\"t\"/>"
		 @"<bpmn:boundaryEvent id=\"b\" attachedToRef=\"t\" cancelActivity=\"false\">"
		 @"<bpmn:conditionalEventDefinition id=\"c2\">"
		 @"<bpmn:condition xsi:type=\"bpmn:tFormalExpression\">=late</bpmn:condition>"
		 @"</bpmn:conditionalEventDefinition></bpmn:boundaryEvent>"
		 @"<bpmn:endEvent id=\"e\"/><bpmn:endEvent id=\"e2\"/>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"wait\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"wait\" targetRef=\"t\"/>"
		 @"<bpmn:sequenceFlow id=\"f3\" sourceRef=\"t\" targetRef=\"e\"/>"
		 @"<bpmn:sequenceFlow id=\"f4\" sourceRef=\"b\" targetRef=\"e2\"/>"
		 @"</bpmn:process></bpmn:definitions>";
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	WFEventCondition *condition = [(WFEvent *)[definition nodeWithId:@"wait"] condition];
	XCTAssertEqualObjects([condition.expression expressionString], @"stock > 0");
	XCTAssertEqualObjects(condition.variableName, @"stock");
	XCTAssertEqualObjects(condition.variableEvents, (@[ @"create", @"update" ]));
	XCTAssertFalse([(WFEvent *)[definition nodeWithId:@"b"] isInterrupting]);

	NSString *written = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
	WFProcessDefinition *again = [WFBpmnReader definitionFromXMLString:written error:&error];
	XCTAssertNotNil(again, @"%@\n%@", error, written);
	WFEventCondition *reread = [(WFEvent *)[again nodeWithId:@"wait"] condition];
	XCTAssertEqualObjects([reread.expression expressionString], @"stock > 0");
	XCTAssertEqualObjects(reread.variableEvents, (@[ @"create", @"update" ]));
	XCTAssertEqualObjects([[(WFEvent *)[again nodeWithId:@"b"] condition].expression expressionString], @"late");

	NSString *wrong = [xml stringByReplacingOccurrencesOfString:@"create, update" withString:@"create, change"];
	XCTAssertNil([WFBpmnReader definitionFromXMLString:wrong error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"change"].location != NSNotFound, @"%@", error);
}

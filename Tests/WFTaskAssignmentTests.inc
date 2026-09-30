/* Included into a class of each backend's suite: see WFTestCase.h. */

/* start -> approve (a user task with the assignment) -> end */
- (WFProcessDefinition *)approval:(NSDictionary *)assignment
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"approval"];
	[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:nil] addEnd:@"end"];
	[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"end"];
	[b setAssignment:assignment forElement:@"approve"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testCandidatesClaimAndGiveBack
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self approval:@{ @"candidateUsers": @"ann, bob",
	                                            @"candidateGroups": @"managers" }]
	                   engine:engine variables:nil];
	WFWorkItem *task = [self task:@"approve" of:pid engine:engine];
	XCTAssertNil(task.assignee);
	XCTAssertEqualObjects(task.candidateUsers, (@[ @"ann", @"bob" ]));
	XCTAssertEqualObjects(task.candidateGroups, @[ @"managers" ]);

	XCTAssertEqual([[engine.taskService tasksForCandidateUser:@"ann" groups:nil] count], (NSUInteger)1);
	XCTAssertEqual([[engine.taskService tasksForCandidateUser:@"cy" groups:@[ @"managers" ]] count], (NSUInteger)1);
	XCTAssertEqual([[engine.taskService tasksForCandidateUser:@"cy" groups:@[ @"staff" ]] count], (NSUInteger)0);
	XCTAssertEqual([[engine.taskService tasksForCandidateGroup:@"managers"] count], (NSUInteger)1);

	XCTAssertTrue([engine.taskService claimTask:task.taskId user:@"ann" error:&error], @"%@", error);
	/* Claimed: no longer offered, and nobody else can take it. */
	XCTAssertEqual([[engine.taskService tasksForCandidateUser:@"bob" groups:nil] count], (NSUInteger)0);
	XCTAssertEqual([[engine.taskService tasksForAssignee:@"ann"] count], (NSUInteger)1);
	XCTAssertFalse([engine.taskService claimTask:task.taskId user:@"bob" error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorInvalidState);
	XCTAssertTrue([engine.taskService claimTask:task.taskId user:@"ann" error:&error], @"%@", error);

	XCTAssertTrue([engine.taskService unclaimTask:task.taskId error:&error], @"%@", error);
	XCTAssertEqual([[engine.taskService tasksForCandidateUser:@"bob" groups:nil] count], (NSUInteger)1);
	XCTAssertTrue([engine.taskService setAssignee:@"dan" forTask:task.taskId error:&error], @"%@", error);
	XCTAssertEqualObjects([[engine.taskService taskWithId:task.taskId error:NULL] assignee], @"dan");
	XCTAssertEqualObjects([[[engine.historyService historicTaskInstancesForProcessInstance:pid] lastObject]
		assignee], @"dan");
	[self complete:@"approve" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"WFIdentityLink" engine:engine] count], (NSUInteger)0);
}

- (void)testAssignmentFromExpressions
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSDate *before = [NSDate date];
	NSString *pid = [self run:[self approval:@{
		@"assignee": @"${owner}",
		@"candidateGroups": @"=[team, \"auditors\"]",
		@"dueDate": @"=now() + @\"P2D\"",
		@"followUpDate": @"2030-01-01T09:00:00Z",
		@"priority": @"${urgency}",
	}] engine:engine variables:@{ @"owner": @"ann", @"team": @"sales", @"urgency": @80 }];
	WFWorkItem *task = [self task:@"approve" of:pid engine:engine];
	XCTAssertEqualObjects(task.assignee, @"ann");
	XCTAssertEqualObjects(task.candidateGroups, (@[ @"auditors", @"sales" ]));
	XCTAssertEqualWithAccuracy([task.dueDate timeIntervalSinceDate:before], 2 * 86400.0, 5.0);
	XCTAssertEqualObjects(task.followUpDate, [NSDate dateWithTimeIntervalSince1970:1893488400]);
	XCTAssertEqual(task.priority, (NSInteger)80);
}

- (void)testEachInstanceAssignedFromItsElement
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"reviews"];
	[[[b addStart:@"start"] addUserTask:@"review" name:@"Review" assignee:nil] addEnd:@"end"];
	[[b connect:@"start" to:@"review"] connect:@"review" to:@"end"];
	[b setAssignment:@{ @"assignee": @"${reviewer}" } forElement:@"review"];
	[b setMultiInstanceSequential:NO loopCardinality:nil collection:@"reviewers" elementVariable:@"reviewer"
	          completionCondition:nil forElement:@"review"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"reviewers": @[ @"ann", @"bob" ] }];
	NSArray *assignees = [[[engine.taskService tasksForProcessInstance:pid] valueForKey:@"assignee"]
		sortedArrayUsingSelector:@selector(compare:)];
	XCTAssertEqualObjects(assignees, (@[ @"ann", @"bob" ]));
}

- (void)testAssignmentMistakes
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"bad"];
	[[[b addStart:@"start"] addUserTask:@"t" name:@"T" assignee:nil] addEnd:@"end"];
	[[b connect:@"start" to:@"t"] connect:@"t" to:@"end"];
	[b setAssignment:@{ @"priority": @"high" } forElement:@"t"];
	XCTAssertNil([b build:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"priority"].location != NSNotFound, @"%@", error);

	/* A value of the wrong kind fails the command that creates the task. */
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self approval:@{ @"assignee": @"${owner}" }] engine:engine];
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"approval"
		variables:@{ @"owner": @42 } error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"assignee"].location != NSNotFound, @"%@", error);
}

- (void)testReadsAndWritesCamundaAssignment
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\"><bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:userTask id=\"t\" camunda:assignee=\"${initiator}\" camunda:candidateUsers=\"ann,bob\" "
		 @"camunda:candidateGroups=\"${groups}\" camunda:dueDate=\"2030-01-01T09:00:00Z\" camunda:priority=\"70\"/>"
		 @"<bpmn:endEvent id=\"e\"/><bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"t\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"t\" targetRef=\"e\"/></bpmn:process></bpmn:definitions>";
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	WFTask *task = (WFTask *)[definition nodeWithId:@"t"];
	XCTAssertNil(task.assignee);
	XCTAssertEqualObjects([task.assigneeExpression expressionString], @"initiator");
	XCTAssertEqualObjects([task.candidateUsers expressionString], @"[\"ann\", \"bob\"]");

	NSString *written = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
	for (NSString *attribute in @[ @"camunda:assignee=\"=initiator\"", @"camunda:candidateUsers=\"ann,bob\"",
	                               @"camunda:candidateGroups=\"=groups\"",
	                               @"camunda:dueDate=\"2030-01-01T09:00:00Z\"", @"camunda:priority=\"70\"" ]) {
		XCTAssertTrue([written rangeOfString:attribute].location != NSNotFound, @"%@ in %@", attribute, written);
	}
	WFProcessDefinition *again = [WFBpmnReader definitionFromXMLString:written error:&error];
	[self assertNode:task matches:[again nodeWithId:@"t"]];
}

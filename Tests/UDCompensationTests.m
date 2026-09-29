#import "UDWorkflowTestCase.h"

@interface UDCompensationTests : UDWorkflowTestCase
@end

@implementation UDCompensationTests

/* A user task with a compensation handler, itself a user task. */
- (void)add:(NSString *)task undoneBy:(NSString *)handler to:(UDDefinitionBuilder *)b
{
	[[b addUserTask:task name:task assignee:@"ann"] addUserTask:handler name:handler assignee:@"ann"];
	[b addBoundaryCompensation:[@"undo_" stringByAppendingString:task] onTask:task handler:handler];
}

/* start -> book -> charge -> undo (compensation throw of target) -> after -> end */
- (UDProcessDefinition *)trip:(NSString *)target
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"trip"];
	[b addStart:@"start"];
	[self add:@"book" undoneBy:@"cancelBooking" to:b];
	[self add:@"charge" undoneBy:@"refund" to:b];
	[[[b addCompensationThrow:@"undo" activity:target] addUserTask:@"after" name:@"After" assignee:@"ann"]
		addEnd:@"end"];
	[[[b connect:@"start" to:@"book"] connect:@"book" to:@"charge"] connect:@"charge" to:@"undo"];
	[[b connect:@"undo" to:@"after"] connect:@"after" to:@"end"];
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testHandlersRunNewestFirstAndTheThrowerWaits
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self trip:nil] engine:engine variables:nil];
	[self complete:@"book" of:pid engine:engine variables:nil];
	[self complete:@"charge" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"refund" ]);
	[self complete:@"refund" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"cancelBooking" ]);
	[self complete:@"cancelBooking" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	/* Compensated once: nothing waits any more. */
	XCTAssertEqual([[self rows:@"UDEventSubscription" engine:engine] count], (NSUInteger)0);
}

- (void)testActivityRefCompensatesOnlyThatActivity
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self trip:@"book"] engine:engine variables:nil];
	[self complete:@"book" of:pid engine:engine variables:nil];
	[self complete:@"charge" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"cancelBooking" ]);
	[self complete:@"cancelBooking" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
}

- (void)testNothingCompletedNothingToCompensate
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"early"];
	[[[b addStart:@"start"] addCompensationThrow:@"undo" activity:nil] addEnd:@"end"];
	[[b connect:@"start" to:@"undo"] connect:@"undo" to:@"end"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testAnInterruptedActivityIsNotCompensated
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"cut"];
	[b addStart:@"start"];
	[self add:@"book" undoneBy:@"cancelBooking" to:b];
	[[b addBoundaryTimer:@"late" onTask:@"book" duration:3600 interrupting:YES]
		addCompensationEnd:@"undo" activity:nil];
	[[b addEnd:@"end"] connect:@"start" to:@"book"];
	[[b connect:@"book" to:@"end"] connect:@"late" to:@"undo"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	UDJob *timer = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertTrue([engine.managementService executeJob:timer.jobId error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertNil([self task:@"cancelBooking" of:pid engine:engine]);
}

/* A subprocess's completed activities are compensated from outside it --
 * or its own handler is, when it has one. */
- (UDProcessDefinition *)nested:(BOOL)ownHandler target:(NSString *)target
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"sub"];
	[inner addStart:@"s"];
	[self add:@"reserve" undoneBy:@"release" to:inner];
	[inner addEnd:@"e"];
	[[inner connect:@"s" to:@"reserve"] connect:@"reserve" to:@"e"];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"outer"];
	[[[b addStart:@"start"] addSubProcess:@"sub" name:@"Sub" inner:[inner build:&error]]
		addCompensationEnd:@"undo" activity:target];
	[[b connect:@"start" to:@"sub"] connect:@"sub" to:@"undo"];
	if (ownHandler) {
		[b addUserTask:@"releaseAll" name:@"Release all" assignee:@"ann"];
		[b addBoundaryCompensation:@"undoSub" onTask:@"sub" handler:@"releaseAll"];
	}
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testASubprocessIsCompensatedFromInside
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	for (id target in @[ [NSNull null], @"sub" ]) {
		NSString *pid = [self run:[self nested:NO target:target == [NSNull null] ? nil : target]
		                   engine:engine variables:nil];
		[self complete:@"reserve" of:pid engine:engine variables:nil];
		XCTAssertEqualObjects([self active:pid engine:engine], @[ @"release" ], @"%@", target);
		[self complete:@"release" of:pid engine:engine variables:nil];
		XCTAssertTrue([self ended:pid engine:engine], @"%@", target);
	}
}

- (void)testASubprocessHandlerStandsForItsInside
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self nested:YES target:nil] engine:engine variables:nil];
	[self complete:@"reserve" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"releaseAll" ]);
	[self complete:@"releaseAll" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testEachInstanceOfAMultiInstanceActivityIsCompensated
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"many"];
	[b addStart:@"start"];
	[self add:@"ship" undoneBy:@"recall" to:b];
	[[b addCompensationEnd:@"undo" activity:nil] connect:@"start" to:@"ship"];
	[b connect:@"ship" to:@"undo"];
	[b setMultiInstanceSequential:NO loopCardinality:@"3" collection:nil elementVariable:nil
	          completionCondition:nil forElement:@"ship"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	for (UDWorkItem *task in [engine.taskService tasksForProcessInstance:pid]) {
		XCTAssertTrue([engine.taskService completeTask:task.taskId variables:nil error:&error], @"%@", error);
	}
	for (int i = 0; i < 3; i++) {
		XCTAssertEqualObjects([self active:pid engine:engine], @[ @"recall" ], @"%d", i);
		[self complete:@"recall" of:pid engine:engine variables:nil];
	}
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testReadsCamundaModelerCompensation
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" id=\"d\">"
		 @"<bpmn:escalation id=\"Escalation_1\" escalationCode=\"LATE\"/>"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\">"
		 @"<bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:userTask id=\"book\"/>"
		 @"<bpmn:boundaryEvent id=\"undoBook\" attachedToRef=\"book\"><bpmn:compensateEventDefinition/></bpmn:boundaryEvent>"
		 @"<bpmn:userTask id=\"cancel\" isForCompensation=\"true\"/>"
		 @"<bpmn:intermediateThrowEvent id=\"late\"><bpmn:escalationEventDefinition escalationRef=\"Escalation_1\"/>"
		 @"</bpmn:intermediateThrowEvent>"
		 @"<bpmn:endEvent id=\"e\"><bpmn:compensateEventDefinition activityRef=\"book\"/></bpmn:endEvent>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"book\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"book\" targetRef=\"late\"/>"
		 @"<bpmn:sequenceFlow id=\"f3\" sourceRef=\"late\" targetRef=\"e\"/>"
		 @"<bpmn:association id=\"a1\" associationDirection=\"One\" sourceRef=\"undoBook\" targetRef=\"cancel\"/>"
		 @"</bpmn:process></bpmn:definitions>";
	UDProcessDefinition *definition = [UDBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	XCTAssertEqualObjects([(UDEvent *)[definition nodeWithId:@"undoBook"] compensationHandlerId], @"cancel");
	XCTAssertTrue([[definition nodeWithId:@"cancel"] isForCompensation]);
	XCTAssertEqualObjects([(UDEvent *)[definition nodeWithId:@"late"] escalationCode], @"LATE");
	XCTAssertEqualObjects([(UDEvent *)[definition nodeWithId:@"e"] activityRef], @"book");

	NSString *noHandler = [xml stringByReplacingOccurrencesOfString:
		@"<bpmn:association id=\"a1\" associationDirection=\"One\" sourceRef=\"undoBook\" targetRef=\"cancel\"/>"
		withString:@""];
	XCTAssertNil([UDBpmnReader definitionFromXMLString:noHandler error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"needs a handler"].location != NSNotFound,
		@"%@", error);
	NSString *noWait = [xml stringByReplacingOccurrencesOfString:@"activityRef=\"book\""
		withString:@"activityRef=\"book\" waitForCompletion=\"false\""];
	XCTAssertNil([UDBpmnReader definitionFromXMLString:noWait error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"waitForCompletion"].location != NSNotFound,
		@"%@", error);
}

@end

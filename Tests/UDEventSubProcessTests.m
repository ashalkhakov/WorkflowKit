#import "UDWorkflowTestCase.h"

@interface UDEventSubProcessTests : UDWorkflowTestCase
@end

@implementation UDEventSubProcessTests

/* An event subprocess: its start (added by start), then a user task
 * named task, then an end. */
- (UDProcessDefinition *)handler:(NSString *)elementId
                           start:(void (^)(UDDefinitionBuilder *b))start
                            task:(NSString *)task
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:elementId];
	start(b);
	[[b addUserTask:task name:task assignee:@"ann"] addEnd:[elementId stringByAppendingString:@"_end"]];
	[[b connect:@"handlerStart" to:task] connect:task to:[elementId stringByAppendingString:@"_end"]];
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

/* start -> work (a user task) -> end, with the event subprocess. */
- (UDProcessDefinition *)process:(UDProcessDefinition *)handler
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"main"];
	[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[b addEventSubProcess:@"handler" name:@"Handler" inner:handler];
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)correlate:(NSString *)message to:(NSString *)pid engine:(UDProcessEngine *)engine
{
	NSError *error = nil;
	XCTAssertTrue([engine.runtimeService correlateMessage:message processInstanceId:pid
	                                            variables:@{ @"reason": message } error:&error], @"%@", error);
	[engine waitUntilSettled:pid timeout:10.0];
}

- (UDHistoricActivityInstance *)history:(NSString *)activityId
                                     of:(NSString *)pid
                                 engine:(UDProcessEngine *)engine
{
	for (UDHistoricActivityInstance *row in [engine.historyService historicActivityInstancesForProcessInstance:pid]) {
		if ([row.activityId isEqualToString:activityId]) {
			return row;
		}
	}
	return nil;
}

- (void)testInterruptingMessageTakesOverTheProcess
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self process:[self handler:@"handler" start:^(UDDefinitionBuilder *b) {
		[b addMessageStart:@"handlerStart" message:@"cancel"];
	} task:@"undo"]] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"work" ]);
	[self correlate:@"cancel" to:pid engine:engine];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"undo" ]);
	XCTAssertNil([self task:@"work" of:pid engine:engine]);
	XCTAssertTrue([self history:@"work" of:pid engine:engine].canceled);
	XCTAssertEqualObjects([self history:@"handler" of:pid engine:engine].activityType, @"eventSubProcess");
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"reason"], @"cancel");
	/* Interrupting: it fires once; nothing waits for the message now. */
	NSError *error = nil;
	XCTAssertFalse([engine.runtimeService correlateMessage:@"cancel" processInstanceId:pid
	                                             variables:nil error:&error]);
	[self complete:@"undo" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testNonInterruptingMessageRunsBesideAndAgain
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self process:[self handler:@"handler" start:^(UDDefinitionBuilder *b) {
		[[b addMessageStart:@"handlerStart" message:@"ping"] setInterrupting:NO forElement:@"handlerStart"];
	} task:@"answer"]] engine:engine variables:nil];
	[self correlate:@"ping" to:pid engine:engine];
	[self correlate:@"ping" to:pid engine:engine];
	NSArray *tasks = [engine.taskService tasksForProcessInstance:pid];
	XCTAssertEqual([tasks count], (NSUInteger)3);
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"answer", @"work" ]));
	/* The main path ends; the process waits for the handlers. */
	[self complete:@"work" of:pid engine:engine variables:nil];
	XCTAssertFalse([self ended:pid engine:engine]);
	for (UDWorkItem *task in [engine.taskService tasksForProcessInstance:pid]) {
		XCTAssertTrue([engine.taskService completeTask:task.taskId variables:nil error:&error], @"%@", error);
	}
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"UDEventSubscription" engine:engine] count], (NSUInteger)0);
}

- (void)testTimerInsideASubprocess
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"sub"];
	[[[inner addStart:@"s"] addUserTask:@"slow" name:@"Slow" assignee:@"ann"] addEnd:@"e"];
	[[inner connect:@"s" to:@"slow"] connect:@"slow" to:@"e"];
	[inner addEventSubProcess:@"timeout" name:@"Timeout" inner:[self handler:@"timeout"
		start:^(UDDefinitionBuilder *b) {
			[b addTimerStart:@"handlerStart" duration:3600];
		} task:@"late"]];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"outer"];
	[[[[b addStart:@"start"] addSubProcess:@"sub" name:@"Sub" inner:[inner build:&error]]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"sub"] connect:@"sub" to:@"after"] connect:@"after" to:@"end"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"slow" ]);
	UDJob *timer = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(timer.activityId, @"handlerStart");
	XCTAssertTrue([engine.managementService executeJob:timer.jobId error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"late" ]);
	[self complete:@"late" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
}

/* An error event subprocess inside the subprocess catches before an error
 * boundary on the subprocess; an error thrown inside it goes outward. */
- (UDProcessDefinition *)guarded:(NSString *)handlerTopic
{
	NSError *error = nil;
	UDDefinitionBuilder *handler = [UDDefinitionBuilder process:@"recover"];
	[[[handler addErrorStart:@"handlerStart" errorRef:@"BOOM"] addServiceTask:@"fix" action:handlerTopic]
		addEnd:@"fixed"];
	[[handler connect:@"handlerStart" to:@"fix"] connect:@"fix" to:@"fixed"];
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"sub"];
	[[[inner addStart:@"s"] addServiceTask:@"try" action:@"try"] addEnd:@"e"];
	[[inner connect:@"s" to:@"try"] connect:@"try" to:@"e"];
	[inner addEventSubProcess:@"recover" name:@"Recover" inner:[handler build:&error]];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"outer"];
	[[[[b addStart:@"start"] addSubProcess:@"sub" name:@"Sub" inner:[inner build:&error]]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"sub"] connect:@"sub" to:@"after"] connect:@"after" to:@"end"];
	[[b addUserTask:@"escalated" name:@"Escalated" assignee:@"boss"] addEnd:@"escalatedEnd"];
	[b addBoundaryError:@"onError" onTask:@"sub" errorRef:nil interrupting:YES];
	[[b connect:@"onError" to:@"escalated"] connect:@"escalated" to:@"escalatedEnd"];
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testErrorEventSubprocessCatchesBeforeTheBoundary
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.bpmnErrors setObject:@"BOOM" forKey:@"try"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self guarded:@"fix"] engine:engine variables:nil];
	XCTAssertTrue([self waitForActive:@"after" in:pid engine:engine]);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	XCTAssertNotNil([self history:@"fix" of:pid engine:engine]);
	XCTAssertTrue([self history:@"try" of:pid engine:engine].canceled);
}

- (void)testAnErrorInsideTheHandlerGoesOutward
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.bpmnErrors setObject:@"BOOM" forKey:@"try"];
	[h.bpmnErrors setObject:@"BOOM" forKey:@"fix"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self guarded:@"fix"] engine:engine variables:nil];
	XCTAssertTrue([self waitForActive:@"escalated" in:pid engine:engine]);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"escalated" ]);
}

- (void)testSignalStartsANonInterruptingHandler
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self process:[self handler:@"handler" start:^(UDDefinitionBuilder *b) {
		[[b addSignalStart:@"handlerStart" signal:@"audit"] setInterrupting:NO forElement:@"handlerStart"];
	} task:@"note"]] engine:engine variables:nil];
	XCTAssertTrue([engine.runtimeService signal:@"audit" variables:nil error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"note", @"work" ]));
}

/* The scope's own waits survive an event-based gateway on the same
 * execution picking its event. */
- (void)testAnEventBasedGatewayLeavesTheScopesWaits
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"main"];
	[[[b addStart:@"start"] addEventBased:@"race"] addMessageCatch:@"go" message:@"go"];
	[[[b addTimerCatch:@"wait" duration:3600] addUserTask:@"work" name:@"Work" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"start" to:@"race"] connect:@"race" to:@"go"];
	[[b connect:@"race" to:@"wait"] connect:@"go" to:@"work"];
	[[b connect:@"wait" to:@"work"] connect:@"work" to:@"end"];
	[b addEventSubProcess:@"handler" name:@"Handler" inner:[self handler:@"handler"
		start:^(UDDefinitionBuilder *h) {
			[[h addMessageStart:@"handlerStart" message:@"ping"] setInterrupting:NO forElement:@"handlerStart"];
		} task:@"answer"]];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	[self correlate:@"go" to:pid engine:engine];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"work" ]);
	/* The gateway's timer is gone; the handler's message still waits. */
	XCTAssertEqual([[engine.managementService jobsForProcessInstance:pid] count], (NSUInteger)0);
	[self correlate:@"ping" to:pid engine:engine];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"answer", @"work" ]));
}

- (void)testTheScopesWaitsEndWithIt
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"sub"];
	[[[inner addStart:@"s"] addUserTask:@"step" name:@"Step" assignee:@"ann"] addEnd:@"e"];
	[[inner connect:@"s" to:@"step"] connect:@"step" to:@"e"];
	[inner addEventSubProcess:@"handler" name:@"Handler" inner:[self handler:@"handler"
		start:^(UDDefinitionBuilder *b) {
			[b addMessageStart:@"handlerStart" message:@"stop"];
		} task:@"stopped"]];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"outer"];
	[[[[b addStart:@"start"] addSubProcess:@"sub" name:@"Sub" inner:[inner build:&error]]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"sub"] connect:@"sub" to:@"after"] connect:@"after" to:@"end"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqual([[self rows:@"UDEventSubscription" engine:engine] count], (NSUInteger)1);
	[self complete:@"step" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	XCTAssertEqual([[self rows:@"UDEventSubscription" engine:engine] count], (NSUInteger)0);
	XCTAssertFalse([engine.runtimeService correlateMessage:@"stop" processInstanceId:pid
	                                             variables:nil error:&error]);
}

/* A handler beside a path at a call activity: the called instance goes
 * with the path it belongs to. */
- (void)testANonInterruptingHandlerBesideACallActivity
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	UDDefinitionBuilder *c = [UDDefinitionBuilder process:@"child"];
	[[[c addStart:@"s"] addUserTask:@"check" name:@"Check" assignee:@"ann"] addEnd:@"e"];
	[[c connect:@"s" to:@"check"] connect:@"check" to:@"e"];
	[self deploy:[c build:&error] engine:engine];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"main"];
	[[[b addStart:@"start"] addCallActivity:@"call" calledElement:@"child"] addEnd:@"end"];
	[[b connect:@"start" to:@"call"] connect:@"call" to:@"end"];
	[b addEventSubProcess:@"handler" name:@"Handler" inner:[self handler:@"handler"
		start:^(UDDefinitionBuilder *h) {
			[[h addMessageStart:@"handlerStart" message:@"ping"] setInterrupting:NO forElement:@"handlerStart"];
		} task:@"answer"]];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	[self correlate:@"ping" to:pid engine:engine];
	NSString *childId = [[[engine.runtimeService subProcessInstancesOf:pid error:NULL] lastObject]
		processInstanceId];
	XCTAssertNotNil(childId);
	[self complete:@"check" of:childId engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"answer" ]);
	[self complete:@"answer" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

static NSString *
UDEventSubProcessDocument(NSString *inside)
{
	return [NSString stringWithFormat:
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" id=\"d\">"
		 @"<bpmn:message id=\"Message_1\" name=\"cancel\"/>"
		 @"<bpmn:error id=\"Error_1\" errorCode=\"BOOM\"/>"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\">"
		 @"<bpmn:startEvent id=\"s\"/><bpmn:userTask id=\"t\"/><bpmn:endEvent id=\"e\"/>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"t\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"t\" targetRef=\"e\"/>"
		 @"%@</bpmn:process></bpmn:definitions>", inside];
}

- (void)testReadsEventSubprocessesAndRefusesMistakes
{
	NSError *error = nil;
	NSString *xml = UDEventSubProcessDocument(
		@"<bpmn:subProcess id=\"onCancel\" triggeredByEvent=\"true\">"
		 @"<bpmn:startEvent id=\"cs\" isInterrupting=\"false\"><bpmn:messageEventDefinition messageRef=\"Message_1\"/></bpmn:startEvent>"
		 @"<bpmn:endEvent id=\"ce\"/><bpmn:sequenceFlow id=\"c1\" sourceRef=\"cs\" targetRef=\"ce\"/>"
		 @"</bpmn:subProcess>"
		 @"<bpmn:subProcess id=\"onError\" triggeredByEvent=\"true\">"
		 @"<bpmn:startEvent id=\"es\"><bpmn:errorEventDefinition errorRef=\"Error_1\"/></bpmn:startEvent>"
		 @"<bpmn:endEvent id=\"ee\"/><bpmn:sequenceFlow id=\"e1\" sourceRef=\"es\" targetRef=\"ee\"/>"
		 @"</bpmn:subProcess>");
	UDProcessDefinition *definition = [UDBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	UDSubProcess *onCancel = (UDSubProcess *)[definition nodeWithId:@"onCancel"];
	XCTAssertTrue(onCancel.isTriggeredByEvent);
	XCTAssertFalse([onCancel.innerDefinition startEvent].isInterrupting);
	XCTAssertEqualObjects([onCancel.innerDefinition startEvent].messageName, @"cancel");
	UDSubProcess *onError = (UDSubProcess *)[definition nodeWithId:@"onError"];
	XCTAssertEqualObjects([onError.innerDefinition startEvent].errorRef, @"BOOM");
	XCTAssertTrue([onError.innerDefinition startEvent].isInterrupting);

	NSDictionary *refused = @{
		@"<bpmn:subProcess id=\"x\" triggeredByEvent=\"true\"><bpmn:startEvent id=\"xs\"/>"
		 @"<bpmn:endEvent id=\"xe\"/><bpmn:sequenceFlow id=\"x1\" sourceRef=\"xs\" targetRef=\"xe\"/>"
		 @"</bpmn:subProcess>": @"message, timer, signal or error start",
		@"<bpmn:subProcess id=\"x\" triggeredByEvent=\"true\">"
		 @"<bpmn:startEvent id=\"xs\"><bpmn:messageEventDefinition messageRef=\"Message_1\"/></bpmn:startEvent>"
		 @"<bpmn:endEvent id=\"xe\"/><bpmn:sequenceFlow id=\"x1\" sourceRef=\"xs\" targetRef=\"xe\"/>"
		 @"</bpmn:subProcess><bpmn:sequenceFlow id=\"x2\" sourceRef=\"t\" targetRef=\"x\"/>":
			@"no sequence flows",
		@"<bpmn:subProcess id=\"x\"><bpmn:startEvent id=\"xs\"><bpmn:errorEventDefinition/></bpmn:startEvent>"
		 @"<bpmn:endEvent id=\"xe\"/><bpmn:sequenceFlow id=\"x1\" sourceRef=\"xs\" targetRef=\"xe\"/>"
		 @"</bpmn:subProcess>": @"only start an event subprocess",
		@"<bpmn:subProcess id=\"x\" triggeredByEvent=\"true\">"
		 @"<bpmn:startEvent id=\"xs\" isInterrupting=\"false\"><bpmn:errorEventDefinition/></bpmn:startEvent>"
		 @"<bpmn:endEvent id=\"xe\"/><bpmn:sequenceFlow id=\"x1\" sourceRef=\"xs\" targetRef=\"xe\"/>"
		 @"</bpmn:subProcess>": @"always interrupts",
	};
	for (NSString *inside in refused) {
		error = nil;
		XCTAssertNil([UDBpmnReader definitionFromXMLString:UDEventSubProcessDocument(inside) error:&error],
			@"%@", inside);
		XCTAssertTrue([[error localizedDescription] rangeOfString:[refused objectForKey:inside]].location
			!= NSNotFound, @"%@: %@", [refused objectForKey:inside], error);
	}
}

@end

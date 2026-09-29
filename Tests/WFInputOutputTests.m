#import "WFTestCase.h"

@interface WFInputOutputTests : WFTestCase
@end

@implementation WFInputOutputTests

/* start -> work (a service task, topic work, mapped by map) -> after -> end */
- (WFProcessDefinition *)mapped:(void (^)(WFDefinitionBuilder *b))map
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"mapped"];
	[[[[b addStart:@"start"] addServiceTask:@"work" action:@"work"]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"work"] connect:@"work" to:@"after"] connect:@"after" to:@"end"];
	map(b);
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (WFExternalTask *)fetch:(NSString *)topic engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	NSArray *tasks = [engine.externalTaskService fetchAndLock:1 workerId:@"w" topics:@{ topic: @60 } error:&error];
	XCTAssertEqual([tasks count], (NSUInteger)1, @"%@", error);
	return [tasks lastObject];
}

- (void)testInputsAreTheActivitysOwnAndOutputsGoBack
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self mapped:^(WFDefinitionBuilder *b) {
		[b addInputParameter:@"amount" value:@"${order.total}" forElement:@"work"];
		[b addInputParameter:@"currency" value:@"EUR" forElement:@"work"];
		[b addInputParameter:@"nothing" value:nil forElement:@"work"];
		[b addOutputParameter:@"approvedAmount" value:@"=amount * 2" forElement:@"work"];
		[b addOutputParameter:@"decision" value:@"${verdict}" forElement:@"work"];
	}] engine:engine variables:@{ @"order": @{ @"total": @21 } }];

	WFExternalTask *task = [self fetch:@"work" engine:engine];
	XCTAssertEqualObjects([task.variables objectForKey:@"amount"], @21);
	XCTAssertEqualObjects([task.variables objectForKey:@"currency"], @"EUR");
	XCTAssertEqualObjects([task.variables objectForKey:@"nothing"], [NSNull null]);
	NSDictionary *outside = [engine.runtimeService variablesForProcessInstance:pid error:NULL];
	XCTAssertNil([outside objectForKey:@"amount"]);

	XCTAssertTrue([engine.externalTaskService complete:task.externalTaskId workerId:@"w"
	                                         variables:@{ @"verdict": @"yes" } error:&error], @"%@", error);
	outside = [engine.runtimeService variablesForProcessInstance:pid error:NULL];
	XCTAssertEqualObjects([outside objectForKey:@"approvedAmount"], @42);
	XCTAssertEqualObjects([outside objectForKey:@"decision"], @"yes");
	/* The activity's own variables went with it. */
	XCTAssertNil([outside objectForKey:@"amount"]);
	XCTAssertNil([outside objectForKey:@"currency"]);
}

- (void)testListsAndMaps
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self run:[self mapped:^(WFDefinitionBuilder *b) {
		[b addInputParameter:@"approvers"
		          expression:[WFFeelExpression expressionWithString:@"[\"ann\", boss]" error:NULL]
		          forElement:@"work"];
		[b addInputParameter:@"limits"
		          expression:[WFFeelExpression expressionWithString:@"{low: 10, high: cap}" error:NULL]
		          forElement:@"work"];
	}] engine:engine variables:@{ @"boss": @"bob", @"cap": @100 }];
	WFExternalTask *task = [self fetch:@"work" engine:engine];
	XCTAssertEqualObjects([task.variables objectForKey:@"approvers"], (@[ @"ann", @"bob" ]));
	XCTAssertEqualObjects([[task.variables objectForKey:@"limits"] objectForKey:@"high"], @100);
	(void)error;
}

- (void)testAnInterruptedActivityMapsNoOutputs
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self mapped:^(WFDefinitionBuilder *b) {
		[b addOutputParameter:@"result" value:@"done" forElement:@"work"];
		[b addBoundaryTimer:@"late" onTask:@"work" duration:3600 interrupting:YES];
		[b connect:@"late" to:@"after"];
	}] engine:engine variables:nil];
	WFJob *timer = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertTrue([engine.managementService executeJob:timer.jobId error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	XCTAssertNil([[engine.runtimeService variablesForProcessInstance:pid error:NULL] objectForKey:@"result"]);
}

- (void)testSubprocessAndMultiInstanceParameters
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *inner = [WFDefinitionBuilder process:@"sub"];
	[[[inner addStart:@"s"] addServiceTask:@"step" action:@"step"] addEnd:@"e"];
	[[inner connect:@"s" to:@"step"] connect:@"step" to:@"e"];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"outer"];
	[[[b addStart:@"start"] addSubProcess:@"sub" name:@"Sub" inner:[inner build:&error]] addEnd:@"end"];
	[[b connect:@"start" to:@"sub"] connect:@"sub" to:@"end"];
	[b addInputParameter:@"label" value:@"=\"item \" + string(loopCounter)" forElement:@"sub"];
	[b setMultiInstanceSequential:NO loopCardinality:@"2" collection:nil elementVariable:nil
	          completionCondition:nil forElement:@"sub"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	NSArray *steps = [engine.externalTaskService fetchAndLock:10 workerId:@"w" topics:@{ @"step": @60 }
	                                                    error:&error];
	NSArray *labels = [[steps valueForKeyPath:@"variables.label"] sortedArrayUsingSelector:@selector(compare:)];
	XCTAssertEqualObjects(labels, (@[ @"item 0", @"item 1" ]), @"%@", [steps valueForKey:@"variables"]);
	for (WFExternalTask *step in steps) {
		XCTAssertTrue([engine.externalTaskService complete:step.externalTaskId workerId:@"w" variables:nil
		                                            error:&error], @"%@", error);
	}
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testReadsAndWritesCamundaInputOutput
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\"><bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:userTask id=\"t\"><bpmn:extensionElements><camunda:inputOutput>"
		 @"<camunda:inputParameter name=\"who\">ann</camunda:inputParameter>"
		 @"<camunda:inputParameter name=\"sum\">${a + b}</camunda:inputParameter>"
		 @"<camunda:inputParameter name=\"list\"><camunda:list><camunda:value>x</camunda:value>"
		 @"<camunda:value>${y}</camunda:value></camunda:list></camunda:inputParameter>"
		 @"<camunda:inputParameter name=\"map\"><camunda:map><camunda:entry key=\"k\">v</camunda:entry>"
		 @"</camunda:map></camunda:inputParameter>"
		 @"<camunda:outputParameter name=\"out\">${sum}</camunda:outputParameter>"
		 @"</camunda:inputOutput></bpmn:extensionElements></bpmn:userTask>"
		 @"<bpmn:endEvent id=\"e\"/><bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"t\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"t\" targetRef=\"e\"/></bpmn:process></bpmn:definitions>";
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	NSArray *inputs = [[definition nodeWithId:@"t"] inputParameters];
	XCTAssertEqualObjects([inputs valueForKey:@"name"], (@[ @"who", @"sum", @"list", @"map" ]));
	XCTAssertEqualObjects([((WFParameter *)[inputs objectAtIndex:2]).expression expressionString], @"[\"x\", y]");
	XCTAssertEqualObjects([((WFParameter *)[inputs objectAtIndex:3]).expression expressionString], @"{k: \"v\"}");

	NSString *written = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
	WFProcessDefinition *again = [WFBpmnReader definitionFromXMLString:written error:&error];
	XCTAssertNotNil(again, @"%@\n%@", error, written);
	NSArray *reread = [[again nodeWithId:@"t"] inputParameters];
	for (NSUInteger i = 0; i < [inputs count]; i++) {
		XCTAssertEqualObjects([((WFParameter *)[reread objectAtIndex:i]).expression expressionString],
			[((WFParameter *)[inputs objectAtIndex:i]).expression expressionString], @"%@", written);
	}
	XCTAssertEqualObjects([[[[again nodeWithId:@"t"] outputParameters] lastObject] name], @"out");

	NSString *script = [xml stringByReplacingOccurrencesOfString:@"<camunda:inputParameter name=\"who\">ann</camunda:inputParameter>"
		withString:@"<camunda:inputParameter name=\"who\"><camunda:script scriptFormat=\"js\">1</camunda:script></camunda:inputParameter>"];
	XCTAssertNil([WFBpmnReader definitionFromXMLString:script error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"script"].location != NSNotFound, @"%@", error);
}

@end

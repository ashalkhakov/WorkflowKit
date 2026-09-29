#import "UDWorkflowTestCase.h"

@interface UDBpmnTests : UDWorkflowTestCase
@end

@implementation UDBpmnTests

/* Every construct the engine runs, subprocess included. */
- (UDProcessDefinition *)everyConstruct
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"manual" name:@"Manual review"];
	[[[[[inner addStart:@"ms"] addInclusive:@"or1" defaultFlow:@"f_or_b"]
		addUserTask:@"review" name:@"Review" assignee:@"clerk"]
		addUserTask:@"review2" name:@"Second look" assignee:nil]
		addInclusive:@"or2" defaultFlow:nil];
	[[inner addEnd:@"me"] addEnd:@"reminded"];
	[inner addBoundaryTimer:@"remind" onTask:@"review" duration:90 interrupting:NO];
	[inner connect:@"ms" to:@"or1"];
	[inner connect:@"or1" to:@"review" flowId:@"f_or_a"
	     condition:[UDFeelExpression expressionWithString:@"urgent = true" error:NULL]];
	[inner connect:@"or1" to:@"review2" flowId:@"f_or_b"];
	[[[inner connect:@"review" to:@"or2"] connect:@"review2" to:@"or2"] connect:@"or2" to:@"me"];
	[inner connect:@"remind" to:@"reminded"];
	[inner setBoundsFor:@"review" x:40 y:30 width:100 height:80];
	UDProcessDefinition *manual = [inner build:&error];
	XCTAssertNotNil(manual, @"%@", error);

	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"everything" name:@"Everything"];
	[[[[b addStart:@"start"] addUserTask:@"fill" name:@"Fill in" assignee:@"requester"]
		addParallel:@"split"] addServiceTask:@"check" action:@"credit.check"];
	[[[b addScriptTask:@"audit" action:@"audit.log"] addParallel:@"join"]
		addExclusive:@"choice" defaultFlow:@"toManual"];
	[[[b addIntermediateThrow:@"milestone"] addSubProcess:@"manual" name:@"Manual review" inner:manual]
		addEventBased:@"race"];
	[[[b addMessageCatch:@"paid" message:@"Payment received"] addMessageThrow:@"notify" message:@"shipped"]
		addMessageEnd:@"done" message:@"closed"];
	[[[b addTimerCatch:@"timeout" duration:7 * 86400] addEnd:@"late"] addEnd:@"badCredit"];
	[[b addEnd:@"anyError"] addEnd:@"cancelled"];
	[b addBoundaryError:@"onBad" onTask:@"check" errorRef:@"BAD_CREDIT" interrupting:YES];
	[b addBoundaryError:@"onAny" onTask:@"audit" errorRef:nil interrupting:YES];
	[b addBoundaryMessage:@"onCancel" onTask:@"fill" message:@"cancel" interrupting:YES];
	[[b addSignalCatch:@"recalled" signal:@"recall"] addTerminateEnd:@"aborted"];
	[b addBoundarySignal:@"onStop" onTask:@"manual" signal:@"stop" interrupting:NO];
	[[b addSignalThrow:@"announce" signal:@"stopped"] addSignalEnd:@"announced" signal:@"over"];
	[[b connect:@"start" to:@"fill"] connect:@"fill" to:@"split"];
	[[b connect:@"split" to:@"check"] connect:@"split" to:@"audit"];
	[[b connect:@"check" to:@"join"] connect:@"audit" to:@"join"];
	[b connect:@"join" to:@"choice"];
	[b connect:@"choice" to:@"milestone" when:@"amount <= 1000"];
	[b connect:@"choice" to:@"manual" flowId:@"toManual"];
	[[b connect:@"milestone" to:@"race"] connect:@"manual" to:@"race"];
	[[b connect:@"race" to:@"paid"] connect:@"race" to:@"timeout"];
	[[b connect:@"paid" to:@"notify"] connect:@"notify" to:@"done"];
	[b addCallActivity:@"escalate" calledElement:@"escalation"];
	[b setBinding:UDCalledElementBindingVersion version:2 forElement:@"escalate"];
	[[[b addInput:[UDVariableMapping businessKey] forElement:@"escalate"]
		addInput:[UDVariableMapping allVariables] forElement:@"escalate"]
		addInput:[UDVariableMapping mappingFrom:@"amount" to:@"sum"] forElement:@"escalate"];
	[b addOutput:[UDVariableMapping mappingFrom:@"verdict" to:@"escalation"] forElement:@"escalate"];
	[b addBoundaryTimer:@"stale" onTask:@"escalate" duration:3600 interrupting:YES];
	[[b connect:@"timeout" to:@"escalate"] connect:@"escalate" to:@"late"];
	[b connect:@"stale" to:@"late"];
	[[b connect:@"race" to:@"recalled"] connect:@"recalled" to:@"aborted"];
	[[b connect:@"onStop" to:@"announce"] connect:@"announce" to:@"announced"];
	[[[b connect:@"onBad" to:@"badCredit"] connect:@"onAny" to:@"anyError"]
		connect:@"onCancel" to:@"cancelled"];
	[b setName:@"Request received" forElement:@"start"];
	[b setName:@"needs review" forElement:@"toManual"];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"check"];
	[b setAsyncBefore:NO asyncAfter:YES exclusive:NO forElement:@"audit"];
	[b setRetryTimeCycle:@"R5/PT5M" forElement:@"check"];
	[b setRetryTimeCycle:@"PT1M,PT10M" forElement:@"timeout"];
	[b setTaskPriority:7 forElement:@"check"];
	[b setDefaultTaskPriority:3];
	[b setHistoryTimeToLive:90];
	[b setAsyncBefore:NO asyncAfter:YES exclusive:YES forElement:@"join"];
	[b setBoundsFor:@"start" x:10 y:20 width:36 height:36];
	[b setBoundsFor:@"fill" x:100 y:8 width:100 height:80];
	[b setBoundsFor:@"manual" x:300 y:200 width:350.5 height:200];
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testBpmnRoundTripsEveryConstruct
{
	NSError *error = nil;
	UDProcessDefinition *definition = [self everyConstruct];
	NSString *xml = [UDBpmnWriter XMLStringFromDefinition:definition error:&error];
	XCTAssertNotNil(xml, @"%@", error);
	XCTAssertTrue([xml rangeOfString:@"<bpmn:timeDuration xsi:type=\"bpmn:tFormalExpression\">P7D</bpmn:timeDuration>"].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"PT1M30S"].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"camunda:topic=\"credit.check\""].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"<camunda:failedJobRetryTimeCycle>R5/PT5M</camunda:failedJobRetryTimeCycle>"].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"<bpmndi:BPMNShape"].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"calledElement=\"escalation\" camunda:calledElementBinding=\"version\" camunda:calledElementVersion=\"2\""].location != NSNotFound, @"%@", xml);
	XCTAssertTrue([xml rangeOfString:@"<camunda:in businessKey=\"#{execution.processBusinessKey}\"/>"].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"<camunda:out source=\"verdict\" target=\"escalation\"/>"].location != NSNotFound);
	UDProcessDefinition *again = [UDBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(again, @"%@\n%@", error, xml);
	[self assertDefinition:definition matches:again];
	/* Writing what was read gives the same document. */
	XCTAssertEqualObjects([UDBpmnWriter XMLStringFromDefinition:again error:&error], xml);
}

static NSString * const UDModelerInvoice =
	@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	 @"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
	 @"xmlns:bpmndi=\"http://www.omg.org/spec/BPMN/20100524/DI\" "
	 @"xmlns:dc=\"http://www.omg.org/spec/DD/20100524/DC\" "
	 @"xmlns:di=\"http://www.omg.org/spec/DD/20100524/DI\" "
	 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" "
	 @"xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
	 @"xmlns:modeler=\"http://camunda.org/schema/modeler/1.0\" id=\"Definitions_1\" "
	 @"targetNamespace=\"http://bpmn.io/schema/bpmn\" exporter=\"Camunda Modeler\" "
	 @"exporterVersion=\"5.20.0\" modeler:executionPlatform=\"Camunda Platform\" "
	 @"modeler:executionPlatformVersion=\"7.20.0\">\n"
	 @"  <bpmn:process id=\"invoice\" name=\"Invoice\" isExecutable=\"true\" camunda:historyTimeToLive=\"180\">\n"
	 @"    <bpmn:documentation>Pays invoices.</bpmn:documentation>\n"
	 @"    <bpmn:startEvent id=\"StartEvent_1\" name=\"Invoice received\">\n"
	 @"      <bpmn:outgoing>Flow_1</bpmn:outgoing>\n"
	 @"    </bpmn:startEvent>\n"
	 @"    <bpmn:exclusiveGateway id=\"Gateway_amount\" name=\"Amount?\" default=\"Flow_small\">\n"
	 @"      <bpmn:incoming>Flow_1</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_big</bpmn:outgoing>\n"
	 @"      <bpmn:outgoing>Flow_small</bpmn:outgoing>\n"
	 @"    </bpmn:exclusiveGateway>\n"
	 @"    <bpmn:userTask id=\"Task_approve\" name=\"Approve invoice\" camunda:assignee=\"demo\" camunda:candidateGroups=\"accounting\">\n"
	 @"      <bpmn:extensionElements>\n"
	 @"        <camunda:properties><camunda:property name=\"sla\" value=\"2d\" /></camunda:properties>\n"
	 @"      </bpmn:extensionElements>\n"
	 @"      <bpmn:incoming>Flow_big</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_approved</bpmn:outgoing>\n"
	 @"    </bpmn:userTask>\n"
	 @"    <bpmn:boundaryEvent id=\"Event_reminder\" name=\"5 minutes\" cancelActivity=\"false\" attachedToRef=\"Task_approve\">\n"
	 @"      <bpmn:outgoing>Flow_remind</bpmn:outgoing>\n"
	 @"      <bpmn:timerEventDefinition id=\"TimerEventDefinition_1\">\n"
	 @"        <bpmn:timeDuration xsi:type=\"bpmn:tFormalExpression\">PT5M</bpmn:timeDuration>\n"
	 @"      </bpmn:timerEventDefinition>\n"
	 @"    </bpmn:boundaryEvent>\n"
	 @"    <bpmn:serviceTask id=\"Task_remind\" name=\"Remind\" camunda:type=\"external\" camunda:topic=\"reminder\">\n"
	 @"      <bpmn:incoming>Flow_remind</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_reminded</bpmn:outgoing>\n"
	 @"    </bpmn:serviceTask>\n"
	 @"    <bpmn:endEvent id=\"Event_reminded\">\n"
	 @"      <bpmn:incoming>Flow_reminded</bpmn:incoming>\n"
	 @"    </bpmn:endEvent>\n"
	 @"    <bpmn:serviceTask id=\"Task_pay\" name=\"Pay\" camunda:asyncBefore=\"true\" camunda:type=\"external\" camunda:topic=\"payments.pay\">\n"
	 @"      <bpmn:incoming>Flow_small</bpmn:incoming>\n"
	 @"      <bpmn:incoming>Flow_approved</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_paid</bpmn:outgoing>\n"
	 @"    </bpmn:serviceTask>\n"
	 @"    <bpmn:intermediateCatchEvent id=\"Event_confirmed\" name=\"Bank confirmed\">\n"
	 @"      <bpmn:incoming>Flow_paid</bpmn:incoming>\n"
	 @"      <bpmn:outgoing>Flow_done</bpmn:outgoing>\n"
	 @"      <bpmn:messageEventDefinition id=\"MessageEventDefinition_1\" messageRef=\"Message_confirm\" />\n"
	 @"    </bpmn:intermediateCatchEvent>\n"
	 @"    <bpmn:endEvent id=\"Event_paid\" name=\"Invoice paid\">\n"
	 @"      <bpmn:incoming>Flow_done</bpmn:incoming>\n"
	 @"    </bpmn:endEvent>\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_1\" sourceRef=\"StartEvent_1\" targetRef=\"Gateway_amount\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_big\" name=\"over 1000\" sourceRef=\"Gateway_amount\" targetRef=\"Task_approve\">\n"
	 @"      <bpmn:conditionExpression xsi:type=\"bpmn:tFormalExpression\">${amount &gt; 1000}</bpmn:conditionExpression>\n"
	 @"    </bpmn:sequenceFlow>\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_small\" sourceRef=\"Gateway_amount\" targetRef=\"Task_pay\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_approved\" sourceRef=\"Task_approve\" targetRef=\"Task_pay\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_remind\" sourceRef=\"Event_reminder\" targetRef=\"Task_remind\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_reminded\" sourceRef=\"Task_remind\" targetRef=\"Event_reminded\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_paid\" sourceRef=\"Task_pay\" targetRef=\"Event_confirmed\" />\n"
	 @"    <bpmn:sequenceFlow id=\"Flow_done\" sourceRef=\"Event_confirmed\" targetRef=\"Event_paid\" />\n"
	 @"  </bpmn:process>\n"
	 @"  <bpmn:message id=\"Message_confirm\" name=\"PaymentConfirmed\" />\n"
	 @"  <bpmndi:BPMNDiagram id=\"BPMNDiagram_1\">\n"
	 @"    <bpmndi:BPMNPlane id=\"BPMNPlane_1\" bpmnElement=\"invoice\">\n"
	 @"      <bpmndi:BPMNShape id=\"_BPMNShape_StartEvent_2\" bpmnElement=\"StartEvent_1\">\n"
	 @"        <dc:Bounds x=\"179\" y=\"99\" width=\"36\" height=\"36\" />\n"
	 @"        <bpmndi:BPMNLabel><dc:Bounds x=\"155\" y=\"142\" width=\"84\" height=\"14\" /></bpmndi:BPMNLabel>\n"
	 @"      </bpmndi:BPMNShape>\n"
	 @"      <bpmndi:BPMNShape id=\"Activity_approve_di\" bpmnElement=\"Task_approve\">\n"
	 @"        <dc:Bounds x=\"370\" y=\"77\" width=\"100\" height=\"80\" />\n"
	 @"      </bpmndi:BPMNShape>\n"
	 @"      <bpmndi:BPMNEdge id=\"Flow_1_di\" bpmnElement=\"Flow_1\">\n"
	 @"        <di:waypoint x=\"215\" y=\"117\" />\n"
	 @"        <di:waypoint x=\"265\" y=\"117\" />\n"
	 @"      </bpmndi:BPMNEdge>\n"
	 @"    </bpmndi:BPMNPlane>\n"
	 @"  </bpmndi:BPMNDiagram>\n"
	 @"</bpmn:definitions>\n";

- (void)testRunsACamundaModelerFile
{
	NSError *error = nil;
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"paid": @YES } forKey:@"payments.pay"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	UDDeployment *deployment = [engine.repositoryService
		deployResources:@{ @"invoice.bpmn": [UDModelerInvoice dataUsingEncoding:NSUTF8StringEncoding] }
		           name:@"invoice"
		filterDuplicates:YES
		          error:&error];
	XCTAssertNotNil(deployment, @"%@", error);
	UDProcessDefinition *definition = [deployment.definitions lastObject];
	XCTAssertEqualObjects(definition.name, @"Invoice");
	XCTAssertEqualObjects(definition.historyTimeToLive, @180);
	XCTAssertEqualObjects([[definition nodeWithId:@"StartEvent_1"] name], @"Invoice received");
	XCTAssertEqualWithAccuracy([[definition nodeWithId:@"Task_approve"] boundsX], 370.0, 0.001);
	XCTAssertEqualObjects([(UDTask *)[definition nodeWithId:@"Task_approve"] assignee], @"demo");
	XCTAssertEqualObjects([[definition flowWithId:@"Flow_big"].condition expressionString],
		@"amount > 1000");
	XCTAssertEqualObjects([(UDEvent *)[definition nodeWithId:@"Event_confirmed"] messageName],
		@"PaymentConfirmed");
	XCTAssertEqualWithAccuracy([(UDEvent *)[definition nodeWithId:@"Event_reminder"] timerDuration],
		300.0, 0.001);

	UDProcessInstance *big = [engine.runtimeService startProcessInstanceByKey:@"invoice"
	                                                               businessKey:@"INV-7"
	                                                                 variables:@{ @"amount": @5000 }
	                                                                     error:&error];
	NSString *pid = big.processInstanceId;
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"Task_approve" ]);
	XCTAssertEqualObjects([[engine.taskService tasksForAssignee:@"demo"] valueForKey:@"taskDefinitionKey"],
		@[ @"Task_approve" ]);
	[self complete:@"Task_approve" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"Event_confirmed" ]);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"PaymentConfirmed" businessKey:@"INV-7"
	                                      correlationKeys:nil variables:nil error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"paid"], @YES);

	NSString *small = [engine.runtimeService startProcessInstanceByKey:@"invoice"
	                                                          variables:@{ @"amount": @200 }
	                                                              error:&error].processInstanceId;
	XCTAssertTrue([engine waitUntilSettled:small timeout:10.0]);
	XCTAssertEqualObjects([self active:small engine:engine], @[ @"Event_confirmed" ],
		@"under 1000 skips approval");
}

@end

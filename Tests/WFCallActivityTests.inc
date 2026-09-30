/* Included into a class of each backend's suite: see WFTestCase.h. */

/* A process that waits in a user task and then ends. */
- (WFProcessDefinition *)waitingProcess:(NSString *)key task:(NSString *)taskId
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:key];
	[[[b addStart:@"s"] addUserTask:taskId name:taskId assignee:@"ann"] addEnd:@"e"];
	[[b connect:@"s" to:taskId] connect:taskId to:@"e"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

/* start -> call (with what configure adds) -> after (a user task) -> end */
- (WFProcessDefinition *)caller:(NSString *)calledKey
                      configure:(void (^)(WFDefinitionBuilder *b))configure
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"caller"];
	[[[[b addStart:@"start"] addCallActivity:@"call" calledElement:calledKey]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"call"] connect:@"call" to:@"after"] connect:@"after" to:@"end"];
	if (configure != nil) {
		configure(b);
	}
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (WFProcessInstance *)onlyCalled:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	NSArray *called = [engine.runtimeService subProcessInstancesOf:processInstanceId error:&error];
	XCTAssertNotNil(called, @"%@", error);
	XCTAssertEqual([called count], (NSUInteger)1);
	return [called firstObject];
}

- (WFHistoricActivityInstance *)history:(NSString *)activityId
                                     of:(NSString *)processInstanceId
                                 engine:(WFProcessEngine *)engine
{
	for (WFHistoricActivityInstance *activity in
	     [engine.historyService historicActivityInstancesForProcessInstance:processInstanceId]) {
		if ([activity.activityId isEqualToString:activityId]) {
			return activity;
		}
	}
	return nil;
}

- (void)testCallActivityPassesVariablesInAndOut
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self waitingProcess:@"review" task:@"check"] engine:engine];
	[self deploy:[self caller:@"review" configure:^(WFDefinitionBuilder *b) {
		[[b addInput:[WFVariableMapping mappingFrom:@"amount" to:@"sum"] forElement:@"call"]
			addInput:[WFVariableMapping businessKey] forElement:@"call"];
		[b addOutput:[WFVariableMapping mappingFrom:@"verdict" to:@"result"] forElement:@"call"];
	}] engine:engine];
	WFProcessInstance *parent =
		[engine.runtimeService startProcessInstanceByKey:@"caller" businessKey:@"order-7"
		                                       variables:@{ @"amount": @10, @"secret": @1 }
		                                           error:&error];
	XCTAssertNotNil(parent, @"%@", error);
	NSString *pid = parent.processInstanceId;
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"call" ]);

	WFProcessInstance *child = [self onlyCalled:pid engine:engine];
	XCTAssertEqualObjects(child.definitionKey, @"review");
	XCTAssertEqualObjects(child.businessKey, @"order-7");
	XCTAssertEqualObjects(child.superProcessInstanceId, pid);
	XCTAssertEqualObjects([engine.runtimeService variablesForProcessInstance:child.processInstanceId
	                                                                   error:NULL],
		(@{ @"sum": @10 }));
	XCTAssertEqualObjects([self history:@"call" of:pid engine:engine].activityType, @"callActivity");
	XCTAssertEqualObjects([self history:@"call" of:pid engine:engine].calledProcessInstanceId,
		child.processInstanceId);

	[self complete:@"check" of:child.processInstanceId engine:engine
	     variables:@{ @"verdict": @"ok", @"note": @"fine" }];
	XCTAssertTrue([self ended:child.processInstanceId engine:engine]);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	NSDictionary *variables = [engine.runtimeService variablesForProcessInstance:pid error:NULL];
	XCTAssertEqualObjects([variables objectForKey:@"result"], @"ok");
	XCTAssertNil([variables objectForKey:@"note"]);
	XCTAssertNotNil([self history:@"call" of:pid engine:engine].endTime);
	WFHistoricProcessInstance *childHistory =
		[engine.historyService historicProcessInstanceWithId:child.processInstanceId];
	XCTAssertEqualObjects(childHistory.superProcessInstanceId, pid);
	XCTAssertEqualObjects(childHistory.state, WFProcessInstanceStateCompleted);
}

- (void)testAllVariablesGoInAndComeBack
{
	NSError *error = nil;
	WFDefinitionBuilder *c = [WFDefinitionBuilder process:@"compute"];
	[[[c addStart:@"s"] addServiceTask:@"sum" action:@"sum"] addEnd:@"e"];
	[[c connect:@"s" to:@"sum"] connect:@"sum" to:@"e"];
	WFMapHandler *h = [[WFMapHandler alloc] init];
	[h.results setObject:@{ @"total": @42 } forKey:@"sum"];
	WFProcessEngine *engine = [self engineWithHandler:h];
	[self deploy:[c build:&error] engine:engine];
	NSString *pid = [self run:[self caller:@"compute" configure:^(WFDefinitionBuilder *b) {
		[b addInput:[WFVariableMapping allVariables] forElement:@"call"];
		[b addOutput:[WFVariableMapping allVariables] forElement:@"call"];
	}] engine:engine variables:@{ @"x": @1 }];
	XCTAssertTrue([self waitForActive:@"after" in:pid engine:engine]);
	NSDictionary *variables = [engine.runtimeService variablesForProcessInstance:pid error:NULL];
	XCTAssertEqualObjects(variables, (@{ @"x": @1, @"total": @42 }));
}

- (void)testCalledProcessThatEndsAtOnceReturnsInTheSameCommand
{
	NSError *error = nil;
	WFDefinitionBuilder *c = [WFDefinitionBuilder process:@"noop"];
	[[c addStart:@"s"] addEnd:@"e"];
	[c connect:@"s" to:@"e"];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[c build:&error] engine:engine];
	NSString *pid = [self run:[self caller:@"noop" configure:^(WFDefinitionBuilder *b) {
		[b addOutput:[WFVariableMapping mappingFrom:@"missing" to:@"got"] forElement:@"call"];
	}] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	/* A source that is not there comes back as null. */
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:pid error:NULL]
		objectForKey:@"got"], [NSNull null]);
	XCTAssertEqual([[engine.runtimeService subProcessInstancesOf:pid error:NULL] count], (NSUInteger)0);
}

- (void)testErrorInTheCalledProcessIsCaughtOnTheCallActivity
{
	NSError *error = nil;
	WFDefinitionBuilder *c = [WFDefinitionBuilder process:@"risky"];
	[[[c addStart:@"s"] addServiceTask:@"try" action:@"try"] addEnd:@"e"];
	[[c connect:@"s" to:@"try"] connect:@"try" to:@"e"];
	WFMapHandler *h = [[WFMapHandler alloc] init];
	[h.bpmnErrors setObject:@"BOOM" forKey:@"try"];
	WFProcessEngine *engine = [self engineWithHandler:h];
	[self deploy:[c build:&error] engine:engine];
	NSString *pid = [self run:[self caller:@"risky" configure:^(WFDefinitionBuilder *b) {
		[b addInput:[WFVariableMapping mappingFrom:@"attempt" to:@"attempt"] forElement:@"call"];
		[b addOutput:[WFVariableMapping mappingFrom:@"attempt" to:@"lastAttempt"] forElement:@"call"];
		[[b addUserTask:@"handle" name:@"Handle" assignee:@"ann"] addEnd:@"handled"];
		[b addBoundaryError:@"failed" onTask:@"call" errorRef:@"BOOM" interrupting:YES];
		[[b connect:@"failed" to:@"handle"] connect:@"handle" to:@"handled"];
	}] engine:engine variables:@{ @"attempt": @3 }];
	XCTAssertTrue([self waitForActive:@"handle" in:pid engine:engine]);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"handle" ]);
	/* The outputs are passed back on the way out. */
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:pid error:NULL]
		objectForKey:@"lastAttempt"], @3);
	XCTAssertTrue([self history:@"call" of:pid engine:engine].canceled);
	NSString *childId = [self history:@"call" of:pid engine:engine].calledProcessInstanceId;
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:childId] state],
		WFProcessInstanceStateInternallyTerminated);
	XCTAssertTrue([self history:@"try" of:childId engine:engine].canceled);
	for (NSDictionary *row in [self rows:@"WFExecution" engine:engine]) {
		XCTAssertEqualObjects([row objectForKey:@"processInstanceId"], pid);
	}
	XCTAssertEqual([[self rows:@"WFExternalTask" engine:engine] count], (NSUInteger)0);
}

- (void)testTimerOnTheCallActivityCancelsTheCalledInstance
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	[self deploy:[self waitingProcess:@"review" task:@"check"] engine:engine];
	NSString *pid = [self run:[self caller:@"review" configure:^(WFDefinitionBuilder *b) {
		[b addBoundaryTimer:@"late" onTask:@"call" duration:3600 interrupting:YES];
		[b connect:@"late" to:@"after"];
	}] engine:engine variables:nil];
	NSString *childId = [self onlyCalled:pid engine:engine].processInstanceId;
	XCTAssertNotNil([self task:@"check" of:childId engine:engine]);

	WFJob *timer = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(timer.activityId, @"late");
	XCTAssertTrue([engine.managementService executeJob:timer.jobId error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	XCTAssertNil([engine.runtimeService processInstanceWithId:childId error:NULL]);
	XCTAssertEqual([[self rows:@"WFTask" engine:engine] count], (NSUInteger)1);
	XCTAssertEqualObjects([[[engine.historyService historicTaskInstancesForProcessInstance:childId]
		lastObject] deleteReason], WFTaskDeleteReasonDeleted);
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:childId] state],
		WFProcessInstanceStateInternallyTerminated);
}

- (void)testTerminateInTheCallerCancelsTheCalledInstance
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self waitingProcess:@"review" task:@"check"] engine:engine];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"racer"];
	[[[[b addStart:@"start"] addParallel:@"fork"] addCallActivity:@"call" calledElement:@"review"]
		addUserTask:@"decide" name:@"Decide" assignee:@"boss"];
	[[b addEnd:@"done"] addTerminateEnd:@"stop"];
	[[b connect:@"start" to:@"fork"] connect:@"fork" to:@"call"];
	[[b connect:@"fork" to:@"decide"] connect:@"call" to:@"done"];
	[b connect:@"decide" to:@"stop"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	NSString *childId = [self onlyCalled:pid engine:engine].processInstanceId;
	[self complete:@"decide" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)0);
	XCTAssertEqual([[self rows:@"WFTask" engine:engine] count], (NSUInteger)0);
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:childId] state],
		WFProcessInstanceStateInternallyTerminated);
}

- (void)testCallsFromParallelPathsReturnToTheirOwnPaths
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self waitingProcess:@"review" task:@"check"] engine:engine];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"both"];
	[[[[b addStart:@"start"] addParallel:@"fork"] addCallActivity:@"left" calledElement:@"review"]
		addCallActivity:@"right" calledElement:@"review"];
	[[[b addParallel:@"join"] addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"start" to:@"fork"] connect:@"fork" to:@"left"];
	[[b connect:@"fork" to:@"right"] connect:@"left" to:@"join"];
	[[b connect:@"right" to:@"join"] connect:@"join" to:@"after"];
	[b connect:@"after" to:@"end"];
	[b addInput:[WFVariableMapping mappingFrom:@"leftSide" to:@"side"] forElement:@"left"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"leftSide": @"L" }];
	NSArray *called = [engine.runtimeService subProcessInstancesOf:pid error:NULL];
	XCTAssertEqual([called count], (NSUInteger)2);
	NSString *leftId = [self history:@"left" of:pid engine:engine].calledProcessInstanceId;
	NSString *rightId = [self history:@"right" of:pid engine:engine].calledProcessInstanceId;
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:leftId error:NULL]
		objectForKey:@"side"], @"L");
	[self complete:@"check" of:rightId engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"left" ]);
	[self complete:@"check" of:leftId engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
}

- (void)testCallingAProcessThatIsNotDeployedFails
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self caller:@"nowhere" configure:nil] engine:engine];
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"caller" variables:nil error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"nowhere"].location != NSNotFound,
		@"%@", error);
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)0);
}

static NSString *
WFCallerDocument(NSString *callActivities)
{
	return [NSString stringWithFormat:
		@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		 @"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\" "
		 @"targetNamespace=\"http://bpmn.io/schema/bpmn\">\n"
		 @"  <bpmn:process id=\"child\" isExecutable=\"true\">\n"
		 @"    <bpmn:startEvent id=\"cs\"/>\n"
		 @"    <bpmn:userTask id=\"v1\"/>\n"
		 @"    <bpmn:endEvent id=\"ce\"/>\n"
		 @"    <bpmn:sequenceFlow id=\"c1\" sourceRef=\"cs\" targetRef=\"v1\"/>\n"
		 @"    <bpmn:sequenceFlow id=\"c2\" sourceRef=\"v1\" targetRef=\"ce\"/>\n"
		 @"  </bpmn:process>\n"
		 @"  <bpmn:process id=\"parent\" isExecutable=\"true\">\n"
		 @"    <bpmn:startEvent id=\"s\"/>\n"
		 @"    <bpmn:parallelGateway id=\"fork\"/>\n"
		 @"%@"
		 @"    <bpmn:sequenceFlow id=\"f0\" sourceRef=\"s\" targetRef=\"fork\"/>\n"
		 @"  </bpmn:process>\n"
		 @"</bpmn:definitions>\n", callActivities];
}

static NSString *
WFCallActivityXML(NSString *elementId, NSString *attributes, NSString *extensions)
{
	return [NSString stringWithFormat:
		@"    <bpmn:callActivity id=\"%@\" calledElement=\"child\"%@>\n"
		 @"      <bpmn:extensionElements>%@</bpmn:extensionElements>\n"
		 @"    </bpmn:callActivity>\n"
		 @"    <bpmn:endEvent id=\"%@_end\"/>\n"
		 @"    <bpmn:sequenceFlow id=\"%@_in\" sourceRef=\"fork\" targetRef=\"%@\"/>\n"
		 @"    <bpmn:sequenceFlow id=\"%@_out\" sourceRef=\"%@\" targetRef=\"%@_end\"/>\n",
		elementId, attributes, extensions ?: @"", elementId, elementId, elementId,
		elementId, elementId, elementId];
}

- (void)testBindingsPickTheCalledVersion
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *calls = [@[
		WFCallActivityXML(@"latest", @"", nil),
		WFCallActivityXML(@"sameDeployment", @" camunda:calledElementBinding=\"deployment\"",
			@"<camunda:in variables=\"all\"/>"),
		WFCallActivityXML(@"first", @" camunda:calledElementBinding=\"version\" camunda:calledElementVersion=\"1\"",
			@"<camunda:in businessKey=\"${execution.processBusinessKey}\"/>")
	] componentsJoinedByString:@""];
	NSData *document = [WFCallerDocument(calls) dataUsingEncoding:NSUTF8StringEncoding];
	XCTAssertNotNil([engine.repositoryService deployResources:@{ @"calls.bpmn": document }
	                                                     name:@"calls"
	                                         filterDuplicates:NO
	                                                    error:&error], @"%@", error);
	/* A second version of the child, deployed on its own. */
	[self deploy:[self waitingProcess:@"child" task:@"v2"] engine:engine];

	WFProcessInstance *parent = [engine.runtimeService startProcessInstanceByKey:@"parent"
		businessKey:@"bk" variables:@{ @"x": @1 } error:&error];
	XCTAssertNotNil(parent, @"%@", error);
	NSString *pid = parent.processInstanceId;
	NSMutableDictionary *versions = [NSMutableDictionary dictionary];
	for (NSString *activityId in @[ @"latest", @"sameDeployment", @"first" ]) {
		NSString *childId = [self history:activityId of:pid engine:engine].calledProcessInstanceId;
		WFProcessInstance *child = [engine.runtimeService processInstanceWithId:childId error:NULL];
		WFProcessDefinition *definition =
			[engine.repositoryService definitionWithId:child.definitionId error:NULL];
		[versions setObject:[NSNumber numberWithInteger:definition.version] forKey:activityId];
		if ([activityId isEqualToString:@"sameDeployment"]) {
			XCTAssertEqualObjects([engine.runtimeService variablesForProcessInstance:childId error:NULL],
				(@{ @"x": @1 }));
		}
		XCTAssertEqualObjects(child.businessKey,
			[activityId isEqualToString:@"first"] ? @"bk" : nil, @"%@", activityId);
	}
	XCTAssertEqualObjects(versions, (@{ @"latest": @2, @"sameDeployment": @1, @"first": @1 }));
}

- (void)testCallActivityFeaturesTheEngineDoesNotRunAreRejected
{
	NSArray *cases = @[
		@[ @" calledElement=\"${key}\"", @"", @"expression" ],
		@[ @" camunda:calledElementBinding=\"versionTag\"", @"", @"versionTag" ],
		@[ @" camunda:calledElementBinding=\"version\"", @"", @"calledElementVersion" ],
		@[ @"", @"<camunda:in sourceExpression=\"${a}\" target=\"b\"/>", @"sourceExpression" ],
		@[ @"", @"<camunda:out local=\"true\" variables=\"all\"/>", @"local" ],
		@[ @"", @"<camunda:out businessKey=\"#{execution.processBusinessKey}\"/>", @"businessKey" ],
		@[ @"", @"<camunda:in source=\"a\"/>", @"target" ],
		@[ @" camunda:variableMappingClass=\"org.example.Mapping\"", @"", @"variableMappingClass" ],
	];
	for (NSArray *c in cases) {
		NSString *attributes = [c objectAtIndex:0];
		NSString *call = WFCallActivityXML(@"call", attributes, [c objectAtIndex:1]);
		if ([attributes hasPrefix:@" calledElement="]) {
			call = [call stringByReplacingOccurrencesOfString:@" calledElement=\"child\"" withString:@""];
		}
		NSError *error = nil;
		NSArray *definitions = [WFBpmnReader definitionsFromData:
				[WFCallerDocument(call) dataUsingEncoding:NSUTF8StringEncoding]
			error:&error];
		XCTAssertNil(definitions, @"%@ was accepted", c);
		XCTAssertTrue([[error localizedDescription] rangeOfString:[c objectAtIndex:2]].location
			!= NSNotFound, @"%@: %@", [c objectAtIndex:2], error);
	}
}

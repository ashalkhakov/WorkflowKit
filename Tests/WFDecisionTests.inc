/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Decisions

/* A decision "approval" on amount: up to the limit it is approved, above
 * it reviewed; the limit is 1000, or what the version says. */
static NSData *
WFApprovalDmn(NSString *limit, NSString *hitPolicy)
{
	NSString *xml = [NSString stringWithFormat:
		@"<definitions xmlns=\"https://www.omg.org/spec/DMN/20191111/MODEL/\" id=\"d\" name=\"D\" namespace=\"n\">"
		 @"<decision id=\"approval\" name=\"Approval\"><decisionTable id=\"t\" hitPolicy=\"%@\">"
		 @"<input id=\"i\" label=\"Amount\"><inputExpression id=\"ie\" typeRef=\"double\"><text>amount</text>"
		 @"</inputExpression></input>"
		 @"<output id=\"o1\" name=\"outcome\" typeRef=\"string\"/><output id=\"o2\" name=\"level\" typeRef=\"integer\"/>"
		 @"<rule id=\"r1\"><inputEntry id=\"a\"><text>&lt;= %@</text></inputEntry>"
		 @"<outputEntry id=\"b\"><text>\"approved\"</text></outputEntry><outputEntry id=\"c\"><text>1</text></outputEntry></rule>"
		 @"<rule id=\"r2\"><inputEntry id=\"d\"><text>&gt; %@</text></inputEntry>"
		 @"<outputEntry id=\"e\"><text>\"review\"</text></outputEntry><outputEntry id=\"f\"><text>2</text></outputEntry></rule>"
		 @"<rule id=\"r3\"><inputEntry id=\"g\"><text>&gt; 5000</text></inputEntry>"
		 @"<outputEntry id=\"h\"><text>\"refused\"</text></outputEntry><outputEntry id=\"k\"><text>3</text></outputEntry></rule>"
		 @"</decisionTable></decision></definitions>", hitPolicy, limit, limit];
	return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

/* start -> decide (the business rule task) -> end */
- (NSData *)decidingProcess:(void (^)(WFDefinitionBuilder *b))configure
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"deciding"];
	[[[b addStart:@"start"] addBusinessRuleTask:@"decide" decision:@"approval" resultVariable:@"result"
	                                     mapping:WFDecisionResultMappingSingleResult] addEnd:@"end"];
	[[b connect:@"start" to:@"decide"] connect:@"decide" to:@"end"];
	if (configure != nil) {
		configure(b);
	}
	NSString *xml = [WFBpmnWriter XMLStringFromDefinition:[b build:&error] error:&error];
	XCTAssertNotNil(xml, @"%@", error);
	return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

- (WFDeployment *)deploy:(NSDictionary *)resources engine:(WFProcessEngine *)engine name:(NSString *)name
{
	NSError *error = nil;
	WFDeployment *deployment = [engine.repositoryService deployResources:resources name:name
	                                                     filterDuplicates:NO error:&error];
	XCTAssertNotNil(deployment, @"%@", error);
	return deployment;
}

- (NSDictionary *)decide:(NSDictionary *)variables engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	WFProcessInstance *instance = [engine.runtimeService startProcessInstanceByKey:@"deciding"
	                                                                    variables:variables error:&error];
	XCTAssertNotNil(instance, @"%@", error);
	XCTAssertTrue(instance.ended);
	return [engine.historyService historicVariablesForProcessInstance:instance.processInstanceId];
}

- (void)testDeploysDecisionsBesideProcesses
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDeployment *first = [self deploy:@{ @"approval.dmn": WFApprovalDmn(@"1000", @"FIRST"),
	                                      @"deciding.bpmn": [self decidingProcess:nil] }
	                            engine:engine name:@"approvals"];
	XCTAssertEqual([first.definitions count], (NSUInteger)1);
	XCTAssertEqualObjects([first.decisions valueForKey:@"key"], @[ @"approval" ]);
	XCTAssertEqual([[first.decisions firstObject] version], (NSInteger)1);
	[self deploy:@{ @"approval.dmn": WFApprovalDmn(@"2000", @"FIRST") } engine:engine name:@"approvals"];
	NSError *error = nil;
	WFDecisionDefinition *latest = [engine.repositoryService latestDecisionForKey:@"approval" error:&error];
	XCTAssertEqual(latest.version, (NSInteger)2, @"%@", error);
	XCTAssertEqualObjects([[engine.repositoryService deploymentWithId:first.deploymentId error:&error]
		.decisions.firstObject definitionId], [first.decisions.firstObject definitionId]);
	XCTAssertNil([engine.repositoryService latestDecisionForKey:@"nothing" error:&error]);

	NSData *broken = [@"<definitions xmlns=\"https://www.omg.org/spec/DMN/20191111/MODEL/\"/>"
		dataUsingEncoding:NSUTF8StringEncoding];
	XCTAssertNil([engine.repositoryService deployResources:@{ @"broken.dmn": broken } name:@"broken"
	                                      filterDuplicates:NO error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorInvalidDmn);
}

- (void)testABusinessRuleTaskKeepsTheResultAsMapped
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:@{ @"approval.dmn": WFApprovalDmn(@"1000", @"RULE ORDER"),
	                @"deciding.bpmn": [self decidingProcess:nil] } engine:engine name:@"single"];
	NSDictionary *result = [[self decide:@{ @"amount": @500 } engine:engine] objectForKey:@"result"];
	XCTAssertEqualObjects(result, (@{ @"outcome": @"approved", @"level": @1 }));

	NSData *listing = [self decidingProcess:^(WFDefinitionBuilder *b) {
		[b addBusinessRuleTask:@"decide" decision:@"approval" resultVariable:@"result"
		               mapping:WFDecisionResultMappingResultList];
	}];
	[self deploy:@{ @"deciding.bpmn": listing } engine:engine name:@"list"];
	XCTAssertEqualObjects([[self decide:@{ @"amount": @6000 } engine:engine] objectForKey:@"result"],
		(@[ @{ @"outcome": @"review", @"level": @2 }, @{ @"outcome": @"refused", @"level": @3 } ]));

	/* Two outputs are not a single entry: the task fails, and nothing starts. */
	NSData *entry = [self decidingProcess:^(WFDefinitionBuilder *b) {
		[b addBusinessRuleTask:@"decide" decision:@"approval" resultVariable:@"result"
		               mapping:WFDecisionResultMappingSingleEntry];
	}];
	[self deploy:@{ @"deciding.bpmn": entry } engine:engine name:@"entry"];
	NSError *error = nil;
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"deciding"
	                                                    variables:@{ @"amount": @10 } error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorDecision, @"%@", error);
}

- (void)testADecisionThatCannotBeEvaluatedFailsTheCommand
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:@{ @"approval.dmn": WFApprovalDmn(@"1000", @"UNIQUE"),
	                @"deciding.bpmn": [self decidingProcess:nil] } engine:engine name:@"unique"];
	/* Rules r2 and r3 both match 6000. */
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"deciding"
	                                                    variables:@{ @"amount": @6000 } error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"UNIQUE"].location != NSNotFound, @"%@", error);
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)0);
	XCTAssertEqualObjects([[[self decide:@{ @"amount": @10 } engine:engine] objectForKey:@"result"]
		objectForKey:@"outcome"], @"approved");
}

- (void)testBindingsPickTheDecisionsVersion
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSData *deploymentBound = [self decidingProcess:^(WFDefinitionBuilder *b) {
		[b setDecisionBinding:WFCalledElementBindingDeployment version:0 forElement:@"decide"];
	}];
	[self deploy:@{ @"approval.dmn": WFApprovalDmn(@"100", @"FIRST"), @"deciding.bpmn": deploymentBound }
	      engine:engine name:@"v1"];
	[self deploy:@{ @"approval.dmn": WFApprovalDmn(@"10000", @"FIRST") } engine:engine name:@"v2"];
	NSDictionary *amount = @{ @"amount": @500 };
	XCTAssertEqualObjects([[[self decide:amount engine:engine] objectForKey:@"result"] objectForKey:@"outcome"],
		@"review", @"the version deployed with the process: a limit of 100");

	NSData *versionBound = [self decidingProcess:^(WFDefinitionBuilder *b) {
		[b setDecisionBinding:WFCalledElementBindingVersion version:1 forElement:@"decide"];
	}];
	[self deploy:@{ @"deciding.bpmn": versionBound } engine:engine name:@"pinned"];
	XCTAssertEqualObjects([[[self decide:amount engine:engine] objectForKey:@"result"] objectForKey:@"outcome"],
		@"review");
	[self deploy:@{ @"deciding.bpmn": [self decidingProcess:nil] } engine:engine name:@"latest"];
	XCTAssertEqualObjects([[[self decide:amount engine:engine] objectForKey:@"result"] objectForKey:@"outcome"],
		@"approved", @"the latest version: a limit of 10000");
}

- (void)testTheDecisionServiceAndHistory
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.historyLevel = WFHistoryLevelFull;
	WFDeployment *deployment = [self deploy:@{ @"approval.dmn": WFApprovalDmn(@"1000", @"COLLECT"),
	                                           @"deciding.bpmn": [self decidingProcess:^(WFDefinitionBuilder *b) {
		[b addBusinessRuleTask:@"decide" decision:@"approval" resultVariable:nil
		               mapping:WFDecisionResultMappingResultList];
	}] } engine:engine name:@"service"];
	WFDecisionResult *result = [engine.decisionService evaluateDecisionByKey:@"approval"
	                                                               variables:@{ @"amount": @7000 } error:&error];
	XCTAssertEqualObjects([[result collectEntries:@"outcome"] sortedArrayUsingSelector:@selector(compare:)],
		(@[ @"refused", @"review" ]), @"%@", error);
	result = [engine.decisionService evaluateDecisionById:[deployment.decisions.firstObject definitionId]
	                                            variables:@{ @"amount": @1 } error:&error];
	XCTAssertEqualObjects([result collectEntries:@"level"], @[ @1 ], @"%@", error);
	XCTAssertNil([engine.decisionService evaluateDecisionByKey:@"approval" variables:@{ @"amount": @"much" }
	                                                     error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorDecision);

	NSString *pid = [engine.runtimeService startProcessInstanceByKey:@"deciding"
	                                                       variables:@{ @"amount": @20 } error:&error].processInstanceId;
	NSArray *recorded = [engine.historyService historicDecisionInstancesForProcessInstance:pid];
	XCTAssertEqual([recorded count], (NSUInteger)1);
	WFHistoricDecisionInstance *instance = [recorded firstObject];
	XCTAssertEqualObjects(instance.activityId, @"decide");
	XCTAssertEqualObjects([instance.inputs objectForKey:@"i"], @20);
	XCTAssertEqualObjects([instance.outputs valueForKey:@"outcome"], @[ @"approved" ]);
	XCTAssertEqual([[engine.historyService historicDecisionInstancesForDecisionKey:@"approval"] count], (NSUInteger)3);
}

- (void)testNoDecisionHistoryBelowFull
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:@{ @"approval.dmn": WFApprovalDmn(@"1000", @"FIRST") } engine:engine name:@"audit"];
	XCTAssertNotNil([engine.decisionService evaluateDecisionByKey:@"approval" variables:@{ @"amount": @1 }
	                                                        error:&error], @"%@", error);
	XCTAssertEqual([[engine.historyService historicDecisionInstancesForDecisionKey:@"approval"] count], (NSUInteger)0);
}

- (void)testReadsAndWritesDecisionTasks
{
	NSError *error = nil;
	NSString *xml =
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\"><bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:businessRuleTask id=\"rule\" camunda:decisionRef=\"approval\" camunda:decisionRefBinding=\"version\" "
		 @"camunda:decisionRefVersion=\"3\" camunda:resultVariable=\"outcome\" camunda:mapDecisionResult=\"collectEntries\"/>"
		 @"<bpmn:endEvent id=\"e\"/><bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"rule\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"rule\" targetRef=\"e\"/></bpmn:process></bpmn:definitions>";
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	NSString *written = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
	WFTask *task = (WFTask *)[[WFBpmnReader definitionFromXMLString:written error:&error] nodeWithId:@"rule"];
	XCTAssertEqualObjects(task.decisionRef, @"approval", @"%@\n%@", error, written);
	XCTAssertEqual(task.decisionBinding, WFCalledElementBindingVersion);
	XCTAssertEqual(task.decisionVersion, (NSInteger)3);
	XCTAssertEqualObjects(task.resultVariable, @"outcome");
	XCTAssertEqual(task.mapDecisionResult, WFDecisionResultMappingCollectEntries);

	NSString *tagged = [xml stringByReplacingOccurrencesOfString:@"decisionRefBinding=\"version\""
	                                                  withString:@"decisionRefBinding=\"versionTag\""];
	XCTAssertNil([WFBpmnReader definitionFromXMLString:tagged error:&error]);
	NSString *unmapped = [xml stringByReplacingOccurrencesOfString:@"mapDecisionResult=\"collectEntries\""
	                                                    withString:@"mapDecisionResult=\"everything\""];
	XCTAssertNil([WFBpmnReader definitionFromXMLString:unmapped error:&error]);
}

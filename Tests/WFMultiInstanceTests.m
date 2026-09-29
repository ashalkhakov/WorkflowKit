#import "WFTestCase.h"

@interface WFMultiInstanceTests : WFTestCase
@end

@implementation WFMultiInstanceTests

/* start -> work (made multi-instance by loop) -> after (a user task) -> end.
 * kind: "service" (topic work), "user", or "subprocess" (a service task
 * inside, topic step). */
- (WFProcessDefinition *)loop:(void (^)(WFDefinitionBuilder *b))loop kind:(NSString *)kind
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"loop"];
	[b addStart:@"start"];
	if ([kind isEqualToString:@"service"]) {
		[b addServiceTask:@"work" action:@"work"];
	} else if ([kind isEqualToString:@"user"]) {
		[b addUserTask:@"work" name:@"Work" assignee:@"ann"];
	} else {
		WFDefinitionBuilder *inner = [WFDefinitionBuilder process:@"work"];
		[[[inner addStart:@"s"] addServiceTask:@"step" action:@"step"] addEnd:@"e"];
		[[inner connect:@"s" to:@"step"] connect:@"step" to:@"e"];
		[b addSubProcess:@"work" name:@"Work" inner:[inner build:&error]];
	}
	[[b addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"work"] connect:@"work" to:@"after"] connect:@"after" to:@"end"];
	loop(b);
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (NSArray<WFExternalTask *> *)fetch:(NSString *)topic engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	NSArray *tasks = [engine.externalTaskService fetchAndLock:100 workerId:@"w"
	                                                   topics:@{ topic: @60 } error:&error];
	XCTAssertNotNil(tasks, @"%@", error);
	return [tasks sortedArrayUsingComparator:^NSComparisonResult(WFExternalTask *x, WFExternalTask *y) {
		return [[x.variables objectForKey:@"loopCounter"] compare:[y.variables objectForKey:@"loopCounter"]];
	}];
}

- (void)finish:(WFExternalTask *)task engine:(WFProcessEngine *)engine variables:(NSDictionary *)variables
{
	NSError *error = nil;
	XCTAssertTrue([engine.externalTaskService complete:task.externalTaskId workerId:@"w"
	                                          variables:variables error:&error], @"%@", error);
}

- (NSArray<WFHistoricActivityInstance *> *)history:(NSString *)pid
                                          activity:(NSString *)activityId
                                            engine:(WFProcessEngine *)engine
{
	NSMutableArray *rows = [NSMutableArray array];
	for (WFHistoricActivityInstance *row in
	     [engine.historyService historicActivityInstancesForProcessInstance:pid]) {
		if ([row.activityId isEqualToString:activityId]) {
			[rows addObject:row];
		}
	}
	return rows;
}

- (void)testParallelInstancesOverACollection
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:NO loopCardinality:nil collection:@"reviewers"
		              elementVariable:@"reviewer" completionCondition:nil forElement:@"work"];
	} kind:@"service"] engine:engine variables:@{ @"reviewers": @[ @"ann", @"bob", @"cy" ] }];

	NSArray *tasks = [self fetch:@"work" engine:engine];
	XCTAssertEqual([tasks count], (NSUInteger)3);
	NSArray *expected = @[ @"ann", @"bob", @"cy" ];
	for (NSUInteger i = 0; i < [tasks count]; i++) {
		NSDictionary *variables = [[tasks objectAtIndex:i] variables];
		XCTAssertEqualObjects([variables objectForKey:@"reviewer"], [expected objectAtIndex:i]);
		XCTAssertEqualObjects([variables objectForKey:@"loopCounter"], @(i));
		XCTAssertEqualObjects([variables objectForKey:@"nrOfInstances"], @3);
		XCTAssertEqualObjects([variables objectForKey:@"nrOfActiveInstances"], @3);
	}
	/* The instances' own variables stay theirs. */
	XCTAssertNil([[engine.runtimeService variablesForProcessInstance:pid error:NULL]
		objectForKey:@"reviewer"]);

	[self finish:[tasks objectAtIndex:0] engine:engine variables:@{ @"seen": @YES }];
	[self finish:[tasks objectAtIndex:1] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"work" ]);
	[self finish:[tasks objectAtIndex:2] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	/* A new variable an instance sets lands on the process instance. */
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:pid error:NULL]
		objectForKey:@"seen"], @YES);

	NSArray *body = [self history:pid activity:@"work#multiInstanceBody" engine:engine];
	XCTAssertEqual([body count], (NSUInteger)1);
	XCTAssertEqualObjects([[body lastObject] activityType], @"multiInstanceBody");
	XCTAssertNotNil([[body lastObject] endTime]);
	XCTAssertEqual([[self history:pid activity:@"work" engine:engine] count], (NSUInteger)3);
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)1);
}

/* Instances finishing at once each count: the body's counters conflict,
 * and the caller retries, rather than one completion being lost. */
- (void)testInstancesFinishingAtOnceAreAllCounted
{
	NSError *error = nil;
	WFProcessEngine *engine = [self SQLiteEngineAtURL:[self temporarySQLiteURL] handler:nil];
	[self deploy:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:NO loopCardinality:@"4" collection:nil elementVariable:nil
		          completionCondition:nil forElement:@"work"];
	} kind:@"user"] engine:engine];
	for (int round = 0; round < 10; round++) {
		NSString *pid = [engine.runtimeService startProcessInstanceByKey:@"loop" variables:nil
		                                                           error:&error].processInstanceId;
		NSArray *tasks = [engine.taskService tasksForProcessInstance:pid];
		XCTAssertEqual([tasks count], (NSUInteger)4);
		dispatch_group_t group = dispatch_group_create();
		for (WFWorkItem *task in tasks) {
			dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				NSError *completeError = nil;
				while (![engine.taskService completeTask:task.taskId variables:nil error:&completeError]
				       && [completeError code] == WFErrorConflict) {
				}
			});
		}
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		WFDispatchRelease(group);
		XCTAssertEqualObjects([[engine.taskService tasksForProcessInstance:pid]
			valueForKey:@"taskDefinitionKey"], @[ @"after" ], @"round %d", round);
	}
}

- (void)testSequentialInstancesOneAfterAnother
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:YES loopCardinality:@"n + 1" collection:nil
		              elementVariable:nil completionCondition:nil forElement:@"work"];
	} kind:@"service"] engine:engine variables:@{ @"n": @2 }];
	for (NSUInteger i = 0; i < 3; i++) {
		NSArray *tasks = [self fetch:@"work" engine:engine];
		XCTAssertEqual([tasks count], (NSUInteger)1, @"round %lu", (unsigned long)i);
		NSDictionary *variables = [[tasks lastObject] variables];
		XCTAssertEqualObjects([variables objectForKey:@"loopCounter"], @(i));
		XCTAssertEqualObjects([variables objectForKey:@"nrOfCompletedInstances"], @(i));
		XCTAssertEqualObjects([variables objectForKey:@"nrOfActiveInstances"], @1);
		[self finish:[tasks lastObject] engine:engine variables:nil];
	}
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
}

- (void)testCompletionConditionCancelsTheRest
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:NO loopCardinality:@"4" collection:nil elementVariable:nil
		          completionCondition:@"nrOfCompletedInstances / nrOfInstances >= 0.5"
		                   forElement:@"work"];
	} kind:@"user"] engine:engine variables:nil];
	NSArray *tasks = [engine.taskService tasksForProcessInstance:pid];
	XCTAssertEqual([tasks count], (NSUInteger)4);
	NSError *error = nil;
	XCTAssertTrue([engine.taskService completeTask:[[tasks objectAtIndex:0] taskId] variables:nil error:&error],
		@"%@", error);
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:pid] count], (NSUInteger)3);
	XCTAssertTrue([engine.taskService completeTask:[[tasks objectAtIndex:1] taskId] variables:nil error:&error],
		@"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	NSUInteger deleted = 0;
	for (WFHistoricTaskInstance *task in [engine.historyService historicTaskInstancesForProcessInstance:pid]) {
		deleted += [task.deleteReason isEqualToString:WFTaskDeleteReasonDeleted];
	}
	XCTAssertEqual(deleted, (NSUInteger)2);
}

- (void)testNoInstancesPassesStraightThrough
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:NO loopCardinality:nil collection:@"items"
		              elementVariable:@"item" completionCondition:nil forElement:@"work"];
	} kind:@"service"] engine:engine variables:@{ @"items": @[] }];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	XCTAssertEqual([[self history:pid activity:@"work#multiInstanceBody" engine:engine] count],
		(NSUInteger)1);
	XCTAssertEqual([[self history:pid activity:@"work" engine:engine] count], (NSUInteger)0);
}

- (void)testATimerOnTheActivityCancelsEveryInstance
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:NO loopCardinality:@"3" collection:nil elementVariable:nil
		          completionCondition:nil forElement:@"work"];
		[b addBoundaryTimer:@"late" onTask:@"work" duration:3600 interrupting:YES];
		[b connect:@"late" to:@"after"];
	} kind:@"user"] engine:engine variables:nil];
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:pid] count], (NSUInteger)3);
	NSArray *jobs = [engine.managementService jobsForProcessInstance:pid];
	/* One timer, on the body, not one per instance. */
	XCTAssertEqual([jobs count], (NSUInteger)1);
	XCTAssertTrue([engine.managementService executeJob:[[jobs lastObject] jobId] error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:pid] count], (NSUInteger)1);
	XCTAssertTrue([[[self history:pid activity:@"work#multiInstanceBody" engine:engine] lastObject] isCanceled]);
}

- (void)testAnErrorFromOneInstanceIsCaughtOnTheActivity
{
	WFMapHandler *h = [[WFMapHandler alloc] init];
	[h.bpmnErrors setObject:@"STOP" forKey:@"work"];
	WFProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:NO loopCardinality:@"2" collection:nil elementVariable:nil
		          completionCondition:nil forElement:@"work"];
		[[b addUserTask:@"handle" name:@"Handle" assignee:@"ann"] addEnd:@"handled"];
		[b addBoundaryError:@"stopped" onTask:@"work" errorRef:@"STOP" interrupting:YES];
		[[b connect:@"stopped" to:@"handle"] connect:@"handle" to:@"handled"];
	} kind:@"service"] engine:engine variables:nil];
	XCTAssertTrue([self waitForActive:@"handle" in:pid engine:engine]);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"handle" ]);
	XCTAssertEqual([[self rows:@"WFExternalTask" engine:engine] count], (NSUInteger)0);
}

- (void)testMultiInstanceSubprocess
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:NO loopCardinality:nil collection:@"[\"a\", \"b\"]"
		              elementVariable:@"part" completionCondition:nil forElement:@"work"];
	} kind:@"subprocess"] engine:engine variables:nil];
	NSArray *steps = [self fetch:@"step" engine:engine];
	XCTAssertEqual([steps count], (NSUInteger)2);
	XCTAssertEqualObjects([[[steps objectAtIndex:0] variables] objectForKey:@"part"], @"a");
	XCTAssertEqualObjects([[[steps objectAtIndex:1] variables] objectForKey:@"part"], @"b");
	for (WFExternalTask *step in steps) {
		[self finish:step engine:engine variables:nil];
	}
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
}

- (void)testMultiInstanceCallActivity
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFDefinitionBuilder *c = [WFDefinitionBuilder process:@"child"];
	[[[c addStart:@"s"] addUserTask:@"check" name:@"Check" assignee:@"ann"] addEnd:@"e"];
	[[c connect:@"s" to:@"check"] connect:@"check" to:@"e"];
	[self deploy:[c build:&error] engine:engine];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"parent"];
	[[[[b addStart:@"start"] addCallActivity:@"call" calledElement:@"child"]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"call"] connect:@"call" to:@"after"] connect:@"after" to:@"end"];
	[b addInput:[WFVariableMapping mappingFrom:@"order" to:@"order"] forElement:@"call"];
	[b setMultiInstanceSequential:NO loopCardinality:nil collection:@"orders"
	              elementVariable:@"order" completionCondition:nil forElement:@"call"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"orders": @[ @"o1", @"o2" ] }];
	NSArray *children = [engine.runtimeService subProcessInstancesOf:pid error:NULL];
	XCTAssertEqual([children count], (NSUInteger)2);
	NSMutableSet *orders = [NSMutableSet set];
	for (WFProcessInstance *child in children) {
		[orders addObject:[[engine.runtimeService variablesForProcessInstance:child.processInstanceId
		                                                                error:NULL] objectForKey:@"order"]];
	}
	XCTAssertEqualObjects(orders, ([NSSet setWithObjects:@"o1", @"o2", nil]));
	for (WFProcessInstance *child in children) {
		[self complete:@"check" of:child.processInstanceId engine:engine variables:nil];
	}
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
}

- (void)testACollectionThatIsNotAListFailsTheStart
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self loop:^(WFDefinitionBuilder *b) {
		[b setMultiInstanceSequential:NO loopCardinality:nil collection:@"items"
		              elementVariable:@"item" completionCondition:nil forElement:@"work"];
	} kind:@"service"] engine:engine];
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"loop"
		variables:@{ @"items": @"not a list" } error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"not a list"].location != NSNotFound,
		@"%@", error);
	XCTAssertEqual([[self rows:@"WFExecution" engine:engine] count], (NSUInteger)0);
}

- (void)testTheBuilderRefusesALoopWithoutACount
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"p"];
	[[[b addStart:@"s"] addUserTask:@"t" name:@"T" assignee:nil] addEnd:@"e"];
	[[b connect:@"s" to:@"t"] connect:@"t" to:@"e"];
	[b setMultiInstanceSequential:NO loopCardinality:nil collection:nil elementVariable:nil
	          completionCondition:nil forElement:@"t"];
	XCTAssertNil([b build:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"cardinality or a collection"].location
		!= NSNotFound, @"%@", error);
}

static NSString *
WFLoopDocument(NSString *loop)
{
	return [NSString stringWithFormat:
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\" "
		 @"xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\">"
		 @"<bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:userTask id=\"review\">%@</bpmn:userTask>"
		 @"<bpmn:endEvent id=\"e\"/>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"review\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"review\" targetRef=\"e\"/>"
		 @"</bpmn:process></bpmn:definitions>", loop];
}

- (void)testReadsCamundaModelerLoops
{
	NSError *error = nil;
	NSString *xml = WFLoopDocument(
		@"<bpmn:multiInstanceLoopCharacteristics isSequential=\"true\" "
		 @"camunda:collection=\"${reviewers}\" camunda:elementVariable=\"reviewer\">"
		 @"<bpmn:completionCondition xsi:type=\"bpmn:tFormalExpression\">${approved == false}"
		 @"</bpmn:completionCondition></bpmn:multiInstanceLoopCharacteristics>");
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:xml error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	WFMultiInstance *loop = [[definition nodeWithId:@"review"] multiInstance];
	XCTAssertTrue(loop.isSequential);
	XCTAssertEqualObjects([loop.collection expressionString], @"reviewers");
	XCTAssertEqualObjects(loop.elementVariable, @"reviewer");
	XCTAssertEqualObjects([loop.completionCondition expressionString], @"approved = false");

	NSDictionary *refused = @{
		@"<bpmn:multiInstanceLoopCharacteristics camunda:asyncBefore=\"true\">"
		 @"<bpmn:loopCardinality>3</bpmn:loopCardinality></bpmn:multiInstanceLoopCharacteristics>":
			@"camunda:asyncBefore",
		@"<bpmn:multiInstanceLoopCharacteristics><bpmn:loopDataInputRef>x</bpmn:loopDataInputRef>"
		 @"</bpmn:multiInstanceLoopCharacteristics>": @"loopDataInputRef",
		@"<bpmn:standardLoopCharacteristics/>": @"standard loops",
		@"<bpmn:multiInstanceLoopCharacteristics><bpmn:loopCardinality>3</bpmn:loopCardinality>"
		 @"<bpmn:completionCondition>${size(list) > 1}"
		 @"</bpmn:completionCondition></bpmn:multiInstanceLoopCharacteristics>": @"completion condition",
		@"<bpmn:multiInstanceLoopCharacteristics/>": @"cardinality or a collection",
	};
	for (NSString *loopXML in refused) {
		error = nil;
		XCTAssertNil([WFBpmnReader definitionFromXMLString:WFLoopDocument(loopXML) error:&error], @"%@", loopXML);
		XCTAssertTrue([[error localizedDescription] rangeOfString:[refused objectForKey:loopXML]].location
			!= NSNotFound, @"%@: %@", loopXML, error);
	}
	/* The usual Camunda 7 completion condition, and the same in FEEL. */
	for (NSString *condition in @[ @"${nrOfCompletedInstances/nrOfInstances >= 0.6}",
	                               @"nrOfCompletedInstances / nrOfInstances >= 0.6" ]) {
		xml = WFLoopDocument([NSString stringWithFormat:
			@"<bpmn:multiInstanceLoopCharacteristics><bpmn:loopCardinality>3</bpmn:loopCardinality>"
			 @"<bpmn:completionCondition>%@</bpmn:completionCondition>"
			 @"</bpmn:multiInstanceLoopCharacteristics>", condition]);
		WFProcessDefinition *read = [WFBpmnReader definitionFromXMLString:xml error:&error];
		XCTAssertNotNil(read, @"%@", error);
		XCTAssertEqualObjects([[[read nodeWithId:@"review"] multiInstance].completionCondition expressionString],
			@"nrOfCompletedInstances / nrOfInstances >= 0.6");
	}
}

@end

#import "UDWorkflowTestCase.h"

@interface UDTimerTests : UDWorkflowTestCase
@end

@implementation UDTimerTests

- (UDProcessEngine *)steppedEngine
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	return engine;
}

/* start -> wait (a timer catch set by timer) -> done (a user task) -> end */
- (UDProcessDefinition *)waitFor:(void (^)(UDDefinitionBuilder *b))timer
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"wait"];
	[[[[b addStart:@"start"] addTimerCatch:@"wait" duration:0]
		addUserTask:@"done" name:@"Done" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"wait"] connect:@"wait" to:@"done"] connect:@"done" to:@"end"];
	timer(b);
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testADurationFromAVariable
{
	UDProcessEngine *engine = [self steppedEngine];
	NSDate *before = [NSDate date];
	NSString *pid = [self run:[self waitFor:^(UDDefinitionBuilder *b) {
		[b setTimer:UDTimerKindDuration expression:@"patience" forElement:@"wait"];
	}] engine:engine variables:@{ @"patience": @"PT2H" }];
	UDJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqualWithAccuracy([job.dueDate timeIntervalSinceDate:before], 7200.0, 5.0);
}

- (void)testADateFromAVariableAndFromFeel
{
	UDProcessEngine *engine = [self steppedEngine];
	NSDate *due = [NSDate dateWithTimeIntervalSince1970:4102444800];
	NSString *pid = [self run:[self waitFor:^(UDDefinitionBuilder *b) {
		[b setTimer:UDTimerKindDate expression:@"deadline" forElement:@"wait"];
	}] engine:engine variables:@{ @"deadline": due }];
	XCTAssertEqualObjects([[[engine.managementService jobsForProcessInstance:pid] lastObject] dueDate], due);

	pid = [self run:[self waitFor:^(UDDefinitionBuilder *b) {
		[b setTimer:UDTimerKindDate expression:@"deadline + @\"P1D\"" forElement:@"wait"];
	}] engine:engine variables:@{ @"deadline": due }];
	XCTAssertEqualObjects([[[engine.managementService jobsForProcessInstance:pid] lastObject] dueDate],
		[due dateByAddingTimeInterval:86400]);
}

- (void)testAValueThatIsNoTimeFailsTheCommand
{
	NSError *error = nil;
	UDProcessEngine *engine = [self steppedEngine];
	[self deploy:[self waitFor:^(UDDefinitionBuilder *b) {
		[b setTimer:UDTimerKindDate expression:@"deadline" forElement:@"wait"];
	}] engine:engine];
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"wait"
		variables:@{ @"deadline": @"next week" } error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"not a date and time"].location != NSNotFound,
		@"%@", error);
}

- (void)testATimerStartCycleStartsAsManyInstances
{
	NSError *error = nil;
	UDProcessEngine *engine = [self steppedEngine];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"hourly"];
	[[[b addTimerStart:@"tick" duration:0] addUserTask:@"look" name:@"Look" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"tick" to:@"look"] connect:@"look" to:@"end"];
	[b setTimer:[UDTimer timerWithKind:UDTimerKindCycle text:@"R3/PT1H"] forElement:@"tick"];
	[self deploy:[b build:&error] engine:engine];
	NSString *definitionId = [[engine.repositoryService latestDefinitionForKey:@"hourly" error:NULL] definitionId];
	NSDate *previous = nil;
	for (int round = 0; round < 3; round++) {
		NSArray *jobs = [engine.managementService jobsForDefinition:definitionId];
		XCTAssertEqual([jobs count], (NSUInteger)1, @"round %d", round);
		UDJob *job = [jobs lastObject];
		if (previous != nil) {
			XCTAssertEqualWithAccuracy([job.dueDate timeIntervalSinceDate:previous], 3600.0, 0.001);
		}
		previous = job.dueDate;
		XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@", error);
	}
	XCTAssertEqual([[engine.managementService jobsForDefinition:definitionId] count], (NSUInteger)0);
	XCTAssertEqual([[self rows:@"UDTask" engine:engine] count], (NSUInteger)3);
}

- (void)testANonInterruptingBoundaryCycleFiresAgain
{
	NSError *error = nil;
	UDProcessEngine *engine = [self steppedEngine];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"nag"];
	[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"] addEnd:@"end"];
	[[b addBoundaryTimer:@"remind" onTask:@"work" duration:0 interrupting:NO]
		addUserTask:@"reminded" name:@"Reminded" assignee:@"ann"];
	[b addEnd:@"remindedEnd"];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[[b connect:@"remind" to:@"reminded"] connect:@"reminded" to:@"remindedEnd"];
	[b setTimer:UDTimerKindCycle expression:@"\"R2/PT10M\"" forElement:@"remind"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	for (int round = 0; round < 2; round++) {
		UDJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
		XCTAssertNotNil(job, @"round %d", round);
		XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@", error);
	}
	XCTAssertEqual([[engine.managementService jobsForProcessInstance:pid] count], (NSUInteger)0);
	NSArray *keys = [[engine.taskService tasksForProcessInstance:pid] valueForKey:@"taskDefinitionKey"];
	XCTAssertEqual([keys count], (NSUInteger)3);
	XCTAssertTrue([keys containsObject:@"work"]);
}

- (void)testAnInterruptingTimerFiresOnceWhateverItsCycle
{
	NSError *error = nil;
	UDProcessEngine *engine = [self steppedEngine];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"once"];
	[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"] addEnd:@"end"];
	[[b addBoundaryTimer:@"late" onTask:@"work" duration:0 interrupting:YES]
		addUserTask:@"escalated" name:@"Escalated" assignee:@"boss"];
	[b addEnd:@"escalatedEnd"];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[[b connect:@"late" to:@"escalated"] connect:@"escalated" to:@"escalatedEnd"];
	[b setTimer:[UDTimer timerWithKind:UDTimerKindCycle text:@"R/PT1H"] forElement:@"late"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	UDJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"escalated" ]);
	XCTAssertEqual([[engine.managementService jobsForProcessInstance:pid] count], (NSUInteger)0);
}

- (void)testATimerStartThatNeedsVariablesFailsTheDeployment
{
	NSError *error = nil;
	UDProcessEngine *engine = [self steppedEngine];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"bad"];
	[[[b addTimerStart:@"tick" duration:0] addUserTask:@"look" name:@"Look" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"tick" to:@"look"] connect:@"look" to:@"end"];
	[b setTimer:UDTimerKindDate expression:@"when" forElement:@"tick"];
	XCTAssertNil([engine.repositoryService deployDefinition:[b build:&error] error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"tick"].location != NSNotFound, @"%@", error);
}

static NSString *
UDTimerDocument(NSString *timer)
{
	return [NSString stringWithFormat:
		@"<bpmn:definitions xmlns:bpmn=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" id=\"d\">"
		 @"<bpmn:process id=\"p\" isExecutable=\"true\">"
		 @"<bpmn:startEvent id=\"s\"/>"
		 @"<bpmn:intermediateCatchEvent id=\"t\"><bpmn:timerEventDefinition>%@"
		 @"</bpmn:timerEventDefinition></bpmn:intermediateCatchEvent>"
		 @"<bpmn:endEvent id=\"e\"/>"
		 @"<bpmn:sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"t\"/>"
		 @"<bpmn:sequenceFlow id=\"f2\" sourceRef=\"t\" targetRef=\"e\"/>"
		 @"</bpmn:process></bpmn:definitions>", timer];
}

- (void)testReadsTimersAsModelersWriteThem
{
	NSDictionary *cases = @{
		@"<bpmn:timeDate>2030-01-01T09:00:00Z</bpmn:timeDate>": @"@\"2030-01-01T09:00:00Z\"",
		@"<bpmn:timeDate>${deadline}</bpmn:timeDate>": @"deadline",
		@"<bpmn:timeDuration>P2W</bpmn:timeDuration>": @"@\"P14D\"",
		@"<bpmn:timeDuration>=duration(wait) * 2</bpmn:timeDuration>": @"duration(wait) * 2",
		@"<bpmn:timeCycle>R/PT1H</bpmn:timeCycle>": @"\"R/PT1H\"",
		@"<bpmn:timeCycle>R3/2030-01-01T09:00:00Z/P1D</bpmn:timeCycle>": @"\"R3/2030-01-01T09:00:00Z/P1D\"",
	};
	for (NSString *timer in cases) {
		NSError *error = nil;
		UDProcessDefinition *definition = [UDBpmnReader definitionFromXMLString:UDTimerDocument(timer) error:&error];
		XCTAssertNotNil(definition, @"%@: %@", timer, error);
		XCTAssertEqualObjects([[(UDEvent *)[definition nodeWithId:@"t"] timer].expression expressionString],
			[cases objectForKey:timer], @"%@", timer);
	}
	NSDictionary *refused = @{
		@"<bpmn:timeCycle>0 0 9 * * ?</bpmn:timeCycle>": @"cron",
		@"<bpmn:timeDate>2030-01-01</bpmn:timeDate><bpmn:timeDuration>PT1H</bpmn:timeDuration>": @"one of",
		@"": @"needs timeDate",
	};
	for (NSString *timer in refused) {
		NSError *error = nil;
		XCTAssertNil([UDBpmnReader definitionFromXMLString:UDTimerDocument(timer) error:&error], @"%@", timer);
		XCTAssertTrue([[error localizedDescription] rangeOfString:[refused objectForKey:timer]].location
			!= NSNotFound, @"%@: %@", timer, error);
	}
}

@end

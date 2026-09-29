#import "UDWorkflowTestCase.h"

@interface UDEventTests : UDWorkflowTestCase
@end

@implementation UDEventTests

#pragma mark - Events

- (void)testTimerAndMessageCatch
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	UDDefinitionBuilder *tb = [UDDefinitionBuilder process:@"t"];
	[[[tb addStart:@"start"] addTimerCatch:@"wait" duration:0] addEnd:@"end"];
	[[tb connect:@"start" to:@"wait"] connect:@"wait" to:@"end"];
	NSString *timed = [self run:[tb build:&error] engine:engine variables:nil];
	XCTAssertTrue([self waitForEnd:timed engine:engine seconds:5.0]);

	UDDefinitionBuilder *mb = [UDDefinitionBuilder process:@"m"];
	[[[mb addStart:@"start"] addMessageCatch:@"go" message:@"go"] addEnd:@"end"];
	[[mb connect:@"start" to:@"go"] connect:@"go" to:@"end"];
	NSString *waiting = [self run:[mb build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:waiting engine:engine], @[ @"go" ]);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"go"
	                                    processInstanceId:waiting
	                                            variables:@{ @"ok": @YES }
	                                                error:&error], @"%@", error);
	XCTAssertTrue([self ended:waiting engine:engine]);
	XCTAssertEqualObjects([[self variables:waiting engine:engine] objectForKey:@"ok"], @YES);
}

- (UDProcessDefinition *)raceDefinition:(NSTimeInterval)timeout
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"egw"];
	[[[[b addStart:@"start"] addEventBased:@"choice"]
		addMessageCatch:@"msg" message:@"arrive"]
		addTimerCatch:@"timeout" duration:timeout];
	[[b addEnd:@"arrived"] addEnd:@"timedOut"];
	[b connect:@"start" to:@"choice"];
	[[b connect:@"choice" to:@"msg"] connect:@"choice" to:@"timeout"];
	[[b connect:@"msg" to:@"arrived"] connect:@"timeout" to:@"timedOut"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testEventBasedGatewayMessageWins
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self raceDefinition:30] engine:engine variables:nil];
	/* The path waits at the gateway itself. */
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"choice" ]);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"arrive" processInstanceId:pid
	                                            variables:nil error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	/* The losing timer went with the path. */
	XCTAssertEqual([[self rows:@"UDJob" engine:engine] count], (NSUInteger)0);
}

- (void)testEventBasedGatewayTimerWins
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine openWithError:&error], @"%@", error);
	NSString *pid = [self run:[self raceDefinition:0.2] engine:engine variables:nil];
	XCTAssertFalse([self ended:pid engine:engine]);
	XCTAssertTrue([self waitForEnd:pid engine:engine seconds:5.0]);
	XCTAssertFalse([engine.runtimeService correlateMessage:@"arrive" processInstanceId:pid
	                                             variables:nil error:&error]);
	XCTAssertEqual([[self rows:@"UDEventSubscription" engine:engine] count], (NSUInteger)0);
}

- (void)testInterruptingTimerBoundary
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"escalate"];
	[[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"]
		addUserTask:@"escalated" name:@"Escalated" assignee:@"boss"] addEnd:@"end"];
	[b addBoundaryTimer:@"late" onTask:@"work" duration:0.2 interrupting:YES];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[[b connect:@"late" to:@"escalated"] connect:@"escalated" to:@"end"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine openWithError:&error], @"%@", error);
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"work" ]);
	XCTAssertTrue([self waitForActive:@"escalated" in:pid engine:engine]);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"escalated" ]);
	XCTAssertNil([self task:@"work" of:pid engine:engine], @"the interrupted task is gone");
}

- (void)testNonInterruptingMessageBoundaryStaysArmed
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"nudge"];
	[[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"]
		addUserTask:@"answer" name:@"Answer" assignee:@"ann"] addEnd:@"end"];
	[b addEnd:@"answered"];
	[b addBoundaryMessage:@"asked" onTask:@"work" message:@"question" interrupting:NO];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[[b connect:@"asked" to:@"answer"] connect:@"answer" to:@"answered"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	for (int round = 0; round < 2; round++) {
		XCTAssertTrue([engine.runtimeService correlateMessage:@"question" processInstanceId:pid
		                                            variables:nil error:&error], @"%@", error);
		XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"answer", @"work" ]));
		[self complete:@"answer" of:pid engine:engine variables:nil];
		XCTAssertEqualObjects([self active:pid engine:engine], @[ @"work" ]);
	}
	[self complete:@"work" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

#pragma mark - Messages and correlation

- (UDProcessDefinition *)paymentDefinition
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"corr"];
	[[[b addStart:@"start"] addMessageCatch:@"pay" message:@"paid"] addEnd:@"end"];
	[[b connect:@"start" to:@"pay"] connect:@"pay" to:@"end"];
	return [b build:&error];
}

- (void)testCorrelationByBusinessKeyAndVariables
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self paymentDefinition] engine:engine];
	UDRuntimeService *runtime = engine.runtimeService;
	NSString *eight = [runtime startProcessInstanceByKey:@"corr" businessKey:@"SO-8"
	                                           variables:@{ @"region": @"eu" } error:&error].processInstanceId;
	NSString *nine = [runtime startProcessInstanceByKey:@"corr" businessKey:@"SO-9"
	                                          variables:@{ @"region": @"us" } error:&error].processInstanceId;
	/* Two recipients: correlating to exactly one fails and changes nothing. */
	XCTAssertFalse([runtime correlateMessage:@"paid" businessKey:nil correlationKeys:nil
	                               variables:nil error:&error]);
	XCTAssertTrue([runtime correlateMessage:@"paid" businessKey:@"SO-9" correlationKeys:nil
	                              variables:@{ @"paid": @YES } error:&error], @"%@", error);
	XCTAssertTrue([self ended:nine engine:engine]);
	XCTAssertFalse([self ended:eight engine:engine]);
	XCTAssertTrue([runtime correlateMessage:@"paid" businessKey:nil
	                        correlationKeys:@{ @"region": @"eu" }
	                              variables:nil error:&error], @"%@", error);
	XCTAssertTrue([self ended:eight engine:engine]);
}

- (void)testCorrelateToAll
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self paymentDefinition] engine:engine];
	for (int i = 0; i < 3; i++) {
		[engine.runtimeService startProcessInstanceByKey:@"corr" variables:nil error:&error];
	}
	NSArray *reached = [engine.runtimeService correlateMessageToAll:@"paid" businessKey:nil
	                                                correlationKeys:nil variables:nil
	                                                          error:&error];
	XCTAssertEqual([reached count], (NSUInteger)3, @"%@", error);
	XCTAssertEqual([[self rows:@"UDExecution" engine:engine] count], (NSUInteger)0);
}

- (void)testMessageStartEvent
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"onOrder"];
	[[[b addMessageStart:@"received" message:@"order"] addUserTask:@"pack" name:@"Pack" assignee:@"joe"]
		addEnd:@"end"];
	[[b connect:@"received" to:@"pack"] connect:@"pack" to:@"end"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[b build:&error] engine:engine];
	XCTAssertTrue([engine.runtimeService correlateMessage:@"order" businessKey:@"SO-1"
	                                      correlationKeys:nil variables:@{ @"qty": @2 }
	                                                error:&error], @"%@", error);
	UDWorkItem *pack = [[engine.taskService tasksForAssignee:@"joe"] lastObject];
	XCTAssertNotNil(pack);
	XCTAssertEqualObjects([[engine.runtimeService processInstanceWithId:pack.processInstanceId
	                                                             error:&error] businessKey], @"SO-1");
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:pack.processInstanceId
	                                                                    error:&error] objectForKey:@"qty"], @2);
}

#pragma mark - Jobs

- (void)testTimerStartEvent
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"nightly"];
	[[[b addTimerStart:@"tick" duration:0.2] addUserTask:@"report" name:@"Report" assignee:@"ops"]
		addEnd:@"end"];
	[[b connect:@"tick" to:@"report"] connect:@"report" to:@"end"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine openWithError:&error], @"%@", error);
	UDDeployment *deployment = [engine.repositoryService deployDefinition:[b build:&error] error:&error];
	NSString *definitionId = [[deployment.definitions lastObject] definitionId];
	XCTAssertEqual([[engine.managementService jobsForDefinition:definitionId] count], (NSUInteger)1);
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
	while ([deadline timeIntervalSinceNow] > 0
	       && [[engine.taskService tasksForAssignee:@"ops"] count] == 0) {
		[NSThread sleepForTimeInterval:0.02];
	}
	XCTAssertEqual([[engine.taskService tasksForAssignee:@"ops"] count], (NSUInteger)1);
	XCTAssertEqual([[engine.managementService jobsForDefinition:definitionId] count], (NSUInteger)0);
}

- (void)testNewVersionReplacesTheTimerStart
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *ids[2];
	for (int version = 0; version < 2; version++) {
		UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"weekly"];
		[[[b addTimerStart:@"tick" duration:3600] addUserTask:@"report" name:@"Report" assignee:@"ops"]
			addEnd:version == 0 ? @"end" : @"done"];
		[[b connect:@"tick" to:@"report"] connect:@"report" to:version == 0 ? @"end" : @"done"];
		ids[version] = [[[engine.repositoryService deployDefinition:[b build:&error] error:&error]
			definitions] lastObject].definitionId;
	}
	XCTAssertEqual([[engine.managementService jobsForDefinition:ids[0]] count], (NSUInteger)0);
	XCTAssertEqual([[engine.managementService jobsForDefinition:ids[1]] count], (NSUInteger)1);
}

#pragma mark - Signals and terminate

- (UDProcessDefinition *)waitForSignal:(NSString *)key signal:(NSString *)signal
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:key];
	[[[b addStart:@"start"] addSignalCatch:@"wait" signal:signal] addEnd:@"end"];
	[[b connect:@"start" to:@"wait"] connect:@"wait" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testSignalReachesEveryWaitingInstance
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self waitForSignal:@"listener" signal:@"go"] engine:engine];
	NSMutableArray *pids = [NSMutableArray array];
	for (int i = 0; i < 3; i++) {
		[pids addObject:[engine.runtimeService startProcessInstanceByKey:@"listener"
		                                                       variables:nil error:&error].processInstanceId];
	}
	XCTAssertTrue([engine.runtimeService signal:@"go" variables:@{ @"why": @"launch" } error:&error], @"%@", error);
	for (NSString *pid in pids) {
		XCTAssertTrue([self ended:pid engine:engine]);
		XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"why"], @"launch");
	}
	/* Nobody waiting any more: still not an error. */
	XCTAssertTrue([engine.runtimeService signal:@"go" variables:nil error:&error], @"%@", error);
}

- (void)testThrownSignalStartsAndWakesInOneTransaction
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	UDDefinitionBuilder *thrower = [UDDefinitionBuilder process:@"alarm"];
	[[[thrower addStart:@"start"] addSignalThrow:@"ring" signal:@"fire"] addSignalEnd:@"done" signal:@"allClear"];
	[[thrower connect:@"start" to:@"ring"] connect:@"ring" to:@"done"];
	UDDefinitionBuilder *starter = [UDDefinitionBuilder process:@"evacuate"];
	[[[starter addSignalStart:@"heard" signal:@"fire"] addUserTask:@"leave" name:@"Leave" assignee:@"everyone"]
		addEnd:@"out"];
	[[starter connect:@"heard" to:@"leave"] connect:@"leave" to:@"out"];
	[self deploy:[thrower build:&error] engine:engine];
	[self deploy:[starter build:&error] engine:engine];
	[self deploy:[self waitForSignal:@"sprinkler" signal:@"fire"] engine:engine];
	[self deploy:[self waitForSignal:@"reset" signal:@"allClear"] engine:engine];
	NSString *sprinkler = [engine.runtimeService startProcessInstanceByKey:@"sprinkler"
	                                                            variables:nil error:&error].processInstanceId;
	NSString *reset = [engine.runtimeService startProcessInstanceByKey:@"reset"
	                                                        variables:nil error:&error].processInstanceId;

	UDProcessInstance *alarm = [engine.runtimeService startProcessInstanceByKey:@"alarm"
	                                                                 variables:nil error:&error];
	XCTAssertTrue(alarm.isEnded, @"%@", error);
	XCTAssertTrue([self ended:sprinkler engine:engine]);
	XCTAssertTrue([self ended:reset engine:engine], @"the signal end event broadcast too");
	XCTAssertEqual([[engine.taskService tasksForAssignee:@"everyone"] count], (NSUInteger)1,
		@"the signal start event started an instance");
}

- (void)testSignalBoundaryAndSignallingOneInstance
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"recallable"];
	[[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"]
		addUserTask:@"recheck" name:@"Recheck" assignee:@"ann"] addEnd:@"end"];
	[b addEnd:@"rechecked"];
	[b addBoundarySignal:@"recalled" onTask:@"work" signal:@"recall" interrupting:NO];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[[b connect:@"recalled" to:@"recheck"] connect:@"recheck" to:@"rechecked"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *first = [self run:[b build:&error] engine:engine variables:nil];
	NSString *second = [engine.runtimeService startProcessInstanceByKey:@"recallable"
	                                                         variables:nil error:&error].processInstanceId;
	XCTAssertTrue([engine.runtimeService signal:@"recall" processInstanceId:first
	                                  variables:nil error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:first engine:engine], (@[ @"recheck", @"work" ]));
	XCTAssertEqualObjects([self active:second engine:engine], @[ @"work" ]);
	/* Non-interrupting: it stays armed. */
	XCTAssertTrue([engine.runtimeService signal:@"recall" variables:nil error:&error], @"%@", error);
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:first] count], (NSUInteger)3);
	XCTAssertEqualObjects([self active:second engine:engine], (@[ @"recheck", @"work" ]));
}

- (void)testTerminateEndEndsEveryPath
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"abort"];
	[[[[b addStart:@"start"] addParallel:@"fork"] addUserTask:@"slow" name:@"Slow" assignee:@"ann"]
		addUserTask:@"decide" name:@"Decide" assignee:@"boss"];
	[[b addEnd:@"done"] addTerminateEnd:@"stop"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"slow"] connect:@"fork" to:@"decide"];
	[[b connect:@"slow" to:@"done"] connect:@"decide" to:@"stop"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	[self complete:@"decide" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"UDExecution" engine:engine] count], (NSUInteger)0);
	XCTAssertEqual([[self rows:@"UDTask" engine:engine] count], (NSUInteger)0);
	NSDictionary *reasons = [NSDictionary dictionaryWithObjects:
			[[engine.historyService historicTaskInstancesForProcessInstance:pid] valueForKey:@"deleteReason"]
		forKeys:[[engine.historyService historicTaskInstancesForProcessInstance:pid] valueForKey:@"taskDefinitionKey"]];
	XCTAssertEqualObjects([reasons objectForKey:@"slow"], UDTaskDeleteReasonDeleted);
	XCTAssertEqualObjects([reasons objectForKey:@"decide"], UDTaskDeleteReasonCompleted);
}

- (void)testTerminateInsideASubprocessEndsOnlyTheSubprocess
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"attempt"];
	[[[[inner addStart:@"s"] addParallel:@"fork"] addUserTask:@"wait" name:@"Wait" assignee:@"ann"]
		addTerminateEnd:@"enough"];
	[inner addEnd:@"e"];
	[inner connect:@"s" to:@"fork"];
	[[inner connect:@"fork" to:@"wait"] connect:@"fork" to:@"enough"];
	[inner connect:@"wait" to:@"e"];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"outer"];
	[[[[b addStart:@"start"] addSubProcess:@"sub" name:@"Sub" inner:[inner build:&error]]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"sub"] connect:@"sub" to:@"after"] connect:@"after" to:@"end"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"after" ]);
	XCTAssertFalse([self ended:pid engine:engine]);
}

@end

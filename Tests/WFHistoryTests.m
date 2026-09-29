#import "WFTestCase.h"

@interface WFHistoryTests : WFTestCase
@end

@implementation WFHistoryTests

#pragma mark - History

- (WFProcessDefinition *)exclusiveDefinition
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"route"];
	[[[[b addStart:@"start"] addExclusive:@"g" defaultFlow:@"low"] addUserTask:@"review" name:@"Review" assignee:@"ann"]
		addEnd:@"end"];
	[b connect:@"start" to:@"g"];
	[b connect:@"g" to:@"review" when:@"amount > 1000"];
	[b connect:@"g" to:@"end" flowId:@"low"];
	[b connect:@"review" to:@"end"];
	WFProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testActivityHistoryRecordsThePath
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self exclusiveDefinition] engine:engine variables:@{ @"amount": @5000 }];
	[self complete:@"review" of:pid engine:engine variables:@{ @"ok": @YES }];
	NSArray *activities = [engine.historyService historicActivityInstancesForProcessInstance:pid];
	XCTAssertEqualObjects([activities valueForKey:@"activityId"], (@[ @"start", @"g", @"review", @"end" ]));
	XCTAssertEqualObjects([activities valueForKey:@"activityType"],
		(@[ @"startEvent", @"exclusiveGateway", @"userTask", @"endEvent" ]));
	for (WFHistoricActivityInstance *activity in activities) {
		XCTAssertNotNil(activity.endTime, @"%@", activity);
		XCTAssertFalse(activity.canceled, @"%@", activity);
	}
	XCTAssertEqualObjects([[activities objectAtIndex:2] activityName], @"Review");

	WFHistoricTaskInstance *task = [[engine.historyService historicTaskInstancesForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(task.taskDefinitionKey, @"review");
	XCTAssertEqualObjects(task.assignee, @"ann");
	XCTAssertEqualObjects(task.deleteReason, WFTaskDeleteReasonCompleted);
	XCTAssertNotNil(task.endTime);
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:pid] state],
		WFProcessInstanceStateCompleted);
}

- (void)testRunningActivitiesHaveNoEndTime
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self exclusiveDefinition] engine:engine variables:@{ @"amount": @5000 }];
	WFHistoricActivityInstance *review =
		[[engine.historyService historicActivityInstancesForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(review.activityId, @"review");
	XCTAssertNil(review.endTime);
	XCTAssertNil([[engine.historyService historicProcessInstanceWithId:pid] endTime]);
}

- (void)testInterruptedTaskIsCanceledInHistory
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"escalate"];
	[[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"]
		addUserTask:@"escalated" name:@"Escalated" assignee:@"boss"] addEnd:@"end"];
	[b addBoundaryTimer:@"late" onTask:@"work" duration:3600 interrupting:YES];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[[b connect:@"late" to:@"escalated"] connect:@"escalated" to:@"end"];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.historyLevel = WFHistoryLevelFull;
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	WFJob *timer = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertTrue([engine.managementService executeJob:timer.jobId error:&error], @"%@", error);

	NSArray *activities = [engine.historyService historicActivityInstancesForProcessInstance:pid];
	XCTAssertEqualObjects([activities valueForKey:@"activityId"],
		(@[ @"start", @"work", @"late", @"escalated" ]));
	WFHistoricActivityInstance *work = [activities objectAtIndex:1];
	XCTAssertTrue(work.canceled);
	XCTAssertNotNil(work.endTime);
	XCTAssertFalse([[activities objectAtIndex:2] isCanceled]);
	XCTAssertEqualObjects([[activities objectAtIndex:2] activityType], @"boundaryEvent");
	NSArray *tasks = [engine.historyService historicTaskInstancesForProcessInstance:pid];
	XCTAssertEqualObjects([tasks valueForKey:@"deleteReason"], (@[ WFTaskDeleteReasonDeleted, [NSNull null] ]),
		@"%@ %@", [tasks valueForKey:@"taskDefinitionKey"], [tasks valueForKey:@"deleteReason"]);
	NSArray *log = [engine.historyService historicJobLogForProcessInstance:pid];
	XCTAssertEqualObjects([log valueForKey:@"state"], (@[ WFJobLogStateCreated, WFJobLogStateSuccessful ]));
}

- (void)testParallelJoinHistory
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"both"];
	[[[[b addStart:@"start"] addParallel:@"fork"] addUserTask:@"a" name:@"A" assignee:@"x"]
		addUserTask:@"b" name:@"B" assignee:@"y"];
	[[b addParallel:@"join"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"a"] connect:@"fork" to:@"b"];
	[[b connect:@"a" to:@"join"] connect:@"b" to:@"join"];
	[b connect:@"join" to:@"end"];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	[self complete:@"a" of:pid engine:engine variables:nil];
	[self complete:@"b" of:pid engine:engine variables:nil];
	NSArray *activities = [engine.historyService historicActivityInstancesForProcessInstance:pid];
	NSCountedSet *ids = [NSCountedSet setWithArray:[activities valueForKey:@"activityId"]];
	XCTAssertEqual([ids countForObject:@"a"], (NSUInteger)1);
	XCTAssertEqual([ids countForObject:@"b"], (NSUInteger)1);
	XCTAssertEqual([ids countForObject:@"end"], (NSUInteger)1);
	XCTAssertEqual([ids countForObject:@"join"], (NSUInteger)2, @"one per arriving path");
	for (WFHistoricActivityInstance *activity in activities) {
		XCTAssertNotNil(activity.endTime, @"%@", activity);
	}
}

- (void)testHistoryLevelNoneWritesNothing
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.historyLevel = WFHistoryLevelNone;
	[self deploy:[self exclusiveDefinition] engine:engine];
	WFProcessInstance *instance = [engine.runtimeService startProcessInstanceByKey:@"route"
	                                                                    variables:@{ @"amount": @5 }
	                                                                        error:&error];
	XCTAssertTrue(instance.isEnded, @"%@", error);
	XCTAssertNil([engine.historyService historicProcessInstanceWithId:instance.processInstanceId]);
	XCTAssertEqual([[engine.historyService historicActivityInstancesForProcessInstance:instance.processInstanceId]
		count], (NSUInteger)0);
	XCTAssertEqual([[engine.historyService historicVariablesForProcessInstance:instance.processInstanceId]
		count], (NSUInteger)0);
}

- (void)testActivityLevelKeepsNoVariables
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.historyLevel = WFHistoryLevelActivity;
	NSString *pid = [self run:[self exclusiveDefinition] engine:engine variables:@{ @"amount": @5 }];
	XCTAssertNotNil([[engine.historyService historicProcessInstanceWithId:pid] endTime]);
	XCTAssertEqual([[engine.historyService historicActivityInstancesForProcessInstance:pid] count], (NSUInteger)3);
	XCTAssertEqual([[engine.historyService historicVariablesForProcessInstance:pid] count], (NSUInteger)0);
}

- (void)testFullLevelKeepsUpdatesIncidentsAndTheJobLog
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.historyLevel = WFHistoryLevelFull;
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self fragileDefinition:nil] engine:engine variables:@{ @"amount": @1 }];
	WFManagementService *management = engine.managementService;
	NSString *jobId = [[[management jobsForProcessInstance:pid] lastObject] jobId];
	for (int attempt = 0; attempt < 3; attempt++) {
		/* amount 1 matches "small"; unset it so the gateway finds no path. */
		if (attempt == 0) {
			XCTAssertTrue([engine.runtimeService setVariables:@{ @"amount": [NSNull null] }
			                                processInstanceId:pid error:&error], @"%@", error);
		}
		XCTAssertFalse([management executeJob:jobId error:&error]);
	}
	WFHistoricIncident *open = [[engine.historyService historicIncidentsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(open.state, WFIncidentStateOpen);
	XCTAssertEqualObjects(open.configuration, jobId);

	XCTAssertTrue([engine.runtimeService setVariables:@{ @"amount": @500 } processInstanceId:pid error:&error]);
	XCTAssertTrue([management setRetries:1 forJob:jobId error:&error], @"%@", error);
	XCTAssertTrue([management executeJob:jobId error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);

	WFHistoricIncident *resolved = [[engine.historyService historicIncidentsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(resolved.state, WFIncidentStateResolved);
	XCTAssertNotNil(resolved.endTime);
	NSArray *updates = [engine.historyService historicVariableUpdatesForProcessInstance:pid];
	XCTAssertEqualObjects([updates valueForKey:@"value"], (@[ @1, [NSNull null], @500 ]));
	NSArray *log = [engine.historyService historicJobLogForProcessInstance:pid];
	XCTAssertEqualObjects([log valueForKey:@"state"], (@[ WFJobLogStateCreated, WFJobLogStateFailed,
		WFJobLogStateFailed, WFJobLogStateFailed, WFJobLogStateSuccessful ]));
	XCTAssertEqualObjects([log valueForKey:@"retries"], (@[ @3, @2, @1, @0, @1 ]));
	XCTAssertEqualObjects([[engine.historyService historicVariablesForProcessInstance:pid] objectForKey:@"amount"], @500);
}

#pragma mark - History cleanup

- (void)testHistoryCleanupRemovesWhatOutlivedItsTimeToLive
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pids[3];
	NSNumber *ttls[3] = { @0, @30, nil };
	for (int i = 0; i < 3; i++) {
		WFDefinitionBuilder *b = [WFDefinitionBuilder process:[NSString stringWithFormat:@"kept%d", i]];
		[[b addStart:@"start"] addEnd:@"end"];
		[b connect:@"start" to:@"end"];
		if (ttls[i] != nil) {
			[b setHistoryTimeToLive:[ttls[i] integerValue]];
		}
		pids[i] = [self run:[b build:&error] engine:engine variables:@{ @"x": @1 }];
		XCTAssertTrue([self ended:pids[i] engine:engine]);
	}
	XCTAssertEqual([engine.historyService cleanUpHistory:100 error:&error], (NSInteger)1, @"%@", error);
	/* Time to live 0: gone, with its activities and variables. */
	XCTAssertNil([engine.historyService historicProcessInstanceWithId:pids[0]]);
	XCTAssertEqual([[engine.historyService historicActivityInstancesForProcessInstance:pids[0]] count], (NSUInteger)0);
	XCTAssertEqual([[engine.historyService historicVariablesForProcessInstance:pids[0]] count], (NSUInteger)0);
	/* 30 days, and none at all: kept. */
	XCTAssertNotNil([engine.historyService historicProcessInstanceWithId:pids[1]]);
	XCTAssertNotNil([engine.historyService historicProcessInstanceWithId:pids[2]]);
}

- (void)testTheStoreKeepsItsHistoryLevel
{
	NSError *error = nil;
	NSURL *url = [self temporarySQLiteURL];
	@autoreleasepool {
		WFProcessEngine *first = [self SQLiteEngineAtURL:url handler:nil];
		XCTAssertTrue([first openWithError:&error], @"%@", error);
		[first close];
	}
	WFProcessEngine *full = [self SQLiteEngineAtURL:url handler:nil];
	full.historyLevel = WFHistoryLevelFull;
	XCTAssertFalse([full openWithError:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorInvalidState);
	[full close];
	WFProcessEngine *same = [self SQLiteEngineAtURL:url handler:nil];
	XCTAssertTrue([same openWithError:&error], @"%@", error);
	[same close];
}

@end

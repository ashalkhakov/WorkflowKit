#import "WFTestCase.h"

@interface WFJobTests : WFTestCase
@end

@implementation WFJobTests

#pragma mark - Jobs

- (void)testAsyncBeforeWaitsForItsJob
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"later"];
	[[[b addStart:@"start"] addServiceTask:@"book" action:@"book"] addEnd:@"end"];
	[[b connect:@"start" to:@"book"] connect:@"book" to:@"end"];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"book"];
	WFMapHandler *h = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:h];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	/* The start command stopped before the task: no call yet, one job. */
	XCTAssertEqual([h calls], (NSUInteger)0);
	NSArray *jobs = [engine.managementService jobsForProcessInstance:pid];
	XCTAssertEqual([jobs count], (NSUInteger)1);
	WFJob *job = [jobs lastObject];
	XCTAssertEqualObjects(job.jobType, WFJobTypeAsyncBeforeName);
	XCTAssertEqualObjects(job.activityId, @"book");
	XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:pid timeout:10.0]);
	XCTAssertEqual([h calls], (NSUInteger)1);
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testAsyncAfterWaitsForItsJob
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"thenLater"];
	[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"] addEnd:@"end"];
	[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"end"];
	[b setAsyncBefore:NO asyncAfter:YES exclusive:YES forElement:@"approve"];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	[self complete:@"approve" of:pid engine:engine variables:@{ @"ok": @YES }];
	/* The task is done and its variables committed; leaving waits. */
	XCTAssertFalse([self ended:pid engine:engine]);
	XCTAssertNil([self task:@"approve" of:pid engine:engine]);
	WFJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(job.jobType, WFJobTypeAsyncAfterName);
	XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"ok"], @YES);
}

- (void)testFailingJobRaisesAnIncidentUntilFixed
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self fragileDefinition:nil] engine:engine variables:nil];
	WFManagementService *management = engine.managementService;
	NSString *jobId = [[[management jobsForProcessInstance:pid] lastObject] jobId];
	for (NSInteger left = 2; left >= 0; left--) {
		XCTAssertFalse([management executeJob:jobId error:&error]);
		XCTAssertEqual([error code], (NSInteger)WFErrorNoPath);
		XCTAssertEqual([[management jobWithId:jobId] retries], left);
	}
	WFIncident *incident = [[management incidentsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(incident.incidentType, WFIncidentTypeFailedJobName);
	XCTAssertEqualObjects(incident.configuration, jobId);
	XCTAssertEqualObjects(incident.activityId, @"route");
	XCTAssertNotNil([[management jobWithId:jobId] exceptionMessage]);

	/* Fix the data, give the job an attempt: the incident goes, the job
	 * runs, the instance ends. */
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"amount": @500 }
	                                processInstanceId:pid error:&error], @"%@", error);
	XCTAssertTrue([management setRetries:1 forJob:jobId error:&error], @"%@", error);
	XCTAssertEqual([[management incidentsForProcessInstance:pid] count], (NSUInteger)0);
	XCTAssertTrue([management executeJob:jobId error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testRetryTimeCycleDelaysTheRetry
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self fragileDefinition:@"R4/PT10M"] engine:engine variables:nil];
	WFJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqual(job.retries, (NSInteger)5, @"the first attempt and four retries");
	XCTAssertFalse([engine.managementService executeJob:job.jobId error:&error]);
	WFJob *after = [engine.managementService jobWithId:job.jobId];
	XCTAssertEqual(after.retries, (NSInteger)4);
	XCTAssertEqualWithAccuracy([after.dueDate timeIntervalSinceNow], 600.0, 5.0);
}

- (void)testJobExecutorRetriesByItself
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	XCTAssertTrue([engine openWithError:&error], @"%@", error);
	NSString *pid = [self run:[self fragileDefinition:nil] engine:engine variables:nil];
	/* Three attempts in the background, then an incident. */
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
	while ([deadline timeIntervalSinceNow] > 0
	       && [[engine.managementService incidentsForProcessInstance:pid] count] == 0) {
		[NSThread sleepForTimeInterval:0.02];
	}
	XCTAssertEqual([[engine.managementService incidentsForProcessInstance:pid] count], (NSUInteger)1);
}

#pragma mark - Priorities, gateways and boundaries

- (WFProcessDefinition *)forkJoinDefinition:(BOOL)asyncFork asyncJoin:(BOOL)asyncJoin
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"forked"];
	[[[[b addStart:@"start"] addParallel:@"fork"] addUserTask:@"a" name:@"A" assignee:@"x"]
		addUserTask:@"b" name:@"B" assignee:@"y"];
	[[b addParallel:@"join"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"a"] connect:@"fork" to:@"b"];
	[[b connect:@"a" to:@"join"] connect:@"b" to:@"join"];
	[b connect:@"join" to:@"end"];
	[b setAsyncBefore:NO asyncAfter:asyncFork exclusive:YES forElement:@"fork"];
	[b setAsyncBefore:NO asyncAfter:asyncJoin exclusive:YES forElement:@"join"];
	WFProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testAsyncAfterOnAForkDefersTheSplit
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self forkJoinDefinition:YES asyncJoin:NO] engine:engine variables:nil];
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:pid] count], (NSUInteger)0);
	NSArray *jobs = [engine.managementService jobsForProcessInstance:pid];
	XCTAssertEqual([jobs count], (NSUInteger)1, @"one job, which then forks");
	XCTAssertTrue([engine.managementService executeJob:[[jobs lastObject] jobId] error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"a", @"b" ]));
}

- (void)testAsyncAfterOnAJoinFiresThenWaits
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self forkJoinDefinition:NO asyncJoin:YES] engine:engine variables:nil];
	[self complete:@"a" of:pid engine:engine variables:nil];
	XCTAssertEqual([[engine.managementService jobsForProcessInstance:pid] count], (NSUInteger)0,
		@"the join still waits for b");
	[self complete:@"b" of:pid engine:engine variables:nil];
	NSArray *jobs = [engine.managementService jobsForProcessInstance:pid];
	XCTAssertEqual([jobs count], (NSUInteger)1);
	XCTAssertFalse([self ended:pid engine:engine]);
	XCTAssertTrue([engine.managementService executeJob:[[jobs lastObject] jobId] error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testAsyncBeforeOnABoundaryEvent
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"escalateLater"];
	[[[[b addStart:@"start"] addUserTask:@"work" name:@"Work" assignee:@"ann"]
		addUserTask:@"escalated" name:@"Escalated" assignee:@"boss"] addEnd:@"end"];
	[b addBoundaryTimer:@"late" onTask:@"work" duration:3600 interrupting:YES];
	[[b connect:@"start" to:@"work"] connect:@"work" to:@"end"];
	[[b connect:@"late" to:@"escalated"] connect:@"escalated" to:@"end"];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"late"];
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	WFJob *timer = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertTrue([engine.managementService executeJob:timer.jobId error:&error], @"%@", error);
	/* The task is interrupted; passing the boundary waits for its job. */
	XCTAssertNil([self task:@"work" of:pid engine:engine]);
	XCTAssertNil([self task:@"escalated" of:pid engine:engine]);
	WFJob *before = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(before.jobType, WFJobTypeAsyncBeforeName);
	XCTAssertEqualObjects(before.activityId, @"late");
	XCTAssertTrue([engine.managementService executeJob:before.jobId error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"escalated" ]);
}

@end

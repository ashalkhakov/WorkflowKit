#import "UDWorkflowTestCase.h"

@interface UDExternalTaskTests : UDWorkflowTestCase
@end

@implementation UDExternalTaskTests

#pragma mark - Service tasks

- (UDProcessDefinition *)failingDefinition:(BOOL)withBoundary
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:withBoundary ? @"err" : @"plain"];
	[[[b addStart:@"start"] addServiceTask:@"work" action:@"boom"] addEnd:@"ok"];
	[b connect:@"start" to:@"work"];
	[b connect:@"work" to:@"ok"];
	if (withBoundary) {
		[[b addBoundaryError:@"onerr" onTask:@"work" errorRef:@"BOOM" interrupting:YES]
			addUserTask:@"handle" name:@"Handle" assignee:@"ops"];
		[b addEnd:@"handled"];
		[[b connect:@"onerr" to:@"handle"] connect:@"handle" to:@"handled"];
	}
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testBpmnErrorTakesTheBoundary
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.bpmnErrors setObject:@"BOOM" forKey:@"boom"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self failingDefinition:YES] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"handle" ]);
}

- (void)testUncaughtBpmnErrorEndsThePath
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.bpmnErrors setObject:@"BOOM" forKey:@"boom"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self failingDefinition:NO] engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testFailedServiceIsRetried
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.failures setObject:@2 forKey:@"boom"];
	[h.results setObject:@{ @"done": @YES } forKey:@"boom"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self failingDefinition:NO] engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([h calls], (NSUInteger)3);
	/* The same external task each time. */
	XCTAssertEqual([[NSSet setWithArray:h.taskIds] count], (NSUInteger)1);
}

- (void)testServiceFailuresRunOutOfRetries
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.failures setObject:@-1 forKey:@"boom"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self failingDefinition:NO] engine:engine variables:nil];
	XCTAssertEqual([h calls], (NSUInteger)3);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"work" ]);
	NSDictionary *task = [[self rows:@"UDExternalTask" engine:engine] lastObject];
	XCTAssertEqualObjects([task objectForKey:@"retries"], @0);
	XCTAssertEqualObjects([task objectForKey:@"errorMessage"], @"down");
	UDIncident *incident = [[engine.managementService incidentsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(incident.incidentType, UDIncidentTypeFailedExternalTaskName);
	XCTAssertEqualObjects(incident.configuration, [task objectForKey:@"externalTaskId"]);
	XCTAssertEqualObjects(incident.activityId, @"work");
}

#pragma mark - External tasks

- (UDProcessDefinition *)twoTopicsDefinition
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"shipping"];
	[[[[[b addStart:@"start"] addParallel:@"fork"] addServiceTask:@"pack" action:@"pack"]
		addServiceTask:@"bill" action:@"bill"] addParallel:@"join"];
	[b addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"pack"] connect:@"fork" to:@"bill"];
	[[b connect:@"pack" to:@"join"] connect:@"bill" to:@"join"];
	[b connect:@"join" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testExternalWorkerFetchesLocksAndCompletes
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self twoTopicsDefinition] engine:engine variables:@{ @"order": @"SO-5" }];
	UDExternalTaskService *tasks = engine.externalTaskService;

	/* Only the topic asked for. */
	NSArray *packs = [tasks fetchAndLock:10 workerId:@"packer" topics:@{ @"pack": @60 } error:&error];
	XCTAssertEqual([packs count], (NSUInteger)1, @"%@", error);
	UDExternalTask *pack = [packs lastObject];
	XCTAssertEqualObjects(pack.topic, @"pack");
	XCTAssertEqualObjects(pack.workerId, @"packer");
	XCTAssertEqualObjects([pack.variables objectForKey:@"order"], @"SO-5");
	/* Locked: nobody else gets it. */
	XCTAssertEqual([[tasks fetchAndLock:10 workerId:@"other" topics:@{ @"pack": @60 } error:&error] count],
		(NSUInteger)0);
	/* Only the worker holding the lock may complete it. */
	XCTAssertFalse([tasks complete:pack.externalTaskId workerId:@"other" variables:nil error:&error]);
	XCTAssertTrue([tasks complete:pack.externalTaskId workerId:@"packer"
	                    variables:@{ @"packed": @YES } error:&error], @"%@", error);

	UDExternalTask *bill = [[tasks fetchAndLock:10 workerId:@"biller" topics:@{ @"bill": @60, @"pack": @60 }
	                                      error:&error] lastObject];
	XCTAssertEqualObjects(bill.topic, @"bill");
	XCTAssertTrue([tasks complete:bill.externalTaskId workerId:@"biller"
	                    variables:@{ @"billed": @YES } error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	NSDictionary *vars = [self variables:pid engine:engine];
	XCTAssertEqualObjects([vars objectForKey:@"packed"], @YES);
	XCTAssertEqualObjects([vars objectForKey:@"billed"], @YES);
}

- (void)testExpiredLockPassesToAnotherWorker
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	[self run:[self failingDefinition:NO] engine:engine variables:nil];
	UDExternalTaskService *tasks = engine.externalTaskService;
	UDExternalTask *first = [[tasks fetchAndLock:1 workerId:@"slow" topics:@{ @"boom": @0.1 } error:&error] lastObject];
	XCTAssertNotNil(first, @"%@", error);
	[NSThread sleepForTimeInterval:0.2];
	UDExternalTask *second = [[tasks fetchAndLock:1 workerId:@"fast" topics:@{ @"boom": @60 } error:&error] lastObject];
	XCTAssertEqualObjects(second.externalTaskId, first.externalTaskId);
	XCTAssertFalse([tasks complete:first.externalTaskId workerId:@"slow" variables:nil error:&error],
		@"the lock is someone else's now");
	XCTAssertTrue([tasks complete:first.externalTaskId workerId:@"fast" variables:nil error:&error], @"%@", error);
}

- (void)testExtendedLockHoldsTheTask
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	[self run:[self failingDefinition:NO] engine:engine variables:nil];
	UDExternalTaskService *tasks = engine.externalTaskService;
	UDExternalTask *task = [[tasks fetchAndLock:1 workerId:@"w" topics:@{ @"boom": @0.2 } error:&error] lastObject];
	XCTAssertFalse([tasks extendLock:task.externalTaskId workerId:@"x" duration:60 error:&error]);
	XCTAssertTrue([tasks extendLock:task.externalTaskId workerId:@"w" duration:60 error:&error], @"%@", error);
	[NSThread sleepForTimeInterval:0.3];
	XCTAssertEqual([[tasks fetchAndLock:1 workerId:@"x" topics:@{ @"boom": @60 } error:&error] count],
		(NSUInteger)0);
}

- (void)testWorkerFailuresRunOutThenRetriesResume
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self failingDefinition:NO] engine:engine variables:nil];
	UDExternalTaskService *tasks = engine.externalTaskService;
	NSDictionary *topics = @{ @"boom": @60 };

	UDExternalTask *task = [[tasks fetchAndLock:1 workerId:@"w" topics:topics error:&error] lastObject];
	XCTAssertTrue([tasks handleFailure:task.externalTaskId workerId:@"w" errorMessage:@"down"
	                           retries:1 retryTimeout:0.2 error:&error], @"%@", error);
	/* Waiting out the timeout. */
	XCTAssertEqual([[tasks fetchAndLock:1 workerId:@"w" topics:topics error:&error] count], (NSUInteger)0);
	[NSThread sleepForTimeInterval:0.3];
	task = [[tasks fetchAndLock:1 workerId:@"w" topics:topics error:&error] lastObject];
	XCTAssertEqualObjects(task.retries, @1);
	XCTAssertEqualObjects(task.errorMessage, @"down");
	XCTAssertTrue([tasks handleFailure:task.externalTaskId workerId:@"w" errorMessage:@"still down"
	                           retries:0 retryTimeout:0 error:&error], @"%@", error);
	/* None left: an incident, and not fetched. */
	UDIncident *incident = [[engine.managementService incidentsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(incident.incidentType, UDIncidentTypeFailedExternalTaskName);
	XCTAssertEqualObjects(incident.message, @"still down");
	XCTAssertEqual([[tasks fetchAndLock:1 workerId:@"w" topics:topics error:&error] count], (NSUInteger)0);

	XCTAssertTrue([tasks setRetries:2 forExternalTask:task.externalTaskId error:&error], @"%@", error);
	XCTAssertEqual([[engine.managementService incidentsForProcessInstance:pid] count], (NSUInteger)0);
	task = [[tasks fetchAndLock:1 workerId:@"w" topics:topics error:&error] lastObject];
	XCTAssertNotNil(task);
	XCTAssertTrue([tasks complete:task.externalTaskId workerId:@"w" variables:nil error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testWorkerBpmnErrorTakesTheBoundary
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self failingDefinition:YES] engine:engine variables:nil];
	UDExternalTaskService *tasks = engine.externalTaskService;
	UDExternalTask *task = [[tasks fetchAndLock:1 workerId:@"w" topics:@{ @"boom": @60 } error:&error] lastObject];
	XCTAssertTrue([tasks handleBpmnError:task.externalTaskId workerId:@"w" errorCode:@"BOOM"
	                           variables:@{ @"reason": @"out of stock" } error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"handle" ]);
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:pid error:&error]
		objectForKey:@"reason"], @"out of stock");
	XCTAssertEqual([[tasks externalTasksForProcessInstance:pid] count], (NSUInteger)0);
}

- (void)testInProcessIncidentIsResolvedByRetries
{
	NSError *error = nil;
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.failures setObject:@3 forKey:@"boom"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self failingDefinition:NO] engine:engine variables:nil];
	XCTAssertEqual([h calls], (NSUInteger)3);
	UDIncident *incident = [[engine.managementService incidentsForProcessInstance:pid] lastObject];
	XCTAssertNotNil(incident);
	/* The handler recovered: one more attempt, and the in-process worker
	 * picks the task up by itself. */
	XCTAssertTrue([engine.externalTaskService setRetries:1 forExternalTask:incident.configuration
	                                               error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:pid timeout:10.0]);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([h calls], (NSUInteger)4);
}

#pragma mark - Priorities, gateways and boundaries

- (void)testTaskPriorityOrdersTheFetchAndVariablesCanBeChosen
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"ranked"];
	[[[[[b addStart:@"start"] addParallel:@"fork"] addServiceTask:@"low" action:@"work"]
		addServiceTask:@"high" action:@"work"] addParallel:@"join"];
	[b addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"low"] connect:@"fork" to:@"high"];
	[[b connect:@"low" to:@"join"] connect:@"high" to:@"join"];
	[b connect:@"join" to:@"end"];
	[b setDefaultTaskPriority:5];
	[b setTaskPriority:10 forElement:@"high"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	[self run:[b build:&error] engine:engine variables:@{ @"a": @1, @"b": @2 }];
	NSArray *tasks = [engine.externalTaskService fetchAndLock:10 workerId:@"w"
	                                                   topics:@{ @"work": @60 }
	                                            variableNames:@{ @"work": @[ @"b" ] }
	                                                    error:&error];
	XCTAssertEqualObjects([tasks valueForKey:@"activityId"], (@[ @"high", @"low" ]));
	XCTAssertEqualObjects([tasks valueForKey:@"priority"], (@[ @10, @5 ]));
	XCTAssertEqualObjects([[tasks firstObject] variables], @{ @"b": @2 });
}

@end

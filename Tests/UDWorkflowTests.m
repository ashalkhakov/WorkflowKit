#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "UDWorkflow.h"

@interface UDMapHandler : NSObject <UDServiceTaskHandler>
@property (nonatomic, strong) NSMutableDictionary *results;
/* Topic to the BPMN error code the task answers with. */
@property (nonatomic, strong) NSMutableDictionary *bpmnErrors;
/* Topic to the number of failures before the task succeeds. */
@property (nonatomic, strong) NSMutableDictionary *failures;
/* Invocations taken and never finished, as if the process died mid-call. */
@property (nonatomic) BOOL drops;
@property (nonatomic, strong) NSMutableArray *taskIds;
@end

@implementation UDMapHandler
- (instancetype)init
{
	self = [super init];
	if (self) {
		_results = [NSMutableDictionary dictionary];
		_bpmnErrors = [NSMutableDictionary dictionary];
		_failures = [NSMutableDictionary dictionary];
		_taskIds = [NSMutableArray array];
	}
	return self;
}
- (void)performInvocation:(UDServiceInvocation *)invocation
{
	NSInteger failuresLeft = 0;
	@synchronized (self) {
		[self.taskIds addObject:invocation.externalTaskId];
		failuresLeft = [[self.failures objectForKey:invocation.topic] integerValue];
		if (failuresLeft > 0) {
			[self.failures setObject:[NSNumber numberWithInteger:failuresLeft - 1]
			                  forKey:invocation.topic];
		}
	}
	if (self.drops) {
		return;
	}
	NSString *code = [self.bpmnErrors objectForKey:invocation.topic];
	if (code != nil) {
		[invocation finishWithVariables:nil
		                          error:[NSError errorWithDomain:UDWorkflowErrorDomain
		                                                    code:UDWorkflowErrorHandler
		                                                userInfo:@{ UDWorkflowErrorRefKey: code }]];
		return;
	}
	if (failuresLeft != 0) {
		[invocation finishWithVariables:nil
		                          error:[NSError errorWithDomain:@"test"
		                                                    code:1
		                                                userInfo:@{ NSLocalizedDescriptionKey: @"down" }]];
		return;
	}
	[invocation finishWithVariables:[self.results objectForKey:invocation.topic] error:nil];
}
- (NSUInteger)calls
{
	@synchronized (self) {
		return [self.taskIds count];
	}
}
@end

@interface UDCompletingDelegate : NSObject <UDProcessEngineDelegate>
@property (nonatomic, strong) NSMutableArray *ended;
@end

@implementation UDCompletingDelegate
- (instancetype)init
{
	self = [super init];
	if (self) {
		_ended = [NSMutableArray array];
	}
	return self;
}
/* Completes every task from inside the callback. */
- (void)processEngine:(UDProcessEngine *)engine taskCreated:(UDWorkItem *)task
{
	[engine.taskService completeTask:task.taskId variables:@{ @"byDelegate": @YES } error:NULL];
}
- (void)processEngine:(UDProcessEngine *)engine processInstanceEnded:(UDProcessInstance *)instance
{
	(void)engine;
	@synchronized (self) {
		[self.ended addObject:instance.processInstanceId];
	}
}
@end

@interface UDWorkflowTests : XCTestCase
@end

@implementation UDWorkflowTests

- (UDProcessEngine *)engineWithHandler:(UDMapHandler *)handler
{
	NSError *error = nil;
	UDStore *store = [UDStore inMemoryStore:&error];
	XCTAssertNotNil(store, @"%@", error);
	UDProcessEngine *engine = [[UDProcessEngine alloc] initWithStore:store];
	engine.serviceHandler = handler;
	return engine;
}

- (NSURL *)temporarySQLiteURL
{
	NSString *name = [NSString stringWithFormat:@"udworkflow-%@.sqlite",
		[[NSUUID UUID] UUIDString]];
	return [NSURL fileURLWithPath:
		[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (UDProcessEngine *)SQLiteEngineAtURL:(NSURL *)url handler:(UDMapHandler *)handler
{
	NSError *error = nil;
	UDStore *store = [UDStore SQLiteStoreAtURL:url error:&error];
	XCTAssertNotNil(store, @"%@", error);
	UDProcessEngine *engine = [[UDProcessEngine alloc] initWithStore:store];
	engine.serviceHandler = handler;
	return engine;
}

- (void)deploy:(UDProcessDefinition *)definition engine:(UDProcessEngine *)engine
{
	NSError *error = nil;
	XCTAssertNotNil(definition);
	XCTAssertNotNil([engine.repositoryService deployDefinition:definition error:&error],
		@"%@", error);
}

/* Deploys, starts, and waits for the engine's own work on the instance. */
- (NSString *)run:(UDProcessDefinition *)definition
           engine:(UDProcessEngine *)engine
        variables:(NSDictionary *)variables
{
	NSError *error = nil;
	[self deploy:definition engine:engine];
	UDProcessInstance *instance =
		[engine.runtimeService startProcessInstanceByKey:definition.processId
		                                       variables:variables
		                                           error:&error];
	XCTAssertNotNil(instance, @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:instance.processInstanceId timeout:10.0]);
	return instance.processInstanceId;
}

- (BOOL)ended:(NSString *)processInstanceId engine:(UDProcessEngine *)engine
{
	return [[engine.historyService historicProcessInstanceWithId:processInstanceId] endTime] != nil;
}

- (NSDictionary *)variables:(NSString *)processInstanceId engine:(UDProcessEngine *)engine
{
	return [engine.historyService historicVariablesForProcessInstance:processInstanceId];
}

- (NSArray *)active:(NSString *)processInstanceId engine:(UDProcessEngine *)engine
{
	return [engine.runtimeService activeActivityIdsForProcessInstance:processInstanceId error:NULL];
}

- (UDWorkItem *)task:(NSString *)key of:(NSString *)processInstanceId engine:(UDProcessEngine *)engine
{
	for (UDWorkItem *task in [engine.taskService tasksForProcessInstance:processInstanceId]) {
		if ([task.taskDefinitionKey isEqualToString:key]) {
			return task;
		}
	}
	return nil;
}

- (void)complete:(NSString *)key
              of:(NSString *)processInstanceId
          engine:(UDProcessEngine *)engine
       variables:(NSDictionary *)variables
{
	NSError *error = nil;
	UDWorkItem *task = [self task:key of:processInstanceId engine:engine];
	XCTAssertNotNil(task, @"no task %@", key);
	XCTAssertTrue([engine.taskService completeTask:task.taskId variables:variables error:&error],
		@"%@", error);
	XCTAssertTrue([engine waitUntilSettled:processInstanceId timeout:10.0]);
}

/* Timers are waits, not work: poll history until the instance ends. */
- (BOOL)waitForEnd:(NSString *)processInstanceId
            engine:(UDProcessEngine *)engine
           seconds:(NSTimeInterval)seconds
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
	while ([deadline timeIntervalSinceNow] > 0) {
		[engine waitUntilSettled:processInstanceId timeout:1.0];
		if ([self ended:processInstanceId engine:engine]) {
			return YES;
		}
		[NSThread sleepForTimeInterval:0.02];
	}
	return NO;
}

- (BOOL)waitForActive:(NSString *)activityId
                   in:(NSString *)processInstanceId
               engine:(UDProcessEngine *)engine
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
	while ([deadline timeIntervalSinceNow] > 0) {
		if ([[self active:processInstanceId engine:engine] containsObject:activityId]) {
			return YES;
		}
		[NSThread sleepForTimeInterval:0.02];
	}
	return NO;
}

- (NSArray *)rows:(NSString *)entity engine:(UDProcessEngine *)engine
{
	__block NSArray *rows = nil;
	NSManagedObjectContext *context = [engine.store newCommandContext];
	[context performBlockAndWait:^{
		NSArray *objects = [context executeFetchRequest:
			[NSFetchRequest fetchRequestWithEntityName:entity] error:NULL];
		NSMutableArray *values = [NSMutableArray array];
		for (NSManagedObject *object in objects) {
			[values addObject:[object dictionaryWithValuesForKeys:
				[[[object entity] attributesByName] allKeys]]];
		}
		rows = values;
	}];
	return rows;
}

- (UDProcessDefinition *)approvalDefinition
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"approval"];
	[[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"]
		addServiceTask:@"book" action:@"book"] addEnd:@"end"];
	[[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"book"]
		connect:@"book" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

#pragma mark - Gateways

- (void)testExclusiveAutoApprove
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"xor"];
	[[[[b addStart:@"start"] addExclusive:@"g" defaultFlow:@"low"] addServiceTask:@"hi" action:@"hi"]
		addServiceTask:@"lo" action:@"lo"];
	[b addEnd:@"end"];
	[b connect:@"start" to:@"g"];
	[b connect:@"g" to:@"hi" key:@"amount" op:UDComparisonOpGreater value:@1000];
	[b connect:@"g" to:@"lo" flowId:@"low"];
	[[b connect:@"hi" to:@"end"] connect:@"lo" to:@"end"];
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"path": @"lo" } forKey:@"lo"];
	[h.results setObject:@{ @"path": @"hi" } forKey:@"hi"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"amount": @50 }];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"path"], @"lo");
}

- (void)testParallelJoin
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"and"];
	[[[[b addStart:@"start"] addParallel:@"fork"] addServiceTask:@"a" action:@"a"]
		addServiceTask:@"b" action:@"b"];
	[[b addParallel:@"join"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"a"] connect:@"fork" to:@"b"];
	[[b connect:@"a" to:@"join"] connect:@"b" to:@"join"];
	[b connect:@"join" to:@"end"];
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"a": @YES } forKey:@"a"];
	[h.results setObject:@{ @"b": @YES } forKey:@"b"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	NSDictionary *vars = [self variables:pid engine:engine];
	XCTAssertEqualObjects([vars objectForKey:@"a"], @YES);
	XCTAssertEqualObjects([vars objectForKey:@"b"], @YES);
}

- (void)testParallelJoinWaitsForBothUserTasks
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"review"];
	[[[[b addStart:@"start"] addParallel:@"fork"]
		addUserTask:@"legal" name:@"Legal" assignee:@"ann"]
		addUserTask:@"finance" name:@"Finance" assignee:@"bob"];
	[[[b addParallel:@"join"] addUserTask:@"sign" name:@"Sign" assignee:@"cat"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"legal"] connect:@"fork" to:@"finance"];
	[[b connect:@"legal" to:@"join"] connect:@"finance" to:@"join"];
	[[b connect:@"join" to:@"sign"] connect:@"sign" to:@"end"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"finance", @"legal" ]));
	XCTAssertEqual([[engine.taskService tasksForAssignee:@"ann"] count], (NSUInteger)1);
	[self complete:@"legal" of:pid engine:engine variables:nil];
	/* Waiting at the join is not active. */
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"finance" ]);
	[self complete:@"finance" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"sign" ]);
	/* One path again: the tree is back to the process instance alone. */
	XCTAssertEqual([[self rows:@"UDExecution" engine:engine] count], (NSUInteger)1);
	[self complete:@"sign" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual([[self rows:@"UDExecution" engine:engine] count], (NSUInteger)0);
}

- (UDProcessDefinition *)inclusiveDefinition
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"or"];
	[[[[b addStart:@"start"] addInclusive:@"split" defaultFlow:@"d"]
		addServiceTask:@"audit" action:@"audit"] addServiceTask:@"ship" action:@"ship"];
	[[b addInclusive:@"join" defaultFlow:nil] addEnd:@"end"];
	[b connect:@"start" to:@"split"];
	[b connect:@"split" to:@"audit" key:@"audit" op:UDComparisonOpEqual value:@YES];
	[b connect:@"split" to:@"ship" key:@"ship" op:UDComparisonOpEqual value:@YES];
	[b connect:@"split" to:@"ship" flowId:@"d"];
	[[b connect:@"audit" to:@"join"] connect:@"ship" to:@"join"];
	[b connect:@"join" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testInclusiveTwoBranches
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"audited": @YES } forKey:@"audit"];
	[h.results setObject:@{ @"shipped": @YES } forKey:@"ship"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self inclusiveDefinition] engine:engine
	                variables:@{ @"audit": @YES, @"ship": @YES }];
	XCTAssertTrue([self ended:pid engine:engine]);
	NSDictionary *vars = [self variables:pid engine:engine];
	XCTAssertEqualObjects([vars objectForKey:@"audited"], @YES);
	XCTAssertEqualObjects([vars objectForKey:@"shipped"], @YES);
}

- (void)testInclusiveJoinWithOneBranchTaken
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"audited": @YES } forKey:@"audit"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self inclusiveDefinition] engine:engine
	                variables:@{ @"audit": @YES, @"ship": @NO }];
	/* Nothing else can reach the join, so it does not wait for "ship". */
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertNil([[self variables:pid engine:engine] objectForKey:@"shipped"]);
}

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

#pragma mark - Subprocesses and variables

- (void)testSubProcess
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"inner"];
	[[inner addStart:@"s"] addServiceTask:@"step" action:@"step"];
	[inner addEnd:@"e"];
	[[inner connect:@"s" to:@"step"] connect:@"step" to:@"e"];
	UDDefinitionBuilder *outer = [UDDefinitionBuilder process:@"outer"];
	[[[outer addStart:@"s0"] addSubProcess:@"sub" name:@"sub" inner:[inner build:&error]] addEnd:@"e0"];
	[[outer connect:@"s0" to:@"sub"] connect:@"sub" to:@"e0"];
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"inner": @YES } forKey:@"step"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[outer build:&error] engine:engine variables:@{ @"seen": @1 }];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"inner"], @YES);
}

- (void)testUserTaskInsideSubProcess
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"checks"];
	[[[inner addStart:@"s"] addUserTask:@"check" name:@"Check" assignee:@"qa"] addEnd:@"e"];
	[[inner connect:@"s" to:@"check"] connect:@"check" to:@"e"];
	UDDefinitionBuilder *outer = [UDDefinitionBuilder process:@"release"];
	[[[outer addStart:@"s0"] addSubProcess:@"sub" name:@"sub" inner:[inner build:&error]]
		addEnd:@"e0"];
	[[outer connect:@"s0" to:@"sub"] connect:@"sub" to:@"e0"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[outer build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"check" ]);
	[self complete:@"check" of:pid engine:engine variables:@{ @"checked": @YES }];
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"checked"], @YES);
}

- (void)testVariableTypes
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	[self deploy:[self approvalDefinition] engine:engine];
	NSDate *when = [NSDate dateWithTimeIntervalSince1970:1700000000.5];
	NSDictionary *values = @{
		@"text": @"x", @"yes": @YES, @"count": @42, @"ratio": @2.5, @"when": when,
		@"blob": [@"b" dataUsingEncoding:NSUTF8StringEncoding], @"none": [NSNull null],
		@"list": @[ @1, @"two" ], @"map": @{ @"k": @"v" }
	};
	UDProcessInstance *instance = [engine.runtimeService startProcessInstanceByKey:@"approval"
	                                                                     variables:values
	                                                                         error:&error];
	NSDictionary *stored = [engine.runtimeService
		variablesForProcessInstance:instance.processInstanceId error:&error];
	XCTAssertEqualObjects(stored, values);
	XCTAssertNil([engine.runtimeService startProcessInstanceByKey:@"approval"
	                                                    variables:@{ @"who": [NSObject new] }
	                                                        error:&error]);
	XCTAssertEqual([error code], (NSInteger)UDWorkflowErrorInvalidState);
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

#pragma mark - Deployment

- (void)testDeploymentsAreVersioned
{
	NSError *error = nil;
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"booked": @YES } forKey:@"book"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	UDRepositoryService *repository = engine.repositoryService;
	UDDeployment *first = [repository deployDefinition:[self approvalDefinition] error:&error];
	XCTAssertEqual([[first.definitions lastObject] version], (NSInteger)1);
	NSString *running = [engine.runtimeService startProcessInstanceByKey:@"approval"
	                                                           variables:nil error:&error].processInstanceId;
	UDDeployment *again = [repository deployDefinition:[self approvalDefinition] error:&error];
	XCTAssertEqualObjects(again.deploymentId, first.deploymentId);

	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"approval"];
	[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"] addEnd:@"end"];
	[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"end"];
	UDDeployment *second = [repository deployDefinition:[b build:&error] error:&error];
	XCTAssertEqual([[second.definitions lastObject] version], (NSInteger)2);

	/* The instance started on version 1 finishes on version 1: it still
	 * reaches the booking service, which version 2 no longer has. */
	[self complete:@"approve" of:running engine:engine variables:nil];
	XCTAssertTrue([self ended:running engine:engine]);
	XCTAssertEqualObjects([[self variables:running engine:engine] objectForKey:@"booked"], @YES);
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:running] definitionId],
		[[first.definitions lastObject] definitionId]);
}

- (void)testBrokenDeploymentStoresNothing
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *xml =
		@"<definitions xmlns=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" id=\"d\">"
		 @"<process id=\"calls\" isExecutable=\"true\">"
		 @"<startEvent id=\"s\"/><callActivity id=\"other\" calledElement=\"x\"/><endEvent id=\"e\"/>"
		 @"<sequenceFlow id=\"f1\" sourceRef=\"s\" targetRef=\"other\"/>"
		 @"<sequenceFlow id=\"f2\" sourceRef=\"other\" targetRef=\"e\"/>"
		 @"</process></definitions>";
	XCTAssertNil([engine.repositoryService
		deployResources:@{ @"calls.bpmn": [xml dataUsingEncoding:NSUTF8StringEncoding] }
		           name:@"calls"
		filterDuplicates:YES
		          error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"callActivity"].location
		!= NSNotFound, @"%@", error);
	XCTAssertNil([engine.repositoryService latestDefinitionForKey:@"calls" error:NULL]);
}

#pragma mark - Durability

- (void)testUserTaskSurvivesRestart
{
	NSError *error = nil;
	NSURL *url = [self temporarySQLiteURL];
	NSString *pid = nil;
	@autoreleasepool {
		UDProcessEngine *first = [self SQLiteEngineAtURL:url handler:nil];
		[self deploy:[self approvalDefinition] engine:first];
		pid = [first.runtimeService startProcessInstanceByKey:@"approval"
		                                            variables:@{ @"amount": @2500 }
		                                                error:&error].processInstanceId;
		XCTAssertNotNil(pid, @"%@", error);
		[first close];
	}
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"booked": @YES } forKey:@"book"];
	/* Nothing deployed: the definition comes back from the store. */
	UDProcessEngine *second = [self SQLiteEngineAtURL:url handler:h];
	XCTAssertTrue([second openWithError:&error], @"%@", error);
	XCTAssertEqualObjects([[second.runtimeService variablesForProcessInstance:pid error:&error]
		objectForKey:@"amount"], @2500);
	[self complete:@"approve" of:pid engine:second variables:@{ @"approved": @YES }];
	XCTAssertTrue([self ended:pid engine:second]);
	XCTAssertEqualObjects([[self variables:pid engine:second] objectForKey:@"booked"], @YES);
	[second close];
}

- (void)testExternalTaskIsOfferedAgainAfterRestart
{
	NSError *error = nil;
	NSURL *url = [self temporarySQLiteURL];
	NSString *pid = nil;
	NSString *taskId = nil;
	@autoreleasepool {
		UDMapHandler *dropping = [[UDMapHandler alloc] init];
		dropping.drops = YES;
		UDProcessEngine *first = [self SQLiteEngineAtURL:url handler:dropping];
		[self deploy:[self approvalDefinition] engine:first];
		pid = [first.runtimeService startProcessInstanceByKey:@"approval"
		                                            variables:nil error:&error].processInstanceId;
		UDWorkItem *approve = [self task:@"approve" of:pid engine:first];
		XCTAssertTrue([first.taskService completeTask:approve.taskId variables:nil error:&error]);
		/* The call went out, and the process "died" before answering. */
		XCTAssertFalse([first waitUntilSettled:pid timeout:0.2]);
		@synchronized (dropping) {
			taskId = [dropping.taskIds lastObject];
		}
		XCTAssertNotNil(taskId);
		[first close];
	}
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.results setObject:@{ @"booked": @YES } forKey:@"book"];
	UDProcessEngine *second = [self SQLiteEngineAtURL:url handler:h];
	/* Same identifier on the same host: the engine takes its lock back. */
	XCTAssertTrue([second openWithError:&error], @"%@", error);
	XCTAssertTrue([second waitUntilSettled:pid timeout:10.0]);
	XCTAssertTrue([self ended:pid engine:second]);
	XCTAssertEqualObjects(h.taskIds, @[ taskId ]);
	[second close];
}

- (void)testTimerKeepsItsDueTimeAcrossRestart
{
	NSError *error = nil;
	NSURL *url = [self temporarySQLiteURL];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"sleepy"];
	[[[b addStart:@"start"] addTimerCatch:@"nap" duration:1.0] addEnd:@"end"];
	[[b connect:@"start" to:@"nap"] connect:@"nap" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	NSString *pid = nil;
	NSDate *due = nil;
	@autoreleasepool {
		UDProcessEngine *first = [self SQLiteEngineAtURL:url handler:nil];
		[self deploy:def engine:first];
		pid = [first.runtimeService startProcessInstanceByKey:@"sleepy"
		                                            variables:nil error:&error].processInstanceId;
		due = [[[self rows:@"UDJob" engine:first] lastObject] objectForKey:@"dueDate"];
		XCTAssertNotNil(due);
		[first close];
	}
	[NSThread sleepForTimeInterval:0.5];
	UDProcessEngine *second = [self SQLiteEngineAtURL:url handler:nil];
	XCTAssertTrue([second openWithError:&error], @"%@", error);
	XCTAssertTrue([self waitForEnd:pid engine:second seconds:5.0]);
	/* Fired at the stored due time, not a full duration after the restart. */
	XCTAssertLessThan([[NSDate date] timeIntervalSinceDate:due], 0.9);
	[second close];
}

- (void)testDelegateMayCallBackIntoTheEngine
{
	NSError *error = nil;
	UDMapHandler *h = [[UDMapHandler alloc] init];
	UDProcessEngine *engine = [self engineWithHandler:h];
	UDCompletingDelegate *delegate = [[UDCompletingDelegate alloc] init];
	engine.delegate = delegate;
	[self deploy:[self approvalDefinition] engine:engine];
	NSString *pid = [engine.runtimeService startProcessInstanceByKey:@"approval"
	                                                        variables:nil error:&error].processInstanceId;
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
	while ([deadline timeIntervalSinceNow] > 0) {
		@synchronized (delegate) {
			if ([delegate.ended containsObject:pid]) {
				break;
			}
		}
		[NSThread sleepForTimeInterval:0.02];
	}
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"byDelegate"], @YES);
}

#pragma mark - Jobs

- (void)testAsyncBeforeWaitsForItsJob
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"later"];
	[[[b addStart:@"start"] addServiceTask:@"book" action:@"book"] addEnd:@"end"];
	[[b connect:@"start" to:@"book"] connect:@"book" to:@"end"];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"book"];
	UDMapHandler *h = [[UDMapHandler alloc] init];
	UDProcessEngine *engine = [self engineWithHandler:h];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	/* The start command stopped before the task: no call yet, one job. */
	XCTAssertEqual([h calls], (NSUInteger)0);
	NSArray *jobs = [engine.managementService jobsForProcessInstance:pid];
	XCTAssertEqual([jobs count], (NSUInteger)1);
	UDJob *job = [jobs lastObject];
	XCTAssertEqualObjects(job.jobType, UDJobTypeAsyncBeforeName);
	XCTAssertEqualObjects(job.activityId, @"book");
	XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:pid timeout:10.0]);
	XCTAssertEqual([h calls], (NSUInteger)1);
	XCTAssertTrue([self ended:pid engine:engine]);
}

- (void)testAsyncAfterWaitsForItsJob
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"thenLater"];
	[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"] addEnd:@"end"];
	[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"end"];
	[b setAsyncBefore:NO asyncAfter:YES exclusive:YES forElement:@"approve"];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	[self complete:@"approve" of:pid engine:engine variables:@{ @"ok": @YES }];
	/* The task is done and its variables committed; leaving waits. */
	XCTAssertFalse([self ended:pid engine:engine]);
	XCTAssertNil([self task:@"approve" of:pid engine:engine]);
	UDJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(job.jobType, UDJobTypeAsyncAfterName);
	XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"ok"], @YES);
}

/* An exclusive gateway behind an async continuation, with no default: it
 * fails until "amount" is set. */
- (UDProcessDefinition *)fragileDefinition:(NSString *)cycle
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"fragile"];
	[[[[b addStart:@"start"] addExclusive:@"route" defaultFlow:nil] addEnd:@"big"] addEnd:@"small"];
	[b connect:@"start" to:@"route"];
	[b connect:@"route" to:@"big" key:@"amount" op:UDComparisonOpGreater value:@100];
	[b connect:@"route" to:@"small" key:@"amount" op:UDComparisonOpLessOrEqual value:@100];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"route"];
	if (cycle != nil) {
		[b setRetryTimeCycle:cycle forElement:@"route"];
	}
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testFailingJobRaisesAnIncidentUntilFixed
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self fragileDefinition:nil] engine:engine variables:nil];
	UDManagementService *management = engine.managementService;
	NSString *jobId = [[[management jobsForProcessInstance:pid] lastObject] jobId];
	for (NSInteger left = 2; left >= 0; left--) {
		XCTAssertFalse([management executeJob:jobId error:&error]);
		XCTAssertEqual([error code], (NSInteger)UDWorkflowErrorNoPath);
		XCTAssertEqual([[management jobWithId:jobId] retries], left);
	}
	UDIncident *incident = [[management incidentsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(incident.incidentType, UDIncidentTypeFailedJobName);
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
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self fragileDefinition:@"R4/PT10M"] engine:engine variables:nil];
	UDJob *job = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqual(job.retries, (NSInteger)5, @"the first attempt and four retries");
	XCTAssertFalse([engine.managementService executeJob:job.jobId error:&error]);
	UDJob *after = [engine.managementService jobWithId:job.jobId];
	XCTAssertEqual(after.retries, (NSInteger)4);
	XCTAssertEqualWithAccuracy([after.dueDate timeIntervalSinceNow], 600.0, 5.0);
}

- (void)testJobExecutorRetriesByItself
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
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

- (void)testConcurrentCompletionsJoinOnce
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"race"];
	[[[[b addStart:@"start"] addParallel:@"fork"]
		addUserTask:@"left" name:@"Left" assignee:@"a"] addUserTask:@"right" name:@"Right" assignee:@"b"];
	[[[b addParallel:@"join"] addUserTask:@"after" name:@"After" assignee:@"c"] addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"left"] connect:@"fork" to:@"right"];
	[[b connect:@"left" to:@"join"] connect:@"right" to:@"join"];
	[[b connect:@"join" to:@"after"] connect:@"after" to:@"end"];
	UDProcessDefinition *definition = [b build:&error];
	UDProcessEngine *engine = [self SQLiteEngineAtURL:[self temporarySQLiteURL] handler:nil];
	[self deploy:definition engine:engine];
	__block NSUInteger conflicts = 0;
	for (int round = 0; round < 20; round++) {
		NSString *pid = [engine.runtimeService startProcessInstanceByKey:@"race"
		                                                        variables:nil error:&error].processInstanceId;
		NSArray *tasks = [engine.taskService tasksForProcessInstance:pid];
		XCTAssertEqual([tasks count], (NSUInteger)2);
		dispatch_group_t group = dispatch_group_create();
		for (UDWorkItem *task in tasks) {
			dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				NSError *completeError = nil;
				/* A lost race changed nothing: the caller tries again. */
				while (![engine.taskService completeTask:task.taskId variables:nil error:&completeError]) {
					if ([completeError code] != UDWorkflowErrorConflict) {
						break;
					}
					@synchronized (self) {
						conflicts += 1;
					}
				}
			});
		}
		dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
		UDDispatchRelease(group);
		/* The join fired exactly once. */
		XCTAssertEqualObjects([[engine.taskService tasksForProcessInstance:pid]
			valueForKey:@"taskDefinitionKey"], @[ @"after" ], @"round %d", round);
	}
	NSLog(@"conflicts resolved by retrying: %lu", (unsigned long)conflicts);
}

#pragma mark - BPMN

- (void)assertNode:(UDFlowNode *)a matches:(UDFlowNode *)b
{
	XCTAssertEqualObjects(NSStringFromClass([a class]), NSStringFromClass([b class]), @"%@", a.elementId);
	XCTAssertEqualObjects(a.name, b.name, @"%@", a.elementId);
	XCTAssertEqualObjects([NSSet setWithArray:a.incomingFlowIds],
		[NSSet setWithArray:b.incomingFlowIds], @"%@", a.elementId);
	XCTAssertEqualObjects([NSSet setWithArray:a.outgoingFlowIds],
		[NSSet setWithArray:b.outgoingFlowIds], @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsX, b.boundsX, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsY, b.boundsY, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsWidth, b.boundsWidth, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsHeight, b.boundsHeight, 0.001, @"%@", a.elementId);
	XCTAssertEqual(a.isAsyncBefore, b.isAsyncBefore, @"%@", a.elementId);
	XCTAssertEqual(a.isAsyncAfter, b.isAsyncAfter, @"%@", a.elementId);
	XCTAssertEqual(a.isExclusive, b.isExclusive, @"%@", a.elementId);
	XCTAssertEqualObjects(a.retryTimeCycle, b.retryTimeCycle, @"%@", a.elementId);
	if ([a isKindOfClass:[UDEvent class]]) {
		UDEvent *x = (UDEvent *)a, *y = (UDEvent *)b;
		XCTAssertEqual(x.kind, y.kind, @"%@", a.elementId);
		XCTAssertEqual(x.trigger, y.trigger, @"%@", a.elementId);
		if (x.trigger == UDEventTriggerMessage) {
			XCTAssertEqualObjects(x.messageName, y.messageName, @"%@", a.elementId);
		}
		if (x.trigger == UDEventTriggerError) {
			XCTAssertEqualObjects(x.errorRef, y.errorRef, @"%@", a.elementId);
		}
		XCTAssertEqualWithAccuracy(x.timerDuration, y.timerDuration, 0.001, @"%@", a.elementId);
		XCTAssertEqualObjects(x.attachedToId, y.attachedToId, @"%@", a.elementId);
		if (x.kind == UDEventKindBoundary) {
			XCTAssertEqual(x.isInterrupting, y.isInterrupting, @"%@", a.elementId);
		}
	} else if ([a isKindOfClass:[UDTask class]]) {
		UDTask *x = (UDTask *)a, *y = (UDTask *)b;
		XCTAssertEqual(x.kind, y.kind, @"%@", a.elementId);
		XCTAssertEqualObjects(x.assignee, y.assignee, @"%@", a.elementId);
		if (x.kind != UDTaskKindUser) {
			XCTAssertEqualObjects(x.actionKey, y.actionKey, @"%@", a.elementId);
		}
	} else if ([a isKindOfClass:[UDGateway class]]) {
		XCTAssertEqual([(UDGateway *)a kind], [(UDGateway *)b kind], @"%@", a.elementId);
		XCTAssertEqualObjects([(UDGateway *)a defaultFlowId], [(UDGateway *)b defaultFlowId],
			@"%@", a.elementId);
	} else if ([a isKindOfClass:[UDSubProcess class]]) {
		[self assertDefinition:[(UDSubProcess *)a innerDefinition]
		               matches:[(UDSubProcess *)b innerDefinition]];
	}
}

- (void)assertDefinition:(UDProcessDefinition *)a matches:(UDProcessDefinition *)b
{
	XCTAssertEqualObjects(a.processId, b.processId);
	XCTAssertEqualObjects(a.name, b.name);
	XCTAssertEqualObjects([NSSet setWithArray:[a.nodes allKeys]],
		[NSSet setWithArray:[b.nodes allKeys]]);
	XCTAssertEqualObjects([NSSet setWithArray:[a.flows allKeys]],
		[NSSet setWithArray:[b.flows allKeys]]);
	for (NSString *nodeId in a.nodes) {
		UDFlowNode *other = [b nodeWithId:nodeId];
		if (other != nil) {
			[self assertNode:[a nodeWithId:nodeId] matches:other];
		}
	}
	for (NSString *flowId in a.flows) {
		UDSequenceFlow *x = [a flowWithId:flowId];
		UDSequenceFlow *y = [b flowWithId:flowId];
		XCTAssertEqualObjects(x.sourceId, y.sourceId, @"%@", flowId);
		XCTAssertEqualObjects(x.targetId, y.targetId, @"%@", flowId);
		XCTAssertEqualObjects(x.name, y.name, @"%@", flowId);
		XCTAssertEqualObjects([x.condition expressionString], [y.condition expressionString],
			@"%@", flowId);
	}
}

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
	     condition:[UDComparisonCondition key:@"urgent" equals:@YES]];
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
	[[b connect:@"start" to:@"fill"] connect:@"fill" to:@"split"];
	[[b connect:@"split" to:@"check"] connect:@"split" to:@"audit"];
	[[b connect:@"check" to:@"join"] connect:@"audit" to:@"join"];
	[b connect:@"join" to:@"choice"];
	[b connect:@"choice" to:@"milestone" key:@"amount" op:UDComparisonOpLessOrEqual value:@1000];
	[b connect:@"choice" to:@"manual" flowId:@"toManual"];
	[[b connect:@"milestone" to:@"race"] connect:@"manual" to:@"race"];
	[[b connect:@"race" to:@"paid"] connect:@"race" to:@"timeout"];
	[[b connect:@"paid" to:@"notify"] connect:@"notify" to:@"done"];
	[b connect:@"timeout" to:@"late"];
	[[[b connect:@"onBad" to:@"badCredit"] connect:@"onAny" to:@"anyError"]
		connect:@"onCancel" to:@"cancelled"];
	[b setName:@"Request received" forElement:@"start"];
	[b setName:@"needs review" forElement:@"toManual"];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"check"];
	[b setAsyncBefore:NO asyncAfter:YES exclusive:NO forElement:@"audit"];
	[b setRetryTimeCycle:@"R5/PT5M" forElement:@"check"];
	[b setRetryTimeCycle:@"PT1M,PT10M" forElement:@"timeout"];
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

- (void)testFeelComparisons
{
	NSError *error = nil;
	UDComparisonCondition *c =
		[UDComparisonCondition conditionWithExpression:@"amount > 10" error:&error];
	XCTAssertNotNil(c, @"%@", error);
	XCTAssertTrue([c evaluateWithVariables:@{ @"amount": @11 } error:NULL]);
	XCTAssertFalse([c evaluateWithVariables:@{ @"amount": @3 } error:NULL]);
	XCTAssertEqualObjects([c expressionString], @"amount > 10");

	UDComparisonCondition *approved =
		[UDComparisonCondition conditionWithExpression:@"approved = true" error:&error];
	XCTAssertTrue([approved evaluateWithVariables:@{ @"approved": @YES } error:NULL]);
	XCTAssertEqualObjects([approved expressionString], @"approved = true");
	XCTAssertEqualObjects([[UDComparisonCondition key:@"name" equals:@"x"] expressionString],
		@"name = \"x\"");
}

@end

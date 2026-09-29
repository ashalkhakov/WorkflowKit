#import "UDWorkflowTestCase.h"

@interface UDSubprocessTests : UDWorkflowTestCase
@end

@implementation UDSubprocessTests

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

#pragma mark - Priorities, gateways and boundaries

/* A subprocess holding one task, with boundaries on the subprocess. */
- (UDProcessDefinition *)guardedSubprocess:(NSString *)innerKind
                                  boundary:(void (^)(UDDefinitionBuilder *b))boundary
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"stage"];
	if ([innerKind isEqualToString:@"service"]) {
		[[[inner addStart:@"s"] addServiceTask:@"step" action:@"step"] addEnd:@"e"];
	} else {
		[[[inner addStart:@"s"] addUserTask:@"step" name:@"Step" assignee:@"ann"] addEnd:@"e"];
	}
	[[inner connect:@"s" to:@"step"] connect:@"step" to:@"e"];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"guarded"];
	[[[[b addStart:@"start"] addSubProcess:@"sub" name:@"Stage" inner:[inner build:&error]]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[b addUserTask:@"handle" name:@"Handle" assignee:@"ops"] addEnd:@"handled"];
	[[[b connect:@"start" to:@"sub"] connect:@"sub" to:@"after"] connect:@"after" to:@"end"];
	[b connect:@"handle" to:@"handled"];
	boundary(b);
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)testErrorInsideASubprocessIsCaughtOnTheSubprocess
{
	UDMapHandler *h = [[UDMapHandler alloc] init];
	[h.bpmnErrors setObject:@"STOP" forKey:@"step"];
	UDProcessEngine *engine = [self engineWithHandler:h];
	NSString *pid = [self run:[self guardedSubprocess:@"service" boundary:^(UDDefinitionBuilder *b) {
		[b addBoundaryError:@"stopped" onTask:@"sub" errorRef:@"STOP" interrupting:YES];
		[b connect:@"stopped" to:@"handle"];
	}] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"handle" ]);
	UDHistoricActivityInstance *sub = nil;
	for (UDHistoricActivityInstance *activity in
	     [engine.historyService historicActivityInstancesForProcessInstance:pid]) {
		if ([activity.activityId isEqualToString:@"sub"]) {
			sub = activity;
		}
	}
	XCTAssertTrue(sub.canceled);
}

- (void)testTimerOnASubprocessInterruptsIt
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *pid = [self run:[self guardedSubprocess:@"user" boundary:^(UDDefinitionBuilder *b) {
		[b addBoundaryTimer:@"late" onTask:@"sub" duration:3600 interrupting:YES];
		[b connect:@"late" to:@"handle"];
	}] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"step" ]);
	UDJob *timer = [[engine.managementService jobsForProcessInstance:pid] lastObject];
	XCTAssertEqualObjects(timer.activityId, @"late");
	XCTAssertTrue([engine.managementService executeJob:timer.jobId error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"handle" ]);
	XCTAssertNil([self task:@"step" of:pid engine:engine]);
}

- (void)testNonInterruptingMessageOnASubprocess
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self guardedSubprocess:@"user" boundary:^(UDDefinitionBuilder *b) {
		[b addBoundaryMessage:@"poked" onTask:@"sub" message:@"poke" interrupting:NO];
		[b connect:@"poked" to:@"handle"];
	}] engine:engine variables:nil];
	XCTAssertTrue([engine.runtimeService correlateMessage:@"poke" processInstanceId:pid
	                                            variables:nil error:&error], @"%@", error);
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"handle", @"step" ]));
	[self complete:@"step" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"after", @"handle" ]));
	/* Left behind: the subprocess is over, its message boundary with it. */
	XCTAssertFalse([engine.runtimeService correlateMessage:@"poke" processInstanceId:pid
	                                             variables:nil error:&error]);
}

@end

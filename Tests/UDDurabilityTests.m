#import "UDWorkflowTestCase.h"

@interface UDDurabilityTests : UDWorkflowTestCase
@end

@implementation UDDurabilityTests

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

@end

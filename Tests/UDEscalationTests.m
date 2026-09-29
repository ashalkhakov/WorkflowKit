#import "UDWorkflowTestCase.h"

@interface UDEscalationTests : UDWorkflowTestCase
@end

@implementation UDEscalationTests

/* start -> sub -> after -> end; inside sub: s -> [inside sub] -> e, and
 * catch adds what catches. */
- (UDProcessDefinition *)outer:(void (^)(UDDefinitionBuilder *inner))inside
                         catch:(void (^)(UDDefinitionBuilder *b))catch
{
	NSError *error = nil;
	UDDefinitionBuilder *inner = [UDDefinitionBuilder process:@"sub"];
	inside(inner);
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"outer"];
	[[[[b addStart:@"start"] addSubProcess:@"sub" name:@"Sub" inner:[inner build:&error]]
		addUserTask:@"after" name:@"After" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"sub"] connect:@"sub" to:@"after"] connect:@"after" to:@"end"];
	catch(b);
	UDProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

/* Inside: throws escalation code, then waits in a user task "inside". */
- (void (^)(UDDefinitionBuilder *))throwThenWait:(NSString *)code
{
	return ^(UDDefinitionBuilder *inner) {
		[[[[inner addStart:@"s"] addEscalationThrow:@"raise" code:code]
			addUserTask:@"inside" name:@"Inside" assignee:@"ann"] addEnd:@"e"];
		[[[inner connect:@"s" to:@"raise"] connect:@"raise" to:@"inside"] connect:@"inside" to:@"e"];
	};
}

- (void)testANonInterruptingCatchLetsTheThrowerGoOn
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self outer:[self throwThenWait:@"LATE"] catch:^(UDDefinitionBuilder *b) {
		[[b addBoundaryEscalation:@"late" onTask:@"sub" code:@"LATE" interrupting:NO]
			addUserTask:@"notify" name:@"Notify" assignee:@"boss"];
		[b setCodeVariable:@"escalation" forElement:@"late"];
		[b addEnd:@"notified"];
		[[b connect:@"late" to:@"notify"] connect:@"notify" to:@"notified"];
	}] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"inside", @"notify" ]));
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"escalation"], @"LATE");
}

- (void)testAnInterruptingCatchCancelsTheSubprocess
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self outer:^(UDDefinitionBuilder *inner) {
		[[[inner addStart:@"s"] addUserTask:@"inside" name:@"Inside" assignee:@"ann"]
			addEscalationEnd:@"giveUp" code:@"GIVE_UP"];
		[[inner connect:@"s" to:@"inside"] connect:@"inside" to:@"giveUp"];
	} catch:^(UDDefinitionBuilder *b) {
		/* A catch-all. */
		[[b addBoundaryEscalation:@"escalated" onTask:@"sub" code:nil interrupting:YES]
			addUserTask:@"handled" name:@"Handled" assignee:@"boss"];
		[b addEnd:@"handledEnd"];
		[[b connect:@"escalated" to:@"handled"] connect:@"handled" to:@"handledEnd"];
	}] engine:engine variables:nil];
	[self complete:@"inside" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"handled" ]);
}

- (void)testAnUncaughtEscalationIsNotAnError
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self outer:[self throwThenWait:@"NOBODY"] catch:^(UDDefinitionBuilder *b) {
		[[b addBoundaryEscalation:@"other" onTask:@"sub" code:@"OTHER" interrupting:YES] addEnd:@"otherEnd"];
		[b connect:@"other" to:@"otherEnd"];
	}] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"inside" ]);
}

- (void)testAnEventSubprocessBesideTheThrowingPath
{
	NSError *error = nil;
	UDDefinitionBuilder *handler = [UDDefinitionBuilder process:@"onLate"];
	[[[handler addEscalationStart:@"lateStart" code:@"LATE"] addUserTask:@"note" name:@"Note" assignee:@"boss"]
		addEnd:@"noted"];
	[[handler connect:@"lateStart" to:@"note"] connect:@"note" to:@"noted"];
	[handler setInterrupting:NO forElement:@"lateStart"];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"main"];
	[[[[b addStart:@"start"] addEscalationThrow:@"raise" code:@"LATE"]
		addUserTask:@"work" name:@"Work" assignee:@"ann"] addEnd:@"end"];
	[[[b connect:@"start" to:@"raise"] connect:@"raise" to:@"work"] connect:@"work" to:@"end"];
	[b addEventSubProcess:@"onLate" name:@"On late" inner:[handler build:&error]];
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"note", @"work" ]));
}

- (void)testAnEscalationOutOfACalledProcess
{
	NSError *error = nil;
	UDProcessEngine *engine = [self engineWithHandler:nil];
	UDDefinitionBuilder *c = [UDDefinitionBuilder process:@"child"];
	[self throwThenWait:@"HELP"](c);
	[self deploy:[c build:&error] engine:engine];
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"parent"];
	[[[b addStart:@"start"] addCallActivity:@"call" calledElement:@"child"] addEnd:@"end"];
	[[b connect:@"start" to:@"call"] connect:@"call" to:@"end"];
	[[b addBoundaryEscalation:@"help" onTask:@"call" code:@"HELP" interrupting:NO]
		addUserTask:@"assist" name:@"Assist" assignee:@"boss"];
	[b addEnd:@"assisted"];
	[[b connect:@"help" to:@"assist"] connect:@"assist" to:@"assisted"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], (@[ @"assist", @"call" ]));
	NSString *childId = [[[engine.runtimeService subProcessInstancesOf:pid error:NULL] lastObject]
		processInstanceId];
	XCTAssertEqualObjects([self active:childId engine:engine], @[ @"inside" ]);
}

- (void)testAnErrorEndEventIsCaughtLikeAnyError
{
	UDProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self outer:^(UDDefinitionBuilder *inner) {
		[[[inner addStart:@"s"] addUserTask:@"inside" name:@"Inside" assignee:@"ann"]
			addErrorEnd:@"fail" errorRef:@"REJECTED"];
		[[inner connect:@"s" to:@"inside"] connect:@"inside" to:@"fail"];
	} catch:^(UDDefinitionBuilder *b) {
		[[b addBoundaryError:@"rejected" onTask:@"sub" errorRef:@"REJECTED" interrupting:YES]
			addUserTask:@"rework" name:@"Rework" assignee:@"ann"];
		[b setCodeVariable:@"why" forElement:@"rejected"];
		[b addEnd:@"reworked"];
		[[b connect:@"rejected" to:@"rework"] connect:@"rework" to:@"reworked"];
	}] engine:engine variables:nil];
	[self complete:@"inside" of:pid engine:engine variables:nil];
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"rework" ]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"why"], @"REJECTED");
}

@end

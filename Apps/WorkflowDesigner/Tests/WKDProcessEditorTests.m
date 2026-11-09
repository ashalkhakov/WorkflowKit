#import <XCTest/XCTest.h>
#import "WKDProcessEditor.h"
#import "WKDFixtures.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

/* What the designer's parts share: the process, the selection that follows
 * its changes, and what the engine finds wrong with it. */
@interface WKDProcessEditorTests : XCTestCase
@end

@implementation WKDProcessEditorTests

- (WKDProcessEditor *)modeller
{
	NSError *error = nil;
	WKDProcessEditor *editor = [[WKDProcessEditor alloc] initWithData:[WKDModellerFile dataUsingEncoding:NSUTF8StringEncoding]
	                                                      undoManager:nil error:&error];
	XCTAssertNotNil(editor, @"%@", error);
	return editor;
}

- (void)testTheTextIsReadAndWrittenBack
{
	WKDProcessEditor *editor = [self modeller];
	XCTAssertFalse(editor.laidOut, @"it has its diagram");
	WKDProcessEditor *again = [[WKDProcessEditor alloc] initWithData:[editor data] undoManager:nil error:NULL];
	XCTAssertNotNil([again.editor.model nodeWithId:@"review"]);
	NSError *error = nil;
	XCTAssertNil([[WKDProcessEditor alloc] initWithData:[@"<notBpmn/>" dataUsingEncoding:NSUTF8StringEncoding]
	                                        undoManager:nil error:&error]);
	XCTAssertNotNil(error);
	WKDProcessEditor *fresh = [[WKDProcessEditor alloc] initNewProcessWithUndoManager:nil];
	XCTAssertEqual([fresh.editor.model.nodes count], (NSUInteger)1, @"a start event");
}

- (void)testTheSelectionFollowsTheProcess
{
	WKDProcessEditor *editor = [self modeller];
	__block NSUInteger selections = 0, changes = 0;
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	id selected = [center addObserverForName:WKDSelectionDidChangeNotification object:editor.selection queue:nil
	                              usingBlock:^(NSNotification *note) { selections++; }];
	id changed = [center addObserverForName:WKDProcessEditorDidChangeNotification object:editor queue:nil
	                             usingBlock:^(NSNotification *note) { changes++; }];
	editor.selection.selectedIds = @[ @"review", @"ok" ];
	XCTAssertEqualObjects(editor.selection.selectedId, @"review");
	editor.selection.selectedIds = @[ @"review", @"ok" ];
	XCTAssertEqual(selections, (NSUInteger)1, @"the same again is no change");
	[editor.editor deleteElements:@[ @"review" ]];
	XCTAssertEqualObjects(editor.selection.selectedIds, @[ @"ok" ], @"what went is not selected");
	XCTAssertEqual(selections, (NSUInteger)2);
	XCTAssertEqual(changes, (NSUInteger)1);
	[center removeObserver:selected];
	[center removeObserver:changed];
}

- (void)testTheEnginesProblemsAreCheckedWithWhatIsBeside
{
	WKDProcessEditor *editor = [self modeller];
	editor.fileName = @"order.bpmn";
	[editor checkNow];
	NSArray *before = editor.problems;
	__block NSUInteger told = 0;
	id observer = [[NSNotificationCenter defaultCenter] addObserverForName:WKDProcessEditorProblemsDidChangeNotification
	                                                                object:editor queue:nil
	                                                            usingBlock:^(NSNotification *note) { told++; }];
	/* review's outgoing flow gone: it ends nowhere. */
	[editor.editor deleteElements:@[ @"f2" ]];
	[editor checkNow];
	XCTAssertGreaterThan([editor.problems count], [before count], @"%@", editor.problems);
	XCTAssertTrue([[editor.problems valueForKey:@"elementId"] containsObject:@"review"], @"%@", editor.problems);
	XCTAssertEqualObjects([[editor.problems firstObject] resourceName], @"order.bpmn");
	XCTAssertNotNil(editor.problem);
	XCTAssertEqual(told, (NSUInteger)1);
	[editor checkNow];
	XCTAssertEqual(told, (NSUInteger)1, @"the same problems are no news");
	[[NSNotificationCenter defaultCenter] removeObserver:observer];
}

@end

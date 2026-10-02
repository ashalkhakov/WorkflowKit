#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDXML.h"
#import "WKDFixtures.h"

/* Several shapes at once: lined up with the first selected, spread out,
 * nudged. */
@interface WKDAlignmentTests : XCTestCase
@end

@implementation WKDAlignmentTests

- (WKDEditor *)modeller
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
}

static NSRect
WKDBounds(WKDEditor *editor, NSString *elementId)
{
	return [editor.diagram shapeWithId:elementId].bounds;
}

- (void)testShapesLineUpWithTheFirst
{
	WKDEditor *editor = [self modeller];
	/* refused is at x 367, review -- the anchor -- at 200. */
	NSArray *leftward = @[ @"review", @"refused" ];
	XCTAssertTrue([editor alignElements:leftward to:WKDAlignLeft]);
	XCTAssertEqual(NSMinX(WKDBounds(editor, @"refused")), 200.0);
	XCTAssertEqual(NSMinX(WKDBounds(editor, @"review")), 200.0, @"the anchor stays");
	XCTAssertEqual(NSMinY(WKDBounds(editor, @"refused")), 230.0, @"only across");

	NSArray *level = @[ @"ok", @"done", @"chased" ];
	XCTAssertTrue([editor alignElements:level to:WKDAlignMiddle]);
	XCTAssertEqual(NSMidY(WKDBounds(editor, @"chased")), NSMidY(WKDBounds(editor, @"ok")));
	XCTAssertEqual(NSMidY(WKDBounds(editor, @"done")), NSMidY(WKDBounds(editor, @"ok")));
	NSArray *rightward = @[ @"done", @"refused" ];
	XCTAssertTrue([editor alignElements:rightward to:WKDAlignRight]);
	XCTAssertEqual(NSMaxX(WKDBounds(editor, @"refused")), NSMaxX(WKDBounds(editor, @"done")));
}

- (void)testWhatAShapeCarriesIsNotArrangedOnItsOwn
{
	WKDEditor *editor = [self modeller];
	NSRect pack = WKDBounds(editor, @"pack");
	NSArray *carried = @[ @"ship", @"pack" ];
	XCTAssertFalse([editor alignElements:carried to:WKDAlignTop],
	               @"pack is inside ship: one shape is nothing to line up");
	NSArray *tops = @[ @"refused", @"ship", @"pack" ];
	XCTAssertTrue([editor alignElements:tops to:WKDAlignTop]);
	XCTAssertEqual(NSMinY(WKDBounds(editor, @"ship")), 230.0);
	XCTAssertEqual(NSMinY(WKDBounds(editor, @"pack")), NSMinY(pack) + 210, @"carried with ship");
}

- (void)testShapesAreSpreadOut
{
	WKDEditor *editor = [self modeller];
	/* start 100-136, review 200-300, ok 360-410: 310 across, 186 of it
	 * shapes, so gaps of 62. */
	NSArray *across = @[ @"ok", @"start", @"review" ];
	XCTAssertTrue([editor distributeElements:across vertically:NO]);
	XCTAssertEqual(NSMinX(WKDBounds(editor, @"start")), 100.0);
	XCTAssertEqual(NSMinX(WKDBounds(editor, @"review")), 198.0);
	XCTAssertEqual(NSMinX(WKDBounds(editor, @"ok")), 360.0);
	NSArray *two = @[ @"ok", @"start" ];
	XCTAssertFalse([editor distributeElements:two vertically:YES], @"two have one gap");
}

- (void)testNudgesInABurstAreOneStep
{
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:undo];
	NSRect start = WKDBounds(editor, @"review");
	[editor nudgeElements:@[ @"review" ] by:NSMakeSize(1, 0)];
	[editor nudgeElements:@[ @"review" ] by:NSMakeSize(1, 0)];
	[editor nudgeElements:@[ @"review" ] by:NSMakeSize(0, 10)];
	XCTAssertTrue(NSEqualRects(WKDBounds(editor, @"review"), NSOffsetRect(start, 2, 10)));
	XCTAssertTrue(NSEqualRects(WKDBounds(editor, @"late"), NSOffsetRect(NSMakeRect(232, 140, 36, 36), 2, 10)),
	              @"its boundary timer with it");
	[undo undo];
	XCTAssertTrue(NSEqualRects(WKDBounds(editor, @"review"), start), @"one undo for the burst");
}

@end

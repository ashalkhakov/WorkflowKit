#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDXML.h"
#import "WKDFixtures.h"
#if __has_include(<WorkflowKit/WFBpmn.h>)
#import <WorkflowKit/WFBpmn.h>
#else
#import "WFBpmn.h"
#endif

/* Pools and lanes: read, kept round their nodes as the nodes move, added,
 * resized, removed, and laid out. */
@interface WKDLanesTests : XCTestCase
@end

@implementation WKDLanesTests

- (WKDEditor *)team
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(WKDLanesFile) undoManager:nil];
}

/* The ids a lane lists, in order. */
static NSArray *
WKDRefs(WKDEditor *editor, NSString *laneId)
{
	return [editor.diagram laneWithId:laneId].flowNodeIds;
}

static NSRect
WKDBoundsOf(WKDEditor *editor, NSString *elementId)
{
	WKDShape *shape = [editor.diagram shapeWithId:elementId];
	return shape != nil ? shape.bounds : [editor.diagram laneWithId:elementId].bounds;
}

/* Whether the engine reads the document. */
static BOOL
WKDRuns(WKDEditor *editor, NSError **error)
{
	return [WFBpmnReader definitionFromXMLString:[editor.document XMLString] error:error] != nil;
}

- (void)testAPoolAndItsLanesAreRead
{
	WKDEditor *editor = [self team];
	WKDDiagram *diagram = editor.diagram;
	XCTAssertEqualObjects(diagram.pool.elementId, @"company");
	XCTAssertEqualObjects(diagram.pool.name, @"Company");
	XCTAssertTrue(diagram.pool.horizontal);
	XCTAssertTrue(NSEqualRects(diagram.pool.bounds, NSMakeRect(100, 80, 700, 300)));
	NSArray *lanes = [diagram.lanes valueForKey:@"elementId"];
	NSArray *expected = @[ @"hr", @"manager" ];
	XCTAssertEqualObjects(lanes, expected);
	XCTAssertEqualObjects([diagram.leafLanes valueForKey:@"elementId"], expected);
	XCTAssertEqualObjects([diagram laneOf:[diagram shapeWithId:@"approve"]].elementId, @"manager");
	XCTAssertEqualObjects([diagram.otherPools valueForKey:@"elementId"], @[ @"candidate" ]);
	XCTAssertTrue(NSContainsRect(diagram.contentBounds, NSMakeRect(100, 420, 700, 80)), @"pools are content");
	NSError *error = nil;
	XCTAssertTrue(WKDRuns(editor, &error), @"%@", error);
}

- (void)testANodeMovedIntoAnotherLaneChangesLanes
{
	WKDEditor *editor = [self team];
	[editor moveElements:@[ @"review" ] by:NSMakeSize(0, 150)];
	NSArray *hr = @[ @"start" ], *manager = @[ @"approve", @"done", @"review" ];
	XCTAssertEqualObjects(WKDRefs(editor, @"hr"), hr);
	XCTAssertEqualObjects(WKDRefs(editor, @"manager"), manager);
	/* Moved within its lane: listed where it was. */
	[editor moveElements:@[ @"start" ] by:NSMakeSize(20, 10)];
	XCTAssertEqualObjects(WKDRefs(editor, @"hr"), hr);
}

- (void)testThePoolGrowsRoundWhatIsMovedPastIt
{
	WKDEditor *editor = [self team];
	[editor moveElements:@[ @"done" ] by:NSMakeSize(200, 60)];
	NSRect pool = WKDBoundsOf(editor, @"company");
	XCTAssertTrue(NSMaxX(pool) >= 836 + 20, @"%@", NSStringFromRect(pool));
	XCTAssertTrue(NSMaxY(pool) >= 383 + 20, @"%@", NSStringFromRect(pool));
	XCTAssertEqual(NSMaxX(WKDBoundsOf(editor, @"hr")), NSMaxX(pool), @"its lanes across with it");
	XCTAssertEqual(NSMaxY(WKDBoundsOf(editor, @"manager")), NSMaxY(pool), @"its bottom lane down with it");
	XCTAssertEqual(NSMinY(WKDBoundsOf(editor, @"manager")), 230.0);
}

- (void)testALaneIsAddedBetweenTheOthers
{
	WKDEditor *editor = [self team];
	NSString *lane = [editor addLaneAfter:@"hr"];
	XCTAssertNotNil(lane);
	NSArray *order = @[ @"hr", lane, @"manager" ];
	XCTAssertEqualObjects([editor.diagram.lanes valueForKey:@"elementId"], order);
	XCTAssertTrue(NSEqualRects(WKDBoundsOf(editor, lane), NSMakeRect(130, 230, 670, 125)));
	XCTAssertEqual(NSMinY(WKDBoundsOf(editor, @"manager")), 355.0, @"moved down to make room");
	XCTAssertEqual(NSMinY(WKDBoundsOf(editor, @"approve")), 390.0, @"with what is in it");
	XCTAssertEqual(NSHeight(WKDBoundsOf(editor, @"company")), 425.0);
	XCTAssertEqual(NSHeight(WKDBoundsOf(editor, @"hr")), 150.0, @"the lane before is as it was");
	WKDConnection *f2 = [editor.diagram connectionWithId:@"f2"];
	XCTAssertEqual([[f2.waypoints lastObject] pointValue].y, 430.0, @"the flow's end with its node");
	XCTAssertEqual([[f2.waypoints firstObject] pointValue].y, 155.0, @"its start where it was");
	NSArray *manager = @[ @"approve", @"done" ];
	XCTAssertEqualObjects(WKDRefs(editor, @"manager"), manager, @"still the manager's");
	XCTAssertEqual(NSMinY(WKDBoundsOf(editor, @"candidate")), 545.0, @"another pool below moved down too");
	NSError *error = nil;
	XCTAssertTrue(WKDRuns(editor, &error), @"%@", error);
	NSString *last = [editor addLaneAfter:nil];
	XCTAssertEqualObjects([[editor.diagram.lanes lastObject] elementId], last, @"at the bottom of the pool");
}

- (void)testAProcessIsPutInAPoolAndGivenLanes
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
	XCTAssertNil(editor.diagram.pool);
	NSString *lane = [editor addLaneAfter:nil];
	WKDLane *pool = editor.diagram.pool;
	XCTAssertNotNil(pool, @"a pool first");
	XCTAssertEqual([editor.diagram.lanes count], (NSUInteger)2, @"a lane holding everything, then the new one");
	WKDLane *first = [editor.diagram.lanes firstObject];
	XCTAssertTrue([first.flowNodeIds containsObject:@"review"], @"%@", first.flowNodeIds);
	XCTAssertTrue([first.flowNodeIds containsObject:@"late"], @"boundary events too");
	XCTAssertFalse([first.flowNodeIds containsObject:@"pack"], @"not what a subprocess holds");
	XCTAssertEqualObjects([[editor.diagram.lanes lastObject] elementId], lane);
	XCTAssertEqual(NSMaxY(WKDBoundsOf(editor, lane)), NSMaxY(pool.bounds));
	NSString *xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"processRef=\"order\""].location != NSNotFound, @"%@", xml);
	NSError *error = nil;
	XCTAssertTrue(WKDRuns(editor, &error), @"%@", error);

	/* And taken out again: the plane shows the process. */
	[editor deleteElements:@[ pool.elementId ]];
	XCTAssertNil(editor.diagram.pool);
	XCTAssertEqual([editor.diagram.lanes count], (NSUInteger)0);
	xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"collaboration"].location == NSNotFound, @"%@", xml);
	XCTAssertTrue([xml rangeOfString:@"bpmnElement=\"order\""].location != NSNotFound);
	XCTAssertNotNil([editor.diagram shapeWithId:@"review"], @"the nodes stay");
}

- (void)testLanesAreResizedAndRemoved
{
	WKDEditor *editor = [self team];
	[editor resizeElement:@"hr" to:NSMakeRect(130, 80, 670, 200)];
	XCTAssertEqual(NSHeight(WKDBoundsOf(editor, @"hr")), 200.0);
	XCTAssertEqual(NSMinY(WKDBoundsOf(editor, @"manager")), 280.0);
	XCTAssertEqual(NSMinY(WKDBoundsOf(editor, @"done")), 337.0);
	XCTAssertEqual(NSHeight(WKDBoundsOf(editor, @"company")), 350.0);
	[editor resizeElement:@"hr" to:NSMakeRect(130, 80, 670, 10)];
	XCTAssertEqual(NSHeight(WKDBoundsOf(editor, @"hr")), 60.0, @"no shorter than a lane may be");
	[editor resizeElement:@"company" to:NSMakeRect(100, 80, 900, 210)];
	XCTAssertEqual(NSMaxX(WKDBoundsOf(editor, @"manager")), 1000.0, @"its lanes across with the pool");

	[editor deleteElements:@[ @"hr" ]];
	NSArray *one = @[ @"manager" ];
	XCTAssertEqualObjects([editor.diagram.lanes valueForKey:@"elementId"], one);
	XCTAssertEqual(NSMinY(WKDBoundsOf(editor, @"manager")), 80.0, @"the lane after takes its room");
	NSArray *everything = @[ @"approve", @"done", @"start", @"review" ];
	XCTAssertEqualObjects(WKDRefs(editor, @"manager"), everything, @"and what was in it");
	[editor deleteElements:@[ @"manager" ]];
	XCTAssertEqual([editor.diagram.lanes count], (NSUInteger)0);
	XCTAssertTrue([[editor.document XMLString] rangeOfString:@"laneSet"].location == NSNotFound);
	XCTAssertNotNil(editor.diagram.pool, @"the pool stays");
}

- (void)testThePoolIsMovedWithWhatItHolds
{
	WKDEditor *editor = [self team];
	[editor moveElements:@[ @"company" ] by:NSMakeSize(50, 20)];
	XCTAssertTrue(NSEqualRects(WKDBoundsOf(editor, @"company"), NSMakeRect(150, 100, 700, 300)));
	XCTAssertTrue(NSEqualRects(WKDBoundsOf(editor, @"manager"), NSMakeRect(180, 250, 670, 150)));
	XCTAssertTrue(NSEqualRects(WKDBoundsOf(editor, @"review"), NSMakeRect(310, 135, 100, 80)));
	WKDConnection *f2 = [editor.diagram connectionWithId:@"f2"];
	XCTAssertEqual([[f2.waypoints objectAtIndex:1] pointValue].x, 440.0, @"its bends with it");
	XCTAssertTrue(NSEqualRects(WKDBoundsOf(editor, @"candidate"), NSMakeRect(100, 420, 700, 80)),
	              @"not another's pool");
}

- (void)testANodeAddedOrRenamedIsListedByItsLane
{
	WKDEditor *editor = [self team];
	NSString *added = [editor insertNodeOfType:@"userTask" eventDefinition:nil at:NSMakePoint(700, 305) error:NULL];
	XCTAssertTrue([WKDRefs(editor, @"manager") containsObject:added]);
	XCTAssertTrue([editor renameElement:@"review" to:@"screen" error:NULL]);
	NSArray *hr = @[ @"start", @"screen" ];
	XCTAssertEqualObjects(WKDRefs(editor, @"hr"), hr);
	[editor deleteElements:@[ @"start" ]];
	XCTAssertEqualObjects(WKDRefs(editor, @"hr"), @[ @"screen" ]);
}

- (void)testArrangingKeepsEachNodeInItsLane
{
	WKDEditor *editor = [self team];
	[editor arrange];
	for (WKDShape *shape in editor.diagram.shapes) {
		WKDLane *lane = [editor.diagram laneOf:shape];
		XCTAssertNotNil(lane, @"%@", shape.elementId);
		XCTAssertTrue(NSPointInRect(NSMakePoint(NSMidX(shape.bounds), NSMidY(shape.bounds)), lane.bounds),
		              @"%@ in %@", shape, lane);
	}
	NSArray *hr = @[ @"start", @"review" ];
	XCTAssertEqualObjects(WKDRefs(editor, @"hr"), hr);
	NSRect top = WKDBoundsOf(editor, @"hr"), bottom = WKDBoundsOf(editor, @"manager");
	XCTAssertEqual(NSMaxY(top), NSMinY(bottom), @"stacked");
	XCTAssertTrue(NSContainsRect(WKDBoundsOf(editor, @"company"), NSUnionRect(top, bottom)));
	NSError *error = nil;
	XCTAssertTrue(WKDRuns(editor, &error), @"%@", error);
}

- (void)testUndoRestoresTheLanes
{
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDLanesFile) undoManager:undo];
	NSString *before = [editor.document XMLString];
	[editor addLaneAfter:@"hr"];
	[editor moveElements:@[ @"review" ] by:NSMakeSize(0, 300)];
	[undo undo];
	[undo undo];
	XCTAssertEqualObjects([editor.document XMLString], before);
}

@end

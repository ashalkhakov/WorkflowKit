#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDXML.h"
#import "WKDFixtures.h"

/* What the canvas changes directly: names typed in place, a flow's ends
 * moved to other nodes, its bends and labels, and the bends a flow keeps
 * when one of its ends moves. */
@interface WKDCanvasEditsTests : XCTestCase
@end

@implementation WKDCanvasEditsTests
{
	NSUndoManager *_undo;
}

- (void)setUp
{
	[super setUp];
	_undo = [[NSUndoManager alloc] init];
	[_undo setGroupsByEvent:NO];
}

/* Each change in a test that undoes goes in a -step:, as the run loop's
 * events would group it. */
- (WKDEditor *)modeller
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:_undo];
}

- (WKDEditor *)modellerWithoutUndo
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
}

- (void)step:(void (^)(void))change
{
	[_undo beginUndoGrouping];
	change();
	[_undo endUndoGrouping];
}

static NSArray *
WKDPoints(WKDConnection *connection)
{
	NSMutableArray *points = [NSMutableArray array];
	for (NSValue *value in connection.waypoints) {
		[points addObject:NSStringFromPoint([value pointValue])];
	}
	return points;
}

static NSArray *
WKDReferences(NSXMLElement *node, NSString *local)
{
	return [WKDChildren(node, WKDBpmnNamespace, local) valueForKey:@"stringValue"];
}

- (void)testANameIsTypedInPlace
{
	WKDEditor *editor = [self modeller];
	[self step:^{ [editor setName:@"  Check the order\n" of:@"review"]; }];
	XCTAssertEqualObjects([editor.diagram shapeWithId:@"review"].name, @"Check the order", @"trimmed");
	[self step:^{ [editor setName:@"" of:@"ok"]; }];
	XCTAssertNil(WKDAttribute([editor elementWithId:@"ok"], @"name"), @"no name rather than an empty one");
	[self step:^{ [editor setName:@"Call them" of:@"note"]; }];
	XCTAssertEqualObjects([editor.diagram shapeWithId:@"note"].name, @"Call them", @"an annotation's text");
	[self step:^{ [editor setName:@"fine" of:@"f3"]; }];
	XCTAssertEqualObjects([editor.diagram connectionWithId:@"f3"].name, @"fine");
	[_undo undo];
	[_undo undo];
	[_undo undo];
	[_undo undo];
	XCTAssertEqualObjects([editor.diagram shapeWithId:@"review"].name, @"Review", @"each one step");
}

- (void)testAFlowsEndIsMovedToAnotherNode
{
	WKDEditor *editor = [self modellerWithoutUndo];
	NSString *reason = nil;
	/* f4, the gateway's default, now ends at done. */
	XCTAssertTrue([editor reconnect:@"f4" atSource:NO to:@"done" error:&reason], @"%@", reason);
	XCTAssertEqualObjects(WKDAttribute([editor elementWithId:@"f4"], @"targetRef"), @"done");
	XCTAssertEqualObjects(WKDReferences([editor elementWithId:@"refused"], @"incoming"), @[]);
	XCTAssertEqualObjects(WKDReferences([editor elementWithId:@"done"], @"incoming"), (@[ @"f6", @"f4" ]));
	XCTAssertTrue([editor.diagram connectionWithId:@"f4"].isDefault, @"still the gateway's default");
	WKDConnection *f4 = [editor.diagram connectionWithId:@"f4"];
	XCTAssertTrue(NSPointInRect([[f4.waypoints lastObject] pointValue], NSInsetRect(f4.target.bounds, -1, -1)),
	              @"drawn to its new end: %@", WKDPoints(f4));

	/* Its start moved: the gateway it left keeps no default to it. */
	XCTAssertTrue([editor reconnect:@"f4" atSource:YES to:@"review" error:&reason], @"%@", reason);
	XCTAssertNil(WKDAttribute([editor elementWithId:@"ok"], @"default"));
	XCTAssertEqualObjects(WKDReferences([editor elementWithId:@"review"], @"outgoing"), (@[ @"f2", @"f4" ]));
	XCTAssertEqualObjects(WKDReferences([editor elementWithId:@"ok"], @"outgoing"), @[ @"f3" ]);

	/* By the rules a new flow keeps to. */
	XCTAssertFalse([editor reconnect:@"f1" atSource:NO to:@"start" error:&reason]);
	XCTAssertEqualObjects(reason, @"A flow cannot go back into the node it leaves.");
	XCTAssertFalse([editor reconnect:@"f2" atSource:NO to:@"late" error:&reason]);
	XCTAssertEqualObjects(reason, @"Nothing flows into a start or boundary event.");
	XCTAssertFalse([editor reconnect:@"s1" atSource:NO to:@"done" error:&reason]);
	XCTAssertEqualObjects(reason, @"A flow stays within its process or subprocess.");
}

- (void)testABendStaysWhenOneEndMoves
{
	WKDEditor *editor = [self modellerWithoutUndo];
	/* f5 goes down from the boundary timer, then across to chased. */
	XCTAssertEqualObjects(WKDPoints([editor.diagram connectionWithId:@"f5"]),
	                      (@[ NSStringFromPoint(NSMakePoint(250, 176)), NSStringFromPoint(NSMakePoint(250, 318)),
	                          NSStringFromPoint(NSMakePoint(300, 318)) ]));
	[editor moveElements:@[ @"chased" ] by:NSMakeSize(30, 40)];
	XCTAssertEqualObjects(WKDPoints([editor.diagram connectionWithId:@"f5"]),
	                      (@[ NSStringFromPoint(NSMakePoint(250, 176)), NSStringFromPoint(NSMakePoint(250, 358)),
	                          NSStringFromPoint(NSMakePoint(330, 358)) ]),
	                      @"the bend slides down with the end; the way down stays where it was");

	/* Where the bend would land inside the shape, the router draws it. */
	[editor moveElements:@[ @"chased" ] by:NSMakeSize(-110, 0)];
	WKDConnection *f5 = [editor.diagram connectionWithId:@"f5"];
	for (NSValue *value in [f5.waypoints subarrayWithRange:NSMakeRange(1, [f5.waypoints count] - 2)]) {
		XCTAssertFalse(NSPointInRect([value pointValue], NSInsetRect(f5.target.bounds, 1, 1)),
		               @"no bend inside chased: %@", WKDPoints(f5));
	}
}

- (void)testKeptRoutes
{
	NSArray *route = @[ [NSValue valueWithPoint:NSMakePoint(100, 50)], [NSValue valueWithPoint:NSMakePoint(150, 50)],
	                    [NSValue valueWithPoint:NSMakePoint(150, 200)], [NSValue valueWithPoint:NSMakePoint(200, 200)] ];
	NSRect source = NSMakeRect(0, 10, 100, 80), target = NSMakeRect(200, 180, 36, 36);
	NSArray *kept = [WKDEditor keptRoute:route source:NSOffsetRect(source, 0, 20) target:target
	                         sourceMoved:NSMakeSize(0, 20) targetMoved:NSZeroSize];
	NSArray *expected = @[ [NSValue valueWithPoint:NSMakePoint(100, 70)], [NSValue valueWithPoint:NSMakePoint(150, 70)],
	                       route[2], route[3] ];
	XCTAssertEqualObjects(kept, expected, @"the end and its bend down by 20, the rest kept");
	NSArray *straight = @[ route[0], route[3] ];
	XCTAssertNil([WKDEditor keptRoute:straight source:source target:target
	                      sourceMoved:NSMakeSize(0, 20) targetMoved:NSZeroSize], @"a straight flow has no bends to keep");
	XCTAssertNil([WKDEditor keptRoute:route source:NSOffsetRect(source, 120, 0) target:target
	                      sourceMoved:NSMakeSize(120, 0) targetMoved:NSZeroSize],
	             @"its bend would be inside the source");
}

- (void)testABendIsDragged
{
	WKDEditor *editor = [self modeller];
	[self step:^{ [editor moveBend:1 of:@"f5" to:NSMakePoint(250, 340)]; }];
	XCTAssertEqualObjects(WKDPoints([editor.diagram connectionWithId:@"f5"])[1], NSStringFromPoint(NSMakePoint(250, 340)));
	/* Not bends: nothing changes, and no undo step is made. */
	[editor moveBend:0 of:@"f5" to:NSMakePoint(0, 0)];
	[editor moveBend:2 of:@"f5" to:NSMakePoint(0, 0)];
	XCTAssertEqualObjects(WKDPoints([editor.diagram connectionWithId:@"f5"])[0], NSStringFromPoint(NSMakePoint(250, 176)),
	                      @"the ends are the shapes', not bends");
	[_undo undo];
	XCTAssertEqualObjects(WKDPoints([editor.diagram connectionWithId:@"f5"])[1], NSStringFromPoint(NSMakePoint(250, 318)));
}

- (void)testLabelsAreWhereTheDiagramPutsThem
{
	NSString *labelled = [WKDModellerFile stringByReplacingOccurrencesOfString:
		@"<dc:Bounds x=\"360\" y=\"93\" width=\"50\" height=\"50\"/></bpmndi:BPMNShape>"
		withString:@"<dc:Bounds x=\"360\" y=\"93\" width=\"50\" height=\"50\"/>"
		@"<bpmndi:BPMNLabel><dc:Bounds x=\"420\" y=\"80\" width=\"30\" height=\"14\"/></bpmndi:BPMNLabel></bpmndi:BPMNShape>"];
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(labelled) undoManager:nil];
	XCTAssertTrue(NSEqualRects([editor.diagram shapeWithId:@"ok"].labelBounds, NSMakeRect(420, 80, 30, 14)));
	XCTAssertTrue(NSIsEmptyRect([editor.diagram shapeWithId:@"start"].labelBounds), @"the start's says nothing");

	/* Dragged: a label the diagram had not placed is placed where it was drawn. */
	[editor moveLabelOf:@"start" by:NSMakeSize(0, -60)];
	NSRect drawn = WKDNodeLabelRect(@"startEvent", NSMakeRect(100, 100, 36, 36));
	XCTAssertTrue(NSEqualRects([editor.diagram shapeWithId:@"start"].labelBounds, NSOffsetRect(drawn, 0, -60)));
	/* A node's label goes with it. */
	[editor moveElements:@[ @"ok" ] by:NSMakeSize(0, 100)];
	XCTAssertTrue(NSEqualRects([editor.diagram shapeWithId:@"ok"].labelBounds, NSMakeRect(420, 180, 30, 14)));
	/* A flow's follows its middle. */
	[editor moveLabelOf:@"f3" by:NSMakeSize(0, 10)];
	NSRect before = [editor.diagram connectionWithId:@"f3"].labelBounds;
	[editor moveElements:@[ @"ship" ] by:NSMakeSize(0, 40)];
	WKDConnection *f3 = [editor.diagram connectionWithId:@"f3"];
	NSRect middleNow = WKDFlowLabelRect(f3.waypoints);
	XCTAssertFalse(NSEqualRects(f3.labelBounds, before), @"moved with the flow");
	XCTAssertTrue(NSPointInRect(NSMakePoint(NSMidX(f3.labelBounds), NSMidY(f3.labelBounds) - 10),
	                            NSInsetRect(middleNow, -60, -60)), @"near its middle still");
}

@end

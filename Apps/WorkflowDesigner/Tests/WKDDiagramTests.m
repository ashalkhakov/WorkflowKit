#import <XCTest/XCTest.h>
#import "WKDDiagram.h"
#import "WKDXML.h"
#import "WKDFixtures.h"

@interface WKDDiagramTests : XCTestCase
@end

@implementation WKDDiagramTests

- (void)testShapesAreReadWithTheirKindsAndBounds
{
	WKDDiagram *diagram = [WKDDiagram diagramOfDocument:WKDParse(WKDModellerFile)];
	XCTAssertEqualObjects(WKDAttribute(diagram.process, @"id"), @"order");
	XCTAssertNotNil(diagram.plane);
	XCTAssertEqual([diagram.shapes count], (NSUInteger)12);
	WKDShape *review = [diagram shapeWithId:@"review"];
	XCTAssertEqual(review.kind, WKDShapeActivity);
	XCTAssertEqualObjects(review.name, @"Review");
	XCTAssertTrue(NSEqualRects(review.bounds, NSMakeRect(200, 78, 100, 80)));
	XCTAssertEqual([diagram shapeWithId:@"ok"].kind, WKDShapeGateway);
	XCTAssertEqual([diagram shapeWithId:@"note"].kind, WKDShapeArtifact);
	XCTAssertEqualObjects([diagram shapeWithId:@"note"].name, @"Ask the warehouse", @"an annotation's text is its name");
	XCTAssertFalse(diagram.needsLayout);
}

- (void)testContainmentAndAttachment
{
	WKDDiagram *diagram = [WKDDiagram diagramOfDocument:WKDParse(WKDModellerFile)];
	WKDShape *ship = [diagram shapeWithId:@"ship"];
	XCTAssertEqual([diagram shapeWithId:@"pack"].parent, ship);
	XCTAssertNil([diagram shapeWithId:@"review"].parent);
	WKDShape *late = [diagram shapeWithId:@"late"];
	XCTAssertEqual(late.host, [diagram shapeWithId:@"review"]);
	XCTAssertEqualObjects(late.eventDefinition, @"timerEventDefinition");
	XCTAssertFalse(late.interrupting);
	XCTAssertEqualObjects([[diagram shapesIn:ship] valueForKey:@"elementId"], (@[ @"shipStart", @"pack", @"shipEnd" ]));
	XCTAssertFalse([[[diagram shapesIn:nil] valueForKey:@"elementId"] containsObject:@"late"],
	               @"a boundary event is its activity's, not the process's");
}

- (void)testFlowsWithTheirRoutesDefaultsAndConditions
{
	WKDDiagram *diagram = [WKDDiagram diagramOfDocument:WKDParse(WKDModellerFile)];
	XCTAssertEqual([diagram.connections count], (NSUInteger)8);
	WKDConnection *late = [diagram connectionWithId:@"f5"];
	XCTAssertEqual([late.waypoints count], (NSUInteger)3);
	XCTAssertTrue(NSEqualPoints([[late.waypoints lastObject] pointValue], NSMakePoint(300, 318)));
	XCTAssertTrue([diagram connectionWithId:@"f4"].isDefault);
	XCTAssertFalse([diagram connectionWithId:@"f3"].isDefault);
	XCTAssertTrue([diagram connectionWithId:@"f3"].hasCondition);
	XCTAssertEqual([[diagram connectionsOf:[diagram shapeWithId:@"ok"]] count], (NSUInteger)3);
}

- (void)testAProcessWithoutADiagramNeedsLayout
{
	WKDDiagram *diagram = [WKDDiagram diagramOfDocument:WKDParse(WKDUndrawnFile)];
	XCTAssertNil(diagram.plane);
	XCTAssertTrue(diagram.needsLayout);
	XCTAssertEqual([diagram.shapes count], (NSUInteger)6);
	XCTAssertEqual([diagram.connections count], (NSUInteger)6);
	XCTAssertEqual([[diagram connectionWithId:@"a"].waypoints count], (NSUInteger)0, @"no shapes, no route");
}

@end

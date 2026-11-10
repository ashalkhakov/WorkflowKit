#import <XCTest/XCTest.h>
#import "WKDModel.h"
#import "WKDXML.h"
#import "WKDFixtures.h"

@interface WKDDiagramTests : XCTestCase
@end

@implementation WKDDiagramTests

- (void)testShapesAreReadWithTheirKindsAndBounds
{
	WKDModel *diagram = [WKDModel modelOfDocument:WKDParse(WKDModellerFile)];
	XCTAssertEqualObjects(WKDAttribute(diagram.process, @"id"), @"order");
	XCTAssertNotNil(diagram.plane);
	XCTAssertEqual([diagram.nodes count], (NSUInteger)12);
	WKDNode *review = [diagram nodeWithId:@"review"];
	XCTAssertEqual(review.kind, WKDShapeActivity);
	XCTAssertEqualObjects(review.name, @"Review");
	XCTAssertTrue(NSEqualRects(review.bounds, NSMakeRect(200, 78, 100, 80)));
	XCTAssertEqual([diagram nodeWithId:@"ok"].kind, WKDShapeGateway);
	XCTAssertEqual([diagram nodeWithId:@"note"].kind, WKDShapeArtifact);
	XCTAssertEqualObjects([diagram nodeWithId:@"note"].name, @"Ask the warehouse", @"an annotation's text is its name");
	XCTAssertFalse(diagram.needsLayout);
}

- (void)testContainmentAndAttachment
{
	WKDModel *diagram = [WKDModel modelOfDocument:WKDParse(WKDModellerFile)];
	WKDNode *ship = [diagram nodeWithId:@"ship"];
	XCTAssertEqual([diagram nodeWithId:@"pack"].parent, ship);
	XCTAssertNil([diagram nodeWithId:@"review"].parent);
	WKDNode *late = [diagram nodeWithId:@"late"];
	XCTAssertEqual(late.host, [diagram nodeWithId:@"review"]);
	XCTAssertEqualObjects(late.eventDefinition, @"timerEventDefinition");
	XCTAssertFalse(late.interrupting);
	XCTAssertEqualObjects([[diagram nodesIn:ship] valueForKey:@"elementId"], (@[ @"shipStart", @"pack", @"shipEnd" ]));
	XCTAssertFalse([[[diagram nodesIn:nil] valueForKey:@"elementId"] containsObject:@"late"],
	               @"a boundary event is its activity's, not the process's");
}

- (void)testFlowsWithTheirRoutesDefaultsAndConditions
{
	WKDModel *diagram = [WKDModel modelOfDocument:WKDParse(WKDModellerFile)];
	XCTAssertEqual([diagram.flows count], (NSUInteger)8);
	WKDFlow *late = [diagram flowWithId:@"f5"];
	XCTAssertEqual([late.waypoints count], (NSUInteger)3);
	XCTAssertTrue(NSEqualPoints([[late.waypoints lastObject] pointValue], NSMakePoint(300, 318)));
	XCTAssertTrue([diagram flowWithId:@"f4"].isDefault);
	XCTAssertFalse([diagram flowWithId:@"f3"].isDefault);
	XCTAssertTrue([diagram flowWithId:@"f3"].hasCondition);
	XCTAssertEqual([[diagram flowsOf:[diagram nodeWithId:@"ok"]] count], (NSUInteger)3);
}

- (void)testAProcessWithoutADiagramNeedsLayout
{
	WKDModel *diagram = [WKDModel modelOfDocument:WKDParse(WKDUndrawnFile)];
	XCTAssertNil(diagram.plane);
	XCTAssertTrue(diagram.needsLayout);
	XCTAssertEqual([diagram.nodes count], (NSUInteger)6);
	XCTAssertEqual([diagram.flows count], (NSUInteger)6);
	XCTAssertEqual([[diagram flowWithId:@"a"].waypoints count], (NSUInteger)0, @"no shapes, no route");
}

@end

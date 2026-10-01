#import <XCTest/XCTest.h>
#import "WKDLayout.h"

@interface WKDLayoutTests : XCTestCase
@end

@implementation WKDLayoutTests

static NSRect
WKDFrame(NSDictionary *origins, NSString *nodeId, NSSize size)
{
	NSPoint origin = [[origins objectForKey:nodeId] pointValue];
	return NSMakeRect(origin.x, origin.y, size.width, size.height);
}

- (void)testAChainIsOneStraightLine
{
	WKDLayout *layout = [[WKDLayout alloc] init];
	[layout addNode:@"a" size:NSMakeSize(36, 36)];
	[layout addNode:@"b" size:NSMakeSize(100, 80)];
	[layout addNode:@"c" size:NSMakeSize(36, 36)];
	[layout addEdgeFrom:@"a" to:@"b"];
	[layout addEdgeFrom:@"b" to:@"c"];
	NSDictionary *origins = [layout layout];
	NSRect a = WKDFrame(origins, @"a", NSMakeSize(36, 36)), b = WKDFrame(origins, @"b", NSMakeSize(100, 80));
	NSRect c = WKDFrame(origins, @"c", NSMakeSize(36, 36));
	XCTAssertEqual(NSMidY(a), NSMidY(b));
	XCTAssertEqual(NSMidY(b), NSMidY(c));
	XCTAssertEqual(NSMinX(b) - NSMaxX(a), layout.layerSpacing);
	XCTAssertLessThan(NSMaxX(b), NSMinX(c));
	XCTAssertEqual(layout.size.height, 80.0);
}

- (void)testBranchesShareALayerWithoutOverlapping
{
	WKDLayout *layout = [[WKDLayout alloc] init];
	for (NSString *node in @[ @"split", @"x", @"y", @"z", @"join" ]) {
		[layout addNode:node size:NSMakeSize(100, 80)];
	}
	for (NSString *branch in @[ @"x", @"y", @"z" ]) {
		[layout addEdgeFrom:@"split" to:branch];
		[layout addEdgeFrom:branch to:@"join"];
	}
	NSDictionary *origins = [layout layout];
	XCTAssertEqual([layout layerOf:@"x"], 1);
	XCTAssertEqual([layout layerOf:@"z"], 1);
	XCTAssertEqual([layout layerOf:@"join"], 2);
	NSRect x = WKDFrame(origins, @"x", NSMakeSize(100, 80)), y = WKDFrame(origins, @"y", NSMakeSize(100, 80));
	XCTAssertFalse(NSIntersectsRect(x, y));
	XCTAssertEqual(NSMinY(y) - NSMaxY(x), layout.nodeSpacing);
	XCTAssertEqual(NSMidY(WKDFrame(origins, @"split", NSMakeSize(100, 80))), NSMidY(y), @"centred on its branches");
}

- (void)testALoopIsLaidOutAsIfItRanForward
{
	WKDLayout *layout = [[WKDLayout alloc] init];
	for (NSString *node in @[ @"start", @"work", @"check", @"end" ]) {
		[layout addNode:node size:NSMakeSize(50, 50)];
	}
	[layout addEdgeFrom:@"start" to:@"work"];
	[layout addEdgeFrom:@"work" to:@"check"];
	[layout addEdgeFrom:@"check" to:@"work"];
	[layout addEdgeFrom:@"check" to:@"end"];
	[layout layout];
	XCTAssertEqual([layout layerOf:@"start"], 0);
	XCTAssertEqual([layout layerOf:@"work"], 1);
	XCTAssertEqual([layout layerOf:@"check"], 2);
	XCTAssertEqual([layout layerOf:@"end"], 3);
}

- (void)testALongEdgeDoesNotCrossItsNeighbours
{
	/* a → b → c → d, and a → d around them: d's placeholder path keeps
	 * the long edge to one side. */
	WKDLayout *layout = [[WKDLayout alloc] init];
	for (NSString *node in @[ @"a", @"b", @"c", @"d", @"e" ]) {
		[layout addNode:node size:NSMakeSize(40, 40)];
	}
	[layout addEdgeFrom:@"a" to:@"b"];
	[layout addEdgeFrom:@"b" to:@"c"];
	[layout addEdgeFrom:@"c" to:@"d"];
	[layout addEdgeFrom:@"a" to:@"e"];
	[layout addEdgeFrom:@"e" to:@"d"];
	NSDictionary *origins = [layout layout];
	XCTAssertEqual([origins count], (NSUInteger)5, @"placeholders are not nodes");
	XCTAssertEqual([layout layerOf:@"d"], 3);
	XCTAssertEqual([layout layerOf:@"e"], 1);
}

@end

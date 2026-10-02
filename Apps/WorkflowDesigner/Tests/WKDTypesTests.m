#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDXML.h"
#import "WKDFixtures.h"

/* A node's type changed in place, and what goes with its old one. */
@interface WKDTypesTests : XCTestCase
@end

@implementation WKDTypesTests

- (WKDEditor *)modeller
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
}

static NSArray *
WKDTitles(NSArray<WKDNodeType *> *types)
{
	return [types valueForKey:@"title"];
}

- (void)testWhatANodeCanBecome
{
	WKDEditor *editor = [self modeller];
	XCTAssertTrue([WKDTitles([editor typesFor:@"review"]) containsObject:@"Service Task"]);
	XCTAssertEqualObjects([editor typesFor:@"ship"], @[], @"a subprocess stays one");
	XCTAssertEqualObjects(WKDTitles([editor typesFor:@"ok"]),
	                      (@[ @"Exclusive Gateway", @"Parallel Gateway", @"Inclusive Gateway", @"Event-based Gateway" ]));
	NSArray *refused = WKDTitles([editor typesFor:@"refused"]);
	XCTAssertTrue([refused containsObject:@"Terminate End Event"]);
	XCTAssertTrue([refused containsObject:@"Timer Catch Event"]);
	XCTAssertFalse([refused containsObject:@"Start Event"], @"a flow comes into it");
	NSArray *start = WKDTitles([editor typesFor:@"start"]);
	XCTAssertTrue([start containsObject:@"Timer Start Event"]);
	XCTAssertFalse([start containsObject:@"End Event"], @"a flow leaves it");
	XCTAssertFalse([start containsObject:@"Error Start Event"], @"only an event subprocess starts on an error");
	XCTAssertTrue([WKDTitles([editor typesFor:@"late"]) containsObject:@"Message Boundary Event"]);
	XCTAssertFalse([WKDTitles([editor typesFor:@"late"]) containsObject:@"End Event"]);
}

- (void)testATaskBecomesAnother
{
	WKDEditor *editor = [self modeller];
	NSString *reason = nil;
	XCTAssertTrue([editor changeType:@"review" to:[WKDNodeType type:@"serviceTask" eventDefinition:nil title:nil]
	                           error:&reason], @"%@", reason);
	WKDShape *review = [editor.diagram shapeWithId:@"review"];
	XCTAssertEqualObjects(review.type, @"serviceTask");
	XCTAssertEqualObjects([review.element name], @"bpmn:serviceTask", @"in its prefix");
	XCTAssertEqualObjects(review.name, @"Review");
	XCTAssertNil(WKDQualifiedAttribute(editor.document, review.element, WKDCamundaNamespace, @"candidateGroups"),
	             @"who does a user task goes");
	XCTAssertNotNil(WKDDescendants(review.element, WKDCamundaNamespace, @"inputParameter").firstObject,
	                @"its parameters stay");
	XCTAssertEqual([[editor.diagram connectionsOf:review] count], (NSUInteger)2, @"and its flows");
	XCTAssertNotNil([editor.diagram shapeWithId:@"late"].host, @"and what is attached to it");
}

- (void)testAGatewayBecomesAnother
{
	WKDEditor *editor = [self modeller];
	XCTAssertTrue([editor changeType:@"ok" to:[WKDNodeType type:@"inclusiveGateway" eventDefinition:nil title:nil]
	                           error:NULL]);
	XCTAssertEqualObjects(WKDAttribute([editor elementWithId:@"ok"], @"default"), @"f4", @"an inclusive one has defaults");
	XCTAssertTrue([editor changeType:@"ok" to:[WKDNodeType type:@"parallelGateway" eventDefinition:nil title:nil]
	                           error:NULL]);
	XCTAssertNil(WKDAttribute([editor elementWithId:@"ok"], @"default"), @"a parallel one has none");
}

- (void)testAnEventChangesItsDefinition
{
	WKDEditor *editor = [self modeller];
	NSString *reason = nil;
	XCTAssertTrue([editor changeType:@"late" to:[WKDNodeType type:@"boundaryEvent"
	                                            eventDefinition:@"messageEventDefinition" title:nil] error:&reason]);
	WKDShape *late = [editor.diagram shapeWithId:@"late"];
	XCTAssertEqualObjects(late.eventDefinition, @"messageEventDefinition");
	XCTAssertNil(WKDChild(late.element, WKDBpmnNamespace, @"timerEventDefinition"));
	XCTAssertEqualObjects([[WKDChildren(late.element, WKDBpmnNamespace, nil) lastObject] localName],
	                      @"messageEventDefinition", @"after its outgoing");

	XCTAssertTrue([editor changeType:@"refused" to:[WKDNodeType type:@"endEvent"
	                                               eventDefinition:@"terminateEventDefinition" title:nil] error:NULL]);
	XCTAssertEqualObjects([editor.diagram shapeWithId:@"refused"].eventDefinition, @"terminateEventDefinition");
	XCTAssertTrue([editor changeType:@"refused" to:[WKDNodeType type:@"endEvent" eventDefinition:nil title:nil]
	                           error:NULL]);
	XCTAssertNil([editor.diagram shapeWithId:@"refused"].eventDefinition, @"a none event again");

	XCTAssertFalse([editor changeType:@"refused" to:[WKDNodeType type:@"startEvent" eventDefinition:nil title:nil]
	                            error:&reason]);
	XCTAssertEqualObjects(reason, @"The node cannot become that.");
	XCTAssertFalse([editor changeType:@"review" to:[WKDNodeType type:@"exclusiveGateway" eventDefinition:nil title:nil]
	                            error:&reason]);
}

@end

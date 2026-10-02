#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDXML.h"
#import "WKDFixtures.h"

/* Copying and pasting: what is copied, under what ids it comes back, and
 * into another document, whatever prefixes it writes. */
@interface WKDClipboardTests : XCTestCase
@end

/* A process in BPMN's namespace by default, no prefix, with a message. */
static NSString * const WKDUnprefixedFile =
	@"<definitions xmlns=\"http://www.omg.org/spec/BPMN/20100524/MODEL\" "
	@"xmlns:bpmndi=\"http://www.omg.org/spec/BPMN/20100524/DI\" xmlns:dc=\"http://www.omg.org/spec/DD/20100524/DC\" "
	@"id=\"defs\" targetNamespace=\"http://example.com\">"
	@"<message id=\"paid\" name=\"paid\"/>"
	@"<process id=\"p\" isExecutable=\"true\"><startEvent id=\"s\"/></process>"
	@"<bpmndi:BPMNDiagram id=\"d\"><bpmndi:BPMNPlane id=\"pl\" bpmnElement=\"p\">"
	@"<bpmndi:BPMNShape id=\"s_di\" bpmnElement=\"s\"><dc:Bounds x=\"10\" y=\"10\" width=\"36\" height=\"36\"/>"
	@"</bpmndi:BPMNShape></bpmndi:BPMNPlane></bpmndi:BPMNDiagram></definitions>";

@implementation WKDClipboardTests

- (WKDEditor *)editorOf:(NSString *)xml undo:(NSUndoManager *)undo
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(xml) undoManager:undo];
}

static NSArray *
WKDReferences(NSXMLElement *node, NSString *local)
{
	return [WKDChildren(node, WKDBpmnNamespace, local) valueForKey:@"stringValue"];
}

- (void)testACopyHoldsWhatTheNodesNeed
{
	WKDEditor *editor = [self editorOf:WKDModellerFile undo:nil];
	NSXMLDocument *fragment = [editor fragmentOfElements:@[ @"review", @"ok", @"late" ]];
	XCTAssertNotNil(fragment);
	WKDDiagram *copied = [WKDDiagram diagramOfDocument:fragment];
	XCTAssertEqualObjects([[copied.shapes valueForKey:@"elementId"] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @"late", @"ok", @"review" ]));
	XCTAssertEqualObjects([copied.connections valueForKey:@"elementId"], @[ @"f2" ], @"only the flow between them");
	NSXMLElement *review = [[copied shapeWithId:@"review"] element];
	XCTAssertEqualObjects(WKDReferences(review, @"incoming"), @[], @"f1 was not copied");
	XCTAssertEqualObjects(WKDReferences(review, @"outgoing"), @[ @"f2" ]);
	XCTAssertNil(WKDAttribute([[copied shapeWithId:@"ok"] element], @"default"), @"f4 was not copied");
	XCTAssertTrue([copied shapeWithId:@"review"].hasBounds, @"with its diagram");

	/* A boundary event needs its activity. */
	XCTAssertNil([editor fragmentOfElements:@[ @"late" ]]);
	XCTAssertNil([editor fragmentOfElements:@[ @"f1" ]], @"a flow alone");
}

- (void)testPastedNodesGetIdsOfTheirOwn
{
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	WKDEditor *editor = [self editorOf:WKDModellerFile undo:undo];
	NSUInteger nodes = [editor.diagram.shapes count], flows = [editor.diagram.connections count];
	NSString *reason = nil;
	NSArray *added = [editor paste:[editor fragmentOfElements:@[ @"review", @"ok" ]] offset:NSMakeSize(0, 300)
	                         error:&reason];
	XCTAssertEqual([added count], (NSUInteger)4, @"review, late, ok and f2: %@ %@", added, reason);
	XCTAssertEqual([editor.diagram.shapes count], nodes + 3);
	XCTAssertEqual([editor.diagram.connections count], flows + 1);
	WKDConnection *flow = nil;
	NSArray *originals = @[ @"review", @"late", @"ok", @"f2" ];
	for (NSString *elementId in added) {
		XCTAssertFalse([originals containsObject:elementId]);
		flow = flow ?: [editor.diagram connectionWithId:elementId];
	}
	XCTAssertEqualObjects(flow.source.name, @"Review", @"the copy's flow joins the copies");
	XCTAssertEqualObjects(flow.target.name, @"OK?");
	XCTAssertTrue(flow.source != [editor.diagram shapeWithId:@"review"]);
	XCTAssertEqualObjects(WKDReferences(flow.source.element, @"outgoing"), @[ flow.elementId ]);
	XCTAssertEqualObjects(WKDReferences(flow.target.element, @"incoming"), @[ flow.elementId ]);
	XCTAssertTrue(NSEqualRects(flow.source.bounds, NSOffsetRect([editor.diagram shapeWithId:@"review"].bounds, 0, 300)),
	              @"moved by the offset");
	WKDShape *timer = nil;
	for (WKDShape *shape in editor.diagram.shapes) {
		if (shape.host == flow.source) {
			timer = shape;
		}
	}
	XCTAssertNotNil(timer, @"the boundary timer is on the copy");
	XCTAssertEqualObjects(timer.eventDefinition, @"timerEventDefinition");
	XCTAssertFalse([WKDAttribute(WKDChild(timer.element, WKDBpmnNamespace, @"timerEventDefinition"), @"id")
	                isEqualToString:@"t1"], @"its definition too");

	/* Pasted again: other ids still. */
	NSArray *again = [editor paste:[editor fragmentOfElements:@[ @"review" ]] offset:NSMakeSize(0, 600) error:NULL];
	XCTAssertFalse([again firstObjectCommonWithArray:added] != nil);
	[undo undo];
	[undo undo];
	XCTAssertEqual([editor.diagram.shapes count], nodes, @"each paste one step");
}

- (void)testASubprocessComesWithWhatItHolds
{
	WKDEditor *editor = [self editorOf:WKDModellerFile undo:nil];
	NSArray *added = [editor paste:[editor fragmentOfElements:@[ @"ship" ]] offset:NSMakeSize(0, 300) error:NULL];
	XCTAssertEqual([added count], (NSUInteger)1, @"%@", added);
	WKDShape *copy = [editor.diagram shapeWithId:[added firstObject]];
	NSArray *inside = [editor.diagram shapesIn:copy];
	XCTAssertEqual([inside count], (NSUInteger)3);
	NSUInteger innerFlows = 0;
	for (WKDConnection *connection in editor.diagram.connections) {
		if (connection.source.parent == copy) {
			innerFlows++;
			XCTAssertTrue(connection.target.parent == copy);
			XCTAssertTrue(connection.source.hasBounds && [connection.waypoints count] >= 2);
		}
	}
	XCTAssertEqual(innerFlows, (NSUInteger)2);
}

- (void)testPastedIntoAnotherDocument
{
	NSString *withMessage = [WKDModellerFile stringByReplacingOccurrencesOfString:@"<bpmn:process id=\"order\""
		withString:@"<bpmn:message id=\"paid\" name=\"paid\"/><bpmn:message id=\"Message_9\" name=\"ready\"/>"
		@"<bpmn:process id=\"order\""];
	withMessage = [withMessage stringByReplacingOccurrencesOfString:@"<bpmn:endEvent id=\"done\">"
		withString:@"<bpmn:receiveTask id=\"wait\" messageRef=\"Message_9\"/><bpmn:endEvent id=\"done\">"];
	WKDEditor *source = [self editorOf:withMessage undo:nil];
	NSXMLDocument *fragment = [source fragmentOfElements:@[ @"review", @"wait" ]];
	XCTAssertNotNil(WKDElementWithId(fragment, @"Message_9"), @"the message it names goes with it");
	XCTAssertNil(WKDElementWithId(fragment, @"paid"), @"not the one it does not");

	WKDEditor *target = [self editorOf:WKDUnprefixedFile undo:nil];
	NSString *reason = nil;
	NSArray *added = [target paste:fragment offset:NSZeroSize error:&reason];
	XCTAssertEqual([added count], (NSUInteger)3, @"%@", reason);
	NSString *xml = [target.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"<userTask"].location != NSNotFound, @"in its prefixes: %@", xml);
	XCTAssertTrue([xml rangeOfString:@"bpmn:"].location == NSNotFound, @"none of the copy's: %@", xml);
	XCTAssertTrue([xml rangeOfString:@"xmlns:camunda=\"http://camunda.org/schema/1.0/bpmn\""].location != NSNotFound,
	              @"camunda's namespace declared where it was not: %@", xml);
	WKDShape *review = nil, *wait = nil;
	for (WKDShape *shape in target.diagram.shapes) {
		review = [shape.name isEqualToString:@"Review"] ? shape : review;
		wait = [shape.type isEqualToString:@"receiveTask"] ? shape : wait;
	}
	XCTAssertEqualObjects(WKDQualifiedAttribute(target.document, review.element, WKDCamundaNamespace, @"candidateGroups"),
	                      @"clerks", @"%@", [review.element XMLString]);
	XCTAssertEqualObjects(WKDAttribute(wait.element, @"messageRef"), @"Message_9", @"the message, copied as it was");
	XCTAssertEqualObjects([WKDElementWithId(target.document, @"Message_9") localName], @"message");
	XCTAssertTrue(review.hasBounds, @"with its shape");

	/* A message of that id the target has already is the one it names. */
	WKDEditor *again = [self editorOf:withMessage undo:nil];
	NSUInteger messages = [WKDChildren([again.document rootElement], WKDBpmnNamespace, @"message") count];
	[again paste:fragment offset:NSMakeSize(0, 200) error:NULL];
	XCTAssertEqual([WKDChildren([again.document rootElement], WKDBpmnNamespace, @"message") count], messages);
}

@end

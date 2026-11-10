#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDXML.h"
#import "WKDFixtures.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

@interface WKDEditorTests : XCTestCase
@end

@implementation WKDEditorTests
{
	NSUndoManager *_undo;
}

- (void)setUp
{
	[super setUp];
	_undo = [[NSUndoManager alloc] init];
	/* Each change its own step, as the run loop's events make them. */
	[_undo setGroupsByEvent:NO];
}

- (WKDEditor *)editorOf:(NSString *)xml
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(xml) undoManager:nil];
}

/* The change, as one undo step. */
- (void)step:(void (^)(void))change
{
	[_undo beginUndoGrouping];
	change();
	[_undo endUndoGrouping];
}

/* What the engine makes of the document: nil, with the error, when it
 * would not deploy it. */
- (WFProcessDefinition *)engineRead:(WKDEditor *)editor
{
	NSError *error = nil;
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:[editor.document XMLString] error:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

static NSArray *
WKDReferences(NSXMLElement *node, NSString *local)
{
	return [WKDChildren(node, WKDBpmnNamespace, local) valueForKey:@"stringValue"];
}

- (void)testANewProcessIsAStartEvent
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:[WKDEditor newProcessDocument] undoManager:nil];
	XCTAssertEqual([editor.model.nodes count], (NSUInteger)1);
	XCTAssertTrue([editor.model.nodes.firstObject hasBounds]);
	XCTAssertTrue(WKDAttribute(editor.model.process, @"isExecutable") != nil);
	/* Not yet one the engine runs: what the designer's check reports. */
	NSError *error = nil;
	XCTAssertNil([WFBpmnReader definitionFromXMLString:[editor.document XMLString] error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"end event"].location != NSNotFound, @"%@", error);
}

- (void)testAProcessWithoutADiagramIsLaidOut
{
	WKDEditor *editor = [self editorOf:WKDUndrawnFile];
	[editor completeDiagram];
	WKDModel *diagram = editor.model;
	XCTAssertFalse(diagram.needsLayout);
	for (WKDNode *a in diagram.nodes) {
		for (WKDNode *b in diagram.nodes) {
			XCTAssertTrue(a == b || !NSIntersectsRect(a.bounds, b.bounds), @"%@ overlaps %@", a, b);
		}
	}
	/* Left to right, along the flows -- the loop back aside. */
	for (WKDFlow *connection in diagram.flows) {
		XCTAssertGreaterThanOrEqual([connection.waypoints count], (NSUInteger)2, @"%@", connection.elementId);
		if (![connection.elementId isEqualToString:@"back"]) {
			XCTAssertLessThan(NSMidX(connection.source.bounds), NSMidX(connection.target.bounds), @"%@", connection.elementId);
		}
	}
	XCTAssertEqual(NSMidY([diagram nodeWithId:@"request"].bounds), NSMidY([diagram nodeWithId:@"approve"].bounds),
	               @"a chain is a straight line");
	XCTAssertEqualObjects(WKDAttribute([diagram nodeWithId:@"approve"].element, @"camunda:candidateGroups"), @"managers");
	[self engineRead:editor];
}

- (void)testAddingAndConnectingKeepTheReferences
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:[WKDEditor newProcessDocument] undoManager:_undo];
	__block NSString *taskId = nil, *flowId = nil;
	[self step:^{
		taskId = [editor insertNodeOfType:@"userTask" eventDefinition:nil at:NSMakePoint(400, 200) error:NULL];
	}];
	XCTAssertTrue([taskId hasPrefix:@"Activity_"]);
	WKDNode *task = [editor.model nodeWithId:taskId];
	XCTAssertTrue(NSEqualRects(task.bounds, NSMakeRect(350, 160, 100, 80)), @"%@", task);
	[self step:^{
		flowId = [editor connect:@"StartEvent_1" to:taskId error:NULL];
	}];
	XCTAssertNotNil(flowId);
	WKDModel *diagram = editor.model;
	XCTAssertEqualObjects(WKDReferences([diagram nodeWithId:@"StartEvent_1"].element, @"outgoing"), @[ flowId ]);
	XCTAssertEqualObjects(WKDReferences([diagram nodeWithId:taskId].element, @"incoming"), @[ flowId ]);
	WKDFlow *flow = [diagram flowWithId:flowId];
	XCTAssertTrue(NSEqualPoints([[flow.waypoints firstObject] pointValue], NSMakePoint(NSMaxX(flow.source.bounds), NSMidY(flow.source.bounds))));
	/* Level with the task: straight across into its side. */
	XCTAssertEqual([flow.waypoints count], (NSUInteger)2, @"%@", flow.waypoints);
	XCTAssertTrue(NSEqualPoints([[flow.waypoints lastObject] pointValue],
	                            NSMakePoint(NSMinX(task.bounds), NSMidY(flow.source.bounds))), @"%@", flow.waypoints);
	__block NSString *endId = nil;
	[self step:^{
		endId = [editor insertNodeOfType:@"endEvent" eventDefinition:nil at:NSMakePoint(560, 200) error:NULL];
	}];
	[self step:^{
		XCTAssertNotNil([editor connect:taskId to:endId error:NULL]);
	}];
	WFProcessDefinition *definition = [self engineRead:editor];
	XCTAssertEqualObjects([definition nodeWithId:taskId].incomingFlowIds, @[ flowId ]);
}

- (void)testFlowsTheEngineWouldRefuseAreNotMade
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	NSString *reason = nil;
	XCTAssertNil([editor connect:@"done" to:@"review" error:&reason]);
	XCTAssertTrue([reason rangeOfString:@"end event"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([editor connect:@"review" to:@"start" error:&reason]);
	XCTAssertNil([editor connect:@"review" to:@"pack" error:&reason]);
	XCTAssertTrue([reason rangeOfString:@"subprocess"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([editor connect:@"start" to:@"review" error:&reason]);
	XCTAssertNil([editor connect:@"review" to:@"review" error:&reason]);
	XCTAssertNotNil([editor connect:@"late" to:@"done" error:&reason], @"%@", reason);
}

- (void)testMovingRoutesTheFlowsAgain
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	[editor moveElements:@[ @"review" ] by:NSMakeSize(0, 100)];
	WKDModel *diagram = editor.model;
	XCTAssertTrue(NSEqualRects([diagram nodeWithId:@"review"].bounds, NSMakeRect(200, 178, 100, 80)));
	XCTAssertTrue(NSEqualRects([diagram nodeWithId:@"late"].bounds, NSMakeRect(232, 240, 36, 36)),
	              @"its boundary event goes with it");
	NSArray *f2 = [diagram flowWithId:@"f2"].waypoints;
	XCTAssertTrue(NSEqualPoints([[f2 firstObject] pointValue], NSMakePoint(300, 218)), @"%@", f2);
	XCTAssertTrue(NSEqualPoints([[f2 lastObject] pointValue], NSMakePoint(360, 118)),
	              @"into the split's side, its bottom f4's: %@", f2);
	XCTAssertTrue(NSEqualPoints([[[diagram flowWithId:@"f6"].waypoints firstObject] pointValue], NSMakePoint(820, 118)),
	              @"a flow between shapes that did not move keeps its route");
}

- (void)testASubprocessMovesWithWhatItHolds
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	[editor moveElements:@[ @"ship" ] by:NSMakeSize(10, 20)];
	WKDModel *diagram = editor.model;
	XCTAssertTrue(NSEqualRects([diagram nodeWithId:@"pack"].bounds, NSMakeRect(600, 98, 100, 80)));
	XCTAssertTrue(NSEqualPoints([[[diagram flowWithId:@"s1"].waypoints firstObject] pointValue], NSMakePoint(546, 138)),
	              @"a flow inside goes with it as it was");
}

- (void)testABoundaryEventStaysOnItsActivitysEdge
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	[editor moveElements:@[ @"late" ] by:NSMakeSize(30, 200)];
	NSRect late = [editor.model nodeWithId:@"late"].bounds;
	XCTAssertEqual(NSMidY(late), 158.0, @"on the bottom edge: %@", NSStringFromRect(late));
	XCTAssertEqual(NSMidX(late), 280.0);
	NSString *reason = nil;
	XCTAssertNil([editor insertNodeOfType:@"boundaryEvent" eventDefinition:@"messageEventDefinition"
	                                   at:NSMakePoint(1000, 1000) error:&reason]);
	NSString *added = [editor insertNodeOfType:@"boundaryEvent" eventDefinition:@"messageEventDefinition"
	                                        at:NSMakePoint(305, 100) error:&reason];
	WKDNode *message = [editor.model nodeWithId:added];
	XCTAssertEqual(message.host, [editor.model nodeWithId:@"review"], @"%@", reason);
	XCTAssertEqual(NSMidX(message.bounds), 300.0, @"on the right edge");
	XCTAssertEqualObjects(message.eventDefinition, @"messageEventDefinition");
}

- (void)testANodeAddedInASubprocessIsItsOwn
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	NSString *added = [editor insertNodeOfType:@"serviceTask" eventDefinition:nil at:NSMakePoint(640, 190) error:NULL];
	XCTAssertEqual([editor.model nodeWithId:added].parent, [editor.model nodeWithId:@"ship"]);
	XCTAssertNotNil([editor connect:@"pack" to:added error:NULL]);
}

- (void)testDeletingTakesTheFlowsAndTheirReferences
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	[editor deleteElements:@[ @"refused" ]];
	WKDModel *diagram = editor.model;
	XCTAssertNil([diagram nodeWithId:@"refused"]);
	XCTAssertNil([diagram flowWithId:@"f4"]);
	NSXMLElement *gateway = [diagram nodeWithId:@"ok"].element;
	XCTAssertEqualObjects(WKDReferences(gateway, @"outgoing"), @[ @"f3" ]);
	XCTAssertNil(WKDAttribute(gateway, @"default"), @"its default went with it");
	NSString *xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"refused_di"].location == NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"f4_di"].location == NSNotFound);

	[editor deleteElements:@[ @"ship" ]];
	xml = [editor.document XMLString];
	for (NSString *gone in @[ @"pack_di", @"s1_di", @"f3_di", @"f6_di", @"<bpmn:incoming>f6" ]) {
		XCTAssertTrue([xml rangeOfString:gone].location == NSNotFound, @"%@ left", gone);
	}
	[editor deleteElements:@[ @"review" ]];
	XCTAssertNil([editor.model nodeWithId:@"late"], @"its boundary event went with it");
	XCTAssertNil([editor.model flowWithId:@"f5"]);
}

- (void)testWhatTheDesignerDoesNotDrawIsKept
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	[editor moveElements:@[ @"start" ] by:NSMakeSize(-20, 0)];
	[editor deleteElements:@[ @"refused" ]];
	NSString *xml = [editor.document XMLString];
	for (NSString *kept in @[ @"Orders, reviewed and shipped.", @"camunda:inputParameter", @"Ask the warehouse",
	                          @"note_di", @"PT1H", @"=fine", @"isMarkerVisible" ]) {
		XCTAssertTrue([xml rangeOfString:kept].location != NSNotFound, @"%@ lost", kept);
	}
	[self engineRead:editor];
}

- (void)testUndoAndRedoRestoreTheDocument
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:_undo];
	NSString *before = [editor.document XMLString];
	__block NSUInteger changes = 0;
	id observer = [[NSNotificationCenter defaultCenter] addObserverForName:WKDEditorDidChangeNotification
	                                                                object:editor queue:nil
	                                                            usingBlock:^(NSNotification *note) {
		changes++;
	}];
	[self step:^{
		[editor moveElements:@[ @"review" ] by:NSMakeSize(40, 0)];
	}];
	NSString *moved = [editor.document XMLString];
	[self step:^{
		[editor deleteElements:@[ @"ok" ]];
	}];
	[_undo undo];
	XCTAssertEqualObjects([editor.document XMLString], moved);
	[_undo undo];
	XCTAssertEqualObjects([editor.document XMLString], before);
	XCTAssertNotNil([editor.model nodeWithId:@"ok"]);
	[_undo redo];
	XCTAssertEqualObjects([editor.document XMLString], moved);
	XCTAssertEqual(changes, (NSUInteger)5, @"two changes, two undos, a redo");
	[[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testArrangeLaysOutEveryScope
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	[editor arrange];
	WKDModel *diagram = editor.model;
	NSRect ship = [diagram nodeWithId:@"ship"].bounds;
	for (NSString *inside in @[ @"shipStart", @"pack", @"shipEnd" ]) {
		XCTAssertTrue(NSContainsRect(ship, [diagram nodeWithId:inside].bounds), @"%@ outside its subprocess", inside);
	}
	XCTAssertLessThan(NSMaxX([diagram nodeWithId:@"ok"].bounds), NSMinX(ship));
	NSRect review = [diagram nodeWithId:@"review"].bounds;
	XCTAssertEqual(NSMidY([diagram nodeWithId:@"late"].bounds), NSMaxY(review), @"on its activity's edge");
	[self engineRead:editor];
}

/* A split's branches leave by corners of their own: one level with it by
 * its side corner, not back through it; what comes into it by its other
 * side corner, not where a branch leaves (the expense review's "Any line
 * over 500?"). */
- (void)testABranchLeavesByACornerOfItsOwn
{
	NSRect split = NSMakeRect(186, 296, 50, 50), above = NSMakeRect(306, 228, 100, 80);
	NSRect level = NSMakeRect(476, 303, 50, 50), start = NSMakeRect(80, 80, 36, 36);
	NSArray *no = [WKDEditor routeFrom:split to:level fromBoundary:NO fromGateway:YES toActivity:NO];
	XCTAssertTrue(NSEqualPoints([no[0] pointValue], NSMakePoint(236, 321)), @"by the side corner: %@", no);
	XCTAssertTrue(NSEqualPoints([[no lastObject] pointValue], NSMakePoint(476, 328)), @"%@", no);
	NSArray *yes = [WKDEditor routeFrom:split to:above fromBoundary:NO fromGateway:YES toActivity:YES];
	XCTAssertTrue(NSEqualPoints([yes[0] pointValue], NSMakePoint(211, 296)), @"by the top corner: %@", yes);
	NSArray *in = [WKDEditor routeFrom:start to:split fromBoundary:NO fromGateway:NO toActivity:NO intoSide:YES];
	XCTAssertTrue(NSEqualPoints([[in lastObject] pointValue], NSMakePoint(186, 321)), @"into the side: %@", in);
	NSArray *back = [WKDEditor routeFrom:NSMakeRect(582, 360, 100, 80) to:split fromBoundary:NO fromGateway:NO
	                          toActivity:NO intoSide:YES];
	XCTAssertTrue(NSEqualPoints([[back lastObject] pointValue], NSMakePoint(186, 321)), @"back round: %@", back);

	WKDEditor *editor = [self editorOf:WKDModellerFile];
	[editor arrange];
	for (WKDNode *node in editor.model.nodes) {
		if (node.kind != WKDShapeGateway || [node.outgoing count] < 2) {
			continue;
		}
		for (WKDFlow *into in node.incoming) {
			for (WKDFlow *out in node.outgoing) {
				XCTAssertFalse(NSEqualPoints([[into.waypoints lastObject] pointValue], [out.waypoints[0] pointValue]),
				               @"%@ and %@ share a corner of %@", into.elementId, out.elementId, node.elementId);
			}
		}
	}
}

@end

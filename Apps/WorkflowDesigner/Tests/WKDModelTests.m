#import <XCTest/XCTest.h>
#import "WKDModelPriv.h"
#import "WKDModel.h"
#import "WKDXML.h"
#import "WKDFixtures.h"
#import "WKDEditor.h"
#import "WKDDecisions.h"
#import "WKDJournal.h"

/* Every editor in the test bundle checks its model against its document
 * after each change, undo and redo. */
__attribute__((constructor)) static void
WKDCheckAgreementInTests(void)
{
	WKDEditor.checksAgreement = YES;
	WKDDmnEditor.checksAgreement = YES;
}

/*
 * The model read from every fixture and example process: it agrees with
 * the diagram the designer draws from (WKDModel) element for element, an
 * unchanged model writes nothing, and every element written from the model
 * leaves the carrier as it was read -- the writer says everything the model
 * holds as the file says it.
 */

/* Where two texts first differ, with a little of each around it: for a
 * failure's message. */
static NSString *
WKDFirstDifference(NSString *a, NSString *b)
{
	NSUInteger length = MIN([a length], [b length]), i = 0;
	while (i < length && [a characterAtIndex:i] == [b characterAtIndex:i]) {
		i++;
	}
	if (i == length && [a length] == [b length]) {
		return @"the same";
	}
	NSUInteger from = i > 80 ? i - 80 : 0;
	return [NSString stringWithFormat:@"at %lu:\n  %@\nnot\n  %@", (unsigned long)i,
		[a substringWithRange:NSMakeRange(from, MIN([a length], i + 160) - from)],
		[b substringWithRange:NSMakeRange(from, MIN([b length], i + 160) - from)]];
}

@interface WKDModelTests : XCTestCase
@end

@implementation WKDModelTests

/* The BPMN fixtures' texts, and the example processes' by file name. */
- (NSDictionary<NSString *, NSString *> *)documents
{
	NSMutableDictionary *documents = [NSMutableDictionary dictionaryWithDictionary:@{
		@"modeller": WKDModellerFile,
		@"undrawn": WKDUndrawnFile,
		@"lanes": WKDLanesFile,
	}];
	NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
	NSString *examples = [[here stringByAppendingPathComponent:@"../../../Examples/Processes"] stringByStandardizingPath];
	NSDirectoryEnumerator *walk = [[NSFileManager defaultManager] enumeratorAtPath:examples];
	for (NSString *path in walk) {
		if ([[path pathExtension] isEqualToString:@"bpmn"]) {
			NSString *text = [NSString stringWithContentsOfFile:[examples stringByAppendingPathComponent:path]
			                                           encoding:NSUTF8StringEncoding error:NULL];
			if (text != nil) {
				[documents setObject:text forKey:[path lastPathComponent]];
			}
		}
	}
	XCTAssertGreaterThan([documents count], 10u, @"the examples are found from %@", examples);
	return documents;
}

- (NSXMLDocument *)parse:(NSString *)text
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error];
	XCTAssertNotNil(document, @"%@", error);
	return document;
}

- (void)testTheModelAgreesWithTheDiagram
{
	NSDictionary *documents = [self documents];
	for (NSString *name in documents) {
		NSString *text = [documents objectForKey:name];
		NSXMLDocument *document = [self parse:text];
		WKDModel *diagram = [WKDModel modelOfDocument:document];
		WKDModel *model = [WKDModel modelOfDocument:document];
		XCTAssertNotNil(model, @"%@", name);
		XCTAssertEqualObjects([model.nodes valueForKey:@"elementId"], [diagram.nodes valueForKey:@"elementId"], @"%@", name);
		for (WKDNode *shape in diagram.nodes) {
			WKDNode *node = [model nodeWithId:shape.elementId];
			XCTAssertEqualObjects(node.type, shape.type, @"%@ %@", name, shape.elementId);
			XCTAssertEqual(node.kind, shape.kind, @"%@ %@", name, shape.elementId);
			XCTAssertEqualObjects(node.name, shape.name, @"%@ %@", name, shape.elementId);
			XCTAssertEqual(node.hasBounds, shape.hasBounds, @"%@ %@", name, shape.elementId);
			XCTAssertTrue(NSEqualRects(node.bounds, shape.bounds), @"%@ %@", name, shape.elementId);
			XCTAssertTrue(NSEqualRects(node.labelBounds, shape.labelBounds), @"%@ %@", name, shape.elementId);
			XCTAssertEqualObjects(node.parent.elementId, shape.parent.elementId, @"%@ %@", name, shape.elementId);
			XCTAssertEqualObjects(node.host.elementId, shape.host.elementId, @"%@ %@", name, shape.elementId);
			XCTAssertEqualObjects(node.eventDefinition, shape.eventDefinition, @"%@ %@", name, shape.elementId);
			XCTAssertEqual(node.interrupting, shape.interrupting, @"%@ %@", name, shape.elementId);
			XCTAssertEqual(node.eventSubProcess, shape.eventSubProcess, @"%@ %@", name, shape.elementId);
			XCTAssertEqualObjects(node.loop, shape.loop, @"%@ %@", name, shape.elementId);
			XCTAssertEqualObjects(node.lane.elementId, [diagram laneOf:shape].elementId, @"%@ %@", name, shape.elementId);
			XCTAssertEqualObjects([node.children valueForKey:@"elementId"],
			                      [[diagram nodesIn:shape] valueForKey:@"elementId"], @"%@ %@", name, shape.elementId);
		}
		XCTAssertEqualObjects([model.topNodes valueForKey:@"elementId"],
		                      [[diagram nodesIn:nil] valueForKey:@"elementId"], @"%@", name);
		XCTAssertEqualObjects([model.flows valueForKey:@"elementId"], [diagram.flows valueForKey:@"elementId"], @"%@", name);
		for (WKDFlow *connection in diagram.flows) {
			WKDFlow *flow = [model flowWithId:connection.elementId];
			XCTAssertEqualObjects(flow.source.elementId, connection.source.elementId, @"%@ %@", name, connection.elementId);
			XCTAssertEqualObjects(flow.target.elementId, connection.target.elementId, @"%@ %@", name, connection.elementId);
			XCTAssertEqualObjects(flow.name, connection.name, @"%@ %@", name, connection.elementId);
			XCTAssertEqual(flow.isAssociation, connection.isAssociation, @"%@ %@", name, connection.elementId);
			XCTAssertEqual(flow.isDefault, connection.isDefault, @"%@ %@", name, connection.elementId);
			XCTAssertEqual(flow.hasCondition, connection.hasCondition, @"%@ %@", name, connection.elementId);
			XCTAssertTrue(NSEqualRects(flow.labelBounds, connection.labelBounds), @"%@ %@", name, connection.elementId);
			/* The diagram draws a flow it gives no route from centre to
			 * centre; the model keeps what the file says. */
			if ([flow.waypoints count] > 0) {
				XCTAssertEqualObjects(flow.waypoints, connection.waypoints, @"%@ %@", name, connection.elementId);
			}
			XCTAssertTrue([flow.source.outgoing containsObject:flow], @"%@ %@", name, connection.elementId);
			XCTAssertTrue([flow.target.incoming containsObject:flow], @"%@ %@", name, connection.elementId);
		}
		XCTAssertEqualObjects(model.pool.elementId, diagram.pool.elementId, @"%@", name);
		XCTAssertEqualObjects([model.lanes valueForKey:@"elementId"], [diagram.lanes valueForKey:@"elementId"], @"%@", name);
		XCTAssertEqualObjects([model.leafLanes valueForKey:@"elementId"], [diagram.leafLanes valueForKey:@"elementId"], @"%@", name);
		XCTAssertEqualObjects([model.otherPools valueForKey:@"elementId"], [diagram.otherPools valueForKey:@"elementId"], @"%@", name);
		for (WKDLane *lane in diagram.lanes) {
			WKDLane *modelLane = [model laneWithId:lane.elementId];
			XCTAssertEqualObjects(modelLane.flowNodeIds, lane.flowNodeIds, @"%@ %@", name, lane.elementId);
			XCTAssertTrue(NSEqualRects(modelLane.bounds, lane.bounds), @"%@ %@", name, lane.elementId);
			XCTAssertEqual(modelLane.horizontal, lane.horizontal, @"%@ %@", name, lane.elementId);
			XCTAssertEqualObjects(modelLane.parent.elementId, lane.parent.elementId, @"%@ %@", name, lane.elementId);
		}
		XCTAssertEqual(model.needsLayout, diagram.needsLayout, @"%@", name);
		XCTAssertTrue(NSEqualRects(model.contentBounds, diagram.contentBounds), @"%@", name);
	}
}

- (void)testAnUnchangedModelWritesNothing
{
	NSDictionary *documents = [self documents];
	for (NSString *name in documents) {
		NSString *text = [documents objectForKey:name];
		NSXMLDocument *document = [self parse:text];
		NSString *before = [document XMLString];
		WKDModel *model = [WKDModel modelOfDocument:document];
		XCTAssertFalse(model.hasChanges, @"%@", name);
		[model write];
		XCTAssertEqualObjects([document XMLString], before, @"%@", name);
	}
}

/* Every element written from what the model holds says what the file
 * says: the writer leaves the carrier as it was read. */
- (void)testEverythingWrittenAgainIsTheSame
{
	NSDictionary *documents = [self documents];
	for (NSString *name in documents) {
		NSString *text = [documents objectForKey:name];
		NSXMLDocument *document = [self parse:text];
		NSString *before = [document XMLString];
		WKDModel *model = [WKDModel modelOfDocument:document];
		[model markEverythingChanged];
		XCTAssertTrue(model.hasChanges, @"%@", name);
		[model write];
		XCTAssertFalse(model.hasChanges, @"%@", name);
		XCTAssertEqualObjects([document XMLString], before, @"%@", name);
	}
}

- (void)testLinksGoBothWays
{
	WKDModel *model = [WKDModel modelOfDocument:[self parse:WKDModellerFile]];
	WKDNode *review = [model nodeWithId:@"review"];
	XCTAssertEqualObjects([review.incoming valueForKey:@"elementId"], @[ @"f1" ]);
	XCTAssertEqualObjects([review.outgoing valueForKey:@"elementId"], @[ @"f2" ]);
	XCTAssertEqualObjects([review.attached valueForKey:@"elementId"], @[ @"late" ]);
	XCTAssertEqual([model nodeWithId:@"late"].host, review);
	WKDNode *ship = [model nodeWithId:@"ship"];
	XCTAssertEqualObjects([ship.children valueForKey:@"elementId"], (@[ @"shipStart", @"pack", @"shipEnd" ]));
	XCTAssertEqual([model nodeWithId:@"pack"].parent, ship);
	WKDNode *ok = [model nodeWithId:@"ok"];
	XCTAssertEqualObjects(ok.defaultFlow.elementId, @"f4");
	XCTAssertTrue([model flowWithId:@"f4"].isDefault);
	XCTAssertFalse([model flowWithId:@"f3"].isDefault);
	XCTAssertTrue([model flowWithId:@"f3"].hasCondition);
}

/* A change writes what changed, and only that: read again, the document
 * gives the model as changed. */
- (void)testAChangeWritesWhatChanged
{
	NSXMLDocument *document = [self parse:WKDModellerFile];
	WKDModel *model = [WKDModel modelOfDocument:document];
	WKDNode *review = [model nodeWithId:@"review"];
	WKDNode *pack = [model nodeWithId:@"pack"];
	NSRect moved = NSOffsetRect(review.bounds, 40, 10);
	review.bounds = moved;
	review.name = @"Check";
	[review changed];
	/* f2 now leaves from pack: both ends' lists change. */
	WKDFlow *f2 = [model flowWithId:@"f2"];
	[model setSource:pack ofFlow:f2];
	[model write];

	WKDModel *again = [WKDModel modelOfDocument:[self parse:[document XMLString]]];
	WKDNode *reviewAgain = [again nodeWithId:@"review"];
	XCTAssertTrue(NSEqualRects(reviewAgain.bounds, moved));
	XCTAssertEqualObjects(reviewAgain.name, @"Check");
	XCTAssertEqualObjects([reviewAgain.outgoing valueForKey:@"elementId"], @[]);
	XCTAssertEqualObjects([[again nodeWithId:@"pack"].outgoing valueForKey:@"elementId"], (@[ @"s2", @"f2" ]));
	XCTAssertEqualObjects(WKDChildText(reviewAgain.element, WKDBpmnNamespace, @"outgoing"), nil);
	XCTAssertEqualObjects([[again flowWithId:@"f2"].source elementId], @"pack");
	/* What the model does not hold is where it was. */
	XCTAssertNotNil(WKDChild(reviewAgain.element, WKDBpmnNamespace, @"extensionElements"));
	XCTAssertEqualObjects([[again nodeWithId:@"late"].host elementId], @"review");
}

/* The editor's model lasts: an element is the same object after a change,
 * an undo and a redo, its values and links those of the document. */
- (void)testTheEditorsModelLasts
{
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	[undo setGroupsByEvent:NO];
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:[self parse:WKDModellerFile] undoManager:undo];
	WKDModel *model = editor.model;
	WKDNode *review = [model nodeWithId:@"review"];
	NSRect before = review.bounds;
	[undo beginUndoGrouping];
	[editor moveElements:@[ @"review" ] by:NSMakeSize(30, 0)];
	[undo endUndoGrouping];
	XCTAssertEqual(editor.model, model);
	XCTAssertEqual([model nodeWithId:@"review"], review);
	XCTAssertEqual(NSMinX(review.bounds), NSMinX(before) + 30);
	XCTAssertEqual([model nodeWithId:@"late"].host, review);
	[undo undo];
	XCTAssertEqual([model nodeWithId:@"review"], review);
	XCTAssertTrue(NSEqualRects(review.bounds, before));
	[undo redo];
	XCTAssertEqual([model nodeWithId:@"review"], review);
	XCTAssertEqual(NSMinX(review.bounds), NSMinX(before) + 30);
	[undo beginUndoGrouping];
	NSString *taskId = [editor insertNodeOfType:@"userTask" eventDefinition:nil at:NSMakePoint(600, 400) error:NULL];
	[undo endUndoGrouping];
	XCTAssertNotNil([model nodeWithId:taskId]);
	[undo beginUndoGrouping];
	[editor deleteElements:@[ @"review" ]];
	[undo endUndoGrouping];
	XCTAssertNil([model nodeWithId:@"review"]);
	XCTAssertNil([model nodeWithId:@"late"].host);
}

/* A journalled step on the model, undone and redone: undo gives back the
 * exact XML, redo the XML after the step, and the model agrees with the
 * document read afresh each time. */
- (void)checkStep:(void (^)(WKDModel *model))step on:(NSString *)text name:(NSString *)name
{
	NSXMLDocument *document = [self parse:text];
	WKDModel *model = [WKDModel modelOfDocument:document];
	NSString *before = [document XMLString];
	[model.journal begin];
	step(model);
	[model write];
	WKDJournalStep *done = [model.journal end];
	NSString *after = [document XMLString];
	XCTAssertNotEqualObjects(after, before, @"%@ changed the document", name);
	XCTAssertNil([model disagreementWith:[WKDModel modelOfDocument:[self parse:after]]], @"%@", name);
	WKDJournalStep *redo = [model.journal undo:done];
	XCTAssertEqualObjects([document XMLString], before, @"%@ undone: %@", name, WKDFirstDifference([document XMLString], before));
	XCTAssertNil([model disagreementWith:[WKDModel modelOfDocument:[self parse:[document XMLString]]]], @"%@ undone", name);
	WKDJournalStep *again = [model.journal undo:redo];
	XCTAssertEqualObjects([document XMLString], after, @"%@ redone: %@", name, WKDFirstDifference([document XMLString], after));
	XCTAssertNil([model disagreementWith:[WKDModel modelOfDocument:[self parse:[document XMLString]]]], @"%@ redone", name);
	[model.journal undo:again];
	XCTAssertEqualObjects([document XMLString], before, @"%@ undone again: %@", name, WKDFirstDifference([document XMLString], before));
}

- (void)testJournalledStepsUndoToTheExactXML
{
	[self checkStep:^(WKDModel *model) {
		WKDNode *review = [model nodeWithId:@"review"];
		[review willChange];
		review.bounds = NSOffsetRect(review.bounds, 25, 5);
		[review willChange];
		review.name = @"Check";
	} on:WKDModellerFile name:@"a move and a rename"];
	[self checkStep:^(WKDModel *model) {
		[model removeNode:[model nodeWithId:@"review"]];
	} on:WKDModellerFile name:@"a node removed with its flows and boundary event"];
	[self checkStep:^(WKDModel *model) {
		[model removeNode:[model nodeWithId:@"ship"]];
	} on:WKDModellerFile name:@"a subprocess removed with what it holds"];
	[self checkStep:^(WKDModel *model) {
		WKDNode *task = [model makeNodeOfType:@"userTask" elementId:@"Activity_new" in:nil];
		task.bounds = NSMakeRect(500, 300, 100, 80);
		task.hasBounds = YES;
		WKDFlow *flow = [model makeFlowFrom:[model nodeWithId:@"start"] to:task elementId:@"Flow_new" association:NO];
		flow.waypoints = @[ [NSValue valueWithPoint:NSMakePoint(200, 120)], [NSValue valueWithPoint:NSMakePoint(500, 340)] ];
	} on:WKDModellerFile name:@"a node and a flow made"];
	[self checkStep:^(WKDModel *model) {
		WKDFlow *f2 = [model flowWithId:@"f2"];
		[model setTarget:[model nodeWithId:@"done"] ofFlow:f2];
		[model setDefaultFlow:[model flowWithId:@"f3"] ofNode:[model nodeWithId:@"ok"]];
	} on:WKDModellerFile name:@"a flow reconnected and a default changed"];
}

@end

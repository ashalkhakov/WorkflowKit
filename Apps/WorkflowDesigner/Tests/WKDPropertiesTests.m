#import <XCTest/XCTest.h>
#import "WKDEditor.h"
#import "WKDProperties.h"
#import "WKDXML.h"
#import "WKDFixtures.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

@interface WKDPropertiesTests : XCTestCase
@end

@implementation WKDPropertiesTests

- (WKDEditor *)editorOf:(NSString *)xml
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(xml) undoManager:nil];
}

/* The property of that label among the element's sections. */
- (WKDProperty *)property:(NSString *)label of:(NSString *)elementId in:(WKDEditor *)editor
{
	for (WKDSection *section in WKDSectionsFor(editor, elementId)) {
		for (WKDProperty *property in section.properties) {
			if ([property.label isEqualToString:label]) {
				return property;
			}
		}
	}
	XCTFail(@"%@ has no %@", elementId, label);
	return nil;
}

- (void)set:(NSString *)label of:(NSString *)elementId to:(NSString *)value in:(WKDEditor *)editor
{
	NSString *reason = nil;
	XCTAssertTrue([[self property:label of:elementId in:editor] setValue:value in:editor of:elementId error:&reason],
	              @"%@: %@", label, reason);
}

- (NSString *)get:(NSString *)label of:(NSString *)elementId in:(WKDEditor *)editor
{
	return [[self property:label of:elementId in:editor] valueIn:editor of:elementId];
}

- (WFProcessDefinition *)engineRead:(WKDEditor *)editor
{
	NSError *error = nil;
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:[editor.document XMLString] error:&error];
	XCTAssertNotNil(definition, @"%@\n%@", error, [editor.document XMLString]);
	return definition;
}

- (void)testEachKindHasItsSections
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	NSArray *(^titles)(NSString *) = ^NSArray *(NSString *elementId) {
		return [WKDSectionsFor(editor, elementId) valueForKey:@"title"];
	};
	XCTAssertEqualObjects(titles(@"review"), (@[ @"General", @"Assignment", @"Form", @"Input/Output", @"Multi-instance",
	                                             @"Listeners", @"Continuation" ]));
	XCTAssertEqualObjects(titles(@"f3"), (@[ @"General", @"Flow", @"Listeners" ]));
	XCTAssertEqualObjects(titles(@"late"), (@[ @"General", @"Event", @"Listeners", @"Continuation" ]));
	XCTAssertEqualObjects(titles(@"order"), (@[ @"Process", @"Starting", @"Running", @"Listeners" ]));
	XCTAssertEqualObjects(titles(@"start"), (@[ @"General", @"Form", @"Listeners", @"Continuation" ]));
	XCTAssertEqualObjects(titles(@"nothing"), @[]);
}

- (void)testAttributesAreReadAndWritten
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	XCTAssertEqualObjects([self get:@"Candidate groups" of:@"review" in:editor], @"clerks");
	[self set:@"Assignee" of:@"review" to:@"ann" in:editor];
	[self set:@"Candidate groups" of:@"review" to:@"" in:editor];
	[self set:@"Name" of:@"review" to:@"Review the order" in:editor];
	NSXMLElement *review = [editor elementWithId:@"review"];
	XCTAssertEqualObjects(WKDAttribute(review, @"camunda:assignee"), @"ann");
	XCTAssertNil(WKDAttribute(review, @"camunda:candidateGroups"), @"emptied, it is gone");
	XCTAssertEqualObjects([editor.diagram shapeWithId:@"review"].name, @"Review the order");
	XCTAssertEqualObjects([[self engineRead:editor] nodeWithId:@"review"].name, @"Review the order");
}

- (void)testRenamingCarriesTheReferences
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	NSString *reason = nil;
	XCTAssertFalse([[self property:@"Id" of:@"ok" in:editor] setValue:@"review" in:editor of:@"ok" error:&reason]);
	XCTAssertTrue([reason rangeOfString:@"another"].location != NSNotFound, @"%@", reason);
	XCTAssertFalse([[self property:@"Id" of:@"ok" in:editor] setValue:@"1st" in:editor of:@"ok" error:&reason]);
	[self set:@"Id" of:@"ok" to:@"checked" in:editor];
	[self set:@"Id" of:@"f4" to:@"refusal" in:editor];
	WKDDiagram *diagram = editor.diagram;
	XCTAssertNotNil([diagram shapeWithId:@"checked"]);
	XCTAssertEqual([diagram connectionWithId:@"f2"].target, [diagram shapeWithId:@"checked"]);
	XCTAssertTrue([diagram connectionWithId:@"refusal"].isDefault, @"the gateway's default follows the flow");
	NSString *xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"bpmnElement=\"checked\""].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"<bpmn:outgoing>refusal</bpmn:outgoing>"].location != NSNotFound);
	XCTAssertTrue(NSEqualRects([diagram shapeWithId:@"checked"].bounds, NSMakeRect(360, 93, 50, 50)), @"its shape too");
	[self engineRead:editor];
}

- (void)testAFlowsConditionAndDefault
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	XCTAssertEqualObjects([self get:@"Condition" of:@"f3" in:editor], @"=fine");
	XCTAssertEqualObjects([self get:@"Default flow" of:@"f4" in:editor], @"true");
	[self set:@"Condition" of:@"f4" to:@"=not(fine)" in:editor];
	[self set:@"Default flow" of:@"f3" to:@"true" in:editor];
	XCTAssertEqualObjects([self get:@"Default flow" of:@"f4" in:editor], @"false", @"one default at a time");
	[self set:@"Condition" of:@"f3" to:@"" in:editor];
	NSXMLElement *f4 = [editor elementWithId:@"f4"];
	NSXMLElement *condition = WKDChild(f4, WKDBpmnNamespace, @"conditionExpression");
	XCTAssertEqualObjects([condition stringValue], @"=not(fine)");
	XCTAssertEqualObjects(WKDAttribute(condition, @"xsi:type"), @"bpmn:tFormalExpression");
	WFProcessDefinition *definition = [self engineRead:editor];
	XCTAssertEqualObjects(((WFGateway *)[definition nodeWithId:@"ok"]).defaultFlowId, @"f3");
}

/* Where the engine reads an expression, the inspector colours and checks
 * one, as the engine reads it there; and what the empty fields suggest is
 * something it reads. */
- (void)testExpressionsAreMarkedWhereTheEngineReadsThem
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	WKDProperty *condition = [self property:@"Condition" of:@"f3" in:editor];
	XCTAssertTrue(condition.holdsExpression);
	XCTAssertEqual(condition.place, WFExpressionPlaceExpression);
	WKDProperty *assignee = [self property:@"Assignee" of:@"review" in:editor];
	XCTAssertTrue(assignee.holdsExpression);
	XCTAssertEqual(assignee.place, WFExpressionPlaceAttribute);
	XCTAssertFalse([self property:@"Name" of:@"review" in:editor].holdsExpression);
	XCTAssertTrue([self property:@"When" of:@"late" in:editor].holdsExpression);
	[self set:@"Instances" of:@"review" to:@"parallel" in:editor];
	for (NSString *label in @[ @"Collection", @"Cardinality", @"Completion" ]) {
		WKDProperty *property = [self property:label of:@"review" in:editor];
		XCTAssertTrue(property.holdsExpression, @"%@", label);
		XCTAssertEqual(property.place, WFExpressionPlaceExpression, @"%@", label);
	}
	for (NSString *elementId in @[ @"f3", @"review", @"late", @"start" ]) {
		for (WKDSection *section in WKDSectionsFor(editor, elementId)) {
			for (WKDProperty *property in section.properties) {
				if (property.holdsExpression && property.placeholder != nil) {
					XCTAssertNil([WFFeelExpression problemInText:property.placeholder place:property.place],
					             @"%@'s %@: %@", elementId, property.label, property.placeholder);
				}
			}
		}
	}
}

- (void)testAServiceTaskBecomesAnExternalTask
{
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:[WKDEditor newProcessDocument] undoManager:nil];
	NSString *task = [editor insertNodeOfType:@"serviceTask" eventDefinition:nil at:NSMakePoint(400, 200) error:NULL];
	NSString *end = [editor insertNodeOfType:@"endEvent" eventDefinition:nil at:NSMakePoint(600, 200) error:NULL];
	[editor connect:@"StartEvent_1" to:task error:NULL];
	[editor connect:task to:end error:NULL];
	[self set:@"Implementation" of:task to:@"external" in:editor];
	[self set:@"Topic" of:task to:@"charge" in:editor];
	XCTAssertEqualObjects([self get:@"Implementation" of:task in:editor], @"external");
	[self engineRead:editor];
	[self set:@"Implementation" of:task to:@"class" in:editor];
	XCTAssertNil(WKDAttribute([editor elementWithId:task], @"camunda:topic"), @"a delegate has no topic");
	XCTAssertNil(WKDAttribute([editor elementWithId:task], @"camunda:type"));
}

- (void)testATimersKindAndText
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	XCTAssertEqualObjects([self get:@"Timer" of:@"late" in:editor], @"timeDuration");
	XCTAssertEqualObjects([self get:@"When" of:@"late" in:editor], @"PT1H");
	[self set:@"Timer" of:@"late" to:@"timeCycle" in:editor];
	XCTAssertEqualObjects([self get:@"When" of:@"late" in:editor], @"PT1H", @"the text goes with it");
	[self set:@"When" of:@"late" to:@"R2/PT30M" in:editor];
	[self set:@"Interrupting" of:@"late" to:@"true" in:editor];
	NSXMLElement *late = [editor elementWithId:@"late"];
	NSXMLElement *timer = WKDChild(late, WKDBpmnNamespace, @"timerEventDefinition");
	XCTAssertNil(WKDChild(timer, WKDBpmnNamespace, @"timeDuration"));
	XCTAssertEqualObjects(WKDChildText(timer, WKDBpmnNamespace, @"timeCycle"), @"R2/PT30M");
	XCTAssertNil(WKDAttribute(late, @"cancelActivity"), @"interrupting is the default");
}

- (void)testAMessageIsReferredToByName
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	NSString *catch = [editor insertNodeOfType:@"intermediateCatchEvent" eventDefinition:@"messageEventDefinition"
	                                        at:NSMakePoint(900, 300) error:NULL];
	[self set:@"Message" of:catch to:@"paid" in:editor];
	[self set:@"Message" of:catch to:@"paid" in:editor];
	XCTAssertEqualObjects([self get:@"Message" of:catch in:editor], @"paid");
	NSArray *messages = WKDChildren([editor.document rootElement], WKDBpmnNamespace, @"message");
	XCTAssertEqual([messages count], (NSUInteger)1);
	XCTAssertEqualObjects(WKDAttribute(messages[0], @"name"), @"paid");
	NSXMLElement *definition = WKDChild([editor elementWithId:catch], WKDBpmnNamespace, @"messageEventDefinition");
	XCTAssertEqualObjects(WKDAttribute(definition, @"messageRef"), WKDAttribute(messages[0], @"id"));
	/* Another event naming the same message shares it. */
	NSString *other = [editor insertNodeOfType:@"intermediateCatchEvent" eventDefinition:@"messageEventDefinition"
	                                        at:NSMakePoint(1000, 300) error:NULL];
	[self set:@"Message" of:other to:@"paid" in:editor];
	XCTAssertEqual([WKDChildren([editor.document rootElement], WKDBpmnNamespace, @"message") count], (NSUInteger)1);
}

- (void)testMultiInstanceAndContinuations
{
	WKDEditor *editor = [self editorOf:WKDModellerFile];
	[self set:@"Instances" of:@"review" to:@"sequential" in:editor];
	[self set:@"Collection" of:@"review" to:@"${clerks}" in:editor];
	[self set:@"Element variable" of:@"review" to:@"clerk" in:editor];
	[self set:@"Asynchronous before" of:@"review" to:@"true" in:editor];
	[self set:@"Exclusive" of:@"review" to:@"false" in:editor];
	[self set:@"Retry cycle" of:@"review" to:@"R5/PT1M" in:editor];
	XCTAssertEqualObjects([editor.diagram shapeWithId:@"review"].loop, @"sequential");
	NSXMLElement *review = [editor elementWithId:@"review"];
	XCTAssertEqualObjects([[[review children] lastObject] localName], @"multiInstanceLoopCharacteristics",
	                      @"loop characteristics last, as BPMN's schema has them");
	XCTAssertEqualObjects([self get:@"Retry cycle" of:@"review" in:editor], @"R5/PT1M");
	XCTAssertTrue([[[editor.document XMLString] substringFromIndex:0] rangeOfString:@"camunda:inputParameter"].location
	              != NSNotFound, @"the extensions there are kept");
	WFProcessDefinition *definition = [self engineRead:editor];
	WFFlowNode *node = [definition nodeWithId:@"review"];
	XCTAssertTrue(node.asyncBefore);
	XCTAssertFalse(node.exclusive);
	XCTAssertEqualObjects(node.retryTimeCycle, @"R5/PT1M");
	XCTAssertNotNil(node.multiInstance);
	[self set:@"Instances" of:@"review" to:@"" in:editor];
	XCTAssertNil(WKDChild([editor elementWithId:@"review"], WKDBpmnNamespace, @"multiInstanceLoopCharacteristics"));
}

- (void)testTheProcessItself
{
	WKDEditor *editor = [self editorOf:WKDUndrawnFile];
	[self set:@"Starter groups" of:@"purchase" to:@"buyers" in:editor];
	[self set:@"Name" of:@"purchase" to:@"Purchase" in:editor];
	XCTAssertEqualObjects([self get:@"Executable" of:@"purchase" in:editor], @"true");
	WFProcessDefinition *definition = [self engineRead:editor];
	XCTAssertEqualObjects(definition.name, @"Purchase");
}

- (void)testAPropertyIsOneUndoStep
{
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	[undo setGroupsByEvent:NO];
	WKDEditor *editor = [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:undo];
	NSString *before = [editor.document XMLString];
	[self set:@"Candidate groups" of:@"review" to:@"clerks" in:editor];
	XCTAssertFalse([undo canUndo], @"the value it has already: no change");
	[undo beginUndoGrouping];
	[self set:@"Id" of:@"ok" to:@"checked" in:editor];
	[undo endUndoGrouping];
	[undo undo];
	XCTAssertEqualObjects([editor.document XMLString], before);
}

@end

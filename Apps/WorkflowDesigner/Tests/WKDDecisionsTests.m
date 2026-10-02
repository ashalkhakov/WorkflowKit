#import <XCTest/XCTest.h>
#import "WKDDecisions.h"
#import "WKDXML.h"
#import "WKDFixtures.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

/* A DMN file's decisions as the decision editor reads and changes them,
 * and the engine reading what it writes. */
@interface WKDDecisionsTests : XCTestCase
@end

@implementation WKDDecisionsTests

- (WKDDmnEditor *)dishes
{
	return [[WKDDmnEditor alloc] initWithDocument:WKDParse(WKDDecisionsFile) undoManager:nil];
}

/* The engine's decisions, by key, from the file as it is written. */
static NSDictionary<NSString *, WFDecisionDefinition *> *
WKDEngineReads(WKDDmnEditor *editor, NSError **error)
{
	NSString *xml = [editor.document XMLStringWithOptions:NSXMLNodePrettyPrint];
	NSArray *decisions = [WFDmnReader decisionsFromXMLString:xml error:error];
	NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
	for (WFDecisionDefinition *decision in decisions) {
		[byKey setObject:decision forKey:decision.key];
	}
	return decisions != nil ? byKey : nil;
}

static NSArray *
WKDEntries(WKDDmnEditor *editor, NSString *decisionId)
{
	NSMutableArray *rows = [NSMutableArray array];
	for (WKDDmnRule *rule in [editor decisionWithId:decisionId].rules) {
		[rows addObject:rule.entries];
	}
	return rows;
}

- (void)testAModellersFileIsRead
{
	WKDDmnEditor *editor = [self dishes];
	XCTAssertEqual([editor.decisions count], (NSUInteger)2, @"input data is not a decision");
	WKDDmnDecision *dish = [editor decisionWithId:@"dish"];
	XCTAssertTrue(dish.isTable);
	XCTAssertEqualObjects(dish.hitPolicy, @"FIRST");
	XCTAssertNil(dish.aggregation);
	XCTAssertEqual([dish.columns count], (NSUInteger)3);
	WKDDmnColumn *guests = [dish.inputs objectAtIndex:1];
	XCTAssertEqualObjects(guests.expression, @"guestCount");
	XCTAssertEqualObjects(guests.typeRef, @"integer");
	XCTAssertEqualObjects(guests.inputVariable, @"count");
	XCTAssertEqualObjects([dish.outputs[0] name], @"dish");
	NSArray *expected = @[ @[ @"\"Winter\"", @"<= 8", @"\"Roastbeef\"" ], @[ @"-", @"", @"\"Stew\"" ] ];
	XCTAssertEqualObjects(WKDEntries(editor, @"dish"), expected);
	XCTAssertEqualObjects([dish.rules[0] annotation], @"Warm");

	WKDDmnDecision *drink = [editor decisionWithId:@"drink"];
	XCTAssertFalse(drink.isTable);
	XCTAssertEqualObjects(drink.variableName, @"drink");
	XCTAssertEqualObjects(drink.expression, @"if dish = \"Stew\" then \"Beer\" else \"Wine\"");
	NSArray *required = @[ @"dish" ];
	XCTAssertEqualObjects(drink.required, required, @"a requirement on input data is not a decision's");
}

- (void)testANewFileIsOneTableTheEngineReadsOnceItHasAnExpression
{
	WKDDmnEditor *editor = [[WKDDmnEditor alloc] initWithDocument:[WKDDmnEditor newDecisionsDocument] undoManager:nil];
	XCTAssertEqual([editor.decisions count], (NSUInteger)1);
	WKDDmnDecision *decision = editor.decisions[0];
	XCTAssertEqual([decision.inputs count], (NSUInteger)1);
	XCTAssertEqual([decision.outputs count], (NSUInteger)1);
	NSError *error = nil;
	XCTAssertNil(WKDEngineReads(editor, &error), @"an input without an expression");
	[editor setColumn:0 property:@"expression" to:@"amount" of:decision.decisionId];
	[editor setColumn:0 property:@"typeRef" to:@"integer" of:decision.decisionId];
	[editor insertRuleAt:0 of:decision.decisionId];
	[editor setEntry:@"> 100" rule:0 column:0 of:decision.decisionId];
	[editor setEntry:@"\"big\"" rule:0 column:1 of:decision.decisionId];
	WFDecisionDefinition *read = [WKDEngineReads(editor, &error) objectForKey:decision.decisionId];
	XCTAssertNotNil(read, @"%@", error);
	error = nil;
	WFDecisionResult *result = [read evaluateWithVariables:@{ @"amount": @500 } inputs:nil error:&error];
	XCTAssertEqualObjects([result singleEntry:NULL], @"big", @"%@", error);
	NSString *xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"<decision "].location != NSNotFound, @"in the default namespace: %@", xml);
	XCTAssertTrue([xml rangeOfString:@"dmndi:DMNShape"].location != NSNotFound, @"with its shape: %@", xml);
}

- (void)testColumnsComeGoAndMoveWithTheirEntries
{
	WKDDmnEditor *editor = [self dishes];
	XCTAssertEqual([editor insertColumn:NO at:0 of:@"dish"], (NSUInteger)0);
	[editor setColumn:0 property:@"expression" to:@"vegetarian" of:@"dish"];
	[editor setColumn:0 property:@"typeRef" to:@"boolean" of:@"dish"];
	[editor setEntry:@"true" rule:1 column:0 of:@"dish"];
	NSArray *added = @[ @[ @"", @"\"Winter\"", @"<= 8", @"\"Roastbeef\"" ], @[ @"true", @"-", @"", @"\"Stew\"" ] ];
	XCTAssertEqualObjects(WKDEntries(editor, @"dish"), added);

	XCTAssertEqual([editor insertColumn:YES at:5 of:@"dish"], (NSUInteger)4, @"after the last output");
	WKDDmnDecision *dish = [editor decisionWithId:@"dish"];
	XCTAssertEqualObjects([dish.outputs[1] name], @"result", @"a name of its own, as the table has several");
	[editor setEntry:@"10" rule:0 column:4 of:@"dish"];

	[editor moveColumn:0 to:2 of:@"dish"];
	NSArray *moved = @[ @[ @"\"Winter\"", @"<= 8", @"", @"\"Roastbeef\"", @"10" ],
	                    @[ @"-", @"", @"true", @"\"Stew\"", @"" ] ];
	XCTAssertEqualObjects(WKDEntries(editor, @"dish"), moved);
	[editor moveColumn:2 to:4 of:@"dish"];
	XCTAssertEqualObjects(WKDEntries(editor, @"dish"), moved, @"an input stays among the inputs");
	[editor moveColumn:4 to:3 of:@"dish"];
	XCTAssertEqualObjects([[editor decisionWithId:@"dish"].outputs[0] name], @"result");

	[editor deleteColumn:1 of:@"dish"];
	NSArray *deleted = @[ @[ @"\"Winter\"", @"", @"10", @"\"Roastbeef\"" ], @[ @"-", @"true", @"", @"\"Stew\"" ] ];
	XCTAssertEqualObjects(WKDEntries(editor, @"dish"), deleted);
	NSError *error = nil;
	WFDecisionDefinition *read = [WKDEngineReads(editor, &error) objectForKey:@"dish"];
	XCTAssertNotNil(read, @"%@", error);
	XCTAssertEqual([read.table.inputs count], (NSUInteger)2);
	XCTAssertEqual([read.table.outputs count], (NSUInteger)2);
	WFDecisionResult *result = [read evaluateWithVariables:@{ @"season": @"Summer", @"vegetarian": @YES }
	                                                inputs:nil error:&error];
	NSDictionary *expected = @{ @"dish": @"Stew" };
	XCTAssertEqualObjects([result singleResult:NULL], expected, @"%@", error);
}

- (void)testRulesAreAddedCopiedMovedAndDeleted
{
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	[undo setGroupsByEvent:NO];
	WKDDmnEditor *editor = [[WKDDmnEditor alloc] initWithDocument:WKDParse(WKDDecisionsFile) undoManager:undo];
	[undo beginUndoGrouping];
	[editor insertRuleAt:1 of:@"dish"];
	[undo endUndoGrouping];
	NSArray *blank = @[ @"", @"", @"" ];
	XCTAssertEqualObjects(WKDEntries(editor, @"dish")[1], blank);
	[undo beginUndoGrouping];
	[editor duplicateRule:0 of:@"dish"];
	[undo endUndoGrouping];
	WKDDmnDecision *dish = [editor decisionWithId:@"dish"];
	XCTAssertEqual([dish.rules count], (NSUInteger)4);
	XCTAssertEqualObjects([dish.rules[1] entries], [dish.rules[0] entries]);
	XCTAssertEqualObjects([dish.rules[1] annotation], @"Warm");
	XCTAssertFalse([[dish.rules[1] ruleId] isEqualToString:[dish.rules[0] ruleId]], @"an id of its own");

	[undo beginUndoGrouping];
	[editor moveRule:3 to:0 of:@"dish"];
	[undo endUndoGrouping];
	XCTAssertEqualObjects([[editor decisionWithId:@"dish"].rules[0] ruleId], @"other");
	[undo beginUndoGrouping];
	[editor deleteRules:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)] of:@"dish"];
	[undo endUndoGrouping];
	NSArray *left = @[ @"other", [dish.rules[2] ruleId] ];
	NSMutableArray *ids = [NSMutableArray array];
	for (WKDDmnRule *rule in [editor decisionWithId:@"dish"].rules) {
		[ids addObject:rule.ruleId];
	}
	XCTAssertEqualObjects(ids, left);
	[undo beginUndoGrouping];
	[editor setAnnotation:@"Whatever is left" rule:0 of:@"dish"];
	[undo endUndoGrouping];
	XCTAssertEqualObjects([[editor decisionWithId:@"dish"].rules[0] annotation], @"Whatever is left");
	NSError *error = nil;
	XCTAssertNotNil(WKDEngineReads(editor, &error), @"its description before its entries: %@", error);

	for (NSUInteger i = 0; i < 5; i++) {
		[undo undo];
	}
	XCTAssertEqualObjects([editor.document XMLString], [WKDParse(WKDDecisionsFile) XMLString], @"undone, as it was");
}

- (void)testTheHitPolicyIsWrittenAsTheEngineReadsIt
{
	WKDDmnEditor *editor = [self dishes];
	[editor setHitPolicy:@"COLLECT" aggregation:@"COUNT" of:@"dish"];
	WKDDmnDecision *dish = [editor decisionWithId:@"dish"];
	XCTAssertEqualObjects(dish.hitPolicy, @"COLLECT");
	XCTAssertEqualObjects(dish.aggregation, @"COUNT");
	NSError *error = nil;
	XCTAssertEqual([[WKDEngineReads(editor, &error) objectForKey:@"dish"] table].aggregation,
	               WFCollectAggregationCount, @"%@", error);
	[editor setHitPolicy:@"RULE ORDER" aggregation:@"SUM" of:@"dish"];
	XCTAssertNil([editor decisionWithId:@"dish"].aggregation, @"only with COLLECT");
	[editor setHitPolicy:@"UNIQUE" aggregation:nil of:@"dish"];
	XCTAssertEqualObjects([editor decisionWithId:@"dish"].hitPolicy, @"UNIQUE");
	XCTAssertTrue([[editor.document XMLString] rangeOfString:@"hitPolicy"].location == NSNotFound,
	              @"UNIQUE is what none says");
}

- (void)testRequirementsAreKeptAcyclicAndDrawn
{
	WKDDmnEditor *editor = [self dishes];
	NSString *reason = nil;
	NSArray *cycle = @[ @"drink" ];
	XCTAssertFalse([editor setRequired:cycle of:@"dish" error:&reason]);
	XCTAssertNotNil(reason);
	NSArray *unknown = @[ @"dessert" ];
	XCTAssertFalse([editor setRequired:unknown of:@"dish" error:&reason]);

	NSString *dessert = [editor addDecisionTable:YES withId:@"dessert"];
	XCTAssertEqualObjects(dessert, @"dessert");
	NSString *xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"dmnElementRef=\"dessert\""].location != NSNotFound, @"a shape: %@", xml);
	NSArray *both = @[ @"dish", @"dessert" ];
	XCTAssertTrue([editor setRequired:both of:@"drink" error:&reason], @"%@", reason);
	XCTAssertEqualObjects([editor decisionWithId:@"drink"].required, both);
	xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"requiredInput href=\"#age\""].location != NSNotFound, @"input data's kept");
	XCTAssertTrue([xml rangeOfString:@"DMNEdge"].location != [xml rangeOfString:@"DMNEdge" options:NSBackwardsSearch].location,
	              @"an edge for the new one: %@", xml);

	NSArray *one = @[ @"dessert" ];
	XCTAssertTrue([editor setRequired:one of:@"drink" error:&reason]);
	xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"drinkNeedsDishEdge"].location == NSNotFound, @"its edge went with it");

	XCTAssertTrue([editor renameDecision:@"dessert" to:@"sweet" error:&reason], @"%@", reason);
	XCTAssertEqualObjects([editor decisionWithId:@"drink"].required, @[ @"sweet" ]);
	xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"dmnElementRef=\"sweet\""].location != NSNotFound);
	XCTAssertFalse([editor renameDecision:@"sweet" to:@"drink" error:&reason], @"taken");
	XCTAssertFalse([editor renameDecision:@"sweet" to:@"9lives" error:&reason], @"not a name");

	[editor deleteDecision:@"sweet"];
	XCTAssertEqualObjects([editor decisionWithId:@"drink"].required, @[]);
	xml = [editor.document XMLString];
	XCTAssertTrue([xml rangeOfString:@"sweet"].location == NSNotFound, @"no trace: %@", xml);
}

- (void)testALiteralExpressionsVariable
{
	WKDDmnEditor *editor = [self dishes];
	NSString *added = [editor addDecisionTable:NO withId:nil];
	XCTAssertFalse([editor decisionWithId:added].isTable);
	[editor setLiteral:@"expression" to:@"guestCount * 2" of:added];
	[editor setLiteral:@"variableName" to:@"plates" of:added];
	[editor setLiteral:@"variableType" to:@"integer" of:added];
	WKDDmnDecision *decision = [editor decisionWithId:added];
	XCTAssertEqualObjects(decision.variableName, @"plates");
	XCTAssertEqualObjects(decision.variableType, @"integer");
	NSError *error = nil;
	WFDecisionDefinition *read = [WKDEngineReads(editor, &error) objectForKey:added];
	XCTAssertNotNil(read, @"%@", error);
	WFDecisionResult *result = [read evaluateWithVariables:@{ @"guestCount": @3 } inputs:nil error:&error];
	NSDictionary *expected = @{ @"plates": [NSDecimalNumber decimalNumberWithString:@"6"] };
	XCTAssertEqualObjects([result singleResult:NULL], expected, @"%@", error);
	[editor setColumn:0 property:@"label" to:@"Nothing" of:added];
	XCTAssertEqualObjects([editor decisionWithId:added].inputs, @[], @"a literal expression has no columns");
}

@end

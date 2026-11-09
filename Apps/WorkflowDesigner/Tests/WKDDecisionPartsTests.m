#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "WKDDecisionDocument.h"
#import "WKDDecisionWindowController.h"
#import "WKDExpressionField.h"
#import "WKDFixtures.h"

/* The decision editor's parts, each from its XIB and connected, following
 * the decision editor they share; and the window that puts them in place. */
@interface WKDDecisionPartsTests : XCTestCase
@end

@implementation WKDDecisionPartsTests

+ (void)setUp
{
	[NSApplication sharedApplication];
}

- (WKDDecisionEditor *)dishes
{
	return [[WKDDecisionEditor alloc] initWithData:[WKDDecisionsFile dataUsingEncoding:NSUTF8StringEncoding]
	                                   undoManager:nil error:NULL];
}

- (void)testWhatIsChosenFollowsTheDecisions
{
	WKDDecisionEditor *editor = [self dishes];
	XCTAssertEqualObjects(editor.decisionId, @"dish", @"the first");
	editor.column = 1;
	XCTAssertEqual(editor.column, (NSUInteger)1);
	[editor.editor deleteColumn:2 of:@"dish"];
	[editor.editor deleteColumn:1 of:@"dish"];
	XCTAssertEqual(editor.column, (NSUInteger)0, @"kept to the columns there are");
	[editor.editor renameDecision:@"dish" to:@"meal" error:NULL];
	XCTAssertEqualObjects(editor.decisionId, @"meal", @"renamed, still chosen");
	[editor.editor deleteDecision:@"meal"];
	XCTAssertEqualObjects(editor.decisionId, @"drink", @"gone: its neighbour");
	XCTAssertNotNil([[WKDDecisionEditor alloc] initNewWithUndoManager:nil].decision);
	NSError *error = nil;
	XCTAssertNil([[WKDDecisionEditor alloc] initWithData:[@"<process/>" dataUsingEncoding:NSUTF8StringEncoding]
	                                         undoManager:nil error:&error]);
	XCTAssertNotNil(error);
}

- (void)testThePartsLoadFromTheirXIBsConnected
{
	WKDDecisionEditor *editor = [self dishes];
	WKDDecisionListViewController *list = [[WKDDecisionListViewController alloc] initWithDecisionEditor:editor];
	XCTAssertNotNil(list.view);
	XCTAssertEqual([list.tableView numberOfRows], (NSInteger)[editor.editor.decisions count]);
	XCTAssertEqual([list.tableView selectedRow], (NSInteger)0, @"the one chosen");

	WKDDecisionDetailViewController *detail = [[WKDDecisionDetailViewController alloc] initWithDecisionEditor:editor];
	XCTAssertNotNil(detail.view);
	XCTAssertEqualObjects([detail.idField stringValue], @"dish");
	XCTAssertFalse([detail.hitPolicy isHidden], @"a table's");
	XCTAssertGreaterThan([detail.hitPolicy numberOfItems], (NSInteger)1);
	XCTAssertGreaterThan([detail.requires numberOfItems], (NSInteger)1, @"the other decisions to check");

	WKDRuleGridViewController *grid = [[WKDRuleGridViewController alloc] initWithDecisionEditor:editor];
	XCTAssertNotNil(grid.view);
	XCTAssertTrue([grid.grid isKindOfClass:[WKDRuleTable class]]);
	XCTAssertEqual([[grid.grid tableColumns] count], [editor.decision.columns count] + 2, @"the numbers, the annotations");
	XCTAssertEqual([grid.grid numberOfRows], (NSInteger)[editor.decision.rules count]);

	WKDColumnViewController *column = [[WKDColumnViewController alloc] initWithDecisionEditor:editor];
	XCTAssertNotNil(column.view);
	XCTAssertTrue([column.labelField isHidden], @"no column chosen");
	editor.column = 1;
	XCTAssertFalse([column.labelField isHidden]);
	XCTAssertTrue([column.expressionField isKindOfClass:[WKDExpressionField class]]);
	XCTAssertEqualObjects(column.expressionField.stringValue, @"guestCount");

	WKDLiteralViewController *literal = [[WKDLiteralViewController alloc] initWithDecisionEditor:editor];
	XCTAssertNotNil(literal.view);
	editor.decisionId = @"drink";
	XCTAssertEqualObjects([literal.variableField stringValue], @"drink");
	XCTAssertTrue([literal.literalField.stringValue hasPrefix:@"if dish"]);
	XCTAssertEqualObjects([detail.idField stringValue], @"drink", @"the detail follows the choice");
	XCTAssertTrue([detail.hitPolicy isHidden], @"a literal has none");
}

- (void)testTheGridsCellsAreTheEntries
{
	WKDDecisionEditor *editor = [self dishes];
	WKDRuleGridViewController *grid = [[WKDRuleGridViewController alloc] initWithDecisionEditor:editor];
	[grid view];
	NSTableColumn *season = [[grid.grid tableColumns] objectAtIndex:1];
	[(id)grid tableView:grid.grid setObjectValue:@"\"Summer\"" forTableColumn:season row:0];
	XCTAssertEqualObjects([editor.decision.rules[0] entries][0], @"\"Summer\"");
	NSUInteger rules = [editor.decision.rules count];
	[grid addRule:nil];
	XCTAssertEqual([editor.decision.rules count], rules + 1);
	XCTAssertEqual([grid.grid numberOfRows], (NSInteger)rules + 1, @"the grid shows it");
	editor.column = 0;
	[grid addInput:nil];
	XCTAssertEqual(editor.column, (NSUInteger)1, @"the column added, after the chosen one, chosen");
	XCTAssertEqual([[grid.grid tableColumns] count], [editor.decision.columns count] + 2);
}

- (void)testTheWindowPutsThePartsInPlace
{
	WKDDecisionDocument *document = [[WKDDecisionDocument alloc] init];
	NSError *error = nil;
	XCTAssertTrue([document readFromData:[WKDDecisionsFile dataUsingEncoding:NSUTF8StringEncoding] ofType:@"DMN"
	                               error:&error], @"%@", error);
	[document makeWindowControllers];
	WKDDecisionWindowController *controller = [[document windowControllers] firstObject];
	XCTAssertNotNil([controller window], @"DecisionWindow.xib");
	for (NSView *host in @[ controller.listHost, controller.detailHost, controller.gridHost, controller.columnHost,
	                        controller.literalHost ]) {
		XCTAssertGreaterThan([[host subviews] count], (NSUInteger)0, @"a part in its host");
	}
	XCTAssertEqual([controller nextResponder], controller.listController, @"the Decision menu's actions in its chain");
	XCTAssertEqual([controller.listController nextResponder], controller.gridController);
	XCTAssertFalse([controller.tablePanel isHidden]);
	XCTAssertTrue([controller.literalHost isHidden]);
	[controller showDecision:@"drink"];
	XCTAssertTrue([controller.tablePanel isHidden]);
	XCTAssertFalse([controller.literalHost isHidden], @"a literal expression's");
	XCTAssertGreaterThan([[controller.statusField stringValue] length], (NSUInteger)0);
	[document close];
}

@end

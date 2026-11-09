#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "WKDDecisionEditor.h"
#import "WKDDecisionListViewController.h"
#import "WKDDecisionDetailViewController.h"
#import "WKDRuleGridViewController.h"
#import "WKDColumnViewController.h"
#import "WKDLiteralViewController.h"
#import "WKDExpressionField.h"
#import "WKDFixtures.h"

/* The decision editor's parts, each from its XIB and connected, following
 * the decision editor they share. */
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

/* The text changed some other way, read again: what is chosen kept where
 * it still is, the parts showing the text as it is. */
- (void)testTheTextIsReadAgain
{
	WKDDecisionEditor *editor = [self dishes];
	editor.decisionId = @"drink";
	WKDLiteralViewController *literal = [[WKDLiteralViewController alloc] initWithDecisionEditor:editor];
	[literal view];
	NSString *text = [[NSString alloc] initWithData:[editor data] encoding:NSUTF8StringEncoding];
	NSError *error = nil;
	XCTAssertTrue([editor readData:[[text stringByReplacingOccurrencesOfString:@"if dish" withString:@"if meal"]
	                                   dataUsingEncoding:NSUTF8StringEncoding] error:&error], @"%@", error);
	XCTAssertEqualObjects(editor.decisionId, @"drink", @"still chosen");
	XCTAssertTrue([literal.literalField.stringValue hasPrefix:@"if meal"], @"shown as it is now");
	XCTAssertFalse([editor readData:[@"<process/>" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
	XCTAssertTrue([literal.literalField.stringValue hasPrefix:@"if meal"], @"nothing changed");
	XCTAssertTrue([editor readData:[[text stringByReplacingOccurrencesOfString:@"\"drink\"" withString:@"\"juice\""]
	                                   dataUsingEncoding:NSUTF8StringEncoding] error:&error], @"%@", error);
	XCTAssertNotNil(editor.decisionId, @"gone: another chosen");
	XCTAssertFalse([editor.decisionId isEqualToString:@"drink"]);
	[editor.editor setName:@"Changed" of:editor.decisionId];
	XCTAssertEqualObjects(editor.decision.name, @"Changed", @"its changes followed");
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

@end

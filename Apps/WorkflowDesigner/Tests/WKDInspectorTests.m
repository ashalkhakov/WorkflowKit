#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "WKDInspectorViewController.h"
#import "WKDInspectorRow.h"
#import "WKDTableRowController.h"
#import "WKDExpressionField.h"
#import "WKDFixtures.h"
#import "WKDXML.h"

@interface WKDInspectorViewController (WKDTesting)
- (NSArray<WKDInspectorRow *> *)testRows;
@end

@implementation WKDInspectorViewController (WKDTesting)
- (NSArray<WKDInspectorRow *> *)testRows
{
	return [self valueForKey:@"_rows"];
}
@end

/* The inspector's rows, each from the XIB of its kind, bound to the
 * section's model: what is set in them is a change, and a change made
 * elsewhere is what they show. */
@interface WKDInspectorTests : XCTestCase
@end

@implementation WKDInspectorTests

+ (void)setUp
{
	[NSApplication sharedApplication];
}

- (WKDProcessEditor *)modeller
{
	return [[WKDProcessEditor alloc] initWithData:[WKDModellerFile dataUsingEncoding:NSUTF8StringEncoding]
	                                  undoManager:nil error:NULL];
}

- (WKDInspectorRow *)row:(NSString *)label of:(WKDInspectorViewController *)inspector
{
	for (WKDInspectorRow *row in [inspector testRows]) {
		if ([row.property.label isEqualToString:label]) {
			return row;
		}
	}
	XCTFail(@"no %@ row", label);
	return nil;
}

- (void)testEachRowIsFromTheXIBOfItsKind
{
	WKDProcessEditor *editor = [self modeller];
	WKDInspectorViewController *inspector = [[WKDInspectorViewController alloc] initWithProcessEditor:editor showingProcess:NO];
	XCTAssertTrue([inspector.view isKindOfClass:[NSScrollView class]]);
	XCTAssertNotNil(inspector.stack);
	XCTAssertEqual([[inspector testRows] count], (NSUInteger)1, @"nothing selected: one line saying so");
	editor.selection.selectedIds = @[ @"review" ];
	XCTAssertEqualObjects(inspector.elementId, @"review");
	XCTAssertGreaterThan([inspector.models count], (NSUInteger)4, @"General, Assignment, Form, Input/Output, ...");
	for (WKDInspectorRow *row in [inspector testRows]) {
		XCTAssertNotNil(row.view, @"%@", row.property.label);
		XCTAssertEqual([row.view superview], inspector.stack);
		if (row.property == nil || row.property.kind == WKDPropertyTable) {
			continue;
		}
		XCTAssertNotNil(row.control, @"%@", row.property.label);
		Class expected = row.property.kind == WKDPropertyCheck || row.property.kind == WKDPropertyButton ? [NSButton class]
			: row.property.kind == WKDPropertyChoice ? [NSPopUpButton class]
			: row.property.kind == WKDPropertyLongText ? [NSTextView class]
			: row.property.holdsExpression ? [WKDExpressionField class] : [NSTextField class];
		XCTAssertTrue([row.control isKindOfClass:expected], @"%@ is a %@", row.property.label, [row.control class]);
	}
	XCTAssertEqualObjects([[self row:@"Name" of:inspector].control stringValue], @"Review");
	NSPopUpButton *instances = [self row:@"Instances" of:inspector].control;
	XCTAssertEqual([instances numberOfItems], (NSInteger)[[self row:@"Instances" of:inspector].property.titles count]);
}

- (void)testTheRowsAreBoundToTheirSection
{
	WKDProcessEditor *editor = [self modeller];
	WKDInspectorViewController *inspector = [[WKDInspectorViewController alloc] initWithProcessEditor:editor showingProcess:NO];
	[inspector view];
	editor.selection.selectedIds = @[ @"review" ];
	WKDInspectorRow *name = [self row:@"Name" of:inspector];
	NSDictionary *binding = [name.control infoForBinding:NSValueBinding];
	XCTAssertEqual([binding objectForKey:NSObservedObjectKey], name.model);
	XCTAssertEqualObjects([binding objectForKey:NSObservedKeyPathKey], @"name");

	/* Changed elsewhere: shown. */
	[editor.editor setName:@"Check the order" of:@"review"];
	XCTAssertEqualObjects([name.control stringValue], @"Check the order");

	/* Clicked: a change. */
	NSButton *async = [self row:@"Asynchronous before" of:inspector].control;
	[async performClick:nil];
	XCTAssertEqualObjects(WKDQualifiedAttribute(editor.editor.document, [editor.editor elementWithId:@"review"],
	                                            WKDCamundaNamespace, @"asyncBefore"), @"true");
}

- (void)testATablesRowsAreItsArrayControllers
{
	WKDProcessEditor *editor = [self modeller];
	WKDInspectorViewController *inspector = [[WKDInspectorViewController alloc] initWithProcessEditor:editor showingProcess:NO];
	[inspector view];
	editor.selection.selectedIds = @[ @"review" ];
	WKDInspectorRow *inputs = nil;
	for (WKDInspectorRow *row in [inspector testRows]) {
		if (row.property.kind == WKDPropertyTable) {
			inputs = row;
			break;
		}
	}
	XCTAssertNotNil(inputs);
	WKDTableRowController *table = [inputs valueForKey:@"_table"];
	XCTAssertNotNil(table.tableView);
	XCTAssertNotNil(table.rows);
	XCTAssertEqual([[table.tableView tableColumns] count], [inputs.property.columns count], @"a column each");
	NSUInteger before = [[table.rows arrangedObjects] count];
	[table addRow:nil];
	XCTAssertEqual([[table.rows arrangedObjects] count], before + 1, @"the table model's rows, the controller's content");
	XCTAssertEqual([table.tableView numberOfRows], (NSInteger)before + 1);
	XCTAssertEqual([table.tableView selectedRow], (NSInteger)before, @"the row added, selected");
}

- (void)testTheProcessAndARenamedElement
{
	WKDProcessEditor *editor = [self modeller];
	WKDInspectorViewController *process = [[WKDInspectorViewController alloc] initWithProcessEditor:editor showingProcess:YES];
	[process view];
	XCTAssertEqualObjects(process.elementId, WKDAttribute(editor.editor.model.process, @"id"));
	XCTAssertEqualObjects([[process.models firstObject] section].title, @"Process");

	WKDInspectorViewController *inspector = [[WKDInspectorViewController alloc] initWithProcessEditor:editor showingProcess:NO];
	[inspector view];
	editor.selection.selectedIds = @[ @"review" ];
	__block NSString *refusal = @"";
	inspector.refused = ^(NSString *reason) {
		refusal = reason;
	};
	WKDElementModel *general = [inspector.models firstObject];
	[general setValue:@"ok" forKey:@"id"];
	XCTAssertNotNil(refusal, @"a taken id");
	XCTAssertEqualObjects([[self row:@"Id" of:inspector].control stringValue], @"review", @"shown as it was");
	[general setValue:@"screen" forKey:@"id"];
	XCTAssertNil(refusal);
	XCTAssertEqualObjects(editor.selection.selectedIds, @[ @"screen" ], @"the same element, selected under its new id");
	XCTAssertEqualObjects(inspector.elementId, @"screen");
}

@end

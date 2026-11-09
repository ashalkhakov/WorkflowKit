#import <XCTest/XCTest.h>
#import "WKDElementModel.h"
#import "WKDTableModel.h"
#import "WKDEditor.h"
#import "WKDXML.h"
#import "WKDFixtures.h"

/* What the inspector's rows bind to: a section's values under keys, set
 * as changes, refused with the reason; a table's rows. */
@interface WKDElementModelTests : XCTestCase
@end

@implementation WKDElementModelTests
{
	NSUInteger _told;
}

- (WKDEditor *)modeller
{
	return [[WKDEditor alloc] initWithDocument:WKDParse(WKDModellerFile) undoManager:nil];
}

- (WKDElementModel *)section:(NSString *)title of:(NSString *)elementId in:(WKDEditor *)editor
{
	for (WKDSection *section in WKDSectionsFor(editor, elementId)) {
		if ([section.title isEqualToString:title]) {
			return [[WKDElementModel alloc] initWithEditor:editor elementId:elementId section:section];
		}
	}
	XCTFail(@"no %@ section for %@", title, elementId);
	return nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	_told++;
}

- (void)testAValueIsReadAndSetUnderItsKey
{
	WKDEditor *editor = [self modeller];
	WKDElementModel *general = [self section:@"General" of:@"review" in:editor];
	NSArray *keys = @[ @"id", @"name", @"documentation" ];
	XCTAssertEqualObjects(general.keys, keys);
	XCTAssertEqualObjects([general valueForKey:@"name"], @"Review");
	[general setValue:@"Check the order" forKey:@"name"];
	XCTAssertEqualObjects([editor.model nodeWithId:@"review"].name, @"Check the order");

	WKDElementModel *continuation = [self section:@"Continuation" of:@"review" in:editor];
	XCTAssertEqualObjects([continuation valueForKey:@"asynchronousBefore"], @NO);
	[continuation setValue:@YES forKey:@"asynchronousBefore"];
	XCTAssertEqualObjects([continuation valueForKey:@"asynchronousBefore"], @YES);
	XCTAssertEqualObjects(WKDQualifiedAttribute(editor.document, [editor elementWithId:@"review"], WKDCamundaNamespace,
	                                            @"asyncBefore"), @"true");
}

- (void)testAnIdTakenIsRefusedWithWhy
{
	WKDEditor *editor = [self modeller];
	WKDElementModel *general = [self section:@"General" of:@"review" in:editor];
	id taken = @"ok";
	NSError *error = nil;
	XCTAssertFalse([general validateValue:&taken forKey:@"id" error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"ok"].location != NSNotFound, @"%@", error);
	__block NSString *refusal = nil;
	general.refused = ^(NSString *reason) {
		refusal = reason;
	};
	[general addObserver:self forKeyPath:@"id" options:0 context:NULL];
	_told = 0;
	[general setValue:@"ok" forKey:@"id"];
	XCTAssertNotNil(refusal);
	XCTAssertEqual(_told, (NSUInteger)1, @"the value as it was, shown again");
	XCTAssertNotNil([editor.model nodeWithId:@"review"], @"not renamed");

	[general setValue:@"screen" forKey:@"id"];
	XCTAssertNil(refusal);
	XCTAssertEqualObjects(general.elementId, @"screen", @"the same element, under its new id");
	XCTAssertEqualObjects([general valueForKey:@"id"], @"screen");
	[general removeObserver:self forKeyPath:@"id"];
}

- (void)testObserversAreToldButOfWhatIsTyped
{
	WKDEditor *editor = [self modeller];
	WKDElementModel *general = [self section:@"General" of:@"review" in:editor];
	[general addObserver:self forKeyPath:@"name" options:0 context:NULL];
	[general addObserver:self forKeyPath:@"documentation" options:0 context:NULL];
	_told = 0;
	[general reload];
	XCTAssertEqual(_told, (NSUInteger)2);
	general.editingKey = @"name";
	_told = 0;
	[general reload];
	XCTAssertEqual(_told, (NSUInteger)1, @"the field being typed in left as it is");
	[general removeObserver:self forKeyPath:@"name"];
	[general removeObserver:self forKeyPath:@"documentation"];
}

- (void)testAnExpressionsProblemIsSaid
{
	WKDEditor *editor = [self modeller];
	WKDElementModel *flow = [self section:@"Flow" of:@"f3" in:editor];
	XCTAssertNil([flow problemWithText:@"amount > 100" forKey:@"condition"]);
	XCTAssertNotNil([flow problemWithText:@"amount >" forKey:@"condition"]);
	XCTAssertNil([flow problemWithText:@"amount >" forKey:@"defaultFlow"], @"not an expression");
}

- (void)testATablesRowsAreAddedSetAndRemoved
{
	WKDEditor *editor = [self modeller];
	WKDElementModel *io = [self section:@"Input/Output" of:@"review" in:editor];
	WKDTableModel *inputs = [io tableModelForKey:[io.keys firstObject]];
	XCTAssertNotNil(inputs);
	XCTAssertEqualObjects([io valueForKey:[io.keys firstObject]], inputs);
	NSUInteger before = [inputs.rows count];
	NSUInteger row = [inputs addRow];
	XCTAssertEqual([inputs.rows count], before + 1);
	[[inputs.rows objectAtIndex:row] setValue:@"amount" forKey:@"c0"];
	XCTAssertEqualObjects([[inputs.rows objectAtIndex:row] valueForKey:@"c0"], @"amount");
	XCTAssertTrue([[editor.document XMLString] rangeOfString:@"name=\"amount\""].location != NSNotFound);
	[inputs removeRowAtIndex:row];
	XCTAssertEqual([inputs.rows count], before);

	WKDElementModel *listeners = [self section:@"Listeners" of:@"review" in:editor];
	WKDTableModel *execution = [listeners tableModelForKey:[listeners.keys firstObject]];
	NSUInteger listener = [execution addRow];
	NSArray *fields = [execution detailsForRow:listener];
	XCTAssertEqual([fields count], [execution.property.details count], @"a listener's fields");
}

@end

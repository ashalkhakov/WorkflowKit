#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "WKDDocument.h"
#import "WKDWindowController.h"
#import "WKDFixtures.h"

/* What the commands told their host. */
@interface WKDTestHost : NSObject <WKDProcessCommandsHost>
@property (nonatomic, copy) NSString *refusal;
@property (nonatomic) NSUInteger arranged;
@end

@implementation WKDTestHost
- (void)commands:(WKDProcessCommands *)commands refused:(NSString *)reason { self.refusal = reason; }
- (void)commands:(WKDProcessCommands *)commands say:(NSString *)status {}
- (void)commands:(WKDProcessCommands *)commands alert:(NSString *)message detail:(NSString *)detail { self.refusal = message; }
- (NSURL *)documentURLForCommands:(WKDProcessCommands *)commands { return nil; }
- (NSDictionary *)editedResourcesForCommands:(WKDProcessCommands *)commands { return @{}; }
- (void)commands:(WKDProcessCommands *)commands open:(NSURL *)url decision:(NSString *)decision {}
- (void)commands:(WKDProcessCommands *)commands rename:(NSString *)elementId {}
- (void)commandsDidArrange:(WKDProcessCommands *)commands { self.arranged++; }
@end

/* The designer's parts, each from its XIB and connected, following the
 * process editor they share; and the window that puts them in place. */
@interface WKDPartsTests : XCTestCase
@end

@implementation WKDPartsTests

+ (void)setUp
{
	[NSApplication sharedApplication];
}

- (WKDProcessEditor *)modeller
{
	return [[WKDProcessEditor alloc] initWithData:[WKDModellerFile dataUsingEncoding:NSUTF8StringEncoding]
	                                  undoManager:nil error:NULL];
}

static NSArray *
WKDTitles(NSMenu *menu)
{
	NSMutableArray *titles = [NSMutableArray array];
	for (NSMenuItem *item in [menu itemArray]) {
		if (![item isSeparatorItem]) {
			[titles addObject:[item title]];
		}
	}
	return titles;
}

- (void)testThePartsLoadFromTheirXIBsConnected
{
	WKDProcessEditor *editor = [self modeller];
	WKDCanvasViewController *canvas = [[WKDCanvasViewController alloc] initWithProcessEditor:editor];
	XCTAssertTrue([canvas.view isKindOfClass:[NSScrollView class]]);
	XCTAssertNotNil(canvas.canvas);
	XCTAssertEqual([(NSScrollView *)canvas.view documentView], canvas.canvas);
	XCTAssertEqual(canvas.canvas.canvasDelegate, canvas);
	XCTAssertEqual([canvas.elementMenu numberOfItems], (NSInteger)11, @"the right click's items");
	XCTAssertNotNil([canvas.canvas.model nodeWithId:@"review"]);

	WKDOutlineViewController *outline = [[WKDOutlineViewController alloc] initWithProcessEditor:editor];
	XCTAssertNotNil(outline.view);
	XCTAssertNotNil(outline.outlineView);
	XCTAssertGreaterThan([outline.outlineView numberOfRows], (NSInteger)1, @"the process and its nodes");

	WKDPaletteViewController *palette = [[WKDPaletteViewController alloc] init];
	XCTAssertNotNil(palette.view);
	XCTAssertEqual((id)palette.palette, (id)palette.view);
	XCTAssertEqual((id)palette.palette.delegate, (id)palette);

	WKDProblemsViewController *problems = [[WKDProblemsViewController alloc] initWithProcessEditor:editor];
	XCTAssertNotNil(problems.view);
	XCTAssertNotNil(problems.tableView);
	XCTAssertEqual([problems.tableView numberOfRows], (NSInteger)MAX([editor.problems count], (NSUInteger)1));
}

- (void)testTheCanvasAndTheOutlineFollowTheSelection
{
	WKDProcessEditor *editor = [self modeller];
	WKDCanvasViewController *canvas = [[WKDCanvasViewController alloc] initWithProcessEditor:editor];
	WKDOutlineViewController *outline = [[WKDOutlineViewController alloc] initWithProcessEditor:editor];
	[canvas view];
	[outline view];
	editor.selection.selectedIds = @[ @"review" ];
	XCTAssertEqualObjects(canvas.canvas.selection, [NSSet setWithObject:@"review"]);
	XCTAssertGreaterThanOrEqual([outline.outlineView selectedRow], (NSInteger)0);

	canvas.canvas.selection = [NSSet setWithObject:@"ok"];
	[canvas canvasSelectionDidChange:canvas.canvas];
	XCTAssertEqualObjects(editor.selection.selectedIds, @[ @"ok" ], @"what the canvas selects is the selection");

	[editor.editor deleteElements:@[ @"ok" ]];
	XCTAssertEqualObjects(canvas.canvas.selection, [NSSet set], @"what went is not selected");
	XCTAssertNil([canvas.canvas.model nodeWithId:@"ok"], @"the canvas shows the process as it is");
}

- (void)testTheRightClicksMenuFitsTheSelection
{
	WKDProcessEditor *editor = [self modeller];
	WKDCanvasViewController *canvas = [[WKDCanvasViewController alloc] initWithProcessEditor:editor];
	[canvas view];
	editor.selection.selectedIds = @[ @"review" ];
	NSMenu *menu = [canvas canvasMenu:canvas.canvas];
	NSArray *titles = WKDTitles(menu);
	XCTAssertTrue([titles containsObject:@"Rename"]);
	XCTAssertFalse([titles containsObject:@"Add Lane"], @"not a lane");
	XCTAssertFalse([titles containsObject:@"Align"], @"one shape");
	NSMenu *types = [[menu itemWithTitle:@"Change Type"] submenu];
	XCTAssertGreaterThan([types numberOfItems], (NSInteger)1, @"the other tasks");
	NSUInteger current = 0;
	for (NSMenuItem *item in [types itemArray]) {
		current += [item state] == NSControlStateValueOn ? 1 : 0;
		XCTAssertEqual([item action], @selector(changeType:));
		XCTAssertNotNil([item representedObject]);
	}
	XCTAssertEqual(current, (NSUInteger)1, @"its own type checked");
	XCTAssertEqual([canvas.elementMenu numberOfItems], (NSInteger)11, @"the XIB's menu as it was");

	editor.selection.selectedIds = @[ @"review", @"ok" ];
	titles = WKDTitles([canvas canvasMenu:canvas.canvas]);
	XCTAssertTrue([titles containsObject:@"Align"]);
	XCTAssertTrue([titles containsObject:@"Distribute"]);
	XCTAssertFalse([titles containsObject:@"Rename"], @"two selected");
	XCTAssertTrue([titles containsObject:@"Copy"]);
}

- (void)testTheCommandsActOnTheSelection
{
	WKDProcessEditor *editor = [self modeller];
	WKDProcessCommands *commands = [[WKDProcessCommands alloc] initWithProcessEditor:editor];
	WKDTestHost *host = [[WKDTestHost alloc] init];
	commands.host = host;
	NSMenuItem *align = [[NSMenuItem alloc] initWithTitle:@"Left Edges" action:@selector(alignLeftEdges:) keyEquivalent:@""];
	editor.selection.selectedIds = @[ @"review" ];
	XCTAssertFalse([commands validateUserInterfaceItem:align], @"one shape");
	[commands alignLeftEdges:nil];
	XCTAssertNotNil(host.refusal);
	editor.selection.selectedIds = @[ @"review", @"ok" ];
	XCTAssertTrue([commands validateUserInterfaceItem:align]);
	[commands alignLeftEdges:nil];
	XCTAssertNil(host.refusal);
	XCTAssertEqual(NSMinX([editor.editor.model nodeWithId:@"ok"].bounds), NSMinX([editor.editor.model nodeWithId:@"review"].bounds));
	[commands arrange:nil];
	XCTAssertEqual(host.arranged, (NSUInteger)1);
	[commands addPool:nil];
	XCTAssertNotNil(editor.editor.model.pool);
	XCTAssertEqualObjects(editor.selection.selectedIds, @[ editor.editor.model.pool.elementId ], @"the pool made, selected");
}

- (void)testTheWindowPutsThePartsInPlace
{
	WKDDocument *document = [[WKDDocument alloc] init];
	NSError *error = nil;
	XCTAssertTrue([document readFromData:[WKDModellerFile dataUsingEncoding:NSUTF8StringEncoding] ofType:@"BPMN"
	                               error:&error], @"%@", error);
	[document makeWindowControllers];
	WKDWindowController *controller = [[document windowControllers] firstObject];
	XCTAssertNotNil([controller window], @"DesignerWindow.xib");
	for (NSView *host in @[ controller.canvasHost, controller.outlineHost, controller.paletteHost, controller.problemsHost,
	                        controller.inspectorHost, controller.processHost ]) {
		XCTAssertGreaterThan([[host subviews] count], (NSUInteger)0, @"a part in its host");
	}
	XCTAssertEqual([controller.canvasController.view superview], controller.canvasHost);
	XCTAssertEqual([controller nextResponder], controller.commands, @"the Editor menu's commands in its chain");
	XCTAssertNotNil(controller.split.delegate);
	XCTAssertEqual([controller.leftTabView numberOfTabViewItems], (NSInteger)3);
	XCTAssertEqual([controller.rightTabView numberOfTabViewItems], (NSInteger)2);
	document.processEditor.selection.selectedIds = @[ @"review" ];
	XCTAssertEqualObjects(controller.canvasController.canvas.selection, [NSSet setWithObject:@"review"]);
	XCTAssertGreaterThan([controller.status length], (NSUInteger)0);
	[document close];
}

@end

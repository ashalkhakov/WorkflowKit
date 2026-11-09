#import "WKDCanvasViewController.h"
#import "WKDRenderer.h"

/* The menu's items, by their tags in WKDCanvas.xib. */
enum {
	WKDMenuRename = 1,
	WKDMenuAddLane,
	WKDMenuChangeType,
	WKDMenuOneSeparator,
	WKDMenuAlign,
	WKDMenuDistribute,
	WKDMenuSeveralSeparator
};

@implementation WKDCanvasViewController

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor
{
	if ((self = [super initWithNibName:@"WKDCanvas" bundle:[NSBundle bundleForClass:[WKDCanvasViewController class]]])) {
		_processEditor = processEditor;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
	[super loadView];
	self.canvas.canvasDelegate = self;
	self.canvas.model = _processEditor.editor.model;
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(processDidChange:) name:WKDProcessEditorDidChangeNotification
	             object:_processEditor];
	[center addObserver:self selector:@selector(selectionDidChange:) name:WKDSelectionDidChangeNotification
	             object:_processEditor.selection];
}

- (WKDEditor *)editor
{
	return _processEditor.editor;
}

- (void)refuse:(NSString *)reason
{
	if (reason != nil) {
		NSBeep();
	}
	if (self.refused != nil) {
		self.refused(reason);
	}
}

#pragma mark Following the process

- (void)processDidChange:(NSNotification *)notification
{
	self.canvas.model = [self editor].model;
	[self selectionDidChange:nil];
}

- (void)selectionDidChange:(NSNotification *)notification
{
	NSSet *selected = [NSSet setWithArray:_processEditor.selection.selectedIds];
	if (![selected isEqualToSet:self.canvas.selection]) {
		self.canvas.selection = selected;
	}
}

- (void)canvasSelectionDidChange:(WKDCanvasView *)canvas
{
	_processEditor.selection.selectedIds = canvas.orderedSelection;
}

- (void)select:(NSString *)elementId
{
	_processEditor.selection.selectedIds = elementId != nil ? @[ elementId ] : @[];
}

#pragma mark Gestures, each one change

- (void)canvas:(WKDCanvasView *)canvas insert:(WKDLook *)tool at:(NSPoint)point
{
	NSString *reason = nil;
	NSString *added = [[self editor] insertNodeOfType:tool.type eventDefinition:tool.eventDefinition at:point
	                                            error:&reason];
	[self refuse:added == nil ? reason : nil];
	if (added != nil) {
		[self select:added];
	}
}

- (void)canvas:(WKDCanvasView *)canvas move:(NSArray<NSString *> *)elementIds by:(NSSize)offset
{
	[self refuse:nil];
	[[self editor] moveElements:elementIds by:offset];
}

- (void)canvas:(WKDCanvasView *)canvas connect:(NSString *)sourceId to:(NSString *)targetId
{
	NSString *reason = nil;
	NSString *flow = [[self editor] connect:sourceId to:targetId error:&reason];
	[self refuse:flow == nil ? reason : nil];
	if (flow != nil) {
		[self select:flow];
	}
}

- (void)canvas:(WKDCanvasView *)canvas resize:(NSString *)elementId to:(NSRect)bounds
{
	[self refuse:nil];
	[[self editor] resizeElement:elementId to:bounds];
}

- (void)canvas:(WKDCanvasView *)canvas delete:(NSArray<NSString *> *)elementIds
{
	[self refuse:nil];
	[[self editor] deleteElements:elementIds];
}

- (void)canvas:(WKDCanvasView *)canvas reconnect:(NSString *)flowId atSource:(BOOL)atSource to:(NSString *)nodeId
{
	NSString *reason = nil;
	BOOL done = [[self editor] reconnect:flowId atSource:atSource to:nodeId error:&reason];
	[self refuse:done ? nil : reason];
}

- (void)canvas:(WKDCanvasView *)canvas moveBend:(NSUInteger)index of:(NSString *)flowId to:(NSPoint)point
{
	[self refuse:nil];
	[[self editor] moveBend:index of:flowId to:point];
}

- (void)canvas:(WKDCanvasView *)canvas nudge:(NSArray<NSString *> *)elementIds by:(NSSize)offset
{
	[self refuse:nil];
	[[self editor] nudgeElements:elementIds by:offset];
}

- (void)canvas:(WKDCanvasView *)canvas moveLabelOf:(NSString *)elementId by:(NSSize)offset
{
	[self refuse:nil];
	[[self editor] moveLabelOf:elementId by:offset];
}

- (void)canvas:(WKDCanvasView *)canvas rename:(NSString *)elementId to:(NSString *)name
{
	[self refuse:nil];
	[[self editor] setName:name of:elementId];
}

- (void)canvasToolWasUsed:(WKDCanvasView *)canvas
{
	if (self.toolUsed != nil) {
		self.toolUsed();
	}
}

- (void)armTool:(WKDLook *)tool
{
	self.canvas.tool = tool;
	[[self.view window] makeFirstResponder:self.canvas];
}

- (void)beginRenaming:(NSString *)elementId
{
	[self.canvas beginRenaming:elementId];
}

- (void)scrollToContent
{
	[self.canvas scrollToContent];
}

#pragma mark The right click's menu

/* The XIB's menu, its items for what is selected: Rename, Add Lane for a
 * lane, Change Type for a node with types to change to; Align and
 * Distribute for several shapes; the clipboard's always. */
- (NSMenu *)canvasMenu:(WKDCanvasView *)canvas
{
	NSMenu *menu = [self.elementMenu copy];
	NSArray *selected = _processEditor.selection.selectedIds;
	NSString *one = [selected count] == 1 ? [selected firstObject] : nil;
	NSUInteger shapes = 0;
	for (NSString *elementId in selected) {
		shapes += [[self editor].model nodeWithId:elementId] != nil ? 1 : 0;
	}
	NSArray *types = one != nil ? [[self editor] typesFor:one] : @[];
	NSMutableIndexSet *dropped = [NSMutableIndexSet indexSet];
	for (NSMenuItem *item in [menu itemArray]) {
		NSInteger tag = [item tag];
		BOOL shown = YES;
		if (tag == WKDMenuRename || tag == WKDMenuOneSeparator) {
			shown = one != nil;
		} else if (tag == WKDMenuAddLane) {
			shown = one != nil && [[self editor].model laneWithId:one] != nil;
		} else if (tag == WKDMenuChangeType) {
			shown = [types count] > 0;
		} else if (tag == WKDMenuAlign || tag == WKDMenuDistribute || tag == WKDMenuSeveralSeparator) {
			shown = shapes >= 2;
		}
		if (!shown) {
			[dropped addIndex:(NSUInteger)[menu indexOfItem:item]];
		}
	}
	for (NSUInteger index = [dropped lastIndex]; index != NSNotFound; index = [dropped indexLessThanIndex:index]) {
		[menu removeItemAtIndex:(NSInteger)index];
	}
	NSMenu *change = [[menu itemWithTag:WKDMenuChangeType] submenu];
	if (change != nil) {
		/* The XIB's item, once for each type. */
		NSMenuItem *pattern = [change itemAtIndex:0];
		while ([change numberOfItems] > 0) {
			[change removeItemAtIndex:0];
		}
		WKDNode *node = [[self editor].model nodeWithId:one];
		for (WKDNodeType *type in types) {
			NSMenuItem *item = [pattern copy];
			[item setTitle:type.title];
			[item setRepresentedObject:type];
			BOOL current = [type.type isEqualToString:node.type]
				&& [type.eventDefinition ?: @"" isEqualToString:node.eventDefinition ?: @""];
			[item setState:current ? NSControlStateValueOn : NSControlStateValueOff];
			[change addItem:item];
		}
	}
	return menu;
}

#pragma mark Zoom

- (IBAction)zoomIn:(id)sender
{
	self.canvas.zoom *= 1.25;
}

- (IBAction)zoomOut:(id)sender
{
	self.canvas.zoom /= 1.25;
}

- (IBAction)actualSize:(id)sender
{
	self.canvas.zoom = 1;
}

- (IBAction)zoomToFit:(id)sender
{
	[self.canvas zoomToFit];
}

@end

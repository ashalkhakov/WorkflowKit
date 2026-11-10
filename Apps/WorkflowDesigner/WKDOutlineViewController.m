#import "WKDOutlineViewController.h"
#import "WKDXML.h"

@implementation WKDOutlineViewController
{
	WKDOutline *_outline;
}

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor
{
	if ((self = [super initWithNibName:@"WKDOutlineView" bundle:[NSBundle bundleForClass:[WKDOutlineViewController class]]])) {
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
	_outline = [[WKDOutline alloc] initWithOutlineView:self.outlineView];
	_outline.delegate = self;
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(processDidChange:) name:WKDProcessEditorDidChangeNotification
	             object:_processEditor];
	[center addObserver:self selector:@selector(selectionDidChange:) name:WKDSelectionDidChangeNotification
	             object:_processEditor.selection];
	[self processDidChange:nil];
}

- (void)processDidChange:(NSNotification *)notification
{
	[_outline showDiagram:_processEditor.editor.model];
	[self selectionDidChange:nil];
}

- (void)selectionDidChange:(NSNotification *)notification
{
	NSArray *selected = _processEditor.selection.selectedIds;
	[_outline select:[selected count] == 1 ? [selected firstObject] : nil];
}

- (void)outline:(WKDOutline *)outline didSelect:(NSString *)elementId
{
	if ([elementId isEqualToString:WKDAttribute(_processEditor.editor.model.process, @"id")]) {
		_processEditor.selection.selectedIds = @[];
		if (self.processChosen != nil) {
			self.processChosen();
		}
		return;
	}
	_processEditor.selection.selectedIds = elementId != nil ? @[ elementId ] : @[];
}

@end

#import "WKDWindowController.h"
#import "WKDDocument.h"
#import "WKDEditor.h"
#import "WKDRenderer.h"

@implementation WKDWindowController
{
	/* What the last change refused, shown until the next. */
	NSString *_note;
}

- (instancetype)init
{
	return [super initWithWindowNibName:@"DesignerWindow"];
}

- (WKDDocument *)designerDocument
{
	return (WKDDocument *)[self document];
}

- (WKDEditor *)editor
{
	return [self designerDocument].editor;
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	self.canvas.delegate = self;
	self.palette.delegate = self;
	__weak WKDWindowController *weakSelf = self;
	[self editor].changed = ^{
		[weakSelf documentDidChange];
	};
	self.canvas.diagram = [self editor].diagram;
	[self.canvas scrollToContent];
	[self updateStatus];
	[[self window] makeFirstResponder:self.canvas];
}

- (void)documentDidChange
{
	[[self designerDocument] check];
	self.canvas.diagram = [self editor].diagram;
	[self updateStatus];
}

- (void)updateStatus
{
	NSString *problem = [self designerDocument].problem;
	NSString *state = problem == nil ? @"The engine runs this process." : [NSString stringWithFormat:@"Not runnable: %@", problem];
	NSUInteger selected = [self.canvas.selection count];
	NSMutableArray *parts = [NSMutableArray array];
	if (_note != nil) {
		[parts addObject:_note];
	}
	[parts addObject:state];
	if (selected > 1) {
		[parts addObject:[NSString stringWithFormat:@"%lu selected", (unsigned long)selected]];
	} else if (selected == 1) {
		[parts addObject:[self.canvas.selection anyObject]];
	}
	self.status = [parts componentsJoinedByString:@" — "];
}

- (void)note:(NSString *)note
{
	_note = [note copy];
	if (note != nil) {
		NSBeep();
	}
	[self updateStatus];
}

#pragma mark Canvas

- (void)canvas:(WKDCanvasView *)canvas insert:(WKDLook *)tool at:(NSPoint)point
{
	NSString *reason = nil;
	NSString *added = [[self editor] insertNodeOfType:tool.type eventDefinition:tool.eventDefinition at:point
	                                            error:&reason];
	[self note:added == nil ? reason : nil];
	if (added != nil) {
		canvas.selection = [NSSet setWithObject:added];
	}
}

- (void)canvas:(WKDCanvasView *)canvas move:(NSArray<NSString *> *)elementIds by:(NSSize)offset
{
	_note = nil;
	[[self editor] moveElements:elementIds by:offset];
}

- (void)canvas:(WKDCanvasView *)canvas connect:(NSString *)sourceId to:(NSString *)targetId
{
	NSString *reason = nil;
	NSString *flow = [[self editor] connect:sourceId to:targetId error:&reason];
	[self note:flow == nil ? reason : nil];
	if (flow != nil) {
		canvas.selection = [NSSet setWithObject:flow];
	}
}

- (void)canvas:(WKDCanvasView *)canvas resize:(NSString *)elementId to:(NSRect)bounds
{
	_note = nil;
	[[self editor] resizeElement:elementId to:bounds];
}

- (void)canvas:(WKDCanvasView *)canvas delete:(NSArray<NSString *> *)elementIds
{
	_note = nil;
	[[self editor] deleteElements:elementIds];
}

- (void)canvasSelectionDidChange:(WKDCanvasView *)canvas
{
	[self updateStatus];
}

- (void)canvasToolWasUsed:(WKDCanvasView *)canvas
{
	[self.palette choosePointer];
}

- (void)palette:(WKDPaletteView *)palette didChoose:(WKDLook *)tool
{
	self.canvas.tool = tool;
	[[self window] makeFirstResponder:self.canvas];
}

#pragma mark Menus

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

- (IBAction)arrange:(id)sender
{
	_note = nil;
	[[self editor] arrange];
	[self.canvas scrollToContent];
}

@end

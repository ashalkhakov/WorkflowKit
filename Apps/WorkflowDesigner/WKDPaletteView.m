#import "WKDPaletteView.h"
#import "WKDEditor.h"
#import "WKDRenderer.h"
#import <DiagramKitUI/DKAppKitSurface.h>

static const double WKDCell = 44;

/* Name, type, event definition: what the engine runs, the common first. */
static NSArray *
WKDTools(void)
{
	return @[
		@[ @"Pointer", @"", @"" ],
		@[ @"Start Event", @"startEvent", @"" ],
		@[ @"Timer Start Event", @"startEvent", @"timerEventDefinition" ],
		@[ @"Message Start Event", @"startEvent", @"messageEventDefinition" ],
		@[ @"End Event", @"endEvent", @"" ],
		@[ @"Error End Event", @"endEvent", @"errorEventDefinition" ],
		@[ @"Terminate End Event", @"endEvent", @"terminateEventDefinition" ],
		@[ @"Timer Catch Event", @"intermediateCatchEvent", @"timerEventDefinition" ],
		@[ @"Message Catch Event", @"intermediateCatchEvent", @"messageEventDefinition" ],
		@[ @"Signal Catch Event", @"intermediateCatchEvent", @"signalEventDefinition" ],
		@[ @"Message Throw Event", @"intermediateThrowEvent", @"messageEventDefinition" ],
		@[ @"Boundary Timer Event", @"boundaryEvent", @"timerEventDefinition" ],
		@[ @"Boundary Message Event", @"boundaryEvent", @"messageEventDefinition" ],
		@[ @"Boundary Error Event", @"boundaryEvent", @"errorEventDefinition" ],
		@[ @"Task", @"task", @"" ],
		@[ @"User Task", @"userTask", @"" ],
		@[ @"Service Task", @"serviceTask", @"" ],
		@[ @"Script Task", @"scriptTask", @"" ],
		@[ @"Send Task", @"sendTask", @"" ],
		@[ @"Receive Task", @"receiveTask", @"" ],
		@[ @"Business Rule Task", @"businessRuleTask", @"" ],
		@[ @"Manual Task", @"manualTask", @"" ],
		@[ @"Call Activity", @"callActivity", @"" ],
		@[ @"Subprocess", @"subProcess", @"" ],
		@[ @"Exclusive Gateway", @"exclusiveGateway", @"" ],
		@[ @"Parallel Gateway", @"parallelGateway", @"" ],
		@[ @"Inclusive Gateway", @"inclusiveGateway", @"" ],
		@[ @"Event-based Gateway", @"eventBasedGateway", @"" ],
	];
}

@implementation WKDPaletteView
{
	NSInteger _chosen;
}

- (BOOL)isFlipped
{
	return YES;
}

/* As many columns as the pane is wide for. */
- (NSInteger)columns
{
	return MAX(2, (NSInteger)((NSWidth([self bounds]) - 8) / WKDCell));
}

- (NSRect)cellAt:(NSInteger)index
{
	NSInteger columns = [self columns];
	return NSMakeRect(4 + (index % columns) * WKDCell, 6 + (index / columns) * WKDCell, WKDCell, WKDCell);
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	[self updateToolTips];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	[self updateToolTips];
}

- (void)updateToolTips
{
	[self removeAllToolTips];
	NSArray *tools = WKDTools();
	for (NSUInteger i = 0; i < [tools count]; i++) {
		[self addToolTipRect:[self cellAt:i] owner:[[tools objectAtIndex:i] objectAtIndex:0] userData:NULL];
	}
}

- (void)choosePointer
{
	_chosen = 0;
	[self setNeedsDisplay:YES];
}

/* The tool in the cell, drawn in a box sized for the cell. */
- (void)drawTool:(NSArray *)tool in:(NSRect)cell
{
	NSString *type = [tool objectAtIndex:1];
	NSRect box = NSInsetRect(cell, 8, 8);
	if ([type length] == 0) {
		NSBezierPath *arrow = [NSBezierPath bezierPath];
		double x = NSMinX(box) + 9, y = NSMinY(box) + 3;
		[arrow moveToPoint:NSMakePoint(x, y)];
		[arrow lineToPoint:NSMakePoint(x, y + 20)];
		[arrow lineToPoint:NSMakePoint(x + 5, y + 15)];
		[arrow lineToPoint:NSMakePoint(x + 9, y + 23)];
		[arrow lineToPoint:NSMakePoint(x + 12, y + 21)];
		[arrow lineToPoint:NSMakePoint(x + 8, y + 14)];
		[arrow lineToPoint:NSMakePoint(x + 14, y + 13)];
		[arrow closePath];
		[WKDInkColor() setFill];
		[arrow fill];
		return;
	}
	NSString *definition = [tool objectAtIndex:2];
	WKDLook *look = [WKDLook lookOfType:type eventDefinition:[definition length] > 0 ? definition : nil];
	NSSize size = [WKDEditor sizeOfType:type];
	double scale = MIN(NSWidth(box) / size.width, NSHeight(box) / size.height);
	NSRect drawn = NSMakeRect(NSMidX(box) - size.width * scale / 2, NSMidY(box) - size.height * scale / 2,
	                          size.width * scale, size.height * scale);
	if (WKDIsContainerType(type) || [type isEqualToString:@"callActivity"] || WKDKindOfType(type, NULL) == WKDShapeActivity) {
		drawn = NSInsetRect(box, 0, 4);
	}
	WKDDrawNode([DKAppKitSurface surface], look, drawn, NO);
}

- (void)drawRect:(NSRect)dirty
{
	[[NSColor windowBackgroundColor] setFill];
	/* Within the view: since macOS 14 views do not clip to their bounds,
	 * and the rectangle to draw may reach past them -- over the tab bar. */
	NSRectFill(NSIntersectionRect(dirty, [self bounds]));
	NSArray *tools = WKDTools();
	for (NSUInteger i = 0; i < [tools count]; i++) {
		NSRect cell = [self cellAt:i];
		if (!NSIntersectsRect(cell, dirty)) {
			continue;
		}
		if ((NSInteger)i == _chosen) {
			[[WKDSelectionColor() colorWithAlphaComponent:0.2] setFill];
			[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cell, 2, 2) xRadius:5 yRadius:5] fill];
		}
		[NSGraphicsContext saveGraphicsState];
		[self drawTool:[tools objectAtIndex:i] in:cell];
		[NSGraphicsContext restoreGraphicsState];
	}
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSArray *tools = WKDTools();
	for (NSUInteger i = 0; i < [tools count]; i++) {
		if (!NSPointInRect(point, [self cellAt:i])) {
			continue;
		}
		_chosen = i;
		[self setNeedsDisplay:YES];
		NSArray *tool = [tools objectAtIndex:i];
		NSString *type = [tool objectAtIndex:1], *definition = [tool objectAtIndex:2];
		WKDLook *look = [type length] > 0
			? [WKDLook lookOfType:type eventDefinition:[definition length] > 0 ? definition : nil] : nil;
		look.name = [tool objectAtIndex:0];
		[self.delegate palette:self didChoose:look];
		return;
	}
}

@end

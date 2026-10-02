#import "WDDiagramView.h"
#import "WKDDiagram.h"
#import "WKDRenderer.h"
#import "WKDXML.h"

static NSColor *
WDActiveColor(void)
{
	return [NSColor colorWithCalibratedRed:0.15 green:0.45 blue:0.9 alpha:1];
}

static NSColor *
WDFinishedColor(void)
{
	return [NSColor colorWithCalibratedRed:0.2 green:0.65 blue:0.3 alpha:1];
}

static NSColor *
WDIncidentColor(void)
{
	return [NSColor colorWithCalibratedRed:0.85 green:0.15 blue:0.15 alpha:1];
}

@implementation WDDiagramView
{
	double _zoom;
	/* The area the diagram was last fitted to, and whether it is being
	 * fitted now: fitting resizes the view, which can show or hide the
	 * scroll view's scrollers and so change the area again. */
	NSSize _fittedTo;
	BOOL _fitting;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_zoom = 1;
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	if ((self = [super initWithCoder:coder])) {
		_zoom = 1;
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

/* Fitted again when the area it is shown in changes size. */
- (void)viewDidMoveToSuperview
{
	[super viewDidMoveToSuperview];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
	NSView *clip = [self superview];
	if (clip != nil) {
		[clip setPostsFrameChangedNotifications:YES];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(areaDidChange:)
		                                             name:NSViewFrameDidChangeNotification object:clip];
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)areaDidChange:(NSNotification *)notification
{
	NSSize now = [[self enclosingScrollView] contentSize];
	/* A scroller shown or hidden is not a new area. */
	if (self.diagram != nil && !_fitting
	    && (fabs(now.width - _fittedTo.width) > 20 || fabs(now.height - _fittedTo.height) > 20)) {
		[self zoomToFit];
	}
}

#pragma mark Size

/* The diagram with a margin round it, from the origin at least, and no
 * smaller than what is visible. */
- (void)resize
{
	NSRect content = self.diagram.contentBounds;
	NSRect canvas = NSIsEmptyRect(content) ? NSMakeRect(0, 0, 1, 1) : NSInsetRect(content, -30, -30);
	NSSize visible = [[self enclosingScrollView] contentSize];
	canvas.size.width = MAX(NSWidth(canvas), visible.width / _zoom);
	canvas.size.height = MAX(NSHeight(canvas), visible.height / _zoom);
	[self setFrameSize:NSMakeSize(NSWidth(canvas) * _zoom, NSHeight(canvas) * _zoom)];
	[self setBoundsOrigin:canvas.origin];
	[self setBoundsSize:canvas.size];
	[self setNeedsDisplay:YES];
}

- (void)setDiagram:(WKDDiagram *)diagram
{
	_diagram = diagram;
	[self zoomToFit];
}

- (void)zoomToFit
{
	if (_fitting) {
		return;
	}
	_fitting = YES;
	NSRect content = self.diagram.contentBounds;
	NSSize visible = [[self enclosingScrollView] contentSize];
	_fittedTo = visible;
	_zoom = 1;
	if (!NSIsEmptyRect(content) && visible.width > 0 && visible.height > 0) {
		content = NSInsetRect(content, -30, -30);
		_zoom = MAX(0.25, MIN(1, MIN(visible.width / NSWidth(content), visible.height / NSHeight(content))));
	}
	[self resize];
	if (!NSIsEmptyRect(content)) {
		[self scrollPoint:content.origin];
	}
	_fitting = NO;
}

- (void)setActive:(NSCountedSet<NSString *> *)active
         finished:(NSSet<NSString *> *)finished
        incidents:(NSCountedSet<NSString *> *)incidents
{
	_active = [active copy];
	_finished = [finished copy];
	_incidents = [incidents copy];
	[self setNeedsDisplay:YES];
}

#pragma mark Drawing

- (WKDLook *)lookOf:(WKDShape *)shape
{
	WKDLook *look = [WKDLook lookOfType:shape.type eventDefinition:shape.eventDefinition];
	look.interrupting = shape.interrupting;
	look.eventSubProcess = shape.eventSubProcess;
	look.loop = shape.loop;
	look.name = shape.name;
	return look;
}

/* A count in a circle of the colour, centred on the point. */
static void
WDBadge(NSPoint centre, NSUInteger count, NSColor *colour)
{
	NSString *text = [NSString stringWithFormat:@"%lu", (unsigned long)count];
	NSDictionary *attributes = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:10],
	                              NSForegroundColorAttributeName: [NSColor whiteColor] };
	NSSize size = [text sizeWithAttributes:attributes];
	double diameter = MAX(16, size.width + 8);
	NSRect circle = NSMakeRect(centre.x - diameter / 2, centre.y - 8, diameter, 16);
	[colour setFill];
	[[NSBezierPath bezierPathWithRoundedRect:circle xRadius:8 yRadius:8] fill];
	[text drawAtPoint:NSMakePoint(NSMidX(circle) - size.width / 2, NSMidY(circle) - size.height / 2)
	   withAttributes:attributes];
}

- (void)drawRect:(NSRect)dirty
{
	[WKDPaperColor() setFill];
	NSRectFill(NSIntersectionRect(dirty, [self bounds]));
	if (self.diagram == nil) {
		NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:12],
		                              NSForegroundColorAttributeName: [NSColor grayColor] };
		NSString *text = self.placeholder ?: @"";
		NSSize size = [text sizeWithAttributes:attributes];
		NSRect visible = [self visibleRect];
		[text drawAtPoint:NSMakePoint(NSMidX(visible) - size.width / 2, NSMidY(visible) - size.height / 2)
		   withAttributes:attributes];
		return;
	}
	/* Pools and lanes under everything. */
	NSMutableArray<WKDLane *> *bands = [NSMutableArray arrayWithArray:self.diagram.otherPools];
	if (self.diagram.pool != nil) {
		[bands addObject:self.diagram.pool];
	}
	[bands addObjectsFromArray:self.diagram.lanes];
	for (WKDLane *band in bands) {
		if (band.hasBounds) {
			WKDDrawLane(band.bounds, band.name, band.horizontal);
		}
	}
	/* The way taken first, under the shapes. */
	for (WKDConnection *connection in self.diagram.connections) {
		BOOL taken = [self.finished containsObject:connection.source.elementId]
			&& ([self.finished containsObject:connection.target.elementId]
			    || [self.active containsObject:connection.target.elementId]);
		[(taken ? WDFinishedColor() : WKDInkColor()) setStroke];
		if (connection.isAssociation) {
			WKDDrawAssociation(connection.waypoints, ![WKDAttribute(connection.element, @"associationDirection") ?: @"None"
			                                           isEqualToString:@"None"]);
		} else {
			WKDDrawFlow(connection.waypoints, connection.isDefault,
			            connection.hasCondition && connection.source.kind == WKDShapeActivity, nil);
		}
		if ([connection.name length] > 0) {
			WKDDrawLabel(connection.name, NSIsEmptyRect(connection.labelBounds)
			                                  ? WKDFlowLabelRect(connection.waypoints) : connection.labelBounds);
		}
	}
	[WKDInkColor() setStroke];
	for (WKDShape *shape in self.diagram.shapes) {
		if (!shape.hasBounds || !NSIntersectsRect(NSInsetRect(shape.bounds, -60, -40), dirty)) {
			continue;
		}
		NSRect label = WKDNodeLabelRect(shape.type, shape.bounds);
		if (!NSIsEmptyRect(label) && [shape.name length] > 0) {
			WKDDrawNode([self lookOf:shape], shape.bounds, NO);
			WKDDrawLabel(shape.name, NSIsEmptyRect(shape.labelBounds) ? label : shape.labelBounds);
		} else {
			WKDDrawNode([self lookOf:shape], shape.bounds, YES);
		}
		BOOL container = WKDIsContainerType(shape.type);
		NSRect outline = NSInsetRect(shape.bounds, -3, -3);
		if ([self.finished containsObject:shape.elementId] && ![self.active containsObject:shape.elementId]
		    && !container) {
			[[WDFinishedColor() colorWithAlphaComponent:0.18] setFill];
			[WKDNodeOutline(shape.type, shape.bounds) fill];
		}
		NSUInteger tokens = [self.active countForObject:shape.elementId];
		if (tokens > 0) {
			NSBezierPath *ring = WKDNodeOutline(shape.type, outline);
			[ring setLineWidth:3];
			[WDActiveColor() setStroke];
			[ring stroke];
			[WKDInkColor() setStroke];
			if (tokens > 1) {
				WDBadge(NSMakePoint(NSMinX(outline), NSMaxY(outline)), tokens, WDActiveColor());
			}
		}
		NSUInteger incidents = [self.incidents countForObject:shape.elementId];
		if (incidents > 0) {
			WDBadge(NSMakePoint(NSMaxX(outline), NSMinY(outline)), incidents, WDIncidentColor());
		}
	}
}

#pragma mark Clicks

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	for (WKDShape *shape in [self.diagram.shapes reverseObjectEnumerator]) {
		if (shape.hasBounds && NSPointInRect(point, NSInsetRect(shape.bounds, -3, -3))) {
			if (self.clicked != nil) {
				self.clicked(shape.elementId);
			}
			return;
		}
	}
	if (self.clicked != nil) {
		self.clicked(nil);
	}
}

@end

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
	/* The area the diagram was last fitted to, and whether it is being
	 * fitted now: fitting resizes the view, which can show or hide the
	 * scroll view's scrollers and so change the area again. */
	NSSize _fittedTo;
	BOOL _fitting;
}

- (void)setUpCanvas
{
	self.dataSource = self;
	self.delegate = self;
	self.margin = 30;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		[self setUpCanvas];
	}
	return self;
}

- (void)awakeFromNib
{
	[self setUpCanvas];
	[super awakeFromNib];
}

/* Fitted again when the area it is shown in changes size; the canvas
 * resizes itself to fill it as well. */
- (void)viewDidMoveToSuperview
{
	[super viewDidMoveToSuperview];
	NSView *clip = [[self enclosingScrollView] contentView];
	if (clip != nil) {
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

- (void)setDiagram:(WKDDiagram *)diagram
{
	_diagram = diagram;
	[self reloadData];
	[self zoomToFit];
}

/* The whole diagram in view, at actual size at most. */
- (void)zoomToFit
{
	if (_fitting) {
		return;
	}
	_fitting = YES;
	_fittedTo = [[self enclosingScrollView] contentSize];
	[self zoomToFit:nil];
	if (self.zoom > 1) {
		self.zoom = 1;
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

#pragma mark The canvas's data source

- (NSRect)diagramBoundsForCanvas:(DKCanvasView *)canvas
{
	NSRect content = self.diagram.contentBounds;
	return NSIsEmptyRect(content) ? NSZeroRect : NSInsetRect(content, -30, -30);
}

- (WKDShape *)shapeAt:(NSPoint)point
{
	for (WKDShape *shape in [self.diagram.shapes reverseObjectEnumerator]) {
		if (shape.hasBounds && NSPointInRect(point, NSInsetRect(shape.bounds, -3, -3))) {
			return shape;
		}
	}
	return nil;
}

- (id)canvas:(DKCanvasView *)canvas itemAtPoint:(NSPoint)point
{
	return [self shapeAt:point].elementId;
}

- (NSArray *)canvas:(DKCanvasView *)canvas itemsInRect:(NSRect)rect
{
	NSMutableArray *items = [NSMutableArray array];
	for (WKDShape *shape in self.diagram.shapes) {
		if (shape.hasBounds && NSIntersectsRect(shape.bounds, rect)) {
			[items addObject:shape.elementId];
		}
	}
	return items;
}

- (NSRect)canvas:(DKCanvasView *)canvas frameOfItem:(id)item
{
	return [self.diagram shapeWithId:item].bounds;
}

- (BOOL)canvas:(DKCanvasView *)canvas canMoveItem:(id)item
{
	return NO;
}

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

/* Drawn with the designer's renderer (WKDRenderer), into the canvas's
 * graphics context: the view and its print. */
- (void)canvas:(DKCanvasView *)canvas
    drawInRect:(NSRect)dirty
       surface:(id<DKSurface>)surface
         state:(DKDrawingState *)state
{
	WKDBeginDrawing(state.dark);
	[self drawDiagramInRect:dirty];
	WKDEndDrawing();
}

- (void)drawDiagramInRect:(NSRect)dirty
{
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

#pragma mark The canvas's delegate

/* A click names what is under it, or nothing: read only, so nothing is
 * selected or moved. */
- (BOOL)canvas:(DKCanvasView *)canvas mouseDown:(NSEvent *)event atPoint:(NSPoint)point
{
	if (self.clicked != nil) {
		self.clicked([self shapeAt:point].elementId);
	}
	return YES;
}

@end

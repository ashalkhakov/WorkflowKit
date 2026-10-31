#import "WDDiagramView.h"
#import "WKDDiagram.h"
#import "WKDRenderer.h"
#import "WKDXML.h"

static DKColor
WDActiveColor(void)
{
	return DKColorMake(0.15, 0.45, 0.9, 1);
}

static DKColor
WDFinishedColor(void)
{
	return DKColorMake(0.2, 0.65, 0.3, 1);
}

static DKColor
WDIncidentColor(void)
{
	return DKColorMake(0.85, 0.15, 0.15, 1);
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
WDBadge(id<DKSurface> surface, NSPoint centre, NSUInteger count, DKColor colour)
{
	NSString *text = [NSString stringWithFormat:@"%lu", (unsigned long)count];
	DKFont *font = [DKFont systemFontOfSize:10 bold:YES];
	NSSize size = [surface sizeOfText:text font:font];
	double diameter = MAX(16, size.width + 8);
	NSRect circle = NSMakeRect(centre.x - diameter / 2, centre.y - 8, diameter, 16);
	[surface fillPath:[DKPath pathWithRoundedRect:circle radius:8] color:colour];
	[surface drawText:text centeredAt:NSMakePoint(NSMidX(circle), NSMidY(circle)) font:font color:DKColorWhite()
	         rotation:DKTextRotationNone];
}

/* Drawn with the designer's renderer (WKDRenderer) through the canvas's
 * surface: the view, a print, an export (PDF, PNG, SVG). */
- (void)canvas:(DKCanvasView *)canvas
    drawInRect:(NSRect)dirty
       surface:(id<DKSurface>)surface
         state:(DKDrawingState *)state
{
	WKDBeginDrawing(state.dark);
	[self drawDiagramInRect:dirty surface:surface];
	WKDEndDrawing();
}

- (void)drawDiagramInRect:(NSRect)dirty surface:(id<DKSurface>)surface
{
	if (self.diagram == nil) {
		NSRect visible = [self visibleRect];
		[surface drawText:self.placeholder ?: @"" centeredAt:NSMakePoint(NSMidX(visible), NSMidY(visible))
		             font:[DKFont systemFontOfSize:12 bold:NO] color:DKColorMake(0.5, 0.5, 0.5, 1)
		         rotation:DKTextRotationNone];
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
			WKDDrawLane(surface, band.bounds, band.name, band.horizontal);
		}
	}
	/* The way taken first, under the shapes. */
	for (WKDConnection *connection in self.diagram.connections) {
		BOOL taken = [self.finished containsObject:connection.source.elementId]
			&& ([self.finished containsObject:connection.target.elementId]
			    || [self.active containsObject:connection.target.elementId]);
		DKColor colour = taken ? WDFinishedColor() : WKDInk();
		if (connection.isAssociation) {
			WKDDrawAssociation(surface, connection.waypoints, colour,
			                   ![WKDAttribute(connection.element, @"associationDirection") ?: @"None" isEqualToString:@"None"]);
		} else {
			WKDDrawFlow(surface, connection.waypoints, colour, connection.isDefault,
			            connection.hasCondition && connection.source.kind == WKDShapeActivity, nil);
		}
		if ([connection.name length] > 0) {
			WKDDrawLabel(surface, connection.name, NSIsEmptyRect(connection.labelBounds)
			                                  ? WKDFlowLabelRect(connection.waypoints) : connection.labelBounds);
		}
	}
	for (WKDShape *shape in self.diagram.shapes) {
		if (!shape.hasBounds || !NSIntersectsRect(NSInsetRect(shape.bounds, -60, -40), dirty)) {
			continue;
		}
		NSRect label = WKDNodeLabelRect(shape.type, shape.bounds);
		if (!NSIsEmptyRect(label) && [shape.name length] > 0) {
			WKDDrawNode(surface, [self lookOf:shape], shape.bounds, NO);
			WKDDrawLabel(surface, shape.name, NSIsEmptyRect(shape.labelBounds) ? label : shape.labelBounds);
		} else {
			WKDDrawNode(surface, [self lookOf:shape], shape.bounds, YES);
		}
		BOOL container = WKDIsContainerType(shape.type);
		NSRect outline = NSInsetRect(shape.bounds, -3, -3);
		if ([self.finished containsObject:shape.elementId] && ![self.active containsObject:shape.elementId]
		    && !container) {
			[surface fillPath:WKDNodeOutline(shape.type, shape.bounds) color:DKColorWithAlpha(WDFinishedColor(), 0.18)];
		}
		NSUInteger tokens = [self.active countForObject:shape.elementId];
		if (tokens > 0) {
			[surface strokePath:WKDNodeOutline(shape.type, outline) color:WDActiveColor() width:3 style:DKStrokeSolid];
			if (tokens > 1) {
				WDBadge(surface, NSMakePoint(NSMinX(outline), NSMaxY(outline)), tokens, WDActiveColor());
			}
		}
		NSUInteger incidents = [self.incidents countForObject:shape.elementId];
		if (incidents > 0) {
			WDBadge(surface, NSMakePoint(NSMaxX(outline), NSMinY(outline)), incidents, WDIncidentColor());
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

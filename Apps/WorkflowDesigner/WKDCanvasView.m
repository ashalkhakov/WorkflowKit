#import "WKDCanvasView.h"
#import "WKDDiagram.h"
#import "WKDEditor.h"
#import "WKDRenderer.h"
#import "WKDXML.h"

typedef NS_ENUM(NSInteger, WKDGesture) {
	WKDGestureNone,
	WKDGestureMove,
	WKDGestureConnect,
	WKDGestureResize,
	WKDGestureBand,
	/* A selected flow's end dragged to another node. */
	WKDGestureReconnect,
	/* A selected flow's bend dragged. */
	WKDGestureBend,
	/* A name dragged on its own. */
	WKDGestureLabel,
};

/* Room around the diagram to draw into. */
static const double WKDRoom = 300;
/* A flow's handles: their size, and how near a click must be. */
static const double WKDHandle = 7;

@implementation WKDCanvasView
{
	WKDGesture _gesture;
	NSPoint _down;
	NSPoint _at;
	NSString *_from;
	/* A reconnection's end, a bend's index. */
	BOOL _atSource;
	NSUInteger _bend;
	/* The selection's order, and the shape a move was started on. */
	NSMutableArray<NSString *> *_order;
	NSString *_grabbed;
	/* The centre lines a move snapped to; NAN when none. */
	double _guideX;
	double _guideY;
	/* The field a name is typed in, and whose name it is. */
	NSTextField *_nameField;
	NSString *_renaming;
	BOOL _cancelRenaming;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_zoom = 1;
		_selection = [NSSet set];
		_guideX = _guideY = NAN;
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	if ((self = [super initWithCoder:coder])) {
		_zoom = 1;
		_selection = [NSSet set];
		_guideX = _guideY = NAN;
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

#pragma mark Size

/* The diagram's extent with room around it, from the origin at least. */
- (NSRect)canvasRect
{
	NSRect content = self.diagram.contentBounds;
	NSRect canvas = NSMakeRect(0, 0, 1, 1);
	if (!NSIsEmptyRect(content)) {
		canvas = NSUnionRect(canvas, NSInsetRect(content, -WKDRoom / 3, -WKDRoom / 3));
		canvas.size.width += WKDRoom;
		canvas.size.height += WKDRoom;
	}
	NSSize visible = [[self enclosingScrollView] contentSize];
	canvas.size.width = MAX(NSWidth(canvas), visible.width / _zoom);
	canvas.size.height = MAX(NSHeight(canvas), visible.height / _zoom);
	return canvas;
}

- (void)resize
{
	NSRect canvas = [self canvasRect];
	[self setFrameSize:NSMakeSize(NSWidth(canvas) * _zoom, NSHeight(canvas) * _zoom)];
	[self setBoundsOrigin:canvas.origin];
	[self setBoundsSize:canvas.size];
	[self setNeedsDisplay:YES];
}

- (void)setDiagram:(WKDDiagram *)diagram
{
	_diagram = diagram;
	/* What was selected and is gone is no longer selected. */
	NSMutableSet *kept = [NSMutableSet set];
	for (NSString *elementId in _selection) {
		if ([diagram shapeWithId:elementId] != nil || [diagram connectionWithId:elementId] != nil) {
			[kept addObject:elementId];
		}
	}
	_selection = kept;
	[self keepOrder];
	if (_renaming != nil && [diagram shapeWithId:_renaming] == nil && [diagram connectionWithId:_renaming] == nil) {
		[self endRenaming:NO];
	}
	[self resize];
}

- (void)setZoom:(double)zoom
{
	_zoom = MAX(0.25, MIN(4, zoom));
	[self resize];
}

- (void)setSelection:(NSSet<NSString *> *)selection
{
	_selection = [selection copy] ?: [NSSet set];
	[self keepOrder];
	[self setNeedsDisplay:YES];
	[self.delegate canvasSelectionDidChange:self];
}

/* What stays selected keeps its place; what is new comes after it, in the
 * diagram's order. */
- (void)keepOrder
{
	NSMutableArray *order = [NSMutableArray array];
	for (NSString *elementId in _order) {
		if ([_selection containsObject:elementId]) {
			[order addObject:elementId];
		}
	}
	NSMutableArray *added = [NSMutableArray array];
	for (WKDShape *shape in self.diagram.shapes) {
		if ([_selection containsObject:shape.elementId] && ![order containsObject:shape.elementId]) {
			[added addObject:shape.elementId];
		}
	}
	for (NSString *elementId in _selection) {
		if (![order containsObject:elementId] && ![added containsObject:elementId]) {
			[added addObject:elementId];
		}
	}
	[order addObjectsFromArray:added];
	_order = order;
}

- (NSArray<NSString *> *)orderedSelection
{
	return [_order copy] ?: @[];
}

- (void)scrollToContent
{
	NSRect content = self.diagram.contentBounds;
	if (!NSIsEmptyRect(content)) {
		[self scrollPoint:NSMakePoint(NSMinX(content) - 40, NSMinY(content) - 40)];
	}
}

- (void)zoomToFit
{
	NSRect content = self.diagram.contentBounds;
	NSSize visible = [[self enclosingScrollView] contentSize];
	if (NSIsEmptyRect(content) || visible.width <= 0 || visible.height <= 0) {
		return;
	}
	content = NSInsetRect(content, -40, -40);
	self.zoom = MIN(2, MIN(visible.width / NSWidth(content), visible.height / NSHeight(content)));
	[self scrollPoint:content.origin];
}

- (IBAction)selectAll:(id)sender
{
	NSMutableSet *all = [NSMutableSet set];
	for (WKDShape *shape in self.diagram.shapes) {
		[all addObject:shape.elementId];
	}
	self.selection = all;
}

#pragma mark Labels

/* Where an event's, a gateway's or a flow's name is drawn: where the
 * diagram puts it, else under the node or over the flow's middle; empty
 * for one without a name, or that holds it inside. */
- (NSRect)labelOfShape:(WKDShape *)shape
{
	if ([shape.name length] == 0) {
		return NSZeroRect;
	}
	NSRect drawn = WKDNodeLabelRect(shape.type, shape.bounds);
	return NSIsEmptyRect(drawn) || NSIsEmptyRect(shape.labelBounds) ? drawn : shape.labelBounds;
}

- (NSRect)labelOfConnection:(WKDConnection *)connection
{
	if ([connection.name length] == 0) {
		return NSZeroRect;
	}
	return NSIsEmptyRect(connection.labelBounds) ? WKDFlowLabelRect(connection.waypoints) : connection.labelBounds;
}

/* The owner of the name at the point. */
- (NSString *)labelAt:(NSPoint)point
{
	for (WKDConnection *connection in self.diagram.connections) {
		if (NSPointInRect(point, [self labelOfConnection:connection])) {
			return connection.elementId;
		}
	}
	for (WKDShape *shape in [self.diagram.shapes reverseObjectEnumerator]) {
		if (shape.hasBounds && NSPointInRect(point, [self labelOfShape:shape])) {
			return shape.elementId;
		}
	}
	return nil;
}

#pragma mark Hit testing

/* The topmost shape at the point: what is drawn last. */
- (WKDShape *)shapeAt:(NSPoint)point
{
	for (WKDShape *shape in [self.diagram.shapes reverseObjectEnumerator]) {
		if (!shape.hasBounds) {
			continue;
		}
		if (WKDIsContainerType(shape.type)) {
			/* A subprocess by its border and title, not its inside. */
			NSRect inner = NSInsetRect(shape.bounds, 8, 8);
			inner.origin.y += 16;
			inner.size.height -= 16;
			if (NSPointInRect(point, shape.bounds) && !NSPointInRect(point, inner)) {
				return shape;
			}
			continue;
		}
		if (NSPointInRect(point, NSInsetRect(shape.bounds, -2, -2))) {
			return shape;
		}
	}
	return nil;
}

/* The pool or lane whose band -- where its name is -- holds the point:
 * the innermost lane's, then the pool's. Only the process's own. */
- (WKDLane *)bandAt:(NSPoint)point
{
	for (WKDLane *lane in [self.diagram.lanes reverseObjectEnumerator]) {
		if (lane.hasBounds && NSPointInRect(point, WKDLaneBandRect(lane.bounds, lane.horizontal))) {
			return lane;
		}
	}
	WKDLane *pool = self.diagram.pool;
	if (pool.hasBounds && NSPointInRect(point, WKDLaneBandRect(pool.bounds, pool.horizontal))) {
		return pool;
	}
	return nil;
}

/* The one pool or lane selected, if one is. */
- (WKDLane *)selectedBand
{
	return [_selection count] == 1 ? [self.diagram laneWithId:[_selection anyObject]] : nil;
}

- (WKDConnection *)connectionAt:(NSPoint)point
{
	for (WKDConnection *connection in self.diagram.connections) {
		if (WKDDistanceToPolyline(point, connection.waypoints) < 5 / _zoom) {
			return connection;
		}
	}
	return nil;
}

/* The one shape selected, if one is. */
- (WKDShape *)selectedShape
{
	return [_selection count] == 1 ? [self.diagram shapeWithId:[_selection anyObject]] : nil;
}

/* The one flow selected, if one is. */
- (WKDConnection *)selectedConnection
{
	return [_selection count] == 1 ? [self.diagram connectionWithId:[_selection anyObject]] : nil;
}

/* The handle a connection is dragged from, beside the selected shape. */
static NSRect
WKDConnectHandle(NSRect bounds)
{
	return NSMakeRect(NSMaxX(bounds) + 6, NSMinY(bounds) - 14, 12, 12);
}

static NSRect
WKDResizeHandle(NSRect bounds)
{
	return NSMakeRect(NSMaxX(bounds) - 8, NSMaxY(bounds) - 8, 10, 10);
}

static NSRect
WKDPointHandle(NSPoint point, double zoom)
{
	double size = WKDHandle / zoom;
	return NSMakeRect(point.x - size / 2, point.y - size / 2, size, size);
}

#pragma mark Drawing

/* How far the selection has been dragged: the pointer's way, with the
 * grabbed shape's centre snapped to another's within a few pixels. */
- (NSSize)moveOffset
{
	NSSize offset = NSMakeSize(_at.x - _down.x, _at.y - _down.y);
	_guideX = _guideY = NAN;
	WKDShape *grabbed = [self.diagram shapeWithId:_grabbed];
	if (grabbed == nil || !grabbed.hasBounds) {
		return offset;
	}
	double snap = 6 / _zoom, bestX = snap, bestY = snap;
	NSPoint centre = NSMakePoint(NSMidX(grabbed.bounds) + offset.width, NSMidY(grabbed.bounds) + offset.height);
	NSSize snapped = offset;
	for (WKDShape *other in self.diagram.shapes) {
		if (!other.hasBounds || [self isMoving:other] || WKDIsContainerType(other.type)) {
			continue;
		}
		double dx = NSMidX(other.bounds) - centre.x, dy = NSMidY(other.bounds) - centre.y;
		if (fabs(dx) < bestX) {
			bestX = fabs(dx);
			snapped.width = offset.width + dx;
			_guideX = NSMidX(other.bounds);
		}
		if (fabs(dy) < bestY) {
			bestY = fabs(dy);
			snapped.height = offset.height + dy;
			_guideY = NSMidY(other.bounds);
		}
	}
	return snapped;
}

/* How far a shape has gone in the gesture under way. */
- (NSSize)offsetOf:(WKDShape *)shape
{
	if (_gesture == WKDGestureMove && [self isMoving:shape]) {
		return [self moveOffset];
	}
	return NSZeroSize;
}

- (NSRect)movedBounds:(WKDShape *)shape
{
	NSSize offset = [self offsetOf:shape];
	NSRect bounds = NSOffsetRect(shape.bounds, offset.width, offset.height);
	if (_gesture == WKDGestureResize && [shape.elementId isEqualToString:_from]) {
		bounds.size.width = MAX(60, NSWidth(bounds) + _at.x - _down.x);
		bounds.size.height = MAX(60, NSHeight(bounds) + _at.y - _down.y);
	}
	return bounds;
}

/* A shape moving with the selection: selected, in a selected subprocess,
 * or on a selected activity. */
- (BOOL)isMoving:(WKDShape *)shape
{
	if (self.diagram.pool != nil && [_selection containsObject:self.diagram.pool.elementId]) {
		return YES;
	}
	for (WKDShape *s = shape; s != nil; s = s.host ?: s.parent) {
		if ([_selection containsObject:s.elementId]) {
			return YES;
		}
	}
	return NO;
}

/* A pool's or lane's bounds as the gesture under way leaves them: moved
 * with its pool, or resized at its bottom right -- the pool's lanes
 * across with it, the lanes below a lane moved down. */
- (NSRect)movedBand:(WKDLane *)lane
{
	NSRect bounds = lane.bounds;
	WKDLane *pool = self.diagram.pool;
	if (_gesture == WKDGestureMove && pool != nil && [_selection containsObject:pool.elementId]
	    && (lane == pool || !lane.isPool)) {
		NSSize offset = [self moveOffset];
		return NSOffsetRect(bounds, offset.width, offset.height);
	}
	WKDLane *resized = _gesture == WKDGestureResize ? [self.diagram laneWithId:_from] : nil;
	if (resized == nil || (lane.isPool && lane != pool)) {
		return bounds;
	}
	double dy = MAX(60, NSHeight(resized.bounds) + _at.y - _down.y) - NSHeight(resized.bounds);
	double end = NSMaxX(resized.bounds) + _at.x - _down.x;
	double line = NSMaxY(resized.bounds);
	if (NSMinY(bounds) >= line - 0.5) {
		bounds.origin.y += dy;
	} else if (NSMaxY(bounds) >= line - 0.5) {
		bounds.size.height += dy;
	}
	bounds.size.width = MAX(100, end - NSMinX(bounds));
	return bounds;
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

/* Where a bend being dragged goes: the pointer, lined up with the points
 * either side of it when it is within a few pixels of their x or y, so
 * that a segment straight across or up and down is easy to come back to. */
- (NSPoint)bendAt:(NSPoint)point of:(WKDConnection *)connection index:(NSUInteger)index
{
	double snap = 8 / _zoom;
	NSArray *points = connection.waypoints;
	for (NSInteger neighbour = (NSInteger)index - 1; neighbour <= (NSInteger)index + 1; neighbour += 2) {
		if (neighbour < 0 || neighbour >= (NSInteger)[points count]) {
			continue;
		}
		NSPoint other = [[points objectAtIndex:(NSUInteger)neighbour] pointValue];
		if (fabs(point.x - other.x) < snap) {
			point.x = other.x;
		}
		if (fabs(point.y - other.y) < snap) {
			point.y = other.y;
		}
	}
	return NSMakePoint(round(point.x), round(point.y));
}

/* The flow's route as the gesture under way leaves it: its ends' shapes
 * moved or resized, a bend dragged. */
- (NSArray<NSValue *> *)pointsOf:(WKDConnection *)connection
{
	NSArray *points = connection.waypoints;
	if (_gesture == WKDGestureBend && [connection.elementId isEqualToString:_from] && _bend < [points count]) {
		NSMutableArray *moved = [points mutableCopy];
		[moved replaceObjectAtIndex:_bend withObject:[NSValue valueWithPoint:[self bendAt:_at of:connection index:_bend]]];
		return moved;
	}
	NSSize from = [self offsetOf:connection.source], to = [self offsetOf:connection.target];
	BOOL resized = _gesture == WKDGestureResize
		&& ([connection.source.elementId isEqualToString:_from] || [connection.target.elementId isEqualToString:_from]);
	if (NSEqualSizes(from, to) && !resized) {
		if (from.width == 0 && from.height == 0) {
			return points;
		}
		NSMutableArray *shifted = [NSMutableArray array];
		for (NSValue *value in points) {
			NSPoint point = [value pointValue];
			[shifted addObject:[NSValue valueWithPoint:NSMakePoint(point.x + from.width, point.y + from.height)]];
		}
		return shifted;
	}
	NSRect source = [self movedBounds:connection.source], target = [self movedBounds:connection.target];
	NSArray *kept = resized ? nil : [WKDEditor keptRoute:points source:source target:target sourceMoved:from
	                                         targetMoved:to];
	return kept ?: [WKDEditor routeFrom:source to:target fromBoundary:connection.source.host != nil
	                        fromGateway:connection.source.kind == WKDShapeGateway
	                         toActivity:connection.target.kind == WKDShapeActivity];
}

- (void)drawRect:(NSRect)dirty
{
	[WKDPaperColor() setFill];
	/* Within the view: since macOS 14 views do not clip to their bounds,
	 * and the rectangle to draw may reach past them -- over the tab bar. */
	NSRectFill(NSIntersectionRect(dirty, [self bounds]));
	NSSize labelMoved = _gesture == WKDGestureLabel ? NSMakeSize(_at.x - _down.x, _at.y - _down.y) : NSZeroSize;
	/* Pools and lanes, under what they hold. */
	NSMutableArray<WKDLane *> *bands = [NSMutableArray arrayWithArray:self.diagram.otherPools];
	if (self.diagram.pool != nil) {
		[bands addObject:self.diagram.pool];
	}
	[bands addObjectsFromArray:self.diagram.lanes];
	for (WKDLane *band in bands) {
		if (band.hasBounds && ![band.elementId isEqualToString:_renaming]) {
			WKDDrawLane([self movedBand:band], band.name, band.horizontal);
		} else if (band.hasBounds) {
			WKDDrawLane([self movedBand:band], nil, band.horizontal);
		}
	}
	for (WKDShape *shape in self.diagram.shapes) {
		if (!shape.hasBounds) {
			continue;
		}
		NSRect bounds = [self movedBounds:shape];
		NSRect label = [self labelOfShape:shape];
		if (!NSIsEmptyRect(label)) {
			NSSize offset = [shape.elementId isEqualToString:_from] && _gesture == WKDGestureLabel
				? labelMoved : [self offsetOf:shape];
			label = NSOffsetRect(label, offset.width, offset.height);
		}
		if (!NSIntersectsRect(NSUnionRect(NSInsetRect(bounds, -60, -40), label), dirty)) {
			continue;
		}
		if ([shape.elementId isEqualToString:_renaming]) {
			WKDLook *look = [self lookOf:shape];
			look.name = nil;
			WKDDrawNode(look, bounds, YES);
		} else if (!NSIsEmptyRect(label)) {
			WKDDrawNode([self lookOf:shape], bounds, NO);
			WKDDrawLabel(shape.name, label);
		} else {
			WKDDrawNode([self lookOf:shape], bounds, YES);
		}
	}
	[WKDInkColor() setStroke];
	for (WKDConnection *connection in self.diagram.connections) {
		NSArray *points = [self pointsOf:connection];
		if ([_selection containsObject:connection.elementId]) {
			[WKDSelectionColor() setStroke];
		}
		if (connection.isAssociation) {
			WKDDrawAssociation(points, ![WKDAttribute(connection.element, @"associationDirection") ?: @"None"
			                              isEqualToString:@"None"]);
		} else {
			WKDDrawFlow(points, connection.isDefault,
			            connection.hasCondition && connection.source.kind == WKDShapeActivity, nil);
		}
		[WKDInkColor() setStroke];
		NSRect label = [self labelOfConnection:connection];
		if (!NSIsEmptyRect(label) && ![connection.elementId isEqualToString:_renaming]) {
			if (NSIsEmptyRect(connection.labelBounds)) {
				label = WKDFlowLabelRect(points);
			} else if (_gesture == WKDGestureLabel && [connection.elementId isEqualToString:_from]) {
				label = NSOffsetRect(label, labelMoved.width, labelMoved.height);
			}
			WKDDrawLabel(connection.name, label);
		}
	}
	for (NSString *elementId in _selection) {
		WKDShape *shape = [self.diagram shapeWithId:elementId];
		WKDLane *band = [self.diagram laneWithId:elementId];
		if (shape.hasBounds) {
			WKDDrawSelection([self movedBounds:shape]);
		} else if (band.hasBounds) {
			WKDDrawSelection([self movedBand:band]);
		}
	}
	/* With several selected, the anchor the others line up with. */
	WKDShape *anchor = [_order count] > 1 ? [self.diagram shapeWithId:[_order firstObject]] : nil;
	if (anchor.hasBounds) {
		NSRect bounds = [self movedBounds:anchor];
		[WKDSelectionColor() setFill];
		NSRectFill(NSMakeRect(NSMinX(bounds) - 8, NSMinY(bounds) - 8, 6 / _zoom + 2, 6 / _zoom + 2));
	}
	if (_gesture == WKDGestureMove) {
		[self moveOffset];
		[self drawGuides];
	}
	[self drawHandles];
	if (_gesture == WKDGestureConnect || _gesture == WKDGestureReconnect) {
		[self drawRubberBand];
	}
	if (_gesture == WKDGestureBand) {
		NSRect band = [self band];
		[[WKDSelectionColor() colorWithAlphaComponent:0.12] setFill];
		NSRectFillUsingOperation(band, NSCompositingOperationSourceOver);
		[WKDSelectionColor() setStroke];
		[NSBezierPath strokeRect:band];
	}
}

/* A selected node's connect and resize handles; a selected flow's ends
 * and bends. */
- (void)drawHandles
{
	if (_gesture != WKDGestureNone) {
		return;
	}
	WKDShape *selected = [self selectedShape];
	if (selected.hasBounds && selected.kind != WKDShapeArtifact) {
		[WKDSelectionColor() setFill];
		NSRect handle = WKDConnectHandle(selected.bounds);
		[[NSBezierPath bezierPathWithOvalInRect:handle] fill];
		NSBezierPath *arrow = [NSBezierPath bezierPath];
		[arrow moveToPoint:NSMakePoint(NSMinX(handle) + 3, NSMidY(handle))];
		[arrow lineToPoint:NSMakePoint(NSMaxX(handle) - 3, NSMidY(handle))];
		[[NSColor whiteColor] setStroke];
		[arrow setLineWidth:1.5];
		[arrow stroke];
		if (WKDIsContainerType(selected.type)) {
			[WKDSelectionColor() setFill];
			NSRectFill(WKDResizeHandle(selected.bounds));
		}
	}
	WKDLane *band = [self selectedBand];
	if (band.hasBounds) {
		[WKDSelectionColor() setFill];
		NSRectFill(WKDResizeHandle(band.bounds));
	}
	WKDConnection *flow = [self selectedConnection];
	if (flow != nil && !flow.isAssociation) {
		NSArray *points = flow.waypoints;
		for (NSUInteger i = 0; i < [points count]; i++) {
			NSRect handle = WKDPointHandle([[points objectAtIndex:i] pointValue], _zoom);
			BOOL end = i == 0 || i + 1 == [points count];
			NSBezierPath *path = end ? [NSBezierPath bezierPathWithRect:handle]
			                         : [NSBezierPath bezierPathWithOvalInRect:handle];
			[(end ? WKDSelectionColor() : WKDPaperColor()) setFill];
			[path fill];
			[WKDSelectionColor() setStroke];
			[path setLineWidth:1 / _zoom];
			[path stroke];
		}
	}
}

/* A new flow or a moved end, dashed from where it stays to the pointer,
 * and the node it would join. */
- (void)drawRubberBand
{
	NSPoint fixed;
	WKDShape *excluded = nil;
	if (_gesture == WKDGestureConnect) {
		excluded = [self.diagram shapeWithId:_from];
		fixed = NSMakePoint(NSMidX(excluded.bounds), NSMidY(excluded.bounds));
	} else {
		WKDConnection *flow = [self.diagram connectionWithId:_from];
		fixed = [(_atSource ? [flow.waypoints lastObject] : [flow.waypoints firstObject]) pointValue];
	}
	NSBezierPath *line = [NSBezierPath bezierPath];
	[line moveToPoint:fixed];
	[line lineToPoint:_at];
	CGFloat pattern[2] = { 5, 3 };
	[line setLineDash:pattern count:2 phase:0];
	[WKDSelectionColor() setStroke];
	[line setLineWidth:1.5];
	[line stroke];
	WKDShape *target = [self shapeAt:_at];
	if (target != nil && target != excluded) {
		WKDDrawSelection(target.bounds);
	}
}

/* The centre lines a move has snapped to, dashed across the view. */
- (void)drawGuides
{
	NSRect visible = [self visibleRect];
	NSBezierPath *guides = [NSBezierPath bezierPath];
	if (!isnan(_guideX)) {
		[guides moveToPoint:NSMakePoint(_guideX, NSMinY(visible))];
		[guides lineToPoint:NSMakePoint(_guideX, NSMaxY(visible))];
	}
	if (!isnan(_guideY)) {
		[guides moveToPoint:NSMakePoint(NSMinX(visible), _guideY)];
		[guides lineToPoint:NSMakePoint(NSMaxX(visible), _guideY)];
	}
	CGFloat pattern[2] = { 4, 4 };
	[guides setLineDash:pattern count:2 phase:0];
	[guides setLineWidth:1 / _zoom];
	[[WKDSelectionColor() colorWithAlphaComponent:0.7] setStroke];
	[guides stroke];
}

- (NSRect)band
{
	return NSMakeRect(MIN(_down.x, _at.x), MIN(_down.y, _at.y), fabs(_at.x - _down.x), fabs(_at.y - _down.y));
}

#pragma mark Mouse and keys

- (NSPoint)pointOf:(NSEvent *)event
{
	return [self convertPoint:[event locationInWindow] fromView:nil];
}

/* A selected flow's handle at the point: its source end, its target end,
 * or a bend. NO when there is none there. */
- (BOOL)flowHandleAt:(NSPoint)point flow:(WKDConnection **)outFlow index:(NSUInteger *)outIndex
{
	WKDConnection *flow = [self selectedConnection];
	if (flow == nil || flow.isAssociation) {
		return NO;
	}
	NSArray *points = flow.waypoints;
	for (NSUInteger i = 0; i < [points count]; i++) {
		NSRect handle = NSInsetRect(WKDPointHandle([[points objectAtIndex:i] pointValue], _zoom), -3 / _zoom, -3 / _zoom);
		if (NSPointInRect(point, handle)) {
			*outFlow = flow;
			*outIndex = i;
			return YES;
		}
	}
	return NO;
}

- (void)mouseDown:(NSEvent *)event
{
	[self endRenaming:YES];
	[[self window] makeFirstResponder:self];
	NSPoint point = [self pointOf:event];
	_down = _at = point;
	_gesture = WKDGestureNone;
	if (self.tool != nil) {
		[self.delegate canvas:self insert:self.tool at:point];
		if (([event modifierFlags] & NSEventModifierFlagOption) == 0) {
			self.tool = nil;
			[self.delegate canvasToolWasUsed:self];
		}
		return;
	}
	WKDShape *selected = [self selectedShape];
	if (selected.hasBounds && NSPointInRect(point, NSInsetRect(WKDConnectHandle(selected.bounds), -3, -3))) {
		_gesture = WKDGestureConnect;
		_from = selected.elementId;
		return;
	}
	if (selected.hasBounds && WKDIsContainerType(selected.type)
	    && NSPointInRect(point, NSInsetRect(WKDResizeHandle(selected.bounds), -3, -3))) {
		_gesture = WKDGestureResize;
		_from = selected.elementId;
		return;
	}
	WKDLane *selectedBand = [self selectedBand];
	if (selectedBand.hasBounds && NSPointInRect(point, NSInsetRect(WKDResizeHandle(selectedBand.bounds), -3, -3))) {
		_gesture = WKDGestureResize;
		_from = selectedBand.elementId;
		return;
	}
	WKDConnection *handleFlow = nil;
	NSUInteger handle = 0;
	if ([self flowHandleAt:point flow:&handleFlow index:&handle]) {
		_from = handleFlow.elementId;
		if (handle == 0 || handle + 1 == [handleFlow.waypoints count]) {
			_gesture = WKDGestureReconnect;
			_atSource = handle == 0;
		} else {
			_gesture = WKDGestureBend;
			_bend = handle;
		}
		return;
	}
	/* Shift or Command: add to the selection, or take out of it. */
	BOOL extend = ([event modifierFlags] & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) != 0;
	NSString *labelled = [self labelAt:point];
	if (labelled != nil && !extend) {
		if ([event clickCount] >= 2) {
			[self beginRenaming:labelled];
			return;
		}
		self.selection = [NSSet setWithObject:labelled];
		_gesture = WKDGestureLabel;
		_from = labelled;
		return;
	}
	WKDShape *shape = [self shapeAt:point];
	if (shape != nil) {
		if ([event clickCount] >= 2 && !extend) {
			self.selection = [NSSet setWithObject:shape.elementId];
			[self beginRenaming:shape.elementId];
			return;
		}
		if (([event modifierFlags] & NSEventModifierFlagOption) != 0) {
			_gesture = WKDGestureConnect;
			_from = shape.elementId;
			return;
		}
		NSMutableSet *selection = [NSMutableSet setWithSet:extend ? _selection : [NSSet set]];
		if (extend && [_selection containsObject:shape.elementId]) {
			[selection removeObject:shape.elementId];
		} else if (!extend && [_selection containsObject:shape.elementId]) {
			selection = [_selection mutableCopy];
		} else {
			[selection addObject:shape.elementId];
		}
		self.selection = selection;
		_gesture = [selection containsObject:shape.elementId] ? WKDGestureMove : WKDGestureNone;
		_grabbed = shape.elementId;
		return;
	}
	WKDConnection *connection = [self connectionAt:point];
	if (connection != nil) {
		self.selection = extend ? [_selection setByAddingObject:connection.elementId] : [NSSet setWithObject:connection.elementId];
		if ([event clickCount] >= 2 && !extend && !connection.isAssociation) {
			[self beginRenaming:connection.elementId];
		}
		return;
	}
	/* A pool or a lane by its band: a pool is dragged with what it holds. */
	WKDLane *band = [self bandAt:point];
	if (band != nil) {
		self.selection = extend ? [_selection setByAddingObject:band.elementId] : [NSSet setWithObject:band.elementId];
		if ([event clickCount] >= 2 && !extend) {
			[self beginRenaming:band.elementId];
			return;
		}
		_gesture = band.isPool && !extend ? WKDGestureMove : WKDGestureNone;
		_grabbed = band.elementId;
		return;
	}
	if (!extend) {
		self.selection = [NSSet set];
	}
	_gesture = WKDGestureBand;
}

- (void)mouseDragged:(NSEvent *)event
{
	if (_gesture == WKDGestureNone) {
		return;
	}
	_at = [self pointOf:event];
	[self autoscroll:event];
	[self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
	WKDGesture gesture = _gesture;
	_gesture = WKDGestureNone;
	_at = [self pointOf:event];
	NSSize offset = NSMakeSize(round(_at.x - _down.x), round(_at.y - _down.y));
	BOOL dragged = fabs(offset.width) >= 2 || fabs(offset.height) >= 2;
	if (gesture == WKDGestureMove) {
		NSSize snapped = [self moveOffset];
		offset = NSMakeSize(round(snapped.width), round(snapped.height));
	}
	switch (gesture) {
	case WKDGestureMove:
		if (dragged) {
			NSMutableArray *shapes = [NSMutableArray array];
			for (NSString *elementId in _selection) {
				if ([self.diagram shapeWithId:elementId] != nil
				    || [elementId isEqualToString:self.diagram.pool.elementId]) {
					[shapes addObject:elementId];
				}
			}
			[self.delegate canvas:self move:shapes by:offset];
		}
		break;
	case WKDGestureConnect: {
		WKDShape *target = [self shapeAt:_at];
		if (target != nil && ![target.elementId isEqualToString:_from]) {
			[self.delegate canvas:self connect:_from to:target.elementId];
		}
		break;
	}
	case WKDGestureReconnect: {
		WKDShape *target = [self shapeAt:_at];
		if (target != nil && dragged) {
			[self.delegate canvas:self reconnect:_from atSource:_atSource to:target.elementId];
		}
		break;
	}
	case WKDGestureBend:
		if (dragged) {
			[self.delegate canvas:self moveBend:_bend of:_from
			                     to:[self bendAt:_at of:[self.diagram connectionWithId:_from] index:_bend]];
		}
		break;
	case WKDGestureLabel:
		if (dragged) {
			[self.delegate canvas:self moveLabelOf:_from by:offset];
		}
		break;
	case WKDGestureResize: {
		WKDShape *shape = [self.diagram shapeWithId:_from];
		WKDLane *band = [self.diagram laneWithId:_from];
		if (shape != nil) {
			[self.delegate canvas:self resize:_from to:[self movedBounds:shape]];
		} else if (band != nil && dragged) {
			[self.delegate canvas:self resize:_from to:[self movedBand:band]];
		}
		break;
	}
	case WKDGestureBand: {
		NSRect band = [self band];
		if (NSWidth(band) > 2 || NSHeight(band) > 2) {
			NSMutableSet *selection = [NSMutableSet setWithSet:_selection];
			for (WKDShape *shape in self.diagram.shapes) {
				if (shape.hasBounds && NSContainsRect(band, shape.bounds)) {
					[selection addObject:shape.elementId];
				}
			}
			self.selection = selection;
		}
		break;
	}
	default:
		break;
	}
	_from = nil;
	_grabbed = nil;
	[self setNeedsDisplay:YES];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	NSPoint point = [self pointOf:event];
	NSString *hit = [self labelAt:point] ?: [self shapeAt:point].elementId ?: [self connectionAt:point].elementId
		?: [self bandAt:point].elementId;
	if (hit != nil && ![_selection containsObject:hit]) {
		self.selection = [NSSet setWithObject:hit];
	}
	return [_selection count] > 0 ? [self.delegate canvasMenu:self] : nil;
}

- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event charactersIgnoringModifiers];
	unichar key = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
	if (key == NSDeleteCharacter || key == NSBackspaceCharacter || key == NSDeleteFunctionKey) {
		[self delete:self];
		return;
	}
	if (key >= NSUpArrowFunctionKey && key <= NSRightArrowFunctionKey && [_selection count] > 0) {
		double step = ([event modifierFlags] & NSEventModifierFlagShift) != 0 ? 10 : 1;
		NSSize by = NSMakeSize(key == NSLeftArrowFunctionKey ? -step : key == NSRightArrowFunctionKey ? step : 0,
		                       key == NSUpArrowFunctionKey ? -step : key == NSDownArrowFunctionKey ? step : 0);
		[self.delegate canvas:self nudge:[self orderedSelection] by:by];
		return;
	}
	if ((key == NSCarriageReturnCharacter || key == NSEnterCharacter) && [_selection count] == 1) {
		[self beginRenaming:[_selection anyObject]];
		return;
	}
	if (key == 27) {
		self.tool = nil;
		[self.delegate canvasToolWasUsed:self];
		self.selection = [NSSet set];
		return;
	}
	[super keyDown:event];
}

- (IBAction)delete:(id)sender
{
	if ([_selection count] > 0) {
		[self.delegate canvas:self delete:[_selection allObjects]];
	}
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	if ([item action] == @selector(delete:)) {
		return [_selection count] > 0;
	}
	return YES;
}

#pragma mark Renaming

/* Where a name is typed: inside a task or subprocess, over its label
 * for an event, a gateway or a flow. */
- (NSRect)nameFieldRectFor:(NSString *)elementId
{
	WKDShape *shape = [self.diagram shapeWithId:elementId];
	if (shape != nil) {
		NSRect label = WKDNodeLabelRect(shape.type, shape.bounds);
		if (NSIsEmptyRect(label)) {
			return WKDIsContainerType(shape.type) || shape.kind == WKDShapeArtifact
				? NSMakeRect(NSMinX(shape.bounds) + 4, NSMinY(shape.bounds) + 2, MAX(NSWidth(shape.bounds) - 8, 80), 22)
				: NSInsetRect(shape.bounds, 4, MAX(4, NSHeight(shape.bounds) / 2 - 22));
		}
		NSRect at = NSIsEmptyRect(shape.labelBounds) ? label : shape.labelBounds;
		return NSMakeRect(NSMidX(at) - 60, NSMinY(at), 120, 40);
	}
	WKDConnection *flow = [self.diagram connectionWithId:elementId];
	if (flow != nil) {
		NSRect at = NSIsEmptyRect(flow.labelBounds) ? WKDFlowLabelRect(flow.waypoints) : flow.labelBounds;
		return NSMakeRect(NSMidX(at) - 60, NSMinY(at), 120, 40);
	}
	WKDLane *band = [self.diagram laneWithId:elementId];
	if (band.hasBounds) {
		NSRect at = WKDLaneBandRect(band.bounds, band.horizontal);
		return NSMakeRect(NSMinX(at) + 2, NSMidY(at) - 11, 200, 22);
	}
	return NSZeroRect;
}

- (void)beginRenaming:(NSString *)elementId
{
	[self endRenaming:YES];
	WKDShape *shape = [self.diagram shapeWithId:elementId];
	WKDConnection *flow = shape == nil ? [self.diagram connectionWithId:elementId] : nil;
	WKDLane *band = shape == nil && flow == nil ? [self.diagram laneWithId:elementId] : nil;
	if ((shape == nil && flow == nil && band == nil) || flow.isAssociation) {
		return;
	}
	NSRect frame = [self nameFieldRectFor:elementId];
	if (NSIsEmptyRect(frame)) {
		return;
	}
	_nameField = [[NSTextField alloc] initWithFrame:frame];
	[_nameField setStringValue:(shape != nil ? shape.name : flow != nil ? flow.name : band.name) ?: @""];
	[_nameField setFont:[NSFont systemFontOfSize:11]];
	[_nameField setAlignment:NSTextAlignmentCenter];
	[_nameField setEditable:YES];
	[_nameField setBezeled:YES];
	[[_nameField cell] setWraps:YES];
	[[_nameField cell] setScrollable:NO];
	[_nameField setDelegate:self];
	_renaming = [elementId copy];
	_cancelRenaming = NO;
	[self addSubview:_nameField];
	[[self window] makeFirstResponder:_nameField];
	[self setNeedsDisplay:YES];
}

/* The field gone; with keep, its name given to the element. */
- (void)endRenaming:(BOOL)keep
{
	if (_nameField == nil) {
		return;
	}
	NSTextField *field = _nameField;
	NSString *elementId = _renaming;
	_nameField = nil;
	_renaming = nil;
	NSString *name = [field stringValue];
	[field setDelegate:nil];
	[field removeFromSuperview];
	[[self window] makeFirstResponder:self];
	[self setNeedsDisplay:YES];
	if (keep && !_cancelRenaming) {
		[self.delegate canvas:self rename:elementId to:name];
	}
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	if ([notification object] == _nameField) {
		[self endRenaming:YES];
	}
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	if (control != _nameField) {
		return NO;
	}
	if (command == @selector(cancelOperation:)) {
		_cancelRenaming = YES;
		[self endRenaming:NO];
		return YES;
	}
	if (command == @selector(insertNewline:)) {
		[self endRenaming:YES];
		return YES;
	}
	return NO;
}

@end

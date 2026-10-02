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
};

/* Room around the diagram to draw into. */
static const double WKDRoom = 300;

@implementation WKDCanvasView
{
	WKDGesture _gesture;
	NSPoint _down;
	NSPoint _at;
	NSString *_from;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_zoom = 1;
		_selection = [NSSet set];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	if ((self = [super initWithCoder:coder])) {
		_zoom = 1;
		_selection = [NSSet set];
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
	[self setNeedsDisplay:YES];
	[self.delegate canvasSelectionDidChange:self];
}

- (void)scrollToContent
{
	NSRect content = self.diagram.contentBounds;
	if (!NSIsEmptyRect(content)) {
		[self scrollPoint:NSMakePoint(NSMinX(content) - 40, NSMinY(content) - 40)];
	}
}

- (IBAction)selectAll:(id)sender
{
	NSMutableSet *all = [NSMutableSet set];
	for (WKDShape *shape in self.diagram.shapes) {
		[all addObject:shape.elementId];
	}
	self.selection = all;
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

#pragma mark Drawing

- (NSRect)movedBounds:(WKDShape *)shape
{
	NSRect bounds = shape.bounds;
	if (_gesture == WKDGestureMove && [self isMoving:shape]) {
		bounds = NSOffsetRect(bounds, _at.x - _down.x, _at.y - _down.y);
	}
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
	for (WKDShape *s = shape; s != nil; s = s.host ?: s.parent) {
		if ([_selection containsObject:s.elementId]) {
			return YES;
		}
	}
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

- (void)drawRect:(NSRect)dirty
{
	[WKDPaperColor() setFill];
	/* Within the view: since macOS 14 views do not clip to their bounds,
	 * and the rectangle to draw may reach past them -- over the tab bar. */
	NSRectFill(NSIntersectionRect(dirty, [self bounds]));
	for (WKDShape *shape in self.diagram.shapes) {
		if (shape.hasBounds && NSIntersectsRect(NSInsetRect([self movedBounds:shape], -60, -40), dirty)) {
			WKDDrawNode([self lookOf:shape], [self movedBounds:shape], YES);
		}
	}
	[WKDInkColor() setStroke];
	for (WKDConnection *connection in self.diagram.connections) {
		NSArray *points = connection.waypoints;
		BOOL moved = _gesture == WKDGestureMove && ([self isMoving:connection.source] || [self isMoving:connection.target]);
		BOOL resized = _gesture == WKDGestureResize
			&& ([connection.source.elementId isEqualToString:_from] || [connection.target.elementId isEqualToString:_from]);
		if (moved || resized) {
			points = [WKDEditor routeFrom:[self movedBounds:connection.source] to:[self movedBounds:connection.target]
			                 fromBoundary:connection.source.host != nil
			                  fromGateway:connection.source.kind == WKDShapeGateway
			                   toActivity:connection.target.kind == WKDShapeActivity];
		}
		if ([_selection containsObject:connection.elementId]) {
			[WKDSelectionColor() setStroke];
		}
		if (connection.isAssociation) {
			WKDDrawAssociation(points, ![WKDAttribute(connection.element, @"associationDirection") ?: @"None"
			                              isEqualToString:@"None"]);
		} else {
			WKDDrawFlow(points, connection.isDefault,
			            connection.hasCondition && connection.source.kind == WKDShapeActivity, connection.name);
		}
		[WKDInkColor() setStroke];
	}
	for (NSString *elementId in _selection) {
		WKDShape *shape = [self.diagram shapeWithId:elementId];
		if (shape.hasBounds) {
			WKDDrawSelection([self movedBounds:shape]);
		}
	}
	WKDShape *selected = [self selectedShape];
	if (selected.hasBounds && _gesture == WKDGestureNone && selected.kind != WKDShapeArtifact) {
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
	if (_gesture == WKDGestureConnect) {
		WKDShape *source = [self.diagram shapeWithId:_from];
		NSBezierPath *line = [NSBezierPath bezierPath];
		[line moveToPoint:NSMakePoint(NSMidX(source.bounds), NSMidY(source.bounds))];
		[line lineToPoint:_at];
		CGFloat pattern[2] = { 5, 3 };
		[line setLineDash:pattern count:2 phase:0];
		[WKDSelectionColor() setStroke];
		[line setLineWidth:1.5];
		[line stroke];
		WKDShape *target = [self shapeAt:_at];
		if (target != nil && target != source) {
			WKDDrawSelection(target.bounds);
		}
	}
	if (_gesture == WKDGestureBand) {
		NSRect band = [self band];
		[[WKDSelectionColor() colorWithAlphaComponent:0.12] setFill];
		NSRectFillUsingOperation(band, NSCompositingOperationSourceOver);
		[WKDSelectionColor() setStroke];
		[NSBezierPath strokeRect:band];
	}
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

- (void)mouseDown:(NSEvent *)event
{
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
	WKDShape *shape = [self shapeAt:point];
	BOOL extend = ([event modifierFlags] & NSEventModifierFlagShift) != 0;
	if (shape != nil) {
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
		return;
	}
	WKDConnection *connection = [self connectionAt:point];
	if (connection != nil) {
		self.selection = extend ? [_selection setByAddingObject:connection.elementId] : [NSSet setWithObject:connection.elementId];
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
	switch (gesture) {
	case WKDGestureMove:
		if (fabs(offset.width) >= 2 || fabs(offset.height) >= 2) {
			NSMutableArray *shapes = [NSMutableArray array];
			for (NSString *elementId in _selection) {
				if ([self.diagram shapeWithId:elementId] != nil) {
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
	case WKDGestureResize: {
		WKDShape *shape = [self.diagram shapeWithId:_from];
		if (shape != nil) {
			[self.delegate canvas:self resize:_from to:[self movedBounds:shape]];
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
	[self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event charactersIgnoringModifiers];
	unichar key = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
	if (key == NSDeleteCharacter || key == NSBackspaceCharacter || key == NSDeleteFunctionKey) {
		[self delete:self];
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

@end

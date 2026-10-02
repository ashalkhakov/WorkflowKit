#import "WKDEditorPriv.h"
#import "WKDLayout.h"
#import "WKDXML.h"

/* Inside a subprocess, around what it holds. */
static const double WKDPadding = 40;
/* Where a laid-out process starts. */
static const double WKDMargin = 80;

@implementation WKDEditor
{
	NSUndoManager *_undoManager;
	/* The change the next coalescing one may join, and when it was. */
	NSString *_coalescedName;
	NSDate *_coalescedAt;
}

#pragma mark Documents

+ (NSXMLDocument *)newProcessDocument
{
	NSXMLElement *root = [[NSXMLElement alloc] initWithName:@"bpmn:definitions" URI:WKDBpmnNamespace];
	NSDictionary *namespaces = @{ @"bpmn": WKDBpmnNamespace, @"bpmndi": WKDBpmnDINamespace,
	                              @"dc": WKDDCNamespace, @"di": WKDDINamespace,
	                              @"camunda": @"http://camunda.org/schema/1.0/bpmn" };
	for (NSString *prefix in @[ @"bpmn", @"bpmndi", @"dc", @"di", @"camunda" ]) {
		[root addNamespace:[NSXMLNode namespaceWithName:prefix stringValue:[namespaces objectForKey:prefix]]];
	}
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:root];
	[document setVersion:@"1.0"];
	[document setCharacterEncoding:@"UTF-8"];
	WKDSetAttribute(root, @"id", @"Definitions_1");
	WKDSetAttribute(root, @"targetNamespace", @"http://bpmn.io/schema/bpmn");
	WKDSetAttribute(root, @"exporter", @"WorkflowDesigner");
	NSXMLElement *process = WKDNewElement(document, WKDBpmnNamespace, @"process");
	WKDSetAttribute(process, @"id", @"Process_1");
	WKDSetAttribute(process, @"isExecutable", @"true");
	[root addChild:process];
	NSXMLElement *start = WKDNewElement(document, WKDBpmnNamespace, @"startEvent");
	WKDSetAttribute(start, @"id", @"StartEvent_1");
	[process addChild:start];
	WKDEditor *editor = [[self alloc] initWithDocument:document undoManager:nil];
	[editor setBounds:NSMakeRect(WKDMargin + 100, WKDMargin + 80, 36, 36) of:@"StartEvent_1"];
	return editor.document;
}

- (instancetype)initWithDocument:(NSXMLDocument *)document undoManager:(NSUndoManager *)undoManager
{
	if ((self = [super init])) {
		_document = document;
		_undoManager = undoManager;
		_diagram = [WKDDiagram diagramOfDocument:document];
	}
	return self;
}

- (void)reread
{
	_diagram = [WKDDiagram diagramOfDocument:_document];
	if (self.changed != nil) {
		self.changed();
	}
}

/* A copy that writes as the original does: Apple's copy drops the XML
 * declaration's standalone. */
static NSXMLDocument *
WKDSnapshot(NSXMLDocument *document)
{
	NSXMLDocument *copy = [document copy];
	if ([copy isStandalone] != [document isStandalone]) {
		[copy setStandalone:[document isStandalone]];
	}
	if ([document version] != nil && ![[copy version] isEqualToString:[document version]]) {
		[copy setVersion:[document version]];
	}
	if ([document characterEncoding] != nil && ![[copy characterEncoding] isEqualToString:[document characterEncoding]]) {
		[copy setCharacterEncoding:[document characterEncoding]];
	}
	return copy;
}

/* One undoable step: the document as it was is what undo restores. The
 * diagram it starts from is held for the change: its shapes' links to one
 * another are weak, and a change reads the document afresh as it goes. */
- (void)change:(NSString *)name with:(void (^)(void))change
{
	[self change:name coalescing:NO with:change];
}

/* With coalescing, a change of the same name made within a second of the
 * last, with nothing undone since, joins its undo step: a burst of arrow
 * key presses is undone at once. */
- (void)change:(NSString *)name coalescing:(BOOL)coalescing with:(void (^)(void))change
{
	__attribute__((objc_precise_lifetime)) WKDDiagram *start = _diagram;
	NSDate *now = [NSDate date];
	BOOL joins = coalescing && _undoManager != nil && [_coalescedName isEqualToString:name]
		&& [now timeIntervalSinceDate:_coalescedAt] < 1.0 && ![_undoManager canRedo]
		&& [[_undoManager undoActionName] isEqualToString:name];
	NSXMLDocument *before = joins ? nil : WKDSnapshot(_document);
	change();
	if (!joins) {
		[_undoManager registerUndoWithTarget:self selector:@selector(restore:) object:before];
		[_undoManager setActionName:name];
	}
	_coalescedName = coalescing ? name : nil;
	_coalescedAt = now;
	[self reread];
}

- (void)restore:(NSXMLDocument *)snapshot
{
	[_undoManager registerUndoWithTarget:self selector:@selector(restore:) object:WKDSnapshot(_document)];
	_document = snapshot;
	[self reread];
}

#pragma mark Identifiers

- (NSMutableSet *)usedIds
{
	NSMutableSet *ids = [NSMutableSet set];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:[_document rootElement]];
	while ([pending count] > 0) {
		NSXMLElement *element = [pending lastObject];
		[pending removeLastObject];
		NSString *elementId = WKDAttribute(element, @"id");
		if (elementId != nil) {
			[ids addObject:elementId];
		}
		for (NSXMLNode *child in [element children]) {
			if ([child kind] == NSXMLElementKind) {
				[pending addObject:child];
			}
		}
	}
	return ids;
}

/* Prefix_ and seven letters and digits, as modellers make them. */
- (NSString *)freshId:(NSString *)prefix
{
	NSSet *used = [self usedIds];
	static const char letters[] = "abcdefghijklmnopqrstuvwxyz0123456789";
	while (YES) {
		char tail[8];
		for (int i = 0; i < 7; i++) {
			tail[i] = letters[arc4random_uniform(36)];
		}
		tail[7] = 0;
		NSString *candidate = [NSString stringWithFormat:@"%@_%s", prefix, tail];
		if (![used containsObject:candidate]) {
			return candidate;
		}
	}
}

NSString *
WKDIdPrefix(NSString *type)
{
	BOOL flowNode = NO;
	switch (WKDKindOfType(type, &flowNode)) {
	case WKDShapeEvent:
		return @"Event";
	case WKDShapeGateway:
		return @"Gateway";
	case WKDShapeActivity:
		return @"Activity";
	default:
		return @"Element";
	}
}

#pragma mark The diagram

+ (NSSize)sizeOfType:(NSString *)type
{
	if (WKDIsContainerType(type)) {
		return NSMakeSize(350, 200);
	}
	switch (WKDKindOfType(type, NULL)) {
	case WKDShapeEvent:
		return NSMakeSize(36, 36);
	case WKDShapeGateway:
		return NSMakeSize(50, 50);
	default:
		return NSMakeSize(100, 80);
	}
}

/* The plane that shows the process, made when the document has none. */
- (NSXMLElement *)plane
{
	if (_diagram.plane != nil) {
		return _diagram.plane;
	}
	NSXMLElement *diagram = WKDNewElement(_document, WKDBpmnDINamespace, @"BPMNDiagram");
	WKDSetAttribute(diagram, @"id", [self freshId:@"BPMNDiagram"]);
	NSXMLElement *plane = WKDNewElement(_document, WKDBpmnDINamespace, @"BPMNPlane");
	WKDSetAttribute(plane, @"id", [self freshId:@"BPMNPlane"]);
	WKDSetAttribute(plane, @"bpmnElement", WKDAttribute(_diagram.process, @"id"));
	[diagram addChild:plane];
	[[_document rootElement] addChild:diagram];
	_diagram = [WKDDiagram diagramOfDocument:_document];
	return plane;
}

/* The DI element that shows the BPMN element: BPMNShape or BPMNEdge. */
- (NSXMLElement *)diagramElement:(NSString *)local of:(NSString *)elementId create:(BOOL)create
{
	NSXMLElement *plane = [self plane];
	for (NSXMLElement *child in WKDChildren(plane, WKDBpmnDINamespace, local)) {
		if ([WKDAttribute(child, @"bpmnElement") isEqualToString:elementId]) {
			return child;
		}
	}
	if (!create) {
		return nil;
	}
	NSXMLElement *element = WKDNewElement(_document, WKDBpmnDINamespace, local);
	NSString *prefix = [local isEqualToString:@"BPMNShape"] ? @"Shape" : @"Edge";
	WKDSetAttribute(element, @"id", [NSString stringWithFormat:@"%@_%@", elementId, prefix]);
	WKDSetAttribute(element, @"bpmnElement", elementId);
	[plane addChild:element];
	return element;
}

- (void)setBounds:(NSRect)bounds of:(NSString *)elementId
{
	NSXMLElement *shape = [self diagramElement:@"BPMNShape" of:elementId create:YES];
	WKDShape *node = [_diagram shapeWithId:elementId];
	if (node != nil && WKDIsContainerType(node.type)) {
		WKDSetAttribute(shape, @"isExpanded", @"true");
	}
	NSXMLElement *box = WKDChild(shape, WKDDCNamespace, @"Bounds");
	if (box == nil) {
		box = WKDNewElement(_document, WKDDCNamespace, @"Bounds");
		[shape insertChild:box atIndex:0];
	}
	WKDSetAttribute(box, @"x", WKDFormat(bounds.origin.x));
	WKDSetAttribute(box, @"y", WKDFormat(bounds.origin.y));
	WKDSetAttribute(box, @"width", WKDFormat(bounds.size.width));
	WKDSetAttribute(box, @"height", WKDFormat(bounds.size.height));
}

- (void)setWaypoints:(NSArray<NSValue *> *)points of:(NSString *)flowId
{
	NSXMLElement *edge = [self diagramElement:@"BPMNEdge" of:flowId create:YES];
	for (NSXMLElement *old in WKDChildren(edge, WKDDINamespace, @"waypoint")) {
		[old detach];
	}
	NSUInteger index = 0;
	for (NSValue *value in points) {
		NSPoint point = [value pointValue];
		NSXMLElement *waypoint = WKDNewElement(_document, WKDDINamespace, @"waypoint");
		WKDSetAttribute(waypoint, @"x", WKDFormat(point.x));
		WKDSetAttribute(waypoint, @"y", WKDFormat(point.y));
		[edge insertChild:waypoint atIndex:index++];
	}
}

- (void)setLabelBounds:(NSRect)bounds of:(NSString *)elementId
{
	NSString *local = [_diagram connectionWithId:elementId] != nil ? @"BPMNEdge" : @"BPMNShape";
	NSXMLElement *owner = [self diagramElement:local of:elementId create:NO];
	if (owner == nil) {
		return;
	}
	NSXMLElement *label = WKDChild(owner, WKDBpmnDINamespace, @"BPMNLabel");
	if (label == nil) {
		label = WKDNewElement(_document, WKDBpmnDINamespace, @"BPMNLabel");
		[owner addChild:label];
	}
	NSXMLElement *box = WKDChild(label, WKDDCNamespace, @"Bounds");
	if (box == nil) {
		box = WKDNewElement(_document, WKDDCNamespace, @"Bounds");
		[label addChild:box];
	}
	WKDSetAttribute(box, @"x", WKDFormat(bounds.origin.x));
	WKDSetAttribute(box, @"y", WKDFormat(bounds.origin.y));
	WKDSetAttribute(box, @"width", WKDFormat(bounds.size.width));
	WKDSetAttribute(box, @"height", WKDFormat(bounds.size.height));
}

static NSValue *
WKDPoint(double x, double y)
{
	return [NSValue valueWithPoint:NSMakePoint(x, y)];
}

+ (NSArray<NSValue *> *)routeFrom:(NSRect)source to:(NSRect)target fromBoundary:(BOOL)fromBoundary
{
	return [self routeFrom:source to:target fromBoundary:fromBoundary fromGateway:NO];
}

+ (NSArray<NSValue *> *)routeFrom:(NSRect)source to:(NSRect)target fromBoundary:(BOOL)fromBoundary
                      fromGateway:(BOOL)fromGateway
{
	return [self routeFrom:source to:target fromBoundary:fromBoundary fromGateway:fromGateway toActivity:NO];
}

+ (NSArray<NSValue *> *)routeFrom:(NSRect)s to:(NSRect)t fromBoundary:(BOOL)fromBoundary
                      fromGateway:(BOOL)fromGateway toActivity:(BOOL)toActivity
{
	if (fromGateway && NSMinX(t) >= NSMaxX(s) && fabs(NSMidY(t) - NSMidY(s)) >= 1) {
		/* Up or down out of the corner, then across into the target. */
		BOOL below = NSMidY(t) > NSMidY(s);
		return @[ WKDPoint(NSMidX(s), below ? NSMaxY(s) : NSMinY(s)), WKDPoint(NSMidX(s), NSMidY(t)),
			WKDPoint(NSMinX(t), NSMidY(t)) ];
	}
	if (fromBoundary) {
		/* Down out of the event, then across. */
		NSPoint start = NSMakePoint(NSMidX(s), NSMaxY(s));
		if (NSMinY(t) > NSMaxY(s) && NSMidX(s) >= NSMinX(t) + 4 && NSMidX(s) <= NSMaxX(t) - 4) {
			/* Right under it: straight down into its top. */
			return @[ [NSValue valueWithPoint:start], WKDPoint(NSMidX(s), NSMinY(t)) ];
		}
		if (NSMidY(t) > NSMaxY(s)) {
			return @[ [NSValue valueWithPoint:start], WKDPoint(NSMidX(s), NSMidY(t)),
				WKDPoint(NSMidX(t) > NSMidX(s) ? NSMinX(t) : NSMaxX(t), NSMidY(t)) ];
		}
	}
	if (NSMinX(t) >= NSMaxX(s) && !fromBoundary && toActivity) {
		/* Level enough to go straight across: the source's middle within
		 * the target, or an activity's side facing the target's middle. */
		if (NSMidY(s) >= NSMinY(t) + 6 && NSMidY(s) <= NSMaxY(t) - 6) {
			return @[ WKDPoint(NSMaxX(s), NSMidY(s)), WKDPoint(NSMinX(t), NSMidY(s)) ];
		}
		if (!fromGateway && NSWidth(s) > 40 && NSMidY(t) >= NSMinY(s) + 6 && NSMidY(t) <= NSMaxY(s) - 6) {
			return @[ WKDPoint(NSMaxX(s), NSMidY(t)), WKDPoint(NSMinX(t), NSMidY(t)) ];
		}
	}
	if (NSMinX(t) >= NSMaxX(s)) {
		NSPoint start = NSMakePoint(NSMaxX(s), NSMidY(s)), end = NSMakePoint(NSMinX(t), NSMidY(t));
		if (fabs(start.y - end.y) < 1) {
			return @[ [NSValue valueWithPoint:start], [NSValue valueWithPoint:end] ];
		}
		if (NSMidX(t) - NSMaxX(s) > 30) {
			/* Across, then up or down into the target's top or bottom. */
			BOOL below = NSMidY(t) > NSMidY(s);
			if (NSMaxX(s) + 20 < NSMidX(t)) {
				return @[ [NSValue valueWithPoint:start], WKDPoint(NSMidX(t), start.y),
					WKDPoint(NSMidX(t), below ? NSMinY(t) : NSMaxY(t)) ];
			}
		}
		double middle = (NSMaxX(s) + NSMinX(t)) / 2;
		return @[ [NSValue valueWithPoint:start], WKDPoint(middle, start.y), WKDPoint(middle, end.y),
			[NSValue valueWithPoint:end] ];
	}
	if (NSMaxX(t) <= NSMinX(s)) {
		/* Backwards: out of the bottom, under both, into the bottom. */
		double under = MAX(NSMaxY(s), NSMaxY(t)) + 30;
		return @[ WKDPoint(NSMidX(s), NSMaxY(s)), WKDPoint(NSMidX(s), under), WKDPoint(NSMidX(t), under),
			WKDPoint(NSMidX(t), NSMaxY(t)) ];
	}
	/* One above the other. */
	BOOL down = NSMidY(t) >= NSMidY(s);
	NSPoint start = NSMakePoint(NSMidX(s), down ? NSMaxY(s) : NSMinY(s));
	NSPoint end = NSMakePoint(NSMidX(t), down ? NSMinY(t) : NSMaxY(t));
	if (fabs(start.x - end.x) < 1) {
		return @[ [NSValue valueWithPoint:start], [NSValue valueWithPoint:end] ];
	}
	double middle = (start.y + end.y) / 2;
	return @[ [NSValue valueWithPoint:start], WKDPoint(start.x, middle), WKDPoint(end.x, middle),
		[NSValue valueWithPoint:end] ];
}

/* Whether a horizontal or vertical segment passes through the rectangle. */
static BOOL
WKDSegmentCrosses(NSPoint a, NSPoint b, NSRect rect)
{
	NSRect segment = NSMakeRect(MIN(a.x, b.x), MIN(a.y, b.y), fabs(a.x - b.x), fabs(a.y - b.y));
	return NSIntersectsRect(NSInsetRect(segment, -0.5, -0.5), rect);
}

/* How many of the shapes in the way the route passes through. */
static NSUInteger
WKDCrossings(NSArray<NSValue *> *route, NSArray<NSValue *> *obstacles)
{
	NSUInteger crossings = 0;
	for (NSValue *obstacle in obstacles) {
		NSRect rect = NSInsetRect([obstacle rectValue], -4, -4);
		for (NSUInteger i = 1; i < [route count]; i++) {
			if (WKDSegmentCrosses([route[i - 1] pointValue], [route[i] pointValue], rect)) {
				crossings++;
				break;
			}
		}
	}
	return crossings;
}

/* The shapes a flow must not pass through: all but its ends, the
 * activity its source is on, and the subprocesses either end is in. */
- (NSArray<NSValue *> *)obstaclesFor:(WKDConnection *)connection
{
	NSMutableSet *allowed = [NSMutableSet set];
	for (WKDShape *end in @[ connection.source, connection.target ]) {
		for (WKDShape *shape = end; shape != nil; shape = shape.parent) {
			[allowed addObject:shape.elementId];
		}
	}
	if (connection.source.host != nil) {
		[allowed addObject:connection.source.host.elementId];
		for (WKDShape *shape = connection.source.host.parent; shape != nil; shape = shape.parent) {
			[allowed addObject:shape.elementId];
		}
	}
	NSMutableArray *obstacles = [NSMutableArray array];
	for (WKDShape *shape in _diagram.shapes) {
		if (shape.hasBounds && ![allowed containsObject:shape.elementId]) {
			[obstacles addObject:[NSValue valueWithRect:shape.bounds]];
		}
	}
	return obstacles;
}

/* The route the router would take, unless it passes through other
 * shapes: then the first of the other ways round that does not, or that
 * passes through fewest. */
- (NSArray<NSValue *> *)routeFor:(WKDConnection *)connection
{
	NSRect s = connection.source.bounds, t = connection.target.bounds;
	BOOL fromBoundary = connection.source.host != nil, fromGateway = connection.source.kind == WKDShapeGateway;
	NSArray *primary = [WKDEditor routeFrom:s to:t fromBoundary:fromBoundary fromGateway:fromGateway
	                             toActivity:connection.target.kind == WKDShapeActivity];
	NSArray *obstacles = [self obstaclesFor:connection];
	if (WKDCrossings(primary, obstacles) == 0) {
		return primary;
	}
	NSMutableArray *candidates = [NSMutableArray arrayWithObject:primary];
	if (NSMinX(t) >= NSMaxX(s) + 20) {
		NSPoint start = fromBoundary ? NSMakePoint(NSMidX(s), NSMaxY(s)) : NSMakePoint(NSMaxX(s), NSMidY(s));
		NSPoint end = NSMakePoint(NSMinX(t), NSMidY(t));
		double between = (NSMaxX(s) + NSMinX(t)) / 2, late = NSMinX(t) - 20, early = NSMaxX(s) + 20;
		for (NSNumber *x in @[ @(between), @(late), @(early) ]) {
			double turn = [x doubleValue];
			if (fromBoundary) {
				/* Down out of the event, across under it, and up or down. */
				double under = NSMaxY(s) + 20;
				[candidates addObject:@[ [NSValue valueWithPoint:start], WKDPoint(start.x, under), WKDPoint(turn, under),
				                         WKDPoint(turn, end.y), [NSValue valueWithPoint:end] ]];
			} else {
				[candidates addObject:@[ [NSValue valueWithPoint:start], WKDPoint(turn, start.y), WKDPoint(turn, end.y),
				                         [NSValue valueWithPoint:end] ]];
			}
		}
	}
	NSArray *best = primary;
	NSUInteger fewest = NSUIntegerMax;
	for (NSArray *candidate in candidates) {
		NSUInteger crossings = WKDCrossings(candidate, obstacles);
		if (crossings < fewest) {
			fewest = crossings;
			best = candidate;
		}
	}
	return best;
}

- (void)reroute:(WKDConnection *)connection
{
	WKDShape *source = connection.source, *target = connection.target;
	if (source.hasBounds && target.hasBounds) {
		[self setWaypoints:[self routeFor:connection] of:connection.elementId];
	}
}

#pragma mark Layout

/* The shapes laid out in the container, relative to its top left; the
 * containers in it laid out first, to know their sizes. */
- (NSSize)layOut:(WKDShape *)container into:(NSMutableDictionary *)frames
{
	NSArray<WKDShape *> *shapes = [_diagram shapesIn:container];
	WKDLayout *layout = [[WKDLayout alloc] init];
	/* Room for the names under events and gateways. */
	layout.layerSpacing = 70;
	layout.nodeSpacing = 60;
	NSMutableDictionary *sizes = [NSMutableDictionary dictionary];
	/* Event subprocesses are joined to nothing: a row of their own,
	 * under the rest. */
	NSMutableArray<WKDShape *> *eventSubProcesses = [NSMutableArray array];
	NSMutableSet *laidOut = [NSMutableSet set];
	for (WKDShape *shape in shapes) {
		NSSize size = [WKDEditor sizeOfType:shape.type];
		if (WKDIsContainerType(shape.type)) {
			NSSize inner = [self layOut:shape into:frames];
			size = NSMakeSize(MAX(size.width, inner.width + 2 * WKDPadding),
			                  MAX(size.height, inner.height + 2 * WKDPadding));
		} else if (shape.hasBounds && shape.kind == WKDShapeActivity) {
			size = shape.bounds.size;
		}
		[sizes setObject:[NSValue valueWithSize:size] forKey:shape.elementId];
		if (shape.eventSubProcess) {
			[eventSubProcesses addObject:shape];
			continue;
		}
		[layout addNode:shape.elementId size:size];
		[laidOut addObject:shape.elementId];
	}
	for (WKDConnection *connection in _diagram.connections) {
		/* A boundary event's flows, and its compensation handler, leave
		 * from the bottom of its activity; an annotation is not laid out
		 * by what it is joined to. */
		WKDShape *source = connection.source.host ?: connection.source;
		if (connection.isAssociation && connection.source.host == nil) {
			continue;
		}
		if ([laidOut containsObject:source.elementId] && [laidOut containsObject:connection.target.elementId]) {
			[layout addEdgeFrom:source.elementId to:connection.target.elementId below:connection.source.host != nil];
		}
	}
	NSDictionary *origins = [layout layout];
	for (NSString *elementId in origins) {
		NSPoint origin = [[origins objectForKey:elementId] pointValue];
		NSSize size = [[sizes objectForKey:elementId] sizeValue];
		[frames setObject:[NSValue valueWithRect:NSMakeRect(origin.x, origin.y, size.width, size.height)]
		           forKey:elementId];
	}
	NSSize size = layout.size;
	if ([eventSubProcesses count] > 0) {
		double x = 0, top = [origins count] > 0 ? size.height + 60 : 0, bottom = top;
		for (WKDShape *shape in eventSubProcesses) {
			NSSize box = [[sizes objectForKey:shape.elementId] sizeValue];
			[frames setObject:[NSValue valueWithRect:NSMakeRect(x, top, box.width, box.height)] forKey:shape.elementId];
			x += box.width + 40;
			bottom = MAX(bottom, top + box.height);
		}
		size = NSMakeSize(MAX(size.width, x - 40), bottom);
	}
	return size;
}

/* Frames relative to their containers made absolute, outermost first;
 * a container that keeps its shape is where it is. */
- (NSRect)absolute:(WKDShape *)shape frames:(NSDictionary *)frames origin:(NSPoint)origin keep:(BOOL)keep
{
	if (keep && shape.hasBounds) {
		return shape.bounds;
	}
	NSRect frame = [[frames objectForKey:shape.elementId] rectValue];
	NSPoint base = origin;
	if (shape.parent != nil) {
		NSRect parent = [self absolute:shape.parent frames:frames origin:origin keep:keep];
		base = NSMakePoint(NSMinX(parent) + WKDPadding, NSMinY(parent) + WKDPadding);
	}
	return NSOffsetRect(frame, base.x, base.y);
}

- (void)placeBoundaryEvents
{
	NSMutableDictionary *byHost = [NSMutableDictionary dictionary];
	for (WKDShape *shape in _diagram.shapes) {
		if (shape.host != nil) {
			NSMutableArray *events = [byHost objectForKey:shape.host.elementId];
			if (events == nil) {
				events = [NSMutableArray array];
				[byHost setObject:events forKey:shape.host.elementId];
			}
			[events addObject:shape];
		}
	}
	/* Leftmost the event whose flows go lowest, so that the routes
	 * down and across out of them do not cross. */
	double (^depth)(WKDShape *) = ^double(WKDShape *event) {
		double lowest = 0;
		for (WKDConnection *connection in [self->_diagram connectionsOf:event]) {
			if (connection.source == event && connection.target.hasBounds) {
				lowest = MAX(lowest, NSMidY(connection.target.bounds));
			}
		}
		return lowest;
	};
	for (NSString *hostId in byHost) {
		NSRect host = [_diagram shapeWithId:hostId].bounds;
		NSArray *events = [[byHost objectForKey:hostId] sortedArrayWithOptions:NSSortStable
		                                                      usingComparator:^NSComparisonResult(WKDShape *a, WKDShape *b) {
			double da = depth(a), db = depth(b);
			return da > db ? NSOrderedAscending : da < db ? NSOrderedDescending : NSOrderedSame;
		}];
		NSUInteger count = [events count];
		for (NSUInteger i = 0; i < count; i++) {
			WKDShape *event = [events objectAtIndex:i];
			double x = NSMinX(host) + NSWidth(host) * (i + 1) / (count + 1);
			[self setBounds:NSMakeRect(x - 18, NSMaxY(host) - 18, 36, 36) of:event.elementId];
		}
	}
}

- (void)layOutAll:(BOOL)onlyMissing
{
	NSMutableDictionary *frames = [NSMutableDictionary dictionary];
	[self layOut:nil into:frames];
	NSPoint origin = NSMakePoint(WKDMargin, WKDMargin);
	if (onlyMissing) {
		/* Below what is there. */
		NSRect content = _diagram.contentBounds;
		if (!NSIsEmptyRect(content)) {
			origin = NSMakePoint(NSMinX(content), NSMaxY(content) + WKDMargin);
		}
	}
	for (WKDShape *shape in _diagram.shapes) {
		if (shape.host != nil || [frames objectForKey:shape.elementId] == nil) {
			continue;
		}
		if (onlyMissing && shape.hasBounds) {
			continue;
		}
		[self setBounds:[self absolute:shape frames:frames origin:origin keep:onlyMissing] of:shape.elementId];
	}
	_diagram = [WKDDiagram diagramOfDocument:_document];
	[self placeBoundaryEvents];
	_diagram = [WKDDiagram diagramOfDocument:_document];
	for (WKDConnection *connection in _diagram.connections) {
		[self reroute:connection];
	}
}

- (void)completeDiagram
{
	if (!_diagram.needsLayout) {
		return;
	}
	[self layOutAll:_diagram.contentBounds.size.width > 0];
	_diagram = [WKDDiagram diagramOfDocument:_document];
}

- (void)arrange
{
	[self change:@"Arrange" with:^{
		[self layOutAll:NO];
	}];
}

#pragma mark Inserting

/* The innermost subprocess whose shape holds the point. */
- (WKDShape *)containerAt:(NSPoint)point
{
	WKDShape *found = nil;
	for (WKDShape *shape in _diagram.shapes) {
		if (WKDIsContainerType(shape.type) && shape.hasBounds && NSPointInRect(point, shape.bounds)) {
			found = shape;
		}
	}
	return found;
}

/* The activity whose edge is near the point. */
- (WKDShape *)activityNear:(NSPoint)point
{
	WKDShape *found = nil;
	for (WKDShape *shape in _diagram.shapes) {
		if (shape.kind == WKDShapeActivity && shape.hasBounds && NSPointInRect(point, NSInsetRect(shape.bounds, -20, -20))) {
			found = shape;
		}
	}
	return found;
}

NSPoint
WKDOnEdge(NSRect host, NSPoint point)
{
	double x = MIN(MAX(point.x, NSMinX(host)), NSMaxX(host));
	double y = MIN(MAX(point.y, NSMinY(host)), NSMaxY(host));
	double left = x - NSMinX(host), right = NSMaxX(host) - x, top = y - NSMinY(host), bottom = NSMaxY(host) - y;
	double nearest = MIN(MIN(left, right), MIN(top, bottom));
	if (nearest == bottom) {
		return NSMakePoint(x, NSMaxY(host));
	}
	if (nearest == top) {
		return NSMakePoint(x, NSMinY(host));
	}
	return NSMakePoint(nearest == left ? NSMinX(host) : NSMaxX(host), y);
}

/* Where in the node a child of this BPMN name goes: incoming and outgoing
 * after its documentation and extension elements, in that order. */
- (void)addReference:(NSString *)local to:(NSString *)flowId in:(NSXMLElement *)node
{
	NSXMLElement *reference = WKDNewElement(_document, WKDBpmnNamespace, local);
	[reference setStringValue:flowId];
	NSArray *before = [local isEqualToString:@"incoming"]
		? @[ @"documentation", @"extensionElements", @"incoming" ]
		: @[ @"documentation", @"extensionElements", @"incoming", @"outgoing" ];
	NSUInteger index = 0;
	NSArray *children = [node children];
	for (NSUInteger i = 0; i < [children count]; i++) {
		NSXMLNode *child = [children objectAtIndex:i];
		if (WKDIs(child, WKDBpmnNamespace, nil) && [before containsObject:[child localName]]) {
			index = i + 1;
		}
	}
	[node insertChild:reference atIndex:index];
}

- (NSString *)insertNodeOfType:(NSString *)type
               eventDefinition:(NSString *)eventDefinition
                            at:(NSPoint)point
                         error:(NSString **)reason
{
	BOOL flowNode = NO;
	WKDKindOfType(type, &flowNode);
	if (!flowNode || _diagram.process == nil) {
		if (reason != NULL) {
			*reason = _diagram.process == nil ? @"The document has no process." : @"That is not a flow node.";
		}
		return nil;
	}
	WKDShape *host = nil;
	if ([type isEqualToString:@"boundaryEvent"]) {
		host = [self activityNear:point];
		if (host == nil) {
			if (reason != NULL) {
				*reason = @"A boundary event goes on the edge of a task or subprocess.";
			}
			return nil;
		}
	}
	WKDShape *container = host != nil ? host.parent : [self containerAt:point];
	NSString *elementId = [self freshId:WKDIdPrefix(type)];
	NSSize size = [WKDEditor sizeOfType:type];
	NSPoint centre = host != nil ? WKDOnEdge(host.bounds, point) : point;
	[self change:@"Add" with:^{
		NSXMLElement *element = WKDNewElement(self->_document, WKDBpmnNamespace, type);
		WKDSetAttribute(element, @"id", elementId);
		if (host != nil) {
			WKDSetAttribute(element, @"attachedToRef", host.elementId);
		}
		if (eventDefinition != nil) {
			NSXMLElement *definition = WKDNewElement(self->_document, WKDBpmnNamespace, eventDefinition);
			NSString *prefix = [[eventDefinition substringToIndex:1] uppercaseString];
			prefix = [prefix stringByAppendingString:[eventDefinition substringFromIndex:1]];
			WKDSetAttribute(definition, @"id", [self freshId:prefix]);
			[element addChild:definition];
		}
		[(container != nil ? container.element : self->_diagram.process) addChild:element];
		self->_diagram = [WKDDiagram diagramOfDocument:self->_document];
		[self setBounds:NSMakeRect(centre.x - size.width / 2, centre.y - size.height / 2, size.width, size.height)
		             of:elementId];
	}];
	return elementId;
}

#pragma mark Connecting

- (NSString *)refusalToConnect:(WKDShape *)source to:(WKDShape *)target except:(NSString *)flowId
{
	WKDShape *sourceScope = source.host != nil ? source.host.parent : source.parent;
	if (source == nil || target == nil || source.kind == WKDShapeArtifact || target.kind == WKDShapeArtifact) {
		return @"Sequence flows join flow nodes.";
	}
	if (source == target) {
		return @"A flow cannot go back into the node it leaves.";
	}
	if ([source.type isEqualToString:@"endEvent"]) {
		return @"Nothing flows out of an end event.";
	}
	if ([target.type isEqualToString:@"startEvent"] || [target.type isEqualToString:@"boundaryEvent"]) {
		return @"Nothing flows into a start or boundary event.";
	}
	if (sourceScope != target.parent) {
		return @"A flow stays within its process or subprocess.";
	}
	for (WKDConnection *connection in _diagram.connections) {
		if (!connection.isAssociation && connection.source == source && connection.target == target
		    && ![connection.elementId isEqualToString:flowId ?: @""]) {
			return @"The two are joined already.";
		}
	}
	return nil;
}

- (NSString *)connect:(NSString *)sourceId to:(NSString *)targetId error:(NSString **)reason
{
	WKDShape *source = [_diagram shapeWithId:sourceId], *target = [_diagram shapeWithId:targetId];
	NSString *refusal = [self refusalToConnect:source to:target except:nil];
	if (refusal != nil) {
		if (reason != NULL) {
			*reason = refusal;
		}
		return nil;
	}
	NSString *flowId = [self freshId:@"Flow"];
	[self change:@"Connect" with:^{
		NSXMLElement *flow = WKDNewElement(self->_document, WKDBpmnNamespace, @"sequenceFlow");
		WKDSetAttribute(flow, @"id", flowId);
		WKDSetAttribute(flow, @"sourceRef", sourceId);
		WKDSetAttribute(flow, @"targetRef", targetId);
		[(target.parent != nil ? target.parent.element : self->_diagram.process) addChild:flow];
		[self addReference:@"outgoing" to:flowId in:source.element];
		[self addReference:@"incoming" to:flowId in:target.element];
		[self setWaypoints:[WKDEditor routeFrom:source.bounds to:target.bounds fromBoundary:source.host != nil
		                            fromGateway:source.kind == WKDShapeGateway
		                             toActivity:target.kind == WKDShapeActivity]
		                of:flowId];
	}];
	return flowId;
}

#pragma mark Moving

/* The shape, what it contains, and what is attached to any of them. */
- (void)collect:(WKDShape *)shape into:(NSMutableSet *)ids
{
	if ([ids containsObject:shape.elementId]) {
		return;
	}
	[ids addObject:shape.elementId];
	for (WKDShape *other in _diagram.shapes) {
		if (other.parent == shape || other.host == shape) {
			[self collect:other into:ids];
		}
	}
}

- (void)moveElements:(NSArray<NSString *> *)elementIds by:(NSSize)offset
{
	if (offset.width == 0 && offset.height == 0) {
		return;
	}
	NSMutableDictionary *offsets = [NSMutableDictionary dictionary];
	for (NSString *elementId in elementIds) {
		[offsets setObject:[NSValue valueWithSize:offset] forKey:elementId];
	}
	[self moveShapes:offsets action:@"Move" coalescing:NO];
}

- (void)moveShapes:(NSDictionary<NSString *, NSValue *> *)offsets action:(NSString *)action coalescing:(BOOL)coalescing
{
	/* Each shape's offset goes to what it holds and what is attached to
	 * it, a container's before its contents'; a boundary event moved
	 * without its activity slides along the activity's edge. */
	NSMutableDictionary<NSString *, NSValue *> *moving = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSValue *> *sliding = [NSMutableDictionary dictionary];
	for (WKDShape *shape in _diagram.shapes) {
		NSValue *offset = [offsets objectForKey:shape.elementId];
		NSSize by = offset != nil ? [offset sizeValue] : NSZeroSize;
		if (offset == nil || (by.width == 0 && by.height == 0) || [moving objectForKey:shape.elementId] != nil) {
			continue;
		}
		if (shape.host != nil && [offsets objectForKey:shape.host.elementId] == nil) {
			[sliding setObject:offset forKey:shape.elementId];
			continue;
		}
		NSMutableSet *held = [NSMutableSet set];
		[self collect:shape into:held];
		for (NSString *heldId in held) {
			if ([moving objectForKey:heldId] == nil) {
				[moving setObject:offset forKey:heldId];
			}
		}
	}
	if ([moving count] == 0 && [sliding count] == 0) {
		return;
	}
	[self change:action coalescing:coalescing with:^{
		/* How far each shape went, its label with it. */
		NSMutableDictionary<NSString *, NSValue *> *moved = [NSMutableDictionary dictionary];
		void (^place)(WKDShape *, NSRect) = ^(WKDShape *shape, NSRect bounds) {
			NSSize by = NSMakeSize(NSMinX(bounds) - NSMinX(shape.bounds), NSMinY(bounds) - NSMinY(shape.bounds));
			[self setBounds:bounds of:shape.elementId];
			if (!NSIsEmptyRect(shape.labelBounds)) {
				[self setLabelBounds:NSOffsetRect(shape.labelBounds, by.width, by.height) of:shape.elementId];
			}
			[moved setObject:[NSValue valueWithSize:by] forKey:shape.elementId];
		};
		for (WKDShape *shape in self->_diagram.shapes) {
			NSValue *offset = [moving objectForKey:shape.elementId];
			if (offset != nil && shape.hasBounds) {
				place(shape, NSOffsetRect(shape.bounds, [offset sizeValue].width, [offset sizeValue].height));
			}
		}
		for (NSString *eventId in sliding) {
			WKDShape *event = [self->_diagram shapeWithId:eventId];
			NSSize offset = [[sliding objectForKey:eventId] sizeValue];
			NSRect bounds = NSOffsetRect(event.bounds, offset.width, offset.height);
			NSPoint centre = WKDOnEdge(event.host.bounds, NSMakePoint(NSMidX(bounds), NSMidY(bounds)));
			place(event, NSMakeRect(centre.x - NSWidth(bounds) / 2, centre.y - NSHeight(bounds) / 2,
			                        NSWidth(bounds), NSHeight(bounds)));
		}
		NSArray *connections = self->_diagram.connections;
		self->_diagram = [WKDDiagram diagramOfDocument:self->_document];
		for (WKDConnection *old in connections) {
			NSValue *fromMove = [moved objectForKey:old.source.elementId];
			NSValue *toMove = [moved objectForKey:old.target.elementId];
			if (fromMove == nil && toMove == nil) {
				continue;
			}
			NSSize from = fromMove != nil ? [fromMove sizeValue] : NSZeroSize;
			NSSize to = toMove != nil ? [toMove sizeValue] : NSZeroSize;
			WKDConnection *now = [self->_diagram connectionWithId:old.elementId];
			NSArray *points = nil;
			if (NSEqualSizes(from, to)) {
				/* Both ends went the same way: the route goes with them. */
				NSMutableArray *shifted = [NSMutableArray array];
				for (NSValue *value in old.waypoints) {
					NSPoint point = [value pointValue];
					[shifted addObject:WKDPoint(point.x + from.width, point.y + from.height)];
				}
				points = shifted;
			} else {
				/* One end went: its bends stay where they were, unless the
				 * route cannot keep them. */
				points = [WKDEditor keptRoute:old.waypoints source:now.source.bounds target:now.target.bounds
				                 sourceMoved:from targetMoved:to] ?: [self routeFor:now];
			}
			[self setWaypoints:points of:old.elementId];
			if (!NSIsEmptyRect(old.labelBounds)) {
				NSRect before = WKDFlowLabelRect(old.waypoints), after = WKDFlowLabelRect(points);
				[self setLabelBounds:NSOffsetRect(old.labelBounds, NSMinX(after) - NSMinX(before),
				                                  NSMinY(after) - NSMinY(before)) of:old.elementId];
			}
		}
	}];
}

- (void)resizeElement:(NSString *)elementId to:(NSRect)bounds
{
	WKDShape *shape = [_diagram shapeWithId:elementId];
	if (shape == nil || NSWidth(bounds) < 20 || NSHeight(bounds) < 20) {
		return;
	}
	[self change:@"Resize" with:^{
		[self setBounds:bounds of:elementId];
		self->_diagram = [WKDDiagram diagramOfDocument:self->_document];
		WKDShape *resized = [self->_diagram shapeWithId:elementId];
		for (WKDShape *event in self->_diagram.shapes) {
			if (event.host == resized) {
				NSPoint centre = WKDOnEdge(bounds, NSMakePoint(NSMidX(event.bounds), NSMidY(event.bounds)));
				[self setBounds:NSMakeRect(centre.x - NSWidth(event.bounds) / 2, centre.y - NSHeight(event.bounds) / 2,
				                           NSWidth(event.bounds), NSHeight(event.bounds)) of:event.elementId];
			}
		}
		self->_diagram = [WKDDiagram diagramOfDocument:self->_document];
		for (WKDConnection *connection in self->_diagram.connections) {
			if (connection.source == resized || connection.target == resized
			    || connection.source.host == resized) {
				[self reroute:connection];
			}
		}
	}];
}

#pragma mark Properties

- (NSXMLElement *)elementWithId:(NSString *)elementId
{
	return WKDElementWithId(_document, elementId);
}

- (BOOL)edit:(NSString *)elementId
      action:(NSString *)action
        with:(void (^)(NSXMLElement *element, NSXMLDocument *document))edit
{
	if ([self elementWithId:elementId] == nil) {
		return NO;
	}
	[self change:action with:^{
		edit([self elementWithId:elementId], self->_document);
	}];
	return YES;
}

- (NSString *)definitionOf:(NSString *)local key:(NSString *)key value:(NSString *)value
{
	NSXMLElement *root = [_document rootElement];
	for (NSXMLElement *definition in WKDChildren(root, WKDBpmnNamespace, local)) {
		if ([WKDAttribute(definition, key) isEqualToString:value]) {
			return WKDAttribute(definition, @"id");
		}
	}
	NSString *prefix = [[local substringToIndex:1] uppercaseString];
	prefix = [prefix stringByAppendingString:[local substringFromIndex:1]];
	NSXMLElement *definition = WKDNewElement(_document, WKDBpmnNamespace, local);
	NSString *definitionId = [self freshId:prefix];
	WKDSetAttribute(definition, @"id", definitionId);
	WKDSetAttribute(definition, @"name", value);
	if (![key isEqualToString:@"name"]) {
		WKDSetAttribute(definition, key, value);
	}
	/* Before the processes, as modellers put them. */
	NSUInteger index = 0;
	NSArray *children = [root children];
	for (NSUInteger i = 0; i < [children count]; i++) {
		if (WKDIs([children objectAtIndex:i], WKDBpmnNamespace, @"process")) {
			index = i;
			break;
		}
		index = i + 1;
	}
	[root insertChild:definition atIndex:index];
	return definitionId;
}

/* An XML name, as an id must be: a letter or underscore, then letters,
 * digits, '-', '_' and '.'. */
static BOOL
WKDIsName(NSString *name)
{
	if ([name length] == 0) {
		return NO;
	}
	NSMutableCharacterSet *first = [NSMutableCharacterSet letterCharacterSet];
	[first addCharactersInString:@"_"];
	NSMutableCharacterSet *rest = [first mutableCopy];
	[rest formUnionWithCharacterSet:[NSCharacterSet decimalDigitCharacterSet]];
	[rest addCharactersInString:@"-."];
	if (![first characterIsMember:[name characterAtIndex:0]]) {
		return NO;
	}
	return [name rangeOfCharacterFromSet:[rest invertedSet]].location == NSNotFound;
}

- (BOOL)renameElement:(NSString *)elementId to:(NSString *)newId error:(NSString **)reason
{
	NSString *refusal = nil;
	if ([newId isEqualToString:elementId]) {
		return YES;
	}
	if (!WKDIsName(newId)) {
		refusal = @"An id is a letter or _, then letters, digits, -, _ and dots.";
	} else if ([self elementWithId:newId] != nil) {
		refusal = [NSString stringWithFormat:@"%@ is the id of another element.", newId];
	} else if ([self elementWithId:elementId] == nil) {
		refusal = @"There is no such element.";
	}
	if (refusal != nil) {
		if (reason != NULL) {
			*reason = refusal;
		}
		return NO;
	}
	[self change:@"Rename" with:^{
		NSArray *references = @[ @"sourceRef", @"targetRef", @"attachedToRef", @"default", @"bpmnElement",
		                         @"processRef", @"activityRef" ];
		NSMutableArray *pending = [NSMutableArray arrayWithObject:[self->_document rootElement]];
		while ([pending count] > 0) {
			NSXMLElement *element = [pending lastObject];
			[pending removeLastObject];
			if ([WKDAttribute(element, @"id") isEqualToString:elementId]) {
				WKDSetAttribute(element, @"id", newId);
			}
			for (NSString *reference in references) {
				if ([WKDAttribute(element, reference) isEqualToString:elementId]) {
					WKDSetAttribute(element, reference, newId);
				}
			}
			if ((WKDIs(element, WKDBpmnNamespace, @"incoming") || WKDIs(element, WKDBpmnNamespace, @"outgoing"))
			    && [[element stringValue] isEqualToString:elementId]) {
				[element setStringValue:newId];
			}
			for (NSXMLNode *child in [element children]) {
				if ([child kind] == NSXMLElementKind) {
					[pending addObject:child];
				}
			}
		}
	}];
	return YES;
}

#pragma mark Deleting

- (void)deleteElements:(NSArray<NSString *> *)elementIds
{
	NSMutableSet *nodes = [NSMutableSet set], *flows = [NSMutableSet set];
	for (NSString *elementId in elementIds) {
		WKDShape *shape = [_diagram shapeWithId:elementId];
		if (shape != nil) {
			[self collect:shape into:nodes];
		} else if ([_diagram connectionWithId:elementId] != nil) {
			[flows addObject:elementId];
		}
	}
	for (WKDConnection *connection in _diagram.connections) {
		if ([nodes containsObject:connection.source.elementId] || [nodes containsObject:connection.target.elementId]) {
			[flows addObject:connection.elementId];
		}
	}
	if ([nodes count] == 0 && [flows count] == 0) {
		return;
	}
	[self change:@"Delete" with:^{
		for (NSString *flowId in flows) {
			WKDConnection *connection = [self->_diagram connectionWithId:flowId];
			for (WKDShape *end in @[ connection.source, connection.target ]) {
				if ([nodes containsObject:end.elementId]) {
					continue;
				}
				for (NSXMLElement *reference in WKDChildren(end.element, WKDBpmnNamespace, nil)) {
					NSString *local = [reference localName];
					if (([local isEqualToString:@"incoming"] || [local isEqualToString:@"outgoing"])
					    && [[reference stringValue] isEqualToString:flowId]) {
						[reference detach];
					}
				}
				if ([WKDAttribute(end.element, @"default") isEqualToString:flowId]) {
					WKDSetAttribute(end.element, @"default", nil);
				}
			}
			[connection.element detach];
		}
		for (NSString *nodeId in nodes) {
			[[self->_diagram shapeWithId:nodeId].element detach];
		}
		NSMutableSet *gone = [NSMutableSet setWithSet:nodes];
		[gone unionSet:flows];
		NSArray *planes = WKDDescendants([self->_document rootElement], WKDBpmnDINamespace, @"BPMNPlane");
		for (NSXMLElement *plane in planes) {
			for (NSXMLElement *child in WKDChildren(plane, WKDBpmnDINamespace, nil)) {
				if ([gone containsObject:WKDAttribute(child, @"bpmnElement") ?: @""]) {
					[child detach];
				}
			}
		}
	}];
}

@end

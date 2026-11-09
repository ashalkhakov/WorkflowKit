#import "WKDEditorPriv.h"
#import <DiagramKit/DKLayeredLayout.h>
#import "WKDXML.h"
#import "WKDJournal.h"
#import "WKDModelPriv.h"

/* Inside a subprocess, around what it holds. */
static const double WKDPadding = 40;
/* Where a laid-out process starts. */
static const double WKDMargin = 80;

@implementation WKDEditor
{
	NSUndoManager *_undoManager;
	/* The step a coalescing change may join. */
	WKDJournalStep *_lastStep;
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
		_model = [WKDModel modelOfDocument:document];
	}
	return self;
}

NSString * const WKDEditorDidChangeNotification = @"WKDEditorDidChange";
NSString * const WKDEditorWillRenameNotification = @"WKDEditorWillRename";

static BOOL WKDChecksAgreement = NO;

+ (BOOL)checksAgreement
{
	return WKDChecksAgreement;
}

+ (void)setChecksAgreement:(BOOL)checks
{
	WKDChecksAgreement = checks;
}

- (void)reread
{
	if (_model == nil) {
		_model = [WKDModel modelOfDocument:_document];
	}
	if (WKDChecksAgreement && _model != nil) {
		NSString *disagreement = [_model disagreementWith:[WKDModel modelOfDocument:_document]]
			?: [_model.journal indexDisagreement];
		if (disagreement != nil) {
			[NSException raise:NSInternalInconsistencyException format:@"the model disagrees with its document: %@", disagreement];
		}
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDEditorDidChangeNotification object:self];
}

/* One undoable step: what it changes is what undo takes back. */
- (void)change:(NSString *)name with:(void (^)(void))change
{
	[self change:name coalescing:NO with:change];
}

/* With coalescing, a change of the same name made within a second of the
 * last, with nothing undone since, joins its undo step: a burst of arrow
 * key presses is undone at once. */
- (void)change:(NSString *)name coalescing:(BOOL)coalescing with:(void (^)(void))change
{
	NSDate *now = [NSDate date];
	BOOL joins = coalescing && _undoManager != nil && _lastStep != nil && [_coalescedName isEqualToString:name]
		&& [now timeIntervalSinceDate:_coalescedAt] < 1.0 && ![_undoManager canRedo]
		&& [[_undoManager undoActionName] isEqualToString:name];
	WKDJournal *journal = _model.journal;
	[journal begin];
	self.needsSync = NO;
	change();
	[_model write];
	[self keepLanes];
	[_model write];
	if (self.needsSync) {
		[self syncModel];
		self.needsSync = NO;
	}
	WKDJournalStep *step = [journal end];
	if (step != nil) {
		if (joins) {
			[journal merge:step into:_lastStep];
		} else {
			[_undoManager registerUndoWithTarget:self selector:@selector(undoStep:) object:step];
			[_undoManager setActionName:name];
			_lastStep = step;
		}
	}
	_coalescedName = coalescing ? name : nil;
	_coalescedAt = now;
	[self reread];
}

/* The model read again from the document, every element's state and the
 * model's lists recorded first, so that undo puts them back. */
- (void)syncModel
{
	WKDJournal *journal = _model.journal;
	[journal willChangeModel];
	for (WKDNode *node in _model.nodes) {
		[journal willChange:node];
	}
	for (WKDFlow *flow in _model.flows) {
		[journal willChange:flow];
	}
	for (WKDLane *lane in _model.lanes) {
		[journal willChange:lane];
	}
	for (WKDLane *pool in _model.otherPools) {
		[journal willChange:pool];
	}
	[journal willChange:_model.pool];
	[_model readDocumentAgain:_document];
}

- (void)undoStep:(WKDJournalStep *)step
{
	WKDJournalStep *inverse = [_model.journal undo:step];
	[_undoManager registerUndoWithTarget:self selector:@selector(undoStep:) object:inverse];
	_lastStep = nil;
	[self reread];
}

#pragma mark Identifiers

/* Prefix_ and seven letters and digits, as modellers make them. */
- (NSString *)freshId:(NSString *)prefix
{
	static const char letters[] = "abcdefghijklmnopqrstuvwxyz0123456789";
	while (YES) {
		char tail[8];
		for (int i = 0; i < 7; i++) {
			tail[i] = letters[arc4random_uniform(36)];
		}
		tail[7] = 0;
		NSString *candidate = [NSString stringWithFormat:@"%@_%s", prefix, tail];
		if ([_model.journal elementWithId:candidate] == nil) {
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
	return [_model ensurePlane];
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
	WKDLogAttribute(self.model.journal, element, @"id", [NSString stringWithFormat:@"%@_%@", elementId, prefix]);
	WKDLogAttribute(self.model.journal, element, @"bpmnElement", elementId);
	WKDLogAdd(self.model.journal, plane, element);
	return element;
}

/* The model's element of the id. One an operation has just made in the XML
 * is read into the model first, until every operation makes its elements
 * in the model. */
- (WKDModelElement *)modelElement:(NSString *)elementId
{
	WKDModelElement *element = [_model nodeWithId:elementId] ?: [_model flowWithId:elementId]
		?: (WKDModelElement *)[_model laneWithId:elementId];
	if (element == nil && elementId != nil) {
		[self syncModel];
		element = [_model nodeWithId:elementId] ?: [_model flowWithId:elementId]
			?: (WKDModelElement *)[_model laneWithId:elementId];
	}
	return element;
}

/* Diagrams are written in whole points: the model holds what is written. */
static NSRect
WKDWholeRect(NSRect rect)
{
	return NSMakeRect(round(rect.origin.x), round(rect.origin.y), round(rect.size.width), round(rect.size.height));
}

static NSArray<NSValue *> *
WKDWholePoints(NSArray<NSValue *> *points)
{
	NSMutableArray *whole = [NSMutableArray arrayWithCapacity:[points count]];
	for (NSValue *value in points) {
		NSPoint point = [value pointValue];
		[whole addObject:[NSValue valueWithPoint:NSMakePoint(round(point.x), round(point.y))]];
	}
	return whole;
}

/* The geometry is the model's: set there and written at once, so what the
 * rest of a change reads of the XML is what it set. */
- (void)setBounds:(NSRect)bounds of:(NSString *)elementId
{
	bounds = WKDWholeRect(bounds);
	WKDModelElement *element = [self modelElement:elementId];
	if (element == nil) {
		/* An element not yet in the document (a lane being made): its shape
		 * by its id, as before the model. */
		NSXMLElement *shape = [self diagramElement:@"BPMNShape" of:elementId create:YES];
		NSXMLElement *box = WKDChild(shape, WKDDCNamespace, @"Bounds");
		if (box == nil) {
			box = WKDNewElement(_document, WKDDCNamespace, @"Bounds");
			WKDLogInsert(self.model.journal, shape, box, 0);
		}
		WKDLogAttribute(self.model.journal, box, @"x", WKDFormat(bounds.origin.x));
		WKDLogAttribute(self.model.journal, box, @"y", WKDFormat(bounds.origin.y));
		WKDLogAttribute(self.model.journal, box, @"width", WKDFormat(bounds.size.width));
		WKDLogAttribute(self.model.journal, box, @"height", WKDFormat(bounds.size.height));
		return;
	}
	if ([element isKindOfClass:[WKDFlow class]]) {
		return;
	}
	[_model.journal willChange:element];
	if ([element isKindOfClass:[WKDNode class]]) {
		((WKDNode *)element).bounds = bounds;
		((WKDNode *)element).hasBounds = YES;
	} else {
		((WKDLane *)element).bounds = bounds;
		((WKDLane *)element).hasBounds = YES;
	}
	[_model writeGeometryOf:element];
}

- (void)setWaypoints:(NSArray<NSValue *> *)points of:(NSString *)flowId
{
	WKDFlow *flow = (WKDFlow *)[self modelElement:flowId];
	if (![flow isKindOfClass:[WKDFlow class]]) {
		return;
	}
	[_model.journal willChange:flow];
	flow.waypoints = WKDWholePoints(points);
	[_model writeGeometryOf:flow];
}

- (void)setLabelBounds:(NSRect)bounds of:(NSString *)elementId
{
	WKDModelElement *element = [self modelElement:elementId];
	WKDFlow *flow = [element isKindOfClass:[WKDFlow class]] ? (WKDFlow *)element : nil;
	WKDNode *node = [element isKindOfClass:[WKDNode class]] ? (WKDNode *)element : nil;
	/* A label goes on a shape or an edge that is there. */
	if ((flow == nil && node == nil) || (flow ?: (WKDModelElement *)node).diagramElement == nil) {
		return;
	}
	[_model.journal willChange:element];
	bounds = WKDWholeRect(bounds);
	if (flow != nil) {
		flow.labelBounds = bounds;
	} else {
		node.labelBounds = bounds;
	}
	[_model writeGeometryOf:element];
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
- (NSArray<NSValue *> *)obstaclesFor:(WKDFlow *)connection
{
	NSMutableSet *allowed = [NSMutableSet set];
	for (WKDNode *end in @[ connection.source, connection.target ]) {
		for (WKDNode *shape = end; shape != nil; shape = shape.parent) {
			[allowed addObject:shape.elementId];
		}
	}
	if (connection.source.host != nil) {
		[allowed addObject:connection.source.host.elementId];
		for (WKDNode *shape = connection.source.host.parent; shape != nil; shape = shape.parent) {
			[allowed addObject:shape.elementId];
		}
	}
	NSMutableArray *obstacles = [NSMutableArray array];
	for (WKDNode *shape in _model.nodes) {
		if (shape.hasBounds && ![allowed containsObject:shape.elementId]) {
			[obstacles addObject:[NSValue valueWithRect:shape.bounds]];
		}
	}
	return obstacles;
}

/* The route the router would take, unless it passes through other
 * shapes: then the first of the other ways round that does not, or that
 * passes through fewest. */
- (NSArray<NSValue *> *)routeFor:(WKDFlow *)connection
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

- (void)reroute:(WKDFlow *)connection
{
	WKDNode *source = connection.source, *target = connection.target;
	if (source.hasBounds && target.hasBounds) {
		[self setWaypoints:[self routeFor:connection] of:connection.elementId];
	}
}

#pragma mark Layout

/* The shapes laid out in the container, relative to its top left; the
 * containers in it laid out first, to know their sizes. */
- (NSSize)layOut:(WKDNode *)container into:(NSMutableDictionary *)frames
{
	NSArray<WKDNode *> *shapes = [_model nodesIn:container];
	/* DiagramKit's layered layout, left to right, as a process reads. */
	DKLayeredLayout *layout = [[DKLayeredLayout alloc] init];
	/* Room for the names under events and gateways. */
	layout.layerSpacing = 70;
	layout.nodeSpacing = 60;
	NSMutableDictionary *sizes = [NSMutableDictionary dictionary];
	/* Event subprocesses are joined to nothing: a row of their own,
	 * under the rest. */
	NSMutableArray<WKDNode *> *eventSubProcesses = [NSMutableArray array];
	NSMutableSet *laidOut = [NSMutableSet set];
	for (WKDNode *shape in shapes) {
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
	for (WKDFlow *connection in _model.flows) {
		/* A boundary event's flows, and its compensation handler, leave
		 * from the bottom of its activity; an annotation is not laid out
		 * by what it is joined to. */
		WKDNode *source = connection.source.host ?: connection.source;
		if (connection.isAssociation && connection.source.host == nil) {
			continue;
		}
		if ([laidOut containsObject:source.elementId] && [laidOut containsObject:connection.target.elementId]) {
			[layout addEdgeFrom:source.elementId to:connection.target.elementId below:connection.source.host != nil];
		}
	}
	NSDictionary *origins = [layout layout];
	for (NSString *elementId in origins) {
		NSPoint origin = [[origins objectForKey:elementId] rectValue].origin;
		NSSize size = [[sizes objectForKey:elementId] sizeValue];
		[frames setObject:[NSValue valueWithRect:NSMakeRect(origin.x, origin.y, size.width, size.height)]
		           forKey:elementId];
	}
	NSSize size = layout.size;
	if ([eventSubProcesses count] > 0) {
		double x = 0, top = [origins count] > 0 ? size.height + 60 : 0, bottom = top;
		for (WKDNode *shape in eventSubProcesses) {
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
- (NSRect)absolute:(WKDNode *)shape frames:(NSDictionary *)frames origin:(NSPoint)origin keep:(BOOL)keep
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
	for (WKDNode *shape in _model.nodes) {
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
	double (^depth)(WKDNode *) = ^double(WKDNode *event) {
		double lowest = 0;
		for (WKDFlow *connection in [self->_model flowsOf:event]) {
			if (connection.source == event && connection.target.hasBounds) {
				lowest = MAX(lowest, NSMidY(connection.target.bounds));
			}
		}
		return lowest;
	};
	for (NSString *hostId in byHost) {
		NSRect host = [_model nodeWithId:hostId].bounds;
		NSArray *events = [[byHost objectForKey:hostId] sortedArrayWithOptions:NSSortStable
		                                                      usingComparator:^NSComparisonResult(WKDNode *a, WKDNode *b) {
			double da = depth(a), db = depth(b);
			return da > db ? NSOrderedAscending : da < db ? NSOrderedDescending : NSOrderedSame;
		}];
		NSUInteger count = [events count];
		for (NSUInteger i = 0; i < count; i++) {
			WKDNode *event = [events objectAtIndex:i];
			double x = NSMinX(host) + NSWidth(host) * (i + 1) / (count + 1);
			[self setBounds:NSMakeRect(x - 18, NSMaxY(host) - 18, 36, 36) of:event.elementId];
		}
	}
}

- (void)layOutAll:(BOOL)onlyMissing
{
	/* Each node stays in its lane, which its new place would not say. */
	NSDictionary *membership = [self laneMembership];
	BOOL bandsMissing = _model.pool != nil && !_model.pool.hasBounds;
	for (WKDLane *lane in _model.lanes) {
		bandsMissing = bandsMissing || !lane.hasBounds;
	}
	NSMutableDictionary *frames = [NSMutableDictionary dictionary];
	[self layOut:nil into:frames];
	NSPoint origin = NSMakePoint(WKDMargin, WKDMargin);
	if (onlyMissing) {
		/* Below what is there. */
		NSRect content = _model.contentBounds;
		if (!NSIsEmptyRect(content)) {
			origin = NSMakePoint(NSMinX(content), NSMaxY(content) + WKDMargin);
		}
	}
	for (WKDNode *shape in _model.nodes) {
		if (shape.host != nil || [frames objectForKey:shape.elementId] == nil) {
			continue;
		}
		if (onlyMissing && shape.hasBounds) {
			continue;
		}
		[self setBounds:[self absolute:shape frames:frames origin:origin keep:onlyMissing] of:shape.elementId];
	}
	[self placeBoundaryEvents];
	if (!onlyMissing || bandsMissing) {
		[self stackLanes:membership];
	}
	for (WKDFlow *connection in _model.flows) {
		[self reroute:connection];
	}
}

- (void)completeDiagram
{
	if (!_model.needsLayout) {
		return;
	}
	[self layOutAll:_model.contentBounds.size.width > 0];
}

- (void)arrange
{
	[self change:@"Arrange" with:^{
		[self layOutAll:NO];
	}];
}

#pragma mark Inserting

/* The innermost subprocess whose shape holds the point. */
- (WKDNode *)containerAt:(NSPoint)point
{
	WKDNode *found = nil;
	for (WKDNode *shape in _model.nodes) {
		if (WKDIsContainerType(shape.type) && shape.hasBounds && NSPointInRect(point, shape.bounds)) {
			found = shape;
		}
	}
	return found;
}

/* The activity whose edge is near the point. */
- (WKDNode *)activityNear:(NSPoint)point
{
	WKDNode *found = nil;
	for (WKDNode *shape in _model.nodes) {
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
	WKDLogText(self.model.journal, reference, flowId);
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
	WKDLogInsert(self.model.journal, node, reference, index);
}

- (NSString *)insertNodeOfType:(NSString *)type
               eventDefinition:(NSString *)eventDefinition
                            at:(NSPoint)point
                         error:(NSString **)reason
{
	BOOL flowNode = NO;
	WKDKindOfType(type, &flowNode);
	if (!flowNode || _model.process == nil) {
		if (reason != NULL) {
			*reason = _model.process == nil ? @"The document has no process." : @"That is not a flow node.";
		}
		return nil;
	}
	WKDNode *host = nil;
	if ([type isEqualToString:@"boundaryEvent"]) {
		host = [self activityNear:point];
		if (host == nil) {
			if (reason != NULL) {
				*reason = @"A boundary event goes on the edge of a task or subprocess.";
			}
			return nil;
		}
	}
	WKDNode *container = host != nil ? host.parent : [self containerAt:point];
	NSString *elementId = [self freshId:WKDIdPrefix(type)];
	NSSize size = [WKDEditor sizeOfType:type];
	NSPoint centre = host != nil ? WKDOnEdge(host.bounds, point) : point;
	[self change:@"Add" with:^{
		WKDModel *model = self->_model;
		WKDNode *node = [model makeNodeOfType:type elementId:elementId in:[model nodeWithId:container.elementId]];
		node.eventDefinition = eventDefinition;
		if (host != nil) {
			[model setHost:[model nodeWithId:host.elementId] ofNode:node];
		}
		node.bounds = NSMakeRect(centre.x - size.width / 2, centre.y - size.height / 2, size.width, size.height);
		node.hasBounds = YES;
		[model write];
	}];
	return elementId;
}

#pragma mark Connecting

- (NSString *)refusalToConnect:(WKDNode *)source to:(WKDNode *)target except:(NSString *)flowId
{
	WKDNode *sourceScope = source.host != nil ? source.host.parent : source.parent;
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
	for (WKDFlow *connection in _model.flows) {
		if (!connection.isAssociation && connection.source == source && connection.target == target
		    && ![connection.elementId isEqualToString:flowId ?: @""]) {
			return @"The two are joined already.";
		}
	}
	return nil;
}

- (NSString *)connect:(NSString *)sourceId to:(NSString *)targetId error:(NSString **)reason
{
	WKDNode *source = [_model nodeWithId:sourceId], *target = [_model nodeWithId:targetId];
	NSString *refusal = [self refusalToConnect:source to:target except:nil];
	if (refusal != nil) {
		if (reason != NULL) {
			*reason = refusal;
		}
		return nil;
	}
	NSString *flowId = [self freshId:@"Flow"];
	[self change:@"Connect" with:^{
		WKDModel *model = self->_model;
		WKDFlow *flow = [model makeFlowFrom:[model nodeWithId:sourceId] to:[model nodeWithId:targetId] elementId:flowId
		                        association:NO];
		flow.waypoints = [WKDEditor routeFrom:source.bounds to:target.bounds fromBoundary:source.host != nil
		                          fromGateway:source.kind == WKDShapeGateway
		                           toActivity:target.kind == WKDShapeActivity];
		[model write];
	}];
	return flowId;
}

#pragma mark Moving

/* The shape, what it contains, and what is attached to any of them. */
- (void)collect:(WKDNode *)shape into:(NSMutableSet *)ids
{
	if ([ids containsObject:shape.elementId]) {
		return;
	}
	[ids addObject:shape.elementId];
	for (WKDNode *other in [shape.children arrayByAddingObjectsFromArray:shape.attached]) {
		[self collect:other into:ids];
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
	/* The pool takes what it holds and its lanes with it. */
	WKDLane *pool = _model.pool;
	NSValue *poolOffset = pool != nil ? [offsets objectForKey:pool.elementId] : nil;
	if (poolOffset != nil) {
		NSMutableDictionary *all = [offsets mutableCopy];
		for (WKDNode *shape in _model.nodes) {
			if (shape.parent == nil && shape.host == nil) {
				[all setObject:poolOffset forKey:shape.elementId];
			}
		}
		offsets = all;
	}
	NSMutableDictionary<NSString *, NSValue *> *moving = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSValue *> *sliding = [NSMutableDictionary dictionary];
	for (WKDNode *shape in _model.nodes) {
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
	if ([moving count] == 0 && [sliding count] == 0 && poolOffset == nil) {
		return;
	}
	[self change:action coalescing:coalescing with:^{
		if (poolOffset != nil) {
			NSSize by = [poolOffset sizeValue];
			NSMutableArray *bands = [NSMutableArray arrayWithArray:self->_model.lanes];
			[bands addObject:pool];
			for (WKDLane *band in bands) {
				if (band.hasBounds) {
					[self setBounds:NSOffsetRect(band.bounds, by.width, by.height) of:band.elementId];
				}
			}
		}
		/* The routes of the flows that touch what moves, as they were. */
		NSMutableArray<WKDFlow *> *touching = [NSMutableArray array];
		NSMapTable<WKDFlow *, NSArray *> *routes = [NSMapTable strongToStrongObjectsMapTable];
		NSMapTable<WKDFlow *, NSValue *> *labels = [NSMapTable strongToStrongObjectsMapTable];
		NSMutableArray *ends = [NSMutableArray arrayWithArray:[moving allKeys]];
		[ends addObjectsFromArray:[sliding allKeys]];
		for (NSString *endId in ends) {
			for (WKDFlow *flow in [self->_model flowsOf:[self->_model nodeWithId:endId]]) {
				if ([routes objectForKey:flow] == nil) {
					[touching addObject:flow];
					[routes setObject:flow.waypoints ?: @[] forKey:flow];
					[labels setObject:[NSValue valueWithRect:flow.labelBounds] forKey:flow];
				}
			}
		}
		/* How far each shape went, its label with it. */
		NSMutableDictionary<NSString *, NSValue *> *moved = [NSMutableDictionary dictionary];
		void (^place)(WKDNode *, NSRect) = ^(WKDNode *shape, NSRect bounds) {
			NSSize by = NSMakeSize(NSMinX(bounds) - NSMinX(shape.bounds), NSMinY(bounds) - NSMinY(shape.bounds));
			if (!NSIsEmptyRect(shape.labelBounds)) {
				[self setLabelBounds:NSOffsetRect(shape.labelBounds, by.width, by.height) of:shape.elementId];
			}
			[self setBounds:bounds of:shape.elementId];
			[moved setObject:[NSValue valueWithSize:by] forKey:shape.elementId];
		};
		for (WKDNode *shape in self->_model.nodes) {
			NSValue *offset = [moving objectForKey:shape.elementId];
			if (offset != nil && shape.hasBounds) {
				place(shape, NSOffsetRect(shape.bounds, [offset sizeValue].width, [offset sizeValue].height));
			}
		}
		for (NSString *eventId in sliding) {
			WKDNode *event = [self->_model nodeWithId:eventId];
			NSSize offset = [[sliding objectForKey:eventId] sizeValue];
			NSRect bounds = NSOffsetRect(event.bounds, offset.width, offset.height);
			NSPoint centre = WKDOnEdge(event.host.bounds, NSMakePoint(NSMidX(bounds), NSMidY(bounds)));
			place(event, NSMakeRect(centre.x - NSWidth(bounds) / 2, centre.y - NSHeight(bounds) / 2,
			                        NSWidth(bounds), NSHeight(bounds)));
		}
		for (WKDFlow *flow in touching) {
			NSValue *fromMove = [moved objectForKey:flow.source.elementId];
			NSValue *toMove = [moved objectForKey:flow.target.elementId];
			if (fromMove == nil && toMove == nil) {
				continue;
			}
			NSSize from = fromMove != nil ? [fromMove sizeValue] : NSZeroSize;
			NSSize to = toMove != nil ? [toMove sizeValue] : NSZeroSize;
			NSArray *route = [routes objectForKey:flow];
			NSRect label = [[labels objectForKey:flow] rectValue];
			NSArray *points = nil;
			if (NSEqualSizes(from, to)) {
				/* Both ends went the same way: the route goes with them. */
				NSMutableArray *shifted = [NSMutableArray array];
				for (NSValue *value in route) {
					NSPoint point = [value pointValue];
					[shifted addObject:WKDPoint(point.x + from.width, point.y + from.height)];
				}
				points = shifted;
			} else {
				/* One end went: its bends stay where they were, unless the
				 * route cannot keep them. */
				points = [WKDEditor keptRoute:route source:flow.source.bounds target:flow.target.bounds
				                 sourceMoved:from targetMoved:to] ?: [self routeFor:flow];
			}
			[self setWaypoints:points of:flow.elementId];
			if (!NSIsEmptyRect(label)) {
				NSRect before = WKDFlowLabelRect(route), after = WKDFlowLabelRect(points);
				[self setLabelBounds:NSOffsetRect(label, NSMinX(after) - NSMinX(before),
				                                  NSMinY(after) - NSMinY(before)) of:flow.elementId];
			}
		}
	}];
}

- (void)resizeElement:(NSString *)elementId to:(NSRect)bounds
{
	if ([_model laneWithId:elementId] != nil) {
		[self resizeBand:elementId to:bounds];
		return;
	}
	WKDNode *shape = [_model nodeWithId:elementId];
	if (shape == nil || NSWidth(bounds) < 20 || NSHeight(bounds) < 20) {
		return;
	}
	[self change:@"Resize" with:^{
		[self setBounds:bounds of:elementId];
		WKDNode *resized = [self->_model nodeWithId:elementId];
		for (WKDNode *event in self->_model.nodes) {
			if (event.host == resized) {
				NSPoint centre = WKDOnEdge(bounds, NSMakePoint(NSMidX(event.bounds), NSMidY(event.bounds)));
				[self setBounds:NSMakeRect(centre.x - NSWidth(event.bounds) / 2, centre.y - NSHeight(event.bounds) / 2,
				                           NSWidth(event.bounds), NSHeight(event.bounds)) of:event.elementId];
			}
		}
		for (WKDFlow *connection in self->_model.flows) {
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
	return [_model.journal elementWithId:elementId];
}

- (BOOL)edit:(NSString *)elementId
      action:(NSString *)action
        with:(void (^)(NSXMLElement *element, NSXMLDocument *document))edit
{
	if ([self elementWithId:elementId] == nil) {
		return NO;
	}
	[self change:action with:^{
		NSXMLElement *element = [self elementWithId:elementId];
		NSXMLElement *root = [self->_document rootElement];
		WKDJournal *journal = self->_model.journal;
		[journal willEditXML:element];
		if (root != element) {
			[journal willEditXML:root];
		}
		edit(element, self->_document);
		[journal didEditXML:element];
		if (root != element) {
			[journal didEditXML:root];
		}
		/* Its values, where the model holds it: nothing else is its to edit. */
		WKDModelElement *modelled = [self->_model nodeWithId:elementId] ?: [self->_model flowWithId:elementId]
			?: (WKDModelElement *)[self->_model laneWithId:elementId];
		if (modelled.element == element) {
			[self->_model readValuesAgain:modelled];
		}
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
	WKDLogAttribute(self.model.journal, definition, @"id", definitionId);
	WKDLogAttribute(self.model.journal, definition, @"name", value);
	if (![key isEqualToString:@"name"]) {
		WKDLogAttribute(self.model.journal, definition, key, value);
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
	WKDLogInsert(self.model.journal, root, definition, index);
	return definitionId;
}


- (NSString *)refusalToRename:(NSString *)elementId to:(NSString *)newId
{
	if ([newId isEqualToString:elementId]) {
		return nil;
	}
	if (!WKDIsName(newId)) {
		return @"An id is a letter or _, then letters, digits, -, _ and dots.";
	}
	if ([self elementWithId:newId] != nil) {
		return [NSString stringWithFormat:@"%@ is the id of another element.", newId];
	}
	return [self elementWithId:elementId] == nil ? @"There is no such element." : nil;
}

- (BOOL)renameElement:(NSString *)elementId to:(NSString *)newId error:(NSString **)reason
{
	if ([newId isEqualToString:elementId]) {
		return YES;
	}
	NSString *refusal = [self refusalToRename:elementId to:newId];
	if (refusal != nil) {
		if (reason != NULL) {
			*reason = refusal;
		}
		return NO;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDEditorWillRenameNotification object:self
	                                                  userInfo:@{ @"from": elementId, @"to": newId }];
	[self change:@"Rename" with:^{
		WKDModelElement *renamed = [self->_model nodeWithId:elementId] ?: [self->_model flowWithId:elementId]
			?: (WKDModelElement *)[self->_model laneWithId:elementId];
		if (renamed != nil) {
			[self->_model renameElement:renamed to:newId];
		}
		NSArray *references = @[ @"sourceRef", @"targetRef", @"attachedToRef", @"default", @"bpmnElement",
		                         @"processRef", @"activityRef" ];
		NSMutableArray *pending = [NSMutableArray arrayWithObject:[self->_document rootElement]];
		while ([pending count] > 0) {
			NSXMLElement *element = [pending lastObject];
			[pending removeLastObject];
			if ([WKDAttribute(element, @"id") isEqualToString:elementId]) {
				WKDLogAttribute(self.model.journal, element, @"id", newId);
			}
			for (NSString *reference in references) {
				if ([WKDAttribute(element, reference) isEqualToString:elementId]) {
					WKDLogAttribute(self.model.journal, element, reference, newId);
				}
			}
			if ((WKDIs(element, WKDBpmnNamespace, @"incoming") || WKDIs(element, WKDBpmnNamespace, @"outgoing")
			     || WKDIs(element, WKDBpmnNamespace, @"flowNodeRef"))
			    && [[element stringValue] isEqualToString:elementId]) {
				WKDLogText(self.model.journal, element, newId);
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
	NSMutableArray *bands = [NSMutableArray array];
	for (NSString *elementId in elementIds) {
		WKDNode *shape = [_model nodeWithId:elementId];
		WKDLane *band = [_model laneWithId:elementId];
		if (shape != nil) {
			[self collect:shape into:nodes];
		} else if ([_model flowWithId:elementId] != nil) {
			[flows addObject:elementId];
		} else if (band != nil && (!band.isPool || band == _model.pool)) {
			[bands addObject:elementId];
		}
	}
	for (WKDFlow *connection in _model.flows) {
		if ([nodes containsObject:connection.source.elementId] || [nodes containsObject:connection.target.elementId]) {
			[flows addObject:connection.elementId];
		}
	}
	if ([nodes count] == 0 && [flows count] == 0 && [bands count] == 0) {
		return;
	}
	[self change:@"Delete" with:^{
		if ([bands count] > 0) {
			[self removeBands:bands];
		}
		WKDModel *model = self->_model;
		for (NSString *flowId in flows) {
			[model removeFlow:[model flowWithId:flowId]];
		}
		for (NSString *nodeId in nodes) {
			[model removeNode:[model nodeWithId:nodeId]];
		}
		[model write];
	}];
}

@end

#import "WKDEditorPriv.h"
#import "WKDXML.h"

/* A new lane's height, the least a lane may have, and the room round what
 * a pool holds. */
static const double WKDLaneHeight = 125;
static const double WKDLaneMinimum = 60;
static const double WKDPoolMargin = 40;

static NSValue *
WKDPointAt(double x, double y)
{
	return [NSValue valueWithPoint:NSMakePoint(x, y)];
}

/* What the lanes' changes share. */
@interface WKDEditor (WKDLanesHelpers)
- (NSArray<WKDShape *> *)laneMembers;
- (NSUInteger)laneLevels;
- (WKDLane *)leafLaneAt:(NSPoint)point;
- (void)setRefs:(NSArray<NSString *> *)ids of:(WKDLane *)lane;
- (NSString *)makePool;
- (NSXMLElement *)newLane:(NSRect)bounds;
- (void)shiftBelow:(double)line by:(double)dy;
@end

@implementation WKDEditor (WKDLanesHelpers)

/* The process's own nodes at its top level, boundary events with them:
 * what lanes list. */
- (NSArray<WKDShape *> *)laneMembers
{
	NSMutableArray *members = [NSMutableArray array];
	for (WKDShape *shape in self.diagram.shapes) {
		if (shape.parent == nil && shape.kind != WKDShapeArtifact) {
			[members addObject:shape];
		}
	}
	return members;
}

/* How many bands of lanes a pool's content is to the right of. */
- (NSUInteger)laneLevels
{
	NSUInteger levels = 0;
	for (WKDLane *lane in self.diagram.lanes) {
		levels = MAX(levels, lane.depth + 1);
	}
	return levels;
}

/* The leaf lane a point is in: the one holding it, else the nearest
 * across. nil when no leaf lane has bounds. */
- (WKDLane *)leafLaneAt:(NSPoint)point
{
	WKDLane *nearest = nil;
	double best = DBL_MAX;
	for (WKDLane *lane in self.diagram.leafLanes) {
		if (!lane.hasBounds) {
			continue;
		}
		NSRect r = lane.bounds;
		double dy = point.y < NSMinY(r) ? NSMinY(r) - point.y : point.y > NSMaxY(r) ? point.y - NSMaxY(r) : 0;
		if (dy < best) {
			best = dy;
			nearest = lane;
		}
	}
	return nearest;
}

/* The lane's flowNodeRefs, as the ids given. */
- (void)setRefs:(NSArray<NSString *> *)ids of:(WKDLane *)lane
{
	for (NSXMLElement *ref in WKDChildren(lane.element, WKDBpmnNamespace, @"flowNodeRef")) {
		[ref detach];
	}
	NSXMLElement *childSet = WKDChild(lane.element, WKDBpmnNamespace, @"childLaneSet");
	for (NSString *nodeId in ids) {
		NSXMLElement *ref = WKDNewElement(self.document, WKDBpmnNamespace, @"flowNodeRef");
		[ref setStringValue:nodeId];
		if (childSet != nil) {
			[lane.element insertChild:ref atIndex:[childSet index]];
		} else {
			[lane.element addChild:ref];
		}
	}
}

/* The process's participant, and the collaboration it is in, made: the
 * diagram's plane shows the collaboration then. Its id. */
- (NSString *)makePool
{
	NSXMLElement *root = [self.document rootElement];
	NSXMLElement *process = self.diagram.process;
	NSXMLElement *collaboration = WKDChild(root, WKDBpmnNamespace, @"collaboration");
	if (collaboration == nil) {
		collaboration = WKDNewElement(self.document, WKDBpmnNamespace, @"collaboration");
		WKDSetAttribute(collaboration, @"id", [self freshId:@"Collaboration"]);
		[root insertChild:collaboration atIndex:[process index]];
	}
	NSString *poolId = [self freshId:@"Participant"];
	NSXMLElement *participant = WKDNewElement(self.document, WKDBpmnNamespace, @"participant");
	WKDSetAttribute(participant, @"id", poolId);
	WKDSetAttribute(participant, @"name", WKDAttribute(process, @"name"));
	WKDSetAttribute(participant, @"processRef", WKDAttribute(process, @"id"));
	[collaboration addChild:participant];
	NSXMLElement *plane = [self plane];
	if ([WKDAttribute(plane, @"bpmnElement") isEqualToString:WKDAttribute(process, @"id")]) {
		WKDSetAttribute(plane, @"bpmnElement", WKDAttribute(collaboration, @"id"));
	}
	/* Round what the diagram shows, the process's lanes' band left of it. */
	NSRect content = NSZeroRect;
	for (WKDShape *shape in self.diagram.shapes) {
		if (shape.hasBounds) {
			content = NSIsEmptyRect(content) ? shape.bounds : NSUnionRect(content, shape.bounds);
		}
	}
	for (WKDLane *lane in self.diagram.lanes) {
		if (lane.hasBounds) {
			content = NSIsEmptyRect(content) ? lane.bounds : NSUnionRect(content, lane.bounds);
		}
	}
	NSRect bounds = NSIsEmptyRect(content) ? NSMakeRect(100, 80, 600, 250)
		: NSInsetRect(content, -WKDPoolMargin, -WKDPoolMargin);
	if ([self.diagram.lanes count] > 0) {
		bounds = content;
	}
	bounds.origin.x -= WKDLaneBandWidth;
	bounds.size.width += WKDLaneBandWidth;
	bounds.size.width = MAX(NSWidth(bounds), 600);
	bounds.size.height = MAX(NSHeight(bounds), 250);
	[self setBounds:bounds of:poolId];
	WKDSetAttribute([self diagramElement:@"BPMNShape" of:poolId create:YES], @"isHorizontal", @"true");
	self.diagram = [WKDDiagram diagramOfDocument:self.document];
	return poolId;
}

/* A new lane element, with its shape. */
- (NSXMLElement *)newLane:(NSRect)bounds
{
	NSXMLElement *lane = WKDNewElement(self.document, WKDBpmnNamespace, @"lane");
	NSString *laneId = [self freshId:@"Lane"];
	WKDSetAttribute(lane, @"id", laneId);
	[self setBounds:bounds of:laneId];
	WKDSetAttribute([self diagramElement:@"BPMNShape" of:laneId create:YES], @"isHorizontal", @"true");
	return lane;
}

/* Everything below the line moved down by dy (up, for less than 0), and
 * the pool and the lanes the line crosses or ends made taller by it:
 * shapes, names, bends, lanes. */
- (void)shiftBelow:(double)line by:(double)dy
{
	for (WKDShape *shape in self.diagram.shapes) {
		if (shape.hasBounds && NSMidY(shape.bounds) > line) {
			[self setBounds:NSOffsetRect(shape.bounds, 0, dy) of:shape.elementId];
			if (!NSIsEmptyRect(shape.labelBounds)) {
				[self setLabelBounds:NSOffsetRect(shape.labelBounds, 0, dy) of:shape.elementId];
			}
		}
	}
	for (WKDConnection *connection in self.diagram.connections) {
		NSMutableArray *points = [NSMutableArray array];
		BOOL moved = NO;
		for (NSValue *value in connection.waypoints) {
			NSPoint point = [value pointValue];
			if (point.y > line) {
				point.y += dy;
				moved = YES;
			}
			[points addObject:WKDPointAt(point.x, point.y)];
		}
		if (moved) {
			[self setWaypoints:points of:connection.elementId];
			if (!NSIsEmptyRect(connection.labelBounds) && NSMidY(connection.labelBounds) > line) {
				[self setLabelBounds:NSOffsetRect(connection.labelBounds, 0, dy) of:connection.elementId];
			}
		}
	}
	/* Message flows' bends, which the diagram does not read. */
	NSMutableSet *messageFlows = [NSMutableSet set];
	for (NSXMLElement *collaboration in WKDChildren([self.document rootElement], WKDBpmnNamespace, @"collaboration")) {
		for (NSXMLElement *flow in WKDChildren(collaboration, WKDBpmnNamespace, @"messageFlow")) {
			[messageFlows addObject:WKDAttribute(flow, @"id") ?: @""];
		}
	}
	for (NSXMLElement *plane in WKDDescendants([self.document rootElement], WKDBpmnDINamespace, @"BPMNPlane")) {
		for (NSXMLElement *edge in WKDChildren(plane, WKDBpmnDINamespace, @"BPMNEdge")) {
			if (![messageFlows containsObject:WKDAttribute(edge, @"bpmnElement") ?: @""]) {
				continue;
			}
			for (NSXMLElement *waypoint in WKDChildren(edge, WKDDINamespace, @"waypoint")) {
				double y = WKDNumber(waypoint, @"y");
				if (y > line) {
					WKDSetAttribute(waypoint, @"y", WKDFormat(y + dy));
				}
			}
		}
	}
	/* The process's pool and lanes, and the other pools below. */
	NSMutableArray *bands = [NSMutableArray arrayWithArray:self.diagram.lanes];
	if (self.diagram.pool != nil) {
		[bands addObject:self.diagram.pool];
	}
	[bands addObjectsFromArray:self.diagram.otherPools];
	for (WKDLane *lane in bands) {
		NSRect r = lane.bounds;
		if (!lane.hasBounds) {
			continue;
		}
		BOOL other = lane.isPool && lane != self.diagram.pool;
		if (other && NSMinY(r) < line - 0.5) {
			continue;
		}
		if (NSMinY(r) >= line - 0.5) {
			[self setBounds:NSOffsetRect(r, 0, dy) of:lane.elementId];
		} else if (NSMaxY(r) >= line - 0.5) {
			[self setBounds:NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), NSHeight(r) + dy) of:lane.elementId];
		}
	}
	self.diagram = [WKDDiagram diagramOfDocument:self.document];
}

@end

@implementation WKDEditor (WKDLanesInternal)

/* After every change: the pool round what it holds, and each node listed
 * by the lane it is in -- a node moved into another lane changes lanes, a
 * node added joins the lane it was put in, and what is gone or renamed is
 * no longer listed. Only what changed is written. */
- (void)keepLanes
{
	self.diagram = [WKDDiagram diagramOfDocument:self.document];
	WKDLane *pool = self.diagram.pool;
	if (pool == nil && [self.diagram.lanes count] == 0) {
		return;
	}
	NSArray<WKDShape *> *members = [self laneMembers];
	if (pool.hasBounds && pool.horizontal) {
		NSRect content = NSZeroRect;
		for (WKDShape *shape in members) {
			if (shape.hasBounds) {
				NSRect r = shape.bounds;
				if (!NSIsEmptyRect(shape.labelBounds)) {
					r = NSUnionRect(r, shape.labelBounds);
				}
				content = NSIsEmptyRect(content) ? r : NSUnionRect(content, r);
			}
		}
		NSRect old = pool.bounds;
		double left = 0, right = 0, top = 0, bottom = 0;
		if (!NSIsEmptyRect(content)) {
			double inner = NSMinX(old) + WKDLaneBandWidth * (1 + [self laneLevels]);
			left = MAX(0, inner - (NSMinX(content) - 20));
			right = MAX(0, NSMaxX(content) + 20 - NSMaxX(old));
			top = MAX(0, NSMinY(old) - (NSMinY(content) - 20));
			bottom = MAX(0, NSMaxY(content) + 20 - NSMaxY(old));
		}
		if (left + right + top + bottom > 0) {
			[self setBounds:NSMakeRect(NSMinX(old) - left, NSMinY(old) - top, NSWidth(old) + left + right,
			                           NSHeight(old) + top + bottom) of:pool.elementId];
			for (WKDLane *lane in self.diagram.lanes) {
				NSRect r = lane.bounds;
				if (!lane.hasBounds) {
					continue;
				}
				double y = NSMinY(r), height = NSHeight(r);
				if (fabs(NSMinY(r) - NSMinY(old)) < 1) {
					y -= top;
					height += top;
				}
				if (fabs(NSMaxY(r) - NSMaxY(old)) < 1) {
					height += bottom;
				}
				[self setBounds:NSMakeRect(NSMinX(r) - left, y, NSWidth(r) + left + right, height) of:lane.elementId];
			}
			self.diagram = [WKDDiagram diagramOfDocument:self.document];
		}
	}

	NSArray<WKDLane *> *lanes = self.diagram.lanes;
	if ([self.diagram.leafLanes count] == 0) {
		return;
	}
	NSMutableSet *present = [NSMutableSet set];
	for (WKDShape *shape in self.diagram.shapes) {
		[present addObject:shape.elementId];
	}
	NSMutableDictionary<NSString *, NSMutableArray *> *refs = [NSMutableDictionary dictionary];
	for (WKDLane *lane in lanes) {
		NSMutableArray *kept = [NSMutableArray array];
		for (NSString *nodeId in lane.flowNodeIds) {
			if ([present containsObject:nodeId]) {
				[kept addObject:nodeId];
			}
		}
		[refs setObject:kept forKey:lane.elementId];
	}
	for (WKDShape *shape in [self laneMembers]) {
		WKDShape *placed = shape.host ?: shape;
		if (!placed.hasBounds) {
			continue;
		}
		WKDLane *target = [self leafLaneAt:NSMakePoint(NSMidX(placed.bounds), NSMidY(placed.bounds))];
		WKDLane *current = [self.diagram laneOf:shape];
		if (target == nil || target == current) {
			continue;
		}
		for (WKDLane *lane in lanes) {
			[[refs objectForKey:lane.elementId] removeObject:shape.elementId];
		}
		/* Listed by its lane, and by the lanes round it that list theirs. */
		for (WKDLane *lane = target; lane != nil; lane = lane.parent) {
			if (lane == target || [lane.flowNodeIds count] > 0) {
				[[refs objectForKey:lane.elementId] addObject:shape.elementId];
			}
		}
	}
	for (WKDLane *lane in lanes) {
		NSArray *now = [refs objectForKey:lane.elementId];
		if (![now isEqualToArray:lane.flowNodeIds]) {
			[self setRefs:now of:lane];
		}
	}
	self.diagram = [WKDDiagram diagramOfDocument:self.document];
}

/* A lane's or a pool's shape and its new size: a lane is made taller or
 * shorter at its bottom, and what is below it moves; a pool's width is its
 * lanes', and its height its bottom lanes'. */
- (void)resizeBand:(NSString *)elementId to:(NSRect)bounds
{
	WKDLane *band = [self.diagram laneWithId:elementId];
	WKDLane *pool = self.diagram.pool;
	if (band == nil || !band.hasBounds || (band.isPool && band != pool)) {
		return;
	}
	NSRect old = band.bounds;
	/* No lane shorter than the least: the ones at the bottom included. */
	double least = WKDLaneMinimum;
	for (WKDLane *lane in self.diagram.lanes) {
		if (lane != band && fabs(NSMaxY(lane.bounds) - NSMaxY(old)) < 1 && NSMinY(lane.bounds) >= NSMinY(old) - 0.5) {
			least = MAX(least, NSHeight(old) - NSHeight(lane.bounds) + WKDLaneMinimum);
		}
	}
	double dy = MAX(NSHeight(bounds), least) - NSHeight(old);
	double right = NSMaxX(bounds) - NSMaxX(old);
	if (fabs(dy) < 1 && fabs(right) < 1) {
		return;
	}
	[self change:@"Resize" with:^{
		if (fabs(dy) >= 1) {
			[self shiftBelow:NSMaxY(old) by:dy];
		}
		if (fabs(right) >= 1) {
			/* Across: the pool and every lane in it end where it now does. */
			double end = MAX(NSMaxX(old) + right, NSMinX(self.diagram.pool.bounds) + 200);
			NSMutableArray *bands = [NSMutableArray arrayWithArray:self.diagram.lanes];
			if (self.diagram.pool != nil) {
				[bands addObject:self.diagram.pool];
			}
			for (WKDLane *lane in bands) {
				NSRect r = lane.bounds;
				[self setBounds:NSMakeRect(NSMinX(r), NSMinY(r), end - NSMinX(r), NSHeight(r)) of:lane.elementId];
			}
		}
	}];
}

/* Removed, inside a change: a lane gives its room to the lane before it,
 * or after it, and the last lane of a set takes the set with it; a pool
 * takes its lanes, and its collaboration when it was its last
 * participant. The nodes stay. */
- (void)removeBands:(NSArray<NSString *> *)elementIds
{
	NSMutableSet *gone = [NSMutableSet set];
	WKDLane *pool = self.diagram.pool;
	BOOL poolGoes = pool != nil && [elementIds containsObject:pool.elementId];
	for (NSString *elementId in elementIds) {
		WKDLane *lane = [self.diagram laneWithId:elementId];
		if (lane == nil || lane.isPool || poolGoes) {
			continue;
		}
		NSXMLElement *set = (NSXMLElement *)[lane.element parent];
		NSArray *siblings = WKDChildren(set, WKDBpmnNamespace, @"lane");
		NSUInteger index = [siblings indexOfObjectIdenticalTo:lane.element];
		NSXMLElement *neighbour = index > 0 ? [siblings objectAtIndex:index - 1]
			: [siblings count] > 1 ? [siblings objectAtIndex:1] : nil;
		WKDLane *taker = [self.diagram laneWithId:WKDAttribute(neighbour, @"id")];
		if (taker.hasBounds && lane.hasBounds) {
			[self setBounds:NSUnionRect(taker.bounds, lane.bounds) of:taker.elementId];
		}
		[gone addObject:lane.elementId];
		for (WKDLane *inner in self.diagram.lanes) {
			for (WKDLane *up = inner; up != nil; up = up.parent) {
				if (up == lane) {
					[gone addObject:inner.elementId];
				}
			}
		}
		[lane.element detach];
		if ([WKDChildren(set, WKDBpmnNamespace, @"lane") count] == 0) {
			[set detach];
		}
	}
	if (poolGoes) {
		[gone addObject:pool.elementId];
		for (WKDLane *lane in self.diagram.lanes) {
			[gone addObject:lane.elementId];
		}
		[WKDChild(self.diagram.process, WKDBpmnNamespace, @"laneSet") detach];
		NSXMLElement *collaboration = (NSXMLElement *)[pool.element parent];
		for (NSXMLElement *flow in WKDChildren(collaboration, WKDBpmnNamespace, @"messageFlow")) {
			if ([WKDAttribute(flow, @"sourceRef") isEqualToString:pool.elementId]
			    || [WKDAttribute(flow, @"targetRef") isEqualToString:pool.elementId]) {
				[gone addObject:WKDAttribute(flow, @"id") ?: @""];
				[flow detach];
			}
		}
		[pool.element detach];
		if ([WKDChildren(collaboration, WKDBpmnNamespace, @"participant") count] == 0) {
			/* The plane shows the process again. */
			NSString *collaborationId = WKDAttribute(collaboration, @"id");
			for (NSXMLElement *plane in WKDDescendants([self.document rootElement], WKDBpmnDINamespace, @"BPMNPlane")) {
				if ([WKDAttribute(plane, @"bpmnElement") isEqualToString:collaborationId]) {
					WKDSetAttribute(plane, @"bpmnElement", WKDAttribute(self.diagram.process, @"id"));
				}
			}
			[collaboration detach];
		}
	}
	for (NSXMLElement *plane in WKDDescendants([self.document rootElement], WKDBpmnDINamespace, @"BPMNPlane")) {
		for (NSXMLElement *child in WKDChildren(plane, WKDBpmnDINamespace, nil)) {
			if ([gone containsObject:WKDAttribute(child, @"bpmnElement") ?: @""]) {
				[child detach];
			}
		}
	}
	self.diagram = [WKDDiagram diagramOfDocument:self.document];
}

/* After the layout: each lane's nodes stacked in a band of their own, top
 * to bottom as the lanes are, and the pool and its lanes round them. The
 * nodes keep their lanes, which `membership` gives -- leaf lane id to the
 * ids of the nodes it held before. */
- (void)stackLanes:(NSDictionary<NSString *, NSArray<NSString *> *> *)membership
{
	WKDLane *pool = self.diagram.pool;
	NSArray<WKDLane *> *leaves = self.diagram.leafLanes;
	if (pool == nil && [leaves count] == 0) {
		return;
	}
	NSRect content = self.diagram.contentBounds;
	for (WKDShape *shape in self.diagram.shapes) {
		if (shape.hasBounds) {
			content = NSIsEmptyRect(content) ? shape.bounds : NSUnionRect(content, shape.bounds);
		}
	}
	/* What is not in a lane goes in the first. */
	NSMutableDictionary<NSString *, NSMutableArray *> *held = [NSMutableDictionary dictionary];
	NSMutableSet *placed = [NSMutableSet set];
	for (WKDLane *lane in leaves) {
		NSMutableArray *ids = [NSMutableArray arrayWithArray:[membership objectForKey:lane.elementId] ?: @[]];
		[held setObject:ids forKey:lane.elementId];
		[placed addObjectsFromArray:ids];
	}
	for (WKDShape *shape in [self laneMembers]) {
		if (shape.host == nil && ![placed containsObject:shape.elementId] && [leaves count] > 0) {
			[[held objectForKey:[[leaves firstObject] elementId]] addObject:shape.elementId];
		}
	}
	/* The shapes' bounds, read once: moving one changes the diagram. */
	NSArray<WKDShape *> *shapes = self.diagram.shapes;
	double band = WKDLaneBandWidth;
	double left = NSMinX(content) - WKDPoolMargin - band * (1 + [self laneLevels]);
	double right = NSMaxX(content) + WKDPoolMargin;
	double top = NSMinY(content) - WKDPoolMargin;
	NSMutableDictionary<NSString *, NSValue *> *spans = [NSMutableDictionary dictionary];
	double y = top;
	for (WKDLane *lane in leaves) {
		NSMutableSet *ids = [NSMutableSet set];
		for (NSString *nodeId in [held objectForKey:lane.elementId]) {
			WKDShape *shape = [self.diagram shapeWithId:nodeId];
			if (shape != nil && shape.host == nil) {
				[self collect:shape into:ids];
			}
		}
		NSRect box = NSZeroRect;
		for (WKDShape *shape in shapes) {
			if ([ids containsObject:shape.elementId] && shape.hasBounds) {
				NSRect r = shape.bounds;
				NSRect label = WKDNodeLabelRect(shape.type, r);
				r = NSIsEmptyRect(label) ? r : NSUnionRect(r, label);
				box = NSIsEmptyRect(box) ? r : NSUnionRect(box, r);
			}
		}
		double height = WKDLaneHeight;
		if (!NSIsEmptyRect(box)) {
			double dy = y + WKDPoolMargin - NSMinY(box);
			for (WKDShape *shape in shapes) {
				if ([ids containsObject:shape.elementId] && shape.hasBounds) {
					[self setBounds:NSOffsetRect(shape.bounds, 0, dy) of:shape.elementId];
					if (!NSIsEmptyRect(shape.labelBounds)) {
						[self setLabelBounds:NSOffsetRect(shape.labelBounds, 0, dy) of:shape.elementId];
					}
				}
			}
			height = MAX(WKDLaneHeight, NSHeight(box) + 2 * WKDPoolMargin);
		}
		[spans setObject:[NSValue valueWithRect:NSMakeRect(0, y, 0, height)] forKey:lane.elementId];
		y += height;
	}
	if ([leaves count] == 0) {
		y = NSMaxY(content) + WKDPoolMargin;
	}
	/* Lanes round the lanes dividing them, innermost first. */
	for (WKDLane *lane in [self.diagram.lanes reverseObjectEnumerator]) {
		NSRect span = NSZeroRect;
		if ([spans objectForKey:lane.elementId] != nil) {
			span = [[spans objectForKey:lane.elementId] rectValue];
		} else {
			for (WKDLane *child in lane.children) {
				NSRect inner = [[spans objectForKey:child.elementId] rectValue];
				span = NSIsEmptyRect(span) && NSHeight(span) == 0 ? inner : NSUnionRect(span, inner);
			}
		}
		[spans setObject:[NSValue valueWithRect:span] forKey:lane.elementId];
		double x = left + band * (1 + lane.depth);
		[self setBounds:NSMakeRect(x, NSMinY(span), right - x, NSHeight(span)) of:lane.elementId];
		WKDSetAttribute([self diagramElement:@"BPMNShape" of:lane.elementId create:YES], @"isHorizontal", @"true");
	}
	if (pool != nil) {
		[self setBounds:NSMakeRect(left, top, right - left, y - top) of:pool.elementId];
		WKDSetAttribute([self diagramElement:@"BPMNShape" of:pool.elementId create:YES], @"isHorizontal", @"true");
	}
	self.diagram = [WKDDiagram diagramOfDocument:self.document];
}

/* Leaf lane id to the nodes it lists, as the document says now. */
- (NSDictionary<NSString *, NSArray<NSString *> *> *)laneMembership
{
	NSMutableDictionary *membership = [NSMutableDictionary dictionary];
	for (WKDShape *shape in [self laneMembers]) {
		WKDLane *lane = [self.diagram laneOf:shape];
		while (lane != nil && [lane.children count] > 0) {
			lane = [lane.children firstObject];
		}
		if (lane == nil) {
			continue;
		}
		NSMutableArray *ids = [membership objectForKey:lane.elementId];
		if (ids == nil) {
			ids = [NSMutableArray array];
			[membership setObject:ids forKey:lane.elementId];
		}
		[ids addObject:shape.elementId];
	}
	return membership;
}

@end

@implementation WKDEditor (WKDLanes)

- (NSString *)addPool
{
	if (self.diagram.pool != nil) {
		return self.diagram.pool.elementId;
	}
	__block NSString *made = nil;
	[self change:@"Add Pool" with:^{
		made = [self makePool];
	}];
	return made;
}

- (NSString *)addLaneAfter:(NSString *)elementId
{
	WKDLane *after = [self.diagram laneWithId:elementId];
	if (after != nil && after.isPool && after != self.diagram.pool) {
		return nil;
	}
	__block NSString *made = nil;
	[self change:@"Add Lane" with:^{
		if (self.diagram.pool == nil) {
			[self makePool];
		}
		WKDLane *pool = self.diagram.pool;
		WKDLane *target = after != nil && !after.isPool ? [self.diagram laneWithId:after.elementId] : nil;
		if ([self.diagram.lanes count] == 0) {
			/* A pool without lanes: one lane first, holding all it holds. */
			NSXMLElement *laneSet = WKDEnsureChild(self.document, self.diagram.process, WKDBpmnNamespace, @"laneSet");
			WKDSetAttribute(laneSet, @"id", [self freshId:@"LaneSet"]);
			NSRect r = pool.bounds;
			NSXMLElement *first = [self newLane:NSMakeRect(NSMinX(r) + WKDLaneBandWidth, NSMinY(r),
			                                                NSWidth(r) - WKDLaneBandWidth, NSHeight(r))];
			[laneSet addChild:first];
			self.diagram = [WKDDiagram diagramOfDocument:self.document];
			[self keepLanes];
			target = [self.diagram laneWithId:WKDAttribute(first, @"id")];
		}
		if (target == nil) {
			/* At the bottom of the pool: after its last lane. */
			for (WKDLane *lane in self.diagram.lanes) {
				if (lane.parent == nil) {
					target = lane;
				}
			}
		}
		NSRect r = target.bounds;
		[self shiftBelow:NSMaxY(r) by:WKDLaneHeight];
		/* The line ended the lane it is added after, which is not taller. */
		[self setBounds:r of:target.elementId];
		NSXMLElement *lane = [self newLane:NSMakeRect(NSMinX(r), NSMaxY(r), NSWidth(r), WKDLaneHeight)];
		NSXMLElement *set = (NSXMLElement *)[target.element parent];
		[set insertChild:lane atIndex:[target.element index] + 1];
		made = WKDAttribute(lane, @"id");
	}];
	return made;
}

@end

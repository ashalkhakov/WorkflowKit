#import "WKDEditorPriv.h"
#import "WKDXML.h"
#import "WKDModelPriv.h"
#import "WKDJournal.h"

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
- (NSArray<WKDNode *> *)laneMembers;
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
- (NSArray<WKDNode *> *)laneMembers
{
	NSMutableArray *members = [NSMutableArray array];
	for (WKDNode *shape in self.model.nodes) {
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
	for (WKDLane *lane in self.model.lanes) {
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
	for (WKDLane *lane in self.model.leafLanes) {
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

/* The lane's flowNodeRefs, as the ids given: its nodes the model's, the
 * refs naming no node of the process kept only where given. */
- (void)setRefs:(NSArray<NSString *> *)ids of:(WKDLane *)lane
{
	WKDModel *model = self.model;
	NSMutableArray<WKDNode *> *nodes = [NSMutableArray array];
	NSMutableArray<NSString *> *others = [NSMutableArray array];
	for (NSString *nodeId in ids) {
		WKDNode *node = [model nodeWithId:nodeId];
		if (node != nil) {
			[nodes addObject:node];
		} else {
			[others addObject:nodeId];
		}
	}
	NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	for (NSXMLElement *ref in WKDChildren(lane.element, WKDBpmnNamespace, @"flowNodeRef")) {
		NSString *named = [[ref stringValue] stringByTrimmingCharactersInSet:space];
		if ([model nodeWithId:named] == nil && ![others containsObject:named]) {
			WKDLogDetach(model.journal, ref);
		}
	}
	NSMutableSet<WKDNode *> *moved = [NSMutableSet setWithArray:lane.nodeList];
	NSSet<WKDNode *> *staying = [NSSet setWithArray:nodes];
	[moved minusSet:staying];
	for (WKDNode *node in nodes) {
		if ([lane.nodeList indexOfObjectIdenticalTo:node] == NSNotFound) {
			[moved addObject:node];
		}
	}
	[lane willChange];
	lane.nodeList = nodes;
	lane.otherIds = others;
	/* Each node's lane: the innermost listing it. */
	for (WKDNode *node in moved) {
		WKDLane *innermost = nil;
		for (WKDLane *listing in model.lanes) {
			if ((innermost == nil || listing.depth >= innermost.depth)
			    && [listing.nodeList indexOfObjectIdenticalTo:node] != NSNotFound) {
				innermost = listing;
			}
		}
		if (node.lane != innermost) {
			[node willChange];
			node.lane = innermost;
		}
	}
}

/* The process's participant, and the collaboration it is in, made: the
 * diagram's plane shows the collaboration then. Its id. */
- (NSString *)makePool
{
	self.needsSync = YES;
	NSXMLElement *root = [self.document rootElement];
	NSXMLElement *process = self.model.process;
	NSXMLElement *collaboration = WKDChild(root, WKDBpmnNamespace, @"collaboration");
	if (collaboration == nil) {
		collaboration = WKDNewElement(self.document, WKDBpmnNamespace, @"collaboration");
		WKDLogAttribute(self.model.journal, collaboration, @"id", [self freshId:@"Collaboration"]);
		WKDLogInsert(self.model.journal, root, collaboration, [process index]);
	}
	NSString *poolId = [self freshId:@"Participant"];
	NSXMLElement *participant = WKDNewElement(self.document, WKDBpmnNamespace, @"participant");
	WKDLogAttribute(self.model.journal, participant, @"id", poolId);
	WKDLogAttribute(self.model.journal, participant, @"name", WKDAttribute(process, @"name"));
	WKDLogAttribute(self.model.journal, participant, @"processRef", WKDAttribute(process, @"id"));
	WKDLogAdd(self.model.journal, collaboration, participant);
	NSXMLElement *plane = [self plane];
	if ([WKDAttribute(plane, @"bpmnElement") isEqualToString:WKDAttribute(process, @"id")]) {
		WKDLogAttribute(self.model.journal, plane, @"bpmnElement", WKDAttribute(collaboration, @"id"));
	}
	/* Round what the diagram shows, the process's lanes' band left of it. */
	NSRect content = NSZeroRect;
	for (WKDNode *shape in self.model.nodes) {
		if (shape.hasBounds) {
			content = NSIsEmptyRect(content) ? shape.bounds : NSUnionRect(content, shape.bounds);
		}
	}
	for (WKDLane *lane in self.model.lanes) {
		if (lane.hasBounds) {
			content = NSIsEmptyRect(content) ? lane.bounds : NSUnionRect(content, lane.bounds);
		}
	}
	NSRect bounds = NSIsEmptyRect(content) ? NSMakeRect(100, 80, 600, 250)
		: NSInsetRect(content, -WKDPoolMargin, -WKDPoolMargin);
	if ([self.model.lanes count] > 0) {
		bounds = content;
	}
	bounds.origin.x -= WKDLaneBandWidth;
	bounds.size.width += WKDLaneBandWidth;
	bounds.size.width = MAX(NSWidth(bounds), 600);
	bounds.size.height = MAX(NSHeight(bounds), 250);
	[self setBounds:bounds of:poolId];
	WKDLogAttribute(self.model.journal, [self diagramElement:@"BPMNShape" of:poolId create:YES], @"isHorizontal", @"true");
	[self syncModel];
	return poolId;
}

/* A new lane element, with its shape. */
- (NSXMLElement *)newLane:(NSRect)bounds
{
	self.needsSync = YES;
	NSXMLElement *lane = WKDNewElement(self.document, WKDBpmnNamespace, @"lane");
	NSString *laneId = [self freshId:@"Lane"];
	WKDLogAttribute(self.model.journal, lane, @"id", laneId);
	[self setBounds:bounds of:laneId];
	WKDLogAttribute(self.model.journal, [self diagramElement:@"BPMNShape" of:laneId create:YES], @"isHorizontal", @"true");
	return lane;
}

/* Everything below the line moved down by dy (up, for less than 0), and
 * the pool and the lanes the line crosses or ends made taller by it:
 * shapes, names, bends, lanes. */
- (void)shiftBelow:(double)line by:(double)dy
{
	for (WKDNode *shape in self.model.nodes) {
		if (shape.hasBounds && NSMidY(shape.bounds) > line) {
			[self setBounds:NSOffsetRect(shape.bounds, 0, dy) of:shape.elementId];
			if (!NSIsEmptyRect(shape.labelBounds)) {
				[self setLabelBounds:NSOffsetRect(shape.labelBounds, 0, dy) of:shape.elementId];
			}
		}
	}
	for (WKDFlow *connection in self.model.flows) {
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
					WKDLogAttribute(self.model.journal, waypoint, @"y", WKDFormat(y + dy));
				}
			}
		}
	}
	/* The process's pool and lanes, and the other pools below. */
	NSMutableArray *bands = [NSMutableArray arrayWithArray:self.model.lanes];
	if (self.model.pool != nil) {
		[bands addObject:self.model.pool];
	}
	[bands addObjectsFromArray:self.model.otherPools];
	for (WKDLane *lane in bands) {
		NSRect r = lane.bounds;
		if (!lane.hasBounds) {
			continue;
		}
		BOOL other = lane.isPool && lane != self.model.pool;
		if (other && NSMinY(r) < line - 0.5) {
			continue;
		}
		if (NSMinY(r) >= line - 0.5) {
			[self setBounds:NSOffsetRect(r, 0, dy) of:lane.elementId];
		} else if (NSMaxY(r) >= line - 0.5) {
			[self setBounds:NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), NSHeight(r) + dy) of:lane.elementId];
		}
	}
}

@end

@implementation WKDEditor (WKDLanesInternal)

/* After every change: the pool round what it holds, and each node listed
 * by the lane it is in -- a node moved into another lane changes lanes, a
 * node added joins the lane it was put in, and what is gone or renamed is
 * no longer listed. Only what changed is written. */
- (void)keepLanes
{
	WKDLane *pool = self.model.pool;
	if (pool == nil && [self.model.lanes count] == 0) {
		return;
	}
	NSArray<WKDNode *> *members = [self laneMembers];
	if (pool.hasBounds && pool.horizontal) {
		NSRect content = NSZeroRect;
		for (WKDNode *shape in members) {
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
			for (WKDLane *lane in self.model.lanes) {
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
		}
	}

	NSArray<WKDLane *> *lanes = self.model.lanes;
	if ([self.model.leafLanes count] == 0) {
		return;
	}
	NSMutableSet *present = [NSMutableSet set];
	for (WKDNode *shape in self.model.nodes) {
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
	for (WKDNode *shape in [self laneMembers]) {
		WKDNode *placed = shape.host ?: shape;
		if (!placed.hasBounds) {
			continue;
		}
		WKDLane *target = [self leafLaneAt:NSMakePoint(NSMidX(placed.bounds), NSMidY(placed.bounds))];
		WKDLane *current = [self.model laneOf:shape];
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
}

/* A lane's or a pool's shape and its new size: a lane is made taller or
 * shorter at its bottom, and what is below it moves; a pool's width is its
 * lanes', and its height its bottom lanes'. */
- (void)resizeBand:(NSString *)elementId to:(NSRect)bounds
{
	WKDLane *band = [self.model laneWithId:elementId];
	WKDLane *pool = self.model.pool;
	if (band == nil || !band.hasBounds || (band.isPool && band != pool)) {
		return;
	}
	NSRect old = band.bounds;
	/* No lane shorter than the least: the ones at the bottom included. */
	double least = WKDLaneMinimum;
	for (WKDLane *lane in self.model.lanes) {
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
			double end = MAX(NSMaxX(old) + right, NSMinX(self.model.pool.bounds) + 200);
			NSMutableArray *bands = [NSMutableArray arrayWithArray:self.model.lanes];
			if (self.model.pool != nil) {
				[bands addObject:self.model.pool];
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
	self.needsSync = YES;
	NSMutableSet *gone = [NSMutableSet set];
	WKDLane *pool = self.model.pool;
	BOOL poolGoes = pool != nil && [elementIds containsObject:pool.elementId];
	for (NSString *elementId in elementIds) {
		WKDLane *lane = [self.model laneWithId:elementId];
		if (lane == nil || lane.isPool || poolGoes) {
			continue;
		}
		NSXMLElement *set = (NSXMLElement *)[lane.element parent];
		NSArray *siblings = WKDChildren(set, WKDBpmnNamespace, @"lane");
		NSUInteger index = [siblings indexOfObjectIdenticalTo:lane.element];
		NSXMLElement *neighbour = index > 0 ? [siblings objectAtIndex:index - 1]
			: [siblings count] > 1 ? [siblings objectAtIndex:1] : nil;
		WKDLane *taker = [self.model laneWithId:WKDAttribute(neighbour, @"id")];
		if (taker.hasBounds && lane.hasBounds) {
			[self setBounds:NSUnionRect(taker.bounds, lane.bounds) of:taker.elementId];
		}
		[gone addObject:lane.elementId];
		for (WKDLane *inner in self.model.lanes) {
			for (WKDLane *up = inner; up != nil; up = up.parent) {
				if (up == lane) {
					[gone addObject:inner.elementId];
				}
			}
		}
		WKDLogDetach(self.model.journal, lane.element);
		if ([WKDChildren(set, WKDBpmnNamespace, @"lane") count] == 0) {
			WKDLogDetach(self.model.journal, set);
		}
	}
	if (poolGoes) {
		[gone addObject:pool.elementId];
		for (WKDLane *lane in self.model.lanes) {
			[gone addObject:lane.elementId];
		}
		WKDLogDetach(self.model.journal, WKDChild(self.model.process, WKDBpmnNamespace, @"laneSet"));
		NSXMLElement *collaboration = (NSXMLElement *)[pool.element parent];
		for (NSXMLElement *flow in WKDChildren(collaboration, WKDBpmnNamespace, @"messageFlow")) {
			if ([WKDAttribute(flow, @"sourceRef") isEqualToString:pool.elementId]
			    || [WKDAttribute(flow, @"targetRef") isEqualToString:pool.elementId]) {
				[gone addObject:WKDAttribute(flow, @"id") ?: @""];
				WKDLogDetach(self.model.journal, flow);
			}
		}
		WKDLogDetach(self.model.journal, pool.element);
		if ([WKDChildren(collaboration, WKDBpmnNamespace, @"participant") count] == 0) {
			/* The plane shows the process again. */
			NSString *collaborationId = WKDAttribute(collaboration, @"id");
			for (NSXMLElement *plane in WKDDescendants([self.document rootElement], WKDBpmnDINamespace, @"BPMNPlane")) {
				if ([WKDAttribute(plane, @"bpmnElement") isEqualToString:collaborationId]) {
					WKDLogAttribute(self.model.journal, plane, @"bpmnElement", WKDAttribute(self.model.process, @"id"));
				}
			}
			WKDLogDetach(self.model.journal, collaboration);
		}
	}
	for (NSXMLElement *plane in WKDDescendants([self.document rootElement], WKDBpmnDINamespace, @"BPMNPlane")) {
		for (NSXMLElement *child in WKDChildren(plane, WKDBpmnDINamespace, nil)) {
			if ([gone containsObject:WKDAttribute(child, @"bpmnElement") ?: @""]) {
				WKDLogDetach(self.model.journal, child);
			}
		}
	}
	[self syncModel];
}

/* After the layout: each lane's nodes stacked in a band of their own, top
 * to bottom as the lanes are, and the pool and its lanes round them. The
 * nodes keep their lanes, which `membership` gives -- leaf lane id to the
 * ids of the nodes it held before. */
- (void)stackLanes:(NSDictionary<NSString *, NSArray<NSString *> *> *)membership
{
	WKDLane *pool = self.model.pool;
	NSArray<WKDLane *> *leaves = self.model.leafLanes;
	if (pool == nil && [leaves count] == 0) {
		return;
	}
	NSRect content = self.model.contentBounds;
	for (WKDNode *shape in self.model.nodes) {
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
	for (WKDNode *shape in [self laneMembers]) {
		if (shape.host == nil && ![placed containsObject:shape.elementId] && [leaves count] > 0) {
			[[held objectForKey:[[leaves firstObject] elementId]] addObject:shape.elementId];
		}
	}
	/* The shapes' bounds, read once: moving one changes the diagram. */
	NSArray<WKDNode *> *shapes = self.model.nodes;
	double band = WKDLaneBandWidth;
	double left = NSMinX(content) - WKDPoolMargin - band * (1 + [self laneLevels]);
	double right = NSMaxX(content) + WKDPoolMargin;
	double top = NSMinY(content) - WKDPoolMargin;
	NSMutableDictionary<NSString *, NSValue *> *spans = [NSMutableDictionary dictionary];
	double y = top;
	for (WKDLane *lane in leaves) {
		NSMutableSet *ids = [NSMutableSet set];
		for (NSString *nodeId in [held objectForKey:lane.elementId]) {
			WKDNode *shape = [self.model nodeWithId:nodeId];
			if (shape != nil && shape.host == nil) {
				[self collect:shape into:ids];
			}
		}
		NSRect box = NSZeroRect;
		for (WKDNode *shape in shapes) {
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
			for (WKDNode *shape in shapes) {
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
	for (WKDLane *lane in [self.model.lanes reverseObjectEnumerator]) {
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
		WKDLogAttribute(self.model.journal, [self diagramElement:@"BPMNShape" of:lane.elementId create:YES], @"isHorizontal", @"true");
	}
	if (pool != nil) {
		[self setBounds:NSMakeRect(left, top, right - left, y - top) of:pool.elementId];
		WKDLogAttribute(self.model.journal, [self diagramElement:@"BPMNShape" of:pool.elementId create:YES], @"isHorizontal", @"true");
	}
	[self syncModel];
}

/* Leaf lane id to the nodes it lists, as the document says now. */
- (NSDictionary<NSString *, NSArray<NSString *> *> *)laneMembership
{
	NSMutableDictionary *membership = [NSMutableDictionary dictionary];
	for (WKDNode *shape in [self laneMembers]) {
		WKDLane *lane = [self.model laneOf:shape];
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
	if (self.model.pool != nil) {
		return self.model.pool.elementId;
	}
	__block NSString *made = nil;
	[self change:@"Add Pool" with:^{
		made = [self makePool];
	}];
	return made;
}

- (NSString *)addLaneAfter:(NSString *)elementId
{
	WKDLane *after = [self.model laneWithId:elementId];
	if (after != nil && after.isPool && after != self.model.pool) {
		return nil;
	}
	__block NSString *made = nil;
	[self change:@"Add Lane" with:^{
		if (self.model.pool == nil) {
			[self makePool];
		}
		WKDLane *pool = self.model.pool;
		WKDLane *target = after != nil && !after.isPool ? [self.model laneWithId:after.elementId] : nil;
		if ([self.model.lanes count] == 0) {
			/* A pool without lanes: one lane first, holding all it holds. */
			NSXMLElement *laneSet = WKDEnsureChild(self.document, self.model.process, WKDBpmnNamespace, @"laneSet");
			WKDLogAttribute(self.model.journal, laneSet, @"id", [self freshId:@"LaneSet"]);
			NSRect r = pool.bounds;
			NSXMLElement *first = [self newLane:NSMakeRect(NSMinX(r) + WKDLaneBandWidth, NSMinY(r),
			                                                NSWidth(r) - WKDLaneBandWidth, NSHeight(r))];
			WKDLogAdd(self.model.journal, laneSet, first);
			[self syncModel];
			[self keepLanes];
			target = [self.model laneWithId:WKDAttribute(first, @"id")];
		}
		if (target == nil) {
			/* At the bottom of the pool: after its last lane. */
			for (WKDLane *lane in self.model.lanes) {
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
		WKDLogInsert(self.model.journal, set, lane, [target.element index] + 1);
		made = WKDAttribute(lane, @"id");
	}];
	return made;
}

@end

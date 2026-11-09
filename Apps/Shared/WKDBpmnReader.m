#import "WKDModelPriv.h"
#import "WKDXML.h"

static NSRect
WKDReadBounds(NSXMLElement *box)
{
	return NSMakeRect(WKDNumber(box, @"x"), WKDNumber(box, @"y"), WKDNumber(box, @"width"), WKDNumber(box, @"height"));
}

/* A BPMNLabel's bounds; NSZeroRect when the diagram element has none. */
static NSRect
WKDReadLabelBounds(NSXMLElement *diagramElement)
{
	NSXMLElement *label = WKDChild(diagramElement, WKDBpmnDINamespace, @"BPMNLabel");
	NSXMLElement *box = label != nil ? WKDChild(label, WKDDCNamespace, @"Bounds") : nil;
	return box != nil ? WKDReadBounds(box) : NSZeroRect;
}

/* What a node's own element says of it, besides its id, type and links. */
static void
WKDReadNodeValues(WKDNode *node)
{
	NSXMLElement *element = node.element;
	node.name = [node.type isEqualToString:@"textAnnotation"]
		? [WKDChild(element, WKDBpmnNamespace, @"text") stringValue]
		: WKDAttribute(element, @"name");
	node.eventDefinition = nil;
	for (NSXMLElement *inner in WKDChildren(element, WKDBpmnNamespace, nil)) {
		if ([[inner localName] hasSuffix:@"EventDefinition"]) {
			node.eventDefinition = [inner localName];
			break;
		}
	}
	NSString *interrupting = WKDAttribute(element, @"cancelActivity") ?: WKDAttribute(element, @"isInterrupting");
	node.interrupting = ![interrupting isEqualToString:@"false"];
	node.eventSubProcess = [WKDAttribute(element, @"triggeredByEvent") isEqualToString:@"true"];
	NSXMLElement *loop = WKDChild(element, WKDBpmnNamespace, @"multiInstanceLoopCharacteristics");
	node.loop = nil;
	if (loop != nil) {
		node.loop = [WKDAttribute(loop, @"isSequential") isEqualToString:@"true"] ? @"sequential" : @"parallel";
	} else if (WKDChild(element, WKDBpmnNamespace, @"standardLoopCharacteristics") != nil) {
		node.loop = @"standard";
	}
}

static void
WKDReadFlowValues(WKDFlow *flow)
{
	flow.name = WKDAttribute(flow.element, @"name");
	flow.hasCondition = WKDChild(flow.element, WKDBpmnNamespace, @"conditionExpression") != nil;
}

@implementation WKDModel (WKDReading)

- (BOOL)readDocument:(NSXMLDocument *)document
{
	self.document = document;
	NSXMLElement *root = [document rootElement];
	NSArray *processes = WKDChildren(root, WKDBpmnNamespace, @"process");
	for (NSXMLElement *process in processes) {
		if ([WKDAttribute(process, @"isExecutable") isEqualToString:@"true"]) {
			self.process = process;
			break;
		}
	}
	if (self.process == nil) {
		self.process = [processes firstObject];
	}
	if (self.process == nil) {
		return NO;
	}
	/* The plane that shows the process, else the first (a collaboration's,
	 * whose shapes name the process's elements). */
	NSString *processId = WKDAttribute(self.process, @"id");
	NSArray *planes = WKDDescendants(root, WKDBpmnDINamespace, @"BPMNPlane");
	for (NSXMLElement *plane in planes) {
		if ([WKDAttribute(plane, @"bpmnElement") isEqualToString:processId]) {
			self.plane = plane;
		}
	}
	if (self.plane == nil) {
		self.plane = [planes firstObject];
	}
	/* Every diagram element by the id it shows; the first wins, as for
	 * WKDDiagram. */
	NSMutableDictionary *shown = [NSMutableDictionary dictionary];
	for (NSXMLElement *plane in planes) {
		for (NSXMLNode *child in [plane children]) {
			if (WKDIs(child, WKDBpmnDINamespace, @"BPMNShape") || WKDIs(child, WKDBpmnDINamespace, @"BPMNEdge")) {
				NSString *ref = WKDAttribute((NSXMLElement *)child, @"bpmnElement");
				if (ref != nil && [shown objectForKey:ref] == nil) {
					[shown setObject:child forKey:ref];
				}
			}
		}
	}
	NSMutableArray *flowElements = [NSMutableArray array];
	[self readContainer:self.process parent:nil shown:shown flows:flowElements];
	/* Boundary events once every activity is known. */
	for (WKDNode *node in self.nodeList) {
		WKDNode *host = [self nodeWithId:WKDAttribute(node.element, @"attachedToRef")];
		if (host != nil) {
			node.host = host;
			[host.attachedList addObject:node];
		}
	}
	for (NSXMLElement *element in flowElements) {
		[self readFlow:element shown:shown];
	}
	for (WKDNode *node in self.nodeList) {
		WKDFlow *flow = [self flowWithId:WKDAttribute(node.element, @"default")];
		if (flow != nil && flow.source == node) {
			node.defaultFlow = flow;
		}
	}
	[self readLanes:root shown:shown];
	return YES;
}

- (void)readContainer:(NSXMLElement *)container
               parent:(WKDNode *)parent
                shown:(NSDictionary *)shown
                flows:(NSMutableArray *)flows
{
	for (NSXMLNode *child in [container children]) {
		if (!WKDIs(child, WKDBpmnNamespace, nil)) {
			continue;
		}
		NSXMLElement *element = (NSXMLElement *)child;
		NSString *type = [element localName];
		if ([type isEqualToString:@"sequenceFlow"] || [type isEqualToString:@"association"]) {
			[flows addObject:element];
			continue;
		}
		BOOL flowNode = NO;
		WKDShapeKind kind = WKDKindOfType(type, &flowNode);
		NSString *elementId = WKDAttribute(element, @"id");
		if (!flowNode || elementId == nil || [self nodeWithId:elementId] != nil) {
			continue;
		}
		WKDNode *node = [[WKDNode alloc] init];
		node.model = self;
		node.element = element;
		node.elementId = elementId;
		node.type = type;
		node.kind = kind;
		node.parent = parent;
		NSXMLElement *shape = [shown objectForKey:elementId];
		if (shape != nil && WKDIs(shape, WKDBpmnDINamespace, @"BPMNShape")) {
			node.diagramElement = shape;
			NSXMLElement *box = WKDChild(shape, WKDDCNamespace, @"Bounds");
			node.hasBounds = box != nil;
			node.bounds = box != nil ? WKDReadBounds(box) : NSZeroRect;
			node.labelBounds = WKDReadLabelBounds(shape);
		}
		WKDReadNodeValues(node);
		[self.nodeList addObject:node];
		[self.nodesById setObject:node forKey:elementId];
		/* Boundary events are their activity's, not their container's
		 * children: they are known once every node is. */
		if (WKDAttribute(element, @"attachedToRef") == nil) {
			[parent.childList addObject:node];
		}
		if (WKDIsContainerType(type)) {
			[self readContainer:element parent:node shown:shown flows:flows];
		}
	}
}

- (void)readFlow:(NSXMLElement *)element shown:(NSDictionary *)shown
{
	NSString *elementId = WKDAttribute(element, @"id");
	WKDNode *source = [self nodeWithId:WKDAttribute(element, @"sourceRef")];
	WKDNode *target = [self nodeWithId:WKDAttribute(element, @"targetRef")];
	if (elementId == nil || source == nil || target == nil || [self flowWithId:elementId] != nil) {
		return;
	}
	WKDFlow *flow = [[WKDFlow alloc] init];
	flow.model = self;
	flow.element = element;
	flow.elementId = elementId;
	flow.isAssociation = [[element localName] isEqualToString:@"association"];
	WKDReadFlowValues(flow);
	flow.source = source;
	flow.target = target;
	[source.outgoingList addObject:flow];
	[target.incomingList addObject:flow];
	NSXMLElement *edge = [shown objectForKey:elementId];
	NSMutableArray *points = [NSMutableArray array];
	if (edge != nil && WKDIs(edge, WKDBpmnDINamespace, @"BPMNEdge")) {
		flow.diagramElement = edge;
		for (NSXMLElement *waypoint in WKDChildren(edge, WKDDINamespace, @"waypoint")) {
			[points addObject:[NSValue valueWithPoint:NSMakePoint(WKDNumber(waypoint, @"x"), WKDNumber(waypoint, @"y"))]];
		}
		flow.labelBounds = WKDReadLabelBounds(edge);
	}
	flow.waypoints = [points count] >= 2 ? points : @[];
	[self.flowList addObject:flow];
	[self.flowsById setObject:flow forKey:elementId];
}

- (WKDLane *)laneFor:(NSXMLElement *)element pool:(BOOL)pool parent:(WKDLane *)parent shown:(NSDictionary *)shown
{
	WKDLane *lane = [[WKDLane alloc] init];
	lane.model = self;
	lane.element = element;
	lane.elementId = WKDAttribute(element, @"id") ?: @"";
	lane.name = WKDAttribute(element, @"name");
	lane.isPool = pool;
	lane.parent = parent;
	lane.depth = parent != nil ? parent.depth + 1 : 0;
	NSXMLElement *shape = [shown objectForKey:lane.elementId];
	if (shape != nil && WKDIs(shape, WKDBpmnDINamespace, @"BPMNShape")) {
		lane.diagramElement = shape;
		NSXMLElement *box = WKDChild(shape, WKDDCNamespace, @"Bounds");
		lane.hasBounds = box != nil;
		lane.bounds = box != nil ? WKDReadBounds(box) : NSZeroRect;
	}
	lane.horizontal = ![WKDAttribute(shape, @"isHorizontal") isEqualToString:@"false"];
	NSMutableArray *others = [NSMutableArray array];
	for (NSXMLElement *ref in WKDChildren(element, WKDBpmnNamespace, @"flowNodeRef")) {
		NSString *nodeId = [[ref stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([nodeId length] == 0) {
			continue;
		}
		WKDNode *node = [self nodeWithId:nodeId];
		if (node != nil) {
			[lane.nodeList addObject:node];
		} else {
			[others addObject:nodeId];
		}
	}
	lane.otherIds = others;
	if ([lane.elementId length] > 0) {
		[self.lanesById setObject:lane forKey:lane.elementId];
	}
	return lane;
}

/* A laneSet's lanes, each followed by those dividing it. */
- (NSArray<WKDLane *> *)lanesIn:(NSXMLElement *)laneSet parent:(WKDLane *)parent shown:(NSDictionary *)shown
                            all:(NSMutableArray *)all
{
	NSMutableArray *lanes = [NSMutableArray array];
	for (NSXMLElement *element in WKDChildren(laneSet, WKDBpmnNamespace, @"lane")) {
		WKDLane *lane = [self laneFor:element pool:NO parent:parent shown:shown];
		[lanes addObject:lane];
		[all addObject:lane];
		NSXMLElement *childSet = WKDChild(element, WKDBpmnNamespace, @"childLaneSet");
		lane.children = childSet != nil ? [self lanesIn:childSet parent:lane shown:shown all:all] : @[];
	}
	return lanes;
}

- (void)readLanes:(NSXMLElement *)root shown:(NSDictionary *)shown
{
	NSString *processId = WKDAttribute(self.process, @"id");
	NSMutableArray *others = [NSMutableArray array];
	for (NSXMLElement *collaboration in WKDChildren(root, WKDBpmnNamespace, @"collaboration")) {
		for (NSXMLElement *participant in WKDChildren(collaboration, WKDBpmnNamespace, @"participant")) {
			WKDLane *pool = [self laneFor:participant pool:YES parent:nil shown:shown];
			if (self.pool == nil && processId != nil && [WKDAttribute(participant, @"processRef") isEqualToString:processId]) {
				self.pool = pool;
			} else {
				[others addObject:pool];
			}
		}
	}
	self.otherPools = others;
	NSMutableArray *all = [NSMutableArray array];
	NSXMLElement *laneSet = WKDChild(self.process, WKDBpmnNamespace, @"laneSet");
	NSArray *top = laneSet != nil ? [self lanesIn:laneSet parent:nil shown:shown all:all] : @[];
	self.pool.children = top;
	self.lanes = all;
	/* Each node's innermost lane: lanes come before those dividing them. */
	for (WKDLane *lane in all) {
		for (WKDNode *node in lane.nodeList) {
			if (node.lane == nil || lane.depth >= node.lane.depth) {
				node.lane = lane;
			}
		}
	}
}

@end

@implementation WKDModel (WKDReadingAgain)

- (void)readValuesAgain:(WKDModelElement *)element
{
	[self.journal willChange:element];
	if ([element isKindOfClass:[WKDNode class]]) {
		WKDNode *node = (WKDNode *)element;
		WKDReadNodeValues(node);
		WKDFlow *preferred = [self flowWithId:WKDAttribute(node.element, @"default")];
		node.defaultFlow = preferred.source == node ? preferred : nil;
	} else if ([element isKindOfClass:[WKDFlow class]]) {
		WKDReadFlowValues((WKDFlow *)element);
	} else {
		element.name = WKDAttribute(element.element, @"name");
	}
}

/* The document read again into these objects: an element whose id is still
 * there is the same object, its values and links those read now; one no
 * longer there leaves the model; one new comes in. For an operation that
 * still edits the XML, and for undo, until they change the model itself. */
- (void)readDocumentAgain:(NSXMLDocument *)document
{
	WKDModel *fresh = [WKDModel modelOfDocument:document];
	NSMutableDictionary *nodes = [NSMutableDictionary dictionary];
	NSMutableDictionary *flows = [NSMutableDictionary dictionary];
	NSMutableDictionary *lanes = [NSMutableDictionary dictionary];
	/* Each fresh element's lasting object: the one of its id, else itself. */
	NSMapTable *lasting = [NSMapTable strongToStrongObjectsMapTable];
	for (WKDNode *node in fresh.nodeList) {
		WKDNode *kept = [self.nodesById objectForKey:node.elementId] ?: node;
		[lasting setObject:kept forKey:node];
		[nodes setObject:kept forKey:node.elementId];
	}
	for (WKDFlow *flow in fresh.flowList) {
		WKDFlow *kept = [self.flowsById objectForKey:flow.elementId] ?: flow;
		[lasting setObject:kept forKey:flow];
		[flows setObject:kept forKey:flow.elementId];
	}
	NSMutableArray *freshLanes = [NSMutableArray arrayWithArray:fresh.lanes];
	[freshLanes addObjectsFromArray:fresh.otherPools];
	if (fresh.pool != nil) {
		[freshLanes addObject:fresh.pool];
	}
	for (WKDLane *lane in freshLanes) {
		WKDLane *kept = ([lane.elementId length] > 0 ? [self.lanesById objectForKey:lane.elementId] : nil) ?: lane;
		if (kept.isPool != lane.isPool) {
			kept = lane;
		}
		[lasting setObject:kept forKey:lane];
		if ([lane.elementId length] > 0) {
			[lanes setObject:kept forKey:lane.elementId];
		}
	}
	id (^map)(id) = ^id (id object) {
		return object != nil ? [lasting objectForKey:object] : nil;
	};
	NSArray *(^mapAll)(NSArray *) = ^NSArray *(NSArray *objects) {
		NSMutableArray *mapped = [NSMutableArray arrayWithCapacity:[objects count]];
		for (id object in objects) {
			[mapped addObject:map(object)];
		}
		return mapped;
	};
	for (WKDNode *node in fresh.nodeList) {
		WKDNode *kept = map(node);
		kept.model = self;
		kept.element = node.element;
		kept.diagramElement = node.diagramElement;
		kept.name = node.name;
		kept.type = node.type;
		kept.kind = node.kind;
		kept.bounds = node.bounds;
		kept.hasBounds = node.hasBounds;
		kept.labelBounds = node.labelBounds;
		kept.eventDefinition = node.eventDefinition;
		kept.interrupting = node.interrupting;
		kept.eventSubProcess = node.eventSubProcess;
		kept.loop = node.loop;
		kept.parent = map(node.parent);
		kept.host = map(node.host);
		kept.defaultFlow = map(node.defaultFlow);
		kept.lane = map(node.lane);
		kept.childList = [mapAll(node.childList) mutableCopy];
		kept.attachedList = [mapAll(node.attachedList) mutableCopy];
		kept.incomingList = [mapAll(node.incomingList) mutableCopy];
		kept.outgoingList = [mapAll(node.outgoingList) mutableCopy];
	}
	for (WKDFlow *flow in fresh.flowList) {
		WKDFlow *kept = map(flow);
		kept.model = self;
		kept.element = flow.element;
		kept.diagramElement = flow.diagramElement;
		kept.name = flow.name;
		kept.isAssociation = flow.isAssociation;
		kept.hasCondition = flow.hasCondition;
		kept.waypoints = flow.waypoints;
		kept.labelBounds = flow.labelBounds;
		kept.source = map(flow.source);
		kept.target = map(flow.target);
	}
	for (WKDLane *lane in freshLanes) {
		WKDLane *kept = map(lane);
		kept.model = self;
		kept.element = lane.element;
		kept.diagramElement = lane.diagramElement;
		kept.elementId = lane.elementId;
		kept.name = lane.name;
		kept.bounds = lane.bounds;
		kept.hasBounds = lane.hasBounds;
		kept.isPool = lane.isPool;
		kept.horizontal = lane.horizontal;
		kept.depth = lane.depth;
		kept.parent = map(lane.parent);
		kept.children = mapAll(lane.children);
		kept.nodeList = [mapAll(lane.nodeList) mutableCopy];
		kept.otherIds = lane.otherIds;
	}
	self.document = document;
	self.process = fresh.process;
	self.plane = fresh.plane;
	self.nodeList = [mapAll(fresh.nodeList) mutableCopy];
	self.flowList = [mapAll(fresh.flowList) mutableCopy];
	self.nodesById = nodes;
	self.flowsById = flows;
	self.lanesById = lanes;
	self.pool = map(fresh.pool);
	self.lanes = mapAll(fresh.lanes);
	self.otherPools = mapAll(fresh.otherPools);
	[self.changedElements removeAllObjects];
	[self.deletedElements removeAllObjects];
}

@end

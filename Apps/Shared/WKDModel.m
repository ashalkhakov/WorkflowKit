#import "WKDModelPriv.h"
#import "WKDXML.h"

@implementation WKDModelElement

- (void)changed
{
	[self.model.changedElements addObject:self];
}

- (void)willChange
{
	[self.model.journal willChange:self];
	[self changed];
}

/* The keys of its state, for the journal. */
+ (NSArray<NSString *> *)journalKeys
{
	/* Its carrier and diagram elements, and where they were, are the
	 * writer's to keep, not the element's state. */
	return @[ @"elementId", @"name" ];
}

- (NSDictionary *)journalState
{
	NSMutableDictionary *state = [NSMutableDictionary dictionary];
	for (NSString *key in [[self class] journalKeys]) {
		id value = [self valueForKey:key];
		/* Lists by their contents as they are now. */
		if ([value isKindOfClass:[NSMutableArray class]]) {
			value = [value copy];
		}
		[state setObject:value ?: [NSNull null] forKey:key];
	}
	return state;
}

- (void)restoreJournalState:(NSDictionary *)state
{
	for (NSString *key in [[self class] journalKeys]) {
		id value = [state objectForKey:key];
		if (value == [NSNull null]) {
			value = nil;
		}
		if ([key hasSuffix:@"List"]) {
			value = [value mutableCopy] ?: [NSMutableArray array];
		}
		[self setValue:value forKey:key];
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@>", NSStringFromClass([self class]), self.elementId];
}

@end

@implementation WKDNode

- (instancetype)init
{
	if ((self = [super init])) {
		_childList = [NSMutableArray array];
		_attachedList = [NSMutableArray array];
		_incomingList = [NSMutableArray array];
		_outgoingList = [NSMutableArray array];
		_interrupting = YES;
	}
	return self;
}

+ (NSArray<NSString *> *)journalKeys
{
	return [[super journalKeys] arrayByAddingObjectsFromArray:@[
		@"type", @"kind", @"bounds", @"hasBounds", @"labelBounds", @"eventDefinition", @"interrupting",
		@"eventSubProcess", @"loop", @"parent", @"host", @"defaultFlow", @"lane",
		@"childList", @"attachedList", @"incomingList", @"outgoingList" ]];
}

- (NSArray<WKDNode *> *)children { return [_childList copy]; }
- (NSArray<WKDNode *> *)attached { return [_attachedList copy]; }
- (NSArray<WKDFlow *> *)incoming { return [_incomingList copy]; }
- (NSArray<WKDFlow *> *)outgoing { return [_outgoingList copy]; }

@end

@implementation WKDFlow

+ (NSArray<NSString *> *)journalKeys
{
	return [[super journalKeys] arrayByAddingObjectsFromArray:@[
		@"source", @"target", @"isAssociation", @"hasCondition", @"waypoints", @"labelBounds" ]];
}

- (BOOL)isDefault
{
	return self.source != nil && self.source.defaultFlow == self;
}

@end

@implementation WKDLane

- (instancetype)init
{
	if ((self = [super init])) {
		_nodeList = [NSMutableArray array];
		_children = @[];
		_otherIds = @[];
	}
	return self;
}

+ (NSArray<NSString *> *)journalKeys
{
	return [[super journalKeys] arrayByAddingObjectsFromArray:@[
		@"bounds", @"hasBounds", @"isPool", @"horizontal", @"parent", @"depth", @"children", @"nodeList", @"otherIds" ]];
}

- (NSArray<WKDNode *> *)nodes { return [_nodeList copy]; }

- (NSArray<NSString *> *)flowNodeIds
{
	NSMutableArray *ids = [[_nodeList valueForKey:@"elementId"] mutableCopy];
	[ids addObjectsFromArray:_otherIds];
	return ids;
}

@end

@implementation WKDModel

+ (instancetype)modelOfDocument:(NSXMLDocument *)document
{
	WKDModel *model = [[self alloc] init];
	return [model readDocument:document] ? model : nil;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_nodeList = [NSMutableArray array];
		_flowList = [NSMutableArray array];
		_nodesById = [NSMutableDictionary dictionary];
		_flowsById = [NSMutableDictionary dictionary];
		_lanesById = [NSMutableDictionary dictionary];
		_changedElements = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
		_deletedElements = [NSMutableArray array];
		_lanes = @[];
		_otherPools = @[];
		_journal = [[WKDJournal alloc] initWithModel:self];
	}
	return self;
}

- (NSArray<WKDNode *> *)nodes { return [_nodeList copy]; }
- (NSArray<WKDFlow *> *)flows { return [_flowList copy]; }

- (NSArray<WKDNode *> *)topNodes
{
	NSMutableArray *top = [NSMutableArray array];
	for (WKDNode *node in _nodeList) {
		if (node.parent == nil && node.host == nil) {
			[top addObject:node];
		}
	}
	return top;
}

- (WKDNode *)nodeWithId:(NSString *)elementId
{
	return elementId != nil ? [_nodesById objectForKey:elementId] : nil;
}

- (WKDFlow *)flowWithId:(NSString *)elementId
{
	return elementId != nil ? [_flowsById objectForKey:elementId] : nil;
}

- (WKDLane *)laneWithId:(NSString *)elementId
{
	return elementId != nil ? [_lanesById objectForKey:elementId] : nil;
}

- (NSArray<WKDFlow *> *)flowsOf:(WKDNode *)node
{
	return [node.incomingList arrayByAddingObjectsFromArray:node.outgoingList] ?: @[];
}

- (NSArray<WKDNode *> *)nodesIn:(WKDNode *)container
{
	return container != nil ? container.children : self.topNodes;
}

- (WKDLane *)laneOf:(WKDNode *)node
{
	return node.lane;
}

- (NSArray<WKDLane *> *)leafLanes
{
	NSMutableArray *leaves = [NSMutableArray array];
	for (WKDLane *lane in _lanes) {
		if ([lane.children count] == 0) {
			[leaves addObject:lane];
		}
	}
	return leaves;
}

- (BOOL)needsLayout
{
	for (WKDNode *node in _nodeList) {
		if (!node.hasBounds) {
			return YES;
		}
	}
	return NO;
}

- (NSRect)contentBounds
{
	NSRect bounds = NSZeroRect;
	for (WKDNode *node in _nodeList) {
		if (node.hasBounds) {
			bounds = NSIsEmptyRect(bounds) ? node.bounds : NSUnionRect(bounds, node.bounds);
		}
	}
	NSMutableArray *bands = [NSMutableArray arrayWithArray:_lanes];
	if (_pool != nil) {
		[bands addObject:_pool];
	}
	[bands addObjectsFromArray:_otherPools];
	for (WKDLane *lane in bands) {
		if (lane.hasBounds) {
			bounds = NSIsEmptyRect(bounds) ? lane.bounds : NSUnionRect(bounds, lane.bounds);
		}
	}
	return bounds;
}

#pragma mark Changes

- (BOOL)hasChanges
{
	return [_changedElements count] > 0 || [_deletedElements count] > 0;
}

- (void)write
{
	if ([self hasChanges]) {
		[self writeChanges];
	}
}

- (void)markEverythingChanged
{
	for (WKDNode *node in _nodeList) {
		[_changedElements addObject:node];
	}
	for (WKDFlow *flow in _flowList) {
		[_changedElements addObject:flow];
	}
	for (WKDLane *lane in _lanes) {
		[_changedElements addObject:lane];
	}
	if (_pool != nil) {
		[_changedElements addObject:_pool];
	}
}

#pragma mark The journal

- (NSDictionary *)journalState
{
	return @{
		@"nodeList": [self.nodeList copy], @"flowList": [self.flowList copy],
		@"nodesById": [self.nodesById copy], @"flowsById": [self.flowsById copy], @"lanesById": [self.lanesById copy],
		@"pool": self.pool ?: [NSNull null], @"lanes": self.lanes, @"otherPools": self.otherPools,
		@"plane": self.plane ?: [NSNull null],
	};
}

- (void)restoreJournalState:(NSDictionary *)state
{
	self.nodeList = [[state objectForKey:@"nodeList"] mutableCopy];
	self.flowList = [[state objectForKey:@"flowList"] mutableCopy];
	self.nodesById = [[state objectForKey:@"nodesById"] mutableCopy];
	self.flowsById = [[state objectForKey:@"flowsById"] mutableCopy];
	self.lanesById = [[state objectForKey:@"lanesById"] mutableCopy];
	id pool = [state objectForKey:@"pool"];
	self.pool = pool != [NSNull null] ? pool : nil;
	self.lanes = [state objectForKey:@"lanes"];
	self.otherPools = [state objectForKey:@"otherPools"];
	id plane = [state objectForKey:@"plane"];
	self.plane = plane != [NSNull null] ? plane : nil;
}

- (BOOL)containsElement:(WKDModelElement *)element
{
	if ([element isKindOfClass:[WKDNode class]]) {
		return [self.nodesById objectForKey:element.elementId] == element;
	}
	if ([element isKindOfClass:[WKDFlow class]]) {
		return [self.flowsById objectForKey:element.elementId] == element;
	}
	return [element isKindOfClass:[WKDLane class]]
		&& ([self.lanesById objectForKey:element.elementId] == element || self.pool == element);
}

/* By the id the node names, then by identity: a node with an element's
 * id is not its carrier unless it is the very one. */
- (BOOL)carries:(NSXMLNode *)node
{
	if ([node kind] != NSXMLElementKind) {
		return NO;
	}
	NSXMLElement *element = (NSXMLElement *)node;
	NSMutableArray *candidates = [NSMutableArray arrayWithCapacity:2];
	for (NSString *name in @[ @"bpmnElement", @"id" ]) {
		NSString *elementId = WKDAttribute(element, name);
		WKDModelElement *found = elementId == nil ? nil : [self.nodesById objectForKey:elementId]
			?: [self.flowsById objectForKey:elementId] ?: (WKDModelElement *)[self.lanesById objectForKey:elementId];
		if (found != nil) {
			[candidates addObject:found];
		}
	}
	if (self.pool != nil) {
		[candidates addObject:self.pool];
	}
	[candidates addObjectsFromArray:self.otherPools];
	for (WKDModelElement *candidate in candidates) {
		if (candidate.element == element || candidate.diagramElement == element) {
			return YES;
		}
	}
	return NO;
}

#pragma mark Making and removing

- (WKDNode *)makeNodeOfType:(NSString *)type elementId:(NSString *)elementId in:(WKDNode *)container
{
	[self.journal willChangeModel];
	BOOL flowNode = NO;
	WKDNode *node = [[WKDNode alloc] init];
	node.model = self;
	node.elementId = elementId;
	node.type = type;
	node.kind = WKDKindOfType(type, &flowNode);
	[node willChange];
	if (container != nil) {
		[container willChange];
		[container.childList addObject:node];
		node.parent = container;
	}
	/* Containers before what they contain: after the container's last
	 * descendant, else at the end. */
	NSUInteger index = [self.nodeList count];
	if (container != nil) {
		NSUInteger at = [self.nodeList indexOfObjectIdenticalTo:container];
		index = at + 1;
		while (index < [self.nodeList count] && [self node:[self.nodeList objectAtIndex:index] isIn:container]) {
			index++;
		}
	}
	[self.nodeList insertObject:node atIndex:index];
	[self.nodesById setObject:node forKey:elementId];
	return node;
}

- (BOOL)node:(WKDNode *)node isIn:(WKDNode *)container
{
	for (WKDNode *up = node.parent ?: node.host.parent; up != nil; up = up.parent) {
		if (up == container) {
			return YES;
		}
	}
	return NO;
}

- (WKDFlow *)makeFlowFrom:(WKDNode *)source to:(WKDNode *)target elementId:(NSString *)elementId
              association:(BOOL)association
{
	[self.journal willChangeModel];
	WKDFlow *flow = [[WKDFlow alloc] init];
	flow.model = self;
	flow.elementId = elementId;
	flow.isAssociation = association;
	flow.waypoints = @[];
	[flow willChange];
	[self setSource:source ofFlow:flow];
	[self setTarget:target ofFlow:flow];
	[self.flowList addObject:flow];
	[self.flowsById setObject:flow forKey:elementId];
	return flow;
}

- (void)renameElement:(WKDModelElement *)element to:(NSString *)elementId
{
	NSMutableDictionary *byId = self.lanesById;
	if ([element isKindOfClass:[WKDNode class]]) {
		byId = self.nodesById;
	} else if ([element isKindOfClass:[WKDFlow class]]) {
		byId = self.flowsById;
	}
	if ([byId objectForKey:element.elementId] != element) {
		return;
	}
	[self.journal willChangeModel];
	[element willChange];
	[byId removeObjectForKey:element.elementId];
	element.elementId = elementId;
	[byId setObject:element forKey:elementId];
}

- (void)removeFlow:(WKDFlow *)flow
{
	if (![self containsElement:flow]) {
		return;
	}
	[self.journal willChangeModel];
	[flow willChange];
	if (flow.source.defaultFlow == flow) {
		[self setDefaultFlow:nil ofNode:flow.source];
	}
	[flow.source willChange];
	[flow.source.outgoingList removeObjectIdenticalTo:flow];
	flow.source.flowsChanged = YES;
	[flow.target willChange];
	[flow.target.incomingList removeObjectIdenticalTo:flow];
	flow.target.flowsChanged = YES;
	[self.flowList removeObjectIdenticalTo:flow];
	[self.flowsById removeObjectForKey:flow.elementId];
	[self.deletedElements addObject:flow];
}

- (void)removeNode:(WKDNode *)node
{
	if (![self containsElement:node]) {
		return;
	}
	for (WKDNode *child in [node.childList copy]) {
		[self removeNode:child];
	}
	for (WKDNode *attached in [node.attachedList copy]) {
		[self removeNode:attached];
	}
	for (WKDFlow *flow in [node.incomingList arrayByAddingObjectsFromArray:node.outgoingList]) {
		[self removeFlow:flow];
	}
	[self.journal willChangeModel];
	[node willChange];
	if (node.parent != nil) {
		[node.parent willChange];
		[node.parent.childList removeObjectIdenticalTo:node];
	}
	if (node.host != nil) {
		[node.host willChange];
		[node.host.attachedList removeObjectIdenticalTo:node];
	}
	if (node.lane != nil) {
		[node.lane willChange];
		[node.lane.nodeList removeObjectIdenticalTo:node];
	}
	[self.nodeList removeObjectIdenticalTo:node];
	[self.nodesById removeObjectForKey:node.elementId];
	[self.deletedElements addObject:node];
}

#pragma mark Links

- (void)setSource:(WKDNode *)source ofFlow:(WKDFlow *)flow
{
	if (flow.source == source) {
		return;
	}
	[flow willChange];
	[flow.source willChange];
	[source willChange];
	[flow.source.outgoingList removeObjectIdenticalTo:flow];
	flow.source.flowsChanged = YES;
	flow.source = source;
	[source.outgoingList addObject:flow];
	source.flowsChanged = YES;
}

- (void)setTarget:(WKDNode *)target ofFlow:(WKDFlow *)flow
{
	if (flow.target == target) {
		return;
	}
	[flow willChange];
	[flow.target willChange];
	[target willChange];
	[flow.target.incomingList removeObjectIdenticalTo:flow];
	flow.target.flowsChanged = YES;
	flow.target = target;
	[target.incomingList addObject:flow];
	target.flowsChanged = YES;
}

- (void)setHost:(WKDNode *)host ofNode:(WKDNode *)node
{
	if (node.host == host) {
		return;
	}
	[node willChange];
	[node.host willChange];
	[host willChange];
	[node.host.attachedList removeObjectIdenticalTo:node];
	node.host = host;
	[host.attachedList addObject:node];
}

- (void)setDefaultFlow:(WKDFlow *)flow ofNode:(WKDNode *)node
{
	if (node.defaultFlow == flow) {
		return;
	}
	[node willChange];
	node.defaultFlow = flow;
}

@end

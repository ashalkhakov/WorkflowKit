#import "WKDModelPriv.h"

@implementation WKDModelElement

- (void)changed
{
	[self.model.changedElements addObject:self];
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

- (NSArray<WKDNode *> *)children { return [_childList copy]; }
- (NSArray<WKDNode *> *)attached { return [_attachedList copy]; }
- (NSArray<WKDFlow *> *)incoming { return [_incomingList copy]; }
- (NSArray<WKDFlow *> *)outgoing { return [_outgoingList copy]; }

@end

@implementation WKDFlow

- (BOOL)isDefault
{
	return self.source != nil && self.source.defaultFlow == self;
}

@end

@implementation WKDSwimlane

- (instancetype)init
{
	if ((self = [super init])) {
		_nodeList = [NSMutableArray array];
		_children = @[];
		_otherIds = @[];
	}
	return self;
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

- (WKDSwimlane *)laneWithId:(NSString *)elementId
{
	return elementId != nil ? [_lanesById objectForKey:elementId] : nil;
}

- (NSArray<WKDSwimlane *> *)leafLanes
{
	NSMutableArray *leaves = [NSMutableArray array];
	for (WKDSwimlane *lane in _lanes) {
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
	for (WKDSwimlane *lane in bands) {
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
	for (WKDSwimlane *lane in _lanes) {
		[_changedElements addObject:lane];
	}
	if (_pool != nil) {
		[_changedElements addObject:_pool];
	}
}

#pragma mark Links

- (void)setSource:(WKDNode *)source ofFlow:(WKDFlow *)flow
{
	if (flow.source == source) {
		return;
	}
	[flow.source.outgoingList removeObjectIdenticalTo:flow];
	if (flow.source != nil) {
		[flow.source changed];
	}
	flow.source = source;
	[source.outgoingList addObject:flow];
	[source changed];
	[flow changed];
}

- (void)setTarget:(WKDNode *)target ofFlow:(WKDFlow *)flow
{
	if (flow.target == target) {
		return;
	}
	[flow.target.incomingList removeObjectIdenticalTo:flow];
	if (flow.target != nil) {
		[flow.target changed];
	}
	flow.target = target;
	[target.incomingList addObject:flow];
	[target changed];
	[flow changed];
}

- (void)setHost:(WKDNode *)host ofNode:(WKDNode *)node
{
	if (node.host == host) {
		return;
	}
	[node.host.attachedList removeObjectIdenticalTo:node];
	node.host = host;
	[host.attachedList addObject:node];
	[node changed];
}

- (void)setDefaultFlow:(WKDFlow *)flow ofNode:(WKDNode *)node
{
	if (node.defaultFlow == flow) {
		return;
	}
	node.defaultFlow = flow;
	[node changed];
}

@end

#import "WKDModelPriv.h"

static NSArray *
WKDIds(NSArray *elements)
{
	return [elements valueForKey:@"elementId"] ?: @[];
}

static BOOL
WKDSame(id a, id b)
{
	return a == b || [a isEqual:b];
}

@implementation WKDModel (WKDChecking)

- (NSString *)disagreementWith:(WKDModel *)other
{
	if (!WKDSame(WKDIds(self.nodeList), WKDIds(other.nodeList))) {
		return [NSString stringWithFormat:@"nodes %@, read afresh %@", WKDIds(self.nodeList), WKDIds(other.nodeList)];
	}
	for (WKDNode *node in self.nodeList) {
		WKDNode *read = [other nodeWithId:node.elementId];
		NSString *differs = nil;
		if (!WKDSame(node.type, read.type)) differs = @"type";
		else if (node.kind != read.kind) differs = @"kind";
		else if (!WKDSame(node.name, read.name)) differs = @"name";
		else if (node.hasBounds != read.hasBounds || !NSEqualRects(node.bounds, read.bounds)) {
			differs = [NSString stringWithFormat:@"bounds %@, read %@", NSStringFromRect(node.bounds), NSStringFromRect(read.bounds)];
		}
		else if (!NSEqualRects(node.labelBounds, read.labelBounds)) {
			differs = [NSString stringWithFormat:@"label bounds %@, read %@", NSStringFromRect(node.labelBounds),
				NSStringFromRect(read.labelBounds)];
		}
		else if (!WKDSame(node.eventDefinition, read.eventDefinition)) differs = @"event definition";
		else if (node.interrupting != read.interrupting) differs = @"interrupting";
		else if (node.eventSubProcess != read.eventSubProcess) differs = @"event subprocess";
		else if (!WKDSame(node.loop, read.loop)) differs = @"loop";
		else if (!WKDSame(node.parent.elementId, read.parent.elementId)) differs = @"parent";
		else if (!WKDSame(node.host.elementId, read.host.elementId)) differs = @"host";
		else if (!WKDSame(node.defaultFlow.elementId, read.defaultFlow.elementId)) differs = @"default flow";
		else if (!WKDSame(node.lane.elementId, read.lane.elementId)) {
			differs = [NSString stringWithFormat:@"lane %@, read %@", node.lane.elementId, read.lane.elementId];
		}
		else if (!WKDSame(WKDIds(node.childList), WKDIds(read.childList))) differs = @"children";
		else if (![[NSSet setWithArray:WKDIds(node.attachedList)] isEqualToSet:[NSSet setWithArray:WKDIds(read.attachedList)]]) differs = @"attached";
		else if (![[NSSet setWithArray:WKDIds(node.incomingList)] isEqualToSet:[NSSet setWithArray:WKDIds(read.incomingList)]]) differs = @"incoming";
		else if (![[NSSet setWithArray:WKDIds(node.outgoingList)] isEqualToSet:[NSSet setWithArray:WKDIds(read.outgoingList)]]) differs = @"outgoing";
		if (differs != nil) {
			return [NSString stringWithFormat:@"node %@: its %@", node.elementId, differs];
		}
	}
	/* The flows' order means nothing: a new one is at the end of the list,
	 * wherever its container puts it in the document. */
	if (![[NSSet setWithArray:WKDIds(self.flowList)] isEqualToSet:[NSSet setWithArray:WKDIds(other.flowList)]]) {
		return [NSString stringWithFormat:@"flows %@, read afresh %@", WKDIds(self.flowList), WKDIds(other.flowList)];
	}
	for (WKDFlow *flow in self.flowList) {
		WKDFlow *read = [other flowWithId:flow.elementId];
		NSString *differs = nil;
		if (!WKDSame(flow.name, read.name)) differs = @"name";
		else if (!WKDSame(flow.source.elementId, read.source.elementId)) differs = @"source";
		else if (!WKDSame(flow.target.elementId, read.target.elementId)) differs = @"target";
		else if (flow.isAssociation != read.isAssociation) differs = @"kind";
		else if (flow.hasCondition != read.hasCondition) differs = @"condition";
		else if (!WKDSame(flow.waypoints, read.waypoints)) {
			differs = [NSString stringWithFormat:@"waypoints %@, read %@", flow.waypoints, read.waypoints];
		}
		else if (!NSEqualRects(flow.labelBounds, read.labelBounds)) {
			differs = [NSString stringWithFormat:@"label bounds %@, read %@", NSStringFromRect(flow.labelBounds),
				NSStringFromRect(read.labelBounds)];
		}
		if (differs != nil) {
			return [NSString stringWithFormat:@"flow %@: its %@", flow.elementId, differs];
		}
	}
	if (!WKDSame(self.pool.elementId, other.pool.elementId)) {
		return @"pool";
	}
	NSMutableArray *lanes = [NSMutableArray arrayWithArray:self.lanes];
	NSMutableArray *read = [NSMutableArray arrayWithArray:other.lanes];
	if (self.pool != nil) {
		[lanes addObject:self.pool];
		[read addObject:other.pool];
	}
	[lanes addObjectsFromArray:self.otherPools];
	[read addObjectsFromArray:other.otherPools];
	if (!WKDSame(WKDIds(lanes), WKDIds(read))) {
		return [NSString stringWithFormat:@"lanes %@, read afresh %@", WKDIds(lanes), WKDIds(read)];
	}
	for (NSUInteger i = 0; i < [lanes count]; i++) {
		WKDLane *lane = [lanes objectAtIndex:i], *again = [read objectAtIndex:i];
		NSString *differs = nil;
		if (!WKDSame(lane.name, again.name)) differs = @"name";
		else if (lane.hasBounds != again.hasBounds || !NSEqualRects(lane.bounds, again.bounds)) differs = @"bounds";
		else if (lane.horizontal != again.horizontal) differs = @"orientation";
		else if (!WKDSame(lane.parent.elementId, again.parent.elementId)) differs = @"parent";
		else if (!WKDSame(WKDIds(lane.children), WKDIds(again.children))) differs = @"children";
		else if (![[NSSet setWithArray:lane.flowNodeIds] isEqualToSet:[NSSet setWithArray:again.flowNodeIds]]) differs = @"nodes";
		if (differs != nil) {
			return [NSString stringWithFormat:@"lane %@: its %@", lane.elementId, differs];
		}
	}
	return nil;
}

@end

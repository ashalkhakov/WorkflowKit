#import "WKDLayout.h"

/* A node of the layered graph: one of ours, or a placeholder on a long edge. */
@interface WKDLayoutNode : NSObject
@property (nonatomic, copy) NSString *nodeId;
@property (nonatomic) NSSize size;
@property (nonatomic) NSInteger layer;
@property (nonatomic) double order;
@property (nonatomic, strong) NSMutableArray<WKDLayoutNode *> *successors;
@property (nonatomic, strong) NSMutableArray<WKDLayoutNode *> *predecessors;
@end

@implementation WKDLayoutNode

- (instancetype)init
{
	if ((self = [super init])) {
		_successors = [NSMutableArray array];
		_predecessors = [NSMutableArray array];
	}
	return self;
}

@end

@implementation WKDLayout
{
	NSMutableArray<WKDLayoutNode *> *_nodes;
	NSMutableDictionary<NSString *, WKDLayoutNode *> *_byId;
	NSMutableArray<NSArray<NSString *> *> *_edges;
	NSMutableDictionary<NSString *, NSNumber *> *_layers;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_nodes = [NSMutableArray array];
		_byId = [NSMutableDictionary dictionary];
		_edges = [NSMutableArray array];
		_layerSpacing = 60;
		_nodeSpacing = 40;
		_sweeps = 12;
	}
	return self;
}

- (void)addNode:(NSString *)nodeId size:(NSSize)size
{
	if ([_byId objectForKey:nodeId] != nil) {
		return;
	}
	WKDLayoutNode *node = [[WKDLayoutNode alloc] init];
	node.nodeId = nodeId;
	node.size = size;
	[_nodes addObject:node];
	[_byId setObject:node forKey:nodeId];
}

- (void)addEdgeFrom:(NSString *)sourceId to:(NSString *)targetId
{
	if (![sourceId isEqualToString:targetId]) {
		[_edges addObject:@[ sourceId, targetId ]];
	}
}

- (NSInteger)layerOf:(NSString *)nodeId
{
	NSNumber *layer = [_layers objectForKey:nodeId];
	return layer != nil ? [layer integerValue] : -1;
}

#pragma mark Phases

/* The edges, those closing a cycle reversed: a depth-first walk from the
 * nodes nothing leads to (else from the first), in the order added. */
- (NSArray *)acyclicEdges
{
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	NSMutableSet *hasIncoming = [NSMutableSet set];
	for (NSArray *edge in _edges) {
		if ([_byId objectForKey:edge[0]] == nil || [_byId objectForKey:edge[1]] == nil) {
			continue;
		}
		NSMutableArray *list = [out objectForKey:edge[0]];
		if (list == nil) {
			list = [NSMutableArray array];
			[out setObject:list forKey:edge[0]];
		}
		[list addObject:edge[1]];
		[hasIncoming addObject:edge[1]];
	}
	NSMutableArray *starts = [NSMutableArray array];
	for (WKDLayoutNode *node in _nodes) {
		if (![hasIncoming containsObject:node.nodeId]) {
			[starts addObject:node.nodeId];
		}
	}
	for (WKDLayoutNode *node in _nodes) {
		[starts addObject:node.nodeId];
	}
	NSMutableSet *done = [NSMutableSet set], *onPath = [NSMutableSet set];
	NSMutableArray *result = [NSMutableArray array];
	__block void (^visit)(NSString *);
	__weak __block void (^weakVisit)(NSString *);
	weakVisit = visit = ^(NSString *nodeId) {
		[onPath addObject:nodeId];
		for (NSString *next in [out objectForKey:nodeId]) {
			if ([onPath containsObject:next]) {
				[result addObject:@[ next, nodeId ]];
			} else {
				[result addObject:@[ nodeId, next ]];
				if (![done containsObject:next]) {
					weakVisit(next);
				}
			}
		}
		[onPath removeObject:nodeId];
		[done addObject:nodeId];
	};
	for (NSString *start in starts) {
		if (![done containsObject:start]) {
			visit(start);
		}
	}
	return result;
}

/* Each node's layer: the longest path to it from a node nothing leads to. */
- (void)assignLayers:(NSArray *)edges
{
	NSMutableDictionary *incoming = [NSMutableDictionary dictionary];
	for (WKDLayoutNode *node in _nodes) {
		[incoming setObject:@0 forKey:node.nodeId];
		node.layer = 0;
	}
	for (NSArray *edge in edges) {
		[incoming setObject:@([[incoming objectForKey:edge[1]] integerValue] + 1) forKey:edge[1]];
		WKDLayoutNode *source = [_byId objectForKey:edge[0]], *target = [_byId objectForKey:edge[1]];
		[source.successors addObject:target];
		[target.predecessors addObject:source];
	}
	NSMutableArray *ready = [NSMutableArray array];
	for (WKDLayoutNode *node in _nodes) {
		if ([[incoming objectForKey:node.nodeId] integerValue] == 0) {
			[ready addObject:node];
		}
	}
	while ([ready count] > 0) {
		WKDLayoutNode *node = [ready objectAtIndex:0];
		[ready removeObjectAtIndex:0];
		for (WKDLayoutNode *next in node.successors) {
			next.layer = MAX(next.layer, node.layer + 1);
			NSInteger left = [[incoming objectForKey:next.nodeId] integerValue] - 1;
			[incoming setObject:@(left) forKey:next.nodeId];
			if (left == 0) {
				[ready addObject:next];
			}
		}
	}
}

/* An edge across several layers through a placeholder in each between. */
- (NSArray<WKDLayoutNode *> *)addPlaceholders
{
	NSMutableArray *all = [NSMutableArray arrayWithArray:_nodes];
	NSInteger count = 0;
	for (WKDLayoutNode *node in [_nodes copy]) {
		for (WKDLayoutNode *next in [node.successors copy]) {
			if (next.layer - node.layer <= 1) {
				continue;
			}
			[node.successors removeObject:next];
			[next.predecessors removeObject:node];
			WKDLayoutNode *previous = node;
			for (NSInteger layer = node.layer + 1; layer < next.layer; layer++) {
				WKDLayoutNode *placeholder = [[WKDLayoutNode alloc] init];
				placeholder.nodeId = [NSString stringWithFormat:@"\x01%ld", (long)count++];
				placeholder.size = NSMakeSize(0, 10);
				placeholder.layer = layer;
				[previous.successors addObject:placeholder];
				[placeholder.predecessors addObject:previous];
				[all addObject:placeholder];
				previous = placeholder;
			}
			[previous.successors addObject:next];
			[next.predecessors addObject:previous];
		}
	}
	return all;
}

- (NSMutableArray<NSMutableArray<WKDLayoutNode *> *> *)layersOf:(NSArray<WKDLayoutNode *> *)all
{
	NSMutableArray *layers = [NSMutableArray array];
	for (WKDLayoutNode *node in all) {
		while ((NSInteger)[layers count] <= node.layer) {
			[layers addObject:[NSMutableArray array]];
		}
		WKDLayoutNode *last = [[layers objectAtIndex:node.layer] lastObject];
		node.order = last != nil ? last.order + 1 : 0;
		[[layers objectAtIndex:node.layer] addObject:node];
	}
	return layers;
}

static NSInteger
WKDCrossings(NSArray<NSArray<WKDLayoutNode *> *> *layers)
{
	NSInteger crossings = 0;
	for (NSArray<WKDLayoutNode *> *layer in layers) {
		NSMutableArray *ends = [NSMutableArray array];
		for (WKDLayoutNode *node in layer) {
			for (WKDLayoutNode *next in node.successors) {
				[ends addObject:@[ @(node.order), @(next.order) ]];
			}
		}
		for (NSUInteger i = 0; i < [ends count]; i++) {
			for (NSUInteger j = i + 1; j < [ends count]; j++) {
				double a0 = [ends[i][0] doubleValue], a1 = [ends[i][1] doubleValue];
				double b0 = [ends[j][0] doubleValue], b1 = [ends[j][1] doubleValue];
				if ((a0 - b0) * (a1 - b1) < 0) {
					crossings++;
				}
			}
		}
	}
	return crossings;
}

/* Each layer sorted by its nodes' neighbours' average order, sweeping
 * forward and back; the best ordering seen is kept. */
- (void)orderLayers:(NSMutableArray<NSMutableArray<WKDLayoutNode *> *> *)layers
{
	NSInteger best = WKDCrossings(layers);
	NSMutableDictionary *bestOrder = [NSMutableDictionary dictionary];
	void (^remember)(void) = ^{
		for (NSArray *layer in layers) {
			for (WKDLayoutNode *node in layer) {
				[bestOrder setObject:@(node.order) forKey:node.nodeId];
			}
		}
	};
	remember();
	for (NSInteger sweep = 0; sweep < _sweeps && best > 0; sweep++) {
		BOOL forward = sweep % 2 == 0;
		NSInteger count = (NSInteger)[layers count];
		for (NSInteger step = 1; step < count; step++) {
			NSInteger index = forward ? step : count - 1 - step;
			NSMutableArray<WKDLayoutNode *> *layer = [layers objectAtIndex:index];
			NSMutableDictionary *centre = [NSMutableDictionary dictionary];
			for (WKDLayoutNode *node in layer) {
				NSArray *neighbours = forward ? node.predecessors : node.successors;
				double sum = 0;
				for (WKDLayoutNode *neighbour in neighbours) {
					sum += neighbour.order;
				}
				[centre setObject:@([neighbours count] > 0 ? sum / [neighbours count] : node.order) forKey:node.nodeId];
			}
			[layer sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(WKDLayoutNode *a, WKDLayoutNode *b) {
				return [[centre objectForKey:a.nodeId] compare:[centre objectForKey:b.nodeId]];
			}];
			for (NSUInteger i = 0; i < [layer count]; i++) {
				[layer objectAtIndex:i].order = i;
			}
		}
		NSInteger crossings = WKDCrossings(layers);
		if (crossings < best) {
			best = crossings;
			remember();
		}
	}
	for (NSMutableArray<WKDLayoutNode *> *layer in layers) {
		for (WKDLayoutNode *node in layer) {
			node.order = [[bestOrder objectForKey:node.nodeId] doubleValue];
		}
		[layer sortUsingComparator:^NSComparisonResult(WKDLayoutNode *a, WKDLayoutNode *b) {
			return a.order < b.order ? NSOrderedAscending : a.order > b.order ? NSOrderedDescending : NSOrderedSame;
		}];
	}
}

- (NSDictionary<NSString *, NSValue *> *)layout
{
	for (WKDLayoutNode *node in _nodes) {
		[node.successors removeAllObjects];
		[node.predecessors removeAllObjects];
	}
	[self assignLayers:[self acyclicEdges]];
	NSArray *all = [self addPlaceholders];
	NSMutableArray<NSMutableArray<WKDLayoutNode *> *> *layers = [self layersOf:all];
	[self orderLayers:layers];

	/* Columns as wide as their widest node; each column's nodes stacked
	 * and centred on the tallest column's middle. */
	double x = 0, tallest = 0;
	NSMutableArray *columnX = [NSMutableArray array], *columnWidth = [NSMutableArray array];
	NSMutableArray *columnHeight = [NSMutableArray array];
	for (NSArray<WKDLayoutNode *> *layer in layers) {
		double width = 0, height = 0;
		for (WKDLayoutNode *node in layer) {
			width = MAX(width, node.size.width);
			height += node.size.height;
		}
		height += _nodeSpacing * MAX(0, (double)[layer count] - 1);
		[columnX addObject:@(x)];
		[columnWidth addObject:@(width)];
		[columnHeight addObject:@(height)];
		tallest = MAX(tallest, height);
		x += width + _layerSpacing;
	}
	NSMutableDictionary *origins = [NSMutableDictionary dictionary];
	_layers = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [layers count]; i++) {
		double y = (tallest - [columnHeight[i] doubleValue]) / 2;
		for (WKDLayoutNode *node in [layers objectAtIndex:i]) {
			if (![node.nodeId hasPrefix:@"\x01"]) {
				double left = [columnX[i] doubleValue] + ([columnWidth[i] doubleValue] - node.size.width) / 2;
				[origins setObject:[NSValue valueWithPoint:NSMakePoint(left, y)] forKey:node.nodeId];
				[_layers setObject:@(node.layer) forKey:node.nodeId];
			}
			y += node.size.height + _nodeSpacing;
		}
	}
	_size = NSMakeSize(MAX(0, x - _layerSpacing), tallest);
	return origins;
}

@end

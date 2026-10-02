#import "WKDLayout.h"

/* A node of the layered graph: one of ours, or a placeholder on a long edge. */
@interface WKDLayoutNode : NSObject
@property (nonatomic, copy) NSString *nodeId;
@property (nonatomic) NSSize size;
@property (nonatomic) NSInteger layer;
@property (nonatomic) double order;
/* Its vertical centre, as the layers are placed. */
@property (nonatomic) double centre;
@property (nonatomic, strong) NSMutableArray<WKDLayoutNode *> *successors;
@property (nonatomic, strong) NSMutableArray<WKDLayoutNode *> *predecessors;
/* The predecessors whose edge to it leaves from their bottom. */
@property (nonatomic, strong) NSHashTable<WKDLayoutNode *> *lowered;
/* The predecessors joined to it by an edge reversed to break a cycle: a
 * loop going back, which does not pull it into line. */
@property (nonatomic, strong) NSHashTable<WKDLayoutNode *> *looped;
@end

@implementation WKDLayoutNode

- (instancetype)init
{
	if ((self = [super init])) {
		_successors = [NSMutableArray array];
		_predecessors = [NSMutableArray array];
		_lowered = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
		_looped = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	}
	return self;
}

@end

@implementation WKDLayout
{
	NSMutableArray<WKDLayoutNode *> *_nodes;
	NSMutableDictionary<NSString *, WKDLayoutNode *> *_byId;
	NSMutableArray<NSArray<NSString *> *> *_edges;
	NSMutableSet<NSString *> *_belowEdges;
	NSMutableDictionary<NSString *, NSNumber *> *_layers;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_nodes = [NSMutableArray array];
		_byId = [NSMutableDictionary dictionary];
		_edges = [NSMutableArray array];
		_belowEdges = [NSMutableSet set];
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
	[self addEdgeFrom:sourceId to:targetId below:NO];
}

- (void)addEdgeFrom:(NSString *)sourceId to:(NSString *)targetId below:(BOOL)below
{
	if (![sourceId isEqualToString:targetId]) {
		[_edges addObject:@[ sourceId, targetId ]];
		if (below) {
			[_belowEdges addObject:[NSString stringWithFormat:@"%@\x02%@", sourceId, targetId]];
		}
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
				/* Reversed, and marked so: a loop going back. */
				[result addObject:@[ next, nodeId, @YES ]];
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
		if ([_belowEdges containsObject:[NSString stringWithFormat:@"%@\x02%@", edge[0], edge[1]]]) {
			[target.lowered addObject:source];
		}
		if ([edge count] > 2) {
			[target.looped addObject:source];
		}
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
			BOOL lowered = [next.lowered containsObject:node], looped = [next.looped containsObject:node];
			[node.successors removeObject:next];
			[next.predecessors removeObject:node];
			[next.lowered removeObject:node];
			[next.looped removeObject:node];
			WKDLayoutNode *previous = node;
			for (NSInteger layer = node.layer + 1; layer < next.layer; layer++) {
				WKDLayoutNode *placeholder = [[WKDLayoutNode alloc] init];
				placeholder.nodeId = [NSString stringWithFormat:@"\x01%ld", (long)count++];
				placeholder.size = NSMakeSize(0, 10);
				placeholder.layer = layer;
				[previous.successors addObject:placeholder];
				[placeholder.predecessors addObject:previous];
				if (lowered && previous == node) {
					[placeholder.lowered addObject:node];
				}
				if (looped) {
					[placeholder.looped addObject:previous];
				}
				[all addObject:placeholder];
				previous = placeholder;
			}
			[previous.successors addObject:next];
			[next.predecessors addObject:previous];
			if (looped) {
				[next.looped addObject:previous];
			}
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
	/* Sweep even when nothing crosses: the order nodes were added in is
	 * not yet one that follows their neighbours (a boundary event's
	 * successor below the others). */
	for (NSInteger sweep = 0; sweep < _sweeps && (best > 0 || sweep < 2); sweep++) {
		BOOL forward = sweep % 2 == 0;
		NSInteger count = (NSInteger)[layers count];
		for (NSInteger step = 1; step < count; step++) {
			NSInteger index = forward ? step : count - 1 - step;
			NSMutableArray<WKDLayoutNode *> *layer = [layers objectAtIndex:index];
			NSMutableDictionary *centre = [NSMutableDictionary dictionary];
			for (WKDLayoutNode *node in layer) {
				/* An edge out of a node's bottom puts what it leads to after
				 * the node's other successors; going back, it does not pull
				 * the node. */
				NSMutableArray *neighbours = [NSMutableArray array];
				double sum = 0;
				for (WKDLayoutNode *neighbour in forward ? node.predecessors : node.successors) {
					BOOL lowered = forward ? [node.lowered containsObject:neighbour] : [neighbour.lowered containsObject:node];
					if (!forward && lowered) {
						continue;
					}
					[neighbours addObject:neighbour];
					sum += neighbour.order + (lowered ? 0.5 : 0);
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
		if (crossings <= best) {
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

#pragma mark Placing the layers

/* The median of the neighbours' centres, or nil when there are none: of
 * two, their middle, so that a gateway sits between its branches. */
static NSNumber *
WKDMedianCentre(NSArray<NSNumber *> *unsorted)
{
	if ([unsorted count] == 0) {
		return nil;
	}
	NSArray *centres = [unsorted sortedArrayUsingSelector:@selector(compare:)];
	NSUInteger n = [centres count];
	double median = n % 2 == 1 ? [centres[n / 2] doubleValue]
		: ([centres[n / 2 - 1] doubleValue] + [centres[n / 2] doubleValue]) / 2;
	return @(median);
}

/* The layer moved as near as it can be to where each node wants to be,
 * keeping its order and the spacing between its nodes: each node's centre
 * less the room the nodes above it need is then a sequence that may not
 * fall, and the nearest such sequence, in least squares, is found by
 * pooling adjacent values that would (isotonic regression). */
- (void)place:(NSArray<WKDLayoutNode *> *)layer towards:(NSArray<NSNumber *> *)wanted
{
	NSUInteger n = [layer count];
	if (n == 0) {
		return;
	}
	double offsets[n], targets[n], weights[n];
	double offset = 0;
	for (NSUInteger k = 0; k < n; k++) {
		WKDLayoutNode *node = [layer objectAtIndex:k];
		if (k > 0) {
			WKDLayoutNode *above = [layer objectAtIndex:k - 1];
			offset += above.size.height / 2 + _nodeSpacing + node.size.height / 2;
		}
		offsets[k] = offset;
		targets[k] = [wanted[k] doubleValue] - offset;
		/* A long edge's placeholders hold it straight; a node with many
		 * flows matters more than one with few. */
		weights[k] = [node.nodeId hasPrefix:@"\x01"] ? 2.0
			: 1.0 + (double)([node.predecessors count] + [node.successors count]) / 4.0;
	}
	/* Blocks of pooled values: their mean, weight and extent. */
	double means[n], blockWeights[n];
	NSUInteger starts[n], blocks = 0;
	for (NSUInteger k = 0; k < n; k++) {
		means[blocks] = targets[k];
		blockWeights[blocks] = weights[k];
		starts[blocks] = k;
		blocks++;
		while (blocks > 1 && means[blocks - 2] > means[blocks - 1]) {
			double weight = blockWeights[blocks - 2] + blockWeights[blocks - 1];
			means[blocks - 2] = (means[blocks - 2] * blockWeights[blocks - 2]
			                     + means[blocks - 1] * blockWeights[blocks - 1]) / weight;
			blockWeights[blocks - 2] = weight;
			blocks--;
		}
	}
	for (NSUInteger b = 0; b < blocks; b++) {
		NSUInteger to = b + 1 < blocks ? starts[b + 1] : n;
		for (NSUInteger k = starts[b]; k < to; k++) {
			[[layer objectAtIndex:k] setCentre:means[b] + offsets[k]];
		}
	}
}

/* Each layer packed, then moved, sweep by sweep, towards its neighbours in
 * the layer before it and then in the layer after it: a node level with
 * the node it follows, a gateway between its branches, so that flows run
 * straight where they can. */
- (void)placeVertically:(NSArray<NSArray<WKDLayoutNode *> *> *)layers
{
	for (NSArray<WKDLayoutNode *> *layer in layers) {
		double y = 0;
		for (WKDLayoutNode *node in layer) {
			node.centre = y + node.size.height / 2;
			y += node.size.height + _nodeSpacing;
		}
	}
	NSUInteger count = [layers count];
	for (NSInteger sweep = 0; sweep < MAX((NSInteger)4, _sweeps / 2); sweep++) {
		for (NSUInteger pass = 0; pass < 2; pass++) {
			BOOL forward = pass == 0;
			for (NSUInteger step = 1; step < count; step++) {
				NSArray<WKDLayoutNode *> *layer = [layers objectAtIndex:forward ? step : count - 1 - step];
				NSMutableArray *wanted = [NSMutableArray array];
				for (WKDLayoutNode *node in layer) {
					/* Below a node whose bottom an edge leaves: a row lower. */
					NSMutableArray *centres = [NSMutableArray array];
					double floor = -1.0e9;
					for (WKDLayoutNode *predecessor in node.predecessors) {
						if ([node.lowered containsObject:predecessor]) {
							floor = MAX(floor, predecessor.centre + predecessor.size.height / 2 + _nodeSpacing
							                   + node.size.height / 2);
						}
					}
					for (WKDLayoutNode *neighbour in forward ? node.predecessors : node.successors) {
						BOOL lowered = forward ? [node.lowered containsObject:neighbour]
							: [neighbour.lowered containsObject:node];
						BOOL looped = forward ? [node.looped containsObject:neighbour]
							: [neighbour.looped containsObject:node];
						if (looped) {
							continue;
						}
						if (!lowered) {
							[centres addObject:@(neighbour.centre)];
						} else if (forward) {
							[centres addObject:@(neighbour.centre + neighbour.size.height / 2 + _nodeSpacing
							                     + node.size.height / 2)];
						}
					}
					NSNumber *median = WKDMedianCentre(centres);
					/* Below what it hangs from, whatever follows it. */
					[wanted addObject:@(MAX(median != nil ? [median doubleValue] : node.centre, floor))];
				}
				[self place:layer towards:wanted];
			}
		}
	}
	/* Last, what hangs below an activity is put below where the activity
	 * ended up, and what follows only it goes with it; the rest stays. */
	NSHashTable *moved = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	for (NSUInteger index = 1; index < count; index++) {
		NSArray<WKDLayoutNode *> *layer = [layers objectAtIndex:index];
		NSMutableArray *wanted = [NSMutableArray array];
		NSMutableArray *before = [NSMutableArray array];
		for (WKDLayoutNode *node in layer) {
			double want = node.centre;
			NSArray *ahead = node.predecessors;
			for (WKDLayoutNode *predecessor in ahead) {
				if ([node.lowered containsObject:predecessor]) {
					want = MAX(want, predecessor.centre + predecessor.size.height / 2 + _nodeSpacing
					                 + node.size.height / 2);
				} else if ([ahead count] == 1 && [moved containsObject:predecessor]) {
					want = predecessor.centre;
				}
			}
			[wanted addObject:@(want)];
			[before addObject:@(node.centre)];
		}
		[self place:layer towards:wanted];
		for (NSUInteger k = 0; k < [layer count]; k++) {
			if (fabs([layer objectAtIndex:k].centre - [before[k] doubleValue]) > 0.5) {
				[moved addObject:[layer objectAtIndex:k]];
			}
		}
	}
}

- (NSDictionary<NSString *, NSValue *> *)layout
{
	for (WKDLayoutNode *node in _nodes) {
		[node.successors removeAllObjects];
		[node.predecessors removeAllObjects];
		[node.lowered removeAllObjects];
		[node.looped removeAllObjects];
	}
	[self assignLayers:[self acyclicEdges]];
	NSArray *all = [self addPlaceholders];
	NSMutableArray<NSMutableArray<WKDLayoutNode *> *> *layers = [self layersOf:all];
	[self orderLayers:layers];

	/* Columns as wide as their widest node. */
	double x = 0;
	NSMutableArray *columnX = [NSMutableArray array], *columnWidth = [NSMutableArray array];
	for (NSArray<WKDLayoutNode *> *layer in layers) {
		double width = 0;
		for (WKDLayoutNode *node in layer) {
			width = MAX(width, node.size.width);
		}
		[columnX addObject:@(x)];
		[columnWidth addObject:@(width)];
		x += width + _layerSpacing;
	}
	[self placeVertically:layers];
	double top = 0, bottom = 0;
	BOOL first = YES;
	for (NSArray<WKDLayoutNode *> *layer in layers) {
		for (WKDLayoutNode *node in layer) {
			double nodeTop = node.centre - node.size.height / 2, nodeBottom = node.centre + node.size.height / 2;
			top = first ? nodeTop : MIN(top, nodeTop);
			bottom = first ? nodeBottom : MAX(bottom, nodeBottom);
			first = NO;
		}
	}
	double tallest = bottom - top;
	NSMutableDictionary *origins = [NSMutableDictionary dictionary];
	_layers = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [layers count]; i++) {
		for (WKDLayoutNode *node in [layers objectAtIndex:i]) {
			if (![node.nodeId hasPrefix:@"\x01"]) {
				double left = [columnX[i] doubleValue] + ([columnWidth[i] doubleValue] - node.size.width) / 2;
				double y = round(node.centre - node.size.height / 2 - top);
				[origins setObject:[NSValue valueWithPoint:NSMakePoint(left, y)] forKey:node.nodeId];
				[_layers setObject:@(node.layer) forKey:node.nodeId];
			}
		}
	}
	_size = NSMakeSize(MAX(0, x - _layerSpacing), tallest);
	return origins;
}

@end

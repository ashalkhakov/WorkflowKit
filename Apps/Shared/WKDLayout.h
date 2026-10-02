#import <Foundation/Foundation.h>

/*
 * A layered (Sugiyama) layout of a directed graph, left to right, as a
 * process reads: adapted from CoreWF's. Cycles are broken by reversing the
 * edges that close them, nodes are put in layers by their longest path
 * from a start, an edge across several layers goes through placeholders,
 * the layers are ordered to cross as few edges as their neighbours'
 * average positions allow, and then they are spaced by the nodes' sizes.
 */
@interface WKDLayout : NSObject

/* Nodes in the order they are added: the order ties are broken in. */
- (void)addNode:(NSString *)nodeId size:(NSSize)size;
- (void)addEdgeFrom:(NSString *)sourceId to:(NSString *)targetId;
/* An edge out of the source's bottom -- a boundary event's flow, a
 * compensation handler's association: what it leads to goes below the
 * source's other successors, a row lower. */
- (void)addEdgeFrom:(NSString *)sourceId to:(NSString *)targetId below:(BOOL)below;

/* Between the layers, and between the nodes of a layer. */
@property (nonatomic) double layerSpacing;
@property (nonatomic) double nodeSpacing;
@property (nonatomic) NSInteger sweeps;

/* Each node's top-left corner, from (0, 0) at the layout's top left. */
- (NSDictionary<NSString *, NSValue *> *)layout;
/* The extent of the last layout. */
@property (nonatomic, readonly) NSSize size;
/* The layer each node was put in by the last layout. */
- (NSInteger)layerOf:(NSString *)nodeId;

@end

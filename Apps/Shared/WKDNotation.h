#import <Foundation/Foundation.h>

/* What BPMN's notation says of its elements' kinds and where their names
 * and bands go, whatever holds them. */

typedef NS_ENUM(NSInteger, WKDShapeKind) {
	WKDShapeEvent,
	WKDShapeActivity,
	WKDShapeGateway,
	/* An artifact with a shape of its own: an annotation, a data object. */
	WKDShapeArtifact,
};

/* Where a node's name goes when the diagram does not say: under an event
 * or a gateway; NSZeroRect for a node that holds its name inside. */
NSRect WKDNodeLabelRect(NSString *type, NSRect rect);
/* Where a flow's name goes when the diagram does not say: over the middle
 * of its middle segment. */
NSRect WKDFlowLabelRect(NSArray<NSValue *> *points);

/* How wide a pool's or a lane's band is: where its name is. */
extern const double WKDLaneBandWidth;
/* The band of a pool or a lane in the rectangle: down its left side, or
 * along its top when it is not drawn horizontally. */
NSRect WKDLaneBandRect(NSRect rect, BOOL horizontal);

/* The local names of the flow nodes of each kind. */
WKDShapeKind WKDKindOfType(NSString *type, BOOL *isFlowNode);
BOOL WKDIsContainerType(NSString *type);

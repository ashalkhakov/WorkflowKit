#import <Foundation/Foundation.h>

/*
 * What the canvas draws, read from the BPMN XML: the shapes of the flow
 * nodes of one process and the flows between them, and the pools and
 * lanes round them, where the document's diagram (BPMN DI) puts them. The XML is the document; a diagram is a
 * projection of it, read again after every change, and holds the elements
 * it was read from.
 */

typedef NS_ENUM(NSInteger, WKDShapeKind) {
	WKDShapeEvent,
	WKDShapeActivity,
	WKDShapeGateway,
	/* An artifact with a shape of its own: an annotation, a data object. */
	WKDShapeArtifact,
};

@interface WKDShape : NSObject
@property (nonatomic, readonly, strong) NSXMLElement *element;
@property (nonatomic, readonly, copy) NSString *elementId;
/* The BPMN element's local name: startEvent, userTask, exclusiveGateway. */
@property (nonatomic, readonly, copy) NSString *type;
@property (nonatomic, readonly) WKDShapeKind kind;
@property (nonatomic, readonly, copy) NSString *name;
/* Where the diagram puts it; NSZeroRect when it has no shape there. */
@property (nonatomic, readonly) NSRect bounds;
@property (nonatomic, readonly) BOOL hasBounds;
/* The subprocess it is in; nil at the process's top level. */
@property (nonatomic, readonly, weak) WKDShape *parent;
/* A boundary event's activity. */
@property (nonatomic, readonly, weak) WKDShape *host;
/* An event's definition's local name -- timerEventDefinition and the
 * rest -- or nil for a none event. */
@property (nonatomic, readonly, copy) NSString *eventDefinition;
/* A boundary event's cancelActivity, an event subprocess's start's
 * isInterrupting: NO draws its outline dashed. */
@property (nonatomic, readonly) BOOL interrupting;
/* A subprocess triggered by an event, drawn with a dotted outline. */
@property (nonatomic, readonly) BOOL eventSubProcess;
/* multiInstanceLoopCharacteristics: none, parallel or sequential. */
@property (nonatomic, readonly, copy) NSString *loop;
/* Where the diagram puts its name, outside it (BPMNLabel's bounds), as
 * events' and gateways' are; NSZeroRect where it says nothing. */
@property (nonatomic, readonly) NSRect labelBounds;
@end

@interface WKDConnection : NSObject
@property (nonatomic, readonly, strong) NSXMLElement *element;
@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, weak) WKDShape *source;
@property (nonatomic, readonly, weak) WKDShape *target;
/* NSValue points, in the diagram's coordinates; two at least. */
@property (nonatomic, readonly, copy) NSArray<NSValue *> *waypoints;
/* An association -- a compensation handler's, an annotation's -- rather
 * than a sequence flow: drawn dotted. */
@property (nonatomic, readonly) BOOL isAssociation;
/* Its source's default flow. */
@property (nonatomic, readonly) BOOL isDefault;
@property (nonatomic, readonly) BOOL hasCondition;
/* Where the diagram puts its name; NSZeroRect where it says nothing. */
@property (nonatomic, readonly) NSRect labelBounds;
@end

/*
 * A pool -- a collaboration's participant -- or a lane of one: a band
 * across the diagram with its name down its left side (or along its top,
 * for a pool drawn vertically). Lanes divide the process's pool by who
 * does what: each lists the flow nodes in it (flowNodeRef), and may be
 * divided into lanes of its own.
 */
@interface WKDLane : NSObject
@property (nonatomic, readonly, strong) NSXMLElement *element;
@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) NSRect bounds;
@property (nonatomic, readonly) BOOL hasBounds;
/* A participant rather than a lane. */
@property (nonatomic, readonly) BOOL isPool;
/* Its name down its left side; NO: along its top. */
@property (nonatomic, readonly) BOOL horizontal;
/* The lane it divides; nil for a pool and the lanes dividing it. */
@property (nonatomic, readonly, weak) WKDLane *parent;
/* 0 for a pool and the lanes dividing it, 1 for theirs, and so on. */
@property (nonatomic, readonly) NSUInteger depth;
/* The lanes dividing it, in order. */
@property (nonatomic, readonly, copy) NSArray<WKDLane *> *children;
/* Its flowNodeRefs: the ids of the flow nodes it lists. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *flowNodeIds;
@end

@interface WKDDiagram : NSObject

+ (instancetype)diagramOfDocument:(NSXMLDocument *)document;

/* The document's first executable process, else its first process. */
@property (nonatomic, readonly, strong) NSXMLElement *process;
/* The BPMNPlane that shows it; nil when the document has no diagram. */
@property (nonatomic, readonly, strong) NSXMLElement *plane;
/* Containers before what they contain, in document order. */
@property (nonatomic, readonly, copy) NSArray<WKDShape *> *shapes;
@property (nonatomic, readonly, copy) NSArray<WKDConnection *> *connections;

- (WKDShape *)shapeWithId:(NSString *)elementId;
- (WKDConnection *)connectionWithId:(NSString *)elementId;
/* The flows into and out of the shape. */
- (NSArray<WKDConnection *> *)connectionsOf:(WKDShape *)shape;
/* The shapes directly in the container (nil: the process), boundary events
 * aside. */
- (NSArray<WKDShape *> *)shapesIn:(WKDShape *)container;
/* The process's pool: the participant whose processRef it is; nil when
 * the document has no collaboration naming it. */
@property (nonatomic, readonly, strong) WKDLane *pool;
/* The process's lanes, each before those dividing it, in document order. */
@property (nonatomic, readonly, copy) NSArray<WKDLane *> *lanes;
/* The lanes no lane divides, top to bottom as the document orders them. */
@property (nonatomic, readonly, copy) NSArray<WKDLane *> *leafLanes;
/* The collaboration's other participants: drawn, not edited. */
@property (nonatomic, readonly, copy) NSArray<WKDLane *> *otherPools;
/* A lane or a pool, the process's or another's, by its id. */
- (WKDLane *)laneWithId:(NSString *)elementId;
/* The innermost lane listing the node; nil when none does. */
- (WKDLane *)laneOf:(WKDShape *)shape;
/* What a diagram lacks: a node without a shape. */
@property (nonatomic, readonly) BOOL needsLayout;
/* The union of every shape's bounds, pools' and lanes' too. */
@property (nonatomic, readonly) NSRect contentBounds;

@end

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

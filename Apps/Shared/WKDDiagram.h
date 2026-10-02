#import <Foundation/Foundation.h>

/*
 * What the canvas draws, read from the BPMN XML: the shapes of the flow
 * nodes of one process and the flows between them, where the document's
 * diagram (BPMN DI) puts them. The XML is the document; a diagram is a
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
/* What a diagram lacks: a node without a shape. */
@property (nonatomic, readonly) BOOL needsLayout;
/* The union of every shape's bounds. */
@property (nonatomic, readonly) NSRect contentBounds;

@end

/* Where a node's name goes when the diagram does not say: under an event
 * or a gateway; NSZeroRect for a node that holds its name inside. */
NSRect WKDNodeLabelRect(NSString *type, NSRect rect);
/* Where a flow's name goes when the diagram does not say: over the middle
 * of its middle segment. */
NSRect WKDFlowLabelRect(NSArray<NSValue *> *points);

/* The local names of the flow nodes of each kind. */
WKDShapeKind WKDKindOfType(NSString *type, BOOL *isFlowNode);
BOOL WKDIsContainerType(NSString *type);

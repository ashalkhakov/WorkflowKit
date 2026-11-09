#import <Foundation/Foundation.h>
#import "WKDNotation.h"

/*
 * The process a BPMN document holds, as objects: its flow nodes, the flows
 * between them, its pools and lanes, and where its diagram (BPMN DI) puts
 * each. The objects are the model. Editors change them, and undo puts them
 * back; the XML is what other tools read and write, read once into the
 * model when a document is opened (WKDBpmnReader) and written from it into
 * the same document, the carrier, where it changed (WKDBpmnWriter).
 * Everything the model does not hold -- documentation, extension elements,
 * other processes -- stays in the carrier as it was read.
 *
 * Each element keeps its id and its carrier element for as long as it is
 * in the model, and its links both ways: a node knows its flows, what it
 * contains, what is attached to it and the lane it is in, and they know it.
 * Outside the designer the model is read-only.
 */

@class WKDModel, WKDNode, WKDFlow, WKDLane;

@interface WKDModelElement : NSObject
@property (nonatomic, readonly, weak) WKDModel *model;
@property (nonatomic, readonly, copy) NSString *elementId;
/* The carrier's element it was read from or written to. */
@property (nonatomic, readonly, strong) NSXMLElement *element;
@property (nonatomic, readonly, copy) NSString *name;
@end

@interface WKDNode : WKDModelElement
/* The BPMN element's local name: startEvent, userTask, exclusiveGateway. */
@property (nonatomic, readonly, copy) NSString *type;
@property (nonatomic, readonly) WKDShapeKind kind;
/* Where the diagram puts it; NSZeroRect when it has no shape there. */
@property (nonatomic, readonly) NSRect bounds;
@property (nonatomic, readonly) BOOL hasBounds;
/* Where the diagram puts its name, outside it; NSZeroRect where it says
 * nothing. */
@property (nonatomic, readonly) NSRect labelBounds;
/* An event's definition's local name, or nil for a none event. */
@property (nonatomic, readonly, copy) NSString *eventDefinition;
@property (nonatomic, readonly) BOOL interrupting;
@property (nonatomic, readonly) BOOL eventSubProcess;
/* multiInstanceLoopCharacteristics: parallel or sequential; standard; nil. */
@property (nonatomic, readonly, copy) NSString *loop;
/* The subprocess it is in; nil at the process's top level. */
@property (nonatomic, readonly, weak) WKDNode *parent;
/* What it contains directly, boundary events aside, in document order. */
@property (nonatomic, readonly, copy) NSArray<WKDNode *> *children;
/* A boundary event's activity, and an activity's boundary events. */
@property (nonatomic, readonly, weak) WKDNode *host;
@property (nonatomic, readonly, copy) NSArray<WKDNode *> *attached;
/* The flows into and out of it, sequence flows and associations alike. */
@property (nonatomic, readonly, copy) NSArray<WKDFlow *> *incoming;
@property (nonatomic, readonly, copy) NSArray<WKDFlow *> *outgoing;
/* Its default flow: a gateway's or an activity's default attribute. */
@property (nonatomic, readonly, weak) WKDFlow *defaultFlow;
/* The innermost lane listing it; nil when none does. */
@property (nonatomic, readonly, weak) WKDLane *lane;
@end

@interface WKDFlow : WKDModelElement
@property (nonatomic, readonly, weak) WKDNode *source;
@property (nonatomic, readonly, weak) WKDNode *target;
/* An association rather than a sequence flow: drawn dotted. */
@property (nonatomic, readonly) BOOL isAssociation;
/* Its source's default flow. */
@property (nonatomic, readonly) BOOL isDefault;
@property (nonatomic, readonly) BOOL hasCondition;
/* NSValue points, in the diagram's coordinates, as the diagram gives them;
 * empty when it gives none. */
@property (nonatomic, readonly, copy) NSArray<NSValue *> *waypoints;
@property (nonatomic, readonly) NSRect labelBounds;
@end

@interface WKDLane : WKDModelElement
@property (nonatomic, readonly) NSRect bounds;
@property (nonatomic, readonly) BOOL hasBounds;
/* A participant rather than a lane. */
@property (nonatomic, readonly) BOOL isPool;
/* Its name down its left side; NO: along its top. */
@property (nonatomic, readonly) BOOL horizontal;
/* The lane it divides; nil for a pool and the lanes dividing it. */
@property (nonatomic, readonly, weak) WKDLane *parent;
@property (nonatomic, readonly) NSUInteger depth;
@property (nonatomic, readonly, copy) NSArray<WKDLane *> *children;
/* The nodes it lists (flowNodeRef), in its order; and their ids, those it
 * lists that are not nodes of the process included. */
@property (nonatomic, readonly, copy) NSArray<WKDNode *> *nodes;
@property (nonatomic, readonly, copy) NSArray<NSString *> *flowNodeIds;
@end

@interface WKDModel : NSObject

/* The document's process -- its first executable one, else its first --
 * read into a model; nil when it has none. The document is kept as the
 * carrier, and written to by -write. */
+ (instancetype)modelOfDocument:(NSXMLDocument *)document;

@property (nonatomic, readonly, strong) NSXMLDocument *document;
@property (nonatomic, readonly, strong) NSXMLElement *process;
/* The BPMNPlane that shows it; nil when the document has no diagram. */
@property (nonatomic, readonly, strong) NSXMLElement *plane;

/* Containers before what they contain, in document order. */
@property (nonatomic, readonly, copy) NSArray<WKDNode *> *nodes;
@property (nonatomic, readonly, copy) NSArray<WKDFlow *> *flows;
/* The process's top-level nodes, boundary events aside. */
@property (nonatomic, readonly, copy) NSArray<WKDNode *> *topNodes;
- (WKDNode *)nodeWithId:(NSString *)elementId;
- (WKDFlow *)flowWithId:(NSString *)elementId;
/* The flows into and out of the node. */
- (NSArray<WKDFlow *> *)flowsOf:(WKDNode *)node;
/* The nodes directly in the container (nil: the process), boundary events
 * aside. */
- (NSArray<WKDNode *> *)nodesIn:(WKDNode *)container;

/* The process's pool; nil when no collaboration names it. */
@property (nonatomic, readonly, strong) WKDLane *pool;
/* The process's lanes, each before those dividing it, in document order. */
@property (nonatomic, readonly, copy) NSArray<WKDLane *> *lanes;
@property (nonatomic, readonly, copy) NSArray<WKDLane *> *leafLanes;
/* The collaboration's other participants: drawn, not edited. */
@property (nonatomic, readonly, copy) NSArray<WKDLane *> *otherPools;
/* A lane or a pool, the process's or another's, by its id. */
- (WKDLane *)laneWithId:(NSString *)elementId;
/* The innermost lane listing the node; nil when none does. */
- (WKDLane *)laneOf:(WKDNode *)node;

/* A node without a shape. */
@property (nonatomic, readonly) BOOL needsLayout;
/* The union of every shape's bounds, pools' and lanes' too. */
@property (nonatomic, readonly) NSRect contentBounds;

/* What changed since the last write -- elements made, changed or deleted --
 * written into the carrier where it differs from what is there. An
 * unchanged model writes nothing. */
- (void)write;
@property (nonatomic, readonly) BOOL hasChanges;

@end

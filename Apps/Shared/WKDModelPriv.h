#import "WKDModel.h"
#import "WKDJournal.h"

/*
 * The model as the reader, the writer and the editors see it: values set
 * through here mark the element changed, for the writer; links are kept
 * both ways by the setters that make them.
 */

@interface WKDModelElement ()
@property (nonatomic, readwrite, weak) WKDModel *model;
@property (nonatomic, readwrite, copy) NSString *elementId;
@property (nonatomic, readwrite, strong) NSXMLElement *element;
@property (nonatomic, readwrite, copy) NSString *name;
/* The diagram element that shows it: a BPMNShape or a BPMNEdge; nil when
 * the diagram has none. */
@property (nonatomic, strong) NSXMLElement *diagramElement;
/* Where its carrier element and its diagram element were when it left the
 * model, for undo to put them back. */
@property (nonatomic, weak) NSXMLElement *carrierParent;
@property (nonatomic) NSUInteger carrierIndex;
@property (nonatomic, weak) NSXMLElement *diagramParent;
@property (nonatomic) NSUInteger diagramIndex;
/* Marked for the writer: its values are written at the next -write. */
- (void)changed;
/* Before its values or links change: recorded in the model's journal when
 * a step is being recorded, and marked for the writer. */
- (void)willChange;
/* Its values and links, for the journal; and put back. */
- (NSDictionary *)journalState;
- (void)restoreJournalState:(NSDictionary *)state;
@end

@interface WKDNode ()
@property (nonatomic, readwrite, copy) NSString *type;
@property (nonatomic, readwrite) WKDShapeKind kind;
@property (nonatomic, readwrite) NSRect bounds;
@property (nonatomic, readwrite) BOOL hasBounds;
@property (nonatomic, readwrite) NSRect labelBounds;
@property (nonatomic, readwrite, copy) NSString *eventDefinition;
@property (nonatomic, readwrite) BOOL interrupting;
@property (nonatomic, readwrite) BOOL eventSubProcess;
@property (nonatomic, readwrite, copy) NSString *loop;
@property (nonatomic, readwrite, weak) WKDNode *parent;
@property (nonatomic, readwrite, weak) WKDNode *host;
@property (nonatomic, readwrite, weak) WKDFlow *defaultFlow;
@property (nonatomic, readwrite, weak) WKDLane *lane;
@property (nonatomic, strong) NSMutableArray<WKDNode *> *childList;
@property (nonatomic, strong) NSMutableArray<WKDNode *> *attachedList;
@property (nonatomic, strong) NSMutableArray<WKDFlow *> *incomingList;
@property (nonatomic, strong) NSMutableArray<WKDFlow *> *outgoingList;
/* Its flows changed since the last write: its incoming and outgoing are
 * written even in a document that lists none. */
@property (nonatomic) BOOL flowsChanged;
@end

@interface WKDFlow ()
@property (nonatomic, readwrite, weak) WKDNode *source;
@property (nonatomic, readwrite, weak) WKDNode *target;
@property (nonatomic, readwrite) BOOL isAssociation;
@property (nonatomic, readwrite) BOOL hasCondition;
@property (nonatomic, readwrite, copy) NSArray<NSValue *> *waypoints;
@property (nonatomic, readwrite) NSRect labelBounds;
@end

@interface WKDLane ()
@property (nonatomic, readwrite) NSRect bounds;
@property (nonatomic, readwrite) BOOL hasBounds;
@property (nonatomic, readwrite) BOOL isPool;
@property (nonatomic, readwrite) BOOL horizontal;
@property (nonatomic, readwrite, weak) WKDLane *parent;
@property (nonatomic, readwrite) NSUInteger depth;
@property (nonatomic, readwrite, copy) NSArray<WKDLane *> *children;
@property (nonatomic, strong) NSMutableArray<WKDNode *> *nodeList;
/* What it lists that is not a node of the process, kept as read. */
@property (nonatomic, copy) NSArray<NSString *> *otherIds;
@end

@interface WKDModel ()
@property (nonatomic, readwrite, strong) NSXMLDocument *document;
@property (nonatomic, readwrite, strong) NSXMLElement *process;
@property (nonatomic, readwrite, strong) NSXMLElement *plane;
@property (nonatomic, readwrite, strong) WKDLane *pool;
@property (nonatomic, readwrite, copy) NSArray<WKDLane *> *lanes;
@property (nonatomic, readwrite, copy) NSArray<WKDLane *> *otherPools;
@property (nonatomic, strong) NSMutableArray<WKDNode *> *nodeList;
@property (nonatomic, strong) NSMutableArray<WKDFlow *> *flowList;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WKDNode *> *nodesById;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WKDFlow *> *flowsById;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WKDLane *> *lanesById;
/* Elements to write: changed or made since the last write, and deleted. */
@property (nonatomic, strong) NSHashTable<WKDModelElement *> *changedElements;
@property (nonatomic, strong) NSMutableArray<WKDModelElement *> *deletedElements;
/* While writing: the ids of what leaves the carrier now. References to
 * them go too; references to ids the model never knew stay. */
@property (nonatomic, strong) NSSet<NSString *> *leavingIds;

/* Every element marked changed: for the check that writing what the model
 * holds changes nothing in a carrier it was read from. */
- (void)markEverythingChanged;

/* The model's journal: an editor operation's steps for undo. */
@property (nonatomic, readonly, strong) WKDJournal *journal;
/* The model's lists, for the journal; and put back. */
- (NSDictionary *)journalState;
- (void)restoreJournalState:(NSDictionary *)state;
/* Whether the element is in the model now. */
- (BOOL)containsElement:(WKDModelElement *)element;
/* The XML elements the model's elements are read from and drawn by. */
/* Whether the node is a model element's carrier or diagram element. */
- (BOOL)carries:(NSXMLNode *)node;

/* Elements made and removed. A node of the type in the container (nil: the
 * process), with no carrier element until the writer makes it; a flow
 * between two nodes; an element removed with its links -- a node's flows
 * and boundary events go with it, as do what it contains. */
- (WKDNode *)makeNodeOfType:(NSString *)type elementId:(NSString *)elementId in:(WKDNode *)container;
- (WKDFlow *)makeFlowFrom:(WKDNode *)source to:(WKDNode *)target elementId:(NSString *)elementId
              association:(BOOL)association;
- (void)removeNode:(WKDNode *)node;
/* The element under another id, which no element has. */
- (void)renameElement:(WKDModelElement *)element to:(NSString *)elementId;
- (void)removeFlow:(WKDFlow *)flow;

/* Links, both ways. */
- (void)setSource:(WKDNode *)source ofFlow:(WKDFlow *)flow;
- (void)setTarget:(WKDNode *)target ofFlow:(WKDFlow *)flow;
- (void)setHost:(WKDNode *)host ofNode:(WKDNode *)node;
- (void)setDefaultFlow:(WKDFlow *)flow ofNode:(WKDNode *)node;
@end

/* WKDBpmnReader.m: the carrier read into the model. */
@interface WKDModel (WKDReading)
- (BOOL)readDocument:(NSXMLDocument *)document;
@end

@interface WKDModel (WKDReadingAgain)
- (void)readDocumentAgain:(NSXMLDocument *)document;
/* What the element's own XML says of its values read again, journalled:
 * after an edit of that XML alone. Its links stay, its default flow aside. */
- (void)readValuesAgain:(WKDModelElement *)element;
@end

/* WKDModelCheck.m: how the model differs from another, read afresh: nil
 * when they agree element for element -- ids, values and links. */
@interface WKDModel (WKDChecking)
- (NSString *)disagreementWith:(WKDModel *)other;
@end

/* WKDBpmnWriter.m: the model's changes written into the carrier. */
@interface WKDModel (WKDWriting)
/* The plane that shows the process, made when the document has none. */
- (NSXMLElement *)ensurePlane;
- (void)writeChanges;
/* Only the element's place in the diagram -- a shape's bounds, an edge's
 * waypoints, a label's bounds -- written now, the rest of it left to the
 * XML: for an operation that edits the rest of the XML itself. */
- (void)writeGeometryOf:(WKDModelElement *)element;
@end

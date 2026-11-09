#import "WKDModel.h"

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
/* Marked for the writer: its values are written at the next -write. */
- (void)changed;
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
@property (nonatomic, readwrite, weak) WKDSwimlane *lane;
@property (nonatomic, strong) NSMutableArray<WKDNode *> *childList;
@property (nonatomic, strong) NSMutableArray<WKDNode *> *attachedList;
@property (nonatomic, strong) NSMutableArray<WKDFlow *> *incomingList;
@property (nonatomic, strong) NSMutableArray<WKDFlow *> *outgoingList;
@end

@interface WKDFlow ()
@property (nonatomic, readwrite, weak) WKDNode *source;
@property (nonatomic, readwrite, weak) WKDNode *target;
@property (nonatomic, readwrite) BOOL isAssociation;
@property (nonatomic, readwrite) BOOL hasCondition;
@property (nonatomic, readwrite, copy) NSArray<NSValue *> *waypoints;
@property (nonatomic, readwrite) NSRect labelBounds;
@end

@interface WKDSwimlane ()
@property (nonatomic, readwrite) NSRect bounds;
@property (nonatomic, readwrite) BOOL hasBounds;
@property (nonatomic, readwrite) BOOL isPool;
@property (nonatomic, readwrite) BOOL horizontal;
@property (nonatomic, readwrite, weak) WKDSwimlane *parent;
@property (nonatomic, readwrite) NSUInteger depth;
@property (nonatomic, readwrite, copy) NSArray<WKDSwimlane *> *children;
@property (nonatomic, strong) NSMutableArray<WKDNode *> *nodeList;
/* What it lists that is not a node of the process, kept as read. */
@property (nonatomic, copy) NSArray<NSString *> *otherIds;
@end

@interface WKDModel ()
@property (nonatomic, readwrite, strong) NSXMLDocument *document;
@property (nonatomic, readwrite, strong) NSXMLElement *process;
@property (nonatomic, readwrite, strong) NSXMLElement *plane;
@property (nonatomic, readwrite, strong) WKDSwimlane *pool;
@property (nonatomic, readwrite, copy) NSArray<WKDSwimlane *> *lanes;
@property (nonatomic, readwrite, copy) NSArray<WKDSwimlane *> *otherPools;
@property (nonatomic, strong) NSMutableArray<WKDNode *> *nodeList;
@property (nonatomic, strong) NSMutableArray<WKDFlow *> *flowList;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WKDNode *> *nodesById;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WKDFlow *> *flowsById;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WKDSwimlane *> *lanesById;
/* Elements to write: changed or made since the last write, and deleted. */
@property (nonatomic, strong) NSHashTable<WKDModelElement *> *changedElements;
@property (nonatomic, strong) NSMutableArray<WKDModelElement *> *deletedElements;

/* Every element marked changed: for the check that writing what the model
 * holds changes nothing in a carrier it was read from. */
- (void)markEverythingChanged;

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
@end

/* WKDModelCheck.m: how the model differs from another, read afresh: nil
 * when they agree element for element -- ids, values and links. */
@interface WKDModel (WKDChecking)
- (NSString *)disagreementWith:(WKDModel *)other;
@end

/* WKDBpmnWriter.m: the model's changes written into the carrier. */
@interface WKDModel (WKDWriting)
- (void)writeChanges;
@end

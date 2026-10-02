#import <Foundation/Foundation.h>
#import "WKDDiagram.h"

/* A type a node can have: its BPMN name, its event's definition (nil for
 * none), and what to call it. */
@interface WKDNodeType : NSObject
@property (nonatomic, readonly, copy) NSString *type;
@property (nonatomic, readonly, copy) NSString *eventDefinition;
@property (nonatomic, readonly, copy) NSString *title;
+ (instancetype)type:(NSString *)type eventDefinition:(NSString *)eventDefinition title:(NSString *)title;
@end

/*
 * Every change to a BPMN document goes through here: elements and their
 * references -- a flow's ends, the nodes' incoming and outgoing, a
 * gateway's default -- and the diagram that shows them change together.
 * Each change is one step on the undo manager, which keeps the document
 * as it was before: restoring a snapshot is right whatever the change was,
 * and a process's XML is small.
 */
@interface WKDEditor : NSObject

/* A new executable process with a start event, and its diagram. */
+ (NSXMLDocument *)newProcessDocument;

- (instancetype)initWithDocument:(NSXMLDocument *)document undoManager:(NSUndoManager *)undoManager;

/* The document as it is now: undo and redo replace it. */
@property (nonatomic, readonly, strong) NSXMLDocument *document;
/* Read again after every change. */
@property (nonatomic, readonly, strong) WKDDiagram *diagram;
/* Called after every change, undo and redo included. */
@property (nonatomic, copy) void (^changed)(void);

/* Shapes for the nodes that have none, laid out with the rest left as
 * they are; nothing when every node has one. Not undoable: for opening. */
- (void)completeDiagram;
/* Every node laid out afresh, left to right, flows routed between. */
- (void)arrange;

/* A node of the type -- userTask, exclusiveGateway, endEvent -- centred
 * at the point, in the subprocess there; a boundary event on the activity
 * there. The event definition (timerEventDefinition, ...) or nil. Its id,
 * or nil with the reason. */
- (NSString *)insertNodeOfType:(NSString *)type
               eventDefinition:(NSString *)eventDefinition
                            at:(NSPoint)point
                         error:(NSString **)reason;
/* A sequence flow; its id, or nil with why it cannot be. */
- (NSString *)connect:(NSString *)sourceId to:(NSString *)targetId error:(NSString **)reason;
/* Shapes moved by the offset, with what they contain and what is attached
 * to them; a boundary event alone slides along its activity's edge. */
- (void)moveElements:(NSArray<NSString *> *)elementIds by:(NSSize)offset;
- (void)resizeElement:(NSString *)elementId to:(NSRect)bounds;
/* Nodes with what they contain and the flows that touch them, and flows. */
- (void)deleteElements:(NSArray<NSString *> *)elementIds;

/* A change to one element -- the process, a node, a flow -- as one undo
 * step named for it: the block gets the element and the document. NO when
 * there is no element of that id. */
- (BOOL)edit:(NSString *)elementId
      action:(NSString *)action
        with:(void (^)(NSXMLElement *element, NSXMLDocument *document))edit;
/* A new id, and every reference to the old one with it: flows' ends,
 * boundary events' activities, defaults, incoming and outgoing, the
 * diagram. NO, with why, for an id that is taken or not an XML name. */
- (BOOL)renameElement:(NSString *)elementId to:(NSString *)newId error:(NSString **)reason;
/* An element of the document anywhere, by id. */
- (NSXMLElement *)elementWithId:(NSString *)elementId;
/* A top-level definition -- bpmn:message, signal, error, escalation --
 * whose attribute (name, errorCode, escalationCode) has the value: its id,
 * made with the value as its name too when there is none. For an edit. */
- (NSString *)definitionOf:(NSString *)local key:(NSString *)key value:(NSString *)value;

/* The flow's route between two shapes, as a modeller draws it: straight
 * where they face each other, with right-angle bends where they do not. */
+ (NSArray<NSValue *> *)routeFrom:(NSRect)source to:(NSRect)target fromBoundary:(BOOL)fromBoundary;
/* From a gateway, a branch leaves by the corner on the target's side. */
+ (NSArray<NSValue *> *)routeFrom:(NSRect)source to:(NSRect)target fromBoundary:(BOOL)fromBoundary
                      fromGateway:(BOOL)fromGateway;
/* Into an activity's side, a flow goes straight across wherever the two
 * face each other; a gateway or an event it enters at its corner. */
+ (NSArray<NSValue *> *)routeFrom:(NSRect)source to:(NSRect)target fromBoundary:(BOOL)fromBoundary
                      fromGateway:(BOOL)fromGateway toActivity:(BOOL)toActivity;
/* The default size of a node of the type. */
+ (NSSize)sizeOfType:(NSString *)type;

@end

/* What the canvas changes directly (WKDEditor+Canvas.m). */
@interface WKDEditor (WKDCanvas)

/* Its name, as one step: a node's or flow's name attribute, an
 * annotation's text; nil or empty for none. */
- (void)setName:(NSString *)name of:(NSString *)elementId;
/* The flow's source (atSource) or target is another node now, by the
 * rules a new flow keeps to; its route is drawn afresh. NO, with why, when
 * it cannot be. */
- (BOOL)reconnect:(NSString *)flowId atSource:(BOOL)atSource to:(NSString *)nodeId error:(NSString **)reason;
/* One of a flow's bends -- a waypoint other than its ends -- at the point. */
- (void)moveBend:(NSUInteger)index of:(NSString *)flowId to:(NSPoint)point;
/* The name of an event, a gateway or a flow moved by the offset, from where
 * the diagram puts it or, when it says nothing, where it is drawn. */
- (void)moveLabelOf:(NSString *)elementId by:(NSSize)offset;
/* A flow's route after its ends moved by these offsets, its bends kept:
 * each end's point goes with its shape, and the bend next to it slides
 * along to keep the segment between them straight across or up and
 * down. nil when the route cannot keep them -- it has none, or the
 * bend would land inside the shape -- and the router should draw it. */
+ (NSArray<NSValue *> *)keptRoute:(NSArray<NSValue *> *)points source:(NSRect)source target:(NSRect)target
                      sourceMoved:(NSSize)sourceMoved targetMoved:(NSSize)targetMoved;

@end

/* Copying and pasting (WKDEditor+Clipboard.m). */
@interface WKDEditor (WKDClipboard)

/* The elements as a BPMN document of their own, for the clipboard: the
 * nodes, with what they contain and what is attached to them, the flows
 * between them, their diagram, and the messages, signals, errors and
 * escalations they name. nil when none of them can be copied. */
- (NSXMLDocument *)fragmentOfElements:(NSArray<NSString *> *)elementIds;
/* What -fragmentOfElements: made -- from this document or another -- added to
 * the process under fresh ids, its diagram moved by the offset, as one
 * step. The ids of the nodes and flows added at the top, or nil with why
 * there is nothing to paste. */
- (NSArray<NSString *> *)paste:(NSXMLDocument *)copy offset:(NSSize)offset error:(NSString **)reason;

@end

/* A node's type changed in place (WKDEditor+Types.m). */
@interface WKDEditor (WKDTypes)

/* What a node can be changed into in place: the other tasks for a task,
 * the other gateways for a gateway, and for an event the other events its
 * flows allow, each with the definitions BPMN gives it. */
- (NSArray<WKDNodeType *> *)typesFor:(NSString *)elementId;
/* The node, of the type now, as one step: what only its old type had --
 * a form for a user task, a topic for a service task, a gateway's default
 * where the new one has none -- goes, the rest stays. NO, with why, for a
 * type -typesFor: does not offer. */
- (BOOL)changeType:(NSString *)elementId to:(WKDNodeType *)type error:(NSString **)reason;

@end

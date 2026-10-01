#import <Foundation/Foundation.h>
#import "WKDDiagram.h"

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

/* The flow's route between two shapes, as a modeller draws it: straight
 * where they face each other, with right-angle bends where they do not. */
+ (NSArray<NSValue *> *)routeFrom:(NSRect)source to:(NSRect)target fromBoundary:(BOOL)fromBoundary;
/* From a gateway, a branch leaves by the corner on the target's side. */
+ (NSArray<NSValue *> *)routeFrom:(NSRect)source to:(NSRect)target fromBoundary:(BOOL)fromBoundary
                      fromGateway:(BOOL)fromGateway;
/* The default size of a node of the type. */
+ (NSSize)sizeOfType:(NSString *)type;

@end

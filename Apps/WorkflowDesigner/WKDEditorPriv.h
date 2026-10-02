#import "WKDEditor.h"

/*
 * What WKDEditor's own files share. The editor is split by what it
 * changes -- WKDEditor.m the nodes, flows and layout, WKDEditor+Canvas.m
 * names, labels, bends and reconnections, WKDEditor+Clipboard.m copying
 * and pasting, WKDEditor+Types.m a node's type -- and every change in any
 * of them is one -change:with: step.
 */
@interface WKDEditor ()
@property (nonatomic, readwrite, strong) NSXMLDocument *document;
@property (nonatomic, readwrite, strong) WKDDiagram *diagram;

/* One undoable step named for the change: the document as it was is what
 * undo restores, and the diagram is read again after it. */
- (void)change:(NSString *)name with:(void (^)(void))change;
/* Every id in the document. */
- (NSMutableSet *)usedIds;
/* An id of the prefix no element has. */
- (NSString *)freshId:(NSString *)prefix;
/* The plane that shows the process, made when the document has no diagram. */
- (NSXMLElement *)plane;
/* The BPMNShape or BPMNEdge showing the element, made when asked for. */
- (NSXMLElement *)diagramElement:(NSString *)local of:(NSString *)elementId create:(BOOL)create;
- (void)setBounds:(NSRect)bounds of:(NSString *)elementId;
- (void)setWaypoints:(NSArray<NSValue *> *)points of:(NSString *)flowId;
/* The BPMNLabel's bounds of the element's shape or edge. */
- (void)setLabelBounds:(NSRect)bounds of:(NSString *)elementId;
/* The router's way for the flow, round the shapes in the way. */
- (NSArray<NSValue *> *)routeFor:(WKDConnection *)connection;
- (void)reroute:(WKDConnection *)connection;
/* The shape, what it contains, and what is attached to any of them. */
- (void)collect:(WKDShape *)shape into:(NSMutableSet *)ids;
/* An incoming or outgoing reference to the flow in the node, where BPMN
 * orders them. */
- (void)addReference:(NSString *)local to:(NSString *)flowId in:(NSXMLElement *)node;
/* Why a sequence flow cannot join the two -- a flow other than `except`
 * joining them already is one reason -- or nil when it can. */
- (NSString *)refusalToConnect:(WKDShape *)source to:(WKDShape *)target except:(NSString *)flowId;
@end

/* The prefix of a new node's id: Event, Gateway, Activity. */
NSString *WKDIdPrefix(NSString *type);
/* A boundary event's centre on its activity's edge nearest the point. */
NSPoint WKDOnEdge(NSRect host, NSPoint point);

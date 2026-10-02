#import <AppKit/AppKit.h>

/*
 * BPMN's notation drawn with NSBezierPath, the same on both platforms: the
 * canvas draws the document with it and the palette its tools. In a
 * flipped view: y grows downwards, as in BPMN DI.
 */

/* What a node looks like, apart from where it is. */
@interface WKDLook : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *eventDefinition;
@property (nonatomic) BOOL interrupting;
@property (nonatomic) BOOL eventSubProcess;
@property (nonatomic, copy) NSString *loop;
@property (nonatomic, copy) NSString *name;
+ (instancetype)lookOfType:(NSString *)type eventDefinition:(NSString *)eventDefinition;
@end

/* The node in the rectangle; its name inside it, or under it for events
 * and gateways, unless names is NO. */
void WKDDrawNode(WKDLook *look, NSRect rect, BOOL names);
/* A sequence flow through the points, its arrowhead at the last; its name,
 * when given, where WKDFlowLabelRect puts it. */
void WKDDrawFlow(NSArray<NSValue *> *points, BOOL isDefault, BOOL conditionalFromActivity, NSString *name);
/* A name in a label's rectangle, as BPMN DI gives one: centred across it,
 * from its top, onto more lines than it is tall when the name needs them. */
void WKDDrawLabel(NSString *name, NSRect rect);
/* An association through the points: dotted, with an open arrowhead
 * when it is directed. */
void WKDDrawAssociation(NSArray<NSValue *> *points, BOOL directed);
/* A selection outline around the rectangle. */
void WKDDrawSelection(NSRect rect);
/* The distance from the point to the polyline. */
double WKDDistanceToPolyline(NSPoint point, NSArray<NSValue *> *points);

NSColor *WKDInkColor(void);
NSColor *WKDPaperColor(void);
NSColor *WKDSelectionColor(void);

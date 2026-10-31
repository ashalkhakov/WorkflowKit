#import <AppKit/AppKit.h>
#import <DiagramKit/DiagramKit.h>

/*
 * BPMN's notation drawn through a DiagramKit surface (DKSurface), the same
 * on every platform and for every use: the canvases draw the document with
 * it (their view, a print, a PDF or PNG export through DKAppKitSurface; an
 * SVG export through DKSVGSurface) and the palette its tools. In flipped
 * coordinates: y grows downwards, as in BPMN DI.
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
void WKDDrawNode(id<DKSurface> surface, WKDLook *look, NSRect rect, BOOL names);
/* A sequence flow through the points in the colour, its arrowhead at the
 * last; its name, when given, where WKDFlowLabelRect puts it. */
void WKDDrawFlow(id<DKSurface> surface, NSArray<NSValue *> *points, DKColor color, BOOL isDefault,
                 BOOL conditionalFromActivity, NSString *name);
/* A name in a label's rectangle, as BPMN DI gives one: centred across it,
 * from its top, onto more lines than it is tall when the name needs them. */
void WKDDrawLabel(id<DKSurface> surface, NSString *name, NSRect rect);
/* An association through the points in the colour: dotted, with an open
 * arrowhead when it is directed. */
void WKDDrawAssociation(id<DKSurface> surface, NSArray<NSValue *> *points, DKColor color, BOOL directed);
/* The outline of a node of the type in the rectangle: a circle for an
 * event, a diamond for a gateway, a rounded box for the rest -- for marks
 * laid over a node in its own shape. */
DKPath *WKDNodeOutline(NSString *type, NSRect rect);
/* A pool or a lane: its outline, and its band with its name in it, read
 * from the bottom up as BPMN's notation turns it. */
void WKDDrawLane(id<DKSurface> surface, NSRect rect, NSString *name, BOOL horizontal);
/* A selection outline around the rectangle. */
void WKDDrawSelection(id<DKSurface> surface, NSRect rect);
/* The distance from the point to the polyline. */
double WKDDistanceToPolyline(NSPoint point, NSArray<NSValue *> *points);

/* A DiagramKit canvas's drawing, between these: dark as its DKDrawingState
 * says, the appearance's colours; not (a light view, a print, an export),
 * black on white. Outside them the renderer draws in the appearance's
 * colours, as a view of its own does. */
void WKDBeginDrawing(BOOL dark);
void WKDEndDrawing(void);
/* The ink, the paper and the selection's colour, as the renderer draws
 * them now; and as AppKit colours, for what a view draws over them. */
DKColor WKDInk(void);
DKColor WKDPaper(void);
DKColor WKDSelection(void);
NSColor *WKDInkColor(void);
NSColor *WKDPaperColor(void);
NSColor *WKDSelectionColor(void);

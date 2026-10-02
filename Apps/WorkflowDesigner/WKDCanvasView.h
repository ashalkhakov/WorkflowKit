#import <AppKit/AppKit.h>

@class WKDCanvasView, WKDDiagram, WKDLook;

/* What the canvas asks for; the document's editor makes the changes. */
@protocol WKDCanvasDelegate <NSObject>
- (void)canvas:(WKDCanvasView *)canvas insert:(WKDLook *)tool at:(NSPoint)point;
- (void)canvas:(WKDCanvasView *)canvas move:(NSArray<NSString *> *)elementIds by:(NSSize)offset;
- (void)canvas:(WKDCanvasView *)canvas connect:(NSString *)sourceId to:(NSString *)targetId;
- (void)canvas:(WKDCanvasView *)canvas resize:(NSString *)elementId to:(NSRect)bounds;
- (void)canvas:(WKDCanvasView *)canvas delete:(NSArray<NSString *> *)elementIds;
/* A flow's source (atSource) or target dropped on another node. */
- (void)canvas:(WKDCanvasView *)canvas reconnect:(NSString *)flowId atSource:(BOOL)atSource to:(NSString *)nodeId;
- (void)canvas:(WKDCanvasView *)canvas moveBend:(NSUInteger)index of:(NSString *)flowId to:(NSPoint)point;
- (void)canvas:(WKDCanvasView *)canvas moveLabelOf:(NSString *)elementId by:(NSSize)offset;
/* The selection moved by the arrow keys. */
- (void)canvas:(WKDCanvasView *)canvas nudge:(NSArray<NSString *> *)elementIds by:(NSSize)offset;
/* A name typed over the element. */
- (void)canvas:(WKDCanvasView *)canvas rename:(NSString *)elementId to:(NSString *)name;
/* The menu a right click on the selection shows. */
- (NSMenu *)canvasMenu:(WKDCanvasView *)canvas;
- (void)canvasSelectionDidChange:(WKDCanvasView *)canvas;
- (void)canvasToolWasUsed:(WKDCanvasView *)canvas;
@end

/*
 * The diagram, drawn and edited: CoreWF's directed graph view's ways --
 * click to select, drag to move, drag from a node to connect, Delete --
 * on BPMN's shapes. A flipped view in a scroll view, in the diagram's own
 * coordinates; zooming scales its bounds.
 *
 * Shift- or Command-click adds to the selection or takes out of it, and a
 * band dragged over empty canvas adds what it encloses; the arrow keys
 * nudge what is selected, by ten with Shift. A shape dragged snaps its
 * centre to another's, and a guide shows it.
 *
 * A selected flow shows handles: its ends, dragged onto another node,
 * reconnect it; its bends are dragged where they go. An event's, a
 * gateway's or a flow's name is dragged on its own. Double-click, or
 * Rename, types a name over the element.
 *
 * Moves, connections and resizes are shown as the mouse goes and asked of
 * the delegate when it is released: one change each, one undo step.
 */
@interface WKDCanvasView : NSView <NSTextFieldDelegate>

@property (nonatomic, strong) WKDDiagram *diagram;
/* The ids of the shapes and flows selected. */
@property (nonatomic, copy) NSSet<NSString *> *selection;
/* The same, in the order they were selected: the first is the anchor that
 * the others are lined up with, marked when there are several. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *orderedSelection;
/* What a click puts down; nil to select and move. */
@property (nonatomic, strong) WKDLook *tool;
@property (nonatomic) double zoom;
@property (nonatomic, weak) IBOutlet id<WKDCanvasDelegate> delegate;

- (IBAction)selectAll:(id)sender;
- (void)scrollToContent;
/* The zoom at which the whole diagram fits the visible area, at most
 * actual size twice over, and the view scrolled to it. */
- (void)zoomToFit;
/* A field over the element to type its name in: Return keeps it, Escape
 * leaves the name as it was. */
- (void)beginRenaming:(NSString *)elementId;

@end

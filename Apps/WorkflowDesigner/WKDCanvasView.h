#import <AppKit/AppKit.h>

@class WKDCanvasView, WKDDiagram, WKDLook;

/* What the canvas asks for; the document's editor makes the changes. */
@protocol WKDCanvasDelegate <NSObject>
- (void)canvas:(WKDCanvasView *)canvas insert:(WKDLook *)tool at:(NSPoint)point;
- (void)canvas:(WKDCanvasView *)canvas move:(NSArray<NSString *> *)elementIds by:(NSSize)offset;
- (void)canvas:(WKDCanvasView *)canvas connect:(NSString *)sourceId to:(NSString *)targetId;
- (void)canvas:(WKDCanvasView *)canvas resize:(NSString *)elementId to:(NSRect)bounds;
- (void)canvas:(WKDCanvasView *)canvas delete:(NSArray<NSString *> *)elementIds;
- (void)canvasSelectionDidChange:(WKDCanvasView *)canvas;
- (void)canvasToolWasUsed:(WKDCanvasView *)canvas;
@end

/*
 * The diagram, drawn and edited: CoreWF's directed graph view's ways --
 * click to select, drag to move, drag from a node to connect, Delete --
 * on BPMN's shapes. A flipped view in a scroll view, in the diagram's own
 * coordinates; zooming scales its bounds.
 *
 * Moves, connections and resizes are shown as the mouse goes and asked of
 * the delegate when it is released: one change each, one undo step.
 */
@interface WKDCanvasView : NSView

@property (nonatomic, strong) WKDDiagram *diagram;
/* The ids of the shapes and flows selected. */
@property (nonatomic, copy) NSSet<NSString *> *selection;
/* What a click puts down; nil to select and move. */
@property (nonatomic, strong) WKDLook *tool;
@property (nonatomic) double zoom;
@property (nonatomic, weak) IBOutlet id<WKDCanvasDelegate> delegate;

- (IBAction)selectAll:(id)sender;
- (void)scrollToContent;

@end

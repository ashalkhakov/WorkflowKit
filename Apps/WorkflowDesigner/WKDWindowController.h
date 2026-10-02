#import <AppKit/AppKit.h>
#import "WKDCanvasView.h"
#import "WKDOutline.h"
#import "WKDPaletteView.h"

/*
 * A document's window, in three panes, as RDLKit's and XFormsKit's
 * designers have them: on the left the process's outline, the palette and
 * the engine's problems, each behind a tab; the canvas in the middle; on
 * the right the inspector, for the element selected and for the process.
 * The outline, the canvas and the inspector follow one selection.
 */
@interface WKDWindowController : NSWindowController <WKDCanvasDelegate, WKDPaletteDelegate, WKDOutlineDelegate,
                                                    NSSplitViewDelegate>

@property (nonatomic, strong) IBOutlet WKDCanvasView *canvas;
@property (nonatomic, strong) IBOutlet WKDPaletteView *palette;
@property (nonatomic, strong) IBOutlet NSSplitView *split;
@property (nonatomic, strong) IBOutlet NSView *leftTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *leftTabView;
@property (nonatomic, strong) IBOutlet NSView *rightTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *rightTabView;
@property (nonatomic, strong) IBOutlet NSView *outlineHost;
@property (nonatomic, strong) IBOutlet NSView *problemsHost;
@property (nonatomic, strong) IBOutlet NSView *inspectorHost;
@property (nonatomic, strong) IBOutlet NSView *processHost;
@property (nonatomic, copy) NSString *status;

- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)actualSize:(id)sender;
- (IBAction)arrange:(id)sender;
/* Server ▸ Deploy: the process, its forms and its decisions -- as their
 * editors have them, for those open in one -- to the server connected. */
- (IBAction)deploy:(id)sender;
/* Diagram ▸ Edit Form: the selected task's or start event's embedded form,
 * beside the process, opened in this app's form editor (XFormsDesignKit's);
 * made from its fields first, and named in its form key, when there is
 * none. */
- (IBAction)editForm:(id)sender;
/* Diagram ▸ Edit Decision: the selected business rule task's decision,
 * from the DMN file beside the process that defines it, opened in this
 * app's decision editor; a file of its own made for it, and named in the
 * task's decisionRef, when there is none. */
- (IBAction)editDecision:(id)sender;
/* Diagram ▸ Align: the selected shapes lined up with the first selected;
 * Diagram ▸ Distribute: spread out evenly, across or down. */
- (IBAction)alignLeftEdges:(id)sender;
- (IBAction)alignCentres:(id)sender;
- (IBAction)alignRightEdges:(id)sender;
- (IBAction)alignTopEdges:(id)sender;
- (IBAction)alignMiddles:(id)sender;
- (IBAction)alignBottomEdges:(id)sender;
- (IBAction)distributeAcross:(id)sender;
- (IBAction)distributeDown:(id)sender;
/* View ▸ Zoom to Fit: the whole diagram in the window. */
- (IBAction)zoomToFit:(id)sender;
/* Diagram ▸ Rename: the selected element's name typed over it. */
- (IBAction)rename:(id)sender;
/* A Change Type menu item's type (its represented object) for the
 * selected node. */
- (IBAction)changeType:(id)sender;
/* The selection to the pasteboard as BPMN, and back as copies under ids
 * of their own, a step further down each time; Duplicate both at once. */
- (IBAction)copy:(id)sender;
- (IBAction)cut:(id)sender;
- (IBAction)paste:(id)sender;
- (IBAction)duplicate:(id)sender;
- (IBAction)showOutline:(id)sender;
- (IBAction)showPalette:(id)sender;
- (IBAction)showProblems:(id)sender;
- (IBAction)showElementInspector:(id)sender;
- (IBAction)showProcessInspector:(id)sender;

@end

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
/* Server ▸ Deploy: the process and its forms, to the server connected. */
- (IBAction)deploy:(id)sender;
/* Diagram ▸ Edit Form: the selected task's or start event's embedded form,
 * beside the process, in the form designer (the WKDFormDesigner default,
 * XFormsDesigner); made from its fields first, and named in its form key,
 * when there is none. */
- (IBAction)editForm:(id)sender;
- (IBAction)showOutline:(id)sender;
- (IBAction)showPalette:(id)sender;
- (IBAction)showProblems:(id)sender;
- (IBAction)showElementInspector:(id)sender;
- (IBAction)showProcessInspector:(id)sender;

@end

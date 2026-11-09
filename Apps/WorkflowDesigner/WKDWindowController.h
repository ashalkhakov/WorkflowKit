#import <AppKit/AppKit.h>
#import "WKDCanvasViewController.h"
#import "WKDOutlineViewController.h"
#import "WKDPaletteViewController.h"
#import "WKDProblemsViewController.h"
#import "WKDProcessCommands.h"
#import "WKDInspectorViewController.h"

/*
 * A document's window, in three panes, as RDLKit's and XFormsKit's
 * designers have them: on the left the process's outline, the palette and
 * the engine's problems, each behind a tab; the canvas in the middle; on
 * the right the inspector, for the element selected and for the process.
 * It puts the parts in their places in DesignerWindow.xib and nothing
 * more: each follows the document's process editor, and the Editor menu's
 * commands are in its responder chain.
 */
@interface WKDWindowController : NSWindowController <WKDProcessCommandsHost, NSSplitViewDelegate>

@property (nonatomic, strong) IBOutlet NSSplitView *split;
@property (nonatomic, strong) IBOutlet NSView *leftTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *leftTabView;
@property (nonatomic, strong) IBOutlet NSView *rightTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *rightTabView;
@property (nonatomic, strong) IBOutlet NSView *outlineHost;
@property (nonatomic, strong) IBOutlet NSView *paletteHost;
@property (nonatomic, strong) IBOutlet NSView *problemsHost;
@property (nonatomic, strong) IBOutlet NSView *canvasHost;
@property (nonatomic, strong) IBOutlet NSView *inspectorHost;
@property (nonatomic, strong) IBOutlet NSView *processHost;
@property (nonatomic, copy) NSString *status;

/* The parts, once the window has loaded. */
@property (nonatomic, readonly, strong) WKDCanvasViewController *canvasController;
@property (nonatomic, readonly, strong) WKDOutlineViewController *outlineController;
@property (nonatomic, readonly, strong) WKDPaletteViewController *paletteController;
@property (nonatomic, readonly, strong) WKDProblemsViewController *problemsController;
/* The selected element's properties, and the process's. */
@property (nonatomic, readonly, strong) WKDInspectorViewController *inspectorController;
@property (nonatomic, readonly, strong) WKDInspectorViewController *processInspectorController;
@property (nonatomic, readonly, strong) WKDProcessCommands *commands;

/* The canvas's zoom, for the View menu. */
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)actualSize:(id)sender;
- (IBAction)zoomToFit:(id)sender;
/* Server ▸ Deploy: the process, its forms and its decisions -- as their
 * editors have them, for those open in one -- to the server connected. */
- (IBAction)deploy:(id)sender;
- (IBAction)showOutline:(id)sender;
- (IBAction)showPalette:(id)sender;
- (IBAction)showProblems:(id)sender;
- (IBAction)showElementInspector:(id)sender;
- (IBAction)showProcessInspector:(id)sender;

@end

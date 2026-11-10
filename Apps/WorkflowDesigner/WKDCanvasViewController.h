#import <AppKit/AppKit.h>
#import "WKDCanvasView.h"
#import "WKDProcessEditor.h"

/*
 * The process's diagram, from WKDCanvas.xib: the canvas in its scroll
 * view, its zoom, and the menu a right click on the selection shows, whose
 * items the XIB holds. Its gestures are the process editor's changes, one
 * each; what it shows is the process editor's model and selection, and
 * what it selects there is the selection.
 */
@interface WKDCanvasViewController : NSViewController <WKDCanvasDelegate>

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor;
@property (nonatomic, readonly, strong) WKDProcessEditor *processEditor;

@property (nonatomic, strong) IBOutlet WKDCanvasView *canvas;
/* The right click's menu as the XIB has it: every item, each shown or not
 * by what is selected, Change Type's one item the pattern of its types. */
@property (nonatomic, strong) IBOutlet NSMenu *elementMenu;

/* Why a gesture did nothing, until the next; nil: it did. */
@property (nonatomic, copy) void (^refused)(NSString *reason);
/* An element placed with the palette's tool: the palette back to the
 * pointer. */
@property (nonatomic, copy) void (^toolUsed)(void);

/* The next click places what the tool is; nil: the pointer. */
- (void)armTool:(WKDLook *)tool;
- (void)beginRenaming:(NSString *)elementId;
- (void)scrollToContent;

- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)actualSize:(id)sender;
/* View ▸ Zoom to Fit: the whole diagram in the view. */
- (IBAction)zoomToFit:(id)sender;

@end

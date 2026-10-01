#import <AppKit/AppKit.h>
#import "WKDCanvasView.h"
#import "WKDPaletteView.h"

/* A document's window: the palette, the canvas, and a line saying whether
 * the engine would deploy the process. */
@interface WKDWindowController : NSWindowController <WKDCanvasDelegate, WKDPaletteDelegate>

@property (nonatomic, strong) IBOutlet WKDCanvasView *canvas;
@property (nonatomic, strong) IBOutlet WKDPaletteView *palette;
@property (nonatomic, copy) NSString *status;

- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)actualSize:(id)sender;
- (IBAction)arrange:(id)sender;

@end

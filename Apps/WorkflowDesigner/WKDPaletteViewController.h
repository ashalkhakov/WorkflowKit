#import <AppKit/AppKit.h>
#import "WKDPaletteView.h"

/*
 * The elements a click on the canvas puts down, from WKDPalette.xib, drawn
 * as the canvas draws them: what the designer's Insert tab shows, and in
 * UDCode its Library.
 */
@interface WKDPaletteViewController : NSViewController <WKDPaletteDelegate>

- (instancetype)init;

@property (nonatomic, strong) IBOutlet WKDPaletteView *palette;
/* A tool chosen; nil: the pointer. */
@property (nonatomic, copy) void (^chosen)(WKDLook *tool);

/* Back to the pointer, without saying so. */
- (void)choosePointer;

@end

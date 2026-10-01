#import <AppKit/AppKit.h>

@class WKDLook, WKDPaletteView;

@protocol WKDPaletteDelegate <NSObject>
/* nil: the pointer, to select and move. */
- (void)palette:(WKDPaletteView *)palette didChoose:(WKDLook *)tool;
@end

/* The elements a click on the canvas puts down, drawn as the canvas draws
 * them, in two columns; the pointer first. */
@interface WKDPaletteView : NSView
@property (nonatomic, weak) IBOutlet id<WKDPaletteDelegate> delegate;
/* Back to the pointer. */
- (void)choosePointer;
@end

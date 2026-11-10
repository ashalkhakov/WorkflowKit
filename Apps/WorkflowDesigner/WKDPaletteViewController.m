#import "WKDPaletteViewController.h"

@implementation WKDPaletteViewController

- (instancetype)init
{
	return [super initWithNibName:@"WKDPalette" bundle:[NSBundle bundleForClass:[WKDPaletteViewController class]]];
}

- (void)palette:(WKDPaletteView *)palette didChoose:(WKDLook *)tool
{
	if (self.chosen != nil) {
		self.chosen(tool);
	}
}

- (void)choosePointer
{
	[self view];
	[self.palette choosePointer];
}

@end

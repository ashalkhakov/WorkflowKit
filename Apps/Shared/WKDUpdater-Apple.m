#import "WKDUpdater.h"
#import <Sparkle/Sparkle.h>

/* macOS: Sparkle (WKDUpdater.h). */
@implementation WKDUpdater
{
	SPUStandardUpdaterController *_controller;
}

- (instancetype)initStarting:(BOOL)start
{
	if (!(self = [super init])) {
		return nil;
	}
	_controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:start
	                                                            updaterDelegate:nil
	                                                         userDriverDelegate:nil];
	return self;
}

- (BOOL)available
{
	return YES;
}

- (BOOL)canCheckForUpdates
{
	return _controller.updater.canCheckForUpdates;
}

- (IBAction)checkForUpdates:(id)sender
{
	[_controller checkForUpdates:sender];
}

- (void)addMenuItemWithTarget:(id)target
{
	WKDAddCheckForUpdatesItem(self, target);
}

@end

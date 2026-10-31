#import "WKDUpdater.h"
#import <GSUpdater/GSUpdater.h>

/* GNUstep: the stack's GSUpdater (WKDUpdater.h) -- WinSparkle on Windows; on
   Linux nothing, the AppImage being updated from outside it. */
@implementation WKDUpdater
{
	GSUpdater *_updater;
}

- (instancetype)initStarting:(BOOL)start
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_updater = [[GSUpdater alloc] initStarting:start];
	return self;
}

- (BOOL)available
{
	return [_updater available];
}

- (BOOL)canCheckForUpdates
{
	return [_updater canCheckForUpdates];
}

- (IBAction)checkForUpdates:(id)sender
{
	[_updater checkForUpdates:sender];
}

- (void)addMenuItemWithTarget:(id)target
{
	WKDAddCheckForUpdatesItem(self, target);
}

@end

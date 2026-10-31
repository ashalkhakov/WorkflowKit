//
// WKDUpdater — WorkflowDesk's and WorkflowDesigner's updates.
//
// On macOS, Sparkle (WKDUpdater-Apple.m): the newest release's appcast for
// this app (SUFeedURL in <App>-Info.plist, appcast-<App>.xml, signed with the
// key SUPublicEDKey names) is checked once a day if the user allows it, and
// Check for Updates… checks now. On GNUstep (WKDUpdater-GNUstep.m), the
// stack's GSUpdater: on Windows WinSparkle, its feed the newest release's
// appcast-windows.xml (SUWindowsFeedURL, which the installer's build writes
// into Info-gnustep.plist with SUPublicEDKey, the same key's); on Linux
// nothing, the AppImage carrying its own update information, for
// AppImageUpdate, Gear Lever and the like.
//
// WKDUpdater-Apple.m is the Xcode targets' (.tools/genxcodeproj.py takes it
// for the -GNUstep.m the GNUmakefiles name), WKDUpdater-GNUstep.m the
// GNUmakefiles'.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKDUpdater : NSObject
// Started at once unless told not to.
- (instancetype)initStarting:(BOOL)start;
// Whether this system has an updater at all (Check for Updates… shown).
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) BOOL canCheckForUpdates;
- (IBAction)checkForUpdates:(nullable id)sender;
// Check for Updates…, put in the app menu after About when there is an
// updater, sent to target.
- (void)addMenuItemWithTarget:(id)target;
@end

/* The menu item both halves add: after About in the app menu (MainMenu.xib),
 * where there is an updater. */
static inline void WKDAddCheckForUpdatesItem(WKDUpdater *updater, id target)
{
	if (![updater available]) {
		return;
	}
	NSMenu *appMenu = [[[NSApp mainMenu] itemAtIndex:0] submenu];
	NSInteger about = [appMenu indexOfItemWithTarget:nil
	                                       andAction:@selector(orderFrontStandardAboutPanel:)];
	NSMenuItem *check = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…"
	                                               action:@selector(checkForUpdates:)
	                                        keyEquivalent:@""];
	[check setTarget:target];
	[appMenu insertItem:check atIndex:about >= 0 ? about + 1 : 0];
}

NS_ASSUME_NONNULL_END

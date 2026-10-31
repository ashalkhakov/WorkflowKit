//
// WKLauncherAppDelegate — the chooser the AppImage and the Windows
// installer's shortcut open.
//
// The image and the installer have one entry point and carry two
// applications, WorkflowDesk and WorkflowDesigner, so launching opens this: a
// window with a button per app. Ported from XFormsKit's XFormsLauncher (and
// it from UDQuakeTools' UDLauncher); the menu is built in code.
//
// Only GNUstep builds it. On a Mac each app is its own bundle in
// /Applications and there is nothing to choose between.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKLauncherAppDelegate : NSObject
@end

NS_ASSUME_NONNULL_END

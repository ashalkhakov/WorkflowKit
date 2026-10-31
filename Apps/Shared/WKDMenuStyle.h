//
// WKDMenuStyle — where the apps' menus are.
//
// Under a theme that puts the menus in the windows (WinUXTheme, the Windows
// installer's look) an app with no window shows nothing of itself at all:
// no menu bar, no floating menu. There each app opens a window at launch
// and quits with its last one, as a Windows program does. Elsewhere (macOS,
// GNUstep's own look) the menu stays up on its own and nothing changes.
//

#import <AppKit/AppKit.h>

static inline BOOL WKDMenusInWindows(void)
{
#if defined(GNUSTEP)
    return NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil) == NSWindows95InterfaceStyle;
#else
    return NO;
#endif
}

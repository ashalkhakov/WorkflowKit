//
// WorkflowLauncher — the chooser the AppImage opens. See
// WKLauncherAppDelegate.h.
//

#import <AppKit/AppKit.h>
#import "WKLauncherAppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        WKLauncherAppDelegate *delegate = [[WKLauncherAppDelegate alloc] init];
        [app setDelegate:(id)delegate];
        [app run];
    }
    (void)argc; (void)argv;
    return 0;
}

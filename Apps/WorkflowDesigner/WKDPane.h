#import <AppKit/AppKit.h>

/* Putting the panes in their places; ported from RDLKit's RDLPane. */

/* The view fills the host, and goes on filling it as it resizes. */
void WKDFillHost(NSView *host, NSView *view);
/* The same, in a scroll view: a pane taller than its place scrolls rather
 * than losing its last rows. The view keeps its own height. */
void WKDFillHostScrolling(NSView *host, NSView *view);
/* A round coloured badge with one or two letters, for a tab bar: drawn,
 * not shipped as an image. */
NSImage *WKDTabBadge(NSString *letters, double r, double g, double b);

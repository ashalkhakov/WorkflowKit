#import "WKDPane.h"

void
WKDFillHost(NSView *host, NSView *view)
{
	[view setFrame:[host bounds]];
	[view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[host addSubview:view];
}

void
WKDFillHostScrolling(NSView *host, NSView *view)
{
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:[host bounds]];
	[scroll setHasVerticalScroller:YES];
	[scroll setHasHorizontalScroller:NO];
	/* Shown always: GNUstep's scroller, on the left, leaves its line where
	 * it hid, and what the pane holds slides under it. */
	[scroll setAutohidesScrollers:NO];
	[scroll setBorderType:NSNoBorder];
	[scroll setDrawsBackground:NO];
	[scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[view setFrame:NSMakeRect(0, 0, [scroll contentSize].width, NSHeight([view frame]))];
	[view setAutoresizingMask:NSViewWidthSizable];
	[scroll setDocumentView:view];
	[host addSubview:scroll];
}

NSImage *
WKDTabBadge(NSString *letters, double r, double g, double b)
{
	static NSMutableDictionary *cache;
	if (cache == nil) {
		cache = [NSMutableDictionary dictionary];
	}
	NSString *key = [NSString stringWithFormat:@"%@|%.2f%.2f%.2f", letters, r, g, b];
	NSImage *image = [cache objectForKey:key];
	if (image != nil) {
		return image;
	}
	NSSize size = NSMakeSize(15, 15);
	image = [[NSImage alloc] initWithSize:size];
	/* -lockFocus is deprecated on macOS and is what GNUstep has. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	[image lockFocus];
	[[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] set];
	[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 14, 14)] fill];
	NSDictionary *attributes = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[letters length] > 1 ? 7.0 : 9.0],
	                              NSForegroundColorAttributeName: [NSColor whiteColor] };
	NSSize text = [letters sizeWithAttributes:attributes];
	[letters drawAtPoint:NSMakePoint((size.width - text.width) / 2, (size.height - text.height) / 2)
	      withAttributes:attributes];
	[image unlockFocus];
#pragma clang diagnostic pop
	[cache setObject:image forKey:key];
	return image;
}

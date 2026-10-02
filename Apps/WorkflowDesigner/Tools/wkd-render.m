/*
 * wkd-render -- a BPMN file's diagram as a PNG, drawn as the designer's
 * canvas draws it: for documentation (docs/examples).
 *
 *   wkd-render file.bpmn out.png [scale]
 *
 * On GNUstep it needs a display to draw with; Xvfb will do.
 */
#import <AppKit/AppKit.h>
#import "WKDCanvasView.h"
#import "WKDDiagram.h"
#import "WKDEditor.h"

int
main(int argc, const char *argv[])
{
	@autoreleasepool {
		if (argc < 3) {
			fprintf(stderr, "usage: wkd-render file.bpmn out.png [scale]\n");
			return 2;
		}
		[NSApplication sharedApplication];
		NSError *error = nil;
		NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
		NSXMLDocument *document = data != nil ? [[NSXMLDocument alloc] initWithData:data options:0 error:&error] : nil;
		WKDEditor *editor = document != nil ? [[WKDEditor alloc] initWithDocument:document undoManager:nil] : nil;
		if (editor.diagram.process == nil) {
			fprintf(stderr, "wkd-render: %s is not a BPMN process\n", argv[1]);
			return 1;
		}
		[editor completeDiagram];
		double scale = argc > 3 ? atof(argv[3]) : 1.0;
		/* The shapes with room around them, and under the lowest for its
		 * name. */
		NSRect content = NSInsetRect(editor.diagram.contentBounds, -24, -24);
		content.size.height += 16;
		WKDCanvasView *canvas = [[WKDCanvasView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
		canvas.diagram = editor.diagram;
		canvas.zoom = scale;
		/* Drawn in a window, as on screen, and read back from it: the way
		 * gnustep-gui draws a view, an offscreen cache of it is empty. */
		NSWindow *window = [[NSWindow alloc] initWithContentRect:[canvas frame] styleMask:NSWindowStyleMaskBorderless
		                                                 backing:NSBackingStoreBuffered defer:NO];
		[[window contentView] addSubview:canvas];
		[window orderFront:nil];
		[window display];
		NSRect rect = NSIntersectionRect(content, [canvas bounds]);
		[canvas lockFocus];
		NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithFocusedViewRect:rect];
		[canvas unlockFocus];
		NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
		if (![png writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES]) {
			fprintf(stderr, "wkd-render: cannot write %s\n", argv[2]);
			return 1;
		}
		return 0;
	}
}

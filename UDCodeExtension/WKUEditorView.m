/*
 * UDCode's BPMN and DMN extension -- an editor tab's view (see
 * WKUEditorView.h).
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import "WKUEditorView.h"

@implementation WKUEditorView

- (void)setNextResponder:(NSResponder *)responder
{
	NSResponder *controller = self.controller;
	if (controller == nil || responder == controller) {
		[super setNextResponder:responder];
		return;
	}
	[controller setNextResponder:responder];
	[super setNextResponder:controller];
}

@end

NSImage *
WKUTabImage(NSImage *badge)
{
	if (badge == nil) {
		return nil;
	}
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	[image lockFocus];
	[badge drawInRect:NSMakeRect(0.5, 0.5, 15, 15) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
	[image unlockFocus];
#pragma clang diagnostic pop
	return image;
}

/*
 * UDCode's BPMN and DMN extension -- an editor tab's view
 * (WKUProcessEditor.xib, WKUDecisionEditor.xib): its controller after it
 * in the responder chain, wherever UDCode puts it, so the Editor menu's
 * items and Undo reach the tab. AppKit puts a view controller there by
 * itself (since 10.10); gnustep-gui does not; and a view put in another is
 * given its superview as the next responder again.
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import <AppKit/AppKit.h>

@interface WKUEditorView : NSView
@property (nonatomic, weak) IBOutlet NSResponder *controller;
@end

/* A badge at a pane tab's size (16 points square), drawn afresh: a copy of
 * a badge drawn with -lockFocus is blank on GNUstep, whose image keeps what
 * was drawn in a cache the copy does not take. */
NSImage *WKUTabImage(NSImage *badge);

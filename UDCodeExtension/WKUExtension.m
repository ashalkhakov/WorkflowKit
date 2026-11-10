/*
 * UDCode's BPMN and DMN extension (see WKUExtension.h).
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import "WKUExtension.h"
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDLanguageMode.h>
#import <UDPieceTable/UDTextModel.h>
#import "WKUProcessEditorViewController.h"
#import "WKUDecisionEditorViewController.h"

@implementation WKUExtension

+ (NSArray<NSMenuItem *> *)editorMenuItems
{
	NSNib *nib = [[NSNib alloc] initWithNibNamed:@"WKUEditorMenus" bundle:[NSBundle bundleForClass:[WKUExtension class]]];
	NSArray *objects = nil;
	/* An owner the XIB has no use for: gnustep-gui's NSNib takes no nil one. */
	if (![nib instantiateWithOwner:[[NSObject alloc] init] topLevelObjects:&objects]) {
		return @[];
	}
	for (id object in objects) {
		if ([object isKindOfClass:[NSMenu class]]) {
			NSArray *items = [[(NSMenu *)object itemArray] copy];
			[(NSMenu *)object removeAllItems];
			return items;
		}
	}
	return @[];
}

+ (BOOL)textIsAProcess:(NSString *)text
{
	return [text rangeOfString:@"http://www.omg.org/spec/BPMN/20100524/MODEL"].location != NSNotFound;
}

+ (BOOL)textIsDecisions:(NSString *)text
{
	return [text rangeOfString:@"/spec/DMN/"].location != NSNotFound;
}

- (void)extensionDidLoad:(NSBundle *)bundle
{
}

- (void)extensionWillUnload:(NSBundle *)bundle
{
}

/* The modes' grammar is the XML mode's (LanguageInfo.plist's grammarOf). */
- (const void *)languageFuncForIdentifier:(NSString *)identifier
{
	return NULL;
}

/* A process in the process editor, decisions in the decision editor;
 * anything else in either file as text, in the XML grammar. */
- (NSViewController *)workbench:(id<UDWorkbench>)workbench editorForDocument:(UDCodeDocument *)document
{
	NSString *mode = document.languageMode.identifier;
	NSString *text = [document.textModel getValue];
	if ([mode isEqualToString:@"bpmn"] && [WKUExtension textIsAProcess:text]) {
		return [[WKUProcessEditorViewController alloc] initWithDocument:document workbench:workbench];
	}
	if ([mode isEqualToString:@"dmn"] && [WKUExtension textIsDecisions:text]) {
		return [[WKUDecisionEditorViewController alloc] initWithDocument:document workbench:workbench];
	}
	return nil;
}

/* The editors' items go to the first responder, which in a process's or
 * decisions' tab is its editor; elsewhere nothing takes them, and they are
 * dimmed. */
- (NSArray<NSMenuItem *> *)editorMenuItemsForWorkbench:(id<UDWorkbench>)workbench
{
	return [WKUExtension editorMenuItems];
}

@end

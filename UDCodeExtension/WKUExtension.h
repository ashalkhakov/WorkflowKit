/*
 * UDCode's BPMN and DMN extension (docs/UDCODE.md): processes and decisions
 * edited in UDCode with the designer's parts (Apps/WorkflowDesigner), in a
 * tab of their own, as part of a project. A .bpmn file opens in the
 * process editor, a .dmn file in the decision editor: the file's text is
 * what is edited, each change written into it, so undo, saving, the tab's
 * dot and source control are UDCode's, and a tab of its text shows it as
 * XML (its grammar is the XML mode's). A file of either kind that is not
 * BPMN or DMN opens as text. The editors' menus are in UDCode's Editor
 * menu; what the engine finds wrong is in the Issues navigator.
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDExtension.h>

@interface WKUExtension : NSObject <UDExtension>

/* The Editor menu's items, from WKUEditorMenus.xib. */
+ (NSArray<NSMenuItem *> *)editorMenuItems;
/* Whether the text is a BPMN process's, or DMN decisions'. */
+ (BOOL)textIsAProcess:(NSString *)text;
+ (BOOL)textIsDecisions:(NSString *)text;

@end

/*
 * UDCode's BPMN and DMN extension -- a DMN file's tab
 * (WKUDecisionEditor.xib): the decision editor's parts over the file's
 * text, spread over the window's panes as an Xcode editor's are
 * (UDEditorPanes): the decisions listed, and the one chosen -- its name,
 * id and the decisions it requires, and its decision table or literal
 * expression -- in the tab; the column chosen in the table, a tab of the
 * inspector pane; what the engine finds wrong the document's issues.
 *
 * The text is the model, as in a process's tab
 * (WKUProcessEditorViewController.h): each change one edit of it, its
 * undo the undo; changed some other way, it is read again, what is chosen
 * kept where it still is.
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>
#import <UDCodeKit/UDEditorPanes.h>

@class UDCodeDocument, WKDDecisionEditor, WKDDecisionListViewController, WKDDecisionDetailViewController,
	WKDRuleGridViewController, WKDColumnViewController, WKDLiteralViewController;

@interface WKUDecisionEditorViewController : NSViewController <UDEditorPanes, NSSplitViewDelegate>

/* The tabs open, in every window: a process's Edit Decision finds its
 * file's here. */
+ (NSArray<WKUDecisionEditorViewController *> *)openTabs;
+ (instancetype)tabOfURL:(NSURL *)url;

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench;

@property (nonatomic, readonly, strong) UDCodeDocument *document;
/* The decision editor, made for the first text that is DMN; nil until then. */
@property (nonatomic, readonly, strong) WKDDecisionEditor *decisionEditor;
/* Why the text is not DMN, while it is not; nil while it is. */
@property (nonatomic, readonly, copy) NSString *problem;

@property (nonatomic, readonly, strong) WKDDecisionListViewController *listController;
@property (nonatomic, readonly, strong) WKDDecisionDetailViewController *detailController;
@property (nonatomic, readonly, strong) WKDRuleGridViewController *gridController;
@property (nonatomic, readonly, strong) WKDLiteralViewController *literalController;
/* The inspector pane's tab: the column chosen. */
@property (nonatomic, readonly, strong) WKDColumnViewController *columnController;
/* What the last change refused, and whether the engine evaluates them. */
@property (nonatomic, readonly, copy) NSString *status;

/* The decision chosen; made, a decision table, when the file has none of
 * that id. */
- (void)showDecision:(NSString *)decisionId;
/* The text written now, if a change is waiting. */
- (void)write;

- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
- (IBAction)showAsText:(id)sender;

@end

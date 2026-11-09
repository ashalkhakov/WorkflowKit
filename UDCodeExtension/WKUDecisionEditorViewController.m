/*
 * UDCode's BPMN and DMN extension -- a DMN file's tab (see
 * WKUDecisionEditorViewController.h).
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import "WKUDecisionEditorViewController.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDDiagnosticStore.h>
#import <UDPieceTable/UDTextModel.h>
#import "WKDDecisionEditor.h"
#import "WKDDecisionListViewController.h"
#import "WKDDecisionDetailViewController.h"
#import "WKDRuleGridViewController.h"
#import "WKDColumnViewController.h"
#import "WKDLiteralViewController.h"
#import "WKDPane.h"
#import "WKUEditorView.h"
#import "WKUTextEdits.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

/* The engine's problems, among the document's diagnostics. */
static UDDiagnosticSource const WKUIssueSource = @"dmn";

/* The list's width when the tab opens, and its narrowest. */
static const CGFloat WKUListWidth = 220;
static const CGFloat WKUListMinimum = 150;

@interface WKUDecisionEditorViewController ()
@property (nonatomic, weak) IBOutlet NSView *problemView;
@property (nonatomic, weak) IBOutlet NSTextField *problemLabel;
@property (nonatomic, weak) IBOutlet NSView *editorView;
@property (nonatomic, weak) IBOutlet NSSplitView *split;
@property (nonatomic, weak) IBOutlet NSView *listHost;
@property (nonatomic, weak) IBOutlet NSView *detailHost;
@property (nonatomic, weak) IBOutlet NSView *gridHost;
@property (nonatomic, weak) IBOutlet NSView *literalHost;
@property (nonatomic, weak) IBOutlet NSTextField *statusField;
@property (nonatomic, readwrite, strong) WKDDecisionEditor *decisionEditor;
@property (nonatomic, readwrite, copy) NSString *problem;
@property (nonatomic, readwrite, strong) WKDDecisionListViewController *listController;
@property (nonatomic, readwrite, strong) WKDDecisionDetailViewController *detailController;
@property (nonatomic, readwrite, strong) WKDRuleGridViewController *gridController;
@property (nonatomic, readwrite, strong) WKDLiteralViewController *literalController;
@property (nonatomic, readwrite, strong) WKDColumnViewController *columnController;
@property (nonatomic, readwrite, copy) NSString *status;
@end

@implementation WKUDecisionEditorViewController
{
	__weak id<UDWorkbench> _workbench;
	BOOL _reading;
	BOOL _writing;
	/* What the last change refused, or an expression's problem as it is typed. */
	NSString *_note;
	/* Each issue's decision, by its diagnostic's line and message. */
	NSMutableDictionary<NSString *, NSString *> *_issueDecisions;
}

static NSHashTable *WKUOpenTabs;

+ (NSArray<WKUDecisionEditorViewController *> *)openTabs
{
	return [WKUOpenTabs allObjects] ?: @[];
}

+ (instancetype)tabOfURL:(NSURL *)url
{
	NSString *path = [[url URLByStandardizingPath] path];
	for (WKUDecisionEditorViewController *tab in [self openTabs]) {
		if (path != nil && [[[tab.document.fileURL URLByStandardizingPath] path] isEqualToString:path]) {
			return tab;
		}
	}
	return nil;
}

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench
{
	if ((self = [super initWithNibName:@"WKUDecisionEditor"
	                            bundle:[NSBundle bundleForClass:[WKUDecisionEditorViewController class]]])) {
		_document = document;
		_workbench = workbench;
		_issueDecisions = [NSMutableDictionary dictionary];
		if (WKUOpenTabs == nil) {
			WKUOpenTabs = [NSHashTable weakObjectsHashTable];
		}
		[WKUOpenTabs addObject:self];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textDidChange:)
		                                             name:UDTextModelDidChangeNotification
		                                           object:document.textModel];
		[self read];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)loadView
{
	[super loadView];
	[self.split setPosition:WKUListWidth ofDividerAtIndex:0];
	[self show];
}

/* The Decision menu's actions -- the list's and the grid's -- after this,
 * wherever UDCode puts the tab. */
- (void)setNextResponder:(NSResponder *)responder
{
	if (self.listController == nil || responder == self.listController) {
		[super setNextResponder:responder];
		return;
	}
	[self.gridController setNextResponder:responder];
	[self.listController setNextResponder:self.gridController];
	[super setNextResponder:self.listController];
}

#pragma mark Reading

- (void)makePartsWithData:(NSData *)data error:(NSError **)error
{
	WKDDecisionEditor *decisionEditor = [[WKDDecisionEditor alloc] initWithData:data undoManager:nil error:error];
	if (decisionEditor == nil) {
		return;
	}
	self.decisionEditor = decisionEditor;
	decisionEditor.fileName = [_document.fileURL lastPathComponent];
	[decisionEditor checkNow];
	__weak WKUDecisionEditorViewController *weakSelf = self;
	void (^refused)(NSString *) = ^(NSString *reason) {
		[weakSelf note:reason];
	};
	void (^explained)(NSString *) = ^(NSString *problem) {
		[weakSelf note:problem];
	};
	self.listController = [[WKDDecisionListViewController alloc] initWithDecisionEditor:decisionEditor];
	self.detailController = [[WKDDecisionDetailViewController alloc] initWithDecisionEditor:decisionEditor];
	self.gridController = [[WKDRuleGridViewController alloc] initWithDecisionEditor:decisionEditor];
	self.literalController = [[WKDLiteralViewController alloc] initWithDecisionEditor:decisionEditor];
	self.columnController = [[WKDColumnViewController alloc] initWithDecisionEditor:decisionEditor];
	self.columnController.title = @"Column";
	self.detailController.refused = refused;
	self.gridController.explained = explained;
	self.columnController.explained = explained;
	self.literalController.explained = explained;
	self.listController.added = ^{
		[[weakSelf.view window] makeFirstResponder:weakSelf.detailController.nameField];
	};
	self.gridController.columnAdded = ^(BOOL output) {
		[weakSelf showColumn];
		[weakSelf.columnController focus];
	};
	[self setNextResponder:[super nextResponder]];

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(decisionsDidChange:) name:WKDDecisionEditorDidChangeNotification
	             object:decisionEditor];
	[center addObserver:self selector:@selector(choiceDidChange:) name:WKDDecisionEditorChoiceDidChangeNotification
	             object:decisionEditor];
	[center addObserver:self selector:@selector(problemsDidChange:) name:WKDDecisionEditorProblemsDidChangeNotification
	             object:decisionEditor];
	[self findIssues];
}

- (void)read
{
	NSData *data = [[_document.textModel getValue] ?: @"" dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error = nil;
	BOOL first = self.decisionEditor == nil;
	_reading = YES;
	if (first) {
		[self makePartsWithData:data error:&error];
	}
	BOOL read = first ? self.decisionEditor != nil : [self.decisionEditor readData:data error:&error];
	_reading = NO;
	self.problem = read ? nil
		: [NSString stringWithFormat:@"This is not DMN that can be shown: %@",
		   [error localizedRecoverySuggestion] ?: [error localizedDescription] ?: @"it cannot be read."];
	[self show];
}

- (void)textDidChange:(NSNotification *)notification
{
	if (_writing) {
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(read) object:nil];
	if ([self isViewLoaded] && [[self view] window] != nil) {
		[self read];
	} else {
		[self performSelector:@selector(read) withObject:nil afterDelay:0.3];
	}
}

#pragma mark Writing

- (void)decisionsDidChange:(NSNotification *)notification
{
	[self show];
	if (_reading) {
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
	[self performSelector:@selector(write) withObject:nil afterDelay:0];
}

- (void)write
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
	if (self.decisionEditor == nil || self.problem != nil) {
		return;
	}
	NSString *text = [[NSString alloc] initWithData:[self.decisionEditor data] encoding:NSUTF8StringEncoding];
	if (text == nil) {
		return;
	}
	_writing = YES;
	WKUWriteText(_document.textModel, text);
	_writing = NO;
}

#pragma mark Showing

/* The list, the detail, and the table or the literal expression in the
 * tab; or why there are none. */
- (void)show
{
	if (![self isViewLoaded]) {
		return;
	}
	BOOL shown = self.problem == nil && self.decisionEditor != nil;
	if (shown) {
		if ([self.listController.view superview] != self.listHost) {
			WKDFillHost(self.listHost, self.listController.view);
			WKDFillHost(self.detailHost, self.detailController.view);
			WKDFillHost(self.gridHost, self.gridController.view);
			WKDFillHost(self.literalHost, self.literalController.view);
		}
		WKDDmnDecision *decision = self.decisionEditor.decision;
		[self.gridHost setHidden:!decision.isTable];
		[self.literalHost setHidden:decision == nil || decision.isTable];
	} else {
		[self.problemLabel setStringValue:self.problem ?: @""];
	}
	[self.editorView setHidden:!shown];
	[self.problemView setHidden:shown];
	[self updateStatus];
}

- (void)choiceDidChange:(NSNotification *)notification
{
	[self show];
	if (self.decisionEditor.column != NSNotFound) {
		[self showColumn];
	}
}

- (void)showColumn
{
	if ([[self view] window] != nil) {
		[_workbench showEditorInspector:self.columnController];
	}
}

- (void)showDecision:(NSString *)decisionId
{
	if (self.decisionEditor == nil || self.problem != nil || decisionId == nil) {
		return;
	}
	if ([self.decisionEditor.editor decisionWithId:decisionId] == nil) {
		[self.decisionEditor.editor addDecisionTable:YES withId:decisionId];
	}
	self.decisionEditor.decisionId = decisionId;
}

- (void)updateStatus
{
	if (self.decisionEditor == nil) {
		self.status = nil;
	} else {
		NSString *problem = self.decisionEditor.problem;
		NSMutableArray *parts = [NSMutableArray array];
		if (_note != nil) {
			[parts addObject:_note];
		}
		[parts addObject:problem == nil ? @"The engine evaluates these decisions."
		                                : [NSString stringWithFormat:@"Not deployable: %@", problem]];
		self.status = [parts componentsJoinedByString:@" — "];
	}
	[self.statusField setStringValue:self.status ?: @""];
}

- (void)note:(NSString *)note
{
	_note = [note copy];
	[self updateStatus];
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
	return subview != self.listHost;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
	return MAX(proposed, WKUListMinimum);
}

#pragma mark The engine's problems, as issues

- (void)problemsDidChange:(NSNotification *)notification
{
	[self findIssues];
	[self updateStatus];
}

/* Each problem at the line its element's id is written on; the problem's
 * own line when it is about no element the text has. */
- (void)findIssues
{
	NSMutableArray *items = [NSMutableArray array];
	[_issueDecisions removeAllObjects];
	NSString *text = [_document.textModel getValue] ?: @"";
	for (WFProblem *problem in self.problem == nil ? self.decisionEditor.problems : @[]) {
		NSInteger line = MAX((NSInteger)problem.line, 1);
		NSRange at = problem.elementId != nil
			? [text rangeOfString:[NSString stringWithFormat:@"id=\"%@\"", problem.elementId]]
			: NSMakeRange(NSNotFound, 0);
		if (at.location != NSNotFound) {
			line = [_document.textModel getPositionAt:(NSInteger)at.location].line;
		}
		[items addObject:[[UDDiagnosticItem alloc] initWithLine:line column:0 message:problem.message
		                                               severity:UDDiagnosticSeverityError source:WKUIssueSource]];
		if (problem.elementId != nil) {
			[_issueDecisions setObject:problem.elementId
			                    forKey:[NSString stringWithFormat:@"%ld %@", (long)line, problem.message]];
		}
	}
	[_document.diagnosticStore setDiagnostics:items forSource:WKUIssueSource];
}

#pragma mark The window's panes (UDEditorPanes)

- (NSArray<NSViewController *> *)inspectorViewControllers
{
	if (self.decisionEditor == nil || self.problem != nil) {
		return @[];
	}
	return @[ self.columnController ];
}

- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController
{
#ifndef GNUSTEP
	if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
		return [NSImage imageWithSystemSymbolName:@"tablecells" accessibilityDescription:viewController.title];
	}
#endif
	return WKUTabImage(WKDTabBadge(@"C", 0.20, 0.50, 0.90));
}

/* An issue of a decision: that decision chosen. */
- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic
{
	NSString *decisionId = [_issueDecisions objectForKey:[NSString stringWithFormat:@"%ld %@", (long)diagnostic.line,
	                                                      diagnostic.message]];
	if (decisionId != nil && [self.decisionEditor.editor decisionWithId:decisionId] != nil) {
		self.decisionEditor.decisionId = decisionId;
	}
}

#pragma mark Actions

- (IBAction)undo:(id)sender
{
	[self write];
	[_document.textModel.undoManager undo];
}

- (IBAction)redo:(id)sender
{
	[_document.textModel.undoManager redo];
}

- (IBAction)showAsText:(id)sender
{
	[_workbench showDocumentAsText:_document];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	SEL action = [item action];
	if (sel_isEqual(action, @selector(undo:))) {
		return _document.textModel.undoManager.canUndo;
	}
	if (sel_isEqual(action, @selector(redo:))) {
		return _document.textModel.undoManager.canRedo;
	}
	return YES;
}

@end

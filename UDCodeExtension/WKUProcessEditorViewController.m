/*
 * UDCode's BPMN and DMN extension -- a process's tab (see
 * WKUProcessEditorViewController.h).
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import "WKUProcessEditorViewController.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDDiagnosticStore.h>
#import <UDPieceTable/UDTextModel.h>
#import "WKDProcessEditor.h"
#import "WKDCanvasViewController.h"
#import "WKDOutlineViewController.h"
#import "WKDPaletteViewController.h"
#import "WKDInspectorViewController.h"
#import "WKDDeployment.h"
#import "WKDDecisions.h"
#import "WKDPane.h"
#import "WKDXML.h"
#import "WKUDecisionEditorViewController.h"
#import "WKUEditorView.h"
#import "WKUTextEdits.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

/* The engine's problems, among the document's diagnostics. */
static UDDiagnosticSource const WKUIssueSource = @"bpmn";

/* The outline's width when the tab opens, and its narrowest. */
static const CGFloat WKUOutlineWidth = 230;
static const CGFloat WKUOutlineMinimum = 160;

@interface WKUProcessEditorViewController ()
@property (nonatomic, weak) IBOutlet NSView *problemView;
@property (nonatomic, weak) IBOutlet NSTextField *problemLabel;
@property (nonatomic, weak) IBOutlet NSView *editorView;
@property (nonatomic, weak) IBOutlet NSSplitView *split;
@property (nonatomic, weak) IBOutlet NSView *outlineHost;
@property (nonatomic, weak) IBOutlet NSView *canvasHost;
@property (nonatomic, weak) IBOutlet NSTextField *statusField;
@property (nonatomic, readwrite, strong) WKDProcessEditor *processEditor;
@property (nonatomic, readwrite, copy) NSString *problem;
@property (nonatomic, readwrite, strong) WKDCanvasViewController *canvasController;
@property (nonatomic, readwrite, strong) WKDOutlineViewController *outlineController;
@property (nonatomic, readwrite, strong) WKDPaletteViewController *paletteController;
@property (nonatomic, readwrite, strong) WKDInspectorViewController *inspectorController;
@property (nonatomic, readwrite, strong) WKDInspectorViewController *processInspectorController;
@property (nonatomic, readwrite, strong) WKDProcessCommands *commands;
@property (nonatomic, readwrite, copy) NSString *status;
@end

@implementation WKUProcessEditorViewController
{
	__weak id<UDWorkbench> _workbench;
	/* The text being read (what the process editor reports then is no
	 * change of the user's), or written (what the text model reports then
	 * is the parts' own). */
	BOOL _reading;
	BOOL _writing;
	/* What the last command refused or said, shown until the next. */
	NSString *_note;
	/* Each issue's element, by its diagnostic's line and message. */
	NSMutableDictionary<NSString *, NSString *> *_issueElements;
}

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench
{
	if ((self = [super initWithNibName:@"WKUProcessEditor"
	                            bundle:[NSBundle bundleForClass:[WKUProcessEditorViewController class]]])) {
		_document = document;
		_workbench = workbench;
		_issueElements = [NSMutableDictionary dictionary];
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
	[self.split setPosition:WKUOutlineWidth ofDividerAtIndex:0];
	[self show];
}

/* The Editor menu's commands after this, wherever UDCode puts the tab. */
- (void)setNextResponder:(NSResponder *)responder
{
	if (self.commands == nil || responder == self.commands) {
		[super setNextResponder:responder];
		return;
	}
	[self.commands setNextResponder:responder];
	[super setNextResponder:self.commands];
}

#pragma mark Reading

/* The forms the process names, and the models and flows it imports (their
 * forms its tasks may be done with), from beside its file: what deploying it
 * sends with it, and so what it is checked with. */
- (NSDictionary<NSString *, NSData *> *)formsBeside
{
	NSURL *directory = [_document.fileURL URLByDeletingLastPathComponent];
	NSMutableDictionary *forms = [NSMutableDictionary dictionary];
	NSXMLDocument *document = self.processEditor.editor.document;
	NSArray *names = [WKDEmbeddedForms(document) arrayByAddingObjectsFromArray:[WFModelForms importsOfProcess:[document XMLData]]];
	for (NSString *name in directory != nil ? names : @[]) {
		NSData *bytes = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:name]];
		if (bytes != nil) {
			[forms setObject:bytes forKey:name];
		}
	}
	return forms;
}

/* The parts, over the first text that is a process: the process editor
 * has no undo manager (the text's undo is the undo). */
- (void)makePartsWithData:(NSData *)data error:(NSError **)error
{
	WKDProcessEditor *processEditor = [[WKDProcessEditor alloc] initWithData:data undoManager:nil error:error];
	if (processEditor == nil) {
		return;
	}
	self.processEditor = processEditor;
	__weak WKUProcessEditorViewController *weakSelf = self;
	processEditor.fileName = [_document.fileURL lastPathComponent];
	processEditor.resourcesBeside = ^NSDictionary *{
		return [weakSelf formsBeside];
	};
	/* Checked again, as a deployment of the file with what is beside it. */
	[processEditor checkNow];
	void (^refused)(NSString *) = ^(NSString *reason) {
		[weakSelf note:reason];
	};
	/* An expression's problem as it is typed: said, not beeped at. */
	void (^explained)(NSString *) = ^(NSString *problem) {
		[weakSelf note:problem];
	};

	self.canvasController = [[WKDCanvasViewController alloc] initWithProcessEditor:processEditor];
	self.canvasController.refused = refused;
	self.paletteController = [[WKDPaletteViewController alloc] init];
	self.paletteController.title = @"Elements";
	self.paletteController.chosen = ^(WKDLook *tool) {
		[weakSelf.canvasController armTool:tool];
		[weakSelf closeLibrary];
	};
	self.canvasController.toolUsed = ^{
		[weakSelf.paletteController choosePointer];
	};
	self.outlineController = [[WKDOutlineViewController alloc] initWithProcessEditor:processEditor];
	self.outlineController.processChosen = ^{
		[weakSelf showInspector:weakSelf.processInspectorController];
	};
	self.inspectorController = [[WKDInspectorViewController alloc] initWithProcessEditor:processEditor showingProcess:NO];
	self.inspectorController.title = @"Element";
	self.processInspectorController = [[WKDInspectorViewController alloc] initWithProcessEditor:processEditor
	                                                                             showingProcess:YES];
	self.processInspectorController.title = @"Process";
	for (WKDInspectorViewController *inspector in @[ self.inspectorController, self.processInspectorController ]) {
		inspector.refused = refused;
		inspector.explained = explained;
	}
	self.commands = [[WKDProcessCommands alloc] initWithProcessEditor:processEditor];
	self.commands.host = self;
	/* In the chain from now on, wherever the tab already is. */
	[self setNextResponder:[super nextResponder]];

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(processDidChange:) name:WKDProcessEditorDidChangeNotification
	             object:processEditor];
	[center addObserver:self selector:@selector(selectionDidChange:) name:WKDSelectionDidChangeNotification
	             object:processEditor.selection];
	[center addObserver:self selector:@selector(problemsDidChange:) name:WKDProcessEditorProblemsDidChangeNotification
	             object:processEditor];
	[self findIssues];
}

/* The text read into the process editor; or, when it is no process, why.
 * A process with no diagram is laid out as it is first read: written,
 * one change of its text. */
- (void)read
{
	NSData *data = [[_document.textModel getValue] ?: @"" dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error = nil;
	BOOL first = self.processEditor == nil;
	_reading = YES;
	if (first) {
		[self makePartsWithData:data error:&error];
	}
	BOOL read = first ? self.processEditor != nil : [self.processEditor readData:data error:&error];
	_reading = NO;
	self.problem = read ? nil
		: [NSString stringWithFormat:@"This is not a BPMN process that can be shown: %@",
		   [error localizedRecoverySuggestion] ?: [error localizedDescription] ?: @"it cannot be read."];
	if (read && first && self.processEditor.laidOut) {
		[self write];
	}
	[self show];
}

/* The text changed, not by the parts: read again, at once while the tab
 * shows (an undo), a moment later while it does not (typed in a tab of
 * its text, each key would be a read of the whole process). */
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

/* The process changed: written once the change is done, so one action is
 * one edit of the text, one undo. */
- (void)processDidChange:(NSNotification *)notification
{
	[self updateStatus];
	if (_reading) {
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
	[self performSelector:@selector(write) withObject:nil afterDelay:0];
}

- (void)write
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
	if (self.processEditor == nil || self.problem != nil) {
		return;
	}
	NSString *text = [[NSString alloc] initWithData:[self.processEditor data] encoding:NSUTF8StringEncoding];
	if (text == nil) {
		return;
	}
	_writing = YES;
	WKUWriteText(_document.textModel, text);
	_writing = NO;
}

#pragma mark Showing

/* The outline and the canvas in the tab; or why there are none. */
- (void)show
{
	if (![self isViewLoaded]) {
		return;
	}
	BOOL shown = self.problem == nil && self.processEditor != nil;
	if (shown) {
		if ([self.canvasController.view superview] != self.canvasHost) {
			WKDFillHost(self.canvasHost, self.canvasController.view);
			WKDFillHost(self.outlineHost, self.outlineController.view);
			[self.canvasController scrollToContent];
		}
	} else {
		[self.problemLabel setStringValue:self.problem ?: @""];
	}
	[self.editorView setHidden:!shown];
	[self.problemView setHidden:shown];
	[self updateStatus];
}

- (void)selectionDidChange:(NSNotification *)notification
{
	/* An element chosen: its inspector to the front. */
	if ([self.processEditor.selection.selectedIds count] == 1) {
		[self showInspector:self.inspectorController];
	}
	[self updateStatus];
}

- (void)showInspector:(NSViewController *)inspector
{
	if ([[self view] window] != nil) {
		[_workbench showEditorInspector:inspector];
	}
}

- (void)closeLibrary
{
	[_workbench closeLibrary];
}

- (void)updateStatus
{
	if (self.processEditor == nil) {
		self.status = nil;
	} else {
		NSString *problem = self.processEditor.problem;
		NSUInteger selected = [self.processEditor.selection.selectedIds count];
		NSMutableArray *parts = [NSMutableArray array];
		if (_note != nil) {
			[parts addObject:_note];
		}
		[parts addObject:problem == nil ? @"The engine runs this process."
		                                : [NSString stringWithFormat:@"Not runnable: %@", problem]];
		if (selected > 1) {
			[parts addObject:[NSString stringWithFormat:@"%lu selected", (unsigned long)selected]];
		}
		self.status = [parts componentsJoinedByString:@" — "];
	}
	[self.statusField setStringValue:self.status ?: @""];
}

- (void)note:(NSString *)note
{
	_note = [note copy];
	[self updateStatus];
}

/* The outline keeps its width as the tab is resized, the canvas taking
 * the difference. */
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
	return subview != self.outlineHost;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
	return MAX(proposed, WKUOutlineMinimum);
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
	[_issueElements removeAllObjects];
	NSString *text = [_document.textModel getValue] ?: @"";
	for (WFProblem *problem in self.problem == nil ? self.processEditor.problems : @[]) {
		NSInteger line = MAX((NSInteger)problem.line, 1);
		NSRange at = problem.elementId != nil
			? [text rangeOfString:[NSString stringWithFormat:@"id=\"%@\"", problem.elementId]]
			: NSMakeRange(NSNotFound, 0);
		if (at.location != NSNotFound) {
			line = [_document.textModel getPositionAt:(NSInteger)at.location].line;
		}
		NSString *message = problem.resourceName != nil && ![problem.resourceName isEqualToString:self.processEditor.fileName ?: @"process.bpmn"]
			? [NSString stringWithFormat:@"%@: %@", problem.resourceName, problem.message] : problem.message;
		[items addObject:[[UDDiagnosticItem alloc] initWithLine:line column:0 message:message
		                                               severity:UDDiagnosticSeverityError source:WKUIssueSource]];
		if (problem.elementId != nil) {
			[_issueElements setObject:problem.elementId forKey:[NSString stringWithFormat:@"%ld %@", (long)line, message]];
		}
	}
	[_document.diagnosticStore setDiagnostics:items forSource:WKUIssueSource];
}

#pragma mark The window's panes (UDEditorPanes)

- (NSArray<NSViewController *> *)inspectorViewControllers
{
	if (self.processEditor == nil || self.problem != nil) {
		return @[];
	}
	return @[ self.inspectorController, self.processInspectorController ];
}

/* An SF Symbol on macOS; on GNUstep, which has none, the designer's badges. */
- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController
{
	BOOL element = viewController == self.inspectorController;
#ifndef GNUSTEP
	if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
		return [NSImage imageWithSystemSymbolName:element ? @"slider.horizontal.3" : @"gearshape"
		                 accessibilityDescription:viewController.title];
	}
#endif
	return element ? WKUTabImage(WKDTabBadge(@"E", 0.20, 0.50, 0.90))
	               : WKUTabImage(WKDTabBadge(@"P", 0.40, 0.48, 0.58));
}

- (NSViewController *)libraryViewController
{
	return self.processEditor != nil && self.problem == nil ? self.paletteController : nil;
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic
{
	NSString *elementId = [_issueElements objectForKey:[NSString stringWithFormat:@"%ld %@", (long)diagnostic.line,
	                                                    diagnostic.message]];
	if (elementId == nil) {
		return;
	}
	/* The process's own: its inspector; an element of it: selected. */
	if ([elementId isEqualToString:WKDAttribute(self.processEditor.editor.model.process, @"id")]) {
		[self showInspector:self.processInspectorController];
	} else if ([self.processEditor.editor elementWithId:elementId] != nil) {
		self.processEditor.selection.selectedIds = @[ elementId ];
	}
}

#pragma mark The commands' host

- (void)commands:(WKDProcessCommands *)commands refused:(NSString *)reason
{
	if (reason != nil) {
		NSBeep();
	}
	[self note:reason];
}

- (void)commands:(WKDProcessCommands *)commands say:(NSString *)status
{
	[self note:status];
}

- (void)commands:(WKDProcessCommands *)commands alert:(NSString *)message detail:(NSString *)detail
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:message];
	[alert setInformativeText:detail ?: @""];
	NSWindow *window = [[self view] window];
	if (window != nil) {
		[alert beginSheetModalForWindow:window completionHandler:nil];
	} else {
		[self note:message];
	}
}

- (NSURL *)documentURLForCommands:(WKDProcessCommands *)commands
{
	return _document.fileURL;
}

/* The DMN files beside the process open in a tab of this extension's, as
 * they stand there; the rest are read from beside it. */
- (NSDictionary<NSString *, NSString *> *)editedResourcesForCommands:(WKDProcessCommands *)commands
{
	NSString *directory = [[_document.fileURL URLByDeletingLastPathComponent] path];
	NSMutableDictionary *edited = [NSMutableDictionary dictionary];
	for (WKUDecisionEditorViewController *tab in [WKUDecisionEditorViewController openTabs]) {
		NSURL *url = tab.document.fileURL;
		if (directory != nil && url != nil && [[[url URLByDeletingLastPathComponent] path] isEqualToString:directory]) {
			[edited setObject:[tab.document.textModel getValue] ?: @"" forKey:[url lastPathComponent]];
		}
	}
	return edited;
}

/* A form in a tab of its own (the XForms extension's editor, where it is
 * installed); a DMN file in this extension's decision editor, the decision
 * added to it when the file has not got it, and shown. */
- (void)commands:(WKDProcessCommands *)commands open:(NSURL *)url decision:(NSString *)decision
{
	[_workbench showURL:url];
	if (decision != nil) {
		WKUDecisionEditorViewController *tab = [WKUDecisionEditorViewController tabOfURL:url];
		if (tab == nil) {
			[self note:[NSString stringWithFormat:@"%@ is not DMN that can be shown.", [url lastPathComponent]]];
			return;
		}
		[tab showDecision:decision];
	}
	[self note:nil];
}

- (void)commands:(WKDProcessCommands *)commands rename:(NSString *)elementId
{
	[self.canvasController beginRenaming:elementId];
}

- (void)commandsDidArrange:(WKDProcessCommands *)commands
{
	[self.canvasController scrollToContent];
}

#pragma mark Actions

- (IBAction)zoomIn:(id)sender
{
	[self.canvasController zoomIn:sender];
}

- (IBAction)zoomOut:(id)sender
{
	[self.canvasController zoomOut:sender];
}

- (IBAction)actualSize:(id)sender
{
	[self.canvasController actualSize:sender];
}

- (IBAction)zoomToFit:(id)sender
{
	[self.canvasController zoomToFit:sender];
}

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
	if (sel_isEqual(action, @selector(showAsText:))) {
		return YES;
	}
	return self.processEditor != nil && self.problem == nil;
}

@end

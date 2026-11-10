/*
 * UDCode's BPMN and DMN extension against UDCode's own document and text
 * model (its SDK): a process, and a DMN file, is its document's text, each
 * change one edit of it, the text's undo undoing it; the inspectors are the
 * window's pane, the palette its Library, the engine's problems the
 * document's issues; a text that cannot be shown says why.
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDDiagnosticStore.h>
#import <UDCodeKit/UDLanguageMode.h>
#import <UDCodeKit/UDLanguageConfiguration.h>
#import <UDPieceTable/UDTextModel.h>
#import "WKUExtension.h"
#import "WKUProcessEditorViewController.h"
#import "WKUDecisionEditorViewController.h"
#import "WKUTextEdits.h"
#import "WKDProcessEditor.h"
#import "WKDCanvasViewController.h"
#import "WKDPaletteViewController.h"
#import "WKDInspectorViewController.h"
#import "WKDDecisionEditor.h"
#import "WKDColumnViewController.h"
#import "WKDDecisionListViewController.h"
#import "WKDRuleGridViewController.h"
#import "WKDFixtures.h"

/* The window's side of what a tab asks of it: what it was asked to show,
 * and a DMN file's tab made for a URL shown, as UDCode's would be. */
@interface WKUTestWorkbench : NSObject
@property (nonatomic, strong) NSMutableArray<UDCodeDocument *> *shownAsText;
@property (nonatomic, strong) NSMutableArray<NSURL *> *shownURLs;
@property (nonatomic, strong) NSMutableArray *tabs;
@property (nonatomic, strong) NSMutableArray<NSViewController *> *inspectorsShown;
@property (nonatomic) NSUInteger librariesClosed;
@end

@implementation WKUTestWorkbench
- (instancetype)init
{
	if ((self = [super init])) {
		_shownAsText = [NSMutableArray array];
		_shownURLs = [NSMutableArray array];
		_tabs = [NSMutableArray array];
		_inspectorsShown = [NSMutableArray array];
	}
	return self;
}
- (void)showDocumentAsText:(UDCodeDocument *)document { [_shownAsText addObject:document]; }
- (BOOL)showEditorInspector:(NSViewController *)inspector { [_inspectorsShown addObject:inspector]; return YES; }
- (void)closeLibrary { _librariesClosed++; }
- (void)showURL:(NSURL *)url
{
	[_shownURLs addObject:url];
	if ([[url pathExtension] isEqualToString:@"dmn"] && [WKUDecisionEditorViewController tabOfURL:url] == nil) {
		NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL] ?: @"";
		UDCodeDocument *document = [[UDCodeDocument alloc] initWithText:text fileURL:url languageMode:nil];
		[_tabs addObject:[[WKUDecisionEditorViewController alloc] initWithDocument:document workbench:(id<UDWorkbench>)self]];
	}
}
@end

@interface WKUTests : XCTestCase
@end

@implementation WKUTests
{
	UDCodeDocument *_document;
	WKUTestWorkbench *_workbench;
	NSWindow *_window;
	NSUInteger _edits;
}

- (void)setUp
{
	[super setUp];
	[NSApplication sharedApplication];
	_workbench = [[WKUTestWorkbench alloc] init];
	_edits = 0;
}

- (void)tearDown
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_window orderOut:nil];
	[super tearDown];
}

- (void)countEdit:(NSNotification *)notification
{
	_edits++;
}

- (void)spin:(NSTimeInterval)seconds
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (UDCodeDocument *)documentOfText:(NSString *)text at:(NSURL *)url
{
	UDCodeDocument *document = [[UDCodeDocument alloc] initWithText:text fileURL:url languageMode:nil];
	if (document.textModel.undoManager == nil) {
		document.textModel.undoManager = [[NSUndoManager alloc] init];
	}
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(countEdit:)
	                                             name:UDTextModelDidChangeNotification object:document.textModel];
	return document;
}

/* A tab's view in a window, as UDCode's tab would have it. */
- (void)show:(NSViewController *)tab
{
	_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 700) styleMask:NSWindowStyleMaskTitled
	                                        backing:NSBackingStoreBuffered defer:YES];
	[_window setReleasedWhenClosed:NO];
	[[tab view] setFrame:[[_window contentView] bounds]];
	[[_window contentView] addSubview:[tab view]];
}

- (WKUProcessEditorViewController *)openProcess:(NSString *)text at:(NSURL *)url
{
	_document = [self documentOfText:text at:url];
	WKUProcessEditorViewController *tab = [[WKUProcessEditorViewController alloc]
		initWithDocument:_document workbench:(id<UDWorkbench>)_workbench];
	[self show:tab];
	return tab;
}

- (WKUDecisionEditorViewController *)openDecisions:(NSString *)text
{
	_document = [self documentOfText:text at:nil];
	WKUDecisionEditorViewController *tab = [[WKUDecisionEditorViewController alloc]
		initWithDocument:_document workbench:(id<UDWorkbench>)_workbench];
	[self show:tab];
	return tab;
}

- (UDLanguageMode *)modeNamed:(NSString *)identifier
{
	return [[UDLanguageMode alloc] initWithIdentifier:identifier displayName:identifier fileExtensions:@[]
	                                     languageFunc:NULL highlightsQuery:nil indentsQuery:nil lspLanguageID:nil
	                            languageServerCommand:nil defaultNewDocumentText:@""
	                            languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
	                                       keyHandler:nil extension:nil];
}

- (NSString *)temporaryDirectory
{
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	return directory;
}

#pragma mark - The extension

- (void)testAProcessOrDecisionsAreKnownByTheirText
{
	XCTAssertTrue([WKUExtension textIsAProcess:WKDModellerFile]);
	XCTAssertFalse([WKUExtension textIsAProcess:WKDDecisionsFile]);
	XCTAssertTrue([WKUExtension textIsDecisions:WKDDecisionsFile]);
	XCTAssertFalse([WKUExtension textIsDecisions:@"<plist/>"]);
}

- (void)testEachModesDocumentGetsItsEditorAndAnyOtherNone
{
	WKUExtension *extension = [[WKUExtension alloc] init];
	UDCodeDocument *process = [[UDCodeDocument alloc] initWithText:WKDModellerFile fileURL:nil
	                                                  languageMode:[self modeNamed:@"bpmn"]];
	XCTAssertTrue([[extension workbench:(id<UDWorkbench>)_workbench editorForDocument:process]
		isKindOfClass:[WKUProcessEditorViewController class]]);
	UDCodeDocument *decisions = [[UDCodeDocument alloc] initWithText:WKDDecisionsFile fileURL:nil
	                                                    languageMode:[self modeNamed:@"dmn"]];
	XCTAssertTrue([[extension workbench:(id<UDWorkbench>)_workbench editorForDocument:decisions]
		isKindOfClass:[WKUDecisionEditorViewController class]]);
	UDCodeDocument *other = [[UDCodeDocument alloc] initWithText:@"some notes" fileURL:nil
	                                                languageMode:[self modeNamed:@"bpmn"]];
	XCTAssertNil([extension workbench:(id<UDWorkbench>)_workbench editorForDocument:other],
	             @"a .bpmn file that is no process opens as text");
}

- (void)testTheEditorMenusItemsComeFromTheXIBEachWithAnAction
{
	NSArray *items = [WKUExtension editorMenuItems];
	XCTAssertGreaterThan([items count], (NSUInteger)20);
	NSMutableArray *titles = [NSMutableArray array];
	for (NSMenuItem *item in items) {
		if ([item isSeparatorItem]) {
			continue;
		}
		[titles addObject:[item title]];
		XCTAssertTrue([item action] != NULL || [item hasSubmenu], @"%@", [item title]);
		XCTAssertEqualObjects([item keyEquivalent], @"", @"UDCode's own keys stay its own: %@", [item title]);
	}
	XCTAssertTrue([titles containsObject:@"Arrange"] && [titles containsObject:@"Add Rule"], @"%@", titles);
}

#pragma mark - The text edits

- (void)testTheEditsMakeTheTextWhereverItsEndIs
{
	NSArray *cases = @[ @[ @"a\nb\n", @"a\nb" ], @[ @"a\nb", @"a\nb\n" ], @[ @"a", @"a\nb" ], @[ @"a\nb\nc", @"a" ],
	                    @[ @"a\nb\n", @"x\ny" ], @[ @"", @"a\n" ], @[ @"a\n", @"" ], @[ @"a\n\n\n", @"a\n" ] ];
	for (NSArray *pair in cases) {
		UDCodeDocument *document = [self documentOfText:pair[0] at:nil];
		WKUWriteText(document.textModel, pair[1]);
		XCTAssertEqualObjects([document.textModel getValue], pair[1], @"from %@", [pair[0] description]);
	}
}

- (void)testTheEditsAreOnePerRunOfChangedLines
{
	UDCodeDocument *document = [self documentOfText:@"a\nb\nc\nd\ne\n" at:nil];
	NSString *wanted = @"a\nB\nc\nd\nE\nf\n";
	XCTAssertEqual([WKUEditsToText(document.textModel, wanted) count], (NSUInteger)2);
	XCTAssertTrue(WKUWriteText(document.textModel, wanted));
	XCTAssertEqualObjects([document.textModel getValue], wanted);
	XCTAssertFalse(WKUWriteText(document.textModel, wanted), @"the same text: nothing to write");
}

#pragma mark - A process's tab

- (void)testAProcessOpensWithItsPartsInTheWindowsPanes
{
	WKUProcessEditorViewController *tab = [self openProcess:WKDModellerFile at:nil];
	XCTAssertNotNil(tab.processEditor);
	XCTAssertNil(tab.problem);
	XCTAssertEqual([tab.canvasController.view superview] != nil, YES, @"the canvas in the tab");
	NSArray *inspectors = [tab inspectorViewControllers];
	XCTAssertEqualObjects([inspectors valueForKey:@"title"], (@[ @"Element", @"Process" ]));
	for (NSViewController *inspector in inspectors) {
		XCTAssertNotNil([tab imageForInspectorViewController:inspector], @"%@", inspector.title);
	}
	XCTAssertEqual([tab libraryViewController], (NSViewController *)tab.paletteController);
	XCTAssertEqualObjects([_document.textModel getValue], WKDModellerFile, @"opened, the text as it was");
	XCTAssertEqual(_edits, (NSUInteger)0);
	XCTAssertEqual([[tab view] nextResponder], (NSResponder *)tab, @"the tab's controller after its view");
	XCTAssertEqual([tab nextResponder], (NSResponder *)tab.commands, @"the Editor menu's commands after it");
	XCTAssertGreaterThan([tab.status length], (NSUInteger)0);
}

- (void)testAChangeIsOneEditOfTheTextAndTheTextsUndoUndoesIt
{
	WKUProcessEditorViewController *tab = [self openProcess:WKDModellerFile at:nil];
	tab.processEditor.selection.selectedIds = @[ @"review" ];
	XCTAssertEqualObjects([_workbench.inspectorsShown lastObject], tab.inspectorController, @"its inspector in front");
	[tab.processEditor.editor setName:@"Check" of:@"review"];
	[self spin:0.1];
	XCTAssertTrue([[_document.textModel getValue] containsString:@"name=\"Check\""]);
	XCTAssertEqual(_edits, (NSUInteger)1, @"one change, one edit of the text");
	[tab undo:nil];
	[self spin:0.1];
	XCTAssertFalse([[_document.textModel getValue] containsString:@"name=\"Check\""]);
	XCTAssertEqualObjects([tab.processEditor.editor.model nodeWithId:@"review"].name, @"Review", @"read again after the undo");
	XCTAssertEqualObjects(tab.processEditor.selection.selectedIds, @[ @"review" ], @"still selected");
	[tab redo:nil];
	[self spin:0.1];
	XCTAssertEqualObjects([tab.processEditor.editor.model nodeWithId:@"review"].name, @"Check");
}

- (void)testTheTextChangedAsTextIsReadAgainAndANoProcessSaysWhy
{
	WKUProcessEditorViewController *tab = [self openProcess:WKDModellerFile at:nil];
	NSString *text = [_document.textModel getValue];
	WKUWriteText(_document.textModel, [text stringByReplacingOccurrencesOfString:@"name=\"Review\""
	                                                                  withString:@"name=\"Typed\""]);
	[self spin:0.5];
	XCTAssertEqualObjects([tab.processEditor.editor.model nodeWithId:@"review"].name, @"Typed");
	WKUWriteText(_document.textModel, @"<bpmn:definitions");
	[self spin:0.5];
	XCTAssertTrue([tab.problem hasPrefix:@"This is not a BPMN process"], @"%@", tab.problem);
	XCTAssertEqual([[tab inspectorViewControllers] count], (NSUInteger)0);
	XCTAssertNil([tab libraryViewController]);
	[tab showAsText:nil];
	XCTAssertEqual([_workbench.shownAsText firstObject], _document);
	WKUWriteText(_document.textModel, text);
	[self spin:0.5];
	XCTAssertNil(tab.problem, @"a process again");
	XCTAssertEqual([[tab inspectorViewControllers] count], (NSUInteger)2);
}

- (void)testAProcessWithNoDiagramIsLaidOutAsOneEdit
{
	WKUProcessEditorViewController *tab = [self openProcess:WKDUndrawnFile at:nil];
	XCTAssertNil(tab.problem);
	XCTAssertEqual(_edits, (NSUInteger)1, @"its diagram written into the text");
	XCTAssertTrue([[_document.textModel getValue] containsString:@"BPMNShape"]);
	XCTAssertTrue(_document.textModel.undoManager.canUndo);
}

- (void)testThePalettesToolIsArmedAndTheLibraryClosed
{
	WKUProcessEditorViewController *tab = [self openProcess:WKDModellerFile at:nil];
	[[tab libraryViewController] view];
	XCTAssertNotNil(tab.paletteController.chosen);
	tab.paletteController.chosen(nil);
	XCTAssertEqual(_workbench.librariesClosed, (NSUInteger)1);
}

/* What the engine refuses, an issue at its element's line; chosen in the
 * Issues navigator, the element selected. */
- (void)testTheEnginesProblemsAreTheDocumentsIssues
{
	NSString *broken = [[WKDModellerFile stringByReplacingOccurrencesOfString:@"<bpmn:userTask id=\"review\""
	                                                                withString:@"<bpmn:serviceTask id=\"review\""]
		stringByReplacingOccurrencesOfString:@"</bpmn:userTask>" withString:@"</bpmn:serviceTask>"];
	WKUProcessEditorViewController *tab = [self openProcess:broken at:nil];
	[tab.processEditor checkNow];
	XCTAssertGreaterThan([tab.processEditor.problems count], (NSUInteger)0);
	NSArray *issues = _document.diagnosticStore.allDiagnostics;
	XCTAssertEqual([issues count], [tab.processEditor.problems count]);
	UDDiagnosticItem *issue = [issues firstObject];
	XCTAssertEqual(issue.line, (NSInteger)2, @"the line its element is on");
	tab.processEditor.selection.selectedIds = @[];
	[tab revealDiagnostic:issue];
	XCTAssertEqualObjects(tab.processEditor.selection.selectedIds, @[ @"review" ]);
}

/* The forms beside the file are checked with it, as deploying it would. */
- (void)testTheProcessIsCheckedWithTheFormsBesideIt
{
	NSString *directory = [self temporaryDirectory];
	NSString *withForm = [WKDModellerFile stringByReplacingOccurrencesOfString:@"<bpmn:userTask id=\"review\" name=\"Review\""
	                                                                withString:@"<bpmn:userTask id=\"review\" name=\"Review\" camunda:formKey=\"embedded:deployment:review.xhtml\""];
	NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"order.bpmn"]];
	WKUProcessEditorViewController *alone = [self openProcess:withForm at:url];
	XCTAssertTrue([[[alone.processEditor.problems valueForKey:@"message"] componentsJoinedByString:@"\n"]
		containsString:@"review.xhtml"], @"its form is missing: %@", alone.processEditor.problems);
	NSData *form = [@"<html xmlns=\"http://www.w3.org/1999/xhtml\"><head/><body/></html>" dataUsingEncoding:NSUTF8StringEncoding];
	[form writeToFile:[directory stringByAppendingPathComponent:@"review.xhtml"] atomically:NO];
	WKUProcessEditorViewController *tab = [self openProcess:withForm at:url];
	XCTAssertFalse([[[tab.processEditor.problems valueForKey:@"message"] componentsJoinedByString:@"\n"]
		containsString:@"review.xhtml"], @"%@", tab.processEditor.problems);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* Edit Decision: the DMN file beside the process, made for the decision,
 * in a tab of its own, the decision shown. */
- (void)testEditDecisionOpensTheDecisionsTab
{
	NSString *directory = [self temporaryDirectory];
	NSString *withTask = [[WKDModellerFile stringByReplacingOccurrencesOfString:@"<bpmn:userTask id=\"review\" name=\"Review\""
	                                                                  withString:@"<bpmn:businessRuleTask id=\"review\" name=\"Review\" camunda:decisionRef=\"approve\""]
		stringByReplacingOccurrencesOfString:@"</bpmn:userTask>" withString:@"</bpmn:businessRuleTask>"];
	NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"order.bpmn"]];
	WKUProcessEditorViewController *tab = [self openProcess:withTask at:url];
	tab.processEditor.selection.selectedIds = @[ @"review" ];
	[tab.commands editDecision:nil];
	NSURL *opened = [_workbench.shownURLs lastObject];
	XCTAssertEqualObjects([opened pathExtension], @"dmn", @"%@", _workbench.shownURLs);
	WKUDecisionEditorViewController *decisions = [WKUDecisionEditorViewController tabOfURL:opened];
	XCTAssertNotNil(decisions);
	XCTAssertEqualObjects(decisions.decisionEditor.decisionId, @"approve");
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

#pragma mark - A DMN file's tab

- (void)testDecisionsOpenWithTheColumnAsAnInspector
{
	WKUDecisionEditorViewController *tab = [self openDecisions:WKDDecisionsFile];
	XCTAssertNil(tab.problem);
	XCTAssertEqualObjects(tab.decisionEditor.decisionId, @"dish");
	XCTAssertEqualObjects([[tab inspectorViewControllers] valueForKey:@"title"], (@[ @"Column" ]));
	XCTAssertNotNil([tab imageForInspectorViewController:tab.columnController]);
	XCTAssertEqual([tab nextResponder], (NSResponder *)tab.listController, @"the Decision menu's actions after it");
	XCTAssertEqual([tab.listController nextResponder], (NSResponder *)tab.gridController);
	tab.decisionEditor.column = 1;
	XCTAssertEqualObjects([_workbench.inspectorsShown lastObject], tab.columnController, @"a column chosen: its inspector");
	XCTAssertEqual(_edits, (NSUInteger)0);
}

- (void)testADecisionChangeIsOneEditAndTheTextsUndoUndoesIt
{
	WKUDecisionEditorViewController *tab = [self openDecisions:WKDDecisionsFile];
	NSUInteger rules = [tab.decisionEditor.decision.rules count];
	[tab.gridController addRule:nil];
	[self spin:0.1];
	XCTAssertEqual(_edits, (NSUInteger)1);
	XCTAssertEqual([tab.decisionEditor.decision.rules count], rules + 1);
	[tab undo:nil];
	[self spin:0.1];
	XCTAssertEqual([tab.decisionEditor.decision.rules count], rules, @"read again after the undo");
	XCTAssertEqualObjects(tab.decisionEditor.decisionId, @"dish");
	[tab showDecision:@"extra"];
	[self spin:0.1];
	XCTAssertEqualObjects(tab.decisionEditor.decisionId, @"extra", @"made, and chosen");
	XCTAssertTrue([[_document.textModel getValue] containsString:@"id=\"extra\""]);
}

- (void)testATextThatIsNotDMNSaysWhy
{
	WKUDecisionEditorViewController *tab = [self openDecisions:@"<definitions"];
	XCTAssertNil(tab.decisionEditor);
	XCTAssertTrue([tab.problem hasPrefix:@"This is not DMN"], @"%@", tab.problem);
	XCTAssertEqual([[tab inspectorViewControllers] count], (NSUInteger)0);
}

@end

#import "WKDWindowController.h"
#import "WKDProcessEditor.h"
#import "WKDAppDelegate.h"
#import "WKDDecisionDocument.h"
#import "WKDDecisions.h"
#import "WKDDeployment.h"
#import "WKDDocument.h"
#import "WKDEditor.h"
#import "WKDInspectorView.h"
#import "WKDPane.h"
#import "WKDRenderer.h"
#import "WKDXML.h"
#import "WDSession.h"
/* XFormsDesignKit, and its tab bar, which this app's panes share: the
 * framework's headers on macOS, its installed tree's on GNUstep (the
 * GNUmakefile names the directories). */
#if __has_include(<XFormsDesignKit/DMTabBar.h>)
#import <XFormsDesignKit/XFormsDesignKit.h>
#import <XFormsDesignKit/DMTabBar.h>
#import <XFormsDesignKit/DMTabBarItem.h>
#else
#import "XFormsDesignKit.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"
#endif

static const double WKDLeftWidth = 230;
static const double WKDRightWidth = 360;
static const double WKDSideMinimum = 170;
static const double WKDCentreMinimum = 320;

@implementation WKDWindowController
{
	WKDInspectorView *_inspector;
	WKDInspectorView *_processInspector;
	/* What the last change refused, shown until the next. */
	NSString *_note;
}

- (instancetype)init
{
	return [super initWithWindowNibPath:WKDNibPath(@"DesignerWindow") owner:self];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (WKDDocument *)designerDocument
{
	return (WKDDocument *)[self document];
}

- (WKDProcessEditor *)processEditor
{
	return [self designerDocument].processEditor;
}

- (WKDEditor *)editor
{
	return [self processEditor].editor;
}

#pragma mark Putting the parts in their places

/* A bar of drawn badges, a tab each; the colours are RDLKit's and the
 * XForms Designer's, grouped by role. */
static void
WKDFillTabBar(NSView *host, id target, SEL action, NSArray<NSArray *> *pages)
{
	DMTabBar *bar = (DMTabBar *)host;
	if (![bar isKindOfClass:[DMTabBar class]]) {
		return;
	}
	NSMutableArray *items = [NSMutableArray array];
	NSUInteger tag = 0;
	for (NSArray *page in pages) {
		DMTabBarItem *item = [DMTabBarItem tabBarItemWithIcon:WKDTabBadge(page[0], [page[2] doubleValue],
		                                                                   [page[3] doubleValue], [page[4] doubleValue])
		                                                  tag:tag++];
		item.toolTip = page[1];
		[items addObject:item];
	}
	bar.tabBarItems = items;
	[bar setTarget:target action:action];
	bar.selectedIndex = 0;
}

/* The bar sends itself; its selected index is the tab's. */
static void
WKDSelectTab(id sender, NSTabView *tabView)
{
	if ([sender isKindOfClass:[DMTabBar class]]) {
		NSInteger index = (NSInteger)[(DMTabBar *)sender selectedIndex];
		if (index >= 0 && index < [tabView numberOfTabViewItems]) {
			[tabView selectTabViewItemAtIndex:index];
		}
	}
}

- (void)leftTabChanged:(id)sender
{
	WKDSelectTab(sender, self.leftTabView);
}

- (void)rightTabChanged:(id)sender
{
	WKDSelectTab(sender, self.rightTabView);
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	WKDProcessEditor *processEditor = [self processEditor];
	__weak WKDWindowController *weakSelf = self;
	void (^refused)(NSString *) = ^(NSString *reason) {
		[weakSelf note:reason];
	};

	_canvasController = [[WKDCanvasViewController alloc] initWithProcessEditor:processEditor];
	WKDFillHost(self.canvasHost, _canvasController.view);
	_canvasController.refused = refused;
	_paletteController = [[WKDPaletteViewController alloc] init];
	WKDFillHost(self.paletteHost, _paletteController.view);
	_paletteController.chosen = ^(WKDLook *tool) {
		[weakSelf.canvasController armTool:tool];
	};
	_canvasController.toolUsed = ^{
		[weakSelf.paletteController choosePointer];
	};
	_outlineController = [[WKDOutlineViewController alloc] initWithProcessEditor:processEditor];
	WKDFillHost(self.outlineHost, _outlineController.view);
	_outlineController.processChosen = ^{
		[weakSelf showProcessInspector:weakSelf];
	};
	_problemsController = [[WKDProblemsViewController alloc] initWithProcessEditor:processEditor];
	WKDFillHost(self.problemsHost, _problemsController.view);

	/* An expression's problem as it is typed: said, not beeped at. */
	void (^explained)(NSString *) = ^(NSString *problem) {
		[weakSelf explain:problem];
	};
	_inspector = [[WKDInspectorView alloc] initWithFrame:[self.inspectorHost bounds]];
	_inspector.editor = [self editor];
	_inspector.refused = refused;
	_inspector.explained = explained;
	WKDFillHostScrolling(self.inspectorHost, _inspector);
	_processInspector = [[WKDInspectorView alloc] initWithFrame:[self.processHost bounds]];
	_processInspector.editor = [self editor];
	_processInspector.refused = refused;
	_processInspector.explained = explained;
	WKDFillHostScrolling(self.processHost, _processInspector);

	WKDFillTabBar(self.leftTabBar, self, @selector(leftTabChanged:), @[
		@[ @"O", @"Outline", @0.40, @0.48, @0.58 ],
		@[ @"+", @"Insert", @0.20, @0.50, @0.90 ],
		@[ @"!", @"Problems", @0.90, @0.45, @0.15 ] ]);
	WKDFillTabBar(self.rightTabBar, self, @selector(rightTabChanged:), @[
		@[ @"E", @"Element", @0.20, @0.50, @0.90 ],
		@[ @"P", @"Process", @0.40, @0.48, @0.58 ] ]);

	/* The Editor menu's commands, after this in the responder chain. */
	_commands = [[WKDProcessCommands alloc] initWithProcessEditor:processEditor];
	_commands.host = self;
	[_commands setNextResponder:[self nextResponder]];
	[self setNextResponder:_commands];

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(processDidChange:) name:WKDProcessEditorDidChangeNotification
	             object:processEditor];
	[center addObserver:self selector:@selector(selectionDidChange:) name:WKDSelectionDidChangeNotification
	             object:processEditor.selection];
	[center addObserver:self selector:@selector(problemsDidChange:) name:WKDProcessEditorProblemsDidChangeNotification
	             object:processEditor];
	[self setDefaultPaneWidths];
	[self showInspectors];
	[_canvasController scrollToContent];
	[[self window] makeFirstResponder:_canvasController.canvas];
}

- (void)setDefaultPaneWidths
{
	double width = NSWidth([self.split bounds]), divider = [self.split dividerThickness];
	if (width < WKDLeftWidth + WKDRightWidth + 2 * divider + WKDCentreMinimum) {
		return;
	}
	[self.split setPosition:WKDLeftWidth ofDividerAtIndex:0];
	[self.split setPosition:width - WKDRightWidth - divider ofDividerAtIndex:1];
}

#pragma mark Following the process editor

- (NSString *)processId
{
	return WKDAttribute([self editor].model.process, @"id");
}

- (NSString *)selectedId
{
	NSArray *selected = [self processEditor].selection.selectedIds;
	return [selected count] == 1 ? [selected firstObject] : nil;
}

- (void)showInspectors
{
	_inspector.elementId = [self selectedId];
	_processInspector.elementId = [self processId];
	[self updateStatus];
}

- (void)processDidChange:(NSNotification *)notification
{
	/* An element renamed in the inspector: selected under its new id. */
	NSString *shown = _inspector.elementId;
	WKDSelection *selection = [self processEditor].selection;
	if (shown != nil && [selection.selectedIds count] == 0 && [[self editor] elementWithId:shown] != nil) {
		selection.selectedIds = @[ shown ];
	}
	[_inspector reload];
	[self showInspectors];
}

- (void)selectionDidChange:(NSNotification *)notification
{
	/* An element chosen: its inspector to the front. */
	if ([self selectedId] != nil) {
		[self showElementInspector:self];
	}
	[self showInspectors];
}

- (void)problemsDidChange:(NSNotification *)notification
{
	[self updateStatus];
}

- (void)updateStatus
{
	NSString *problem = [self designerDocument].problem;
	NSString *state = problem == nil ? @"The engine runs this process." : [NSString stringWithFormat:@"Not runnable: %@", problem];
	NSUInteger selected = [[self processEditor].selection.selectedIds count];
	NSMutableArray *parts = [NSMutableArray array];
	if (_note != nil) {
		[parts addObject:_note];
	}
	[parts addObject:state];
	if (selected > 1) {
		[parts addObject:[NSString stringWithFormat:@"%lu selected", (unsigned long)selected]];
	}
	self.status = [parts componentsJoinedByString:@" — "];
}

- (void)note:(NSString *)note
{
	_note = [note copy];
	[self updateStatus];
}

- (void)explain:(NSString *)problem
{
	_note = [problem copy];
	[self updateStatus];
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
	_note = nil;
	self.status = status;
}

- (void)commands:(WKDProcessCommands *)commands alert:(NSString *)message detail:(NSString *)detail
{
	[self alert:message detail:detail];
}

- (NSURL *)documentURLForCommands:(WKDProcessCommands *)commands
{
	return [[self designerDocument] fileURL];
}

- (NSDictionary<NSString *, NSString *> *)editedResourcesForCommands:(WKDProcessCommands *)commands
{
	return [self editedResources];
}

- (void)commands:(WKDProcessCommands *)commands rename:(NSString *)elementId
{
	[_canvasController beginRenaming:elementId];
}

- (void)commandsDidArrange:(WKDProcessCommands *)commands
{
	[_canvasController scrollToContent];
}

/* In this app: a form in the form editor (an XFDDocument, Info.plist's
 * XForms Form type), a DMN file in the decision editor (a
 * WKDDecisionDocument), the decision added to it when the file has not
 * got it; each brought forward when it is open already. */
- (void)commands:(WKDProcessCommands *)commands open:(NSURL *)url decision:(NSString *)decision
{
	NSString *name = [url lastPathComponent];
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES
		completionHandler:^(NSDocument *opened, BOOL wasOpen, NSError *error) {
		if (opened == nil || (decision != nil && ![opened isKindOfClass:[WKDDecisionDocument class]])) {
			[self alert:[NSString stringWithFormat:@"%@ could not be opened.", name]
			     detail:[error localizedDescription] ?: [url path]];
			return;
		}
		if (decision != nil) {
			WKDDecisionDocument *decisions = (WKDDecisionDocument *)opened;
			if ([decisions.editor decisionWithId:decision] == nil) {
				[decisions.editor addDecisionTable:YES withId:decision];
			}
			[decisions showDecision:decision];
		}
		[self note:nil];
		self.status = [NSString stringWithFormat:@"%@ is open in the %@ editor.", name, decision != nil ? @"decision" : @"form"];
	}];
}

#pragma mark The View menu

- (IBAction)zoomIn:(id)sender
{
	[_canvasController zoomIn:sender];
}

- (IBAction)zoomOut:(id)sender
{
	[_canvasController zoomOut:sender];
}

- (IBAction)actualSize:(id)sender
{
	[_canvasController actualSize:sender];
}

- (IBAction)zoomToFit:(id)sender
{
	[_canvasController zoomToFit:sender];
}

#pragma mark Deploying

- (void)alert:(NSString *)message detail:(NSString *)detail
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:message];
	[alert setInformativeText:detail ?: @""];
	[alert beginSheetModalForWindow:[self window] completionHandler:nil];
}

- (IBAction)deploy:(id)sender
{
	WKDDocument *document = [self designerDocument];
	NSString *problem = document.problem;
	if (problem != nil) {
		[self alert:@"The engine would not run this process." detail:problem];
		return;
	}
	NSString *processId = [self processId];
	NSURL *file = [document fileURL];
	NSString *fileName = document.resourceName ?: [file lastPathComponent]
		?: [processId stringByAppendingPathExtension:@"bpmn"];
	NSArray<NSString *> *missing = nil;
	NSDictionary *resources = WKDDeploymentResources([self editor].document, fileName,
	                                                 [file URLByDeletingLastPathComponent], [self editedResources],
	                                                 &missing);
	if (resources == nil) {
		[self alert:@"The process's forms are missing."
		     detail:[NSString stringWithFormat:@"%@ must be beside the process%@: %@.",
		             [missing count] == 1 ? @"This form" : @"These forms",
		             file == nil ? @", which must be saved first" : @"",
		             [missing componentsJoinedByString:@", "]]];
		return;
	}
	NSString *name = WKDAttribute([self editor].model.process, @"name");
	[[WKDAppDelegate shared] withSession:^(WDSession *session) {
		[self deploy:resources named:[name length] > 0 ? name : processId key:processId on:session];
	}];
}

- (void)deploy:(NSDictionary *)resources named:(NSString *)name key:(NSString *)key on:(WDSession *)session
{
	[self note:nil];
	self.status = [NSString stringWithFormat:@"Deploying to %@…", [session.serviceURL host]];
	[session invoke:@"Deploy" on:nil parameters:@{ @"Name": name, @"Resources": resources }
	     completion:^(id result, NSError *error) {
		if (error != nil) {
			[self updateStatus];
			[self alert:@"Could not deploy." detail:[error localizedDescription]];
			return;
		}
		/* The version the process has now: a new one, or -- unchanged
		 * since it was last deployed -- the one it had. */
		NSFetchRequest *latest = [NSFetchRequest fetchRequestWithEntityName:@"WFDefinitionRecord"];
		[latest setPredicate:[NSPredicate predicateWithFormat:@"key == %@", key]];
		[latest setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"version" ascending:NO] ]];
		[latest setFetchLimit:1];
		[session fetch:latest completion:^(NSArray *objects, NSError *fetchError) {
			id version = [[objects firstObject] valueForKey:@"version"];
			self->_note = version != nil ? [NSString stringWithFormat:@"Deployed %@ as version %@", key, version]
			                       : [NSString stringWithFormat:@"Deployed %@", key];
			[self updateStatus];
		}];
	}];
}

/* The files beside the process open in an editor -- its forms in the form
 * editor, DMN files in the decision editor -- as they stand there, by name. */
- (NSDictionary<NSString *, NSString *> *)editedResources
{
	NSURL *directory = [[[self designerDocument] fileURL] URLByDeletingLastPathComponent];
	if (directory == nil) {
		return @{};
	}
	NSMutableDictionary *edited = [NSMutableDictionary dictionary];
	for (NSDocument *open in [[NSDocumentController sharedDocumentController] documents]) {
		NSURL *url = [open fileURL];
		if (url == nil || ![[[url URLByDeletingLastPathComponent] path] isEqualToString:[directory path]]) {
			continue;
		}
		if ([open isKindOfClass:[XFDDocument class]]) {
			[edited setObject:[(XFDDocument *)open hostXMLString] forKey:[url lastPathComponent]];
		} else if ([open isKindOfClass:[WKDDecisionDocument class]]) {
			[edited setObject:[[(WKDDecisionDocument *)open editor].document XMLStringWithOptions:NSXMLNodePrettyPrint]
			           forKey:[url lastPathComponent]];
		}
	}
	return edited;
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	if ([item action] == @selector(deploy:)) {
		return [self designerDocument].problem == nil;
	}
	return YES;
}

- (void)showTab:(NSInteger)index bar:(NSView *)bar tabs:(NSTabView *)tabs
{
	[tabs selectTabViewItemAtIndex:index];
	if ([bar isKindOfClass:[DMTabBar class]]) {
		((DMTabBar *)bar).selectedIndex = (NSUInteger)index;
	}
}

- (IBAction)showOutline:(id)sender
{
	[self showTab:0 bar:self.leftTabBar tabs:self.leftTabView];
}

- (IBAction)showPalette:(id)sender
{
	[self showTab:1 bar:self.leftTabBar tabs:self.leftTabView];
}

- (IBAction)showProblems:(id)sender
{
	[self showTab:2 bar:self.leftTabBar tabs:self.leftTabView];
}

- (IBAction)showElementInspector:(id)sender
{
	[self showTab:0 bar:self.rightTabBar tabs:self.rightTabView];
}

- (IBAction)showProcessInspector:(id)sender
{
	[self showTab:1 bar:self.rightTabBar tabs:self.rightTabView];
}

#pragma mark The split, as RDLKit's designer keeps it

/* A wider window is for a wider canvas: the side panes keep their width. */
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
	NSArray *panes = [splitView subviews];
	if (NSWidth([splitView bounds]) < WKDLeftWidth + WKDRightWidth + WKDCentreMinimum) {
		return YES;
	}
	return subview != [panes firstObject] && subview != [panes lastObject];
}

#if !defined(__APPLE__)
/* GNUstep's -adjustSubviews gives the last subview whatever is left and
 * never asks about it, so the inspector could not keep its width: the
 * space is shared out by hand, by the rule above. */
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
	NSArray<NSView *> *panes = [splitView subviews];
	NSUInteger count = [panes count];
	if (count == 0) {
		return;
	}
	NSRect bounds = [splitView bounds];
	double divider = [splitView dividerThickness];
	double total = NSWidth(bounds) - divider * (double)(count - 1);
	double spans[count];
	BOOL adjust[count];
	double adjustable = 0, fixed = 0;
	NSUInteger adjustableCount = 0;
	for (NSUInteger i = 0; i < count; i++) {
		spans[i] = NSWidth([panes[i] frame]);
		adjust[i] = ![splitView isSubviewCollapsed:panes[i]] && [self splitView:splitView shouldAdjustSizeOfSubview:panes[i]];
		if (adjust[i]) {
			adjustable += spans[i];
			adjustableCount++;
		} else {
			fixed += spans[i];
		}
	}
	double forAdjustable = MAX(0, total - fixed), x = 0;
	for (NSUInteger i = 0; i < count; i++) {
		double span = spans[i];
		if (adjust[i]) {
			span = adjustable > 0.5 ? forAdjustable * (spans[i] / adjustable) : forAdjustable / (double)adjustableCount;
		}
		[panes[i] setFrame:[splitView centerScanRect:NSMakeRect(x, 0, span, NSHeight(bounds))]];
		x += span + divider;
	}
}
#endif

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
	return index == 0 ? MAX(proposed, WKDSideMinimum) : proposed;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
	if (index != (NSInteger)[[splitView subviews] count] - 2) {
		return proposed;
	}
	return MIN(proposed, NSWidth([splitView bounds]) - WKDSideMinimum - [splitView dividerThickness]);
}

@end

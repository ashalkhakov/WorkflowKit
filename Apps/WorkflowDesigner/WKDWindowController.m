#import "WKDWindowController.h"
#import "WKDAppDelegate.h"
#import "WKDDeployment.h"
#import "WKDDocument.h"
#import "WKDEditor.h"
#import "WKDInspectorView.h"
#import "WKDPane.h"
#import "WKDRenderer.h"
#import "WKDXML.h"
#import "WDSession.h"
#import "ThirdParty/DMTabBar/DMTabBar.h"
#import "ThirdParty/DMTabBar/DMTabBarItem.h"

/* The side panes' widths, and how narrow they and the canvas may get. */
static const double WKDLeftWidth = 230;
static const double WKDRightWidth = 300;
static const double WKDSideMinimum = 170;
static const double WKDCentreMinimum = 320;

@implementation WKDWindowController
{
	WKDOutline *_outline;
	NSTextView *_problems;
	WKDInspectorView *_inspector;
	WKDInspectorView *_processInspector;
	/* What the last change refused, shown until the next. */
	NSString *_note;
}

- (instancetype)init
{
	return [super initWithWindowNibName:@"DesignerWindow"];
}

- (WKDDocument *)designerDocument
{
	return (WKDDocument *)[self document];
}

- (WKDEditor *)editor
{
	return [self designerDocument].editor;
}

#pragma mark Building

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

- (void)buildPanes
{
	WKDFillTabBar(self.leftTabBar, self, @selector(leftTabChanged:), @[
		@[ @"O", @"Outline", @0.40, @0.48, @0.58 ],
		@[ @"+", @"Insert", @0.20, @0.50, @0.90 ],
		@[ @"!", @"Problems", @0.90, @0.45, @0.15 ] ]);
	WKDFillTabBar(self.rightTabBar, self, @selector(rightTabChanged:), @[
		@[ @"E", @"Element", @0.20, @0.50, @0.90 ],
		@[ @"P", @"Process", @0.40, @0.48, @0.58 ] ]);

	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:[self.outlineHost bounds]];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutohidesScrollers:YES];
	[scroll setBorderType:NSNoBorder];
	NSOutlineView *outlineView = [[NSOutlineView alloc] initWithFrame:[[scroll contentView] bounds]];
	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
	[column setEditable:NO];
	[column setWidth:NSWidth([self.outlineHost bounds]) - 20];
	[outlineView addTableColumn:column];
	[outlineView setOutlineTableColumn:column];
	[outlineView setHeaderView:nil];
	[outlineView setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
	[scroll setDocumentView:outlineView];
	WKDFillHost(self.outlineHost, scroll);
	_outline = [[WKDOutline alloc] initWithOutlineView:outlineView];
	_outline.delegate = self;

	NSScrollView *problems = [[NSScrollView alloc] initWithFrame:[self.problemsHost bounds]];
	[problems setHasVerticalScroller:YES];
	[problems setBorderType:NSNoBorder];
	_problems = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, [problems contentSize].width, [problems contentSize].height)];
	[_problems setEditable:NO];
	[_problems setRichText:NO];
	[_problems setTextContainerInset:NSMakeSize(8, 8)];
	[_problems setAutoresizingMask:NSViewWidthSizable];
	[problems setDocumentView:_problems];
	WKDFillHost(self.problemsHost, problems);

	__weak WKDWindowController *weakSelf = self;
	void (^refused)(NSString *) = ^(NSString *reason) {
		[weakSelf note:reason];
	};
	_inspector = [[WKDInspectorView alloc] initWithFrame:[self.inspectorHost bounds]];
	_inspector.editor = [self editor];
	_inspector.refused = refused;
	WKDFillHostScrolling(self.inspectorHost, _inspector);
	_processInspector = [[WKDInspectorView alloc] initWithFrame:[self.processHost bounds]];
	_processInspector.editor = [self editor];
	_processInspector.refused = refused;
	WKDFillHostScrolling(self.processHost, _processInspector);
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

- (void)windowDidLoad
{
	[super windowDidLoad];
	self.canvas.delegate = self;
	self.palette.delegate = self;
	[self buildPanes];
	__weak WKDWindowController *weakSelf = self;
	[self editor].changed = ^{
		[weakSelf documentDidChange];
	};
	[self setDefaultPaneWidths];
	[self showDocument];
	[self.canvas scrollToContent];
	[[self window] makeFirstResponder:self.canvas];
}

#pragma mark Following the document

- (NSString *)processId
{
	return WKDAttribute([self editor].diagram.process, @"id");
}

- (void)showDocument
{
	WKDDiagram *diagram = [self editor].diagram;
	self.canvas.diagram = diagram;
	[_outline showDiagram:diagram];
	_processInspector.elementId = [self processId];
	[self selectionDidChange];
	NSString *problem = [self designerDocument].problem;
	[_problems setString:problem == nil ? @"The engine runs this process." : problem];
}

- (void)documentDidChange
{
	[[self designerDocument] check];
	/* An element renamed in the inspector: selected under its new id. */
	NSString *shown = _inspector.elementId;
	if (shown != nil && [self.canvas.selection count] == 1 && ![self.canvas.selection containsObject:shown]
	    && [[self editor] elementWithId:shown] != nil) {
		self.canvas.diagram = [self editor].diagram;
		self.canvas.selection = [NSSet setWithObject:shown];
	}
	[self showDocument];
}

/* The one element selected on the canvas, if one is. */
- (NSString *)selectedId
{
	return [self.canvas.selection count] == 1 ? [self.canvas.selection anyObject] : nil;
}

- (void)selectionDidChange
{
	NSString *selected = [self selectedId];
	_inspector.elementId = selected;
	_processInspector.elementId = [self processId];
	[_outline select:selected];
	[self updateStatus];
}

- (void)updateStatus
{
	NSString *problem = [self designerDocument].problem;
	NSString *state = problem == nil ? @"The engine runs this process." : [NSString stringWithFormat:@"Not runnable: %@", problem];
	NSUInteger selected = [self.canvas.selection count];
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
	if (note != nil) {
		NSBeep();
	}
	[self updateStatus];
}

#pragma mark Canvas, palette and outline

- (void)canvas:(WKDCanvasView *)canvas insert:(WKDLook *)tool at:(NSPoint)point
{
	NSString *reason = nil;
	NSString *added = [[self editor] insertNodeOfType:tool.type eventDefinition:tool.eventDefinition at:point
	                                            error:&reason];
	[self note:added == nil ? reason : nil];
	if (added != nil) {
		canvas.selection = [NSSet setWithObject:added];
	}
}

- (void)canvas:(WKDCanvasView *)canvas move:(NSArray<NSString *> *)elementIds by:(NSSize)offset
{
	_note = nil;
	[[self editor] moveElements:elementIds by:offset];
}

- (void)canvas:(WKDCanvasView *)canvas connect:(NSString *)sourceId to:(NSString *)targetId
{
	NSString *reason = nil;
	NSString *flow = [[self editor] connect:sourceId to:targetId error:&reason];
	[self note:flow == nil ? reason : nil];
	if (flow != nil) {
		canvas.selection = [NSSet setWithObject:flow];
	}
}

- (void)canvas:(WKDCanvasView *)canvas resize:(NSString *)elementId to:(NSRect)bounds
{
	_note = nil;
	[[self editor] resizeElement:elementId to:bounds];
}

- (void)canvas:(WKDCanvasView *)canvas delete:(NSArray<NSString *> *)elementIds
{
	_note = nil;
	[[self editor] deleteElements:elementIds];
}

- (void)canvasSelectionDidChange:(WKDCanvasView *)canvas
{
	/* An element chosen: its inspector to the front. */
	if ([self selectedId] != nil) {
		[self showElementInspector:self];
	}
	[self selectionDidChange];
}

- (void)canvasToolWasUsed:(WKDCanvasView *)canvas
{
	[self.palette choosePointer];
}

- (void)palette:(WKDPaletteView *)palette didChoose:(WKDLook *)tool
{
	self.canvas.tool = tool;
	[[self window] makeFirstResponder:self.canvas];
}

- (void)outline:(WKDOutline *)outline didSelect:(NSString *)elementId
{
	if ([elementId isEqualToString:[self processId]]) {
		self.canvas.selection = [NSSet set];
		[self showProcessInspector:self];
		return;
	}
	self.canvas.selection = [NSSet setWithObject:elementId];
}

#pragma mark Menus

- (IBAction)zoomIn:(id)sender
{
	self.canvas.zoom *= 1.25;
}

- (IBAction)zoomOut:(id)sender
{
	self.canvas.zoom /= 1.25;
}

- (IBAction)actualSize:(id)sender
{
	self.canvas.zoom = 1;
}

- (IBAction)arrange:(id)sender
{
	_note = nil;
	[[self editor] arrange];
	[self.canvas scrollToContent];
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
	                                                 [file URLByDeletingLastPathComponent], &missing);
	if (resources == nil) {
		[self alert:@"The process's forms are missing."
		     detail:[NSString stringWithFormat:@"%@ must be beside the process%@: %@.",
		             [missing count] == 1 ? @"This form" : @"These forms",
		             file == nil ? @", which must be saved first" : @"",
		             [missing componentsJoinedByString:@", "]]];
		return;
	}
	NSString *name = WKDAttribute([self editor].diagram.process, @"name");
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

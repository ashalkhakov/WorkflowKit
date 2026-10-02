#import "WKDWindowController.h"
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
#import "XFormsDesignKit.h"
/* XFormsDesignKit's, which this app's panes share. */
#import "DMTabBar.h"
#import "DMTabBarItem.h"

/* What the designer puts on the pasteboard: a BPMN document of the
 * elements copied, beside the same XML as text. */
static NSString * const WKDFragmentPasteboardType = @"local.workflowkit.bpmn-fragment";

/* The side panes' widths, and how narrow they and the canvas may get. */
static const double WKDLeftWidth = 230;
static const double WKDRightWidth = 360;
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
	/* Pastes since the last copy: each lands a step further down. */
	NSUInteger _pastes;
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

- (void)explain:(NSString *)problem
{
	_note = [problem copy];
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

- (void)canvas:(WKDCanvasView *)canvas reconnect:(NSString *)flowId atSource:(BOOL)atSource to:(NSString *)nodeId
{
	NSString *reason = nil;
	BOOL done = [[self editor] reconnect:flowId atSource:atSource to:nodeId error:&reason];
	[self note:done ? nil : reason];
}

- (void)canvas:(WKDCanvasView *)canvas moveBend:(NSUInteger)index of:(NSString *)flowId to:(NSPoint)point
{
	_note = nil;
	[[self editor] moveBend:index of:flowId to:point];
}

- (void)canvas:(WKDCanvasView *)canvas nudge:(NSArray<NSString *> *)elementIds by:(NSSize)offset
{
	_note = nil;
	[[self editor] nudgeElements:elementIds by:offset];
}

- (void)canvas:(WKDCanvasView *)canvas moveLabelOf:(NSString *)elementId by:(NSSize)offset
{
	_note = nil;
	[[self editor] moveLabelOf:elementId by:offset];
}

- (void)canvas:(WKDCanvasView *)canvas rename:(NSString *)elementId to:(NSString *)name
{
	_note = nil;
	[[self editor] setName:name of:elementId];
}

/* Rename, Change Type for one node, then the clipboard's. */
- (NSMenu *)canvasMenu:(WKDCanvasView *)canvas
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Element"];
	[menu setAutoenablesItems:NO];
	NSString *selected = [self selectedId];
	if (selected != nil) {
		[[menu addItemWithTitle:@"Rename" action:@selector(rename:) keyEquivalent:@""] setTarget:self];
		NSArray *types = [[self editor] typesFor:selected];
		if ([types count] > 0) {
			WKDShape *shape = [[self editor].diagram shapeWithId:selected];
			NSMenu *submenu = [[NSMenu alloc] initWithTitle:@"Change Type"];
			[submenu setAutoenablesItems:NO];
			for (WKDNodeType *type in types) {
				NSMenuItem *item = (NSMenuItem *)[submenu addItemWithTitle:type.title action:@selector(changeType:) keyEquivalent:@""];
				[item setTarget:self];
				[item setRepresentedObject:type];
				BOOL current = [type.type isEqualToString:shape.type]
					&& [type.eventDefinition ?: @"" isEqualToString:shape.eventDefinition ?: @""];
				[item setState:current ? NSControlStateValueOn : NSControlStateValueOff];
			}
			NSMenuItem *change = (NSMenuItem *)[menu addItemWithTitle:@"Change Type" action:NULL keyEquivalent:@""];
			[change setSubmenu:submenu];
		}
		[menu addItem:[NSMenuItem separatorItem]];
	}
	if ([[self selectedShapes] count] >= 2) {
		/* Several: lined up with the first selected, or spread out. */
		NSArray *groups = @[ @[ @"Align", @[ @[ @"Left Edges", @"alignLeftEdges:" ], @[ @"Centres", @"alignCentres:" ],
		                                    @[ @"Right Edges", @"alignRightEdges:" ], @[ @"Top Edges", @"alignTopEdges:" ],
		                                    @[ @"Middles", @"alignMiddles:" ], @[ @"Bottom Edges", @"alignBottomEdges:" ] ] ],
		                     @[ @"Distribute", @[ @[ @"Across", @"distributeAcross:" ], @[ @"Down", @"distributeDown:" ] ] ] ];
		for (NSArray *group in groups) {
			NSMenu *submenu = [[NSMenu alloc] initWithTitle:group[0]];
			[submenu setAutoenablesItems:NO];
			for (NSArray *entry in group[1]) {
				NSMenuItem *item = (NSMenuItem *)[submenu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1])
				                                             keyEquivalent:@""];
				[item setTarget:self];
				[item setEnabled:[self validateUserInterfaceItem:item]];
			}
			NSMenuItem *holder = (NSMenuItem *)[menu addItemWithTitle:group[0] action:NULL keyEquivalent:@""];
			[holder setSubmenu:submenu];
		}
		[menu addItem:[NSMenuItem separatorItem]];
	}
	for (NSArray *entry in @[ @[ @"Cut", NSStringFromSelector(@selector(cut:)) ],
	                          @[ @"Copy", NSStringFromSelector(@selector(copy:)) ],
	                          @[ @"Duplicate", NSStringFromSelector(@selector(duplicate:)) ],
	                          @[ @"Delete", NSStringFromSelector(@selector(delete:)) ] ]) {
		NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];
		[item setTarget:[entry[0] isEqualToString:@"Delete"] ? (id)self.canvas : self];
	}
	return menu;
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

- (IBAction)zoomToFit:(id)sender
{
	[self.canvas zoomToFit];
}

- (IBAction)rename:(id)sender
{
	if ([self selectedId] != nil) {
		[self.canvas beginRenaming:[self selectedId]];
	}
}

- (IBAction)changeType:(id)sender
{
	WKDNodeType *type = [sender representedObject];
	NSString *selected = [self selectedId];
	if (![type isKindOfClass:[WKDNodeType class]] || selected == nil) {
		return;
	}
	NSString *reason = nil;
	BOOL done = [[self editor] changeType:selected to:type error:&reason];
	[self note:done ? nil : reason];
}

#pragma mark Arranging several

/* The selected shapes, the anchor first. */
- (NSArray<NSString *> *)selectedShapes
{
	NSMutableArray *shapes = [NSMutableArray array];
	for (NSString *elementId in self.canvas.orderedSelection) {
		if ([[self editor].diagram shapeWithId:elementId] != nil) {
			[shapes addObject:elementId];
		}
	}
	return shapes;
}

- (void)align:(WKDAlignment)alignment
{
	_note = nil;
	if (![[self editor] alignElements:[self selectedShapes] to:alignment]) {
		[self note:@"Select two shapes or more to line up with the first."];
	}
}

- (IBAction)alignLeftEdges:(id)sender
{
	[self align:WKDAlignLeft];
}

- (IBAction)alignCentres:(id)sender
{
	[self align:WKDAlignCentre];
}

- (IBAction)alignRightEdges:(id)sender
{
	[self align:WKDAlignRight];
}

- (IBAction)alignTopEdges:(id)sender
{
	[self align:WKDAlignTop];
}

- (IBAction)alignMiddles:(id)sender
{
	[self align:WKDAlignMiddle];
}

- (IBAction)alignBottomEdges:(id)sender
{
	[self align:WKDAlignBottom];
}

- (IBAction)distributeAcross:(id)sender
{
	_note = nil;
	if (![[self editor] distributeElements:[self selectedShapes] vertically:NO]) {
		[self note:@"Select three shapes or more to spread out."];
	}
}

- (IBAction)distributeDown:(id)sender
{
	_note = nil;
	if (![[self editor] distributeElements:[self selectedShapes] vertically:YES]) {
		[self note:@"Select three shapes or more to spread out."];
	}
}

#pragma mark Clipboard

/* The selection as a fragment of BPMN; nil, with a beep, when there is
 * nothing in it to copy. */
- (NSXMLDocument *)fragmentOfSelection
{
	NSXMLDocument *fragment = [[self editor] fragmentOfElements:[self.canvas.selection allObjects]];
	if (fragment == nil) {
		NSBeep();
	}
	return fragment;
}

- (IBAction)copy:(id)sender
{
	NSXMLDocument *fragment = [self fragmentOfSelection];
	if (fragment == nil) {
		return;
	}
	NSString *xml = [fragment XMLStringWithOptions:NSXMLNodePrettyPrint];
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard declareTypes:@[ WKDFragmentPasteboardType, NSPasteboardTypeString ] owner:nil];
	[pasteboard setString:xml forType:WKDFragmentPasteboardType];
	[pasteboard setString:xml forType:NSPasteboardTypeString];
	_pastes = 0;
}

- (IBAction)cut:(id)sender
{
	if ([self fragmentOfSelection] != nil) {
		[self copy:sender];
		[[self editor] deleteElements:[self.canvas.selection allObjects]];
	}
}

/* Pasted a step further down each time, the elements pasted selected. */
- (void)pasteFragment:(NSXMLDocument *)fragment
{
	_pastes++;
	NSString *reason = nil;
	NSArray *added = [[self editor] paste:fragment offset:NSMakeSize(30.0 * _pastes, 30.0 * _pastes) error:&reason];
	[self note:added == nil ? reason : nil];
	if (added != nil) {
		self.canvas.selection = [NSSet setWithArray:added];
	}
}

- (IBAction)paste:(id)sender
{
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	NSString *xml = [pasteboard stringForType:WKDFragmentPasteboardType] ?: [pasteboard stringForType:NSPasteboardTypeString];
	NSXMLDocument *fragment = [xml length] > 0 ? [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL] : nil;
	if (fragment == nil) {
		[self note:@"The clipboard holds no BPMN to paste."];
		NSBeep();
		return;
	}
	[self pasteFragment:fragment];
}

- (IBAction)duplicate:(id)sender
{
	NSXMLDocument *fragment = [self fragmentOfSelection];
	if (fragment != nil) {
		_pastes = 0;
		[self pasteFragment:fragment];
	}
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

#pragma mark Forms

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

/* The element whose form is edited: the one selected, a user task or a
 * start event. */
- (NSXMLElement *)formElement
{
	NSString *elementId = [self selectedId];
	NSXMLElement *element = elementId != nil ? [[self editor] elementWithId:elementId] : nil;
	NSString *type = [element localName];
	return [type isEqualToString:@"userTask"] || [type isEqualToString:@"startEvent"] ? element : nil;
}

- (IBAction)editForm:(id)sender
{
	NSXMLElement *element = [self formElement];
	if (element == nil) {
		[self alert:@"Select a user task or a start event." detail:@"Their forms are what the form designer edits."];
		return;
	}
	NSURL *file = [[self designerDocument] fileURL];
	if (file == nil) {
		[self alert:@"Save the process first." detail:@"Its forms are kept beside it, and deployed with it."];
		return;
	}
	NSXMLDocument *document = [self editor].document;
	NSString *elementId = WKDAttribute(element, @"id");
	NSString *name = WKDEmbeddedFormOf(document, element);
	BOOL named = name != nil;
	if (!named) {
		name = [elementId stringByAppendingPathExtension:@"xhtml"];
	}
	NSURL *form = [[file URLByDeletingLastPathComponent] URLByAppendingPathComponent:name];
	if (![[NSFileManager defaultManager] fileExistsAtPath:[form path]]) {
		NSError *error = nil;
		NSXMLDocument *made = WKDGeneratedForm(document, elementId, &error);
		if (made == nil || ![[made XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement]
		                       writeToURL:form options:NSDataWritingAtomic error:&error]) {
			[self alert:[NSString stringWithFormat:@"Could not make %@.", name] detail:[error localizedDescription]];
			return;
		}
	}
	if (!named) {
		/* One change: the key that names it, undone like any other. */
		[[self editor] edit:elementId action:@"Form key" with:^(NSXMLElement *edited, NSXMLDocument *xml) {
			WKDSetQualifiedAttribute(xml, edited, WKDCamundaNamespace, @"formKey",
			                         [@"embedded:deployment:" stringByAppendingString:name]);
		}];
	}
	/* In this app, an XFDDocument (Info.plist's XForms Form type); brought
	 * forward when it is open already. */
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:form display:YES
		completionHandler:^(NSDocument *opened, BOOL wasOpen, NSError *error) {
		if (opened == nil) {
			[self alert:[NSString stringWithFormat:@"%@ could not be opened.", name]
			     detail:[error localizedDescription] ?: [form path]];
			return;
		}
		[self note:nil];
		self.status = [NSString stringWithFormat:@"%@ is open in the form editor.", name];
	}];
}

#pragma mark Decisions

/* The business rule task selected. */
- (NSXMLElement *)decisionElement
{
	NSString *elementId = [self selectedId];
	NSXMLElement *element = elementId != nil ? [[self editor] elementWithId:elementId] : nil;
	return [[element localName] isEqualToString:@"businessRuleTask"] ? element : nil;
}

- (IBAction)editDecision:(id)sender
{
	NSXMLElement *element = [self decisionElement];
	if (element == nil) {
		[self alert:@"Select a business rule task." detail:@"Its decision is what the decision editor edits."];
		return;
	}
	NSURL *file = [[self designerDocument] fileURL];
	if (file == nil) {
		[self alert:@"Save the process first." detail:@"Its decisions are kept beside it, and deployed with it."];
		return;
	}
	NSXMLDocument *document = [self editor].document;
	NSString *elementId = WKDAttribute(element, @"id");
	NSString *key = WKDQualifiedAttribute(document, element, WKDCamundaNamespace, @"decisionRef");
	if ([key hasPrefix:@"${"] || [key hasPrefix:@"#{"] || [key hasPrefix:@"="]) {
		[self alert:@"The task names its decision by an expression."
		     detail:@"Which decision it evaluates is known only as it runs."];
		return;
	}
	BOOL named = [key length] > 0;
	if (!named) {
		key = elementId;
	}
	NSURL *directory = [file URLByDeletingLastPathComponent];
	NSString *name = WKDDecisionFileDefining(key, directory, [self editedResources])
		?: [key stringByAppendingPathExtension:@"dmn"];
	NSURL *url = [directory URLByAppendingPathComponent:name];
	if (![[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
		/* A file of its own, whose one table is the decision. */
		WKDDmnEditor *made = [[WKDDmnEditor alloc] initWithDocument:[WKDDmnEditor newDecisionsDocument] undoManager:nil];
		NSString *first = [made.decisions firstObject].decisionId;
		NSString *title = WKDAttribute(element, @"name");
		[made renameDecision:first to:key error:NULL];
		[made setName:[title length] > 0 ? title : key of:key];
		NSError *error = nil;
		if (![[made.document XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement]
		        writeToURL:url options:NSDataWritingAtomic error:&error]) {
			[self alert:[NSString stringWithFormat:@"Could not make %@.", name] detail:[error localizedDescription]];
			return;
		}
	}
	if (!named) {
		[[self editor] edit:elementId action:@"Decision" with:^(NSXMLElement *edited, NSXMLDocument *xml) {
			WKDSetQualifiedAttribute(xml, edited, WKDCamundaNamespace, @"decisionRef", key);
		}];
	}
	/* In this app, a WKDDecisionDocument (Info.plist's DMN type); brought
	 * forward when it is open already, and the decision added to it when
	 * the file beside has that name but not the decision. */
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES
		completionHandler:^(NSDocument *opened, BOOL wasOpen, NSError *error) {
		if (![opened isKindOfClass:[WKDDecisionDocument class]]) {
			[self alert:[NSString stringWithFormat:@"%@ could not be opened.", name]
			     detail:[error localizedDescription] ?: [url path]];
			return;
		}
		WKDDecisionDocument *decisions = (WKDDecisionDocument *)opened;
		if ([decisions.editor decisionWithId:key] == nil) {
			[decisions.editor addDecisionTable:YES withId:key];
		}
		[decisions showDecision:key];
		[self note:nil];
		self.status = [NSString stringWithFormat:@"%@ is open in the decision editor.", name];
	}];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	if ([item action] == @selector(editForm:)) {
		return [self formElement] != nil;
	}
	if ([item action] == @selector(editDecision:)) {
		return [self decisionElement] != nil;
	}
	if ([item action] == @selector(deploy:)) {
		return [self designerDocument].problem == nil;
	}
	SEL action = [item action];
	if (action == @selector(copy:) || action == @selector(cut:) || action == @selector(duplicate:)) {
		return [self.canvas.selection count] > 0;
	}
	NSString *name = NSStringFromSelector(action);
	if ([name hasPrefix:@"align"]) {
		return [[self selectedShapes] count] >= 2;
	}
	if ([name hasPrefix:@"distribute"]) {
		return [[self selectedShapes] count] >= 3;
	}
	if (action == @selector(rename:)) {
		return [self selectedId] != nil;
	}
	if (action == @selector(paste:)) {
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		return [pasteboard availableTypeFromArray:@[ WKDFragmentPasteboardType, NSPasteboardTypeString ]] != nil;
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

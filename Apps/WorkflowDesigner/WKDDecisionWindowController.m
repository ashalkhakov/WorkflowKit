#import "WKDDecisionWindowController.h"
#import "WKDAppDelegate.h"
#import "WKDDecisionDocument.h"
#import "WKDDecisions.h"
#import "WKDExpressionField.h"
#import "WKDTableEditor.h"
#import "WKDXML.h"
#import "WDSession.h"

static NSString * const WKDNumberColumn = @"#";
static NSString * const WKDAnnotationColumn = @"annotation";

static const double WKDListWidth = 220;
static const double WKDEntryWidth = 170;
static const double WKDAnnotationWidth = 200;
static const double WKDStatusHeight = 24;

@interface WKDFlippedView : NSView
@end

@implementation WKDFlippedView

- (BOOL)isFlipped
{
	return YES;
}

@end

/* The grid: Backspace or Delete removes the selected rules. */
@interface WKDRuleTable : WKDCellTable
@end

@implementation WKDRuleTable

- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event charactersIgnoringModifiers];
	unichar key = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
	if ((key == NSDeleteCharacter || key == NSBackspaceCharacter || key == NSDeleteFunctionKey)
	    && [self selectedRow] >= 0) {
		[NSApp sendAction:@selector(delete:) to:nil from:self];
		return;
	}
	[super keyDown:event];
}

@end

/* The letter DMN heads a table with for its hit policy. */
static NSString *
WKDHitPolicyLetter(WKDDmnDecision *decision)
{
	NSDictionary *letters = @{ @"UNIQUE": @"U", @"FIRST": @"F", @"ANY": @"A", @"RULE ORDER": @"R",
	                           @"COLLECT": @"C", @"PRIORITY": @"P", @"OUTPUT ORDER": @"O" };
	NSDictionary *aggregations = @{ @"SUM": @"+", @"MIN": @"<", @"MAX": @">", @"COUNT": @"#" };
	NSString *letter = [letters objectForKey:decision.hitPolicy] ?: @"?";
	return [letter stringByAppendingString:[aggregations objectForKey:decision.aggregation ?: @""] ?: @""];
}

@implementation WKDDecisionWindowController
{
	NSTableView *_list;
	NSTextField *_nameField;
	NSTextField *_idField;
	NSTextField *_hitPolicyLabel;
	NSPopUpButton *_hitPolicy;
	NSPopUpButton *_requires;

	NSView *_tablePanel;
	WKDRuleTable *_grid;
	/* What the grid's columns were made for: rebuilt when it changes. */
	NSArray *_gridColumns;
	NSTextField *_columnTitle;
	NSTextField *_labelField;
	NSTextField *_expressionLabel;
	WKDExpressionField *_expressionField;
	NSTextField *_nameLabel;
	NSTextField *_outputNameField;
	NSPopUpButton *_typePopup;
	NSTextField *_variableLabel;
	NSTextField *_inputVariableField;
	NSArray<NSView *> *_columnControls;

	NSView *_literalPanel;
	NSTextField *_variableField;
	NSPopUpButton *_variableType;
	WKDExpressionField *_literalField;

	NSTextField *_status;
	NSString *_decisionId;
	/* The column the panel under the grid edits, among the decision's. */
	NSUInteger _column;
	/* What the last change refused, or a cell's problem as it is typed. */
	NSString *_note;
	/* The list being reloaded: gnustep-gui selects a row of its own as it
	 * does, which is not a choice. */
	BOOL _reloading;
}

- (instancetype)init
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1040, 620)
	                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
	                                                         | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
	                                                 backing:NSBackingStoreBuffered
	                                                   defer:YES];
	[window setMinSize:NSMakeSize(760, 420)];
	if ((self = [super initWithWindow:window])) {
		_column = NSNotFound;
		[window setDelegate:self];
		[self build];
		[window center];
	}
	return self;
}

- (WKDDecisionDocument *)decisionDocument
{
	return (WKDDecisionDocument *)[self document];
}

- (WKDDmnEditor *)editor
{
	return [self decisionDocument].editor;
}

- (WKDDmnDecision *)decision
{
	return _decisionId != nil ? [[self editor] decisionWithId:_decisionId] : nil;
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
	return [[self document] undoManager];
}

- (void)setDocument:(NSDocument *)document
{
	[super setDocument:document];
	if (document == nil) {
		return;
	}
	__weak WKDDecisionWindowController *weakSelf = self;
	[self editor].changed = ^{
		[weakSelf documentDidChange];
	};
	if (_decisionId == nil) {
		_decisionId = [[[self editor].decisions firstObject].decisionId copy];
	}
	[self refresh];
}

#pragma mark Building

static NSTextField *
WKDLabel(NSString *text, NSRect frame, BOOL bold)
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	[label setStringValue:text];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBordered:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setAlignment:bold ? NSTextAlignmentLeft : NSTextAlignmentRight];
	[label setFont:bold ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:11]];
	[label setTextColor:bold ? [NSColor textColor] : [NSColor secondaryLabelColor]];
	return label;
}

- (NSTextField *)field:(NSRect)frame action:(SEL)action
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
	[field setFont:[NSFont systemFontOfSize:11]];
	[[field cell] setScrollable:YES];
	[[field cell] setSendsActionOnEndEditing:YES];
	[field setTarget:self];
	[field setAction:action];
	return field;
}

- (NSPopUpButton *)popup:(NSRect)frame action:(SEL)action
{
	NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
	[popup setFont:[NSFont systemFontOfSize:11]];
	[popup setTarget:self];
	[popup setAction:action];
	return popup;
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action
{
	NSButton *button = [[NSButton alloc] initWithFrame:frame];
	[button setTitle:title];
	[button setBezelStyle:NSBezelStyleSmallSquare];
	[button setFont:[NSFont systemFontOfSize:11]];
	[button setTarget:self];
	[button setAction:action];
	return button;
}

- (WKDExpressionField *)expressionField:(NSRect)frame place:(WFExpressionPlace)place action:(SEL)action
{
	WKDExpressionField *field = [[WKDExpressionField alloc] initWithFrame:frame];
	field.place = place;
	field.delegate = self;
	field.target = self;
	field.action = action;
	return field;
}

- (void)build
{
	NSView *content = [[self window] contentView];
	NSRect bounds = [content bounds];
	NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, WKDStatusHeight, NSWidth(bounds),
	                                                                   NSHeight(bounds) - WKDStatusHeight)];
	[split setVertical:YES];
	[split setDividerStyle:NSSplitViewDividerStyleThin];
	[split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[split setDelegate:self];
	[content addSubview:split];

	_status = WKDLabel(@"", NSMakeRect(10, 4, NSWidth(bounds) - 20, 16), NO);
	[_status setAlignment:NSTextAlignmentLeft];
	[_status setAutoresizingMask:NSViewWidthSizable];
	[content addSubview:_status];

	double height = NSHeight([split bounds]);
	NSView *left = [[WKDFlippedView alloc] initWithFrame:NSMakeRect(0, 0, WKDListWidth, height)];
	NSView *right = [[WKDFlippedView alloc] initWithFrame:NSMakeRect(WKDListWidth + 1, 0,
	                                                                 NSWidth(bounds) - WKDListWidth - 1, height)];
	[split addSubview:left];
	[split addSubview:right];
	[self buildList:left];
	[self buildDetail:right];
}

- (void)buildList:(NSView *)pane
{
	double width = NSWidth([pane bounds]), height = NSHeight([pane bounds]);
	[pane addSubview:WKDLabel(@"Decisions", NSMakeRect(10, 8, width - 20, 18), YES)];
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(8, 30, width - 16, height - 66)];
	[scroll setBorderType:NSBezelBorder];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	_list = [[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]];
	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
	[column setEditable:NO];
	[column setWidth:[scroll contentSize].width - 4];
	[column setResizingMask:NSTableColumnAutoresizingMask];
	[_list addTableColumn:column];
	[_list setHeaderView:nil];
	[_list setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
	[_list setAllowsEmptySelection:NO];
	[_list setDataSource:self];
	[_list setDelegate:self];
	[scroll setDocumentView:_list];
	[pane addSubview:scroll];
	NSArray *buttons = @[ [self button:@"+ Table" frame:NSMakeRect(8, height - 30, 70, 22)
	                            action:@selector(addDecisionTable:)],
	                      [self button:@"+ Literal" frame:NSMakeRect(80, height - 30, 70, 22)
	                            action:@selector(addLiteralDecision:)],
	                      [self button:@"−" frame:NSMakeRect(152, height - 30, 28, 22)
	                            action:@selector(deleteDecision:)] ];
	for (NSButton *button in buttons) {
		[button setAutoresizingMask:NSViewMinYMargin];
		[pane addSubview:button];
	}
}

- (void)buildDetail:(NSView *)pane
{
	double width = NSWidth([pane bounds]), height = NSHeight([pane bounds]);
	[pane addSubview:WKDLabel(@"Name", NSMakeRect(8, 13, 70, 16), NO)];
	_nameField = [self field:NSMakeRect(84, 10, 260, 22) action:@selector(nameChanged:)];
	[pane addSubview:_nameField];
	[pane addSubview:WKDLabel(@"Id", NSMakeRect(350, 13, 30, 16), NO)];
	_idField = [self field:NSMakeRect(386, 10, 200, 22) action:@selector(idChanged:)];
	[pane addSubview:_idField];

	_hitPolicyLabel = WKDLabel(@"Hit policy", NSMakeRect(8, 43, 70, 16), NO);
	[pane addSubview:_hitPolicyLabel];
	_hitPolicy = [self popup:NSMakeRect(82, 38, 160, 26) action:@selector(hitPolicyChanged:)];
	for (NSArray *policy in WKDDmnHitPolicies()) {
		[_hitPolicy addItemWithTitle:policy[2]];
	}
	[pane addSubview:_hitPolicy];
	[pane addSubview:WKDLabel(@"Requires", NSMakeRect(250, 43, 60, 16), NO)];
	_requires = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(314, 38, 274, 26) pullsDown:YES];
	[_requires setFont:[NSFont systemFontOfSize:11]];
	[pane addSubview:_requires];

	NSRect panel = NSMakeRect(8, 72, width - 16, height - 80);
	_tablePanel = [[WKDFlippedView alloc] initWithFrame:panel];
	[_tablePanel setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[pane addSubview:_tablePanel];
	[self buildTable:_tablePanel];
	_literalPanel = [[WKDFlippedView alloc] initWithFrame:panel];
	[_literalPanel setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[pane addSubview:_literalPanel];
	[self buildLiteral:_literalPanel];
}

- (void)buildTable:(NSView *)panel
{
	double width = NSWidth([panel bounds]), height = NSHeight([panel bounds]);
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height - 92)];
	[scroll setBorderType:NSBezelBorder];
	[scroll setHasVerticalScroller:YES];
	[scroll setHasHorizontalScroller:YES];
	[scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	_grid = [[WKDRuleTable alloc] initWithFrame:[[scroll contentView] bounds]];
	[_grid setRowHeight:20];
	[_grid setAllowsMultipleSelection:YES];
	[_grid setAllowsEmptySelection:YES];
	[_grid setAllowsColumnReordering:NO];
	[_grid setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
	[_grid setGridStyleMask:NSTableViewSolidVerticalGridLineMask | NSTableViewSolidHorizontalGridLineMask];
	[_grid setDataSource:self];
	[_grid setDelegate:self];
	[_grid setTarget:self];
	[_grid setAction:@selector(gridClicked:)];
	/* Heard as it is typed: gnustep-gui does not pass a cell's typing on
	 * to the table's delegate. */
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cellTextDidChange:)
	                                             name:NSControlTextDidChangeNotification object:_grid];
	[scroll setDocumentView:_grid];
	[panel addSubview:scroll];

	double y = height - 86, x = 0;
	NSArray *rules = @[ @[ @"+ Rule", @"addRule:", @62 ], @[ @"Duplicate", @"duplicate:", @70 ],
	                    @[ @"− Rule", @"delete:", @62 ], @[ @"↑", @"moveRuleUp:", @28 ], @[ @"↓", @"moveRuleDown:", @28 ],
	                    @[ @"", @"", @16 ],
	                    @[ @"+ Input", @"addInput:", @66 ], @[ @"+ Output", @"addOutput:", @70 ],
	                    @[ @"− Column", @"deleteColumn:", @72 ], @[ @"←", @"moveColumnLeft:", @28 ],
	                    @[ @"→", @"moveColumnRight:", @28 ] ];
	for (NSArray *spec in rules) {
		double w = [spec[2] doubleValue];
		if ([spec[0] length] > 0) {
			NSButton *button = [self button:spec[0] frame:NSMakeRect(x, y, w, 22) action:NSSelectorFromString(spec[1])];
			[button setAutoresizingMask:NSViewMinYMargin];
			[panel addSubview:button];
		}
		x += w + 2;
	}

	y = height - 56;
	_columnTitle = WKDLabel(@"", NSMakeRect(0, y, width, 18), YES);
	[_columnTitle setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[panel addSubview:_columnTitle];
	y += 26;
	NSTextField *labelLabel = WKDLabel(@"Label", NSMakeRect(0, y + 3, 40, 16), NO);
	_labelField = [self field:NSMakeRect(44, y, 150, 22) action:@selector(columnLabelChanged:)];
	_expressionLabel = WKDLabel(@"Expression", NSMakeRect(198, y + 3, 66, 16), NO);
	_expressionField = [self expressionField:NSMakeRect(268, y, width - 268 - 300, 22)
	                                   place:WFExpressionPlaceExpression action:@selector(columnExpressionChanged:)];
	_expressionField.placeholderString = @"amount, order.total";
	_nameLabel = WKDLabel(@"Name", NSMakeRect(198, y + 3, 66, 16), NO);
	_outputNameField = [self field:NSMakeRect(268, y, width - 268 - 300, 22) action:@selector(columnNameChanged:)];
	NSTextField *typeLabel = WKDLabel(@"Type", NSMakeRect(width - 292, y + 3, 34, 16), NO);
	_typePopup = [self popup:NSMakeRect(width - 254, y - 2, 104, 26) action:@selector(columnTypeChanged:)];
	_variableLabel = WKDLabel(@"Variable", NSMakeRect(width - 148, y + 3, 52, 16), NO);
	_inputVariableField = [self field:NSMakeRect(width - 92, y, 92, 22) action:@selector(columnVariableChanged:)];
	[[_inputVariableField cell] setPlaceholderString:@"cellInput"];
	_columnControls = @[ labelLabel, _labelField, _expressionLabel, _expressionField, _nameLabel, _outputNameField,
	                     typeLabel, _typePopup, _variableLabel, _inputVariableField ];
	for (NSView *view in _columnControls) {
		NSUInteger mask = NSViewMinYMargin;
		if (view == _expressionField || view == _outputNameField) {
			mask |= NSViewWidthSizable;
		} else if (NSMinX([view frame]) > 300) {
			mask |= NSViewMinXMargin;
		}
		[view setAutoresizingMask:mask];
		[panel addSubview:view];
	}
}

- (void)buildLiteral:(NSView *)panel
{
	double width = NSWidth([panel bounds]);
	[panel addSubview:WKDLabel(@"Variable", NSMakeRect(0, 13, 70, 16), NO)];
	_variableField = [self field:NSMakeRect(76, 10, 200, 22) action:@selector(variableChanged:)];
	[panel addSubview:_variableField];
	[panel addSubview:WKDLabel(@"Type", NSMakeRect(284, 13, 34, 16), NO)];
	_variableType = [self popup:NSMakeRect(322, 8, 110, 26) action:@selector(variableTypeChanged:)];
	[panel addSubview:_variableType];
	[panel addSubview:WKDLabel(@"Expression", NSMakeRect(0, 45, 70, 16), NO)];
	_literalField = [self expressionField:NSMakeRect(76, 42, width - 76, 22) place:WFExpressionPlaceExpression
	                               action:@selector(literalChanged:)];
	_literalField.placeholderString = @"if income > 1000 then \"yes\" else \"no\"";
	[_literalField setAutoresizingMask:NSViewWidthSizable];
	[panel addSubview:_literalField];
	NSTextField *hint = WKDLabel(@"FEEL, or ${...} for Camunda 7's expressions. Its value is the variable's: "
	                             @"what the decision gives.", NSMakeRect(76, 70, width - 76, 16), NO);
	[hint setAlignment:NSTextAlignmentLeft];
	[hint setAutoresizingMask:NSViewWidthSizable];
	[panel addSubview:hint];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
	return MAX(proposed, 150);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
	return MIN(proposed, NSWidth([splitView bounds]) - 600);
}

#pragma mark Following the document

- (void)showDecision:(NSString *)decisionId
{
	if ([[self editor] decisionWithId:decisionId] != nil) {
		_decisionId = [decisionId copy];
		_column = NSNotFound;
	}
	[self refresh];
}

- (void)documentDidChange
{
	[[self decisionDocument] check];
	/* A decision gone -- deleted, or undone -- shows its neighbour. */
	if ([self decision] == nil) {
		NSArray *decisions = [self editor].decisions;
		NSInteger row = [_list selectedRow];
		WKDDmnDecision *next = [decisions count] == 0 ? nil
			: [decisions objectAtIndex:(NSUInteger)MIN(MAX(row, 0), (NSInteger)[decisions count] - 1)];
		_decisionId = [next.decisionId copy];
	}
	/* The grid's cell written is still being edited: shown once it is not. */
	if ([_grid editedRow] >= 0) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self refresh];
		});
		return;
	}
	[self refresh];
}

- (void)refresh
{
	NSArray *decisions = [self editor].decisions;
	_reloading = YES;
	[_list reloadData];
	NSUInteger index = [decisions indexOfObjectPassingTest:^BOOL(WKDDmnDecision *decision, NSUInteger i, BOOL *stop) {
		return [decision.decisionId isEqualToString:self->_decisionId];
	}];
	if (index != NSNotFound) {
		[_list selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
	}
	_reloading = NO;
	[self showDetail];
	[self updateStatus];
}

- (void)showDetail
{
	WKDDmnDecision *decision = [self decision];
	BOOL table = decision.isTable;
	for (NSControl *control in @[ _nameField, _idField, _requires ]) {
		[control setEnabled:decision != nil];
	}
	[_nameField setStringValue:decision.name ?: @""];
	[_idField setStringValue:decision.decisionId ?: @""];
	[_hitPolicyLabel setHidden:!table];
	[_hitPolicy setHidden:!table];
	[_tablePanel setHidden:!table];
	[_literalPanel setHidden:decision == nil || table];
	[self showRequirements:decision];
	if (table) {
		NSArray *policies = WKDDmnHitPolicies();
		NSInteger chosen = -1;
		for (NSUInteger i = 0; i < [policies count]; i++) {
			NSArray *policy = [policies objectAtIndex:i];
			if ([policy[0] isEqualToString:decision.hitPolicy]
			    && [policy[1] isEqualToString:decision.aggregation ?: @""]) {
				chosen = (NSInteger)i;
			}
		}
		/* One the engine does not evaluate, as the file has it. */
		while ([_hitPolicy numberOfItems] > (NSInteger)[policies count]) {
			[_hitPolicy removeItemAtIndex:[_hitPolicy numberOfItems] - 1];
		}
		if (chosen < 0) {
			[_hitPolicy addItemWithTitle:[NSString stringWithFormat:@"%@ %@", decision.hitPolicy,
			                              decision.aggregation ?: @""]];
			chosen = [_hitPolicy numberOfItems] - 1;
		}
		[_hitPolicy selectItemAtIndex:chosen];
		if (_column != NSNotFound && _column >= [decision.columns count]) {
			_column = [decision.columns count] > 0 ? [decision.columns count] - 1 : NSNotFound;
		}
		[self showGrid:decision];
		[self showColumn:decision];
	} else if (decision != nil) {
		[_variableField setStringValue:decision.variableName ?: @""];
		[self fillTypes:_variableType with:decision.variableType];
		if (![[_literalField stringValue] isEqualToString:decision.expression ?: @""]) {
			_literalField.stringValue = decision.expression ?: @"";
		}
	}
}

- (void)showRequirements:(WKDDmnDecision *)decision
{
	[_requires removeAllItems];
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *required in decision.required) {
		[names addObject:[[self editor] decisionWithId:required].title ?: required];
	}
	[_requires addItemWithTitle:[names count] > 0 ? [names componentsJoinedByString:@", "] : @"No other decision"];
	for (WKDDmnDecision *other in [self editor].decisions) {
		if (decision == nil || [other.decisionId isEqualToString:decision.decisionId]) {
			continue;
		}
		NSMenuItem *item = (NSMenuItem *)[[_requires menu] addItemWithTitle:other.title
		                                                            action:@selector(requirementToggled:)
		                                                     keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:other.decisionId];
		[item setState:[decision.required containsObject:other.decisionId] ? NSControlStateValueOn
		                                                                    : NSControlStateValueOff];
	}
}

- (void)fillTypes:(NSPopUpButton *)popup with:(NSString *)typeRef
{
	[popup removeAllItems];
	[popup addItemWithTitle:@"Any"];
	[popup addItemsWithTitles:WKDDmnTypes()];
	if ([typeRef length] > 0 && ![WKDDmnTypes() containsObject:typeRef]) {
		[popup addItemWithTitle:typeRef];
	}
	if ([typeRef length] > 0) {
		[popup selectItemWithTitle:typeRef];
	} else {
		[popup selectItemAtIndex:0];
	}
}

/* The value a type pop-up has chosen: nil for Any. */
static NSString *
WKDChosenType(NSPopUpButton *popup)
{
	return [popup indexOfSelectedItem] > 0 ? [popup titleOfSelectedItem] : nil;
}

#pragma mark The grid

- (NSString *)titleOf:(WKDDmnColumn *)column
{
	NSString *title = column.output ? [@"→ " stringByAppendingString:column.title] : column.title;
	return [column.typeRef length] > 0 ? [NSString stringWithFormat:@"%@ · %@", title, column.typeRef] : title;
}

- (void)showGrid:(WKDDmnDecision *)decision
{
	NSMutableArray *shape = [NSMutableArray arrayWithObject:decision.decisionId];
	for (WKDDmnColumn *column in decision.columns) {
		[shape addObject:[NSString stringWithFormat:@"%@:%d", column.columnId ?: @"", column.output]];
	}
	if (![shape isEqualToArray:_gridColumns]) {
		NSMutableDictionary *widths = [NSMutableDictionary dictionary];
		for (NSTableColumn *column in [_grid tableColumns]) {
			[widths setObject:@([column width]) forKey:[column identifier]];
		}
		for (NSTableColumn *column in [[_grid tableColumns] copy]) {
			[_grid removeTableColumn:column];
		}
		NSMutableArray *identifiers = [NSMutableArray arrayWithObject:WKDNumberColumn];
		for (WKDDmnColumn *column in decision.columns) {
			[identifiers addObject:[NSString stringWithFormat:@"%@:%d", column.columnId ?: @"", column.output]];
		}
		[identifiers addObject:WKDAnnotationColumn];
		for (NSUInteger i = 0; i < [identifiers count]; i++) {
			NSString *identifier = [identifiers objectAtIndex:i];
			NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
			BOOL number = [identifier isEqualToString:WKDNumberColumn];
			BOOL annotation = [identifier isEqualToString:WKDAnnotationColumn];
			double width = number ? 36 : annotation ? WKDAnnotationWidth : WKDEntryWidth;
			[column setWidth:[[widths objectForKey:identifier] doubleValue] ?: width];
			[column setMinWidth:number ? 30 : 60];
			[column setEditable:!number];
			[column setResizingMask:NSTableColumnUserResizingMask];
			/* From the left: what a heading is cut to is its start. */
			[[column headerCell] setAlignment:number ? NSTextAlignmentCenter : NSTextAlignmentLeft];
			[[column headerCell] setLineBreakMode:NSLineBreakByTruncatingTail];
			NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
			[cell setEditable:!number];
			[cell setFont:[NSFont systemFontOfSize:11]];
			[cell setLineBreakMode:NSLineBreakByTruncatingTail];
			if (number) {
				[cell setAlignment:NSTextAlignmentCenter];
				[cell setTextColor:[NSColor secondaryLabelColor]];
			} else if (!annotation && i - 1 < [decision.inputs count]) {
				[cell setPlaceholderString:@"-"];
			}
			[column setDataCell:cell];
			[_grid addTableColumn:column];
		}
		_gridColumns = shape;
	}
	NSArray *columns = [_grid tableColumns];
	[[[columns firstObject] headerCell] setStringValue:WKDHitPolicyLetter(decision)];
	for (NSUInteger i = 0; i < [decision.columns count]; i++) {
		[[[columns objectAtIndex:i + 1] headerCell] setStringValue:[self titleOf:[decision.columns objectAtIndex:i]]];
	}
	[[[columns lastObject] headerCell] setStringValue:@"Annotation"];
	[[_grid headerView] setNeedsDisplay:YES];
	NSIndexSet *selected = [_grid selectedRowIndexes];
	[_grid reloadData];
	if ([selected count] > 0 && [selected lastIndex] >= [decision.rules count]) {
		[_grid deselectAll:nil];
	}
}

/* The index among the decision's columns of a grid's column; NSNotFound
 * for the rule numbers and the annotations. */
- (NSUInteger)columnOf:(NSTableColumn *)tableColumn
{
	NSUInteger index = [[_grid tableColumns] indexOfObjectIdenticalTo:tableColumn];
	NSUInteger count = [[self decision].columns count];
	return index != NSNotFound && index >= 1 && index <= count ? index - 1 : NSNotFound;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == _list) {
		return (NSInteger)[[self editor].decisions count];
	}
	return (NSInteger)[[self decision].rules count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView == _list) {
		NSArray *decisions = [self editor].decisions;
		WKDDmnDecision *decision = row < (NSInteger)[decisions count] ? [decisions objectAtIndex:(NSUInteger)row] : nil;
		return decision.isTable ? decision.title : [decision.title stringByAppendingString:@"  (literal)"];
	}
	WKDDmnDecision *decision = [self decision];
	if (row < 0 || row >= (NSInteger)[decision.rules count]) {
		return @"";
	}
	WKDDmnRule *rule = [decision.rules objectAtIndex:(NSUInteger)row];
	if ([[tableColumn identifier] isEqualToString:WKDNumberColumn]) {
		return [NSString stringWithFormat:@"%ld", (long)row + 1];
	}
	if ([[tableColumn identifier] isEqualToString:WKDAnnotationColumn]) {
		return rule.annotation;
	}
	NSUInteger column = [self columnOf:tableColumn];
	if (column == NSNotFound || column >= [rule.entries count]) {
		return @"";
	}
	NSString *text = [rule.entries objectAtIndex:column];
	/* Coloured as the engine reads it, and plain while it is typed in. */
	BOOL edited = [_grid editedRow] == row
		&& [[_grid tableColumns] indexOfObjectIdenticalTo:tableColumn] == (NSUInteger)[_grid editedColumn];
	if (edited || [text length] == 0) {
		return text;
	}
	return WKDColouredExpression(text, [self placeOfColumn:column], [NSFont systemFontOfSize:11]);
}

- (WFExpressionPlace)placeOfColumn:(NSUInteger)column
{
	return column < [[self decision].inputs count] ? WFExpressionPlaceUnaryTests : WFExpressionPlaceExpression;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row
{
	WKDDmnDecision *decision = [self decision];
	if (tableView != _grid || row < 0 || row >= (NSInteger)[decision.rules count]) {
		return;
	}
	NSString *text = [object isKindOfClass:[NSAttributedString class]] ? [object string] : [object description] ?: @"";
	WKDDmnRule *rule = [decision.rules objectAtIndex:(NSUInteger)row];
	[self explain:nil];
	if ([[tableColumn identifier] isEqualToString:WKDAnnotationColumn]) {
		if (![text isEqualToString:rule.annotation]) {
			[[self editor] setAnnotation:text rule:(NSUInteger)row of:decision.decisionId];
		}
		return;
	}
	NSUInteger column = [self columnOf:tableColumn];
	if (column != NSNotFound && ![text isEqualToString:[rule.entries objectAtIndex:column]]) {
		[[self editor] setEntry:text rule:(NSUInteger)row column:column of:decision.decisionId];
	}
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView != _grid || [[tableColumn identifier] isEqualToString:WKDNumberColumn]) {
		return NO;
	}
	[self setCurrentColumn:[self columnOf:tableColumn]];
	return YES;
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{
	if (tableView == _grid) {
		[self setCurrentColumn:[self columnOf:tableColumn]];
	}
}

- (void)gridClicked:(id)sender
{
	NSInteger clicked = [_grid clickedColumn];
	if (clicked >= 0 && clicked < (NSInteger)[[_grid tableColumns] count]) {
		[self setCurrentColumn:[self columnOf:[[_grid tableColumns] objectAtIndex:(NSUInteger)clicked]]];
	}
}

- (void)setCurrentColumn:(NSUInteger)column
{
	if (column == NSNotFound || column == _column) {
		return;
	}
	_column = column;
	[self showColumn:[self decision]];
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
	NSUInteger column = tableView == _grid ? [self columnOf:tableColumn] : NSNotFound;
	WKDDmnDecision *decision = [self decision];
	if (column == NSNotFound || row < 0 || row >= (NSInteger)[decision.rules count]) {
		return nil;
	}
	NSString *text = [[decision.rules objectAtIndex:(NSUInteger)row].entries objectAtIndex:column];
	return [[WFFeelExpression problemInText:text place:[self placeOfColumn:column]] localizedDescription];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	if ([notification object] != _list || _reloading) {
		return;
	}
	NSInteger row = [_list selectedRow];
	NSArray *decisions = [self editor].decisions;
	if (row >= 0 && row < (NSInteger)[decisions count]) {
		NSString *chosen = [[decisions objectAtIndex:(NSUInteger)row] decisionId];
		if (![chosen isEqualToString:_decisionId]) {
			_decisionId = [chosen copy];
			_column = NSNotFound;
			[_grid deselectAll:nil];
			[self showDetail];
			[self updateStatus];
		}
	}
}

/* An entry being typed: what the engine says of it. */
- (void)cellTextDidChange:(NSNotification *)notification
{
	NSInteger edited = [_grid editedColumn];
	NSUInteger column = edited >= 0 && edited < (NSInteger)[[_grid tableColumns] count]
		? [self columnOf:[[_grid tableColumns] objectAtIndex:(NSUInteger)edited]] : NSNotFound;
	NSText *text = [[notification userInfo] objectForKey:@"NSFieldEditor"];
	if (column == NSNotFound || ![text isKindOfClass:[NSText class]]) {
		return;
	}
	NSError *problem = [WFFeelExpression problemInText:[text string] place:[self placeOfColumn:column]];
	[self explain:problem != nil ? [NSString stringWithFormat:@"%@: %@",
		[[self decision].columns objectAtIndex:column].title, [problem localizedDescription]] : nil];
}

/* An expression field being typed in: what the engine says of it. */
- (void)controlTextDidChange:(NSNotification *)notification
{
	id field = [notification object];
	if ([field isKindOfClass:[WKDExpressionField class]]) {
		[self explain:[(WKDExpressionField *)field problem]];
	}
}

#pragma mark The column

- (void)showColumn:(WKDDmnDecision *)decision
{
	WKDDmnColumn *column = _column < [decision.columns count] ? [decision.columns objectAtIndex:_column] : nil;
	for (NSView *view in _columnControls) {
		[view setHidden:column == nil];
	}
	if (column == nil) {
		[_columnTitle setStringValue:@"Click a column's heading, or one of its cells, to edit the column here."];
		[_columnTitle setFont:[NSFont systemFontOfSize:11]];
		return;
	}
	BOOL output = column.output;
	NSUInteger number = output ? _column - [decision.inputs count] + 1 : _column + 1;
	[_columnTitle setFont:[NSFont boldSystemFontOfSize:12]];
	[_columnTitle setStringValue:[NSString stringWithFormat:output ? @"Output %lu: %@" : @"Input %lu: %@",
	                              (unsigned long)number, column.title]];
	[_expressionLabel setHidden:output];
	[_expressionField setHidden:output];
	[_variableLabel setHidden:output];
	[_inputVariableField setHidden:output];
	[_nameLabel setHidden:!output];
	[_outputNameField setHidden:!output];
	[_labelField setStringValue:column.label ?: @""];
	if (output) {
		[_outputNameField setStringValue:column.name ?: @""];
	} else {
		if (![[_expressionField stringValue] isEqualToString:column.expression ?: @""]) {
			_expressionField.stringValue = column.expression ?: @"";
		}
		[_inputVariableField setStringValue:column.inputVariable ?: @""];
	}
	[self fillTypes:_typePopup with:column.typeRef];
}

- (void)setColumnProperty:(NSString *)property to:(NSString *)value
{
	WKDDmnDecision *decision = [self decision];
	WKDDmnColumn *column = _column < [decision.columns count] ? [decision.columns objectAtIndex:_column] : nil;
	if (column == nil) {
		return;
	}
	NSString *now = [column valueForKey:property] ?: @"";
	if (![now isEqualToString:value ?: @""]) {
		[[self editor] setColumn:_column property:property to:value of:decision.decisionId];
	}
}

- (void)columnLabelChanged:(id)sender
{
	[self setColumnProperty:@"label" to:[_labelField stringValue]];
}

- (void)columnExpressionChanged:(id)sender
{
	[self explain:nil];
	[self setColumnProperty:@"expression" to:[_expressionField stringValue]];
}

- (void)columnNameChanged:(id)sender
{
	[self setColumnProperty:@"name" to:[_outputNameField stringValue]];
}

- (void)columnTypeChanged:(id)sender
{
	[self setColumnProperty:@"typeRef" to:WKDChosenType(_typePopup)];
}

- (void)columnVariableChanged:(id)sender
{
	[self setColumnProperty:@"inputVariable" to:[_inputVariableField stringValue]];
}

#pragma mark The decision

- (void)nameChanged:(id)sender
{
	WKDDmnDecision *decision = [self decision];
	if (decision != nil && ![[_nameField stringValue] isEqualToString:decision.name ?: @""]) {
		[[self editor] setName:[_nameField stringValue] of:decision.decisionId];
	}
}

- (void)idChanged:(id)sender
{
	WKDDmnDecision *decision = [self decision];
	NSString *newId = [[_idField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (decision == nil || [newId isEqualToString:decision.decisionId]) {
		return;
	}
	NSString *reason = nil;
	NSString *oldId = decision.decisionId;
	_decisionId = [newId copy];
	if (![[self editor] renameDecision:oldId to:newId error:&reason]) {
		_decisionId = [oldId copy];
		[_idField setStringValue:oldId];
		[self note:reason];
	}
}

- (void)hitPolicyChanged:(id)sender
{
	NSArray *policies = WKDDmnHitPolicies();
	NSInteger index = [_hitPolicy indexOfSelectedItem];
	WKDDmnDecision *decision = [self decision];
	if (decision == nil || index < 0 || index >= (NSInteger)[policies count]) {
		return;
	}
	NSArray *policy = [policies objectAtIndex:(NSUInteger)index];
	if (![policy[0] isEqualToString:decision.hitPolicy] || ![policy[1] isEqualToString:decision.aggregation ?: @""]) {
		[[self editor] setHitPolicy:policy[0] aggregation:policy[1] of:decision.decisionId];
	}
}

- (void)requirementToggled:(NSMenuItem *)sender
{
	WKDDmnDecision *decision = [self decision];
	NSString *other = [sender representedObject];
	if (decision == nil || other == nil) {
		return;
	}
	NSMutableArray *required = [decision.required mutableCopy];
	if ([required containsObject:other]) {
		[required removeObject:other];
	} else {
		[required addObject:other];
	}
	NSString *reason = nil;
	if (![[self editor] setRequired:required of:decision.decisionId error:&reason]) {
		[self note:reason];
		[self showRequirements:decision];
	}
}

- (void)variableChanged:(id)sender
{
	WKDDmnDecision *decision = [self decision];
	if (decision != nil && ![[_variableField stringValue] isEqualToString:decision.variableName ?: @""]) {
		[[self editor] setLiteral:@"variableName" to:[_variableField stringValue] of:decision.decisionId];
	}
}

- (void)variableTypeChanged:(id)sender
{
	WKDDmnDecision *decision = [self decision];
	NSString *type = WKDChosenType(_variableType);
	if (decision != nil && ![type ?: @"" isEqualToString:decision.variableType ?: @""]) {
		[[self editor] setLiteral:@"variableType" to:type of:decision.decisionId];
	}
}

- (void)literalChanged:(id)sender
{
	WKDDmnDecision *decision = [self decision];
	[self explain:nil];
	if (decision != nil && ![[_literalField stringValue] isEqualToString:decision.expression ?: @""]) {
		[[self editor] setLiteral:@"expression" to:[_literalField stringValue] of:decision.decisionId];
	}
}

#pragma mark Status

- (void)updateStatus
{
	NSString *problem = [self decisionDocument].problem;
	NSMutableArray *parts = [NSMutableArray array];
	if (_note != nil) {
		[parts addObject:_note];
	}
	[parts addObject:problem == nil ? @"The engine evaluates these decisions."
	                                : [NSString stringWithFormat:@"Not deployable: %@", problem]];
	[_status setStringValue:[parts componentsJoinedByString:@" — "]];
}

/* A change refused: said, with a beep. */
- (void)note:(NSString *)note
{
	_note = [note copy];
	if (note != nil) {
		NSBeep();
	}
	[self updateStatus];
}

/* An expression's problem as it is typed: said, not beeped at. */
- (void)explain:(NSString *)problem
{
	_note = [problem copy];
	[self updateStatus];
}

#pragma mark Actions

- (IBAction)addDecisionTable:(id)sender
{
	[self showDecision:[[self editor] addDecisionTable:YES withId:nil]];
	[[self window] makeFirstResponder:_nameField];
}

- (IBAction)addLiteralDecision:(id)sender
{
	[self showDecision:[[self editor] addDecisionTable:NO withId:nil]];
	[[self window] makeFirstResponder:_nameField];
}

- (IBAction)deleteDecision:(id)sender
{
	NSString *decisionId = _decisionId;
	if (decisionId != nil) {
		[[self editor] deleteDecision:decisionId];
	}
}

/* The one rule selected; NSNotFound for none, or several. */
- (NSUInteger)selectedRule
{
	NSIndexSet *selected = [_grid selectedRowIndexes];
	return [selected count] == 1 ? [selected firstIndex] : NSNotFound;
}

- (void)selectRule:(NSUInteger)rule
{
	if (rule < [[self decision].rules count]) {
		[_grid selectRowIndexes:[NSIndexSet indexSetWithIndex:rule] byExtendingSelection:NO];
		[_grid scrollRowToVisible:(NSInteger)rule];
	}
}

- (IBAction)addRule:(id)sender
{
	WKDDmnDecision *decision = [self decision];
	NSIndexSet *selected = [_grid selectedRowIndexes];
	NSUInteger index = [selected count] > 0 ? [selected lastIndex] + 1 : [decision.rules count];
	[[self window] makeFirstResponder:_grid];
	[[self editor] insertRuleAt:index of:decision.decisionId];
	[self selectRule:index];
	if ([decision.columns count] > 0) {
		[_grid editColumn:1 row:(NSInteger)index withEvent:nil select:YES];
	}
}

- (IBAction)duplicate:(id)sender
{
	NSUInteger rule = [self selectedRule];
	if (rule != NSNotFound) {
		[[self editor] duplicateRule:rule of:_decisionId];
		[self selectRule:rule + 1];
	}
}

- (IBAction)delete:(id)sender
{
	NSIndexSet *selected = [_grid selectedRowIndexes];
	if ([selected count] > 0) {
		NSUInteger first = [selected firstIndex];
		[[self editor] deleteRules:selected of:_decisionId];
		NSUInteger count = [[self decision].rules count];
		if (count > 0) {
			[self selectRule:MIN(first, count - 1)];
		}
	}
}

- (IBAction)moveRuleUp:(id)sender
{
	NSUInteger rule = [self selectedRule];
	if (rule != NSNotFound && rule > 0) {
		[[self editor] moveRule:rule to:rule - 1 of:_decisionId];
		[self selectRule:rule - 1];
	}
}

- (IBAction)moveRuleDown:(id)sender
{
	NSUInteger rule = [self selectedRule];
	if (rule != NSNotFound && rule + 1 < [[self decision].rules count]) {
		[[self editor] moveRule:rule to:rule + 1 of:_decisionId];
		[self selectRule:rule + 1];
	}
}

- (void)addColumn:(BOOL)output
{
	WKDDmnDecision *decision = [self decision];
	NSUInteger inputs = [decision.inputs count];
	NSUInteger count = output ? [decision.outputs count] : inputs;
	NSUInteger index = count;
	/* After the current column, when it is of the kind. */
	if (_column != NSNotFound && _column < [decision.columns count] && (_column >= inputs) == output) {
		index = (output ? _column - inputs : _column) + 1;
	}
	_column = [[self editor] insertColumn:output at:index of:decision.decisionId];
	[self showColumn:[self decision]];
	[[self window] makeFirstResponder:output ? (NSView *)_outputNameField : (NSView *)_expressionField];
}

- (IBAction)addInput:(id)sender
{
	[self addColumn:NO];
}

- (IBAction)addOutput:(id)sender
{
	[self addColumn:YES];
}

- (IBAction)deleteColumn:(id)sender
{
	if (_column != NSNotFound) {
		[[self editor] deleteColumn:_column of:_decisionId];
	}
}

- (void)moveColumnBy:(NSInteger)step
{
	WKDDmnDecision *decision = [self decision];
	if (_column == NSNotFound || _column >= [decision.columns count]) {
		return;
	}
	NSUInteger inputs = [decision.inputs count];
	BOOL output = _column >= inputs;
	NSInteger target = (NSInteger)_column + step;
	NSInteger first = output ? (NSInteger)inputs : 0;
	NSInteger last = output ? (NSInteger)[decision.columns count] - 1 : (NSInteger)inputs - 1;
	if (target < first || target > last) {
		return;
	}
	NSUInteger from = _column;
	_column = (NSUInteger)target;
	[[self editor] moveColumn:from to:(NSUInteger)target of:decision.decisionId];
}

- (IBAction)moveColumnLeft:(id)sender
{
	[self moveColumnBy:-1];
}

- (IBAction)moveColumnRight:(id)sender
{
	[self moveColumnBy:1];
}

- (void)alert:(NSString *)message detail:(NSString *)detail
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:message];
	[alert setInformativeText:detail ?: @""];
	[alert beginSheetModalForWindow:[self window] completionHandler:nil];
}

- (IBAction)deploy:(id)sender
{
	WKDDecisionDocument *document = [self decisionDocument];
	if (document.problem != nil) {
		[self alert:@"The engine would not evaluate these decisions." detail:document.problem];
		return;
	}
	NSXMLElement *root = [document.editor.document rootElement];
	NSString *fileName = [[document fileURL] lastPathComponent]
		?: [(WKDAttribute(root, @"id") ?: @"decisions") stringByAppendingPathExtension:@"dmn"];
	NSString *name = WKDAttribute(root, @"name") ?: fileName;
	NSDictionary *resources = @{ fileName: [document.editor.document XMLStringWithOptions:NSXMLNodePrettyPrint] };
	[[WKDAppDelegate shared] withSession:^(WDSession *session) {
		[self note:nil];
		[self->_status setStringValue:[NSString stringWithFormat:@"Deploying to %@…", [session.serviceURL host]]];
		[session invoke:@"Deploy" on:nil parameters:@{ @"Name": name, @"Resources": resources }
		     completion:^(id result, NSError *error) {
			if (error != nil) {
				[self updateStatus];
				[self alert:@"Could not deploy." detail:[error localizedDescription]];
				return;
			}
			self->_note = [NSString stringWithFormat:@"Deployed %@", fileName];
			[self updateStatus];
		}];
	}];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	SEL action = [item action];
	WKDDmnDecision *decision = [self decision];
	BOOL table = decision.isTable;
	NSUInteger rule = [self selectedRule];
	if (action == @selector(deleteDecision:)) {
		return decision != nil;
	}
	if (action == @selector(addRule:) || action == @selector(addInput:) || action == @selector(addOutput:)) {
		return table;
	}
	if (action == @selector(duplicate:)) {
		return table && rule != NSNotFound;
	}
	if (action == @selector(delete:)) {
		return table && [[_grid selectedRowIndexes] count] > 0;
	}
	if (action == @selector(moveRuleUp:)) {
		return table && rule != NSNotFound && rule > 0;
	}
	if (action == @selector(moveRuleDown:)) {
		return table && rule != NSNotFound && rule + 1 < [decision.rules count];
	}
	BOOL column = table && _column != NSNotFound && _column < [decision.columns count];
	if (action == @selector(deleteColumn:)) {
		return column;
	}
	if (action == @selector(moveColumnLeft:)) {
		return column && _column != 0 && _column != [decision.inputs count];
	}
	if (action == @selector(moveColumnRight:)) {
		return column && _column + 1 != [decision.inputs count] && _column + 1 != [decision.columns count];
	}
	if (action == @selector(deploy:)) {
		return [self decisionDocument].problem == nil;
	}
	return YES;
}

#pragma mark The menu

+ (NSMenuItem *)decisionMenuItem
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Decision"];
	NSArray *items = @[ @[ @"Add Decision Table", @"addDecisionTable:" ], @[ @"Add Literal Expression", @"addLiteralDecision:" ],
	                    @[ @"Delete Decision", @"deleteDecision:" ], @[],
	                    @[ @"Add Rule", @"addRule:" ], @[ @"Move Rule Up", @"moveRuleUp:" ],
	                    @[ @"Move Rule Down", @"moveRuleDown:" ], @[],
	                    @[ @"Add Input", @"addInput:" ], @[ @"Add Output", @"addOutput:" ],
	                    @[ @"Delete Column", @"deleteColumn:" ], @[ @"Move Column Left", @"moveColumnLeft:" ],
	                    @[ @"Move Column Right", @"moveColumnRight:" ] ];
	for (NSArray *spec in items) {
		if ([spec count] == 0) {
			[menu addItem:[NSMenuItem separatorItem]];
			continue;
		}
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:spec[0] action:NSSelectorFromString(spec[1])
		                                       keyEquivalent:@""];
		[menu addItem:item];
	}
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Decision" action:NULL keyEquivalent:@""];
	[item setSubmenu:menu];
	return item;
}

@end

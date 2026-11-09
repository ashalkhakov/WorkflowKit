#import "WKDRuleGridViewController.h"
#import "WKDExpressionField.h"

static NSString * const WKDNumberColumn = @"#";
static NSString * const WKDAnnotationColumn = @"annotation";

static const double WKDEntryWidth = 170;
static const double WKDAnnotationWidth = 200;

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

@implementation WKDRuleGridViewController
{
	/* What the grid's columns were made for: rebuilt when it changes. */
	NSArray *_gridColumns;
}

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor
{
	if ((self = [super initWithNibName:@"WKDRuleGrid" bundle:[NSBundle bundleForClass:[WKDRuleGridViewController class]]])) {
		_decisionEditor = decisionEditor;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
	[super loadView];
	[self.grid setTarget:self];
	[self.grid setAction:@selector(gridClicked:)];
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	/* Heard as it is typed: gnustep-gui does not pass a cell's typing on to
	 * the table's delegate. */
	[center addObserver:self selector:@selector(cellTextDidChange:) name:NSControlTextDidChangeNotification
	             object:self.grid];
	[center addObserver:self selector:@selector(decisionsDidChange:) name:WKDDecisionEditorDidChangeNotification
	             object:_decisionEditor];
	[center addObserver:self selector:@selector(choiceDidChange:) name:WKDDecisionEditorChoiceDidChangeNotification
	             object:_decisionEditor];
	[self show];
}

- (WKDDmnEditor *)editor
{
	return _decisionEditor.editor;
}

- (WKDDmnDecision *)decision
{
	return _decisionEditor.decision;
}

#pragma mark Following the decision

- (void)decisionsDidChange:(NSNotification *)notification
{
	/* The cell written is still being edited: shown once it is not. */
	if ([self.grid editedRow] >= 0) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self show];
		});
		return;
	}
	[self show];
}

- (void)choiceDidChange:(NSNotification *)notification
{
	NSString *shown = [_gridColumns firstObject];
	if (![shown isEqualToString:_decisionEditor.decisionId ?: @""]) {
		[self.grid deselectAll:nil];
		[self show];
	}
}

- (NSString *)titleOf:(WKDDmnColumn *)column
{
	NSString *title = column.output ? [@"→ " stringByAppendingString:column.title] : column.title;
	return [column.typeRef length] > 0 ? [NSString stringWithFormat:@"%@ · %@", title, column.typeRef] : title;
}

/* The grid's columns made from the table's, kept when they are the same. */
- (void)show
{
	WKDDmnDecision *decision = [self decision];
	if (!decision.isTable) {
		_gridColumns = nil;
		[self.grid reloadData];
		return;
	}
	NSMutableArray *shape = [NSMutableArray arrayWithObject:decision.decisionId];
	for (WKDDmnColumn *column in decision.columns) {
		[shape addObject:[NSString stringWithFormat:@"%@:%d", column.columnId ?: @"", column.output]];
	}
	if (![shape isEqualToArray:_gridColumns]) {
		NSMutableDictionary *widths = [NSMutableDictionary dictionary];
		for (NSTableColumn *column in [self.grid tableColumns]) {
			[widths setObject:@([column width]) forKey:[column identifier]];
		}
		for (NSTableColumn *column in [[self.grid tableColumns] copy]) {
			[self.grid removeTableColumn:column];
		}
		NSMutableArray *identifiers = [NSMutableArray arrayWithObject:WKDNumberColumn];
		[identifiers addObjectsFromArray:[shape subarrayWithRange:NSMakeRange(1, [shape count] - 1)]];
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
			[self.grid addTableColumn:column];
		}
		_gridColumns = shape;
	}
	NSArray *columns = [self.grid tableColumns];
	[[[columns firstObject] headerCell] setStringValue:WKDHitPolicyLetter(decision)];
	for (NSUInteger i = 0; i < [decision.columns count]; i++) {
		[[[columns objectAtIndex:i + 1] headerCell] setStringValue:[self titleOf:[decision.columns objectAtIndex:i]]];
	}
	[[[columns lastObject] headerCell] setStringValue:@"Annotation"];
	[[self.grid headerView] setNeedsDisplay:YES];
	NSIndexSet *selected = [self.grid selectedRowIndexes];
	[self.grid reloadData];
	if ([selected count] > 0 && [selected lastIndex] >= [decision.rules count]) {
		[self.grid deselectAll:nil];
	}
}

#pragma mark The grid

/* The index among the decision's columns of a grid's column; NSNotFound
 * for the rule numbers and the annotations. */
- (NSUInteger)columnOf:(NSTableColumn *)tableColumn
{
	NSUInteger index = [[self.grid tableColumns] indexOfObjectIdenticalTo:tableColumn];
	NSUInteger count = [[self decision].columns count];
	return index != NSNotFound && index >= 1 && index <= count ? index - 1 : NSNotFound;
}

- (WFExpressionPlace)placeOfColumn:(NSUInteger)column
{
	return column < [[self decision].inputs count] ? WFExpressionPlaceUnaryTests : WFExpressionPlaceExpression;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [self decision].isTable ? (NSInteger)[[self decision].rules count] : 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
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
	BOOL edited = [self.grid editedRow] == row
		&& [[self.grid tableColumns] indexOfObjectIdenticalTo:tableColumn] == (NSUInteger)[self.grid editedColumn];
	if (edited || [text length] == 0) {
		return text;
	}
	return WKDColouredExpression(text, [self placeOfColumn:column], [NSFont systemFontOfSize:11]);
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row
{
	WKDDmnDecision *decision = [self decision];
	if (row < 0 || row >= (NSInteger)[decision.rules count]) {
		return;
	}
	NSString *text = [object isKindOfClass:[NSAttributedString class]] ? [object string] : [object description] ?: @"";
	WKDDmnRule *rule = [decision.rules objectAtIndex:(NSUInteger)row];
	if (self.explained != nil) {
		self.explained(nil);
	}
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
	if ([[tableColumn identifier] isEqualToString:WKDNumberColumn]) {
		return NO;
	}
	[self chooseColumn:[self columnOf:tableColumn]];
	return YES;
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{
	[self chooseColumn:[self columnOf:tableColumn]];
}

- (void)gridClicked:(id)sender
{
	NSInteger clicked = [self.grid clickedColumn];
	if (clicked >= 0 && clicked < (NSInteger)[[self.grid tableColumns] count]) {
		[self chooseColumn:[self columnOf:[[self.grid tableColumns] objectAtIndex:(NSUInteger)clicked]]];
	}
}

- (void)chooseColumn:(NSUInteger)column
{
	if (column != NSNotFound) {
		_decisionEditor.column = column;
	}
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
	NSUInteger column = [self columnOf:tableColumn];
	WKDDmnDecision *decision = [self decision];
	if (column == NSNotFound || row < 0 || row >= (NSInteger)[decision.rules count]) {
		return nil;
	}
	NSString *text = [[decision.rules objectAtIndex:(NSUInteger)row].entries objectAtIndex:column];
	return [[WFFeelExpression problemInText:text place:[self placeOfColumn:column]] localizedDescription];
}

/* An entry being typed: what the engine says of it. */
- (void)cellTextDidChange:(NSNotification *)notification
{
	NSInteger edited = [self.grid editedColumn];
	NSUInteger column = edited >= 0 && edited < (NSInteger)[[self.grid tableColumns] count]
		? [self columnOf:[[self.grid tableColumns] objectAtIndex:(NSUInteger)edited]] : NSNotFound;
	NSText *text = [[notification userInfo] objectForKey:@"NSFieldEditor"];
	if (column == NSNotFound || ![text isKindOfClass:[NSText class]] || self.explained == nil) {
		return;
	}
	NSError *problem = [WFFeelExpression problemInText:[text string] place:[self placeOfColumn:column]];
	self.explained(problem != nil ? [NSString stringWithFormat:@"%@: %@",
		[[self decision].columns objectAtIndex:column].title, [problem localizedDescription]] : nil);
}

#pragma mark Rules

/* The one rule selected; NSNotFound for none, or several. */
- (NSUInteger)selectedRule
{
	NSIndexSet *selected = [self.grid selectedRowIndexes];
	return [selected count] == 1 ? [selected firstIndex] : NSNotFound;
}

- (void)selectRule:(NSUInteger)rule
{
	if (rule < [[self decision].rules count]) {
		[self.grid selectRowIndexes:[NSIndexSet indexSetWithIndex:rule] byExtendingSelection:NO];
		[self.grid scrollRowToVisible:(NSInteger)rule];
	}
}

- (IBAction)addRule:(id)sender
{
	WKDDmnDecision *decision = [self decision];
	NSIndexSet *selected = [self.grid selectedRowIndexes];
	NSUInteger index = [selected count] > 0 ? [selected lastIndex] + 1 : [decision.rules count];
	[[self.grid window] makeFirstResponder:self.grid];
	[[self editor] insertRuleAt:index of:decision.decisionId];
	[self selectRule:index];
	if ([decision.columns count] > 0 && [self.grid window] != nil) {
		[self.grid editColumn:1 row:(NSInteger)index withEvent:nil select:YES];
	}
}

- (IBAction)duplicate:(id)sender
{
	NSUInteger rule = [self selectedRule];
	if (rule != NSNotFound) {
		[[self editor] duplicateRule:rule of:_decisionEditor.decisionId];
		[self selectRule:rule + 1];
	}
}

- (IBAction)delete:(id)sender
{
	NSIndexSet *selected = [self.grid selectedRowIndexes];
	if ([selected count] > 0) {
		NSUInteger first = [selected firstIndex];
		[[self editor] deleteRules:selected of:_decisionEditor.decisionId];
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
		[[self editor] moveRule:rule to:rule - 1 of:_decisionEditor.decisionId];
		[self selectRule:rule - 1];
	}
}

- (IBAction)moveRuleDown:(id)sender
{
	NSUInteger rule = [self selectedRule];
	if (rule != NSNotFound && rule + 1 < [[self decision].rules count]) {
		[[self editor] moveRule:rule to:rule + 1 of:_decisionEditor.decisionId];
		[self selectRule:rule + 1];
	}
}

#pragma mark Columns

- (void)addColumn:(BOOL)output
{
	WKDDmnDecision *decision = [self decision];
	NSUInteger inputs = [decision.inputs count], chosen = _decisionEditor.column;
	NSUInteger index = output ? [decision.outputs count] : inputs;
	/* After the chosen column, when it is of the kind. */
	if (chosen != NSNotFound && chosen < [decision.columns count] && (chosen >= inputs) == output) {
		index = (output ? chosen - inputs : chosen) + 1;
	}
	NSUInteger made = [[self editor] insertColumn:output at:index of:decision.decisionId];
	_decisionEditor.column = made;
	if (self.columnAdded != nil) {
		self.columnAdded(output);
	}
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
	if (_decisionEditor.column != NSNotFound) {
		[[self editor] deleteColumn:_decisionEditor.column of:_decisionEditor.decisionId];
	}
}

- (void)moveColumnBy:(NSInteger)step
{
	WKDDmnDecision *decision = [self decision];
	NSUInteger chosen = _decisionEditor.column;
	if (chosen == NSNotFound || chosen >= [decision.columns count]) {
		return;
	}
	NSUInteger inputs = [decision.inputs count];
	BOOL output = chosen >= inputs;
	NSInteger target = (NSInteger)chosen + step;
	NSInteger first = output ? (NSInteger)inputs : 0;
	NSInteger last = output ? (NSInteger)[decision.columns count] - 1 : (NSInteger)inputs - 1;
	if (target < first || target > last) {
		return;
	}
	[[self editor] moveColumn:chosen to:(NSUInteger)target of:decision.decisionId];
	_decisionEditor.column = (NSUInteger)target;
}

- (IBAction)moveColumnLeft:(id)sender
{
	[self moveColumnBy:-1];
}

- (IBAction)moveColumnRight:(id)sender
{
	[self moveColumnBy:1];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	SEL action = [item action];
	WKDDmnDecision *decision = [self decision];
	BOOL table = decision.isTable;
	NSUInteger rule = [self selectedRule], chosen = _decisionEditor.column;
	if (action == @selector(addRule:) || action == @selector(addInput:) || action == @selector(addOutput:)) {
		return table;
	}
	if (action == @selector(duplicate:)) {
		return table && rule != NSNotFound;
	}
	if (action == @selector(delete:)) {
		return table && [[self.grid selectedRowIndexes] count] > 0;
	}
	if (action == @selector(moveRuleUp:)) {
		return table && rule != NSNotFound && rule > 0;
	}
	if (action == @selector(moveRuleDown:)) {
		return table && rule != NSNotFound && rule + 1 < [decision.rules count];
	}
	BOOL column = table && chosen != NSNotFound && chosen < [decision.columns count];
	if (action == @selector(deleteColumn:)) {
		return column;
	}
	if (action == @selector(moveColumnLeft:)) {
		return column && chosen != 0 && chosen != [decision.inputs count];
	}
	if (action == @selector(moveColumnRight:)) {
		return column && chosen + 1 != [decision.inputs count] && chosen + 1 != [decision.columns count];
	}
	return YES;
}

@end

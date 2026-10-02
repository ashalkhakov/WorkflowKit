#import "WKDTableEditor.h"
#import "WKDEditor.h"
#import "WKDExpressionField.h"
#import "WKDProperties.h"

static const double WKDRowHeight = 20;
static const double WKDVisibleRows = 4;
static const double WKDButtonsHeight = 24;
static const double WKDDetailGap = 8;
static const double WKDDetailLabel = 16;

/* Return ends the editing, as in a field, rather than going on to the
 * next row's cell (gnustep-gui's way). */
@interface WKDCellTable : NSTableView
@end

@implementation WKDCellTable

- (void)textDidEndEditing:(NSNotification *)notification
{
	NSNumber *movement = [[notification userInfo] objectForKey:@"NSTextMovement"];
	if ([movement integerValue] != NSReturnTextMovement) {
		[super textDidEndEditing:notification];
		return;
	}
	NSMutableDictionary *info = [[notification userInfo] mutableCopy];
	[info setObject:@(NSIllegalTextMovement) forKey:@"NSTextMovement"];
	[super textDidEndEditing:[NSNotification notificationWithName:[notification name] object:[notification object]
	                                                     userInfo:info]];
	[[self window] makeFirstResponder:self];
}

@end

/* One table: the property's, or its detail's for a master row. */
@interface WKDTablePane : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) WKDProperty *property;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSScrollView *scroll;
@property (nonatomic, strong) NSButton *add;
@property (nonatomic, strong) NSButton *remove;
@property (nonatomic, strong) NSTextField *empty;
@property (nonatomic, copy) NSArray<WKDRow *> *rows;
/* For a detail: the master's row its entries are in; NSNotFound when none
 * is selected, and for the property's own table. */
@property (nonatomic) NSUInteger master;
@property (nonatomic, weak) WKDTableEditor *owner;
@end

@interface WKDTableEditor ()
- (void)write:(NSArray<WKDRow *> *)rows of:(WKDTablePane *)pane selecting:(NSInteger)row;
- (void)selectionChanged:(WKDTablePane *)pane;
- (void)explain:(NSString *)problem column:(WKDColumn *)column;
@end

@implementation WKDTablePane

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[self.rows count];
}

- (WKDColumn *)columnOf:(NSTableColumn *)tableColumn
{
	NSUInteger index = [[self.table tableColumns] indexOfObjectIdenticalTo:tableColumn];
	return index < [self.property.columns count] ? [self.property.columns objectAtIndex:index] : nil;
}

- (NSString *)valueAt:(NSInteger)row column:(NSTableColumn *)tableColumn
{
	NSUInteger index = [[self.table tableColumns] indexOfObjectIdenticalTo:tableColumn];
	NSArray *values = row >= 0 && row < (NSInteger)[self.rows count] ? [self.rows objectAtIndex:(NSUInteger)row].values : nil;
	return index < [values count] ? [values objectAtIndex:index] : @"";
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	WKDColumn *column = [self columnOf:tableColumn];
	NSString *value = [self valueAt:row column:tableColumn];
	if (column.kind == WKDPropertyChoice) {
		NSUInteger index = [column.values indexOfObject:value];
		return @(index == NSNotFound ? 0 : (NSInteger)index);
	}
	if (column.kind == WKDPropertyCheck) {
		return @([value isEqualToString:@"true"] ? NSControlStateValueOn : NSControlStateValueOff);
	}
	/* An expression, coloured: as the cell's value, which both kits draw
	 * as it is; and plain while it is typed in. */
	BOOL edited = [tableView editedRow] == row
		&& [[tableView tableColumns] indexOfObjectIdenticalTo:tableColumn] == (NSUInteger)[tableView editedColumn];
	if (column.holdsExpression && !edited) {
		return [self colouredText:value column:column];
	}
	return value;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row
{
	WKDColumn *column = [self columnOf:tableColumn];
	NSUInteger index = [[self.table tableColumns] indexOfObjectIdenticalTo:tableColumn];
	if (column == nil || row < 0 || row >= (NSInteger)[self.rows count]) {
		return;
	}
	NSString *value = column.kind == WKDPropertyChoice
		? [column.values objectAtIndex:MIN((NSUInteger)MAX(0, [object integerValue]), [column.values count] - 1)]
		: column.kind == WKDPropertyCheck ? ([object integerValue] != 0 ? @"true" : @"false")
		: [object isKindOfClass:[NSAttributedString class]] ? [object string] : [object description] ?: @"";
	WKDRow *edited = [WKDRow rowWithValues:[self.rows objectAtIndex:(NSUInteger)row].values];
	edited.source = [self.rows objectAtIndex:(NSUInteger)row].source;
	NSMutableArray *values = [edited.values mutableCopy];
	values[index] = value;
	edited.values = values;
	NSMutableArray *rows = [self.rows mutableCopy];
	rows[(NSUInteger)row] = edited;
	[self.owner explain:nil column:nil];
	[self.owner write:rows of:self selecting:row];
}

/* An expression's tokens in their colours, where the engine stops reading
 * underlined. */
- (NSAttributedString *)colouredText:(NSString *)text column:(WKDColumn *)column
{
	NSMutableAttributedString *coloured = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
		NSFontAttributeName: [NSFont systemFontOfSize:11],
		NSForegroundColorAttributeName: [NSColor controlTextColor] }];
	for (NSDictionary *token in [WFFeelExpression tokensOfText:text place:column.place]) {
		NSRange range = [[token objectForKey:@"range"] rangeValue];
		if (NSMaxRange(range) <= [text length]) {
			[coloured addAttribute:NSForegroundColorAttributeName
			                 value:WKDExpressionTokenColor([token objectForKey:@"kind"]) range:range];
		}
	}
	NSError *problem = [WFFeelExpression problemInText:text place:column.place];
	if (problem != nil && [text length] > 0) {
		NSRange range = [[[problem userInfo] objectForKey:WFErrorRangeKey] rangeValue];
		range = NSIntersectionRange(range.length > 0 ? range : NSMakeRange(range.location, 1), NSMakeRange(0, [text length]));
		[coloured addAttributes:@{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleThick),
		                           NSUnderlineColorAttributeName: [NSColor redColor] } range:range];
	}
	return coloured;
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
	WKDColumn *column = [self columnOf:tableColumn];
	if (!column.holdsExpression) {
		return nil;
	}
	return [[WFFeelExpression problemInText:[self valueAt:row column:tableColumn] place:column.place]
		localizedDescription];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self.remove setEnabled:[self.table selectedRow] >= 0];
	[self.owner selectionChanged:self];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* An expression being typed: what the engine says of it. */
- (void)cellTextDidChange:(NSNotification *)notification
{
	NSInteger column = [self.table editedColumn];
	if (column < 0 || column >= (NSInteger)[self.property.columns count]) {
		return;
	}
	WKDColumn *edited = [self.property.columns objectAtIndex:(NSUInteger)column];
	NSText *text = [[notification userInfo] objectForKey:@"NSFieldEditor"];
	if (edited.holdsExpression && [text isKindOfClass:[NSText class]]) {
		NSError *problem = [WFFeelExpression problemInText:[text string] place:edited.place];
		[self.owner explain:[problem localizedDescription] column:edited];
	}
}

- (void)addRow:(id)sender
{
	NSMutableArray *rows = [self.rows mutableCopy];
	[rows addObject:[WKDRow rowWithValues:self.property.blankRow]];
	[self.owner write:rows of:self selecting:(NSInteger)[rows count] - 1];
}

- (void)removeRow:(id)sender
{
	NSInteger selected = [self.table selectedRow];
	if (selected < 0 || selected >= (NSInteger)[self.rows count]) {
		return;
	}
	NSMutableArray *rows = [self.rows mutableCopy];
	[rows removeObjectAtIndex:(NSUInteger)selected];
	[self.owner write:rows of:self selecting:MIN(selected, (NSInteger)[rows count] - 1)];
}

@end

@implementation WKDTableEditor
{
	WKDTablePane *_main;
	/* The tables of the selected row's entries, and what each is titled. */
	NSMutableArray<WKDTablePane *> *_details;
	NSMutableArray<NSTextField *> *_detailLabels;
}

+ (double)tableHeight:(double)rows
{
	return 22 + rows * (WKDRowHeight + 2) + 4;
}

+ (double)heightFor:(WKDProperty *)property
{
	double height = [self tableHeight:WKDVisibleRows] + WKDButtonsHeight;
	height += (double)[property.details count] * (WKDDetailGap + WKDDetailLabel + [self tableHeight:3] + WKDButtonsHeight);
	return height;
}

- (BOOL)isFlipped
{
	return YES;
}

- (instancetype)initWithFrame:(NSRect)frame property:(WKDProperty *)property
{
	if ((self = [super initWithFrame:frame])) {
		_property = property;
		double y = 0, width = NSWidth(frame);
		_main = [self paneFor:property rows:WKDVisibleRows y:&y width:width];
		_main.master = NSNotFound;
		_details = [NSMutableArray array];
		_detailLabels = [NSMutableArray array];
		for (WKDProperty *detail in property.details) {
			y += WKDDetailGap;
			NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, y, width, WKDDetailLabel)];
			[label setEditable:NO];
			[label setSelectable:NO];
			[label setBordered:NO];
			[label setBezeled:NO];
			[label setDrawsBackground:NO];
			[label setFont:[NSFont systemFontOfSize:10]];
			[label setTextColor:[NSColor secondaryLabelColor]];
			[label setAutoresizingMask:NSViewWidthSizable];
			[self addSubview:label];
			[_detailLabels addObject:label];
			y += WKDDetailLabel;
			WKDTablePane *pane = [self paneFor:detail rows:3 y:&y width:width];
			pane.master = NSNotFound;
			[_details addObject:pane];
		}
	}
	return self;
}

- (WKDTablePane *)paneFor:(WKDProperty *)property rows:(double)rows y:(double *)y width:(double)width
{
	WKDTablePane *pane = [[WKDTablePane alloc] init];
	pane.property = property;
	pane.owner = self;
	pane.rows = @[];
	double height = [WKDTableEditor tableHeight:rows];
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, *y, width, height)];
	[scroll setBorderType:NSBezelBorder];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutohidesScrollers:NO];
	[scroll setAutoresizingMask:NSViewWidthSizable];
	NSTableView *table = [[WKDCellTable alloc] initWithFrame:NSMakeRect(0, 0, [scroll contentSize].width, height)];
	[table setRowHeight:WKDRowHeight];
	[table setAllowsMultipleSelection:NO];
	[table setAllowsEmptySelection:YES];
	[table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	double shares = 0;
	for (WKDColumn *column in property.columns) {
		shares += column.share;
	}
	double inner = [scroll contentSize].width - 4;
	for (WKDColumn *column in property.columns) {
		NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:column.title];
		[[tableColumn headerCell] setStringValue:column.title];
		[tableColumn setWidth:floor(inner * column.share / shares)];
		[tableColumn setEditable:YES];
		[tableColumn setResizingMask:NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
		if (column.kind == WKDPropertyCheck) {
			NSButtonCell *cell = [[NSButtonCell alloc] initTextCell:@""];
			[cell setButtonType:NSButtonTypeSwitch];
			[cell setControlSize:NSControlSizeSmall];
			[tableColumn setDataCell:cell];
		} else if (column.kind == WKDPropertyChoice) {
			NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
			[cell addItemsWithTitles:column.titles];
			[cell setBordered:NO];
			[cell setFont:[NSFont systemFontOfSize:11]];
			[cell setControlSize:NSControlSizeSmall];
			[tableColumn setDataCell:cell];
		} else {
			NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
			[cell setEditable:YES];
			[cell setFont:[NSFont systemFontOfSize:11]];
			[cell setLineBreakMode:NSLineBreakByTruncatingTail];
			[cell setPlaceholderString:column.placeholder];
			[tableColumn setDataCell:cell];
		}
		[table addTableColumn:tableColumn];
	}
	[table setDataSource:pane];
	[table setDelegate:pane];
	/* Heard as it is typed: gnustep-gui does not pass a cell's typing on
	 * to the table's delegate. */
	[[NSNotificationCenter defaultCenter] addObserver:pane selector:@selector(cellTextDidChange:)
	                                             name:NSControlTextDidChangeNotification object:table];
	[scroll setDocumentView:table];
	[self addSubview:scroll];
	pane.table = table;
	pane.scroll = scroll;

	/* What an empty table is for, in it. */
	NSTextField *empty = [[NSTextField alloc] initWithFrame:NSMakeRect(8, *y + 30, width - 16, 30)];
	[empty setStringValue:property.placeholder ?: @""];
	[empty setEditable:NO];
	[empty setSelectable:NO];
	[empty setBordered:NO];
	[empty setBezeled:NO];
	[empty setDrawsBackground:NO];
	[empty setFont:[NSFont systemFontOfSize:10]];
	[empty setTextColor:[NSColor disabledControlTextColor]];
	[empty setAutoresizingMask:NSViewWidthSizable];
	[self addSubview:empty];
	pane.empty = empty;
	*y += height + 2;

	NSButton *add = [[NSButton alloc] initWithFrame:NSMakeRect(0, *y, 26, 20)];
	NSButton *remove = [[NSButton alloc] initWithFrame:NSMakeRect(28, *y, 26, 20)];
	[add setTitle:@"+"];
	[remove setTitle:@"−"];
	for (NSButton *button in @[ add, remove ]) {
		[button setBezelStyle:NSBezelStyleSmallSquare];
		[button setFont:[NSFont systemFontOfSize:12]];
		[button setTarget:pane];
		[self addSubview:button];
	}
	[add setAction:@selector(addRow:)];
	[remove setAction:@selector(removeRow:)];
	[remove setEnabled:NO];
	pane.add = add;
	pane.remove = remove;
	*y += WKDButtonsHeight;
	return pane;
}

- (BOOL)isEditing
{
	if ([_main.table editedRow] >= 0) {
		return YES;
	}
	for (WKDTablePane *pane in _details) {
		if ([pane.table editedRow] >= 0) {
			return YES;
		}
	}
	return NO;
}

- (void)reload
{
	if (self.isEditing) {
		return;
	}
	[self load:_main];
	[self selectionChanged:_main];
}

- (void)load:(WKDTablePane *)pane
{
	BOOL usable = self.editor != nil && self.elementId != nil && (pane == _main || pane.master != NSNotFound);
	pane.rows = usable ? [pane.property rowsIn:self.editor of:self.elementId master:pane.master] : @[];
	NSInteger selected = [pane.table selectedRow];
	[pane.table reloadData];
	if (selected >= (NSInteger)[pane.rows count]) {
		[pane.table deselectAll:nil];
	}
	[pane.empty setHidden:[pane.rows count] > 0 || !usable];
	[pane.add setEnabled:usable];
	[pane.remove setEnabled:usable && [pane.table selectedRow] >= 0];
}

- (void)selectionChanged:(WKDTablePane *)pane
{
	if (pane != _main) {
		return;
	}
	NSInteger selected = [_main.table selectedRow];
	NSUInteger master = selected >= 0 && selected < (NSInteger)[_main.rows count]
		? [_main.rows objectAtIndex:(NSUInteger)selected].source : NSNotFound;
	for (NSUInteger i = 0; i < [_details count]; i++) {
		WKDTablePane *detail = [_details objectAtIndex:i];
		if (master != detail.master || master == NSNotFound) {
			[detail.table deselectAll:nil];
		}
		detail.master = master;
		[[_detailLabels objectAtIndex:i] setStringValue:master == NSNotFound
			? [NSString stringWithFormat:@"%@ of the row selected above", detail.property.label]
			: [NSString stringWithFormat:@"%@ of row %ld", detail.property.label, (long)selected + 1]];
		[self load:detail];
	}
}

- (void)write:(NSArray<WKDRow *> *)rows of:(WKDTablePane *)pane selecting:(NSInteger)row
{
	NSString *reason = nil;
	/* The change reloads the inspector, and so this: keep the selection. */
	if (![pane.property setRows:rows in:self.editor of:self.elementId master:pane.master error:&reason]) {
		if (self.refused != nil) {
			self.refused(reason);
		}
	}
	[self load:pane];
	if (row >= 0 && row < (NSInteger)[pane.rows count]) {
		[pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	}
	if (pane == _main) {
		[self selectionChanged:_main];
	}
}

- (void)explain:(NSString *)problem column:(WKDColumn *)column
{
	if (self.explained != nil) {
		self.explained(problem != nil ? [NSString stringWithFormat:@"%@: %@", column.title, problem] : nil);
	}
}

@end

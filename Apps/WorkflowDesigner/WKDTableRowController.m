#import "WKDTableRowController.h"
#import "WKDExpressionField.h"

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

static void *WKDRowsContext = &WKDRowsContext;

@implementation WKDTableRowController
{
	NSArray *_topLevelObjects;
	/* The row to select once the rows are read again. */
	NSInteger _keep;
}

- (instancetype)initWithTableModel:(WKDTableModel *)tableModel title:(NSString *)title
{
	if ((self = [super init])) {
		NSNib *nib = [[NSNib alloc] initWithNibNamed:@"WKDRowTable" bundle:[NSBundle bundleForClass:[WKDTableRowController class]]];
		NSArray *objects = nil;
		if (![nib instantiateWithOwner:self topLevelObjects:&objects] || self.view == nil) {
			return nil;
		}
		_topLevelObjects = objects;
		_keep = -1;
		[self.tableView setDataSource:(id)self];
		[self.tableView setDelegate:(id)self];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cellTextDidChange:)
		                                             name:NSControlTextDidChangeNotification object:self.tableView];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cellDidBeginEditing:)
		                                             name:NSControlTextDidBeginEditingNotification object:self.tableView];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cellDidEndEditing:)
		                                             name:NSControlTextDidEndEditingNotification object:self.tableView];
		self.title = title;
		self.tableModel = tableModel;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self unbind];
}

- (void)setTitle:(NSString *)title
{
	_title = [title copy];
	[self.label setStringValue:title ?: @""];
}

#pragma mark The model

- (void)setTableModel:(WKDTableModel *)tableModel
{
	if (_tableModel == tableModel) {
		return;
	}
	if (_tableModel != nil) {
		[_tableModel removeObserver:self forKeyPath:@"rows" context:WKDRowsContext];
	}
	BOOL columnsChange = _tableModel.property != tableModel.property;
	_tableModel = tableModel;
	if (columnsChange) {
		[self makeColumns];
	}
	[tableModel addObserver:self forKeyPath:@"rows" options:NSKeyValueObservingOptionPrior context:WKDRowsContext];
	[self rowsChanged];
}

- (void)unbind
{
	if (_tableModel != nil) {
		[_tableModel removeObserver:self forKeyPath:@"rows" context:WKDRowsContext];
		_tableModel = nil;
	}
	[self.rows unbind:NSContentArrayBinding];
}

/* The columns, as the property has them: data, not layout. */
- (void)makeColumns
{
	for (NSTableColumn *column in [[self.tableView tableColumns] copy]) {
		[self.tableView removeTableColumn:column];
	}
	WKDProperty *property = _tableModel.property;
	double shares = 0;
	for (WKDColumn *column in property.columns) {
		shares += column.share;
	}
	double inner = NSWidth([[self.tableView enclosingScrollView] bounds]) - 6;
	for (NSUInteger i = 0; i < [property.columns count]; i++) {
		WKDColumn *column = [property.columns objectAtIndex:i];
		NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:[_tableModel.columnKeys objectAtIndex:i]];
		[[tableColumn headerCell] setStringValue:column.title];
		[tableColumn setWidth:shares > 0 ? floor(inner * column.share / shares) : 80];
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
		[self.tableView addTableColumn:tableColumn];
	}
	[self.tableView reloadData];
	[self.emptyLabel setStringValue:property.placeholder ?: @""];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context != WKDRowsContext) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	if ([[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue]) {
		/* Read again: the row selected kept selected. */
		if (_keep < 0) {
			_keep = [self.tableView selectedRow];
		}
		return;
	}
	[self rowsChanged];
}

- (void)rowsChanged
{
	[self.tableView reloadData];
	BOOL usable = _tableModel.elementId != nil;
	NSUInteger count = [_tableModel.rows count];
	if (_keep >= (NSInteger)count) {
		_keep = (NSInteger)count - 1;
	}
	if (_keep >= 0) {
		[self.rows setSelectionIndex:(NSUInteger)_keep];
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)_keep] byExtendingSelection:NO];
	} else {
		[self.rows setSelectionIndexes:[NSIndexSet indexSet]];
		[self.tableView deselectAll:nil];
	}
	_keep = -1;
	[self.emptyLabel setHidden:count > 0 || !usable];
	[self.addButton setEnabled:usable];
	[self.removeButton setEnabled:usable && [self.tableView selectedRow] >= 0];
	[self.tableView setEnabled:usable];
}

#pragma mark Editing

- (IBAction)addRow:(id)sender
{
	_keep = (NSInteger)[_tableModel.rows count];
	[_tableModel addRow];
}

- (IBAction)removeRow:(id)sender
{
	NSInteger selected = [self.tableView selectedRow];
	if (selected < 0) {
		return;
	}
	_keep = MIN(selected, (NSInteger)[_tableModel.rows count] - 2);
	[_tableModel removeRowAtIndex:(NSUInteger)selected];
}

- (void)cellDidBeginEditing:(NSNotification *)notification
{
	_tableModel.editing = YES;
}

- (void)cellDidEndEditing:(NSNotification *)notification
{
	_tableModel.editing = NO;
	if (self.explained != nil) {
		self.explained(nil);
	}
}

/* An expression being typed: what the engine says of it. */
- (void)cellTextDidChange:(NSNotification *)notification
{
	NSInteger column = [self.tableView editedColumn];
	NSArray *columns = _tableModel.property.columns;
	if (column < 0 || column >= (NSInteger)[columns count]) {
		return;
	}
	WKDColumn *edited = [columns objectAtIndex:(NSUInteger)column];
	NSText *text = [[notification userInfo] objectForKey:@"NSFieldEditor"];
	if (edited.holdsExpression && [text isKindOfClass:[NSText class]] && self.explained != nil) {
		NSError *problem = [WFFeelExpression problemInText:[text string] place:edited.place];
		self.explained(problem != nil ? [NSString stringWithFormat:@"%@: %@", edited.title,
		                                                           [problem localizedDescription]] : nil);
	}
}

#pragma mark The table: the array controller's rows

/* Its arranged rows, its content the table model's rows. */
- (NSArray<WKDTableItem *> *)arranged
{
	return [self.rows arrangedObjects];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[[self arranged] count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *rows = [self arranged];
	return row >= 0 && row < (NSInteger)[rows count] ? [[rows objectAtIndex:(NSUInteger)row] valueForKey:[tableColumn identifier]]
	                                                 : nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row
{
	NSArray *rows = [self arranged];
	if (row >= 0 && row < (NSInteger)[rows count]) {
		_keep = row;
		[[rows objectAtIndex:(NSUInteger)row] setValue:object forKey:[tableColumn identifier]];
	}
}

#pragma mark The table's delegate

- (WKDColumn *)columnOf:(NSTableColumn *)tableColumn
{
	NSUInteger index = [_tableModel.columnKeys indexOfObject:[tableColumn identifier]];
	return index < [_tableModel.property.columns count] ? [_tableModel.property.columns objectAtIndex:index] : nil;
}

/* An expression, coloured, while it is not typed in. */
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row
{
	WKDColumn *column = [self columnOf:tableColumn];
	BOOL edited = [tableView editedRow] == row
		&& [[tableView tableColumns] indexOfObjectIdenticalTo:tableColumn] == (NSUInteger)[tableView editedColumn];
	if (column.holdsExpression && !edited && [cell isKindOfClass:[NSTextFieldCell class]]) {
		NSString *text = [[cell objectValue] isKindOfClass:[NSString class]] ? [cell objectValue] : [cell stringValue];
		[cell setAttributedStringValue:WKDColouredExpression(text ?: @"", column.place, [NSFont systemFontOfSize:11])];
	}
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation
{
	WKDColumn *column = [self columnOf:tableColumn];
	if (!column.holdsExpression) {
		return nil;
	}
	return [[WFFeelExpression problemInText:[cell stringValue] ?: @"" place:column.place] localizedDescription];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger selected = [self.tableView selectedRow];
	[self.removeButton setEnabled:selected >= 0 && _tableModel.elementId != nil];
	if (self.selectionChanged != nil) {
		self.selectionChanged(selected);
	}
}

@end

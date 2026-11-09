#import "WKDTableModel.h"

@interface WKDTableItem ()
@property (nonatomic, readwrite, weak) WKDTableModel *table;
@property (nonatomic, readwrite, strong) WKDRow *row;
@end

@implementation WKDTableItem

/* The column of a key: c0 is the first. */
static NSUInteger
WKDColumnOfKey(NSString *key)
{
	if (![key hasPrefix:@"c"] || [key length] < 2) {
		return NSNotFound;
	}
	NSScanner *scanner = [NSScanner scannerWithString:[key substringFromIndex:1]];
	NSInteger column = 0;
	return [scanner scanInteger:&column] && [scanner isAtEnd] && column >= 0 ? (NSUInteger)column : NSNotFound;
}

- (id)valueForUndefinedKey:(NSString *)key
{
	NSUInteger index = WKDColumnOfKey(key);
	NSArray *columns = self.table.property.columns;
	if (index >= [columns count]) {
		return [super valueForUndefinedKey:key];
	}
	WKDColumn *column = [columns objectAtIndex:index];
	NSString *value = index < [self.row.values count] ? [self.row.values objectAtIndex:index] : @"";
	if (column.kind == WKDPropertyCheck) {
		return @([value isEqualToString:@"true"]);
	}
	if (column.kind == WKDPropertyChoice) {
		NSUInteger choice = [column.values indexOfObject:value];
		return @(choice == NSNotFound ? 0 : (NSInteger)choice);
	}
	return value;
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
	NSUInteger index = WKDColumnOfKey(key);
	NSUInteger row = [self.table.rows indexOfObjectIdenticalTo:self];
	if (index >= [self.table.property.columns count] || row == NSNotFound) {
		[super setValue:value forUndefinedKey:key];
		return;
	}
	[self.table setValue:value column:index row:row];
}

@end

@implementation WKDTableModel

- (instancetype)initWithEditor:(WKDEditor *)editor elementId:(NSString *)elementId property:(WKDProperty *)property
                        master:(NSUInteger)master
{
	if ((self = [super init])) {
		_editor = editor;
		_property = property;
		_master = master;
		NSMutableArray *keys = [NSMutableArray array];
		for (NSUInteger i = 0; i < [property.columns count]; i++) {
			[keys addObject:[NSString stringWithFormat:@"c%lu", (unsigned long)i]];
		}
		_columnKeys = keys;
		[self reloadOf:elementId];
	}
	return self;
}

- (void)reloadOf:(NSString *)elementId
{
	_elementId = [elementId copy];
	if (_editing) {
		return;
	}
	NSArray *rows = _editor != nil && _elementId != nil ? [_property rowsIn:_editor of:_elementId master:_master] : @[];
	NSMutableArray *items = [NSMutableArray arrayWithCapacity:[rows count]];
	for (WKDRow *row in rows) {
		WKDTableItem *item = [[WKDTableItem alloc] init];
		item.table = self;
		item.row = row;
		[items addObject:item];
	}
	[self willChangeValueForKey:@"rows"];
	_rows = items;
	[self didChangeValueForKey:@"rows"];
}

/* The rows as they are to be: one change, then read again. */
- (BOOL)write:(NSArray<WKDRow *> *)rows
{
	NSString *reason = nil;
	BOOL done = [_property setRows:rows in:_editor of:_elementId master:_master error:&reason];
	if (self.refused != nil) {
		self.refused(done ? nil : reason);
	}
	BOOL editing = _editing;
	_editing = NO;
	[self reloadOf:_elementId];
	_editing = editing;
	return done;
}

- (NSArray<WKDRow *> *)currentRows
{
	NSMutableArray *rows = [NSMutableArray arrayWithCapacity:[_rows count]];
	for (WKDTableItem *item in _rows) {
		[rows addObject:item.row];
	}
	return rows;
}

- (NSUInteger)addRow
{
	NSMutableArray *rows = [[self currentRows] mutableCopy];
	[rows addObject:[WKDRow rowWithValues:_property.blankRow ?: @[]]];
	[self write:rows];
	return [_rows count] - 1;
}

- (void)removeRowAtIndex:(NSUInteger)index
{
	NSMutableArray *rows = [[self currentRows] mutableCopy];
	if (index >= [rows count]) {
		return;
	}
	[rows removeObjectAtIndex:index];
	[self write:rows];
}

- (void)setValue:(id)value column:(NSUInteger)column row:(NSUInteger)row
{
	NSMutableArray *rows = [[self currentRows] mutableCopy];
	if (row >= [rows count] || column >= [_property.columns count]) {
		return;
	}
	WKDColumn *kind = [_property.columns objectAtIndex:column];
	NSString *text = kind.kind == WKDPropertyChoice
		? [kind.values objectAtIndex:(NSUInteger)MAX(0, MIN([value integerValue], (NSInteger)[kind.values count] - 1))]
		: kind.kind == WKDPropertyCheck ? ([value boolValue] ? @"true" : @"false")
		: [value isKindOfClass:[NSAttributedString class]] ? [value string] : [value description] ?: @"";
	WKDRow *was = [rows objectAtIndex:row];
	NSMutableArray *values = [was.values mutableCopy];
	while ([values count] <= column) {
		[values addObject:@""];
	}
	if ([[values objectAtIndex:column] isEqualToString:text]) {
		return;
	}
	[values replaceObjectAtIndex:column withObject:text];
	WKDRow *edited = [WKDRow rowWithValues:values];
	edited.source = was.source;
	[rows replaceObjectAtIndex:row withObject:edited];
	[self write:rows];
}

- (NSArray<WKDTableModel *> *)detailsForRow:(NSUInteger)row
{
	NSUInteger master = row < [_rows count] ? [_rows objectAtIndex:row].row.source : NSNotFound;
	NSMutableArray *details = [NSMutableArray array];
	for (WKDProperty *detail in _property.details) {
		WKDTableModel *table = [[WKDTableModel alloc] initWithEditor:_editor elementId:master != NSNotFound ? _elementId : nil
		                                                    property:detail master:master];
		table.refused = self.refused;
		[details addObject:table];
	}
	return details;
}

@end

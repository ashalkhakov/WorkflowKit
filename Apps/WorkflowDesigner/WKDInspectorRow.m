#import "WKDInspectorRow.h"
#import "WKDExpressionField.h"
#import "WKDTableRowController.h"

/* The row XIBs, loaded once each. */
static NSNib *
WKDRowNib(NSString *name)
{
	static NSMutableDictionary *nibs;
	if (nibs == nil) {
		nibs = [NSMutableDictionary dictionary];
	}
	NSNib *nib = [nibs objectForKey:name];
	if (nib == nil) {
		nib = [[NSNib alloc] initWithNibNamed:name bundle:[NSBundle bundleForClass:[WKDInspectorRow class]]];
		if (nib != nil) {
			[nibs setObject:nib forKey:name];
		}
	}
	return nib;
}

static NSString *
WKDBindingOf(WKDProperty *property)
{
	return property.kind == WKDPropertyChoice ? NSSelectedIndexBinding : NSValueBinding;
}

/* A flipped view, rows stacked down it: a table's, and its details'. */
@interface WKDRowStack : NSView
@end

@implementation WKDRowStack
- (BOOL)isFlipped
{
	return YES;
}
@end

@interface WKDInspectorRow () <NSTextViewDelegate>
@property (nonatomic, readwrite, strong) WKDProperty *property;
@property (nonatomic, readwrite, strong) WKDElementModel *model;
@property (nonatomic, readwrite, copy) NSString *key;
@end

@implementation WKDInspectorRow
{
	NSArray *_topLevelObjects;
	BOOL _bound;
	BOOL _observing;
	WKDTableRowController *_table;
	NSMutableArray<WKDTableRowController *> *_details;
}

- (BOOL)load:(NSString *)name
{
	NSArray *objects = nil;
	if (![WKDRowNib(name) instantiateWithOwner:self topLevelObjects:&objects]) {
		return NO;
	}
	_topLevelObjects = objects;
	return self.view != nil;
}

+ (instancetype)titleRow:(NSString *)title
{
	WKDInspectorRow *row = [[self alloc] init];
	if (![row load:@"WKDRowTitle"]) {
		return nil;
	}
	[row.label setStringValue:title];
	return row;
}

+ (instancetype)rowForProperty:(WKDProperty *)property model:(WKDElementModel *)model
{
	WKDInspectorRow *row = [[self alloc] init];
	row.property = property;
	row.model = model;
	row.key = [model keyOf:property];
	NSString *name = nil;
	switch (property.kind) {
	case WKDPropertyLongText:
		name = @"WKDRowLongText";
		break;
	case WKDPropertyCheck:
		name = @"WKDRowCheck";
		break;
	case WKDPropertyChoice:
		name = @"WKDRowChoice";
		break;
	case WKDPropertyButton:
		name = @"WKDRowButton";
		break;
	case WKDPropertyTable:
		return [row loadTable] ? row : nil;
	default:
		name = property.holdsExpression ? @"WKDRowExpression" : @"WKDRowText";
		break;
	}
	if (![row load:name]) {
		return nil;
	}
	[row connect];
	return row;
}

- (void)dealloc
{
	[self unbind];
}

#pragma mark Connecting

- (void)connect
{
	WKDProperty *property = self.property;
	[self.label setStringValue:property.label];
	NSDictionary *options = @{ NSContinuouslyUpdatesValueBindingOption: @NO };
	switch (property.kind) {
	case WKDPropertyCheck:
		[self.control setTitle:property.label];
		[self.control bind:NSValueBinding toObject:self.model withKeyPath:self.key options:nil];
		_bound = YES;
		break;
	case WKDPropertyChoice:
		[(NSPopUpButton *)self.control removeAllItems];
		[(NSPopUpButton *)self.control addItemsWithTitles:property.titles];
		[self.control bind:NSSelectedIndexBinding toObject:self.model withKeyPath:self.key options:nil];
		_bound = YES;
		break;
	case WKDPropertyButton:
		[self.control setTitle:property.label];
		[self.control setTarget:nil];
		[self.control setAction:NSSelectorFromString(property.actionName)];
		break;
	case WKDPropertyLongText:
		[(NSTextView *)self.control setDelegate:self];
		[self observe];
		break;
	default:
		if ([self.control isKindOfClass:[WKDExpressionField class]]) {
			/* Coloured, and checked as it is typed, as the engine reads it
			 * there. A view, not a control: kept to the model by hand. */
			WKDExpressionField *field = self.control;
			field.place = property.place;
			field.placeholderString = property.placeholder;
			field.delegate = self;
			field.target = self;
			field.action = @selector(expressionChanged:);
			[self observe];
		} else {
			[[self.control cell] setPlaceholderString:property.placeholder];
			[self.control setDelegate:(id)self];
			[self.control bind:NSValueBinding toObject:self.model withKeyPath:self.key options:options];
			_bound = YES;
		}
		break;
	}
}

- (void)unbind
{
	if (_bound) {
		[self.control unbind:WKDBindingOf(self.property)];
		_bound = NO;
	}
	if (_observing) {
		[self.model removeObserver:self forKeyPath:self.key];
		_observing = NO;
	}
	[_table unbind];
	for (WKDTableRowController *detail in _details) {
		[detail unbind];
	}
}

/* The views that are not controls, kept to the model's value. */
- (void)observe
{
	[self.model addObserver:self forKeyPath:self.key options:NSKeyValueObservingOptionInitial context:NULL];
	_observing = YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	NSString *value = [self.model valueForKey:self.key] ?: @"";
	if ([self.control isKindOfClass:[NSTextView class]]) {
		[(NSTextView *)self.control setString:value];
	} else {
		[(WKDExpressionField *)self.control setStringValue:value];
	}
}

#pragma mark Typing

- (void)controlTextDidBeginEditing:(NSNotification *)notification
{
	self.model.editingKey = self.key;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
	if ([self.model.editingKey isEqualToString:self.key]) {
		self.model.editingKey = nil;
	}
}

/* An expression being typed: what the engine says of it, while it does. */
- (void)controlTextDidChange:(NSNotification *)notification
{
	WKDExpressionField *field = [notification object];
	if (![field isKindOfClass:[WKDExpressionField class]]) {
		return;
	}
	self.model.editingKey = self.key;
	NSString *problem = [self.model problemWithText:field.stringValue forKey:self.key];
	if (self.explained != nil) {
		self.explained(problem != nil ? [NSString stringWithFormat:@"%@: %@", self.property.label, problem] : nil);
	}
}

- (void)expressionChanged:(WKDExpressionField *)field
{
	self.model.editingKey = nil;
	if (self.explained != nil) {
		self.explained(nil);
	}
	[self.model setValue:field.stringValue forKey:self.key];
}

- (void)textDidBeginEditing:(NSNotification *)notification
{
	self.model.editingKey = self.key;
}

- (void)textDidEndEditing:(NSNotification *)notification
{
	self.model.editingKey = nil;
	[self.model setValue:[[(NSTextView *)self.control string] copy] forKey:self.key];
}

#pragma mark A table, and its rows' tables

- (BOOL)loadTable
{
	WKDTableModel *table = [self.model tableModelForKey:self.key];
	_table = [[WKDTableRowController alloc] initWithTableModel:table title:self.property.label];
	if (_table == nil) {
		return NO;
	}
	_details = [NSMutableArray array];
	WKDRowStack *stack = [[WKDRowStack alloc] initWithFrame:NSMakeRect(0, 0, NSWidth([_table.view frame]), 0)];
	[stack setAutoresizingMask:NSViewWidthSizable];
	double y = 0;
	NSMutableArray *parts = [NSMutableArray arrayWithObject:_table];
	for (WKDProperty *detail in self.property.details) {
		WKDTableRowController *part = [[WKDTableRowController alloc]
			initWithTableModel:[[WKDTableModel alloc] initWithEditor:table.editor elementId:nil property:detail master:NSNotFound]
			             title:[NSString stringWithFormat:@"%@ of the row selected above", detail.label]];
		[_details addObject:part];
		[parts addObject:part];
	}
	for (WKDTableRowController *part in parts) {
		NSView *view = part.view;
		[view setFrameOrigin:NSMakePoint(0, y)];
		[view setAutoresizingMask:NSViewWidthSizable];
		[stack addSubview:view];
		y += NSHeight([view frame]);
	}
	[stack setFrameSize:NSMakeSize(NSWidth([_table.view frame]), y)];
	self.view = stack;
	__weak WKDInspectorRow *weakSelf = self;
	_table.selectionChanged = ^(NSInteger row) {
		[weakSelf showDetailsOf:row];
	};
	_table.explained = ^(NSString *problem) {
		if (weakSelf.explained != nil) {
			weakSelf.explained(problem);
		}
	};
	[self showDetailsOf:-1];
	return YES;
}

- (void)showDetailsOf:(NSInteger)row
{
	NSArray *models = row >= 0 ? [_table.tableModel detailsForRow:(NSUInteger)row] : nil;
	for (NSUInteger i = 0; i < [_details count]; i++) {
		WKDTableRowController *detail = [_details objectAtIndex:i];
		WKDProperty *property = [self.property.details objectAtIndex:i];
		WKDTableModel *model = i < [models count] ? [models objectAtIndex:i]
			: [[WKDTableModel alloc] initWithEditor:_table.tableModel.editor elementId:nil property:property master:NSNotFound];
		model.refused = _table.tableModel.refused;
		detail.title = row >= 0 ? [NSString stringWithFormat:@"%@ of row %ld", property.label, (long)row + 1]
		                        : [NSString stringWithFormat:@"%@ of the row selected above", property.label];
		detail.tableModel = model;
	}
}

@end

#import "WKDOutline.h"
#import "WKDDiagram.h"
#import "WKDXML.h"

/* A row: what it shows and the element it is. */
@interface WKDOutlineItem : NSObject
@property (nonatomic, copy) NSString *elementId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSMutableArray<WKDOutlineItem *> *children;
@end

@implementation WKDOutlineItem
@end

/* A node's type as words: userTask is "User task". */
static NSString *
WKDWords(NSString *type)
{
	NSMutableString *words = [NSMutableString string];
	for (NSUInteger i = 0; i < [type length]; i++) {
		unichar c = [type characterAtIndex:i];
		if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) {
			[words appendString:@" "];
			[words appendString:[[NSString stringWithCharacters:&c length:1] lowercaseString]];
		} else {
			[words appendString:i == 0 ? [[NSString stringWithCharacters:&c length:1] uppercaseString]
			                           : [NSString stringWithCharacters:&c length:1]];
		}
	}
	return words;
}

static NSString *
WKDTitle(WKDShape *shape)
{
	return [shape.name length] > 0 ? shape.name : WKDWords(shape.type);
}

@implementation WKDOutline
{
	NSOutlineView *_outlineView;
	WKDOutlineItem *_root;
	BOOL _selecting;
}

- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView
{
	if ((self = [super init])) {
		_outlineView = outlineView;
		[outlineView setDataSource:(id)self];
		[outlineView setDelegate:(id)self];
	}
	return self;
}

- (WKDOutlineItem *)itemFor:(WKDShape *)shape in:(WKDDiagram *)diagram
{
	WKDOutlineItem *item = [[WKDOutlineItem alloc] init];
	item.elementId = shape.elementId;
	item.title = WKDTitle(shape);
	item.children = [NSMutableArray array];
	NSMutableArray *inside = [NSMutableArray array];
	if (WKDIsContainerType(shape.type)) {
		[inside addObjectsFromArray:[diagram shapesIn:shape]];
	}
	for (WKDShape *other in diagram.shapes) {
		if (other.host == shape) {
			[inside addObject:other];
		}
	}
	for (WKDShape *child in inside) {
		[item.children addObject:[self itemFor:child in:diagram]];
	}
	for (WKDConnection *connection in diagram.connections) {
		if (connection.source == shape) {
			WKDOutlineItem *flow = [[WKDOutlineItem alloc] init];
			flow.elementId = connection.elementId;
			flow.title = [connection.name length] > 0
				? [NSString stringWithFormat:@"%@ → %@", connection.name, WKDTitle(connection.target)]
				: [NSString stringWithFormat:@"→ %@", WKDTitle(connection.target)];
			[item.children addObject:flow];
		}
	}
	return item;
}

- (void)showDiagram:(WKDDiagram *)diagram
{
	WKDOutlineItem *root = [[WKDOutlineItem alloc] init];
	root.elementId = WKDAttribute(diagram.process, @"id");
	root.title = WKDAttribute(diagram.process, @"name") ?: @"Process";
	root.children = [NSMutableArray array];
	for (WKDShape *shape in [diagram shapesIn:nil]) {
		[root.children addObject:[self itemFor:shape in:diagram]];
	}
	_root = root;
	NSString *selected = [self selectedId];
	_selecting = YES;
	[_outlineView reloadData];
	/* The root by name: gnustep-gui expands nothing from nil. */
	if (_root != nil) {
		[_outlineView expandItem:_root expandChildren:YES];
	}
	_selecting = NO;
	[self select:selected];
}

- (NSString *)selectedId
{
	NSInteger row = [_outlineView selectedRow];
	return row >= 0 ? [(WKDOutlineItem *)[_outlineView itemAtRow:row] elementId] : nil;
}

- (void)select:(NSString *)elementId
{
	_selecting = YES;
	NSInteger found = -1;
	for (NSInteger row = 0; row < [_outlineView numberOfRows] && elementId != nil; row++) {
		if ([[(WKDOutlineItem *)[_outlineView itemAtRow:row] elementId] isEqualToString:elementId]) {
			found = row;
			break;
		}
	}
	if (found >= 0) {
		[_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)found] byExtendingSelection:NO];
		[_outlineView scrollRowToVisible:found];
	} else {
		[_outlineView deselectAll:nil];
	}
	_selecting = NO;
}

#pragma mark Data source and delegate

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (item == nil) {
		return _root != nil ? 1 : 0;
	}
	return (NSInteger)[[(WKDOutlineItem *)item children] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	return item == nil ? _root : [[(WKDOutlineItem *)item children] objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [[(WKDOutlineItem *)item children] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
	return [(WKDOutlineItem *)item title];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)column item:(id)item
{
	return NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	NSString *selected = [self selectedId];
	if (!_selecting && selected != nil) {
		[self.delegate outline:self didSelect:selected];
	}
}

@end

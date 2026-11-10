#import "WKDSelection.h"

NSString * const WKDSelectionDidChangeNotification = @"WKDSelectionDidChange";

@implementation WKDSelection

- (instancetype)init
{
	if ((self = [super init])) {
		_selectedIds = @[];
	}
	return self;
}

- (void)setSelectedIds:(NSArray<NSString *> *)selectedIds
{
	selectedIds = selectedIds ?: @[];
	if ([selectedIds isEqualToArray:_selectedIds]) {
		return;
	}
	[self willChangeValueForKey:@"selectedId"];
	_selectedIds = [selectedIds copy];
	[self didChangeValueForKey:@"selectedId"];
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDSelectionDidChangeNotification object:self];
}

+ (BOOL)automaticallyNotifiesObserversOfSelectedId
{
	return NO;
}

- (NSString *)selectedId
{
	return [_selectedIds firstObject];
}

- (void)keepOnly:(NSSet<NSString *> *)existing
{
	NSMutableArray *kept = [NSMutableArray array];
	for (NSString *elementId in _selectedIds) {
		if ([existing containsObject:elementId]) {
			[kept addObject:elementId];
		}
	}
	self.selectedIds = kept;
}

@end

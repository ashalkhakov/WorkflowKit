#import "WKDEditorPriv.h"

/*
 * Several shapes at once, as RDLKit's designer arranges report items:
 * nudged with the arrow keys, lined up with the first selected -- the
 * anchor -- and spread out evenly. What a selected subprocess holds, or a
 * selected activity has attached, moves with it and is not arranged on
 * its own.
 */
@implementation WKDEditor (WKDAlignment)

/* The shapes of the ids that have bounds and are not inside or on another
 * of them, in the order given. */
- (NSArray<WKDShape *> *)arrangedShapes:(NSArray<NSString *> *)elementIds
{
	NSMutableArray *shapes = [NSMutableArray array];
	for (NSString *elementId in elementIds) {
		WKDShape *shape = [self.diagram shapeWithId:elementId];
		BOOL carried = NO;
		for (WKDShape *up = shape.host ?: shape.parent; up != nil && !carried; up = up.host ?: up.parent) {
			carried = [elementIds containsObject:up.elementId];
		}
		if (shape.hasBounds && !carried && ![shapes containsObject:shape]) {
			[shapes addObject:shape];
		}
	}
	return shapes;
}

- (void)nudgeElements:(NSArray<NSString *> *)elementIds by:(NSSize)offset
{
	NSMutableDictionary *offsets = [NSMutableDictionary dictionary];
	for (WKDShape *shape in [self arrangedShapes:elementIds]) {
		[offsets setObject:[NSValue valueWithSize:offset] forKey:shape.elementId];
	}
	[self moveShapes:offsets action:@"Nudge" coalescing:YES];
}

- (BOOL)alignElements:(NSArray<NSString *> *)elementIds to:(WKDAlignment)alignment
{
	NSArray *shapes = [self arrangedShapes:elementIds];
	if ([shapes count] < 2) {
		return NO;
	}
	NSRect anchor = [[shapes firstObject] bounds];
	NSMutableDictionary *offsets = [NSMutableDictionary dictionary];
	for (WKDShape *shape in [shapes subarrayWithRange:NSMakeRange(1, [shapes count] - 1)]) {
		NSRect r = shape.bounds;
		NSSize by = NSZeroSize;
		switch (alignment) {
		case WKDAlignLeft:
			by.width = NSMinX(anchor) - NSMinX(r);
			break;
		case WKDAlignCentre:
			by.width = NSMidX(anchor) - NSMidX(r);
			break;
		case WKDAlignRight:
			by.width = NSMaxX(anchor) - NSMaxX(r);
			break;
		case WKDAlignTop:
			by.height = NSMinY(anchor) - NSMinY(r);
			break;
		case WKDAlignMiddle:
			by.height = NSMidY(anchor) - NSMidY(r);
			break;
		case WKDAlignBottom:
			by.height = NSMaxY(anchor) - NSMaxY(r);
			break;
		}
		by = NSMakeSize(round(by.width), round(by.height));
		[offsets setObject:[NSValue valueWithSize:by] forKey:shape.elementId];
	}
	[self moveShapes:offsets action:@"Align" coalescing:NO];
	return YES;
}

- (BOOL)distributeElements:(NSArray<NSString *> *)elementIds vertically:(BOOL)vertically
{
	NSArray *shapes = [self arrangedShapes:elementIds];
	if ([shapes count] < 3) {
		return NO;
	}
	/* In order along the axis, the outermost two staying where they are
	 * and the gaps between neighbours made equal. */
	shapes = [shapes sortedArrayUsingComparator:^NSComparisonResult(WKDShape *a, WKDShape *b) {
		double x = vertically ? NSMinY(a.bounds) : NSMinX(a.bounds), y = vertically ? NSMinY(b.bounds) : NSMinX(b.bounds);
		return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
	}];
	double start = vertically ? NSMinY([[shapes firstObject] bounds]) : NSMinX([[shapes firstObject] bounds]);
	double end = vertically ? NSMaxY([[shapes lastObject] bounds]) : NSMaxX([[shapes lastObject] bounds]);
	double sizes = 0;
	for (WKDShape *shape in shapes) {
		sizes += vertically ? NSHeight(shape.bounds) : NSWidth(shape.bounds);
	}
	double gap = (end - start - sizes) / ([shapes count] - 1);
	NSMutableDictionary *offsets = [NSMutableDictionary dictionary];
	double at = start;
	for (WKDShape *shape in shapes) {
		double now = vertically ? NSMinY(shape.bounds) : NSMinX(shape.bounds);
		double by = round(at - now);
		[offsets setObject:[NSValue valueWithSize:vertically ? NSMakeSize(0, by) : NSMakeSize(by, 0)]
		            forKey:shape.elementId];
		at += (vertically ? NSHeight(shape.bounds) : NSWidth(shape.bounds)) + gap;
	}
	[self moveShapes:offsets action:@"Distribute" coalescing:NO];
	return YES;
}

@end

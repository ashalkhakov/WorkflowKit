#import "WKDNotation.h"
#import "WKDXML.h"

WKDShapeKind
WKDKindOfType(NSString *type, BOOL *isFlowNode)
{
	static NSDictionary *kinds;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableDictionary *table = [NSMutableDictionary dictionary];
		for (NSString *name in @[ @"startEvent", @"endEvent", @"intermediateCatchEvent", @"intermediateThrowEvent",
		                          @"boundaryEvent" ]) {
			[table setObject:@(WKDShapeEvent) forKey:name];
		}
		for (NSString *name in @[ @"task", @"userTask", @"serviceTask", @"scriptTask", @"sendTask", @"receiveTask",
		                          @"manualTask", @"businessRuleTask", @"callActivity", @"subProcess",
		                          @"transaction", @"adHocSubProcess" ]) {
			[table setObject:@(WKDShapeActivity) forKey:name];
		}
		for (NSString *name in @[ @"exclusiveGateway", @"parallelGateway", @"inclusiveGateway",
		                          @"eventBasedGateway", @"complexGateway" ]) {
			[table setObject:@(WKDShapeGateway) forKey:name];
		}
		for (NSString *name in @[ @"textAnnotation", @"dataObjectReference", @"dataStoreReference" ]) {
			[table setObject:@(WKDShapeArtifact) forKey:name];
		}
		kinds = table;
	});
	NSNumber *kind = [kinds objectForKey:type];
	if (isFlowNode != NULL) {
		*isFlowNode = kind != nil;
	}
	return kind != nil ? (WKDShapeKind)[kind integerValue] : WKDShapeArtifact;
}

BOOL
WKDIsContainerType(NSString *type)
{
	return [type isEqualToString:@"subProcess"] || [type isEqualToString:@"transaction"]
		|| [type isEqualToString:@"adHocSubProcess"];
}

NSRect
WKDNodeLabelRect(NSString *type, NSRect rect)
{
	WKDShapeKind kind = WKDKindOfType(type, NULL);
	if (kind != WKDShapeEvent && kind != WKDShapeGateway) {
		return NSZeroRect;
	}
	return NSMakeRect(NSMidX(rect) - 50, NSMaxY(rect) + 2, 100, 30);
}

const double WKDLaneBandWidth = 30;

NSRect
WKDLaneBandRect(NSRect rect, BOOL horizontal)
{
	return horizontal ? NSMakeRect(NSMinX(rect), NSMinY(rect), MIN(WKDLaneBandWidth, NSWidth(rect)), NSHeight(rect))
	                  : NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), MIN(WKDLaneBandWidth, NSHeight(rect)));
}

NSRect
WKDFlowLabelRect(NSArray<NSValue *> *points)
{
	if ([points count] < 2) {
		return NSZeroRect;
	}
	NSUInteger middle = ([points count] - 1) / 2;
	NSPoint a = [[points objectAtIndex:middle] pointValue], b = [[points objectAtIndex:middle + 1] pointValue];
	return NSMakeRect((a.x + b.x) / 2 - 50, (a.y + b.y) / 2 - 20, 100, 18);
}

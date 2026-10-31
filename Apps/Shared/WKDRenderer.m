#import "WKDRenderer.h"
#import "WKDDiagram.h"

@implementation WKDLook

+ (instancetype)lookOfType:(NSString *)type eventDefinition:(NSString *)eventDefinition
{
	WKDLook *look = [[self alloc] init];
	look.type = type;
	look.eventDefinition = eventDefinition;
	look.interrupting = YES;
	return look;
}

@end

/* Between WKDBeginDrawing(NO) and WKDEndDrawing(): black on white, as a
 * DiagramKit canvas draws a light view, a print or an export. Otherwise the
 * appearance's own colours. */
static BOOL WKDLight;

void
WKDBeginDrawing(BOOL dark)
{
	WKDLight = !dark;
}

void
WKDEndDrawing(void)
{
	WKDLight = NO;
}

NSColor *
WKDInkColor(void)
{
	return WKDLight ? [NSColor blackColor] : [NSColor textColor];
}

NSColor *
WKDPaperColor(void)
{
	return WKDLight ? [NSColor whiteColor] : [NSColor textBackgroundColor];
}

NSColor *
WKDSelectionColor(void)
{
	return [NSColor colorWithCalibratedRed:0.15 green:0.45 blue:0.95 alpha:1.0];
}

static void
WKDStroke(NSBezierPath *path, double width, BOOL dashed)
{
	[path setLineWidth:width];
	if (dashed) {
		CGFloat pattern[2] = { 4, 3 };
		[path setLineDash:pattern count:2 phase:0];
	}
	[path stroke];
}

static void
WKDDrawText(NSString *text, NSRect rect, double size)
{
	if ([text length] == 0) {
		return;
	}
	NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	[style setAlignment:NSTextAlignmentCenter];
	[style setLineBreakMode:NSLineBreakByWordWrapping];
	NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:size],
	                              NSForegroundColorAttributeName: WKDInkColor(),
	                              NSParagraphStyleAttributeName: style };
	NSRect needed = [text boundingRectWithSize:NSMakeSize(NSWidth(rect), 1000)
	                                   options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
	double height = MIN(NSHeight(needed), NSHeight(rect));
	NSRect centred = NSMakeRect(NSMinX(rect), NSMidY(rect) - height / 2, NSWidth(rect), height + 2);
	[text drawWithRect:centred options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
}

void
WKDDrawLabel(NSString *name, NSRect rect)
{
	if ([name length] == 0) {
		return;
	}
	NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	[style setAlignment:NSTextAlignmentCenter];
	[style setLineBreakMode:NSLineBreakByWordWrapping];
	NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:10],
	                              NSForegroundColorAttributeName: WKDInkColor(),
	                              NSParagraphStyleAttributeName: style };
	NSRect needed = [name boundingRectWithSize:NSMakeSize(MAX(NSWidth(rect), 20), 1000)
	                                   options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
	NSRect drawn = NSMakeRect(NSMinX(rect), NSMinY(rect), MAX(NSWidth(rect), 20),
	                          MAX(NSHeight(rect), NSHeight(needed) + 2));
	[name drawWithRect:drawn options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
}

#pragma mark Markers

static void
WKDEnvelope(NSRect box, BOOL filled)
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRect:box];
	if (filled) {
		[WKDInkColor() setFill];
		[path fill];
		[WKDPaperColor() setStroke];
	}
	NSBezierPath *flap = [NSBezierPath bezierPath];
	[flap moveToPoint:NSMakePoint(NSMinX(box), NSMinY(box))];
	[flap lineToPoint:NSMakePoint(NSMidX(box), NSMidY(box))];
	[flap lineToPoint:NSMakePoint(NSMaxX(box), NSMinY(box))];
	WKDStroke(flap, 1, NO);
	[WKDInkColor() setStroke];
	if (!filled) {
		WKDStroke(path, 1, NO);
	}
}

static void
WKDPolygon(NSArray *points, BOOL filled)
{
	NSBezierPath *path = [NSBezierPath bezierPath];
	for (NSUInteger i = 0; i < [points count]; i++) {
		NSPoint point = [[points objectAtIndex:i] pointValue];
		if (i == 0) {
			[path moveToPoint:point];
		} else {
			[path lineToPoint:point];
		}
	}
	[path closePath];
	if (filled) {
		[path fill];
	}
	WKDStroke(path, 1, NO);
}

static NSValue *
WKDP(double x, double y)
{
	return [NSValue valueWithPoint:NSMakePoint(x, y)];
}

/* An event's definition, in the middle of its circle. */
static void
WKDEventMarker(NSString *definition, NSRect circle, BOOL throwing)
{
	double r = NSWidth(circle) / 2, cx = NSMidX(circle), cy = NSMidY(circle);
	[WKDInkColor() setStroke];
	[WKDInkColor() setFill];
	if ([definition isEqualToString:@"timerEventDefinition"]) {
		NSRect face = NSInsetRect(circle, r * 0.35, r * 0.35);
		WKDStroke([NSBezierPath bezierPathWithOvalInRect:face], 1, NO);
		NSBezierPath *hands = [NSBezierPath bezierPath];
		[hands moveToPoint:NSMakePoint(cx, cy - r * 0.45)];
		[hands lineToPoint:NSMakePoint(cx, cy)];
		[hands lineToPoint:NSMakePoint(cx + r * 0.35, cy)];
		WKDStroke(hands, 1, NO);
	} else if ([definition isEqualToString:@"messageEventDefinition"]) {
		WKDEnvelope(NSMakeRect(cx - r * 0.5, cy - r * 0.33, r, r * 0.66), throwing);
	} else if ([definition isEqualToString:@"signalEventDefinition"]) {
		WKDPolygon(@[ WKDP(cx, cy - r * 0.5), WKDP(cx + r * 0.5, cy + r * 0.35), WKDP(cx - r * 0.5, cy + r * 0.35) ],
		           throwing);
	} else if ([definition isEqualToString:@"errorEventDefinition"]) {
		WKDPolygon(@[ WKDP(cx - r * 0.45, cy + r * 0.45), WKDP(cx - r * 0.2, cy - r * 0.4), WKDP(cx + r * 0.1, cy + r * 0.1),
		              WKDP(cx + r * 0.45, cy - r * 0.45), WKDP(cx + r * 0.2, cy + r * 0.4), WKDP(cx - r * 0.1, cy - r * 0.1) ],
		           throwing);
	} else if ([definition isEqualToString:@"escalationEventDefinition"]) {
		WKDPolygon(@[ WKDP(cx, cy - r * 0.5), WKDP(cx + r * 0.35, cy + r * 0.45), WKDP(cx, cy + r * 0.1),
		              WKDP(cx - r * 0.35, cy + r * 0.45) ], throwing);
	} else if ([definition isEqualToString:@"compensateEventDefinition"]) {
		WKDPolygon(@[ WKDP(cx - r * 0.5, cy), WKDP(cx, cy - r * 0.3), WKDP(cx, cy + r * 0.3) ], throwing);
		WKDPolygon(@[ WKDP(cx, cy), WKDP(cx + r * 0.5, cy - r * 0.3), WKDP(cx + r * 0.5, cy + r * 0.3) ], throwing);
	} else if ([definition isEqualToString:@"conditionalEventDefinition"]) {
		NSRect page = NSMakeRect(cx - r * 0.35, cy - r * 0.45, r * 0.7, r * 0.9);
		WKDStroke([NSBezierPath bezierPathWithRect:page], 1, NO);
		for (int line = 1; line <= 4; line++) {
			NSBezierPath *rule = [NSBezierPath bezierPath];
			double y = NSMinY(page) + NSHeight(page) * line / 5;
			[rule moveToPoint:NSMakePoint(NSMinX(page) + 2, y)];
			[rule lineToPoint:NSMakePoint(NSMaxX(page) - 2, y)];
			WKDStroke(rule, 1, NO);
		}
	} else if ([definition isEqualToString:@"linkEventDefinition"]) {
		WKDPolygon(@[ WKDP(cx - r * 0.45, cy - r * 0.15), WKDP(cx + r * 0.05, cy - r * 0.15), WKDP(cx + r * 0.05, cy - r * 0.4),
		              WKDP(cx + r * 0.5, cy), WKDP(cx + r * 0.05, cy + r * 0.4), WKDP(cx + r * 0.05, cy + r * 0.15),
		              WKDP(cx - r * 0.45, cy + r * 0.15) ], throwing);
	} else if ([definition isEqualToString:@"terminateEventDefinition"]) {
		[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circle, r * 0.4, r * 0.4)] fill];
	}
}

/* A task's type, in its top left corner. */
static void
WKDTaskMarker(NSString *type, NSRect rect)
{
	NSRect box = NSMakeRect(NSMinX(rect) + 6, NSMinY(rect) + 6, 14, 14);
	[WKDInkColor() setStroke];
	[WKDInkColor() setFill];
	if ([type isEqualToString:@"userTask"]) {
		WKDStroke([NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(box) - 3, NSMinY(box), 6, 6)], 1, NO);
		NSBezierPath *body = [NSBezierPath bezierPath];
		[body appendBezierPathWithArcWithCenter:NSMakePoint(NSMidX(box), NSMaxY(box)) radius:7 startAngle:180 endAngle:360
		                              clockwise:NO];
		WKDStroke(body, 1, NO);
	} else if ([type isEqualToString:@"serviceTask"]) {
		NSPoint c = NSMakePoint(NSMidX(box), NSMidY(box));
		for (int i = 0; i < 8; i++) {
			double a = i * M_PI / 4;
			NSBezierPath *tooth = [NSBezierPath bezierPath];
			[tooth moveToPoint:NSMakePoint(c.x + 4 * cos(a), c.y + 4 * sin(a))];
			[tooth lineToPoint:NSMakePoint(c.x + 7 * cos(a), c.y + 7 * sin(a))];
			WKDStroke(tooth, 2, NO);
		}
		WKDStroke([NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, 3, 3)], 1, NO);
	} else if ([type isEqualToString:@"scriptTask"]) {
		WKDStroke([NSBezierPath bezierPathWithRect:NSInsetRect(box, 2, 0)], 1, NO);
		for (int line = 1; line <= 3; line++) {
			NSBezierPath *rule = [NSBezierPath bezierPath];
			[rule moveToPoint:NSMakePoint(NSMinX(box) + 4, NSMinY(box) + line * 3.5)];
			[rule lineToPoint:NSMakePoint(NSMaxX(box) - 4, NSMinY(box) + line * 3.5)];
			WKDStroke(rule, 1, NO);
		}
	} else if ([type isEqualToString:@"sendTask"] || [type isEqualToString:@"receiveTask"]) {
		WKDEnvelope(NSMakeRect(NSMinX(box), NSMinY(box) + 2, 14, 10), [type isEqualToString:@"sendTask"]);
	} else if ([type isEqualToString:@"businessRuleTask"]) {
		NSRect table = NSMakeRect(NSMinX(box), NSMinY(box) + 2, 14, 10);
		WKDStroke([NSBezierPath bezierPathWithRect:table], 1, NO);
		NSBezierPath *grid = [NSBezierPath bezierPath];
		[grid moveToPoint:NSMakePoint(NSMinX(table), NSMinY(table) + 3)];
		[grid lineToPoint:NSMakePoint(NSMaxX(table), NSMinY(table) + 3)];
		[grid moveToPoint:NSMakePoint(NSMinX(table) + 5, NSMinY(table))];
		[grid lineToPoint:NSMakePoint(NSMinX(table) + 5, NSMaxY(table))];
		WKDStroke(grid, 1, NO);
	} else if ([type isEqualToString:@"manualTask"]) {
		NSBezierPath *hand = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(box), NSMinY(box) + 4, 14, 7)
		                                                     xRadius:3 yRadius:3];
		WKDStroke(hand, 1, NO);
	}
}

/* Multi-instance and loop markers, bottom centre. */
static void
WKDLoopMarker(NSString *loop, NSRect rect)
{
	if (loop == nil) {
		return;
	}
	double cx = NSMidX(rect), bottom = NSMaxY(rect) - 6;
	NSBezierPath *bars = [NSBezierPath bezierPath];
	if ([loop isEqualToString:@"parallel"]) {
		for (int i = -1; i <= 1; i++) {
			[bars moveToPoint:NSMakePoint(cx + i * 4, bottom - 10)];
			[bars lineToPoint:NSMakePoint(cx + i * 4, bottom)];
		}
	} else if ([loop isEqualToString:@"sequential"]) {
		for (int i = 0; i <= 2; i++) {
			[bars moveToPoint:NSMakePoint(cx - 5, bottom - 10 + i * 4)];
			[bars lineToPoint:NSMakePoint(cx + 5, bottom - 10 + i * 4)];
		}
	} else {
		[bars appendBezierPathWithArcWithCenter:NSMakePoint(cx, bottom - 5) radius:5 startAngle:-60 endAngle:240];
	}
	WKDStroke(bars, 1.5, NO);
}

#pragma mark Nodes

void
WKDDrawNode(WKDLook *look, NSRect rect, BOOL names)
{
	NSString *type = look.type;
	BOOL container = WKDIsContainerType(type);
	WKDShapeKind kind = WKDKindOfType(type, NULL);
	[WKDInkColor() setStroke];
	if (kind == WKDShapeEvent) {
		NSRect circle = NSInsetRect(rect, 1, 1);
		NSBezierPath *outline = [NSBezierPath bezierPathWithOvalInRect:circle];
		[WKDPaperColor() setFill];
		[outline fill];
		[WKDInkColor() setStroke];
		BOOL dashed = !look.interrupting;
		if ([type isEqualToString:@"startEvent"]) {
			WKDStroke(outline, 1.5, dashed);
		} else if ([type isEqualToString:@"endEvent"]) {
			WKDStroke(outline, 3.5, NO);
		} else {
			WKDStroke(outline, 1, dashed);
			WKDStroke([NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circle, 3, 3)], 1, dashed);
		}
		WKDEventMarker(look.eventDefinition, circle,
		               [type isEqualToString:@"endEvent"] || [type isEqualToString:@"intermediateThrowEvent"]);
		if (names) {
			WKDDrawText(look.name, WKDNodeLabelRect(type, rect), 10);
		}
		return;
	}
	if (kind == WKDShapeGateway) {
		NSBezierPath *diamond = [NSBezierPath bezierPath];
		[diamond moveToPoint:NSMakePoint(NSMidX(rect), NSMinY(rect))];
		[diamond lineToPoint:NSMakePoint(NSMaxX(rect), NSMidY(rect))];
		[diamond lineToPoint:NSMakePoint(NSMidX(rect), NSMaxY(rect))];
		[diamond lineToPoint:NSMakePoint(NSMinX(rect), NSMidY(rect))];
		[diamond closePath];
		[WKDPaperColor() setFill];
		[diamond fill];
		[WKDInkColor() setStroke];
		WKDStroke(diamond, 1.5, NO);
		double r = NSWidth(rect) / 2, cx = NSMidX(rect), cy = NSMidY(rect);
		NSBezierPath *marker = [NSBezierPath bezierPath];
		if ([type isEqualToString:@"exclusiveGateway"]) {
			[marker moveToPoint:NSMakePoint(cx - r * 0.3, cy - r * 0.3)];
			[marker lineToPoint:NSMakePoint(cx + r * 0.3, cy + r * 0.3)];
			[marker moveToPoint:NSMakePoint(cx + r * 0.3, cy - r * 0.3)];
			[marker lineToPoint:NSMakePoint(cx - r * 0.3, cy + r * 0.3)];
			WKDStroke(marker, 3, NO);
		} else if ([type isEqualToString:@"parallelGateway"] || [type isEqualToString:@"complexGateway"]) {
			[marker moveToPoint:NSMakePoint(cx, cy - r * 0.45)];
			[marker lineToPoint:NSMakePoint(cx, cy + r * 0.45)];
			[marker moveToPoint:NSMakePoint(cx - r * 0.45, cy)];
			[marker lineToPoint:NSMakePoint(cx + r * 0.45, cy)];
			if ([type isEqualToString:@"complexGateway"]) {
				[marker moveToPoint:NSMakePoint(cx - r * 0.3, cy - r * 0.3)];
				[marker lineToPoint:NSMakePoint(cx + r * 0.3, cy + r * 0.3)];
				[marker moveToPoint:NSMakePoint(cx + r * 0.3, cy - r * 0.3)];
				[marker lineToPoint:NSMakePoint(cx - r * 0.3, cy + r * 0.3)];
			}
			WKDStroke(marker, 3, NO);
		} else if ([type isEqualToString:@"inclusiveGateway"]) {
			WKDStroke([NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, r * 0.5, r * 0.5)], 2.5, NO);
		} else if ([type isEqualToString:@"eventBasedGateway"]) {
			NSRect inner = NSInsetRect(rect, r * 0.45, r * 0.45);
			WKDStroke([NSBezierPath bezierPathWithOvalInRect:inner], 1, NO);
			double p = NSWidth(inner) / 2 * 0.6;
			NSMutableArray *pentagon = [NSMutableArray array];
			for (int i = 0; i < 5; i++) {
				double a = -M_PI / 2 + i * 2 * M_PI / 5;
				[pentagon addObject:WKDP(cx + p * cos(a), cy + p * sin(a))];
			}
			WKDPolygon(pentagon, NO);
		}
		if (names) {
			WKDDrawText(look.name, WKDNodeLabelRect(type, rect), 10);
		}
		return;
	}
	if (kind == WKDShapeArtifact) {
		NSBezierPath *bracket = [NSBezierPath bezierPath];
		[bracket moveToPoint:NSMakePoint(NSMinX(rect) + 10, NSMinY(rect))];
		[bracket lineToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
		[bracket lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
		[bracket lineToPoint:NSMakePoint(NSMinX(rect) + 10, NSMaxY(rect))];
		WKDStroke(bracket, 1, NO);
		if (names) {
			WKDDrawText(look.name, NSInsetRect(rect, 6, 2), 10);
		}
		return;
	}
	NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 0.5, 0.5) xRadius:10 yRadius:10];
	[WKDPaperColor() setFill];
	[box fill];
	[WKDInkColor() setStroke];
	if ([type isEqualToString:@"callActivity"]) {
		WKDStroke(box, 3.5, NO);
	} else if (look.eventSubProcess) {
		CGFloat pattern[2] = { 1.5, 3 };
		[box setLineDash:pattern count:2 phase:0];
		WKDStroke(box, 1.5, NO);
	} else if ([type isEqualToString:@"transaction"]) {
		WKDStroke(box, 1, NO);
		WKDStroke([NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 3.5, 3.5) xRadius:8 yRadius:8], 1, NO);
	} else {
		WKDStroke(box, 1.5, NO);
	}
	WKDTaskMarker(type, rect);
	WKDLoopMarker(look.loop, rect);
	if (names) {
		if (container) {
			WKDDrawText(look.name, NSMakeRect(NSMinX(rect) + 8, NSMinY(rect) + 4, NSWidth(rect) - 16, 16), 11);
		} else {
			WKDDrawText(look.name, NSInsetRect(rect, 8, 14), 11);
		}
	}
}

#pragma mark Flows

void
WKDDrawAssociation(NSArray<NSValue *> *points, BOOL directed)
{
	if ([points count] < 2) {
		return;
	}
	NSBezierPath *line = [NSBezierPath bezierPath];
	[line moveToPoint:[[points objectAtIndex:0] pointValue]];
	for (NSUInteger i = 1; i < [points count]; i++) {
		[line lineToPoint:[[points objectAtIndex:i] pointValue]];
	}
	CGFloat dots[2] = { 1.5, 3 };
	[line setLineDash:dots count:2 phase:0];
	[line setLineWidth:1.5];
	[line stroke];
	if (directed) {
		NSPoint end = [[points lastObject] pointValue];
		NSPoint before = [[points objectAtIndex:[points count] - 2] pointValue];
		double angle = atan2(end.y - before.y, end.x - before.x);
		NSBezierPath *head = [NSBezierPath bezierPath];
		[head moveToPoint:NSMakePoint(end.x - 9 * cos(angle - 0.45), end.y - 9 * sin(angle - 0.45))];
		[head lineToPoint:end];
		[head lineToPoint:NSMakePoint(end.x - 9 * cos(angle + 0.45), end.y - 9 * sin(angle + 0.45))];
		WKDStroke(head, 1.2, NO);
	}
}

void
WKDDrawFlow(NSArray<NSValue *> *points, BOOL isDefault, BOOL conditionalFromActivity, NSString *name)
{
	if ([points count] < 2) {
		return;
	}
	NSBezierPath *line = [NSBezierPath bezierPath];
	[line moveToPoint:[[points objectAtIndex:0] pointValue]];
	for (NSUInteger i = 1; i < [points count]; i++) {
		[line lineToPoint:[[points objectAtIndex:i] pointValue]];
	}
	[line setLineJoinStyle:NSRoundLineJoinStyle];
	WKDStroke(line, 1.5, NO);
	NSPoint end = [[points lastObject] pointValue];
	NSPoint before = [[points objectAtIndex:[points count] - 2] pointValue];
	double angle = atan2(end.y - before.y, end.x - before.x);
	NSBezierPath *head = [NSBezierPath bezierPath];
	[head moveToPoint:end];
	[head lineToPoint:NSMakePoint(end.x - 10 * cos(angle - 0.4), end.y - 10 * sin(angle - 0.4))];
	[head lineToPoint:NSMakePoint(end.x - 10 * cos(angle + 0.4), end.y - 10 * sin(angle + 0.4))];
	[head closePath];
	[WKDInkColor() setFill];
	[head fill];

	NSPoint start = [[points objectAtIndex:0] pointValue];
	NSPoint next = [[points objectAtIndex:1] pointValue];
	double out = atan2(next.y - start.y, next.x - start.x);
	if (isDefault) {
		NSPoint mark = NSMakePoint(start.x + 10 * cos(out), start.y + 10 * sin(out));
		NSBezierPath *slash = [NSBezierPath bezierPath];
		[slash moveToPoint:NSMakePoint(mark.x - 5 * cos(out + 0.8), mark.y - 5 * sin(out + 0.8))];
		[slash lineToPoint:NSMakePoint(mark.x + 5 * cos(out + 0.8), mark.y + 5 * sin(out + 0.8))];
		WKDStroke(slash, 1.5, NO);
	} else if (conditionalFromActivity) {
		NSPoint tip = NSMakePoint(start.x + 16 * cos(out), start.y + 16 * sin(out));
		NSPoint mid = NSMakePoint(start.x + 8 * cos(out), start.y + 8 * sin(out));
		NSBezierPath *diamond = [NSBezierPath bezierPath];
		[diamond moveToPoint:start];
		[diamond lineToPoint:NSMakePoint(mid.x - 5 * sin(out), mid.y + 5 * cos(out))];
		[diamond lineToPoint:tip];
		[diamond lineToPoint:NSMakePoint(mid.x + 5 * sin(out), mid.y - 5 * cos(out))];
		[diamond closePath];
		[WKDPaperColor() setFill];
		[diamond fill];
		WKDStroke(diamond, 1, NO);
	}
	if ([name length] > 0) {
		WKDDrawText(name, WKDFlowLabelRect(points), 10);
	}
}

NSBezierPath *
WKDNodeOutline(NSString *type, NSRect rect)
{
	switch (WKDKindOfType(type, NULL)) {
	case WKDShapeEvent:
		return [NSBezierPath bezierPathWithOvalInRect:rect];
	case WKDShapeGateway: {
		NSBezierPath *diamond = [NSBezierPath bezierPath];
		[diamond moveToPoint:NSMakePoint(NSMidX(rect), NSMinY(rect))];
		[diamond lineToPoint:NSMakePoint(NSMaxX(rect), NSMidY(rect))];
		[diamond lineToPoint:NSMakePoint(NSMidX(rect), NSMaxY(rect))];
		[diamond lineToPoint:NSMakePoint(NSMinX(rect), NSMidY(rect))];
		[diamond closePath];
		return diamond;
	}
	default:
		return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:10 yRadius:10];
	}
}

void
WKDDrawLane(NSRect rect, NSString *name, BOOL horizontal)
{
	[WKDInkColor() setStroke];
	NSBezierPath *outline = [NSBezierPath bezierPathWithRect:rect];
	[outline setLineWidth:1.2];
	[outline stroke];
	NSRect band = WKDLaneBandRect(rect, horizontal);
	NSBezierPath *edge = [NSBezierPath bezierPath];
	if (horizontal) {
		[edge moveToPoint:NSMakePoint(NSMaxX(band), NSMinY(band))];
		[edge lineToPoint:NSMakePoint(NSMaxX(band), NSMaxY(band))];
	} else {
		[edge moveToPoint:NSMakePoint(NSMinX(band), NSMaxY(band))];
		[edge lineToPoint:NSMakePoint(NSMaxX(band), NSMaxY(band))];
	}
	[edge setLineWidth:1.2];
	[edge stroke];
	if ([name length] == 0) {
		return;
	}
	NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:11],
	                              NSForegroundColorAttributeName: WKDInkColor() };
	double room = (horizontal ? NSHeight(band) : NSWidth(band)) - 8;
	NSString *text = name;
	while ([text length] > 1 && [text sizeWithAttributes:attributes].width > room) {
		text = [[text substringToIndex:[text length] - 2] stringByAppendingString:@"…"];
	}
	NSSize size = [text sizeWithAttributes:attributes];
	if (!horizontal) {
		[text drawAtPoint:NSMakePoint(NSMidX(band) - size.width / 2, NSMidY(band) - size.height / 2)
		   withAttributes:attributes];
		return;
	}
	/* Turned a quarter anticlockwise about the band's centre. */
	[NSGraphicsContext saveGraphicsState];
	NSAffineTransform *turn = [NSAffineTransform transform];
	[turn translateXBy:NSMidX(band) yBy:NSMidY(band)];
	[turn rotateByDegrees:-90];
	[turn concat];
	[text drawAtPoint:NSMakePoint(-size.width / 2, -size.height / 2) withAttributes:attributes];
	[NSGraphicsContext restoreGraphicsState];
}

void
WKDDrawSelection(NSRect rect)
{
	[WKDSelectionColor() setStroke];
	NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, -4, -4) xRadius:4 yRadius:4];
	CGFloat pattern[2] = { 3, 2 };
	[outline setLineDash:pattern count:2 phase:0];
	[outline setLineWidth:1.5];
	[outline stroke];
	[WKDInkColor() setStroke];
}

double
WKDDistanceToPolyline(NSPoint p, NSArray<NSValue *> *points)
{
	double best = DBL_MAX;
	for (NSUInteger i = 0; i + 1 < [points count]; i++) {
		NSPoint a = [[points objectAtIndex:i] pointValue], b = [[points objectAtIndex:i + 1] pointValue];
		double dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy;
		double t = length > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / length : 0;
		t = MAX(0, MIN(1, t));
		best = MIN(best, hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)));
	}
	return best;
}

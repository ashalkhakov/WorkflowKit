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

#pragma mark Colours

/* Between WKDBeginDrawing(NO) and WKDEndDrawing(): black on white, as a
 * DiagramKit canvas draws a light view, a print or an export. Otherwise the
 * appearance's own colours, taken as they are now. */
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

static DKColor
WKDColorOf(NSColor *color)
{
	NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
	if (rgb == nil) {
		return DKColorBlack();
	}
	return DKColorMake([rgb redComponent], [rgb greenComponent], [rgb blueComponent], [rgb alphaComponent]);
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

DKColor
WKDInk(void)
{
	return WKDLight ? DKColorBlack() : WKDColorOf([NSColor textColor]);
}

DKColor
WKDPaper(void)
{
	return WKDLight ? DKColorWhite() : WKDColorOf([NSColor textBackgroundColor]);
}

DKColor
WKDSelection(void)
{
	return DKColorMake(0.15, 0.45, 0.95, 1.0);
}

#pragma mark Paths and text

static void
WKDStroke(id<DKSurface> surface, DKPath *path, DKColor color, double width, DKStrokeStyle style)
{
	[surface strokePath:path color:color width:width style:style];
}

static DKPath *
WKDPolyline(NSArray<NSValue *> *points)
{
	DKPath *path = [DKPath path];
	for (NSUInteger i = 0; i < [points count]; i++) {
		NSPoint point = [[points objectAtIndex:i] pointValue];
		if (i == 0) {
			[path moveTo:point];
		} else {
			[path lineTo:point];
		}
	}
	return path;
}

static DKPath *
WKDLine(NSPoint from, NSPoint to)
{
	return [DKPath pathWithLineFrom:from to:to];
}

/* An arc of the circle from one angle to the other, in degrees, the way
 * the angles grow (clockwise on the page, y growing downwards), as cubic
 * curves of a quarter turn at most. */
static void
WKDAppendArc(DKPath *path, NSPoint centre, double radius, double from, double to)
{
	double a0 = from * M_PI / 180, a1 = to * M_PI / 180;
	NSInteger pieces = MAX(1, (NSInteger)ceil(fabs(a1 - a0) / (M_PI / 2)));
	double step = (a1 - a0) / pieces;
	double k = 4.0 / 3.0 * tan(step / 4);
	[path moveTo:NSMakePoint(centre.x + radius * cos(a0), centre.y + radius * sin(a0))];
	for (NSInteger i = 0; i < pieces; i++) {
		double s = a0 + i * step, e = s + step;
		NSPoint p0 = NSMakePoint(centre.x + radius * cos(s), centre.y + radius * sin(s));
		NSPoint p3 = NSMakePoint(centre.x + radius * cos(e), centre.y + radius * sin(e));
		NSPoint c1 = NSMakePoint(p0.x - k * radius * sin(s), p0.y + k * radius * cos(s));
		NSPoint c2 = NSMakePoint(p3.x + k * radius * sin(e), p3.y - k * radius * cos(e));
		[path curveTo:p3 control1:c1 control2:c2];
	}
}

/* The text broken at words into lines no wider than the width, as the
 * surface measures them; a word wider than it on a line of its own. */
static NSArray<NSString *> *
WKDLines(id<DKSurface> surface, NSString *text, DKFont *font, double width)
{
	NSMutableArray *lines = [NSMutableArray array];
	for (NSString *paragraph in [text componentsSeparatedByString:@"\n"]) {
		NSString *line = @"";
		for (NSString *word in [paragraph componentsSeparatedByString:@" "]) {
			if ([word length] == 0) {
				continue;
			}
			NSString *longer = [line length] == 0 ? word : [line stringByAppendingFormat:@" %@", word];
			if ([line length] > 0 && [surface sizeOfText:longer font:font].width > width) {
				[lines addObject:line];
				line = word;
			} else {
				line = longer;
			}
		}
		[lines addObject:line];
	}
	return lines;
}

/* The lines centred across the rectangle, from its top; with a limit,
 * what does not fit that height is left out. */
static void
WKDDrawLines(id<DKSurface> surface, NSArray<NSString *> *lines, NSRect rect, DKFont *font, double limit)
{
	double height = [surface sizeOfText:@"Xg" font:font].height;
	double y = NSMinY(rect);
	for (NSString *line in lines) {
		if (limit > 0 && y + height > NSMinY(rect) + limit + 0.5) {
			break;
		}
		[surface drawText:line at:NSMakePoint(NSMidX(rect), y) font:font color:WKDInk() centered:YES];
		y += height;
	}
}

/* A name in the rectangle, centred both ways, wrapped to its width. */
static void
WKDDrawText(id<DKSurface> surface, NSString *text, NSRect rect, double size)
{
	if ([text length] == 0) {
		return;
	}
	DKFont *font = [DKFont systemFontOfSize:size bold:NO];
	NSArray *lines = WKDLines(surface, text, font, NSWidth(rect));
	double lineHeight = [surface sizeOfText:@"Xg" font:font].height;
	double height = MIN([lines count] * lineHeight, NSHeight(rect));
	NSRect centred = NSMakeRect(NSMinX(rect), NSMidY(rect) - height / 2, NSWidth(rect), height + 2);
	WKDDrawLines(surface, lines, centred, font, NSHeight(centred));
}

void
WKDDrawLabel(id<DKSurface> surface, NSString *name, NSRect rect)
{
	if ([name length] == 0) {
		return;
	}
	DKFont *font = [DKFont systemFontOfSize:10 bold:NO];
	NSRect drawn = NSMakeRect(NSMinX(rect), NSMinY(rect), MAX(NSWidth(rect), 20), NSHeight(rect));
	WKDDrawLines(surface, WKDLines(surface, name, font, NSWidth(drawn)), drawn, font, 0);
}

#pragma mark Markers

static void
WKDEnvelope(id<DKSurface> surface, NSRect box, BOOL filled)
{
	DKPath *path = [DKPath pathWithRect:box];
	DKColor flapColor = WKDInk();
	if (filled) {
		[surface fillPath:path color:WKDInk()];
		flapColor = WKDPaper();
	}
	DKPath *flap = [DKPath path];
	[flap moveTo:NSMakePoint(NSMinX(box), NSMinY(box))];
	[flap lineTo:NSMakePoint(NSMidX(box), NSMidY(box))];
	[flap lineTo:NSMakePoint(NSMaxX(box), NSMinY(box))];
	WKDStroke(surface, flap, flapColor, 1, DKStrokeSolid);
	if (!filled) {
		WKDStroke(surface, path, WKDInk(), 1, DKStrokeSolid);
	}
}

static void
WKDPolygon(id<DKSurface> surface, NSArray *points, BOOL filled)
{
	DKPath *path = WKDPolyline(points);
	[path close];
	if (filled) {
		[surface fillPath:path color:WKDInk()];
	}
	WKDStroke(surface, path, WKDInk(), 1, DKStrokeSolid);
}

static NSValue *
WKDP(double x, double y)
{
	return [NSValue valueWithPoint:NSMakePoint(x, y)];
}

/* An event's definition, in the middle of its circle. */
static void
WKDEventMarker(id<DKSurface> surface, NSString *definition, NSRect circle, BOOL throwing)
{
	double r = NSWidth(circle) / 2, cx = NSMidX(circle), cy = NSMidY(circle);
	if ([definition isEqualToString:@"timerEventDefinition"]) {
		NSRect face = NSInsetRect(circle, r * 0.35, r * 0.35);
		WKDStroke(surface, [DKPath pathWithOvalInRect:face], WKDInk(), 1, DKStrokeSolid);
		DKPath *hands = [DKPath path];
		[hands moveTo:NSMakePoint(cx, cy - r * 0.45)];
		[hands lineTo:NSMakePoint(cx, cy)];
		[hands lineTo:NSMakePoint(cx + r * 0.35, cy)];
		WKDStroke(surface, hands, WKDInk(), 1, DKStrokeSolid);
	} else if ([definition isEqualToString:@"messageEventDefinition"]) {
		WKDEnvelope(surface, NSMakeRect(cx - r * 0.5, cy - r * 0.33, r, r * 0.66), throwing);
	} else if ([definition isEqualToString:@"signalEventDefinition"]) {
		WKDPolygon(surface, @[ WKDP(cx, cy - r * 0.5), WKDP(cx + r * 0.5, cy + r * 0.35), WKDP(cx - r * 0.5, cy + r * 0.35) ],
		           throwing);
	} else if ([definition isEqualToString:@"errorEventDefinition"]) {
		WKDPolygon(surface, @[ WKDP(cx - r * 0.45, cy + r * 0.45), WKDP(cx - r * 0.2, cy - r * 0.4), WKDP(cx + r * 0.1, cy + r * 0.1),
		                       WKDP(cx + r * 0.45, cy - r * 0.45), WKDP(cx + r * 0.2, cy + r * 0.4), WKDP(cx - r * 0.1, cy - r * 0.1) ],
		           throwing);
	} else if ([definition isEqualToString:@"escalationEventDefinition"]) {
		WKDPolygon(surface, @[ WKDP(cx, cy - r * 0.5), WKDP(cx + r * 0.35, cy + r * 0.45), WKDP(cx, cy + r * 0.1),
		                       WKDP(cx - r * 0.35, cy + r * 0.45) ], throwing);
	} else if ([definition isEqualToString:@"compensateEventDefinition"]) {
		WKDPolygon(surface, @[ WKDP(cx - r * 0.5, cy), WKDP(cx, cy - r * 0.3), WKDP(cx, cy + r * 0.3) ], throwing);
		WKDPolygon(surface, @[ WKDP(cx, cy), WKDP(cx + r * 0.5, cy - r * 0.3), WKDP(cx + r * 0.5, cy + r * 0.3) ], throwing);
	} else if ([definition isEqualToString:@"conditionalEventDefinition"]) {
		NSRect page = NSMakeRect(cx - r * 0.35, cy - r * 0.45, r * 0.7, r * 0.9);
		WKDStroke(surface, [DKPath pathWithRect:page], WKDInk(), 1, DKStrokeSolid);
		for (int line = 1; line <= 4; line++) {
			double y = NSMinY(page) + NSHeight(page) * line / 5;
			WKDStroke(surface, WKDLine(NSMakePoint(NSMinX(page) + 2, y), NSMakePoint(NSMaxX(page) - 2, y)), WKDInk(), 1,
			          DKStrokeSolid);
		}
	} else if ([definition isEqualToString:@"linkEventDefinition"]) {
		WKDPolygon(surface, @[ WKDP(cx - r * 0.45, cy - r * 0.15), WKDP(cx + r * 0.05, cy - r * 0.15), WKDP(cx + r * 0.05, cy - r * 0.4),
		                       WKDP(cx + r * 0.5, cy), WKDP(cx + r * 0.05, cy + r * 0.4), WKDP(cx + r * 0.05, cy + r * 0.15),
		                       WKDP(cx - r * 0.45, cy + r * 0.15) ], throwing);
	} else if ([definition isEqualToString:@"terminateEventDefinition"]) {
		[surface fillPath:[DKPath pathWithOvalInRect:NSInsetRect(circle, r * 0.4, r * 0.4)] color:WKDInk()];
	}
}

/* A task's type, in its top left corner. */
static void
WKDTaskMarker(id<DKSurface> surface, NSString *type, NSRect rect)
{
	NSRect box = NSMakeRect(NSMinX(rect) + 6, NSMinY(rect) + 6, 14, 14);
	if ([type isEqualToString:@"userTask"]) {
		WKDStroke(surface, [DKPath pathWithOvalInRect:NSMakeRect(NSMidX(box) - 3, NSMinY(box), 6, 6)], WKDInk(), 1,
		          DKStrokeSolid);
		/* The shoulders: the upper half of a circle round the box's bottom
		 * middle. */
		DKPath *body = [DKPath path];
		WKDAppendArc(body, NSMakePoint(NSMidX(box), NSMaxY(box)), 7, 180, 360);
		WKDStroke(surface, body, WKDInk(), 1, DKStrokeSolid);
	} else if ([type isEqualToString:@"serviceTask"]) {
		NSPoint c = NSMakePoint(NSMidX(box), NSMidY(box));
		for (int i = 0; i < 8; i++) {
			double a = i * M_PI / 4;
			WKDStroke(surface, WKDLine(NSMakePoint(c.x + 4 * cos(a), c.y + 4 * sin(a)),
			                           NSMakePoint(c.x + 7 * cos(a), c.y + 7 * sin(a))),
			          WKDInk(), 2, DKStrokeSolid);
		}
		WKDStroke(surface, [DKPath pathWithOvalInRect:NSInsetRect(box, 3, 3)], WKDInk(), 1, DKStrokeSolid);
	} else if ([type isEqualToString:@"scriptTask"]) {
		WKDStroke(surface, [DKPath pathWithRect:NSInsetRect(box, 2, 0)], WKDInk(), 1, DKStrokeSolid);
		for (int line = 1; line <= 3; line++) {
			WKDStroke(surface, WKDLine(NSMakePoint(NSMinX(box) + 4, NSMinY(box) + line * 3.5),
			                           NSMakePoint(NSMaxX(box) - 4, NSMinY(box) + line * 3.5)),
			          WKDInk(), 1, DKStrokeSolid);
		}
	} else if ([type isEqualToString:@"sendTask"] || [type isEqualToString:@"receiveTask"]) {
		WKDEnvelope(surface, NSMakeRect(NSMinX(box), NSMinY(box) + 2, 14, 10), [type isEqualToString:@"sendTask"]);
	} else if ([type isEqualToString:@"businessRuleTask"]) {
		NSRect table = NSMakeRect(NSMinX(box), NSMinY(box) + 2, 14, 10);
		WKDStroke(surface, [DKPath pathWithRect:table], WKDInk(), 1, DKStrokeSolid);
		DKPath *grid = [DKPath path];
		[grid moveTo:NSMakePoint(NSMinX(table), NSMinY(table) + 3)];
		[grid lineTo:NSMakePoint(NSMaxX(table), NSMinY(table) + 3)];
		[grid moveTo:NSMakePoint(NSMinX(table) + 5, NSMinY(table))];
		[grid lineTo:NSMakePoint(NSMinX(table) + 5, NSMaxY(table))];
		WKDStroke(surface, grid, WKDInk(), 1, DKStrokeSolid);
	} else if ([type isEqualToString:@"manualTask"]) {
		WKDStroke(surface, [DKPath pathWithRoundedRect:NSMakeRect(NSMinX(box), NSMinY(box) + 4, 14, 7) radius:3], WKDInk(), 1,
		          DKStrokeSolid);
	}
}

/* Multi-instance and loop markers, bottom centre. */
static void
WKDLoopMarker(id<DKSurface> surface, NSString *loop, NSRect rect)
{
	if (loop == nil) {
		return;
	}
	double cx = NSMidX(rect), bottom = NSMaxY(rect) - 6;
	DKPath *bars = [DKPath path];
	if ([loop isEqualToString:@"parallel"]) {
		for (int i = -1; i <= 1; i++) {
			[bars moveTo:NSMakePoint(cx + i * 4, bottom - 10)];
			[bars lineTo:NSMakePoint(cx + i * 4, bottom)];
		}
	} else if ([loop isEqualToString:@"sequential"]) {
		for (int i = 0; i <= 2; i++) {
			[bars moveTo:NSMakePoint(cx - 5, bottom - 10 + i * 4)];
			[bars lineTo:NSMakePoint(cx + 5, bottom - 10 + i * 4)];
		}
	} else {
		/* A loop: the circle from -60 degrees round to 240, as AppKit drew it
		 * in the flipped view, open at the bottom. */
		WKDAppendArc(bars, NSMakePoint(cx, bottom - 5), 5, -60, 240);
	}
	WKDStroke(surface, bars, WKDInk(), 1.5, DKStrokeSolid);
}

#pragma mark Nodes

static DKPath *
WKDDiamond(NSRect rect)
{
	DKPath *diamond = [DKPath path];
	[diamond moveTo:NSMakePoint(NSMidX(rect), NSMinY(rect))];
	[diamond lineTo:NSMakePoint(NSMaxX(rect), NSMidY(rect))];
	[diamond lineTo:NSMakePoint(NSMidX(rect), NSMaxY(rect))];
	[diamond lineTo:NSMakePoint(NSMinX(rect), NSMidY(rect))];
	[diamond close];
	return diamond;
}

void
WKDDrawNode(id<DKSurface> surface, WKDLook *look, NSRect rect, BOOL names)
{
	NSString *type = look.type;
	BOOL container = WKDIsContainerType(type);
	WKDShapeKind kind = WKDKindOfType(type, NULL);
	if (kind == WKDShapeEvent) {
		NSRect circle = NSInsetRect(rect, 1, 1);
		DKPath *outline = [DKPath pathWithOvalInRect:circle];
		[surface fillPath:outline color:WKDPaper()];
		DKStrokeStyle style = look.interrupting ? DKStrokeSolid : DKStrokeDashed;
		if ([type isEqualToString:@"startEvent"]) {
			WKDStroke(surface, outline, WKDInk(), 1.5, style);
		} else if ([type isEqualToString:@"endEvent"]) {
			WKDStroke(surface, outline, WKDInk(), 3.5, DKStrokeSolid);
		} else {
			WKDStroke(surface, outline, WKDInk(), 1, style);
			WKDStroke(surface, [DKPath pathWithOvalInRect:NSInsetRect(circle, 3, 3)], WKDInk(), 1, style);
		}
		WKDEventMarker(surface, look.eventDefinition, circle,
		               [type isEqualToString:@"endEvent"] || [type isEqualToString:@"intermediateThrowEvent"]);
		if (names) {
			WKDDrawText(surface, look.name, WKDNodeLabelRect(type, rect), 10);
		}
		return;
	}
	if (kind == WKDShapeGateway) {
		DKPath *diamond = WKDDiamond(rect);
		[surface fillPath:diamond color:WKDPaper()];
		WKDStroke(surface, diamond, WKDInk(), 1.5, DKStrokeSolid);
		double r = NSWidth(rect) / 2, cx = NSMidX(rect), cy = NSMidY(rect);
		DKPath *marker = [DKPath path];
		if ([type isEqualToString:@"exclusiveGateway"]) {
			[marker moveTo:NSMakePoint(cx - r * 0.3, cy - r * 0.3)];
			[marker lineTo:NSMakePoint(cx + r * 0.3, cy + r * 0.3)];
			[marker moveTo:NSMakePoint(cx + r * 0.3, cy - r * 0.3)];
			[marker lineTo:NSMakePoint(cx - r * 0.3, cy + r * 0.3)];
			WKDStroke(surface, marker, WKDInk(), 3, DKStrokeSolid);
		} else if ([type isEqualToString:@"parallelGateway"] || [type isEqualToString:@"complexGateway"]) {
			[marker moveTo:NSMakePoint(cx, cy - r * 0.45)];
			[marker lineTo:NSMakePoint(cx, cy + r * 0.45)];
			[marker moveTo:NSMakePoint(cx - r * 0.45, cy)];
			[marker lineTo:NSMakePoint(cx + r * 0.45, cy)];
			if ([type isEqualToString:@"complexGateway"]) {
				[marker moveTo:NSMakePoint(cx - r * 0.3, cy - r * 0.3)];
				[marker lineTo:NSMakePoint(cx + r * 0.3, cy + r * 0.3)];
				[marker moveTo:NSMakePoint(cx + r * 0.3, cy - r * 0.3)];
				[marker lineTo:NSMakePoint(cx - r * 0.3, cy + r * 0.3)];
			}
			WKDStroke(surface, marker, WKDInk(), 3, DKStrokeSolid);
		} else if ([type isEqualToString:@"inclusiveGateway"]) {
			WKDStroke(surface, [DKPath pathWithOvalInRect:NSInsetRect(rect, r * 0.5, r * 0.5)], WKDInk(), 2.5, DKStrokeSolid);
		} else if ([type isEqualToString:@"eventBasedGateway"]) {
			NSRect inner = NSInsetRect(rect, r * 0.45, r * 0.45);
			WKDStroke(surface, [DKPath pathWithOvalInRect:inner], WKDInk(), 1, DKStrokeSolid);
			double p = NSWidth(inner) / 2 * 0.6;
			NSMutableArray *pentagon = [NSMutableArray array];
			for (int i = 0; i < 5; i++) {
				double a = -M_PI / 2 + i * 2 * M_PI / 5;
				[pentagon addObject:WKDP(cx + p * cos(a), cy + p * sin(a))];
			}
			WKDPolygon(surface, pentagon, NO);
		}
		if (names) {
			WKDDrawText(surface, look.name, WKDNodeLabelRect(type, rect), 10);
		}
		return;
	}
	if (kind == WKDShapeArtifact) {
		DKPath *bracket = [DKPath path];
		[bracket moveTo:NSMakePoint(NSMinX(rect) + 10, NSMinY(rect))];
		[bracket lineTo:NSMakePoint(NSMinX(rect), NSMinY(rect))];
		[bracket lineTo:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
		[bracket lineTo:NSMakePoint(NSMinX(rect) + 10, NSMaxY(rect))];
		WKDStroke(surface, bracket, WKDInk(), 1, DKStrokeSolid);
		if (names) {
			WKDDrawText(surface, look.name, NSInsetRect(rect, 6, 2), 10);
		}
		return;
	}
	DKPath *box = [DKPath pathWithRoundedRect:NSInsetRect(rect, 0.5, 0.5) radius:10];
	[surface fillPath:box color:WKDPaper()];
	if ([type isEqualToString:@"callActivity"]) {
		WKDStroke(surface, box, WKDInk(), 3.5, DKStrokeSolid);
	} else if (look.eventSubProcess) {
		WKDStroke(surface, box, WKDInk(), 1.5, DKStrokeDotted);
	} else if ([type isEqualToString:@"transaction"]) {
		WKDStroke(surface, box, WKDInk(), 1, DKStrokeSolid);
		WKDStroke(surface, [DKPath pathWithRoundedRect:NSInsetRect(rect, 3.5, 3.5) radius:8], WKDInk(), 1, DKStrokeSolid);
	} else {
		WKDStroke(surface, box, WKDInk(), 1.5, DKStrokeSolid);
	}
	WKDTaskMarker(surface, type, rect);
	WKDLoopMarker(surface, look.loop, rect);
	if (names) {
		if (container) {
			WKDDrawText(surface, look.name, NSMakeRect(NSMinX(rect) + 8, NSMinY(rect) + 4, NSWidth(rect) - 16, 16), 11);
		} else {
			WKDDrawText(surface, look.name, NSInsetRect(rect, 8, 14), 11);
		}
	}
}

#pragma mark Flows

void
WKDDrawAssociation(id<DKSurface> surface, NSArray<NSValue *> *points, DKColor color, BOOL directed)
{
	if ([points count] < 2) {
		return;
	}
	WKDStroke(surface, WKDPolyline(points), color, 1.5, DKStrokeDotted);
	if (directed) {
		NSPoint end = [[points lastObject] pointValue];
		NSPoint before = [[points objectAtIndex:[points count] - 2] pointValue];
		double angle = atan2(end.y - before.y, end.x - before.x);
		DKPath *head = [DKPath path];
		[head moveTo:NSMakePoint(end.x - 9 * cos(angle - 0.45), end.y - 9 * sin(angle - 0.45))];
		[head lineTo:end];
		[head lineTo:NSMakePoint(end.x - 9 * cos(angle + 0.45), end.y - 9 * sin(angle + 0.45))];
		WKDStroke(surface, head, color, 1.2, DKStrokeSolid);
	}
}

void
WKDDrawFlow(id<DKSurface> surface, NSArray<NSValue *> *points, DKColor color, BOOL isDefault,
            BOOL conditionalFromActivity, NSString *name)
{
	if ([points count] < 2) {
		return;
	}
	WKDStroke(surface, WKDPolyline(points), color, 1.5, DKStrokeSolid);
	NSPoint end = [[points lastObject] pointValue];
	NSPoint before = [[points objectAtIndex:[points count] - 2] pointValue];
	double angle = atan2(end.y - before.y, end.x - before.x);
	DKPath *head = [DKPath path];
	[head moveTo:end];
	[head lineTo:NSMakePoint(end.x - 10 * cos(angle - 0.4), end.y - 10 * sin(angle - 0.4))];
	[head lineTo:NSMakePoint(end.x - 10 * cos(angle + 0.4), end.y - 10 * sin(angle + 0.4))];
	[head close];
	[surface fillPath:head color:color];

	NSPoint start = [[points objectAtIndex:0] pointValue];
	NSPoint next = [[points objectAtIndex:1] pointValue];
	double out = atan2(next.y - start.y, next.x - start.x);
	if (isDefault) {
		NSPoint mark = NSMakePoint(start.x + 10 * cos(out), start.y + 10 * sin(out));
		WKDStroke(surface, WKDLine(NSMakePoint(mark.x - 5 * cos(out + 0.8), mark.y - 5 * sin(out + 0.8)),
		                           NSMakePoint(mark.x + 5 * cos(out + 0.8), mark.y + 5 * sin(out + 0.8))),
		          color, 1.5, DKStrokeSolid);
	} else if (conditionalFromActivity) {
		NSPoint tip = NSMakePoint(start.x + 16 * cos(out), start.y + 16 * sin(out));
		NSPoint mid = NSMakePoint(start.x + 8 * cos(out), start.y + 8 * sin(out));
		DKPath *diamond = [DKPath path];
		[diamond moveTo:start];
		[diamond lineTo:NSMakePoint(mid.x - 5 * sin(out), mid.y + 5 * cos(out))];
		[diamond lineTo:tip];
		[diamond lineTo:NSMakePoint(mid.x + 5 * sin(out), mid.y - 5 * cos(out))];
		[diamond close];
		[surface fillPath:diamond color:WKDPaper()];
		WKDStroke(surface, diamond, color, 1, DKStrokeSolid);
	}
	if ([name length] > 0) {
		WKDDrawText(surface, name, WKDFlowLabelRect(points), 10);
	}
}

DKPath *
WKDNodeOutline(NSString *type, NSRect rect)
{
	switch (WKDKindOfType(type, NULL)) {
	case WKDShapeEvent:
		return [DKPath pathWithOvalInRect:rect];
	case WKDShapeGateway:
		return WKDDiamond(rect);
	default:
		return [DKPath pathWithRoundedRect:rect radius:10];
	}
}

void
WKDDrawLane(id<DKSurface> surface, NSRect rect, NSString *name, BOOL horizontal)
{
	WKDStroke(surface, [DKPath pathWithRect:rect], WKDInk(), 1.2, DKStrokeSolid);
	NSRect band = WKDLaneBandRect(rect, horizontal);
	DKPath *edge = horizontal ? WKDLine(NSMakePoint(NSMaxX(band), NSMinY(band)), NSMakePoint(NSMaxX(band), NSMaxY(band)))
	                          : WKDLine(NSMakePoint(NSMinX(band), NSMaxY(band)), NSMakePoint(NSMaxX(band), NSMaxY(band)));
	WKDStroke(surface, edge, WKDInk(), 1.2, DKStrokeSolid);
	if ([name length] == 0) {
		return;
	}
	DKFont *font = [DKFont systemFontOfSize:11 bold:NO];
	double room = (horizontal ? NSHeight(band) : NSWidth(band)) - 8;
	NSString *text = name;
	while ([text length] > 1 && [surface sizeOfText:text font:font].width > room) {
		text = [[text substringToIndex:[text length] - 2] stringByAppendingString:@"…"];
	}
	/* A horizontal pool's or lane's name turned a quarter anticlockwise,
	 * read from the bottom up; a vertical one's level. */
	[surface drawText:text centeredAt:NSMakePoint(NSMidX(band), NSMidY(band)) font:font color:WKDInk()
	         rotation:horizontal ? DKTextRotationQuarterAnticlockwise : DKTextRotationNone];
}

void
WKDDrawSelection(id<DKSurface> surface, NSRect rect)
{
	WKDStroke(surface, [DKPath pathWithRoundedRect:NSInsetRect(rect, -4, -4) radius:4], WKDSelection(), 1.5,
	          DKStrokeDashed);
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

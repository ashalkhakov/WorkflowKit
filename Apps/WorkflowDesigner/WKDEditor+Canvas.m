#import "WKDEditorPriv.h"
#import "WKDXML.h"

/*
 * What the canvas changes directly: names typed over a shape, a flow's
 * ends dragged to other nodes, its bends and its label dragged, and the
 * route a flow keeps when one of its ends moves.
 */
@implementation WKDEditor (WKDCanvas)

- (void)setName:(NSString *)name of:(NSString *)elementId
{
	NSXMLElement *element = [self elementWithId:elementId];
	if (element == nil) {
		return;
	}
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *value = [trimmed length] > 0 ? trimmed : nil;
	BOOL annotation = WKDIs(element, WKDBpmnNamespace, @"textAnnotation");
	NSString *now = annotation ? WKDChildText(element, WKDBpmnNamespace, @"text") : WKDAttribute(element, @"name");
	if ((now == nil && value == nil) || [now isEqualToString:value]) {
		return;
	}
	[self edit:elementId action:@"Rename" with:^(NSXMLElement *edited, NSXMLDocument *document) {
		if (annotation) {
			WKDSetChildText(document, edited, WKDBpmnNamespace, @"text", value);
		} else {
			WKDSetAttribute(edited, @"name", value);
		}
	}];
}

/* The incoming or outgoing reference to the flow in the node, gone. */
static void
WKDRemoveReference(NSXMLElement *node, NSString *local, NSString *flowId)
{
	for (NSXMLElement *reference in WKDChildren(node, WKDBpmnNamespace, local)) {
		if ([[reference stringValue] isEqualToString:flowId]) {
			[reference detach];
		}
	}
}

- (BOOL)reconnect:(NSString *)flowId atSource:(BOOL)atSource to:(NSString *)nodeId error:(NSString **)reason
{
	WKDConnection *flow = [self.diagram connectionWithId:flowId];
	WKDShape *node = [self.diagram shapeWithId:nodeId];
	NSString *refusal = nil;
	if (flow == nil || flow.isAssociation) {
		refusal = @"Only a sequence flow's ends are moved.";
	} else if (node == nil) {
		refusal = @"There is no such node.";
	} else if ((atSource ? flow.source : flow.target) == node) {
		return YES;
	} else {
		refusal = [self refusalToConnect:atSource ? node : flow.source to:atSource ? flow.target : node except:flowId];
	}
	if (refusal != nil) {
		if (reason != NULL) {
			*reason = refusal;
		}
		return NO;
	}
	WKDShape *old = atSource ? flow.source : flow.target;
	[self change:@"Reconnect" with:^{
		WKDSetAttribute(flow.element, atSource ? @"sourceRef" : @"targetRef", nodeId);
		WKDRemoveReference(old.element, atSource ? @"outgoing" : @"incoming", flowId);
		[self addReference:atSource ? @"outgoing" : @"incoming" to:flowId in:node.element];
		if (atSource && [WKDAttribute(old.element, @"default") isEqualToString:flowId]) {
			WKDSetAttribute(old.element, @"default", nil);
		}
		self.diagram = [WKDDiagram diagramOfDocument:self.document];
		WKDConnection *now = [self.diagram connectionWithId:flowId];
		[self reroute:now];
		if (!NSIsEmptyRect(flow.labelBounds)) {
			/* Its name follows its middle. */
			self.diagram = [WKDDiagram diagramOfDocument:self.document];
			NSRect before = WKDFlowLabelRect(flow.waypoints);
			NSRect after = WKDFlowLabelRect([self.diagram connectionWithId:flowId].waypoints);
			[self setLabelBounds:NSOffsetRect(flow.labelBounds, NSMinX(after) - NSMinX(before),
			                                  NSMinY(after) - NSMinY(before)) of:flowId];
		}
	}];
	return YES;
}

- (void)moveBend:(NSUInteger)index of:(NSString *)flowId to:(NSPoint)point
{
	WKDConnection *flow = [self.diagram connectionWithId:flowId];
	NSArray *points = flow.waypoints;
	if (flow == nil || index == 0 || index + 1 >= [points count]
	    || NSEqualPoints([[points objectAtIndex:index] pointValue], point)) {
		return;
	}
	NSMutableArray *moved = [points mutableCopy];
	[moved replaceObjectAtIndex:index withObject:[NSValue valueWithPoint:point]];
	[self change:@"Move Bend" with:^{
		[self setWaypoints:moved of:flowId];
	}];
}

- (void)moveLabelOf:(NSString *)elementId by:(NSSize)offset
{
	WKDShape *shape = [self.diagram shapeWithId:elementId];
	WKDConnection *flow = shape == nil ? [self.diagram connectionWithId:elementId] : nil;
	NSRect label = NSZeroRect;
	if (shape != nil) {
		label = NSIsEmptyRect(shape.labelBounds) ? WKDNodeLabelRect(shape.type, shape.bounds) : shape.labelBounds;
	} else if (flow != nil) {
		label = NSIsEmptyRect(flow.labelBounds) ? WKDFlowLabelRect(flow.waypoints) : flow.labelBounds;
	}
	if (NSIsEmptyRect(label) || (offset.width == 0 && offset.height == 0)) {
		return;
	}
	[self change:@"Move Label" with:^{
		[self setLabelBounds:NSOffsetRect(label, offset.width, offset.height) of:elementId];
	}];
}

/* The two points are level (a segment straight across) or one above the
 * other (straight up and down). */
static BOOL
WKDLevel(NSPoint a, NSPoint b)
{
	return fabs(a.y - b.y) < 0.5;
}

static BOOL
WKDPlumb(NSPoint a, NSPoint b)
{
	return fabs(a.x - b.x) < 0.5;
}

/* The bend next to an end that moved, slid to keep their segment as it
 * was: level stays level, plumb stays plumb. */
static NSPoint
WKDFollow(NSPoint bend, NSPoint oldEnd, NSPoint newEnd)
{
	if (WKDLevel(oldEnd, bend)) {
		bend.y = newEnd.y;
	} else if (WKDPlumb(oldEnd, bend)) {
		bend.x = newEnd.x;
	}
	return bend;
}

+ (NSArray<NSValue *> *)keptRoute:(NSArray<NSValue *> *)points source:(NSRect)source target:(NSRect)target
                      sourceMoved:(NSSize)sourceMoved targetMoved:(NSSize)targetMoved
{
	NSUInteger count = [points count];
	if (count < 3) {
		return nil;
	}
	NSPoint p[count];
	for (NSUInteger i = 0; i < count; i++) {
		p[i] = [[points objectAtIndex:i] pointValue];
	}
	NSPoint q[count];
	memcpy(q, p, sizeof q);
	NSUInteger last = count - 1;
	if (sourceMoved.width != 0 || sourceMoved.height != 0) {
		q[0] = NSMakePoint(p[0].x + sourceMoved.width, p[0].y + sourceMoved.height);
		q[1] = WKDFollow(q[1], p[0], q[0]);
	}
	if (targetMoved.width != 0 || targetMoved.height != 0) {
		q[last] = NSMakePoint(p[last].x + targetMoved.width, p[last].y + targetMoved.height);
		q[last - 1] = WKDFollow(q[last - 1], p[last], q[last]);
	}
	/* Every segment straight before is straight still... */
	for (NSUInteger i = 1; i < count; i++) {
		BOOL wasStraight = WKDLevel(p[i - 1], p[i]) || WKDPlumb(p[i - 1], p[i]);
		if (wasStraight && !WKDLevel(q[i - 1], q[i]) && !WKDPlumb(q[i - 1], q[i])) {
			return nil;
		}
	}
	/* ...and the route leaves and enters its shapes from outside them. */
	if (NSPointInRect(q[1], NSInsetRect(source, 1, 1)) || NSPointInRect(q[last - 1], NSInsetRect(target, 1, 1))) {
		return nil;
	}
	NSMutableArray *kept = [NSMutableArray arrayWithCapacity:count];
	for (NSUInteger i = 0; i < count; i++) {
		[kept addObject:[NSValue valueWithPoint:q[i]]];
	}
	return kept;
}

@end

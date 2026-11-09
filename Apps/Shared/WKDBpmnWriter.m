#import "WKDModelPriv.h"
#import "WKDXML.h"

/* Numbers are compared as read, so the digits a file was written with
 * stay where the value has not changed. */
static BOOL
WKDSameNumber(NSXMLElement *element, NSString *name, double value)
{
	return WKDAttribute(element, name) != nil && fabs(WKDNumber(element, name) - value) < 1e-9;
}

static void
WKDWriteNumber(NSXMLElement *element, NSString *name, double value)
{
	if (!WKDSameNumber(element, name, value)) {
		WKDSetAttribute(element, name, WKDFormat(value));
	}
}

static void
WKDWriteAttribute(NSXMLElement *element, NSString *name, NSString *value)
{
	NSString *now = WKDAttribute(element, name);
	if (value == now || [value isEqualToString:now]) {
		return;
	}
	WKDSetAttribute(element, name, value);
}

static void
WKDWriteBounds(NSXMLElement *box, NSRect rect)
{
	WKDWriteNumber(box, @"x", rect.origin.x);
	WKDWriteNumber(box, @"y", rect.origin.y);
	WKDWriteNumber(box, @"width", rect.size.width);
	WKDWriteNumber(box, @"height", rect.size.height);
}

/* The texts of the element's children of that local name, trimmed. */
static NSArray<NSString *> *
WKDChildTexts(NSXMLElement *element, NSString *local)
{
	NSMutableArray *texts = [NSMutableArray array];
	for (NSXMLElement *child in WKDChildren(element, WKDBpmnNamespace, local)) {
		[texts addObject:[[child stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	}
	return texts;
}

@implementation WKDModel (WKDWriting)

- (void)writeChanges
{
	BOOL listsFlows = [self documentListsFlows];
	for (WKDModelElement *element in [self.changedElements allObjects]) {
		if ([element isKindOfClass:[WKDNode class]]) {
			[self writeNode:(WKDNode *)element listsFlows:listsFlows];
		} else if ([element isKindOfClass:[WKDFlow class]]) {
			[self writeFlow:(WKDFlow *)element];
		} else if ([element isKindOfClass:[WKDSwimlane class]]) {
			[self writeLane:(WKDSwimlane *)element];
		}
	}
	[self.changedElements removeAllObjects];
	[self.deletedElements removeAllObjects];
}

/* Whether the document lists each node's flows (incoming, outgoing), as
 * Camunda Modeler writes it; some writers leave them out, and the writer
 * then does too. */
- (BOOL)documentListsFlows
{
	for (WKDNode *node in self.nodeList) {
		if (WKDChild(node.element, WKDBpmnNamespace, @"incoming") != nil
		    || WKDChild(node.element, WKDBpmnNamespace, @"outgoing") != nil) {
			return YES;
		}
	}
	return NO;
}

#pragma mark Nodes

- (void)writeNode:(WKDNode *)node listsFlows:(BOOL)listsFlows
{
	NSXMLElement *element = node.element;
	if ([node.type isEqualToString:@"textAnnotation"]) {
		NSString *text = WKDChildText(element, WKDBpmnNamespace, @"text");
		if (!(text == node.name || [text isEqualToString:node.name])) {
			WKDSetChildText(self.document, element, WKDBpmnNamespace, @"text", node.name);
		}
	} else {
		WKDWriteAttribute(element, @"name", node.name);
	}
	if (node.host != nil) {
		WKDWriteAttribute(element, @"attachedToRef", node.host.elementId);
		[self writeInterrupting:node.interrupting of:element attribute:@"cancelActivity"];
	} else if ([node.type isEqualToString:@"startEvent"] && node.parent.eventSubProcess) {
		[self writeInterrupting:node.interrupting of:element attribute:@"isInterrupting"];
	}
	if (WKDIsContainerType(node.type)) {
		BOOL triggered = [WKDAttribute(element, @"triggeredByEvent") isEqualToString:@"true"];
		if (triggered != node.eventSubProcess) {
			WKDSetAttribute(element, @"triggeredByEvent", node.eventSubProcess ? @"true" : nil);
		}
	}
	/* A default that names no flow of the node is not the model's, and is
	 * left as it is. */
	NSString *written = WKDAttribute(element, @"default");
	WKDFlow *writtenFlow = [self flowWithId:written];
	if (node.defaultFlow != nil || (writtenFlow != nil && writtenFlow.source == node)) {
		WKDWriteAttribute(element, @"default", node.defaultFlow.elementId);
	}
	if (listsFlows) {
		[self writeFlowRefs:node.incomingList of:element local:@"incoming"];
		[self writeFlowRefs:node.outgoingList of:element local:@"outgoing"];
	}
	[self writeShapeOf:node bounds:node.bounds hasBounds:node.hasBounds labelBounds:node.labelBounds];
}

- (void)writeInterrupting:(BOOL)interrupting of:(NSXMLElement *)element attribute:(NSString *)attribute
{
	BOOL written = ![WKDAttribute(element, attribute) isEqualToString:@"false"];
	if (written != interrupting) {
		WKDSetAttribute(element, attribute, interrupting ? nil : @"false");
	}
}

/* A node's incoming or outgoing: the sequence flows the model has, as a
 * set; references to what the model does not know are kept. */
- (void)writeFlowRefs:(NSArray<WKDFlow *> *)flows of:(NSXMLElement *)element local:(NSString *)local
{
	NSMutableSet *wanted = [NSMutableSet set];
	for (WKDFlow *flow in flows) {
		if (!flow.isAssociation) {
			[wanted addObject:flow.elementId];
		}
	}
	NSMutableSet *known = [NSMutableSet set];
	for (NSString *ref in WKDChildTexts(element, local)) {
		if ([self flowWithId:ref] != nil) {
			[known addObject:ref];
		}
	}
	if ([known isEqualToSet:wanted]) {
		return;
	}
	for (NSXMLElement *child in WKDChildren(element, WKDBpmnNamespace, local)) {
		NSString *ref = [[child stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([self flowWithId:ref] != nil && ![wanted containsObject:ref]) {
			[child detach];
		}
	}
	for (WKDFlow *flow in flows) {
		if (flow.isAssociation || [known containsObject:flow.elementId]) {
			continue;
		}
		NSXMLElement *ref = WKDNewElement(self.document, WKDBpmnNamespace, local);
		[ref setStringValue:flow.elementId];
		[self insertRef:ref into:element local:local];
	}
}

/* After the last child of that local name, else where BPMN's schema puts
 * it: incoming before outgoing, both after documentation and extensions. */
- (void)insertRef:(NSXMLElement *)ref into:(NSXMLElement *)element local:(NSString *)local
{
	NSArray *same = WKDChildren(element, WKDBpmnNamespace, local);
	if ([same count] > 0) {
		[element insertChild:ref atIndex:[[same lastObject] index] + 1];
		return;
	}
	NSUInteger index = 0;
	for (NSXMLNode *child in [element children]) {
		NSString *name = [child localName];
		if (WKDIs(child, WKDBpmnNamespace, @"documentation") || WKDIs(child, WKDBpmnNamespace, @"extensionElements")
		    || ([local isEqualToString:@"outgoing"] && WKDIs(child, WKDBpmnNamespace, @"incoming"))) {
			index = [child index] + 1;
		} else if (name != nil) {
			break;
		}
	}
	[element insertChild:ref atIndex:index];
}

#pragma mark Flows

- (void)writeFlow:(WKDFlow *)flow
{
	NSXMLElement *element = flow.element;
	WKDWriteAttribute(element, @"name", flow.name);
	WKDWriteAttribute(element, @"sourceRef", flow.source.elementId);
	WKDWriteAttribute(element, @"targetRef", flow.target.elementId);
	if ([flow.waypoints count] < 2 && NSIsEmptyRect(flow.labelBounds)) {
		return;
	}
	NSXMLElement *edge = flow.diagramElement ?: [self newDiagramElement:@"BPMNEdge" for:flow];
	if (edge == nil) {
		return;
	}
	if ([flow.waypoints count] >= 2) {
		NSArray *written = WKDChildren(edge, WKDDINamespace, @"waypoint");
		BOOL same = [written count] == [flow.waypoints count];
		for (NSUInteger i = 0; same && i < [written count]; i++) {
			NSPoint point = [[flow.waypoints objectAtIndex:i] pointValue];
			same = WKDSameNumber([written objectAtIndex:i], @"x", point.x)
				&& WKDSameNumber([written objectAtIndex:i], @"y", point.y);
		}
		if (!same) {
			NSUInteger index = [written count] > 0 ? [[written firstObject] index] : 0;
			for (NSXMLElement *waypoint in written) {
				[waypoint detach];
			}
			for (NSValue *value in flow.waypoints) {
				NSXMLElement *waypoint = WKDNewElement(self.document, WKDDINamespace, @"waypoint");
				WKDSetAttribute(waypoint, @"x", WKDFormat([value pointValue].x));
				WKDSetAttribute(waypoint, @"y", WKDFormat([value pointValue].y));
				[edge insertChild:waypoint atIndex:index++];
			}
		}
	}
	[self writeLabelBounds:flow.labelBounds of:edge];
}

#pragma mark Lanes

- (void)writeLane:(WKDSwimlane *)lane
{
	WKDWriteAttribute(lane.element, @"name", lane.name);
	if (!lane.isPool) {
		NSMutableSet *wanted = [NSMutableSet setWithArray:[lane.nodeList valueForKey:@"elementId"]];
		NSMutableSet *known = [NSMutableSet set];
		for (NSString *ref in WKDChildTexts(lane.element, @"flowNodeRef")) {
			if ([self nodeWithId:ref] != nil) {
				[known addObject:ref];
			}
		}
		if (![known isEqualToSet:wanted]) {
			for (NSXMLElement *child in WKDChildren(lane.element, WKDBpmnNamespace, @"flowNodeRef")) {
				NSString *ref = [[child stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				if ([self nodeWithId:ref] != nil && ![wanted containsObject:ref]) {
					[child detach];
				}
			}
			for (WKDNode *node in lane.nodeList) {
				if (![known containsObject:node.elementId]) {
					NSXMLElement *ref = WKDNewElement(self.document, WKDBpmnNamespace, @"flowNodeRef");
					[ref setStringValue:node.elementId];
					[self insertRef:ref into:lane.element local:@"flowNodeRef"];
				}
			}
		}
	}
	[self writeShapeOf:lane bounds:lane.bounds hasBounds:lane.hasBounds labelBounds:NSZeroRect];
}

#pragma mark The diagram

- (void)writeShapeOf:(WKDModelElement *)element bounds:(NSRect)bounds hasBounds:(BOOL)hasBounds labelBounds:(NSRect)label
{
	if (!hasBounds) {
		return;
	}
	NSXMLElement *shape = element.diagramElement ?: [self newDiagramElement:@"BPMNShape" for:element];
	if (shape == nil) {
		return;
	}
	NSXMLElement *box = WKDChild(shape, WKDDCNamespace, @"Bounds");
	if (box == nil) {
		box = WKDNewElement(self.document, WKDDCNamespace, @"Bounds");
		[shape insertChild:box atIndex:0];
	}
	WKDWriteBounds(box, bounds);
	[self writeLabelBounds:label of:shape];
}

/* A label's bounds where the model has them; one the model has not is left
 * as it is. */
- (void)writeLabelBounds:(NSRect)rect of:(NSXMLElement *)diagramElement
{
	if (NSIsEmptyRect(rect)) {
		return;
	}
	NSXMLElement *label = WKDChild(diagramElement, WKDBpmnDINamespace, @"BPMNLabel");
	if (label == nil) {
		label = WKDNewElement(self.document, WKDBpmnDINamespace, @"BPMNLabel");
		[diagramElement addChild:label];
	}
	NSXMLElement *box = WKDChild(label, WKDDCNamespace, @"Bounds");
	if (box == nil) {
		box = WKDNewElement(self.document, WKDDCNamespace, @"Bounds");
		[label addChild:box];
	}
	WKDWriteBounds(box, rect);
}

/* A BPMNShape or BPMNEdge for the element, at the end of the plane; nil
 * when the document has no diagram. */
- (NSXMLElement *)newDiagramElement:(NSString *)local for:(WKDModelElement *)element
{
	if (self.plane == nil) {
		return nil;
	}
	NSXMLElement *diagramElement = WKDNewElement(self.document, WKDBpmnDINamespace, local);
	WKDSetAttribute(diagramElement, @"id", [element.elementId stringByAppendingString:@"_di"]);
	WKDSetAttribute(diagramElement, @"bpmnElement", element.elementId);
	[self.plane addChild:diagramElement];
	element.diagramElement = diagramElement;
	return diagramElement;
}

@end

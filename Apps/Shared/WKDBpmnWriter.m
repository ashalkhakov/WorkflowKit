#import "WKDModelPriv.h"
#import "WKDXML.h"
#import "WKDJournal.h"

/* Numbers are compared as read, so the digits a file was written with
 * stay where the value has not changed. */
static BOOL
WKDSameNumber(NSXMLElement *element, NSString *name, double value)
{
	return WKDAttribute(element, name) != nil && fabs(WKDNumber(element, name) - value) < 1e-9;
}

/* The writer's edits of the XML, each recorded in the journal so that undo
 * takes it back exactly. */
static void
WKDLogAttribute(WKDJournal *journal, NSXMLElement *element, NSString *name, NSString *value)
{
	NSString *before = WKDAttribute(element, name);
	WKDSetAttribute(element, name, value);
	[journal didSetAttribute:name of:element from:before to:value];
}

static void
WKDLogInsert(WKDJournal *journal, NSXMLElement *parent, NSXMLNode *child, NSUInteger index)
{
	[parent insertChild:child atIndex:index];
	[journal didInsert:child into:parent at:index];
}

static void
WKDLogAdd(WKDJournal *journal, NSXMLElement *parent, NSXMLNode *child)
{
	WKDLogInsert(journal, parent, child, [[parent children] count]);
}

static void
WKDLogDetach(WKDJournal *journal, NSXMLNode *child)
{
	NSXMLElement *parent = (NSXMLElement *)[child parent];
	if (parent == nil) {
		return;
	}
	NSUInteger index = [child index];
	[child detach];
	[journal didDetach:child from:parent at:index];
}

/* Numbers are compared as read, so the digits a file was written with
 * stay where the value has not changed. */
static void
WKDWriteNumber(WKDJournal *journal, NSXMLElement *element, NSString *name, double value)
{
	if (!WKDSameNumber(element, name, value)) {
		WKDLogAttribute(journal, element, name, WKDFormat(value));
	}
}

static void
WKDWriteAttribute(WKDJournal *journal, NSXMLElement *element, NSString *name, NSString *value)
{
	NSString *now = WKDAttribute(element, name);
	if (value == now || [value isEqualToString:now]) {
		return;
	}
	WKDLogAttribute(journal, element, name, value);
}

/* YES when anything was written. */
static BOOL
WKDWriteBounds(WKDJournal *journal, NSXMLElement *box, NSRect rect)
{
	BOOL same = WKDSameNumber(box, @"x", rect.origin.x) && WKDSameNumber(box, @"y", rect.origin.y)
		&& WKDSameNumber(box, @"width", rect.size.width) && WKDSameNumber(box, @"height", rect.size.height);
	WKDWriteNumber(journal, box, @"x", rect.origin.x);
	WKDWriteNumber(journal, box, @"y", rect.origin.y);
	WKDWriteNumber(journal, box, @"width", rect.size.width);
	WKDWriteNumber(journal, box, @"height", rect.size.height);
	return !same;
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

static NSInteger WKDByDiagramIndex(id a, id b, void *context);
static NSInteger WKDByDepthThenIndex(id a, id b, void *context);

@implementation WKDModel (WKDWriting)

- (void)writeChanges
{
	BOOL listsFlows = [self documentListsFlows];
	/* What left the model leaves the carrier, remembering where it was:
	 * every place first, then the detaching, so each index is the one it
	 * had among all its siblings. */
	NSMutableArray *leaving = [NSMutableArray array];
	for (WKDModelElement *element in self.deletedElements) {
		if (![self containsElement:element] && ![leaving containsObject:element]) {
			[self rememberPlaceOf:element];
			[leaving addObject:element];
		}
	}
	for (WKDModelElement *element in leaving) {
		WKDLogDetach(self.journal, element.element);
		WKDLogDetach(self.journal, element.diagramElement);
	}
	self.leavingIds = [NSSet setWithArray:[leaving valueForKey:@"elementId"]];
	/* What is in it has a carrier element: one put back where it was, in
	 * the order they were, or one made. Containers before what they hold. */
	NSMutableArray *present = [NSMutableArray array];
	for (WKDModelElement *element in [self.changedElements allObjects]) {
		if ([self containsElement:element]) {
			[present addObject:element];
		}
	}
	[present sortUsingFunction:WKDByDepthThenIndex context:NULL];
	for (WKDModelElement *element in present) {
		[self attach:element];
	}
	/* Their diagram elements, by where each was in the plane. */
	NSArray *shown = [present sortedArrayUsingFunction:WKDByDiagramIndex context:NULL];
	for (WKDModelElement *element in shown) {
		[self attachDiagramElementOf:element];
	}
	for (WKDModelElement *element in present) {
		if ([element isKindOfClass:[WKDNode class]]) {
			WKDNode *node = (WKDNode *)element;
			[self writeNode:node listsFlows:listsFlows || node.flowsChanged];
			node.flowsChanged = NO;
		} else if ([element isKindOfClass:[WKDFlow class]]) {
			[self writeFlow:(WKDFlow *)element];
		} else if ([element isKindOfClass:[WKDSwimlane class]]) {
			[self writeLane:(WKDSwimlane *)element];
		}
	}
	[self.changedElements removeAllObjects];
	[self.deletedElements removeAllObjects];
	self.leavingIds = nil;
}

/* A reference the model writes: to an element it has, or one leaving. */
- (BOOL)knowsFlow:(NSString *)ref
{
	return [self flowWithId:ref] != nil || [self.leavingIds containsObject:ref];
}

- (BOOL)knowsNode:(NSString *)ref
{
	return [self nodeWithId:ref] != nil || [self.leavingIds containsObject:ref];
}

static NSUInteger
WKDDepth(WKDModelElement *element)
{
	NSUInteger depth = 0;
	if ([element isKindOfClass:[WKDNode class]]) {
		for (WKDNode *up = ((WKDNode *)element).parent; up != nil; up = up.parent) {
			depth++;
		}
	} else if ([element isKindOfClass:[WKDFlow class]]) {
		depth = 1000;
	}
	return depth;
}

/* Containers before their contents, nodes before flows; then where their
 * carrier elements were, so each goes back at its own index. */
static NSInteger
WKDByDepthThenIndex(id a, id b, void *context)
{
	NSUInteger da = WKDDepth(a), db = WKDDepth(b);
	if (da != db) {
		return da < db ? NSOrderedAscending : NSOrderedDescending;
	}
	NSUInteger ia = ((WKDModelElement *)a).carrierIndex, ib = ((WKDModelElement *)b).carrierIndex;
	return ia < ib ? NSOrderedAscending : ia > ib ? NSOrderedDescending : NSOrderedSame;
}

- (void)rememberPlaceOf:(WKDModelElement *)element
{
	NSXMLElement *carrier = element.element;
	if ([carrier parent] != nil) {
		element.carrierParent = (NSXMLElement *)[carrier parent];
		element.carrierIndex = [carrier index];
	}
	NSXMLElement *shown = element.diagramElement;
	if ([shown parent] != nil) {
		element.diagramParent = (NSXMLElement *)[shown parent];
		element.diagramIndex = [shown index];
	}
}

- (void)attach:(WKDModelElement *)element
{
	NSXMLElement *carrier = element.element;
	if (carrier == nil) {
		element.element = [self newCarrierElementFor:element];
	} else if ([carrier parent] == nil && element.carrierParent != nil) {
		NSXMLElement *parent = element.carrierParent;
		WKDLogInsert(self.journal, parent, carrier, MIN(element.carrierIndex, [[parent children] count]));
	}
}

- (void)attachDiagramElementOf:(WKDModelElement *)element
{
	NSXMLElement *shown = element.diagramElement;
	if (shown != nil && [shown parent] == nil && element.diagramParent != nil) {
		NSXMLElement *parent = element.diagramParent;
		WKDLogInsert(self.journal, parent, shown, MIN(element.diagramIndex, [[parent children] count]));
	}
}

static NSInteger
WKDByDiagramIndex(id a, id b, void *context)
{
	NSUInteger ia = ((WKDModelElement *)a).diagramIndex, ib = ((WKDModelElement *)b).diagramIndex;
	return ia < ib ? NSOrderedAscending : ia > ib ? NSOrderedDescending : NSOrderedSame;
}

/* A new element's XML, where the editor has always put it: a node at the
 * end of its container, with its event definition; a flow at the end of
 * its target's container. */
- (NSXMLElement *)newCarrierElementFor:(WKDModelElement *)element
{
	if ([element isKindOfClass:[WKDNode class]]) {
		WKDNode *node = (WKDNode *)element;
		NSXMLElement *carrier = WKDNewElement(self.document, WKDBpmnNamespace, node.type);
		WKDSetAttribute(carrier, @"id", node.elementId);
		if (node.eventDefinition != nil) {
			NSXMLElement *definition = WKDNewElement(self.document, WKDBpmnNamespace, node.eventDefinition);
			NSString *prefix = [[[node.eventDefinition substringToIndex:1] uppercaseString]
				stringByAppendingString:[node.eventDefinition substringFromIndex:1]];
			WKDSetAttribute(definition, @"id", [NSString stringWithFormat:@"%@_%@", prefix, node.elementId]);
			[carrier addChild:definition];
		}
		WKDLogAdd(self.journal, node.parent != nil ? node.parent.element : self.process, carrier);
		return carrier;
	}
	WKDFlow *flow = (WKDFlow *)element;
	NSXMLElement *carrier = WKDNewElement(self.document, WKDBpmnNamespace, flow.isAssociation ? @"association" : @"sequenceFlow");
	WKDSetAttribute(carrier, @"id", flow.elementId);
	WKDLogAdd(self.journal, flow.target.parent != nil ? flow.target.parent.element : self.process, carrier);
	return carrier;
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
			NSXMLElement *child = WKDChild(element, WKDBpmnNamespace, @"text");
			if ([node.name length] == 0) {
				WKDLogDetach(self.journal, child);
			} else if (child != nil) {
				[child setStringValue:node.name];
				[self.journal didSetText:child from:text to:node.name];
			} else {
				child = WKDNewElement(self.document, WKDBpmnNamespace, @"text");
				[child setStringValue:node.name];
				WKDLogAdd(self.journal, element, child);
			}
		}
	} else {
		WKDWriteAttribute(self.journal, element, @"name", node.name);
	}
	if (node.host != nil) {
		WKDWriteAttribute(self.journal, element, @"attachedToRef", node.host.elementId);
		[self writeInterrupting:node.interrupting of:element attribute:@"cancelActivity"];
	} else if ([node.type isEqualToString:@"startEvent"] && node.parent.eventSubProcess) {
		[self writeInterrupting:node.interrupting of:element attribute:@"isInterrupting"];
	}
	if (WKDIsContainerType(node.type)) {
		BOOL triggered = [WKDAttribute(element, @"triggeredByEvent") isEqualToString:@"true"];
		if (triggered != node.eventSubProcess) {
			WKDLogAttribute(self.journal, element, @"triggeredByEvent", node.eventSubProcess ? @"true" : nil);
		}
	}
	/* A default that names a flow the model knows -- or one leaving -- is the
	 * model's to write; one naming what it never knew is left as it is. */
	NSString *written = WKDAttribute(element, @"default");
	if (node.defaultFlow != nil || (written != nil && [self knowsFlow:written])) {
		WKDWriteAttribute(self.journal, element, @"default", node.defaultFlow.elementId);
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
		WKDLogAttribute(self.journal, element, attribute, interrupting ? nil : @"false");
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
		if ([self knowsFlow:ref]) {
			[known addObject:ref];
		}
	}
	if ([known isEqualToSet:wanted]) {
		return;
	}
	for (NSXMLElement *child in WKDChildren(element, WKDBpmnNamespace, local)) {
		NSString *ref = [[child stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([self knowsFlow:ref] && ![wanted containsObject:ref]) {
			WKDLogDetach(self.journal, child);
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
		WKDLogInsert(self.journal, element, ref, [[same lastObject] index] + 1);
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
	WKDLogInsert(self.journal, element, ref, index);
}

#pragma mark Flows

- (void)writeFlow:(WKDFlow *)flow
{
	NSXMLElement *element = flow.element;
	WKDWriteAttribute(self.journal, element, @"name", flow.name);
	WKDWriteAttribute(self.journal, element, @"sourceRef", flow.source.elementId);
	WKDWriteAttribute(self.journal, element, @"targetRef", flow.target.elementId);
	[self writeEdgeOf:flow];
}

- (void)writeEdgeOf:(WKDFlow *)flow
{
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
				WKDLogDetach(self.journal, waypoint);
			}
			for (NSValue *value in flow.waypoints) {
				NSXMLElement *waypoint = WKDNewElement(self.document, WKDDINamespace, @"waypoint");
				WKDSetAttribute(waypoint, @"x", WKDFormat([value pointValue].x));
				WKDSetAttribute(waypoint, @"y", WKDFormat([value pointValue].y));
				WKDLogInsert(self.journal, edge, waypoint, index++);
			}
		}
	}
	[self writeLabelBounds:flow.labelBounds of:edge];
}

#pragma mark Lanes

- (void)writeLane:(WKDSwimlane *)lane
{
	WKDWriteAttribute(self.journal, lane.element, @"name", lane.name);
	if (!lane.isPool) {
		NSMutableSet *wanted = [NSMutableSet setWithArray:[lane.nodeList valueForKey:@"elementId"]];
		NSMutableSet *known = [NSMutableSet set];
		for (NSString *ref in WKDChildTexts(lane.element, @"flowNodeRef")) {
			if ([self knowsNode:ref]) {
				[known addObject:ref];
			}
		}
		if (![known isEqualToSet:wanted]) {
			for (NSXMLElement *child in WKDChildren(lane.element, WKDBpmnNamespace, @"flowNodeRef")) {
				NSString *ref = [[child stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				if ([self knowsNode:ref] && ![wanted containsObject:ref]) {
					WKDLogDetach(self.journal, child);
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

- (void)writeGeometryOf:(WKDModelElement *)element
{
	if ([element isKindOfClass:[WKDNode class]]) {
		WKDNode *node = (WKDNode *)element;
		[self writeShapeOf:node bounds:node.bounds hasBounds:node.hasBounds labelBounds:node.labelBounds];
	} else if ([element isKindOfClass:[WKDSwimlane class]]) {
		WKDSwimlane *lane = (WKDSwimlane *)element;
		[self writeShapeOf:lane bounds:lane.bounds hasBounds:lane.hasBounds labelBounds:NSZeroRect];
	} else if ([element isKindOfClass:[WKDFlow class]]) {
		[self writeEdgeOf:(WKDFlow *)element];
	}
}

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
		WKDLogInsert(self.journal, shape, box, 0);
	}
	/* A container's shape is drawn expanded, as the editor has always
	 * written it whenever it placed one. */
	if (WKDWriteBounds(self.journal, box, bounds) && [element isKindOfClass:[WKDNode class]]
	    && WKDIsContainerType(((WKDNode *)element).type)) {
		WKDWriteAttribute(self.journal, shape, @"isExpanded", @"true");
	}
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
		WKDLogAdd(self.journal, diagramElement, label);
	}
	NSXMLElement *box = WKDChild(label, WKDDCNamespace, @"Bounds");
	if (box == nil) {
		box = WKDNewElement(self.document, WKDDCNamespace, @"Bounds");
		WKDLogAdd(self.journal, label, box);
	}
	WKDWriteBounds(self.journal, box, rect);
}

/* A BPMNShape or BPMNEdge for the element, at the end of the plane, which
 * is made when the document has no diagram. */
- (NSXMLElement *)newDiagramElement:(NSString *)local for:(WKDModelElement *)element
{
	if (self.plane == nil) {
		NSString *processId = WKDAttribute(self.process, @"id");
		NSXMLElement *diagram = WKDNewElement(self.document, WKDBpmnDINamespace, @"BPMNDiagram");
		WKDSetAttribute(diagram, @"id", [NSString stringWithFormat:@"BPMNDiagram_%@", processId]);
		NSXMLElement *plane = WKDNewElement(self.document, WKDBpmnDINamespace, @"BPMNPlane");
		WKDSetAttribute(plane, @"id", [NSString stringWithFormat:@"BPMNPlane_%@", processId]);
		WKDSetAttribute(plane, @"bpmnElement", processId);
		[diagram addChild:plane];
		WKDLogAdd(self.journal, [self.document rootElement], diagram);
		self.plane = plane;
	}
	NSXMLElement *diagramElement = WKDNewElement(self.document, WKDBpmnDINamespace, local);
	NSString *suffix = [local isEqualToString:@"BPMNShape"] ? @"Shape" : @"Edge";
	WKDSetAttribute(diagramElement, @"id", [NSString stringWithFormat:@"%@_%@", element.elementId, suffix]);
	WKDSetAttribute(diagramElement, @"bpmnElement", element.elementId);
	WKDLogAdd(self.journal, self.plane, diagramElement);
	element.diagramElement = diagramElement;
	return diagramElement;
}

@end

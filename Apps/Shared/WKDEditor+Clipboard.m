#import "WKDEditorPriv.h"
#import "WKDXML.h"

/*
 * Copying and pasting. What is copied is a BPMN document of its own -- a
 * process holding the copies, a diagram holding their shapes, and the
 * messages, signals, errors and escalations they name -- so that it can
 * be pasted into another document, or into another modeller as text.
 */

/* The attributes that name another element of the process, and the
 * top-level definitions an event or a task names. */
static NSArray<NSString *> *
WKDReferences(void)
{
	return @[ @"sourceRef", @"targetRef", @"attachedToRef", @"default" ];
}

static NSArray<NSString *> *
WKDDefinitionReferences(void)
{
	return @[ @"messageRef", @"signalRef", @"errorRef", @"escalationRef" ];
}

/* The element and every element below it, in document order. */
static NSArray<NSXMLElement *> *
WKDSelfAndBelow(NSXMLElement *element)
{
	NSMutableArray *all = [NSMutableArray arrayWithObject:element];
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			[all addObjectsFromArray:WKDSelfAndBelow((NSXMLElement *)child)];
		}
	}
	return all;
}

@implementation WKDEditor (WKDClipboard)

- (NSXMLDocument *)fragmentOfElements:(NSArray<NSString *> *)elementIds
{
	WKDDiagram *diagram = self.diagram;
	/* The nodes with what they hold and what is attached to them; a
	 * boundary event without its activity has nothing to sit on. */
	NSMutableSet *nodes = [NSMutableSet set];
	for (NSString *elementId in elementIds) {
		WKDShape *shape = [diagram shapeWithId:elementId];
		if (shape != nil && (shape.host == nil || [elementIds containsObject:shape.host.elementId])) {
			[self collect:shape into:nodes];
		}
	}
	if ([nodes count] == 0) {
		return nil;
	}
	/* What goes at the copy's top: the nodes not inside another copied
	 * one, and the flows between copied nodes that are not either. */
	NSMutableArray *top = [NSMutableArray array];
	NSMutableSet *flows = [NSMutableSet set];
	for (WKDShape *shape in diagram.shapes) {
		if ([nodes containsObject:shape.elementId] && ![nodes containsObject:shape.parent.elementId ?: @""]) {
			[top addObject:shape.element];
		}
	}
	for (WKDConnection *connection in diagram.connections) {
		if ([nodes containsObject:connection.source.elementId] && [nodes containsObject:connection.target.elementId]) {
			[flows addObject:connection.elementId];
			if (![nodes containsObject:connection.target.parent.elementId ?: @""]) {
				[top addObject:connection.element];
			}
		}
	}

	NSXMLElement *root = [self.document rootElement];
	NSXMLElement *definitions = [[NSXMLElement alloc] initWithName:[root name] URI:[root URI]];
	for (NSXMLNode *namespace in [root namespaces]) {
		[definitions addNamespace:[namespace copy]];
	}
	WKDSetAttribute(definitions, @"id", @"Clipboard");
	WKDSetAttribute(definitions, @"targetNamespace", WKDAttribute(root, @"targetNamespace") ?: @"http://bpmn.io/schema/bpmn");
	NSXMLDocument *fragment = [[NSXMLDocument alloc] initWithRootElement:definitions];
	[fragment setCharacterEncoding:@"UTF-8"];
	NSXMLElement *process = WKDNewElement(fragment, WKDBpmnNamespace, @"process");
	WKDSetAttribute(process, @"id", @"Clipboard_process");
	WKDSetAttribute(process, @"isExecutable", @"true");

	NSMutableSet *named = [NSMutableSet set];
	NSMutableSet *copied = [NSMutableSet set];
	for (NSXMLElement *element in top) {
		NSXMLElement *copy = [element copy];
		for (NSXMLElement *below in WKDSelfAndBelow(copy)) {
			/* References to flows not copied go. */
			if ((WKDIs(below, WKDBpmnNamespace, @"incoming") || WKDIs(below, WKDBpmnNamespace, @"outgoing"))
			    && ![flows containsObject:[below stringValue]]) {
				[below detach];
				continue;
			}
			if (WKDAttribute(below, @"default") != nil && ![flows containsObject:WKDAttribute(below, @"default")]) {
				WKDSetAttribute(below, @"default", nil);
			}
			for (NSString *reference in WKDDefinitionReferences()) {
				if (WKDAttribute(below, reference) != nil) {
					[named addObject:WKDAttribute(below, reference)];
				}
			}
			if (WKDAttribute(below, @"id") != nil) {
				[copied addObject:WKDAttribute(below, @"id")];
			}
		}
		[process addChild:copy];
	}
	for (NSXMLElement *child in WKDChildren(root, WKDBpmnNamespace, nil)) {
		if ([named containsObject:WKDAttribute(child, @"id") ?: @""]) {
			[definitions addChild:[child copy]];
		}
	}
	[definitions addChild:process];

	NSXMLElement *diagramElement = WKDNewElement(fragment, WKDBpmnDINamespace, @"BPMNDiagram");
	WKDSetAttribute(diagramElement, @"id", @"Clipboard_diagram");
	NSXMLElement *plane = WKDNewElement(fragment, WKDBpmnDINamespace, @"BPMNPlane");
	WKDSetAttribute(plane, @"id", @"Clipboard_plane");
	WKDSetAttribute(plane, @"bpmnElement", @"Clipboard_process");
	for (NSXMLElement *source in WKDChildren(diagram.plane, WKDBpmnDINamespace, nil)) {
		if ([copied containsObject:WKDAttribute(source, @"bpmnElement") ?: @""]) {
			[plane addChild:[source copy]];
		}
	}
	[diagramElement addChild:plane];
	[definitions addChild:diagramElement];
	return fragment;
}

/* An id's prefix for a copy of the element: a node's as a new one gets,
 * a flow's Flow, anything else its own name's. */
static NSString *
WKDCopyPrefix(NSXMLElement *element)
{
	NSString *local = [element localName];
	BOOL flowNode = NO;
	WKDKindOfType(local, &flowNode);
	if (flowNode) {
		return WKDIdPrefix(local);
	}
	if ([local isEqualToString:@"sequenceFlow"]) {
		return @"Flow";
	}
	return [[[local substringToIndex:1] uppercaseString] stringByAppendingString:[local substringFromIndex:1]];
}

- (NSArray<NSString *> *)paste:(NSXMLDocument *)fragment offset:(NSSize)offset error:(NSString **)reason
{
	NSXMLElement *from = WKDChild([fragment rootElement], WKDBpmnNamespace, @"process");
	NSArray *top = from != nil ? WKDChildren(from, WKDBpmnNamespace, nil) : @[];
	if ([top count] == 0 || self.diagram.process == nil) {
		if (reason != NULL) {
			*reason = self.diagram.process == nil ? @"The document has no process." : @"There is nothing to paste.";
		}
		return nil;
	}
	NSXMLElement *fromPlane = [WKDDescendants([fragment rootElement], WKDBpmnDINamespace, @"BPMNPlane") firstObject];
	NSMutableArray *added = [NSMutableArray array];
	[self change:@"Paste" with:^{
		NSXMLDocument *document = self.document;
		NSXMLElement *root = [document rootElement];
		/* The definitions they name: the one of that id here when there is
		 * one of the same kind, else a copy. */
		NSMutableDictionary<NSString *, NSString *> *ids = [NSMutableDictionary dictionary];
		NSXMLElement *firstProcess = WKDChild(root, WKDBpmnNamespace, @"process");
		for (NSXMLElement *definition in WKDChildren([fragment rootElement], WKDBpmnNamespace, nil)) {
			NSString *definitionId = WKDAttribute(definition, @"id");
			if ([[definition localName] isEqualToString:@"process"] || definitionId == nil) {
				continue;
			}
			NSXMLElement *existing = WKDElementWithId(document, definitionId);
			if (existing != nil && [[existing localName] isEqualToString:[definition localName]]) {
				continue;
			}
			NSXMLElement *copy = [definition copy];
			if (existing != nil) {
				NSString *fresh = [self freshId:WKDCopyPrefix(definition)];
				[ids setObject:fresh forKey:definitionId];
				WKDSetAttribute(copy, @"id", fresh);
			}
			WKDAdoptInto(document, copy, fragment, root, firstProcess != nil ? [firstProcess index] : [root childCount]);
		}
		/* Everything pasted gets an id of its own. */
		NSMutableArray *copies = [NSMutableArray array];
		for (NSXMLElement *element in top) {
			NSXMLElement *copy = [element copy];
			for (NSXMLElement *below in WKDSelfAndBelow(copy)) {
				NSString *old = WKDAttribute(below, @"id");
				if (old != nil) {
					NSString *fresh = [self freshId:WKDCopyPrefix(below)];
					/* freshId reads the document; hold the new id against
					 * the next one until the copy is in it. */
					while ([[ids allValues] containsObject:fresh]) {
						fresh = [self freshId:WKDCopyPrefix(below)];
					}
					[ids setObject:fresh forKey:old];
				}
			}
			[copies addObject:copy];
		}
		for (NSXMLElement *copy in copies) {
			for (NSXMLElement *below in WKDSelfAndBelow(copy)) {
				NSString *old = WKDAttribute(below, @"id");
				if (old != nil && [ids objectForKey:old] != nil) {
					WKDSetAttribute(below, @"id", [ids objectForKey:old]);
				}
				for (NSString *reference in [WKDReferences() arrayByAddingObjectsFromArray:WKDDefinitionReferences()]) {
					NSString *value = WKDAttribute(below, reference);
					if (value != nil && [ids objectForKey:value] != nil) {
						WKDSetAttribute(below, reference, [ids objectForKey:value]);
					}
				}
				if ((WKDIs(below, WKDBpmnNamespace, @"incoming") || WKDIs(below, WKDBpmnNamespace, @"outgoing"))
				    && [ids objectForKey:[below stringValue]] != nil) {
					[below setStringValue:[ids objectForKey:[below stringValue]]];
				}
			}
			NSXMLElement *adopted = WKDAdoptInto(document, copy, fragment, self.diagram.process,
			                                     [self.diagram.process childCount]);
			[added addObject:WKDAttribute(adopted, @"id")];
		}
		/* Their shapes and edges, moved by the offset. */
		for (NSXMLElement *source in WKDChildren(fromPlane, WKDBpmnDINamespace, nil)) {
			NSString *shown = [ids objectForKey:WKDAttribute(source, @"bpmnElement") ?: @""];
			if (shown == nil) {
				continue;
			}
			NSXMLElement *copy = [source copy];
			WKDSetAttribute(copy, @"bpmnElement", shown);
			WKDSetAttribute(copy, @"id", [NSString stringWithFormat:@"%@_di", shown]);
			for (NSXMLElement *below in WKDSelfAndBelow(copy)) {
				if (WKDIs(below, WKDDCNamespace, @"Bounds") || WKDIs(below, WKDDINamespace, @"waypoint")) {
					WKDSetAttribute(below, @"x", WKDFormat(WKDNumber(below, @"x") + offset.width));
					WKDSetAttribute(below, @"y", WKDFormat(WKDNumber(below, @"y") + offset.height));
				}
			}
			NSXMLElement *plane = [self plane];
			WKDAdoptInto(document, copy, fragment, plane, [plane childCount]);
		}
	}];
	return added;
}

@end

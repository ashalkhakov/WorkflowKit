#import "WKDXML.h"

NSString * const WKDBpmnNamespace = @"http://www.omg.org/spec/BPMN/20100524/MODEL";
NSString * const WKDBpmnDINamespace = @"http://www.omg.org/spec/BPMN/20100524/DI";
NSString * const WKDDCNamespace = @"http://www.omg.org/spec/DD/20100524/DC";
NSString * const WKDDINamespace = @"http://www.omg.org/spec/DD/20100524/DI";
NSString * const WKDCamundaNamespace = @"http://camunda.org/schema/1.0/bpmn";
NSString * const WKDExtensionNamespace = @"https://workflowkit.local/bpmn";
NSString * const WKDXSINamespace = @"http://www.w3.org/2001/XMLSchema-instance";

BOOL
WKDIs(NSXMLNode *node, NSString *uri, NSString *local)
{
	return [node kind] == NSXMLElementKind && [[node URI] isEqualToString:uri]
		&& (local == nil || [[node localName] isEqualToString:local]);
}

NSArray<NSXMLElement *> *
WKDChildren(NSXMLElement *element, NSString *uri, NSString *local)
{
	NSMutableArray *found = [NSMutableArray array];
	for (NSXMLNode *child in [element children]) {
		if (WKDIs(child, uri, local)) {
			[found addObject:child];
		}
	}
	return found;
}

NSXMLElement *
WKDChild(NSXMLElement *element, NSString *uri, NSString *local)
{
	for (NSXMLNode *child in [element children]) {
		if (WKDIs(child, uri, local)) {
			return (NSXMLElement *)child;
		}
	}
	return nil;
}

static void
WKDCollect(NSXMLElement *element, NSString *uri, NSString *local, NSMutableArray *found)
{
	for (NSXMLNode *child in [element children]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		if (WKDIs(child, uri, local)) {
			[found addObject:child];
		}
		WKDCollect((NSXMLElement *)child, uri, local, found);
	}
}

NSArray<NSXMLElement *> *
WKDDescendants(NSXMLElement *element, NSString *uri, NSString *local)
{
	NSMutableArray *found = [NSMutableArray array];
	WKDCollect(element, uri, local, found);
	return found;
}

NSString *
WKDAttribute(NSXMLElement *element, NSString *name)
{
	return [[element attributeForName:name] stringValue];
}

void
WKDSetAttribute(NSXMLElement *element, NSString *name, NSString *value)
{
	if (value == nil) {
		[element removeAttributeForName:name];
		return;
	}
	NSXMLNode *attribute = [element attributeForName:name];
	if (attribute != nil) {
		[attribute setStringValue:value];
	} else {
		[element addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
	}
}

double
WKDNumber(NSXMLElement *element, NSString *name)
{
	return [WKDAttribute(element, name) doubleValue];
}

NSString *
WKDFormat(double value)
{
	/* Whole numbers as such: diagrams are written in whole points. */
	double rounded = round(value);
	return [NSString stringWithFormat:@"%.0f", rounded == 0 ? 0.0 : rounded];
}

/* The prefix the BPMN world usually gives a namespace. */
static NSString *
WKDUsualPrefix(NSString *uri)
{
	NSDictionary *prefixes = @{ WKDBpmnNamespace: @"bpmn", WKDBpmnDINamespace: @"bpmndi",
	                            WKDDCNamespace: @"dc", WKDDINamespace: @"di", WKDCamundaNamespace: @"camunda",
	                            WKDExtensionNamespace: @"wf", WKDXSINamespace: @"xsi" };
	return [prefixes objectForKey:uri] ?: @"ns";
}

/* The prefix the root gives the namespace; with declare, the usual one,
 * declared there, when it gives none. */
static NSString *
WKDPrefix(NSXMLDocument *document, NSString *uri, BOOL declare)
{
	NSXMLElement *root = [document rootElement];
	for (NSXMLNode *namespace in [root namespaces]) {
		if ([[namespace stringValue] isEqualToString:uri]) {
			return [namespace name] ?: @"";
		}
	}
	if (!declare) {
		return nil;
	}
	NSString *prefix = WKDUsualPrefix(uri);
	[root addNamespace:[NSXMLNode namespaceWithName:prefix stringValue:uri]];
	return prefix;
}

static NSString *
WKDQualify(NSString *prefix, NSString *local)
{
	return [prefix length] > 0 ? [NSString stringWithFormat:@"%@:%@", prefix, local] : local;
}

NSXMLElement *
WKDNewElement(NSXMLDocument *document, NSString *uri, NSString *local)
{
	return [[NSXMLElement alloc] initWithName:WKDQualify(WKDPrefix(document, uri, YES), local) URI:uri];
}

NSString *
WKDQualifiedAttribute(NSXMLDocument *document, NSXMLElement *element, NSString *uri, NSString *local)
{
	NSString *prefix = WKDPrefix(document, uri, NO);
	return prefix != nil ? WKDAttribute(element, WKDQualify(prefix, local)) : nil;
}

void
WKDSetQualifiedAttribute(NSXMLDocument *document, NSXMLElement *element, NSString *uri, NSString *local,
                         NSString *value)
{
	if ([value length] == 0) {
		NSString *prefix = WKDPrefix(document, uri, NO);
		if (prefix != nil) {
			[element removeAttributeForName:WKDQualify(prefix, local)];
		}
		return;
	}
	NSString *name = WKDQualify(WKDPrefix(document, uri, YES), local);
	NSXMLNode *attribute = [element attributeForName:name];
	if (attribute != nil) {
		[attribute setStringValue:value];
	} else {
		[element addAttribute:[NSXMLNode attributeWithName:name URI:uri stringValue:value]];
	}
}

/* Where a child goes among its siblings, by BPMN's schema. */
static NSInteger
WKDRank(NSString *local)
{
	NSDictionary *ranks = @{ @"documentation": @0, @"extensionElements": @1, @"incoming": @2, @"outgoing": @3,
	                         @"standardLoopCharacteristics": @9, @"multiInstanceLoopCharacteristics": @9 };
	NSNumber *rank = [ranks objectForKey:local];
	return rank != nil ? [rank integerValue] : 5;
}

NSXMLElement *
WKDEnsureChild(NSXMLDocument *document, NSXMLElement *parent, NSString *uri, NSString *local)
{
	NSXMLElement *child = WKDChild(parent, uri, local);
	if (child != nil) {
		return child;
	}
	child = WKDNewElement(document, uri, local);
	NSInteger rank = [uri isEqualToString:WKDBpmnNamespace] ? WKDRank(local) : 5;
	NSArray *children = [parent children];
	NSUInteger index = [children count];
	for (NSUInteger i = 0; i < [children count]; i++) {
		NSXMLNode *sibling = [children objectAtIndex:i];
		if ([sibling kind] == NSXMLElementKind && WKDIs(sibling, WKDBpmnNamespace, nil)
		    && WKDRank([sibling localName]) > rank) {
			index = i;
			break;
		}
	}
	[parent insertChild:child atIndex:index];
	return child;
}

NSString *
WKDChildText(NSXMLElement *parent, NSString *uri, NSString *local)
{
	NSXMLElement *child = WKDChild(parent, uri, local);
	return child != nil ? [child stringValue] : nil;
}

NSXMLElement *
WKDSetChildText(NSXMLDocument *document, NSXMLElement *parent, NSString *uri, NSString *local, NSString *text)
{
	if ([text length] == 0) {
		[WKDChild(parent, uri, local) detach];
		return nil;
	}
	NSXMLElement *child = WKDEnsureChild(document, parent, uri, local);
	[child setStringValue:text];
	return child;
}

NSXMLElement *
WKDElementWithId(NSXMLDocument *document, NSString *elementId)
{
	if (elementId == nil) {
		return nil;
	}
	NSMutableArray *pending = [NSMutableArray arrayWithObject:[document rootElement]];
	while ([pending count] > 0) {
		NSXMLElement *element = [pending lastObject];
		[pending removeLastObject];
		if ([WKDAttribute(element, @"id") isEqualToString:elementId]) {
			return element;
		}
		for (NSXMLNode *child in [element children]) {
			if ([child kind] == NSXMLElementKind) {
				[pending addObject:child];
			}
		}
	}
	return nil;
}

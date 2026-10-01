#import "WKDXML.h"

NSString * const WKDBpmnNamespace = @"http://www.omg.org/spec/BPMN/20100524/MODEL";
NSString * const WKDBpmnDINamespace = @"http://www.omg.org/spec/BPMN/20100524/DI";
NSString * const WKDDCNamespace = @"http://www.omg.org/spec/DD/20100524/DC";
NSString * const WKDDINamespace = @"http://www.omg.org/spec/DD/20100524/DI";

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
	                            WKDDCNamespace: @"dc", WKDDINamespace: @"di" };
	return [prefixes objectForKey:uri] ?: @"ns";
}

NSXMLElement *
WKDNewElement(NSXMLDocument *document, NSString *uri, NSString *local)
{
	NSXMLElement *root = [document rootElement];
	NSString *prefix = nil;
	for (NSXMLNode *namespace in [root namespaces]) {
		if ([[namespace stringValue] isEqualToString:uri]) {
			prefix = [namespace name] ?: @"";
			break;
		}
	}
	if (prefix == nil) {
		prefix = WKDUsualPrefix(uri);
		[root addNamespace:[NSXMLNode namespaceWithName:prefix stringValue:uri]];
	}
	NSString *name = [prefix length] > 0 ? [NSString stringWithFormat:@"%@:%@", prefix, local] : local;
	return [[NSXMLElement alloc] initWithName:name URI:uri];
}

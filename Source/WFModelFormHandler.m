#import "WFModelFormHandler.h"

static NSString * const WFXFormsNamespace = @"http://www.w3.org/2002/xforms";

/* The value of an attribute by its local name, whatever its prefix. */
static NSString *
WFAttribute(NSXMLElement *element, NSString *localName)
{
	for (NSXMLNode *attribute in [element attributes]) {
		if ([[attribute localName] isEqualToString:localName]) {
			return [attribute stringValue];
		}
	}
	return nil;
}

/* Each element of the namespace's of the local name beneath the node. */
static void
WFCollect(NSXMLNode *node, NSString *localName, NSMutableArray<NSXMLElement *> *into)
{
	for (NSXMLNode *child in [node children]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *element = (NSXMLElement *)child;
		if ([[element localName] isEqualToString:localName] && [[element URI] isEqualToString:WFXFormsNamespace]) {
			[into addObject:element];
		}
		WFCollect(element, localName, into);
	}
}

/* The element at the path beneath the root, each step a child by name. */
static NSXMLElement *
WFElementAt(NSXMLElement *root, NSString *path)
{
	NSXMLElement *at = root;
	for (NSString *step in [path componentsSeparatedByString:@"/"]) {
		NSXMLElement *next = nil;
		for (NSXMLNode *child in [at children]) {
			if (next == nil && [child kind] == NSXMLElementKind && [[child name] isEqualToString:step]) {
				next = (NSXMLElement *)child;
			}
		}
		if (next == nil) {
			return nil;
		}
		at = next;
	}
	return at;
}

/* A variable as an instance's text: a string or a number; nil for others. */
static NSString *
WFTextOf(id value)
{
	if ([value isKindOfClass:[NSString class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSNumber class]]) {
		return [value stringValue];
	}
	return nil;
}

@implementation WFModelFormHandler

- (NSXMLDocument *)instanceForForm:(WFFormContext *)context error:(NSError **)error
{
	(void)error;
	NSMutableArray *instances = [NSMutableArray array];
	WFCollect(context.document, @"instance", instances);
	NSXMLElement *formInstance = nil;
	for (NSXMLElement *each in instances) {
		formInstance = formInstance == nil && [WFAttribute(each, @"id") isEqualToString:@"form"] ? each : formInstance;
	}
	NSXMLElement *root = nil;
	for (NSXMLNode *child in [formInstance children]) {
		root = root == nil && [child kind] == NSXMLElementKind ? [(NSXMLElement *)child copy] : root;
	}
	if (root == nil) {
		/* No document: the task's variables, for the application's view. */
		root = [NSXMLElement elementWithName:@"variables"];
		for (NSString *name in [[context.variables allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			NSString *text = WFTextOf([context.variables objectForKey:name]);
			NSXMLElement *element = text != nil && [name length] > 0 ? [NSXMLElement elementWithName:name stringValue:text] : nil;
			if (element != nil && [[element name] isEqualToString:name]) {
				[root addChild:element];
			}
		}
		NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:root];
		[document setDocumentContentKind:NSXMLDocumentXMLKind];
		return document;
	}
	/* Its inputs from the variables: each bind of a given element, at its
	 * path (within an anchor's bind, of several, that anchor's). */
	NSMutableArray *binds = [NSMutableArray array];
	WFCollect(context.document, @"bind", binds);
	for (NSXMLElement *bind in binds) {
		NSString *ref = WFAttribute(bind, @"ref");
		if (![WFAttribute(bind, @"role") isEqualToString:@"given"] || ref == nil) {
			continue;
		}
		NSXMLElement *parent = (NSXMLElement *)[bind parent];
		NSString *within = [[parent localName] isEqualToString:@"bind"] ? WFAttribute(parent, @"nodeset") : nil;
		NSString *path = within != nil ? [NSString stringWithFormat:@"%@/%@", within, ref] : ref;
		NSString *text = WFTextOf([context.variables objectForKey:path])
		                 ?: WFTextOf([context.variables objectForKey:ref])
		                 ?: WFTextOf([context.variables objectForKey:[[ref componentsSeparatedByString:@"/"] lastObject]]);
		NSXMLElement *element = text != nil ? WFElementAt(root, path) : nil;
		[element setStringValue:text];
	}
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:root];
	[document setDocumentContentKind:NSXMLDocumentXMLKind];
	return document;
}

/* The rows' names: each xf:repeat's last step. */
static NSSet<NSString *> *
WFRepeatNames(NSXMLDocument *document)
{
	NSMutableArray *repeats = [NSMutableArray array];
	WFCollect(document, @"repeat", repeats);
	NSMutableSet *names = [NSMutableSet set];
	for (NSXMLElement *repeat in repeats) {
		NSString *nodeset = WFAttribute(repeat, @"nodeset");
		if (nodeset != nil) {
			[names addObject:[[nodeset componentsSeparatedByString:@"/"] lastObject]];
		}
	}
	return names;
}

/* Each element beneath the element, by its path after the prefix: a text,
 * or rows. */
static void
WFFlatten(NSXMLElement *element, NSString *prefix, NSSet<NSString *> *repeats, NSMutableDictionary *into)
{
	NSMutableDictionary<NSString *, NSMutableArray *> *rows = [NSMutableDictionary dictionary];
	NSCountedSet *names = [NSCountedSet set];
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			[names addObject:[child name]];
		}
	}
	for (NSXMLNode *child in [element children]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *each = (NSXMLElement *)child;
		NSString *name = [each name];
		NSString *path = prefix != nil ? [NSString stringWithFormat:@"%@/%@", prefix, name] : name;
		BOOL structured = NO;
		for (NSXMLNode *grandchild in [each children]) {
			structured = structured || [grandchild kind] == NSXMLElementKind;
		}
		if (structured && ([repeats containsObject:name] || [names countForObject:name] > 1)) {
			NSMutableDictionary *row = [NSMutableDictionary dictionary];
			WFFlatten(each, nil, repeats, row);
			NSMutableArray *list = [rows objectForKey:path] ?: [NSMutableArray array];
			[list addObject:row];
			[rows setObject:list forKey:path];
		} else if (structured) {
			WFFlatten(each, path, repeats, into);
		} else {
			[into setObject:[each stringValue] ?: @"" forKey:path];
		}
	}
	[into addEntriesFromDictionary:rows];
}

- (NSDictionary *)variablesFromInstance:(NSXMLDocument *)instance form:(WFFormContext *)context error:(NSError **)error
{
	(void)error;
	NSMutableDictionary *variables = [NSMutableDictionary dictionary];
	NSXMLElement *root = [instance rootElement];
	if (root != nil) {
		WFFlatten(root, nil, WFRepeatNames(context.document), variables);
	}
	return variables;
}

@end

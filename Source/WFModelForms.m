#import "WFModelForms.h"
#import "WFTypes.h"

NSString * const WFModelFormsORMImportType = @"http://schemas.neumont.edu/ORM/2006-04/ORMRoot";
NSString * const WFModelFormsFlowImportType = @"http://schemas.ormkit.org/2026-10/Flows";
NSString * const WFModelFormKeyPrefix = @"ormkit:form:";
NSString * const WFModelFlowKeyPrefix = @"ormkit:flow:";

static NSString * const WFModelBpmnNamespace = @"http://www.omg.org/spec/BPMN/20100524/MODEL";
static NSString * const WFModelCamundaNamespace = @"http://camunda.org/schema/1.0/bpmn";
static NSString * const WFModelQueriesNamespace = @"http://schemas.ormkit.org/2026-10/Queries";

@interface WFModelForm ()
@property (nonatomic, readwrite, copy) NSString *formKey;
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSString *location;
@property (nonatomic, readwrite, getter=isFlow) BOOL flow;
@end

@implementation WFModelForm
@end

/* Every element under the root, depth first. */
static void
WFModelElements(NSXMLElement *element, NSMutableArray<NSXMLElement *> *found)
{
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			[found addObject:(NSXMLElement *)child];
			WFModelElements((NSXMLElement *)child, found);
		}
	}
}

static NSArray<NSXMLElement *> *
WFModelAll(NSXMLDocument *document)
{
	NSMutableArray *found = [NSMutableArray array];
	if ([document rootElement] != nil) {
		[found addObject:[document rootElement]];
		WFModelElements([document rootElement], found);
	}
	return found;
}

static NSXMLDocument *
WFModelDocument(NSData *data)
{
	return data != nil ? [[NSXMLDocument alloc] initWithData:data options:0 error:NULL] : nil;
}

/* The attribute of the local name in the namespace, whatever its prefix. */
static NSString *
WFModelAttribute(NSXMLElement *element, NSString *namespaceURI, NSString *localName)
{
	NSXMLNode *attribute = [element attributeForLocalName:localName URI:namespaceURI];
	if (attribute != nil) {
		return [attribute stringValue];
	}
	/* GNUstep's NSXML does not always know an attribute's URI: by its
	 * prefix as the document declares it. */
	for (NSXMLNode *each in [element attributes]) {
		NSString *name = [each name];
		NSRange colon = [name rangeOfString:@":"];
		if (colon.location != NSNotFound && [[name substringFromIndex:NSMaxRange(colon)] isEqualToString:localName]) {
			NSString *prefix = [name substringToIndex:colon.location];
			if ([[[element resolveNamespaceForName:name] stringValue] isEqualToString:namespaceURI]
			    || [[[element namespaceForPrefix:prefix] stringValue] isEqualToString:namespaceURI]) {
				return [each stringValue];
			}
		}
	}
	return nil;
}

static BOOL
WFModelIs(NSXMLElement *element, NSString *namespaceURI, NSString *localName)
{
	return [[element localName] isEqualToString:localName]
	       && ([[element URI] isEqualToString:namespaceURI] || [element URI] == nil);
}

@implementation WFModelForms

/* The imports, location by import type. */
+ (NSArray<NSArray<NSString *> *> *)typedImportsOf:(NSXMLDocument *)document
{
	NSMutableArray *imports = [NSMutableArray array];
	for (NSXMLElement *element in WFModelAll(document)) {
		if (!WFModelIs(element, WFModelBpmnNamespace, @"import")) {
			continue;
		}
		NSString *type = [[element attributeForName:@"importType"] stringValue];
		NSString *location = [[element attributeForName:@"location"] stringValue];
		if ([location length] > 0 && ([type isEqualToString:WFModelFormsORMImportType] || [type isEqualToString:WFModelFormsFlowImportType])) {
			[imports addObject:@[ type, location ]];
		}
	}
	return imports;
}

+ (NSArray<NSString *> *)importsOfProcess:(NSData *)bpmn
{
	NSMutableArray *locations = [NSMutableArray array];
	for (NSArray *import in [self typedImportsOf:WFModelDocument(bpmn)]) {
		[locations addObject:[import lastObject]];
	}
	return locations;
}

/* A model's forms: its queries of the kind Form, by name. */
+ (NSArray<WFModelForm *> *)formsOfModel:(NSData *)data location:(NSString *)location
{
	NSMutableArray *forms = [NSMutableArray array];
	for (NSXMLElement *element in WFModelAll(WFModelDocument(data))) {
		if (!WFModelIs(element, WFModelQueriesNamespace, @"Query")
		    || ![[[element attributeForName:@"Kind"] stringValue] isEqualToString:@"Form"]) {
			continue;
		}
		NSString *name = [[element attributeForName:@"Name"] stringValue];
		if ([name length] == 0) {
			continue;
		}
		WFModelForm *form = [[WFModelForm alloc] init];
		form.formKey = [WFModelFormKeyPrefix stringByAppendingString:name];
		form.title = [NSString stringWithFormat:@"%@ (%@)", name, location];
		form.location = location;
		[forms addObject:form];
	}
	return forms;
}

/* A flow's entries. */
+ (NSArray<WFModelForm *> *)entriesOfFlow:(NSData *)data location:(NSString *)location
{
	NSMutableArray *entries = [NSMutableArray array];
	NSXMLDocument *document = WFModelDocument(data);
	NSString *flowName = [[[document rootElement] attributeForName:@"Name"] stringValue] ?: location;
	for (NSXMLElement *element in WFModelAll(document)) {
		if (!WFModelIs(element, WFModelFormsFlowImportType, @"Entry")) {
			continue;
		}
		NSString *name = [[element attributeForName:@"Name"] stringValue];
		if ([name length] == 0) {
			continue;
		}
		WFModelForm *entry = [[WFModelForm alloc] init];
		entry.formKey = [NSString stringWithFormat:@"%@%@#%@", WFModelFlowKeyPrefix, location, name];
		entry.title = [NSString stringWithFormat:@"%@: %@ (%@)", flowName, name, location];
		entry.location = location;
		entry.flow = YES;
		[entries addObject:entry];
	}
	return entries;
}

+ (NSArray<WFModelForm *> *)formsImportedBy:(NSData *)bpmn resources:(NSDictionary<NSString *, NSData *> *)resources
{
	NSMutableArray *forms = [NSMutableArray array];
	for (NSArray *import in [self typedImportsOf:WFModelDocument(bpmn)]) {
		NSString *location = [import lastObject];
		NSData *data = [resources objectForKey:location];
		if (data == nil) {
			continue;
		}
		if ([[import firstObject] isEqualToString:WFModelFormsORMImportType]) {
			[forms addObjectsFromArray:[self formsOfModel:data location:location]];
		} else {
			[forms addObjectsFromArray:[self entriesOfFlow:data location:location]];
		}
	}
	return forms;
}

static NSError *
WFModelProblem(NSString *elementId, NSString *message)
{
	NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
	if (elementId != nil) {
		[info setObject:elementId forKey:WFErrorElementIdKey];
	}
	return [NSError errorWithDomain:WFErrorDomain code:WFErrorInvalidDefinition userInfo:info];
}

+ (NSArray<NSError *> *)problemsOfProcess:(NSData *)bpmn resources:(NSDictionary<NSString *, NSData *> *)resources
{
	NSMutableArray *problems = [NSMutableArray array];
	NSXMLDocument *document = WFModelDocument(bpmn);
	for (NSArray *import in [self typedImportsOf:document]) {
		if ([resources objectForKey:[import lastObject]] == nil) {
			[problems addObject:WFModelProblem(nil, [NSString stringWithFormat:@"the process imports %@, which is not beside it",
			                                                                   [import lastObject]])];
		}
	}
	NSSet *keys = [NSSet setWithArray:[[self formsImportedBy:bpmn resources:resources] valueForKey:@"formKey"]];
	for (NSXMLElement *element in WFModelAll(document)) {
		NSString *key = WFModelAttribute(element, WFModelCamundaNamespace, @"formKey");
		if (![key hasPrefix:@"ormkit:"] || [keys containsObject:key]) {
			continue;
		}
		NSString *elementId = [[element attributeForName:@"id"] stringValue];
		NSString *what = [key hasPrefix:WFModelFormKeyPrefix] ? @"a form" : [key hasPrefix:WFModelFlowKeyPrefix] ? @"a flow's entry" : nil;
		[problems addObject:WFModelProblem(elementId, what != nil
			? [NSString stringWithFormat:@"%@: %@ is not %@ the process imports", elementId ?: @"a task", key, what]
			: [NSString stringWithFormat:@"%@: %@ is neither ormkit:form: nor ormkit:flow:", elementId ?: @"a task", key])];
	}
	return problems;
}

@end

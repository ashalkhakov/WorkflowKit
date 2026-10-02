#import "WKDDeployment.h"
#import "WKDXML.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

static NSString * const WKDEmbeddedPrefix = @"embedded:deployment:";

NSArray<NSString *> *
WKDEmbeddedForms(NSXMLDocument *document)
{
	NSMutableArray *forms = [NSMutableArray array];
	for (NSXMLElement *element in WKDDescendants([document rootElement], WKDBpmnNamespace, nil)) {
		NSString *key = WKDQualifiedAttribute(document, element, WKDCamundaNamespace, @"formKey");
		if ([key hasPrefix:WKDEmbeddedPrefix]) {
			NSString *name = [key substringFromIndex:[WKDEmbeddedPrefix length]];
			if ([name length] > 0 && ![forms containsObject:name]) {
				[forms addObject:name];
			}
		}
	}
	return forms;
}

NSArray<NSString *> *
WKDDecisionRefs(NSXMLDocument *document)
{
	NSMutableArray *keys = [NSMutableArray array];
	for (NSXMLElement *element in WKDDescendants([document rootElement], WKDBpmnNamespace, @"businessRuleTask")) {
		NSString *key = WKDQualifiedAttribute(document, element, WKDCamundaNamespace, @"decisionRef");
		if ([key length] > 0 && ![key hasPrefix:@"${"] && ![key hasPrefix:@"#{"] && ![key hasPrefix:@"="]
		    && ![keys containsObject:key]) {
			[keys addObject:key];
		}
	}
	return keys;
}

/* The DMN files beside the process, name to text: those open in an
 * editor as they are there. */
static NSDictionary<NSString *, NSString *> *
WKDDecisionFiles(NSURL *directory, NSDictionary<NSString *, NSString *> *edited)
{
	NSMutableDictionary *files = [NSMutableDictionary dictionary];
	NSArray *names = directory != nil
		? [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[directory path] error:NULL] : @[];
	for (NSString *name in names) {
		if ([[name pathExtension] isEqualToString:@"dmn"]) {
			NSString *text = [NSString stringWithContentsOfURL:[directory URLByAppendingPathComponent:name]
			                                          encoding:NSUTF8StringEncoding error:NULL];
			if (text != nil) {
				[files setObject:text forKey:name];
			}
		}
	}
	for (NSString *name in edited) {
		if ([[name pathExtension] isEqualToString:@"dmn"]) {
			[files setObject:[edited objectForKey:name] forKey:name];
		}
	}
	return files;
}

/* The ids of the decisions a DMN file defines. */
static NSArray<NSString *> *
WKDDecisionsIn(NSString *text)
{
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:NULL];
	NSMutableArray *ids = [NSMutableArray array];
	for (NSXMLNode *child in [[document rootElement] children]) {
		if ([child kind] == NSXMLElementKind && [[child localName] isEqualToString:@"decision"]) {
			NSString *decisionId = WKDAttribute((NSXMLElement *)child, @"id");
			if (decisionId != nil) {
				[ids addObject:decisionId];
			}
		}
	}
	return ids;
}

NSString *
WKDDecisionFileDefining(NSString *decisionKey, NSURL *directory, NSDictionary<NSString *, NSString *> *edited)
{
	NSDictionary *files = WKDDecisionFiles(directory, edited);
	for (NSString *name in [[files allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if ([WKDDecisionsIn([files objectForKey:name]) containsObject:decisionKey]) {
			return name;
		}
	}
	return nil;
}

NSDictionary<NSString *, NSString *> *
WKDDeploymentResources(NSXMLDocument *document, NSString *fileName, NSURL *directory,
                       NSDictionary<NSString *, NSString *> *edited, NSArray<NSString *> **missing)
{
	NSMutableDictionary *resources = [NSMutableDictionary dictionary];
	[resources setObject:[document XMLStringWithOptions:NSXMLNodePrettyPrint] forKey:fileName];
	NSMutableArray *absent = [NSMutableArray array];
	for (NSString *form in WKDEmbeddedForms(document)) {
		NSString *text = [edited objectForKey:form];
		text = text != nil ? text : directory != nil
			? [NSString stringWithContentsOfURL:[directory URLByAppendingPathComponent:form]
			                           encoding:NSUTF8StringEncoding error:NULL]
			: nil;
		if (text != nil) {
			[resources setObject:text forKey:form];
		} else {
			[absent addObject:form];
		}
	}
	NSArray *keys = WKDDecisionRefs(document);
	if ([keys count] > 0) {
		NSDictionary *files = WKDDecisionFiles(directory, edited);
		for (NSString *name in files) {
			for (NSString *decisionId in WKDDecisionsIn([files objectForKey:name])) {
				if ([keys containsObject:decisionId]) {
					[resources setObject:[files objectForKey:name] forKey:name];
				}
			}
		}
	}
	if (missing != NULL) {
		*missing = absent;
	}
	return [absent count] == 0 ? resources : nil;
}

NSString *
WKDEmbeddedFormOf(NSXMLDocument *document, NSXMLElement *element)
{
	NSString *key = WKDQualifiedAttribute(document, element, WKDCamundaNamespace, @"formKey");
	NSString *name = [key hasPrefix:WKDEmbeddedPrefix] ? [key substringFromIndex:[WKDEmbeddedPrefix length]] : nil;
	return [name length] > 0 ? name : nil;
}

NSXMLDocument *
WKDGeneratedForm(NSXMLDocument *document, NSString *elementId, NSError **error)
{
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:[document XMLString] error:error];
	if (definition == nil) {
		return nil;
	}
	WFFormDefinition *form = [[definition flowNodeWithId:elementId] form]
		?: [WFFormDefinition formWithKey:nil fields:@[] businessKeyFieldId:nil];
	return [form XFormsDocument];
}


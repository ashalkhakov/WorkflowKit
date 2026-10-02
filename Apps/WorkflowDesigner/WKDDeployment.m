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

NSDictionary<NSString *, NSString *> *
WKDDeploymentResources(NSXMLDocument *document, NSString *fileName, NSURL *directory, NSArray<NSString *> **missing)
{
	NSMutableDictionary *resources = [NSMutableDictionary dictionary];
	[resources setObject:[document XMLStringWithOptions:NSXMLNodePrettyPrint] forKey:fileName];
	NSMutableArray *absent = [NSMutableArray array];
	for (NSString *form in WKDEmbeddedForms(document)) {
		NSString *text = directory != nil
			? [NSString stringWithContentsOfURL:[directory URLByAppendingPathComponent:form]
			                           encoding:NSUTF8StringEncoding error:NULL]
			: nil;
		if (text != nil) {
			[resources setObject:text forKey:form];
		} else {
			[absent addObject:form];
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


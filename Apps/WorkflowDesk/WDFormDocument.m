#import "WDFormDocument.h"

NSString * const WDXFormsNamespace = @"http://www.w3.org/2002/xforms";

static NSError *
WDFormError(NSString *message)
{
	return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static BOOL
WDIsXForms(NSXMLNode *node, NSString *localName)
{
	return [node kind] == NSXMLElementKind && [[node localName] isEqualToString:localName]
		&& [[node URI] isEqualToString:WDXFormsNamespace];
}

/* The first XForms element of the name, in document order. */
static NSXMLElement *
WDFirst(NSXMLNode *node, NSString *localName)
{
	if (WDIsXForms(node, localName)) {
		return (NSXMLElement *)node;
	}
	for (NSXMLNode *child in [node children]) {
		NSXMLElement *found = WDFirst(child, localName);
		if (found != nil) {
			return found;
		}
	}
	return nil;
}

NSString *
WDFormDocumentWithInstance(NSString *document, NSString *instance, NSError **error)
{
	NSError *parseError = nil;
	NSXMLDocument *form = [document length] > 0
		? [[NSXMLDocument alloc] initWithXMLString:document options:0 error:&parseError] : nil;
	if (form == nil) {
		if (error != NULL) {
			*error = WDFormError([NSString stringWithFormat:@"The form is not XML: %@",
				[parseError localizedDescription] ?: @"it is empty"]);
		}
		return nil;
	}
	/* Written as XML: Apple's takes an <html> root for HTML, and writes its
	 * element names in lower case -- the instance's applicationId too,
	 * which its control is then bound to nothing by. */
	[form setDocumentContentKind:NSXMLDocumentXMLKind];
	if ([instance length] == 0) {
		return [form XMLString];
	}
	NSXMLDocument *data = [[NSXMLDocument alloc] initWithXMLString:instance options:0 error:&parseError];
	NSXMLElement *model = WDFirst([form rootElement], @"model");
	NSXMLElement *target = nil;
	for (NSXMLNode *child in [model children]) {
		if (WDIsXForms(child, @"instance")) {
			target = (NSXMLElement *)child;
			break;
		}
	}
	if (data == nil || target == nil) {
		if (error != NULL) {
			*error = WDFormError(data == nil
				? [NSString stringWithFormat:@"The form's instance is not XML: %@", [parseError localizedDescription]]
				: @"The form has no model with an instance to open with.");
		}
		return nil;
	}
	NSXMLElement *root = [data rootElement];
	[root detach];
	/* Instance data in no namespace stays in none under XHTML's default. */
	if ([[root URI] length] == 0 && [root namespaceForPrefix:@""] == nil) {
		[root addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:@""]];
	}
	[target removeAttributeForName:@"src"];
	[target removeAttributeForName:@"resource"];
	[target setChildren:@[ root ]];
	return [form XMLString];
}

#import <Foundation/Foundation.h>

/*
 * What deploying a process sends: the BPMN file under its name, and every
 * form it names as `camunda:formKey="embedded:deployment:<name>"`, read
 * from beside the file -- the engine refuses a deployment without them.
 */

/* The forms the document names, as deployment resources: order.xhtml. */
NSArray<NSString *> *WKDEmbeddedForms(NSXMLDocument *document);

/* The resources, name to text: the process as `fileName`, and its forms --
 * as `edited` has them, the forms open in an editor, else from
 * `directory`. nil, with the forms there are not, when one is missing or
 * there is no directory to look in. */
NSDictionary<NSString *, NSString *> *WKDDeploymentResources(NSXMLDocument *document, NSString *fileName,
                                                             NSURL *directory,
                                                             NSDictionary<NSString *, NSString *> *edited,
                                                             NSArray<NSString *> **missing);

/* The form the element names as camunda:formKey="embedded:deployment:<name>",
 * or nil. */
NSString *WKDEmbeddedFormOf(NSXMLDocument *document, NSXMLElement *element);

/* An XForms document for the element's form, as the engine makes one from
 * its camunda:formData fields -- a model with an instance and a bind per
 * field, a control per field -- for a form designer to start from; an
 * empty form when it has no fields. nil, with an error, when the engine
 * cannot read the process. */
NSXMLDocument *WKDGeneratedForm(NSXMLDocument *document, NSString *elementId, NSError **error);

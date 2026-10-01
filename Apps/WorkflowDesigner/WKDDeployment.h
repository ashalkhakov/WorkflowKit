#import <Foundation/Foundation.h>

/*
 * What deploying a process sends: the BPMN file under its name, and every
 * form it names as `camunda:formKey="embedded:deployment:<name>"`, read
 * from beside the file -- the engine refuses a deployment without them.
 */

/* The forms the document names, as deployment resources: order.xhtml. */
NSArray<NSString *> *WKDEmbeddedForms(NSXMLDocument *document);

/* The resources, name to text: the process as `fileName`, and its forms
 * from `directory`. nil, with the forms there are not, when one is missing
 * or there is no directory to look in. */
NSDictionary<NSString *, NSString *> *WKDDeploymentResources(NSXMLDocument *document, NSString *fileName,
                                                             NSURL *directory, NSArray<NSString *> **missing);

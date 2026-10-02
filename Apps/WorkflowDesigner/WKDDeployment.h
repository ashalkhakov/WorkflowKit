#import <Foundation/Foundation.h>

/*
 * What deploying a process sends: the BPMN file under its name, and every
 * form it names as `camunda:formKey="embedded:deployment:<name>"`, read
 * from beside the file -- the engine refuses a deployment without them --
 * and the DMN files beside it that define the decisions its business rule
 * tasks name, so that a binding to the same deployment finds them.
 */

/* The forms the document names, as deployment resources: order.xhtml. */
NSArray<NSString *> *WKDEmbeddedForms(NSXMLDocument *document);

/* The decisions the document's business rule tasks name by key: not
 * those named by an expression, which are known only as it runs. */
NSArray<NSString *> *WKDDecisionRefs(NSXMLDocument *document);

/* The DMN file beside the process -- in `directory`, or open in an editor
 * as `edited` has it -- that defines the decision; nil when none does. */
NSString *WKDDecisionFileDefining(NSString *decisionKey, NSURL *directory,
                                  NSDictionary<NSString *, NSString *> *edited);

/* The resources, name to text: the process as `fileName`, its forms and
 * the DMN files defining its decisions -- as `edited` has them, the files
 * open in an editor, else from `directory`. nil, with the forms there are
 * not, when one is missing or there is no directory to look in. A
 * decision no file beside defines is not missing: it may have been
 * deployed on its own. */
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

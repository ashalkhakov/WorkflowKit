#import <Foundation/Foundation.h>

/*
 * A form as the server gives it: its XForms document, as deployed or as
 * the engine wrote it for a form of fields, and apart from it the
 * instance the form opens with, the task's own. What the form view runs
 * is the document with that instance in place of its first model's
 * default one.
 */
NSString *WDFormDocumentWithInstance(NSString *document, NSString *instance, NSError **error);

extern NSString * const WDXFormsNamespace;

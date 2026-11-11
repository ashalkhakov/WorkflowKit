#import "WFFormService.h"

/*
 * The handler of a user task done with an object-role model's form
 * (ORMKit's docs/FORMS.md; camunda:formKey="ormkit:form:RecordFillUp"), the
 * engine's for such a key where the task names none: it reads the form's
 * XForms document as ormtool xforms writes it, deployed beside the process
 * as <Form>.xhtml, and nothing of ORMKit.
 *
 *   - The instance the task opens with: the document's (instance "form"),
 *     each element its binds say is given (ormf:role="given", the form's
 *     inputs: the vehicle a fill-up is of) filled from the variable of its
 *     name, its path ("vehicle", "Onboard/catalog") or its last step.
 *     Without a document (a flow's entry, ormkit:flow:, or a form not
 *     deployed), an instance <variables> of the task's own, for the
 *     application to open its view with.
 *   - What a submitted instance sets: each element's text as a variable of
 *     its path ("timestamp", "contact/contactName"), a repeat's rows (its
 *     xf:repeat's, or an element whose name repeats) an array of
 *     dictionaries, each row's elements by theirs.
 */
@interface WFModelFormHandler : NSObject <WFFormHandler>
@end

#import <Foundation/Foundation.h>

#ifndef WORKFLOWKIT_EXPORT
#define WORKFLOWKIT_EXPORT FOUNDATION_EXPORT
#endif

/*
 * The forms and flows of an object-role model (ORMKit's docs/FORMS.md) that
 * a process imports, for its user tasks to be done with: what the designer
 * offers a task, and what the engine checks a task's form key against.
 *
 * A process imports them as BPMN imports any definitions, by their place
 * beside it:
 *
 *   <bpmn:import importType="http://schemas.neumont.edu/ORM/2006-04/ORMRoot" location="Logbook.orm"/>
 *   <bpmn:import importType="http://schemas.ormkit.org/2026-10/Flows" location="Records.flow"/>
 *
 * and a user task names one by its form key: a form by its name, a flow by
 * its file and an entry of it.
 *
 *   camunda:formKey="ormkit:form:RecordFillUp"
 *   camunda:formKey="ormkit:flow:Records.flow#Start"
 *
 * The engine renders neither: the application opens its own view of the
 * form (its screens are the form's views). A form's XForms document, as
 * ormtool xforms writes it (<Form>.xhtml), is deployed with the process
 * where it is beside it; WFModelFormHandler, the engine's handler of such
 * keys, fills the form's inputs (its given elements) from the task's
 * variables, and what is submitted comes back as the variables it sets.
 * The model's files are read as XML: WorkflowKit does not build on ORMKit.
 */

WORKFLOWKIT_EXPORT NSString * const WFModelFormsORMImportType;
WORKFLOWKIT_EXPORT NSString * const WFModelFormsFlowImportType;
/* "ormkit:form:", "ormkit:flow:". */
WORKFLOWKIT_EXPORT NSString * const WFModelFormKeyPrefix;
WORKFLOWKIT_EXPORT NSString * const WFModelFlowKeyPrefix;

/* A form or a flow's entry a task may be done with. */
@interface WFModelForm : NSObject
/* "ormkit:form:RecordFillUp", "ormkit:flow:Records.flow#Start". */
@property (nonatomic, readonly, copy) NSString *formKey;
/* As a person picks it: "RecordFillUp (Logbook.orm)", "Records: Start (Records.flow)". */
@property (nonatomic, readonly, copy) NSString *title;
/* The import it is of. */
@property (nonatomic, readonly, copy) NSString *location;
@property (nonatomic, readonly, getter=isFlow) BOOL flow;
@end

@interface WFModelForms : NSObject
/* The process's imports of models and flows, by location, in its order. */
+ (NSArray<NSString *> *)importsOfProcess:(NSData *)bpmn;
/* The forms and flows' entries of those of them among the resources (by
 * name: the location, as a deployment names what is beside the process),
 * in the imports' order. */
+ (NSArray<WFModelForm *> *)formsImportedBy:(NSData *)bpmn resources:(NSDictionary<NSString *, NSData *> *)resources;
/* What is wrong of the process's model forms: an import not among the
 * resources, a task's model form key naming no form or flow it imports.
 * Each an NSError naming its element (WFErrorElementIdKey), as deploying
 * says it. */
+ (NSArray<NSError *> *)problemsOfProcess:(NSData *)bpmn resources:(NSDictionary<NSString *, NSData *> *)resources;
@end

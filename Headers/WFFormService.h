#import "WFForm.h"

@class WFProcessInstance;

/* What a form handler works on: the form, where it is, and the variables
 * it sees. */
@interface WFFormContext : NSObject
@property (nonatomic, readonly, strong) WFFormDefinition *form;
/* The task's; nil for a start form. */
@property (nonatomic, readonly, copy) NSString *taskId;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *definitionId;
/* The user task's or the start event's id. */
@property (nonatomic, readonly, copy) NSString *activityId;
/* The variables the task sees; none for a start form. */
@property (nonatomic, readonly, copy) NSDictionary *variables;
/* A start form's business key: the one it is submitted with, which the
 * handler may set when the submission gives one. */
@property (nonatomic, copy) NSString *businessKey;
- (instancetype)init NS_UNAVAILABLE;
@end

/*
 * Host code between a form and the process: it gives the XForms instance a
 * form opens with, and decides what a submitted instance does -- which
 * variables it sets -- or refuses it. What it checks, and where a form's
 * richer data goes, is its own; the engine sets the variables it answers
 * as it completes the task or starts the process, in the same command.
 *
 * A form's handler is the one camunda:formHandlerClass names, resolved as
 * a delegate is (registered by name or class, or linked); else, for a
 * form with fields (camunda:formData), the engine's own, which fills
 * <data> with the fields' variables and takes each back checked against
 * its field; else the engine's defaultFormHandler.
 */
@protocol WFFormHandler <NSObject>
/* The instance the form opens with; nil, with an error, to refuse. */
- (NSXMLDocument *)instanceForForm:(WFFormContext *)context error:(NSError **)error;
/* The variables a submitted instance sets; nil, with an error, to refuse
 * it (WFErrorInvalidFormData for what the person has to change). */
- (NSDictionary *)variablesFromInstance:(NSXMLDocument *)instance
                                   form:(WFFormContext *)context
                                  error:(NSError **)error;
@end

/* A form as it stands for one task, or to start a process. */
@interface WFFormData : NSObject
@property (nonatomic, readonly, strong) WFFormContext *context;
@property (nonatomic, readonly, copy) NSString *formKey;
/* The XForms document: generated from the fields, or deployed under the
 * form key; nil for a key the application resolves itself. */
@property (nonatomic, readonly, strong) NSXMLDocument *document;
/* The instance the handler gives; nil without a handler. */
@property (nonatomic, readonly, strong) NSXMLDocument *instance;
- (instancetype)init NS_UNAVAILABLE;
@end

/*
 * Forms: a user task's or a start event's XForms document and the instance
 * it opens with, and a submitted instance handed to the form's handler,
 * whose variables complete the task or start the process.
 */
@interface WFFormService : NSObject

- (instancetype)init NS_UNAVAILABLE;

/* nil, with an error, for a task that is not open or has no form. */
- (WFFormData *)formDataForTask:(NSString *)taskId error:(NSError **)error;
/* The start form of the latest version of the process. */
- (WFFormData *)startFormDataForKey:(NSString *)definitionKey error:(NSError **)error;

/* The handler's variables complete the task. NO, with its error, when it
 * refuses the instance, or with WFErrorHandler when the form has none;
 * nothing changes then. */
- (BOOL)submitTaskForm:(NSString *)taskId instance:(NSXMLDocument *)instance error:(NSError **)error;
/* The handler's variables start the latest version of the process, under
 * the business key given, else the one the handler sets. */
- (WFProcessInstance *)submitStartFormForKey:(NSString *)definitionKey
                                 businessKey:(NSString *)businessKey
                                    instance:(NSXMLDocument *)instance
                                       error:(NSError **)error;

@end

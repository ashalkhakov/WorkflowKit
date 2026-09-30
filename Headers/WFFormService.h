#import "WFForm.h"

@class WFProcessInstance;

/* A form as it stands for one task, or to start a process: what it is,
 * and each field's value to show. */
@interface WFFormData : NSObject
/* nil when the task or start event has no form. */
@property (nonatomic, readonly, strong) WFFormDefinition *form;
@property (nonatomic, readonly, copy) NSString *formKey;
/* The task's; nil for a start form. */
@property (nonatomic, readonly, copy) NSString *taskId;
@property (nonatomic, readonly, copy) NSString *definitionId;
/* By field: the variable where the task sees one, else the field's
 * default value, as the field's type has it; NSNull for neither. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *values;
- (instancetype)init NS_UNAVAILABLE;
@end

/*
 * Forms, as Camunda 7's form service has them: what a user task's or a
 * start event's form is and shows, and its submission -- values checked
 * against the form's fields (-[WFFormDefinition variablesFromValues:...])
 * before they complete the task or start the process.
 */
@interface WFFormService : NSObject

- (instancetype)init NS_UNAVAILABLE;

/* nil, with an error, for a task that is not open. */
- (WFFormData *)formDataForTask:(NSString *)taskId error:(NSError **)error;
/* The start form of the latest version of the process. */
- (WFFormData *)startFormDataForKey:(NSString *)definitionKey error:(NSError **)error;

/* Checks the values against the task's form, and completes the task with
 * the variables they are. NO, with a WFErrorInvalidFormData error, for
 * values the form does not take; nothing changes then. */
- (BOOL)submitTaskForm:(NSString *)taskId values:(NSDictionary *)values error:(NSError **)error;
/* Checks the values against the start form, and starts the latest version
 * of the process with them. The business key is the given one, else the
 * value of the form's business key field. */
- (WFProcessInstance *)submitStartFormForKey:(NSString *)definitionKey
                                 businessKey:(NSString *)businessKey
                                      values:(NSDictionary *)values
                                       error:(NSError **)error;

@end

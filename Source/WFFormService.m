#import "WFFormService.h"
#import "WFProcessEngine+Internal.h"
#import "WFCommandContext.h"
#import "WFEntities.h"
#import "WFFeel.h"
#import "WFFlowElements.h"
#import "WFProcessDefinition.h"
#import "WFRepositoryService.h"
#import "WFRuntimeService.h"
#import "WFTaskService.h"

@interface WFFormContext ()
@property (nonatomic, readwrite, strong) WFFormDefinition *form;
@property (nonatomic, readwrite, copy) NSString *taskId;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSDictionary *variables;
@end

@implementation WFFormContext

- (instancetype)wf_init
{
	return [super init];
}

@end

@implementation WFFormData

+ (instancetype)dataWithContext:(WFFormContext *)context
                       document:(NSXMLDocument *)document
                       instance:(NSXMLDocument *)instance
{
	WFFormData *data = [[self alloc] wf_init];
	data->_context = context;
	data->_formKey = [context.form.formKey copy];
	data->_document = document;
	data->_instance = instance;
	return data;
}

- (instancetype)wf_init
{
	return [super init];
}

@end

/* The engine's handler of a form with fields: <data>, an element per
 * field, filled from the variables (else the fields' defaults), and taken
 * back checked against the fields. */
@interface WFFieldsFormHandler : NSObject <WFFormHandler>
@end

@implementation WFFieldsFormHandler

- (NSXMLDocument *)instanceForForm:(WFFormContext *)context error:(NSError **)error
{
	NSMutableDictionary *values = [NSMutableDictionary dictionary];
	for (WFFormField *field in context.form.fields) {
		id value = [context.variables objectForKey:field.fieldId];
		if (value == nil && field.defaultValue != nil) {
			value = [field.defaultValue valueWithVariables:context.variables ?: @{}];
		}
		if (value != nil) {
			[values setObject:value forKey:field.fieldId];
		}
	}
	return [context.form instanceWithValues:values];
}

- (NSDictionary *)variablesFromInstance:(NSXMLDocument *)instance
                                   form:(WFFormContext *)context
                                  error:(NSError **)error
{
	NSDictionary *variables = [context.form variablesFromValues:[context.form valuesFromInstance:instance]
	                                                       error:error];
	NSString *key = context.form.businessKeyFieldId != nil
		? [variables objectForKey:context.form.businessKeyFieldId] : nil;
	if (context.businessKey == nil && [key isKindOfClass:[NSString class]] && [key length] > 0) {
		context.businessKey = key;
	}
	return variables;
}

@end

@implementation WFFormService
{
	__weak WFProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine
{
	if ((self = [super init])) {
		_engine = engine;
	}
	return self;
}

/* The form's handler; nil, with an error, for a form without one. */
- (id<WFFormHandler>)handlerOf:(WFFormContext *)context error:(NSError **)error
{
	WFFormDefinition *form = context.form;
	if (form.formHandlerName != nil) {
		return [_engine wf_delegateFor:[WFDelegateReference referenceToClass:form.formHandlerName fields:@[]]
		                      protocol:@protocol(WFFormHandler)
		                         error:error];
	}
	if ([form.fields count] > 0) {
		return [[WFFieldsFormHandler alloc] init];
	}
	id<WFFormHandler> handler = _engine.defaultFormHandler;
	if (handler == nil && error != NULL) {
		*error = [NSError errorWithDomain:WFErrorDomain code:WFErrorHandler userInfo:@{ NSLocalizedDescriptionKey:
			[NSString stringWithFormat:@"%@: no form handler takes its form", context.activityId] }];
	}
	return handler;
}

/* The form's document as deployed beside its definition. */
- (NSXMLDocument *)documentOf:(WFFormContext *)context
{
	__block NSString *text = nil;
	[_engine wf_runCommand:_cmd of:self body:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		NSString *formId = [NSString stringWithFormat:@"%@:%@", context.definitionId, context.activityId];
		WFFormRecordEntity *record = [[command fetch:@"WFFormRecord"
		                                   predicate:[NSPredicate predicateWithFormat:@"formId == %@", formId]
		                                        sort:nil limit:1] lastObject];
		text = record.document;
		return YES;
	} error:NULL];
	return text != nil ? [[NSXMLDocument alloc] initWithXMLString:text options:0 error:NULL] : nil;
}

- (NSError *)noForm:(NSString *)where
{
	return [NSError errorWithDomain:WFErrorDomain code:WFErrorUnknownElement
		userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ has no form", where] }];
}

/* The task's form and the variables it sees, in one command. */
- (WFFormContext *)contextOfTask:(NSString *)taskId error:(NSError **)error
{
	__block WFFormContext *context = nil;
	BOOL found = [_engine wf_runCommand:_cmd of:self body:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFTaskEntity *task = [[command fetch:@"WFTask"
		                           predicate:[NSPredicate predicateWithFormat:@"taskId == %@", taskId ?: @""]
		                                sort:nil
		                               limit:1] lastObject];
		if (task == nil || task.execution == nil) {
			if (commandError != NULL) {
				*commandError = [NSError errorWithDomain:WFErrorDomain code:WFErrorUnknownElement
					userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no open task %@", taskId] }];
			}
			return NO;
		}
		WFProcessDefinition *definition = [command definitionForExecution:task.execution];
		WFFormDefinition *form = [[definition nodeWithId:task.taskDefinitionKey] form];
		if (form == nil) {
			if (commandError != NULL) {
				*commandError = [self noForm:[NSString stringWithFormat:@"task %@", taskId]];
			}
			return NO;
		}
		context = [[WFFormContext alloc] wf_init];
		context.form = form;
		context.taskId = taskId;
		context.processInstanceId = task.processInstanceId;
		context.definitionId = task.definitionId;
		context.activityId = task.taskDefinitionKey;
		context.variables = [command visibleVariables:task.execution];
		return YES;
	} error:error];
	return found ? context : nil;
}

- (WFFormContext *)contextOfStartForm:(NSString *)definitionKey error:(NSError **)error
{
	WFProcessDefinition *definition = [_engine.repositoryService latestDefinitionForKey:definitionKey error:error];
	if (definition == nil) {
		return nil;
	}
	WFEvent *start = [definition startEvent];
	if (start.form == nil) {
		if (error != NULL) {
			*error = [self noForm:[NSString stringWithFormat:@"the start of %@", definitionKey]];
		}
		return nil;
	}
	WFFormContext *context = [[WFFormContext alloc] wf_init];
	context.form = start.form;
	context.definitionId = definition.definitionId;
	context.activityId = start.elementId;
	context.variables = @{};
	return context;
}

- (WFFormData *)dataOf:(WFFormContext *)context error:(NSError **)error
{
	NSError *handlerError = nil;
	id<WFFormHandler> handler = [self handlerOf:context error:&handlerError];
	NSXMLDocument *instance = nil;
	if (handler != nil) {
		instance = [handler instanceForForm:context error:error];
		if (instance == nil) {
			return nil;
		}
	}
	return [WFFormData dataWithContext:context document:[self documentOf:context] instance:instance];
}

- (WFFormData *)formDataForTask:(NSString *)taskId error:(NSError **)error
{
	WFFormContext *context = [self contextOfTask:taskId error:error];
	return context != nil ? [self dataOf:context error:error] : nil;
}

- (WFFormData *)startFormDataForKey:(NSString *)definitionKey error:(NSError **)error
{
	WFFormContext *context = [self contextOfStartForm:definitionKey error:error];
	return context != nil ? [self dataOf:context error:error] : nil;
}

- (NSDictionary *)variablesFrom:(NSXMLDocument *)instance context:(WFFormContext *)context error:(NSError **)error
{
	id<WFFormHandler> handler = [self handlerOf:context error:error];
	if (handler == nil) {
		return nil;
	}
	if (instance == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:WFErrorDomain code:WFErrorInvalidFormData
				userInfo:@{ NSLocalizedDescriptionKey: @"no instance submitted" }];
		}
		return nil;
	}
	return [handler variablesFromInstance:instance form:context error:error];
}

- (BOOL)submitTaskForm:(NSString *)taskId instance:(NSXMLDocument *)instance error:(NSError **)error
{
	WFFormContext *context = [self contextOfTask:taskId error:error];
	NSDictionary *variables = context != nil ? [self variablesFrom:instance context:context error:error] : nil;
	if (variables == nil) {
		return NO;
	}
	return [_engine.taskService completeTask:taskId variables:variables error:error];
}

- (WFProcessInstance *)submitStartFormForKey:(NSString *)definitionKey
                                 businessKey:(NSString *)businessKey
                                    instance:(NSXMLDocument *)instance
                                       error:(NSError **)error
{
	WFFormContext *context = [self contextOfStartForm:definitionKey error:error];
	context.businessKey = businessKey;
	NSDictionary *variables = context != nil ? [self variablesFrom:instance context:context error:error] : nil;
	if (variables == nil) {
		return nil;
	}
	return [_engine.runtimeService startProcessInstanceByKey:definitionKey
	                                             businessKey:context.businessKey
	                                               variables:variables
	                                                   error:error];
}

@end

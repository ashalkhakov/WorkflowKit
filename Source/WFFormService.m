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

@implementation WFFormData

+ (instancetype)dataOfForm:(WFFormDefinition *)form
                    taskId:(NSString *)taskId
              definitionId:(NSString *)definitionId
                 variables:(NSDictionary *)variables
{
	WFFormData *data = [[self alloc] wf_init];
	data->_form = form;
	data->_formKey = [form.formKey copy];
	data->_taskId = [taskId copy];
	data->_definitionId = [definitionId copy];
	NSMutableDictionary *values = [NSMutableDictionary dictionary];
	for (WFFormField *field in form.fields) {
		id value = [variables objectForKey:field.fieldId];
		if (value == nil && field.defaultValue != nil) {
			value = [field.defaultValue valueWithVariables:variables];
		}
		[values setObject:[form displayValue:value ofField:field] forKey:field.fieldId];
	}
	data->_values = values;
	return data;
}

- (instancetype)wf_init
{
	return [super init];
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

/* The task's form, and the variables it sees, in one command. */
- (WFFormData *)formDataForTask:(NSString *)taskId error:(NSError **)error
{
	__block WFFormData *data = nil;
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
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
		data = [WFFormData dataOfForm:form taskId:taskId definitionId:task.definitionId
		                    variables:[command visibleVariables:task.execution]];
		return YES;
	} error:error];
	return data;
}

- (WFFormData *)startFormDataForKey:(NSString *)definitionKey error:(NSError **)error
{
	WFProcessDefinition *definition = [_engine.repositoryService latestDefinitionForKey:definitionKey error:error];
	if (definition == nil) {
		return nil;
	}
	return [WFFormData dataOfForm:[[definition startEvent] form] taskId:nil definitionId:definition.definitionId
	                    variables:@{}];
}

- (BOOL)submitTaskForm:(NSString *)taskId values:(NSDictionary *)values error:(NSError **)error
{
	WFFormData *data = [self formDataForTask:taskId error:error];
	if (data == nil) {
		return NO;
	}
	NSDictionary *variables = data.form != nil ? [data.form variablesFromValues:values error:error] : values;
	if (variables == nil) {
		return NO;
	}
	return [_engine.taskService completeTask:taskId variables:variables error:error];
}

- (WFProcessInstance *)submitStartFormForKey:(NSString *)definitionKey
                                 businessKey:(NSString *)businessKey
                                      values:(NSDictionary *)values
                                       error:(NSError **)error
{
	WFFormData *data = [self startFormDataForKey:definitionKey error:error];
	if (data == nil) {
		return nil;
	}
	NSDictionary *variables = data.form != nil ? [data.form variablesFromValues:values error:error] : values;
	if (variables == nil) {
		return nil;
	}
	NSString *fieldKey = data.form.businessKeyFieldId != nil
		? [variables objectForKey:data.form.businessKeyFieldId] : nil;
	if (businessKey == nil && [fieldKey isKindOfClass:[NSString class]]) {
		businessKey = fieldKey;
	}
	return [_engine.runtimeService startProcessInstanceByKey:definitionKey
	                                             businessKey:businessKey
	                                               variables:variables
	                                                   error:error];
}

@end

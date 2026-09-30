#import "WFODataInternal.h"
#import "WFEntities.h"
#import "WFRuntimeService.h"
#import "WFTaskService.h"
#import <ODataKit/ODataError.h>

@protocol WFODataTaskFunctions <ODataFunctions>
/* The XForms instance the task's form opens with, as XML. */
- (NSString *)formInstance:(ODataReply *)reply;
@end

@protocol WFODataTaskActions <ODataActions>
- (void)submitFormWithInstance:(NSString *)instance reply:(ODataReply *)reply;
- (void)completeWithVariables:(NSDictionary *)variables reply:(ODataReply *)reply;
- (void)claimWithUserId:(NSString *)userId reply:(ODataReply *)reply;
- (void)unclaim:(ODataReply *)reply;
/* To nobody, without a user. */
- (void)assignWithUserId:(NSString *)userId reply:(ODataReply *)reply;
@end

@protocol WFODataProcessInstanceActions <ODataActions>
- (void)suspend:(ODataReply *)reply;
- (void)activate:(ODataReply *)reply;
- (void)cancelWithReason:(NSString *)reason reply:(ODataReply *)reply;
- (void)setVariablesWithVariables:(NSDictionary *)variables reply:(ODataReply *)reply;
- (void)removeVariablesWithNames:(NSArray *)names reply:(ODataReply *)reply;
@end

/* Finishes the reply with the engine's answer: nothing, or its error. */
static void
WFODataFinish(ODataReply *reply, BOOL done, NSError *error)
{
	if (done) {
		[reply finishWithResult:nil];
	} else {
		[reply failWithError:WFODataError(error)];
	}
}

NSXMLDocument *
WFODataInstance(NSString *text, ODataReply *reply)
{
	NSError *error = nil;
	NSXMLDocument *instance = [text isKindOfClass:[NSString class]]
		? [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error] : nil;
	if (instance == nil) {
		[reply failWithError:ODataServiceError(400, [NSString stringWithFormat:@"the instance is not XML: %@",
			[error localizedDescription] ?: @"none given"])];
	}
	return instance;
}

/* NSNull, which a JSON null is, as no value. */
static id
WFODataValue(id value)
{
	return value == [NSNull null] ? nil : value;
}

@implementation WFODataOperations

- (instancetype)initWithEngine:(WFProcessEngine *)engine
{
	if ((self = [super init])) {
		_engine = engine;
	}
	return self;
}

+ (WFODataOperations *)operationsOf:(ODataRequest *)request
{
	return request.service.serviceOperations;
}

- (WFExecutionEntity *)startProcessInstanceWithKey:(NSString *)key
                                       businessKey:(NSString *)businessKey
                                         variables:(NSDictionary *)variables
                                             reply:(ODataReply *)reply
{
	NSError *error = nil;
	WFProcessInstance *instance = [_engine.runtimeService startProcessInstanceByKey:key
	                                                                    businessKey:WFODataValue(businessKey)
	                                                                      variables:WFODataValue(variables)
	                                                                          error:&error];
	if (instance == nil) {
		[reply failWithError:WFODataError(error)];
		return nil;
	}
	/* As the request reads it; none when it has ended already. */
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"WFExecution"];
	[fetch setPredicate:[NSPredicate predicateWithFormat:@"executionId == %@", instance.processInstanceId]];
	return [[reply.request.context executeFetchRequest:fetch error:NULL] firstObject];
}

- (void)correlateMessageWithName:(NSString *)name
                     businessKey:(NSString *)businessKey
               processInstanceId:(NSString *)processInstanceId
                       variables:(NSDictionary *)variables
                           reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = WFODataValue(processInstanceId) != nil
		? [_engine.runtimeService correlateMessage:name processInstanceId:processInstanceId
		                                 variables:WFODataValue(variables) error:&error]
		: [_engine.runtimeService correlateMessage:name businessKey:WFODataValue(businessKey) correlationKeys:nil
		                                 variables:WFODataValue(variables) error:&error];
	WFODataFinish(reply, done, error);
}

- (WFExecutionEntity *)submitStartFormWithKey:(NSString *)key
                                  businessKey:(NSString *)businessKey
                                     instance:(NSString *)text
                                        reply:(ODataReply *)reply
{
	NSXMLDocument *document = WFODataInstance(text, reply);
	if (document == nil) {
		return nil;
	}
	NSError *error = nil;
	WFProcessInstance *instance = [_engine.formService submitStartFormForKey:key businessKey:WFODataValue(businessKey)
	                                                                 instance:document
	                                                                    error:&error];
	if (instance == nil) {
		[reply failWithError:WFODataError(error)];
		return nil;
	}
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"WFExecution"];
	[fetch setPredicate:[NSPredicate predicateWithFormat:@"executionId == %@", instance.processInstanceId]];
	return [[reply.request.context executeFetchRequest:fetch error:NULL] firstObject];
}

- (NSString *)startFormInstanceWithKey:(NSString *)key reply:(ODataReply *)reply
{
	NSError *error = nil;
	WFFormData *data = [_engine.formService startFormDataForKey:key error:&error];
	if (data == nil) {
		[reply failWithError:WFODataError(error)];
		return nil;
	}
	return [data.instance XMLString];
}

@end

@interface WFTaskEntity (WFOData) <WFODataTaskActions, WFODataTaskFunctions>
@end

@implementation WFTaskEntity (WFOData)

- (WFTaskService *)wf_taskServiceFor:(ODataReply *)reply
{
	return [WFODataOperations operationsOf:reply.request].engine.taskService;
}

- (NSString *)formInstance:(ODataReply *)reply
{
	NSError *error = nil;
	WFFormData *data = [[WFODataOperations operationsOf:reply.request].engine.formService formDataForTask:self.taskId
	                                                                                                 error:&error];
	if (data == nil) {
		[reply failWithError:WFODataError(error)];
		return nil;
	}
	return [data.instance XMLString];
}

- (void)submitFormWithInstance:(NSString *)text reply:(ODataReply *)reply
{
	NSXMLDocument *instance = WFODataInstance(text, reply);
	if (instance == nil) {
		return;
	}
	NSError *error = nil;
	BOOL done = [[WFODataOperations operationsOf:reply.request].engine.formService submitTaskForm:self.taskId
	                                                                                      instance:instance
	                                                                                         error:&error];
	WFODataFinish(reply, done, error);
}

- (void)completeWithVariables:(NSDictionary *)variables reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_taskServiceFor:reply] completeTask:self.taskId variables:WFODataValue(variables) error:&error];
	WFODataFinish(reply, done, error);
}

- (void)claimWithUserId:(NSString *)userId reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_taskServiceFor:reply] claimTask:self.taskId user:WFODataValue(userId) error:&error];
	WFODataFinish(reply, done, error);
}

- (void)unclaim:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_taskServiceFor:reply] unclaimTask:self.taskId error:&error];
	WFODataFinish(reply, done, error);
}

- (void)assignWithUserId:(NSString *)userId reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_taskServiceFor:reply] setAssignee:WFODataValue(userId) forTask:self.taskId error:&error];
	WFODataFinish(reply, done, error);
}

@end

@interface WFExecutionEntity (WFOData) <WFODataProcessInstanceActions>
@end

@implementation WFExecutionEntity (WFOData)

+ (NSDictionary *)ODataOperationTypes
{
	return @{ @"removeVariablesWithNames:reply:.names": @"Collection(Edm.String)" };
}

- (WFRuntimeService *)wf_runtimeServiceFor:(ODataReply *)reply
{
	return [WFODataOperations operationsOf:reply.request].engine.runtimeService;
}

- (void)suspend:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_runtimeServiceFor:reply] suspendProcessInstance:self.executionId error:&error];
	WFODataFinish(reply, done, error);
}

- (void)activate:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_runtimeServiceFor:reply] activateProcessInstance:self.executionId error:&error];
	WFODataFinish(reply, done, error);
}

- (void)cancelWithReason:(NSString *)reason reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_runtimeServiceFor:reply] deleteProcessInstance:self.executionId
	                                                              reason:WFODataValue(reason) error:&error];
	WFODataFinish(reply, done, error);
}

- (void)setVariablesWithVariables:(NSDictionary *)variables reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_runtimeServiceFor:reply] setVariables:WFODataValue(variables) ?: @{}
	                                         processInstanceId:self.executionId error:&error];
	WFODataFinish(reply, done, error);
}

- (void)removeVariablesWithNames:(NSArray *)names reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_runtimeServiceFor:reply] removeVariables:WFODataValue(names) ?: @[]
	                                            processInstanceId:self.executionId error:&error];
	WFODataFinish(reply, done, error);
}

@end

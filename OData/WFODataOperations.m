#import "WFODataInternal.h"
#import "WFEntities.h"
#import "WFRuntimeService.h"
#import "WFTaskService.h"
#import <ODataKit/ODataError.h>

@protocol WFODataTaskActions <ODataActions>
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

@end

@interface WFTaskEntity (WFOData) <WFODataTaskActions>
@end

@implementation WFTaskEntity (WFOData)

- (WFTaskService *)wf_taskServiceFor:(ODataReply *)reply
{
	return [WFODataOperations operationsOf:reply.request].engine.taskService;
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

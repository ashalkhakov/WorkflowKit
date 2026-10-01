#import "WFODataInternal.h"
#import "WFEntities.h"
#import "WFRuntimeService.h"
#import "WFTaskService.h"
#import "WFManagementService.h"
#import "WFRepositoryService.h"
#import "WFIdentity.h"
#import "WFProcessDefinition.h"
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

@protocol WFODataProcessInstanceFunctions <ODataFunctions>
/* The activities it is in now, each once. */
- (NSArray *)activeActivities:(ODataReply *)reply;
@end

@protocol WFODataJobActions <ODataActions>
/* Runs it now, whatever its due date; a failure counts as an attempt. */
- (void)execute:(ODataReply *)reply;
/* Gives a failed job attempts again, which resolves its incident. */
- (void)setRetriesWithRetries:(int32_t)retries reply:(ODataReply *)reply;
@end

@protocol WFODataDefinitionActions <ODataActions>
- (void)suspendWithIncludeInstances:(BOOL)includeInstances reply:(ODataReply *)reply;
- (void)activateWithIncludeInstances:(BOOL)includeInstances reply:(ODataReply *)reply;
@end

@protocol WFODataDefinitionFunctions <ODataFunctions>
/* The BPMN it was deployed from, as text: what a client draws. */
- (NSString *)bpmn:(ODataReply *)reply;
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

/* Answers 403 and NO when the caller may not start the process. */
static BOOL
WFODataMayStart(WFProcessEngine *engine, NSString *key, ODataReply *reply)
{
	WFIdentity *identity = WFODataIdentity(reply.request);
	if (identity == nil || WFODataHasScope(reply.request, WFODataScopeStartAny)) {
		return YES;
	}
	WFProcessDefinition *definition = [engine.repositoryService latestDefinitionForKey:key error:NULL];
	if (definition == nil || [definition isStartableBy:identity]) {
		return YES;  /* an unknown key is answered as the engine answers it */
	}
	[reply failWithError:ODataServiceError(403, [NSString stringWithFormat:@"%@ may not start %@", identity.userId, key])];
	return NO;
}

/* Answers 403 and NO unless the caller acts for themselves, or may act
 * for anyone. */
static BOOL
WFODataForThemselves(NSString *userId, ODataReply *reply)
{
	WFIdentity *identity = WFODataIdentity(reply.request);
	if (identity == nil || [userId isEqualToString:identity.userId]
	    || WFODataHasScope(reply.request, WFODataScopeAssignTasks)) {
		return YES;
	}
	[reply failWithError:ODataServiceError(403, [NSString stringWithFormat:@"%@ may assign tasks to themselves only",
		identity.userId])];
	return NO;
}

/* NSNull, which a JSON null is, as no value. */
static id
WFODataValue(id value)
{
	return value == [NSNull null] ? nil : value;
}

@implementation WFODataOperations

+ (NSDictionary *)ODataOperationScopes
{
	NSArray *start = @[ WFODataScopeWork, WFODataScopeStartAny ];
	return @{ @"startProcessInstanceWithKey:businessKey:variables:reply:": start,
	          @"submitStartFormWithKey:businessKey:instance:reply:": start,
	          @"startFormInstanceWithKey:reply:": start,
	          @"correlateMessageWithName:businessKey:processInstanceId:variables:reply:": @[ WFODataScopeOperationsManage ],
	          @"deployWithName:resources:reply:": @[ WFODataScopeDeploy ] };
}

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
	if (!WFODataMayStart(_engine, key, reply)) {
		return nil;
	}
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

- (NSString *)deployWithName:(NSString *)name resources:(NSDictionary *)resources reply:(ODataReply *)reply
{
	/* Text resources -- BPMN, DMN, XForms -- by name. */
	NSMutableDictionary *bytes = [NSMutableDictionary dictionary];
	for (NSString *resource in WFODataValue(resources)) {
		id text = [resources objectForKey:resource];
		if (![text isKindOfClass:[NSString class]]) {
			[reply failWithError:ODataServiceError(400, [NSString stringWithFormat:@"%@ is not text", resource])];
			return nil;
		}
		[bytes setObject:[text dataUsingEncoding:NSUTF8StringEncoding] forKey:resource];
	}
	NSError *error = nil;
	WFDeployment *deployment = [_engine.repositoryService deployResources:bytes name:WFODataValue(name) ?: @"deployment"
	                                                     filterDuplicates:YES error:&error];
	if (deployment == nil) {
		[reply failWithError:WFODataError(error)];
		return nil;
	}
	return deployment.deploymentId;
}

- (WFExecutionEntity *)submitStartFormWithKey:(NSString *)key
                                  businessKey:(NSString *)businessKey
                                     instance:(NSString *)text
                                        reply:(ODataReply *)reply
{
	NSXMLDocument *document = WFODataInstance(text, reply);
	if (document == nil || !WFODataMayStart(_engine, key, reply)) {
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

+ (NSDictionary *)ODataOperationScopes
{
	NSArray *work = @[ WFODataScopeWork, WFODataScopeAssignTasks ];
	return @{ @"formInstance:": work, @"submitFormWithInstance:reply:": work,
	          @"completeWithVariables:reply:": work, @"claimWithUserId:reply:": work,
	          @"unclaim:": work, @"assignWithUserId:reply:": work };
}

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
	/* For the caller, unless named. */
	NSString *user = WFODataValue(userId) ?: WFODataIdentity(reply.request).userId;
	if (!WFODataForThemselves(user, reply)) {
		return;
	}
	NSError *error = nil;
	BOOL done = [[self wf_taskServiceFor:reply] claimTask:self.taskId user:user error:&error];
	WFODataFinish(reply, done, error);
}

- (void)unclaim:(ODataReply *)reply
{
	if (self.assignee != nil && !WFODataForThemselves(self.assignee, reply)) {
		return;
	}
	NSError *error = nil;
	BOOL done = [[self wf_taskServiceFor:reply] unclaimTask:self.taskId error:&error];
	WFODataFinish(reply, done, error);
}

- (void)assignWithUserId:(NSString *)userId reply:(ODataReply *)reply
{
	if (!WFODataForThemselves(WFODataValue(userId), reply)) {
		return;
	}
	NSError *error = nil;
	BOOL done = [[self wf_taskServiceFor:reply] setAssignee:WFODataValue(userId) forTask:self.taskId error:&error];
	WFODataFinish(reply, done, error);
}

@end

@interface WFExecutionEntity (WFOData) <WFODataProcessInstanceActions, WFODataProcessInstanceFunctions>
@end

@implementation WFExecutionEntity (WFOData)

+ (NSDictionary *)ODataOperationTypes
{
	return @{ @"removeVariablesWithNames:reply:.names": @"Collection(Edm.String)",
	          @"activeActivities:": @"Collection(Edm.String)" };
}

+ (NSDictionary *)ODataOperationScopes
{
	NSArray *manage = @[ WFODataScopeOperationsManage ];
	return @{ @"suspend:": manage, @"activate:": manage, @"cancelWithReason:reply:": manage,
	          @"setVariablesWithVariables:reply:": manage, @"removeVariablesWithNames:reply:": manage,
	          @"activeActivities:": @[ WFODataScopeOperationsRead ] };
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

@implementation WFExecutionEntity (WFODataFunctions)

- (NSArray *)activeActivities:(ODataReply *)reply
{
	NSError *error = nil;
	NSArray *active = [[self wf_runtimeServiceFor:reply] activeActivityIdsForProcessInstance:self.executionId error:&error];
	if (active == nil) {
		[reply failWithError:WFODataError(error)];
		return nil;
	}
	return [[NSOrderedSet orderedSetWithArray:active] array];
}

@end

@interface WFJobEntity (WFOData) <WFODataJobActions>
@end

@implementation WFJobEntity (WFOData)

+ (NSDictionary *)ODataOperationScopes
{
	return @{ @"execute:": @[ WFODataScopeOperationsManage ], @"setRetriesWithRetries:reply:": @[ WFODataScopeOperationsManage ] };
}

- (WFManagementService *)wf_managementServiceFor:(ODataReply *)reply
{
	return [WFODataOperations operationsOf:reply.request].engine.managementService;
}

- (void)execute:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_managementServiceFor:reply] executeJob:self.jobId error:&error];
	WFODataFinish(reply, done, error);
}

- (void)setRetriesWithRetries:(int32_t)retries reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_managementServiceFor:reply] setRetries:retries forJob:self.jobId error:&error];
	WFODataFinish(reply, done, error);
}

@end

@interface WFDefinitionRecordEntity (WFOData) <WFODataDefinitionActions, WFODataDefinitionFunctions>
@end

@implementation WFDefinitionRecordEntity (WFOData)

+ (NSDictionary *)ODataOperationScopes
{
	NSArray *manage = @[ WFODataScopeOperationsManage ];
	return @{ @"suspendWithIncludeInstances:reply:": manage, @"activateWithIncludeInstances:reply:": manage,
	          @"bpmn:": @[ WFODataScopeOperationsRead, WFODataScopeWork ] };
}

- (WFRepositoryService *)wf_repositoryServiceFor:(ODataReply *)reply
{
	return [WFODataOperations operationsOf:reply.request].engine.repositoryService;
}

- (void)suspendWithIncludeInstances:(BOOL)includeInstances reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_repositoryServiceFor:reply] suspendDefinition:self.definitionId
	                                                    includeInstances:includeInstances error:&error];
	WFODataFinish(reply, done, error);
}

- (void)activateWithIncludeInstances:(BOOL)includeInstances reply:(ODataReply *)reply
{
	NSError *error = nil;
	BOOL done = [[self wf_repositoryServiceFor:reply] activateDefinition:self.definitionId
	                                                     includeInstances:includeInstances error:&error];
	WFODataFinish(reply, done, error);
}

- (NSString *)bpmn:(ODataReply *)reply
{
	for (WFResourceEntity *resource in self.deployment.resources) {
		if ([resource.name isEqualToString:self.resourceName]) {
			return [[NSString alloc] initWithData:resource.bytes encoding:NSUTF8StringEncoding];
		}
	}
	[reply failWithError:ODataServiceError(404, [NSString stringWithFormat:@"%@ is not deployed", self.resourceName])];
	return nil;
}

@end

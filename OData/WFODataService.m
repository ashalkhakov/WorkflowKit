#import "WFODataInternal.h"
#import "WFStore.h"
#import "WFEntities.h"
#import "WFIdentity+Internal.h"
#import "WFTaskQuery+Internal.h"

NSString * const WFODataScopeReadAllTasks = @"Tasks.ReadAll";
NSString * const WFODataScopeAssignTasks = @"Tasks.Assign";
NSString * const WFODataScopeReadAllDefinitions = @"ProcessDefinitions.ReadAll";
NSString * const WFODataScopeStartAny = @"ProcessInstances.StartAny";

/* What a principal may do: OAuth's scope claim (text) or scp (a list). */
static NSSet *
WFODataScopes(ODataPrincipal *principal)
{
	id scope = [principal.claims objectForKey:@"scope"] ?: [principal.claims objectForKey:@"scp"];
	if ([scope isKindOfClass:[NSString class]]) {
		return [NSSet setWithArray:[scope componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	}
	return [scope isKindOfClass:[NSArray class]] ? [NSSet setWithArray:scope] : [NSSet set];
}

BOOL
WFODataHasScope(ODataRequest *request, NSString *scope)
{
	return request.principal == nil || [WFODataScopes(request.principal) containsObject:scope];
}

WFIdentity *
WFODataIdentity(ODataRequest *request)
{
	ODataPrincipal *principal = request.principal;
	if (principal == nil) {
		return nil;
	}
	id groups = [principal.claims objectForKey:[WFODataOperations operationsOf:request].groupsClaim ?: @"groups"];
	if ([groups isKindOfClass:[NSString class]]) {
		groups = [groups componentsSeparatedByString:@","];
	}
	NSMutableArray *names = [NSMutableArray array];
	for (id group in [groups isKindOfClass:[NSArray class]] ? groups : @[]) {
		NSString *name = [[group description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([name length] > 0) {
			[names addObject:name];
		}
	}
	return [WFIdentity identityWithUserId:principal.subject groups:names claims:principal.claims];
}
#import <ODataKit/ODataError.h>

NSError *
WFODataError(NSError *error)
{
	NSString *message = [error localizedDescription] ?: @"The engine failed";
	if (![[error domain] isEqualToString:WFErrorDomain]) {
		return ODataServiceError(500, message);
	}
	switch ((WFErrorCode)[error code]) {
	case WFErrorUnknownElement:
		return ODataServiceError(404, message);
	case WFErrorHandler:
		/* Host code that is not there: the server's to fix. */
		return ODataServiceError(500, message);
	case WFErrorInvalidState:
	case WFErrorSuspended:
	case WFErrorConflict:
		return ODataServiceError(409, message);
	default:
		return ODataServiceError(400, message);
	}
}

/* key == nil, key != nil. */
static NSPredicate *
WFODataIsNil(NSString *key, BOOL isNil)
{
	return [NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:key]
	                                          rightExpression:[NSExpression expressionForConstantValue:nil]
	                                                 modifier:NSDirectPredicateModifier
	                                                     type:isNil ? NSEqualToPredicateOperatorType
	                                                                : NSNotEqualToPredicateOperatorType
	                                                  options:0];
}

/* What the engine keeps: read here, changed through its actions alone. */
@interface WFODataHandler : ODataEntitySetHandler
@end

@implementation WFODataHandler

- (instancetype)initWithEntity:(NSEntityDescription *)entity
{
	if ((self = [super initWithEntity:entity])) {
		self.allowsInsert = NO;
		self.allowsUpdate = NO;
		self.allowsDelete = NO;
	}
	return self;
}

@end

/* Rows the handler shows where the condition holds. */
@interface WFODataFilteredHandler : WFODataHandler
@property (nonatomic, strong) NSPredicate *visible;
@end

@implementation WFODataFilteredHandler

- (NSPredicate *)predicateForVisibleObjectsInRequest:(ODataRequest *)request
{
	return self.visible;
}

@end

/* Tasks: the caller's, or offered to them. */
@interface WFODataTasksHandler : WFODataHandler
@end

@implementation WFODataTasksHandler

- (NSPredicate *)predicateForVisibleObjectsInRequest:(ODataRequest *)request
{
	WFIdentity *identity = WFODataIdentity(request);
	if (identity == nil || WFODataHasScope(request, WFODataScopeReadAllTasks)) {
		return nil;
	}
	return [[[WFTaskQuery query] visibleTo:identity] wf_predicateWithDefinitionIds:nil error:NULL];
}

@end

/* Process definitions: those the caller may start. */
@interface WFODataDefinitionsHandler : WFODataHandler
@end

@implementation WFODataDefinitionsHandler

- (NSPredicate *)predicateForVisibleObjectsInRequest:(ODataRequest *)request
{
	WFIdentity *identity = WFODataIdentity(request);
	if (identity == nil || WFODataHasScope(request, WFODataScopeReadAllDefinitions)) {
		return nil;
	}
	NSPredicate *anyone = [NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"starterLinks.@count"]
	                                                         rightExpression:[NSExpression expressionForConstantValue:@0]
	                                                                modifier:NSDirectPredicateModifier
	                                                                    type:NSEqualToPredicateOperatorType
	                                                                 options:0];
	return [NSCompoundPredicate orPredicateWithSubpredicates:@[
		anyone, WFLinksMatch(@"starterLinks", WFIdentityLinkStarter, identity) ]];
}

@end

@implementation WFODataService

+ (ODataService *)serviceForEngine:(WFProcessEngine *)engine serviceRoot:(NSURL *)serviceRoot
{
	return [self serviceForEngine:engine serviceRoot:serviceRoot groupsClaim:@"groups"];
}

+ (ODataService *)serviceForEngine:(WFProcessEngine *)engine
                       serviceRoot:(NSURL *)serviceRoot
                       groupsClaim:(NSString *)groupsClaim
{
	ODataService *service = [[ODataService alloc] initWithPersistentStoreCoordinator:engine.store.coordinator
	                                                                      serviceRoot:serviceRoot];
	service.namespaceName = @"WorkflowKit";
	service.configurationName = @"API";
	WFODataOperations *operations = [[WFODataOperations alloc] initWithEngine:engine];
	operations.groupsClaim = groupsClaim;
	service.serviceOperations = operations;
	NSDictionary *entities = [service.model entitiesByName];
	[service setHandler:[[WFODataTasksHandler alloc] initWithEntity:[entities objectForKey:@"WFTask"]]
	       forEntitySet:@"Tasks"];
	[service setHandler:[[WFODataDefinitionsHandler alloc] initWithEntity:[entities objectForKey:@"WFDefinitionRecord"]]
	       forEntitySet:@"ProcessDefinitions"];
	NSDictionary *sets = @{ @"Forms": @"WFFormRecord",
	                        @"Deployments": @"WFDeployment",
	                        @"Resources": @"WFResource",
	                        @"DecisionDefinitions": @"WFDecisionRecord",
	                        @"Jobs": @"WFJob",
	                        @"Incidents": @"WFIncident",
	                        @"ExternalTasks": @"WFExternalTask",
	                        @"HistoricActivityInstances": @"WFHistoricActivityInstance",
	                        @"HistoricVariableUpdates": @"WFHistoricVariableUpdate",
	                        @"HistoricIncidents": @"WFHistoricIncident",
	                        @"HistoricJobLogs": @"WFHistoricJobLog",
	                        @"HistoricDecisionInstances": @"WFHistoricDecisionInstance",
	                        @"HistoricProcessInstances": @"WFHistoricProcessInstance",
	                        @"HistoricTaskInstances": @"WFHistoricTaskInstance" };
	for (NSString *set in sets) {
		[service setHandler:[[WFODataHandler alloc] initWithEntity:[entities objectForKey:[sets objectForKey:set]]]
		       forEntitySet:set];
	}
	/* A process instance is the root of its execution tree, and its
	 * variables are the root's own, not a scope's inside it. */
	WFODataFilteredHandler *instances =
		[[WFODataFilteredHandler alloc] initWithEntity:[entities objectForKey:@"WFExecution"]];
	instances.visible = WFODataIsNil(@"parent", YES);
	[service setHandler:instances forEntitySet:@"ProcessInstances"];
	WFODataFilteredHandler *variables =
		[[WFODataFilteredHandler alloc] initWithEntity:[entities objectForKey:@"WFVariable"]];
	variables.visible = [NSCompoundPredicate andPredicateWithSubpredicates:@[
		WFODataIsNil(@"execution", NO), WFODataIsNil(@"execution.parent", YES) ]];
	[service setHandler:variables forEntitySet:@"Variables"];
	return service;
}

@end

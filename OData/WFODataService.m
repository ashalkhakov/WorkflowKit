#import "WFODataInternal.h"
#import "WFStore.h"
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

@implementation WFODataService

+ (ODataService *)serviceForEngine:(WFProcessEngine *)engine serviceRoot:(NSURL *)serviceRoot
{
	ODataService *service = [[ODataService alloc] initWithPersistentStoreCoordinator:engine.store.coordinator
	                                                                      serviceRoot:serviceRoot];
	service.namespaceName = @"WorkflowKit";
	service.configurationName = @"API";
	service.serviceOperations = [[WFODataOperations alloc] initWithEngine:engine];
	NSDictionary *entities = [service.model entitiesByName];
	NSDictionary *sets = @{ @"Tasks": @"WFTask",
	                        @"ProcessDefinitions": @"WFDefinitionRecord",
	                        @"Forms": @"WFFormRecord",
	                        @"FormFields": @"WFFormFieldRecord",
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

#import "WFODataService.h"
#import "WFProcessEngine.h"

@class WFExecutionEntity;

@protocol WFODataServiceActions <ODataActions>
- (WFExecutionEntity *)startProcessInstanceWithKey:(NSString *)key
                                       businessKey:(NSString *)businessKey
                                         variables:(NSDictionary *)variables
                                             reply:(ODataReply *)reply;
- (void)correlateMessageWithName:(NSString *)name
                     businessKey:(NSString *)businessKey
               processInstanceId:(NSString *)processInstanceId
                       variables:(NSDictionary *)variables
                           reply:(ODataReply *)reply;
/* The deployment's id. */
- (NSString *)deployWithName:(NSString *)name resources:(NSDictionary *)resources reply:(ODataReply *)reply;
- (WFExecutionEntity *)submitStartFormWithKey:(NSString *)key
                                  businessKey:(NSString *)businessKey
                                     instance:(NSString *)instance
                                        reply:(ODataReply *)reply;
/* The external tasks locked for the worker, as JSON objects. */
- (NSArray *)fetchAndLockWithWorkerId:(NSString *)workerId
                             maxTasks:(int32_t)maxTasks
                               topics:(NSDictionary *)topics
                                reply:(ODataReply *)reply;
@end

@protocol WFODataServiceFunctions <ODataFunctions>
- (NSString *)startFormInstanceWithKey:(NSString *)key reply:(ODataReply *)reply;
@end

/* XML text a request carries, as a document; nil, answered 400, when it is
 * not one. */
NSXMLDocument *WFODataInstance(NSString *text, ODataReply *reply);

/* The service's unbound operations, and the engine every operation and
 * handler of the service works through. */
@interface WFODataOperations : NSObject <WFODataServiceActions, WFODataServiceFunctions>
@property (nonatomic, readonly, strong) WFProcessEngine *engine;
/* The claim a principal's groups are in. */
@property (nonatomic, copy) NSString *groupsClaim;
- (instancetype)initWithEngine:(WFProcessEngine *)engine;
/* The operations of the service a request came to. */
+ (WFODataOperations *)operationsOf:(ODataRequest *)request;
@end

@class WFIdentity;

/* Who is asking, as the engine matches people; nil for no one. */
WFIdentity *WFODataIdentity(ODataRequest *request);
/* Whether the request's principal has the scope; YES with no principal,
 * whom nothing limits. */
BOOL WFODataHasScope(ODataRequest *request, NSString *scope);

/* An engine error as the OData error it is answered with. */
NSError *WFODataError(NSError *error);

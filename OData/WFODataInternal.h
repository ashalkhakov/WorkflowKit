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
@end

/* The service's unbound operations, and the engine every operation and
 * handler of the service works through. */
@interface WFODataOperations : NSObject <WFODataServiceActions>
@property (nonatomic, readonly, strong) WFProcessEngine *engine;
- (instancetype)initWithEngine:(WFProcessEngine *)engine;
/* The operations of the service a request came to. */
+ (WFODataOperations *)operationsOf:(ODataRequest *)request;
@end

/* An engine error as the OData error it is answered with. */
NSError *WFODataError(NSError *error);

#import "WFDecision.h"

@class WFProcessEngine;

/*
 * Decisions evaluated on their own, outside any process. Each call is one
 * command; at history level full the evaluation is recorded, as a
 * business rule task's is.
 */
@interface WFDecisionService : NSObject

- (instancetype)init NS_UNAVAILABLE;

/* The latest version of the decision with that key. */
- (WFDecisionResult *)evaluateDecisionByKey:(NSString *)key
                                  variables:(NSDictionary *)variables
                                      error:(NSError **)error;
/* version 0 means the latest. */
- (WFDecisionResult *)evaluateDecisionByKey:(NSString *)key
                                    version:(NSInteger)version
                                  variables:(NSDictionary *)variables
                                      error:(NSError **)error;
- (WFDecisionResult *)evaluateDecisionById:(NSString *)definitionId
                                 variables:(NSDictionary *)variables
                                     error:(NSError **)error;

@end

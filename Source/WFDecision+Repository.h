#import "WFDecision.h"

/* For the repository only: a decision as deployed, stamped with the
 * version and ids the deployment gave it. */
@interface WFDecisionDefinition (WFRepository)
- (WFDecisionDefinition *)wf_deployedCopyWithVersion:(NSInteger)version
                                        definitionId:(NSString *)definitionId
                                        deploymentId:(NSString *)deploymentId
                                        resourceName:(NSString *)resourceName;
@end

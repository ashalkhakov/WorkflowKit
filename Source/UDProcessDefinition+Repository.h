#import "UDProcessDefinition.h"

/* For the repository only: a definition as deployed, stamped with the
 * version and ids the deployment gave it. */
@interface UDProcessDefinition (UDRepository)
- (UDProcessDefinition *)ud_deployedCopyWithVersion:(NSInteger)version
                                        definitionId:(NSString *)definitionId
                                        deploymentId:(NSString *)deploymentId
                                        resourceName:(NSString *)resourceName;
@end

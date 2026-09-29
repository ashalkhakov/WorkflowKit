#import "WFProcessDefinition.h"

@class WFStore;

/* A deployment as stored, with the definitions it holds. */
@interface WFDeployment : NSObject
@property (nonatomic, readonly, copy) NSString *deploymentId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSDate *deployedAt;
@property (nonatomic, readonly, copy) NSArray<WFProcessDefinition *> *definitions;
@end

/*
 * Deployments and process definitions.
 *
 * A deployment is a named set of resources. Every resource whose name ends
 * in .bpmn or .bpmn20.xml is parsed, and each executable process in it
 * becomes a definition, versioned per process key by the repository: the
 * first deployment of a key is version 1, and every later one the next.
 * Instances run on the version they started on.
 *
 * Definitions are read back from the stored BPMN when first needed, so an
 * engine opened on an existing store needs nothing deployed again.
 */
@interface WFRepositoryService : NSObject

- (instancetype)initWithStore:(WFStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/* With filterDuplicates, a deployment whose resources are byte for byte
 * those of the latest deployment of the same name is not stored again:
 * that deployment is answered instead. */
- (WFDeployment *)deployResources:(NSDictionary<NSString *, NSData *> *)resources
                             name:(NSString *)name
                 filterDuplicates:(BOOL)filterDuplicates
                            error:(NSError **)error;

/* Writes the definition as BPMN and deploys that, as <key>.bpmn in a
 * deployment named after the key, filtering duplicates. What runs is what
 * was stored: the deployment's definitions are read from the BPMN. */
- (WFDeployment *)deployDefinition:(WFProcessDefinition *)definition
                             error:(NSError **)error;

- (WFDeployment *)deploymentWithId:(NSString *)deploymentId error:(NSError **)error;
- (WFProcessDefinition *)latestDefinitionForKey:(NSString *)key error:(NSError **)error;
- (WFProcessDefinition *)definitionForKey:(NSString *)key
                                  version:(NSInteger)version
                                    error:(NSError **)error;
- (WFProcessDefinition *)definitionWithId:(NSString *)definitionId error:(NSError **)error;

@end

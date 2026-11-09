#import "WFRepositoryService.h"
#import "WFProcessEngine.h"
#import "WFDeploymentChecker.h"

/*
 * Processes as an application ships them, built as its other resources
 * are: a deployment's directory -- its BPMN files, the decisions (.dmn)
 * and the forms (.xhtml) they use -- checked and written by wf-build into
 * <name>.wfdeployment, which the application carries in its resources
 * and deploys when it opens its engine, as momc's .momd is its model.
 *
 * A .wfdeployment is a directory: Deployment.plist, which says what it
 * is -- its name, its resources, the processes and decisions in them, the
 * WorkflowKit that built it -- and Resources/, the files as they were
 * checked, by their paths in the deployment.
 */

WORKFLOWKIT_EXPORT NSString * const WFBuiltDeploymentExtension;

@interface WFBuiltDeployment : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSData *> *resources;
/* The keys of the processes and the decisions it deploys. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *processKeys;
@property (nonatomic, readonly, copy) NSArray<NSString *> *decisionKeys;

/* A deployment's directory as resources: every file under it by its path
 * there, hidden ones aside -- what wf-serve deploys of a directory. */
+ (NSDictionary<NSString *, NSData *> *)resourcesInDirectory:(NSURL *)directory error:(NSError **)error;

/* The resources checked as deploying them would be: nil, with every
 * problem found, when it would be refused. */
+ (instancetype)deploymentNamed:(NSString *)name
                      resources:(NSDictionary<NSString *, NSData *> *)resources
                       problems:(NSArray<WFProblem *> **)problems;

/* A .wfdeployment, as wf-build wrote it. */
+ (instancetype)deploymentWithContentsOfURL:(NSURL *)url error:(NSError **)error;
/* Written as a .wfdeployment, in place of what is at the URL. */
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;

@end

@interface WFRepositoryService (WFBuiltDeployments)
/* Deployed under its name, unless the latest deployment of that name is
 * the same byte for byte: what an application does at every launch. */
- (WFDeployment *)deployBuiltDeployment:(WFBuiltDeployment *)deployment error:(NSError **)error;
/* Every .wfdeployment in the bundle's resources, in name order. */
- (NSArray<WFDeployment *> *)deployBuiltDeploymentsInBundle:(NSBundle *)bundle error:(NSError **)error;
@end

@interface WFProcessEngine (WFTesting)
/* An engine for an application's tests: on a store in memory, with full
 * history, its job executor stopped (a test runs jobs itself), opened, the
 * bundle's built deployments deployed -- the processes the application
 * ships, as it ships them. */
+ (instancetype)testEngineWithDeploymentsInBundle:(NSBundle *)bundle error:(NSError **)error;
@end

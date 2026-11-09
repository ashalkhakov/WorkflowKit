#import <XCTest/XCTest.h>
#import "WorkflowKit.h"

/* Processes as an application ships them: built by wf-build into its
 * resources (this bundle's: two of the example processes), deployed when
 * it opens its engine, and again, to no effect, at every launch after. */
@interface WFBuiltDeploymentTests : XCTestCase
@end

@implementation WFBuiltDeploymentTests

- (NSBundle *)bundle
{
	return [NSBundle bundleForClass:[self class]];
}

- (void)testTheBundlesDeploymentsAreDeployedOnceWhateverTheLaunches
{
	NSError *error = nil;
	NSArray *built = [[self bundle] pathsForResourcesOfType:WFBuiltDeploymentExtension inDirectory:nil];
	XCTAssertEqual([built count], (NSUInteger)2, @"the two the build put there");
	WFProcessEngine *engine = [WFProcessEngine testEngineWithDeploymentsInBundle:[self bundle] error:&error];
	XCTAssertNotNil(engine, @"%@", error);
	XCTAssertFalse(engine.jobExecutorActive, @"a test runs its jobs");
	XCTAssertEqual(engine.historyLevel, WFHistoryLevelFull);
	WFProcessDefinition *expenses = [engine.repositoryService latestDefinitionForKey:@"expense-review" error:&error];
	XCTAssertNotNil(expenses, @"%@", error);
	XCTAssertEqual(expenses.version, (NSInteger)1);

	/* The next launch: nothing new. */
	NSArray *again = [engine.repositoryService deployBuiltDeploymentsInBundle:[self bundle] error:&error];
	XCTAssertEqual([again count], (NSUInteger)2, @"%@", error);
	XCTAssertEqual([[engine.repositoryService latestDefinitionForKey:@"expense-review" error:NULL] version], (NSInteger)1);
	/* Every process the deployments say they hold, deployed. */
	for (NSString *path in built) {
		WFBuiltDeployment *deployment = [WFBuiltDeployment deploymentWithContentsOfURL:[NSURL fileURLWithPath:path]
		                                                                         error:&error];
		XCTAssertGreaterThan([deployment.processKeys count], (NSUInteger)0, @"%@", error);
		for (NSString *key in deployment.processKeys) {
			XCTAssertNotNil([engine.repositoryService latestDefinitionForKey:key error:NULL], @"%@", key);
		}
	}
	[engine close];
}

- (void)testABuiltDeploymentIsWhatWasChecked
{
	NSError *error = nil;
	NSURL *examples = [[[[NSURL fileURLWithPath:@__FILE__] URLByDeletingLastPathComponent]
		URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"Examples/Processes/expense-review"];
	NSDictionary *resources = [WFBuiltDeployment resourcesInDirectory:examples error:&error];
	XCTAssertEqual([resources count], (NSUInteger)3, @"%@", error);
	NSArray *problems = nil;
	WFBuiltDeployment *deployment = [WFBuiltDeployment deploymentNamed:@"expenses" resources:resources problems:&problems];
	XCTAssertNotNil(deployment, @"%@", problems);
	XCTAssertEqualObjects(deployment.processKeys, @[ @"expense-review" ]);

	NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
		URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.wfdeployment", [[NSUUID UUID] UUIDString]]];
	XCTAssertTrue([deployment writeToURL:url error:&error], @"%@", error);
	XCTAssertTrue([deployment writeToURL:url error:&error], @"written over: %@", error);
	WFBuiltDeployment *read = [WFBuiltDeployment deploymentWithContentsOfURL:url error:&error];
	XCTAssertEqualObjects(read.name, @"expenses", @"%@", error);
	XCTAssertEqualObjects(read.resources, resources);
	XCTAssertEqualObjects(read.processKeys, deployment.processKeys);
	[[NSFileManager defaultManager] removeItemAtURL:url error:NULL];

	NSMutableDictionary *broken = [resources mutableCopy];
	[broken removeObjectForKey:@"claim.xhtml"];
	XCTAssertNil([WFBuiltDeployment deploymentNamed:@"expenses" resources:broken problems:&problems]);
	XCTAssertEqual([problems count], (NSUInteger)1, @"the form it lacks: %@", problems);
	XCTAssertNil([WFBuiltDeployment deploymentNamed:@"" resources:resources problems:&problems], @"a name is needed");
	XCTAssertNil([WFBuiltDeployment deploymentWithContentsOfURL:examples error:&error], @"not a built one");
}

@end

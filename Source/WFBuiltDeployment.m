#import "WFBuiltDeployment.h"
#import "WFDeployment+Internal.h"
#import "WFBpmn.h"
#import "WFDecision.h"
#import "WFStore.h"
#import "WFTypes.h"

NSString * const WFBuiltDeploymentExtension = @"wfdeployment";

/* What Deployment.plist is written as; one that says more is refused. */
static const NSInteger WFBuiltDeploymentFormat = 1;

static NSString * const WFManifestName = @"Deployment.plist";
static NSString * const WFResourcesDirectory = @"Resources";

static id
WFBuiltFail(NSError **error, NSString *format, ...)
{
	if (error != NULL) {
		va_list args;
		va_start(args, format);
		NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
		va_end(args);
		*error = [NSError errorWithDomain:WFErrorDomain code:WFErrorInvalidDefinition
		                         userInfo:@{ NSLocalizedDescriptionKey: message }];
	}
	return nil;
}

@interface WFBuiltDeployment ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSData *> *resources;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *processKeys;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *decisionKeys;
@end

@implementation WFBuiltDeployment

+ (NSDictionary<NSString *, NSData *> *)resourcesInDirectory:(NSURL *)directory error:(NSError **)error
{
	NSFileManager *files = [NSFileManager defaultManager];
	NSString *root = [directory path];
	BOOL isDirectory = NO;
	if (![files fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) {
		return WFBuiltFail(error, @"%@ is not a directory", root);
	}
	NSMutableDictionary *resources = [NSMutableDictionary dictionary];
	for (NSString *path in [files enumeratorAtPath:root]) {
		NSString *full = [root stringByAppendingPathComponent:path];
		BOOL nested = NO;
		BOOL hidden = NO;
		for (NSString *component in [path pathComponents]) {
			hidden = hidden || [component hasPrefix:@"."];
		}
		if (hidden || ([files fileExistsAtPath:full isDirectory:&nested] && nested)) {
			continue;
		}
		NSData *bytes = [NSData dataWithContentsOfFile:full];
		if (bytes == nil) {
			return WFBuiltFail(error, @"%@ cannot be read", full);
		}
		[resources setObject:bytes forKey:path];
	}
	return resources;
}

+ (instancetype)deploymentNamed:(NSString *)name
                      resources:(NSDictionary<NSString *, NSData *> *)resources
                       problems:(NSArray<WFProblem *> **)problems
{
	NSArray *found = [WFDeploymentChecker problemsInResources:resources];
	if ([name length] == 0 || [resources count] == 0) {
		/* What the repository refuses before it reads anything. */
		found = [found arrayByAddingObjectsFromArray:[self problemsOfName:name resources:resources]];
	}
	if (problems != NULL) {
		*problems = found;
	}
	if ([found count] > 0) {
		return nil;
	}
	NSMutableArray *processKeys = [NSMutableArray array], *decisionKeys = [NSMutableArray array];
	for (NSString *path in [[resources allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSData *bytes = [resources objectForKey:path];
		if (WFIsBpmnResource(path)) {
			for (WFProcessDefinition *definition in [WFBpmnReader definitionsFromData:bytes error:NULL]) {
				[processKeys addObject:definition.processId];
			}
		} else if (WFIsDmnResource(path)) {
			for (WFDecisionDefinition *decision in [WFDmnReader decisionsFromData:bytes error:NULL]) {
				[decisionKeys addObject:decision.key];
			}
		}
	}
	WFBuiltDeployment *deployment = [[self alloc] init];
	deployment.name = name;
	deployment.resources = resources;
	deployment.processKeys = processKeys;
	deployment.decisionKeys = decisionKeys;
	return deployment;
}

/* A problem the checker has no resource for: the deployment's own. */
+ (NSArray<WFProblem *> *)problemsOfName:(NSString *)name resources:(NSDictionary *)resources
{
	NSError *error = nil;
	WFBuiltFail(&error, [name length] == 0 ? @"a deployment needs a name" : @"a deployment needs at least one resource");
	return @[ [WFProblem problemWithMessage:[error localizedDescription]] ];
}

+ (instancetype)deploymentWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
	NSData *data = [NSData dataWithContentsOfURL:[url URLByAppendingPathComponent:WFManifestName]];
	id manifest = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL]
		: nil;
	if (![manifest isKindOfClass:[NSDictionary class]]) {
		return WFBuiltFail(error, @"%@ is not a built deployment: it has no %@", [url path], WFManifestName);
	}
	if ([[manifest objectForKey:@"Format"] integerValue] > WFBuiltDeploymentFormat) {
		return WFBuiltFail(error, @"%@ was built by a newer WorkflowKit", [url path]);
	}
	NSString *name = [manifest objectForKey:@"Name"];
	NSArray *paths = [manifest objectForKey:@"Resources"];
	if (![name isKindOfClass:[NSString class]] || ![paths isKindOfClass:[NSArray class]]) {
		return WFBuiltFail(error, @"%@: its %@ names no deployment", [url path], WFManifestName);
	}
	NSURL *root = [url URLByAppendingPathComponent:WFResourcesDirectory];
	NSMutableDictionary *resources = [NSMutableDictionary dictionary];
	for (NSString *path in paths) {
		NSData *bytes = [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:path]];
		if (bytes == nil) {
			return WFBuiltFail(error, @"%@: its resource %@ is missing", [url path], path);
		}
		[resources setObject:bytes forKey:path];
	}
	WFBuiltDeployment *deployment = [[self alloc] init];
	deployment.name = name;
	deployment.resources = resources;
	deployment.processKeys = [manifest objectForKey:@"Processes"] ?: @[];
	deployment.decisionKeys = [manifest objectForKey:@"Decisions"] ?: @[];
	return deployment;
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error
{
	NSFileManager *files = [NSFileManager defaultManager];
	/* Written beside, then moved in: a build that fails leaves what was
	 * there. */
	NSURL *partial = [[url URLByDeletingLastPathComponent]
		URLByAppendingPathComponent:[NSString stringWithFormat:@".%@.partial", [url lastPathComponent]]];
	[files removeItemAtURL:partial error:NULL];
	NSURL *root = [partial URLByAppendingPathComponent:WFResourcesDirectory];
	if (![files createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:error]) {
		return NO;
	}
	NSArray *paths = [[self.resources allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *path in paths) {
		NSURL *file = [root URLByAppendingPathComponent:path];
		if (![files createDirectoryAtURL:[file URLByDeletingLastPathComponent] withIntermediateDirectories:YES
		                      attributes:nil error:error]
		    || ![[self.resources objectForKey:path] writeToURL:file options:NSDataWritingAtomic error:error]) {
			[files removeItemAtURL:partial error:NULL];
			return NO;
		}
	}
	NSDictionary *manifest = @{ @"Format": @(WFBuiltDeploymentFormat), @"Name": self.name, @"Resources": paths,
	                            @"Processes": self.processKeys ?: @[], @"Decisions": self.decisionKeys ?: @[] };
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:manifest format:NSPropertyListXMLFormat_v1_0
	                                                         options:0 error:error];
	if (data == nil || ![data writeToURL:[partial URLByAppendingPathComponent:WFManifestName] options:0 error:error]) {
		[files removeItemAtURL:partial error:NULL];
		return NO;
	}
	[files removeItemAtURL:url error:NULL];
	if (![files moveItemAtURL:partial toURL:url error:error]) {
		[files removeItemAtURL:partial error:NULL];
		return NO;
	}
	return YES;
}

@end

@implementation WFRepositoryService (WFBuiltDeployments)

- (WFDeployment *)deployBuiltDeployment:(WFBuiltDeployment *)deployment error:(NSError **)error
{
	return [self deployResources:deployment.resources name:deployment.name filterDuplicates:YES error:error];
}

- (NSArray<WFDeployment *> *)deployBuiltDeploymentsInBundle:(NSBundle *)bundle error:(NSError **)error
{
	NSMutableArray *deployed = [NSMutableArray array];
	NSArray *paths = [[bundle pathsForResourcesOfType:WFBuiltDeploymentExtension inDirectory:nil]
		sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *path in paths) {
		WFBuiltDeployment *built = [WFBuiltDeployment deploymentWithContentsOfURL:[NSURL fileURLWithPath:path] error:error];
		WFDeployment *deployment = built != nil ? [self deployBuiltDeployment:built error:error] : nil;
		if (deployment == nil) {
			return nil;
		}
		[deployed addObject:deployment];
	}
	return deployed;
}

@end

@implementation WFProcessEngine (WFTesting)

+ (instancetype)testEngineWithDeploymentsInBundle:(NSBundle *)bundle error:(NSError **)error
{
	WFStore *store = [WFStore inMemoryStore:error];
	if (store == nil) {
		return nil;
	}
	WFProcessEngine *engine = [[self alloc] initWithStore:store];
	engine.historyLevel = WFHistoryLevelFull;
	engine.jobExecutorActive = NO;
	if (![engine openWithError:error]) {
		return nil;
	}
	if ([engine.repositoryService deployBuiltDeploymentsInBundle:bundle error:error] == nil) {
		[engine close];
		return nil;
	}
	return engine;
}

@end

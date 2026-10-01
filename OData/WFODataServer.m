#import "WFODataServer.h"
#import "WFODataService.h"
#import "WorkflowKit.h"
#import <OTelKit/OTelKit.h>

static NSString * const WFServerComponent = @"wf-serve";

static NSError *
WFServerError(NSString *message)
{
	/* A setting it cannot use: the server does not start. */
	return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFormattingError
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static BOOL
WFServerFail(NSError **error, NSString *message)
{
	if (error != NULL) {
		*error = WFServerError(message);
	}
	return NO;
}

static NSURL *
WFServerURL(id text)
{
	if (![text isKindOfClass:[NSString class]] || [text length] == 0) {
		return nil;
	}
	return [text rangeOfString:@"://"].location != NSNotFound ? [NSURL URLWithString:text]
		: [NSURL fileURLWithPath:[text stringByExpandingTildeInPath]];
}

/* Everyone is one developer, who may do everything. */
@interface WFDevelopmentAuthenticator : NSObject <HSAuthenticator>
@property (nonatomic, copy) NSString *user;
@property (nonatomic, copy) NSArray<NSString *> *groups;
@end

@implementation WFDevelopmentAuthenticator

- (void)authenticateRequest:(HSRequest *)request reply:(HSAuthenticationReply *)reply
{
	NSString *every = [@[ WFODataScopeWork, WFODataScopeOperationsRead, WFODataScopeOperationsManage,
	                      WFODataScopeDeploy, WFODataScopeReadAllTasks, WFODataScopeAssignTasks,
	                      WFODataScopeReadAllDefinitions, WFODataScopeStartAny ] componentsJoinedByString:@" "];
	[reply finishWithPrincipal:[[HSPrincipal alloc] initWithSubject:self.user
	                                                         claims:@{ @"groups": self.groups ?: @[], @"scope": every }]];
}

@end

@implementation WFServerConfiguration
{
	NSArray *_configurers;
}

static NSMutableDictionary *WFStoreTypes;

+ (void)initialize
{
	if (self == [WFServerConfiguration class] && WFStoreTypes == nil) {
		WFStoreTypes = [NSMutableDictionary dictionaryWithDictionary:@{
			@"InMemory": NSInMemoryStoreType, @"SQLite": NSSQLiteStoreType, @"XML": NSXMLStoreType }];
	}
}

+ (void)registerStoreType:(NSString *)storeType named:(NSString *)name
{
	@synchronized ([WFServerConfiguration class]) {
		[WFStoreTypes setObject:storeType forKey:name];
	}
}

+ (NSString *)environmentPrefix
{
	return @"WF_";
}

+ (NSArray<NSString *> *)knownSettings
{
	return [[super knownSettings] arrayByAddingObjectsFromArray:@[
		@"Deployments", @"Plugins", @"HistoryLevel", @"JobExecutor", @"GroupsClaim",
		@"DevelopmentUser", @"DevelopmentGroups" ]];
}

- (id<HSAuthenticator>)authenticatorWithError:(NSError **)error
{
	NSString *developer = [self setting:@"DevelopmentUser"];
	if (![developer isKindOfClass:[NSString class]] || [developer length] == 0) {
		return [super authenticatorWithError:error];
	}
	for (NSString *other in @[ @"TrustedUserHeader", @"JWTIssuer", @"IntrospectionEndpoint" ]) {
		if ([self setting:other] != nil) {
			WFServerFail(error, [NSString stringWithFormat:@"DevelopmentUser and %@: who is asking is known one way", other]);
			return nil;
		}
	}
	WFDevelopmentAuthenticator *development = [[WFDevelopmentAuthenticator alloc] init];
	development.user = developer;
	id groups = [self setting:@"DevelopmentGroups"];
	if ([groups isKindOfClass:[NSString class]]) {
		NSMutableArray *names = [NSMutableArray array];
		for (NSString *name in [groups componentsSeparatedByString:@","]) {
			NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if ([trimmed length] > 0) {
				[names addObject:trimmed];
			}
		}
		groups = names;
	}
	development.groups = [groups isKindOfClass:[NSArray class]] ? groups : @[];
	[self addWarning:[NSString stringWithFormat:@"every request is %@'s, who may do everything: for development only",
	                  developer]];
	return development;
}

- (BOOL)historyLevel:(WFHistoryLevel *)level error:(NSError **)error
{
	NSDictionary *levels = @{ @"none": @(WFHistoryLevelNone), @"activity": @(WFHistoryLevelActivity),
	                          @"audit": @(WFHistoryLevelAudit), @"full": @(WFHistoryLevelFull) };
	NSString *name = [[self setting:@"HistoryLevel"] description] ?: @"audit";
	NSNumber *found = [levels objectForKey:[name lowercaseString]];
	if (found == nil) {
		return WFServerFail(error, [NSString stringWithFormat:@"HistoryLevel %@: none, activity, audit or full", name]);
	}
	*level = (WFHistoryLevel)[found integerValue];
	return YES;
}

/* Each directory under the deployments directory, as a deployment of the
 * files in it by their paths under it. */
- (BOOL)deployTo:(WFProcessEngine *)engine from:(NSString *)directory error:(NSError **)error
{
	NSFileManager *files = [NSFileManager defaultManager];
	NSArray *names = [[files contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(compare:)];
	if (names == nil) {
		return WFServerFail(error, [NSString stringWithFormat:@"Deployments %@ is not a directory", directory]);
	}
	for (NSString *name in names) {
		NSString *root = [directory stringByAppendingPathComponent:name];
		BOOL isDirectory = NO;
		if ([name hasPrefix:@"."] || ![files fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) {
			continue;
		}
		NSMutableDictionary *resources = [NSMutableDictionary dictionary];
		for (NSString *path in [files enumeratorAtPath:root]) {
			NSString *full = [root stringByAppendingPathComponent:path];
			BOOL nested = NO;
			if ([[path lastPathComponent] hasPrefix:@"."]
			    || ([files fileExistsAtPath:full isDirectory:&nested] && nested)) {
				continue;
			}
			NSData *bytes = [NSData dataWithContentsOfFile:full];
			if (bytes != nil) {
				[resources setObject:bytes forKey:path];
			}
		}
		NSError *failure = nil;
		if ([engine.repositoryService deployResources:resources name:name filterDuplicates:YES error:&failure] == nil) {
			return WFServerFail(error, [NSString stringWithFormat:@"deployment %@: %@", name, [failure localizedDescription]]);
		}
		HSLogMessage(HSLogLevelInfo, WFServerComponent, nil, @"deployment %@: %lu resources", name,
		             (unsigned long)[resources count]);
	}
	return YES;
}

- (WFProcessEngine *)engineWithError:(NSError **)error
{
	@synchronized (self) {
		if (_engine != nil) {
			return _engine;
		}
		WFHistoryLevel history;
		if (![self historyLevel:&history error:error]) {
			return nil;
		}
		NSString *name = [[self setting:@"StoreType"] description] ?: @"InMemory";
		NSString *type;
		@synchronized ([WFServerConfiguration class]) {
			type = [WFStoreTypes objectForKey:name] ?: name;
		}
		NSURL *storeURL = WFServerURL([self setting:@"StoreURL"]);
		NSError *failure = nil;
		WFStore *store = [[WFStore alloc] initWithStoreType:type URL:storeURL options:[self setting:@"StoreOptions"]
		                                              error:&failure];
		if (store == nil) {
			WFServerFail(error, [NSString stringWithFormat:@"the %@ store at %@ does not open: %@", type,
			                     storeURL ?: (id)@"(none)", [failure localizedDescription]]);
			return nil;
		}
		WFProcessEngine *engine = [[WFProcessEngine alloc] initWithStore:store];
		engine.historyLevel = history;
		engine.jobExecutorActive = [self flag:@"JobExecutor" otherwise:YES];
		/* Its commands and jobs as spans, under the requests that ran them;
		 * recorded when the application traces (OTLPEndpoint). */
		engine.tracer = (id<WFTracer>)[OTTracer tracerNamed:@"WorkflowKit" version:nil];

		/* The application's code, before anything runs. */
		NSMutableArray *configurers = [NSMutableArray array];
		NSString *plugins = [[self setting:@"Plugins"] description];
		if (plugins != nil) {
			plugins = [plugins stringByExpandingTildeInPath];
			if (![engine loadPluginsInDirectory:[NSURL fileURLWithPath:plugins] error:&failure]) {
				WFServerFail(error, [NSString stringWithFormat:@"Plugins %@: %@", plugins, [failure localizedDescription]]);
				return nil;
			}
			for (NSString *bundle in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:plugins error:NULL]) {
				Class principal = [[NSBundle bundleWithPath:[plugins stringByAppendingPathComponent:bundle]] principalClass];
				if ([principal conformsToProtocol:@protocol(ODataServiceConfiguring)]) {
					[configurers addObject:principal];
				}
			}
		}
		if (![engine openWithError:&failure]) {
			WFServerFail(error, [NSString stringWithFormat:@"the engine does not open: %@", [failure localizedDescription]]);
			return nil;
		}
		NSString *deployments = [[self setting:@"Deployments"] description];
		if (deployments != nil
		    && ![self deployTo:engine from:[deployments stringByExpandingTildeInPath] error:error]) {
			[engine close];
			return nil;
		}
		_configurers = configurers;
		_engine = engine;
		return engine;
	}
}

- (ODataService *)serviceWithError:(NSError **)error
{
	WFProcessEngine *engine = [self engineWithError:error];
	if (engine == nil) {
		return nil;
	}
	NSURL *root = WFServerURL([self setting:@"ServiceRoot"])
		?: [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu/api/", (unsigned long)self.port]];
	ODataService *service = [WFODataService serviceForEngine:engine serviceRoot:root
	                                              groupsClaim:[[self setting:@"GroupsClaim"] description] ?: @"groups"];
	/* What one request may ask (ODataService.h): each a number, 0 for none. */
	if ([self setting:@"MaxVersion"] != nil) {
		service.maxVersion = [[self setting:@"MaxVersion"] description];
	}
	if ([self setting:@"MaxPageSize"] != nil) {
		service.maxPageSize = (NSUInteger)[self number:@"MaxPageSize" otherwise:0];
	}
	if ([self setting:@"MaxURLLength"] != nil) {
		service.maxURLLength = (NSUInteger)[self number:@"MaxURLLength" otherwise:0];
	}
	if ([self setting:@"MaxExpandDepth"] != nil) {
		service.maxExpandDepth = (NSUInteger)[self number:@"MaxExpandDepth" otherwise:0];
	}
	if ([self setting:@"MaxBatchRequests"] != nil) {
		service.maxBatchRequests = (NSUInteger)[self number:@"MaxBatchRequests" otherwise:0];
	}
	if ([self setting:@"MaxRowsInMemory"] != nil) {
		service.maxRowsInMemory = (NSUInteger)[self number:@"MaxRowsInMemory" otherwise:0];
	}
	if ([self setting:@"MaxJSONDepth"] != nil) {
		service.maxJSONDepth = (NSUInteger)[self number:@"MaxJSONDepth" otherwise:0];
	}
	if ([self setting:@"ReplyTimeout"] != nil) {
		service.replyTimeout = [self number:@"ReplyTimeout" otherwise:0];
	}
	if ([self setting:@"AllowAnonymous"] != nil) {
		service.allowsAnonymousRequests = [self flag:@"AllowAnonymous" otherwise:NO];
	}
	for (Class configurer in _configurers) {
		[(id<ODataServiceConfiguring>)configurer configureService:service];
	}
	return service;
}

@end

@implementation WFServerApplication

+ (Class)configurationClass
{
	return [WFServerConfiguration class];
}

- (WFProcessEngine *)engine
{
	HSConfiguration *configuration = self.configuration;
	return [configuration isKindOfClass:[WFServerConfiguration class]] ? ((WFServerConfiguration *)configuration).engine : nil;
}

- (BOOL)stopWithTimeout:(NSTimeInterval)timeout
{
	BOOL finished = [super stopWithTimeout:timeout];
	[self.engine close];
	return finished;
}

- (int)run
{
	int status = [super run];
	/* PrintMetadata, or a server that never started: nothing stopped it. */
	[self.engine close];
	return status;
}

@end

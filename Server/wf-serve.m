/*
 * wf-serve -- a WorkflowKit engine served over OData.
 *
 *   wf-serve -Config server.plist
 *   wf-serve -StoreType SQLite -StoreURL /var/lib/workflow.sqlite \
 *            -Deployments /srv/workflow/deployments -Port 8080
 *
 * Settings come from the property list -Config names, and any of them can
 * be given on the command line instead, which wins:
 *
 *   StoreType     InMemory (the default), SQLite, XML; CDPostgreSQLStore or
 *                 CDMySQLStore where built with them (make postgresql=yes,
 *                 mysql=yes)
 *   StoreURL      the store's URL; a plain path is a file
 *   StoreOptions  a dictionary, handed to the store as it is: for a
 *                 server's store, CDSQLStoreSchemaName names the schema the
 *                 engine's tables are in
 *   Deployments   a directory: each directory in it is a deployment of
 *                 the files in it, by their paths under it -- BPMN, DMN,
 *                 the XForms documents its forms name -- deployed at start,
 *                 unless the latest deployment of that name is the same
 *                 byte for byte
 *   Plugins       a directory of bundles, each a WFEnginePlugin's
 *                 (WFProcessEngine.h): delegates, listeners, form handlers.
 *                 A principal class that conforms to ODataServiceConfiguring
 *                 is sent +configureService: too.
 *   HistoryLevel  none, activity, audit (the default) or full
 *   JobExecutor   NO: run no jobs (timers, async continuations)
 *   ServiceRoot   the public URL of the service, which its links begin with
 *                 (default http://127.0.0.1:<Port>/api/)
 *   Port          default 8080
 *   Localhost     YES (the default): listen on loopback only, for a proxy
 *                 on the same machine
 *   MaxPageSize   server-driven paging, 0 for none
 *   TrustedUserHeader, ProxySecretHeader, ProxySecretEnvironment,
 *   JWTIssuer, JWTAudience, AllowAnonymous
 *                 who is asking, as ois-serve has them (ODataAuthentication.h)
 *   PrintMetadata YES: write $metadata to standard output and exit
 *
 * It serves until SIGINT or SIGTERM, runs the engine's jobs meanwhile,
 * logs to standard error, and exits 0 on a clean stop, 1 on a
 * configuration it cannot use.
 */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "WorkflowKit.h"
#import "WFODataService.h"
#import "ODataHTTPServer.h"
#ifdef WF_SERVE_POSTGRESQL
#import <CDPostgreSQLStore/CDPostgreSQLStore.h>
#endif
#ifdef WF_SERVE_MYSQL
#import <CDMySQLStore/CDMySQLStore.h>
#endif

static void
WFFail(NSString *message)
{
	fprintf(stderr, "wf-serve: %s\n", [message UTF8String]);
	exit(1);
}

static NSDictionary *
WFSettings(void)
{
	NSMutableDictionary *settings = [NSMutableDictionary dictionary];
	NSDictionary *arguments = [[NSUserDefaults standardUserDefaults] volatileDomainForName:NSArgumentDomain];
	NSString *config = [arguments objectForKey:@"Config"];
	if (config != nil) {
		NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:config];
		if (file == nil) {
			WFFail([NSString stringWithFormat:@"%@ is not a property list", config]);
		}
		[settings addEntriesFromDictionary:file];
	}
	[settings addEntriesFromDictionary:arguments];
	return settings;
}

static NSURL *
WFURL(NSString *text)
{
	if ([text length] == 0) {
		return nil;
	}
	return [text rangeOfString:@"://"].location != NSNotFound ? [NSURL URLWithString:text]
		: [NSURL fileURLWithPath:[text stringByExpandingTildeInPath]];
}

static NSString *
WFStoreType(NSString *name)
{
	NSMutableDictionary *known = [NSMutableDictionary dictionaryWithDictionary:@{
		@"InMemory": NSInMemoryStoreType, @"SQLite": NSSQLiteStoreType, @"XML": NSXMLStoreType }];
#ifdef WF_SERVE_POSTGRESQL
	/* Referenced, so that the linker keeps the backend, which registers it. */
	[CDPostgreSQLStore class];
	[known setObject:CDPostgreSQLStoreType forKey:@"PostgreSQL"];
#endif
#ifdef WF_SERVE_MYSQL
	[CDMySQLStore class];
	[known setObject:CDMySQLStoreType forKey:@"MySQL"];
#endif
	return [known objectForKey:name] ?: name;
}

static WFHistoryLevel
WFHistoryLevelNamed(NSString *name)
{
	NSDictionary *levels = @{ @"none": @(WFHistoryLevelNone), @"activity": @(WFHistoryLevelActivity),
	                          @"audit": @(WFHistoryLevelAudit), @"full": @(WFHistoryLevelFull) };
	NSNumber *level = [levels objectForKey:[name lowercaseString] ?: @"audit"];
	if (level == nil) {
		WFFail([NSString stringWithFormat:@"-HistoryLevel %@: none, activity, audit or full", name]);
	}
	return (WFHistoryLevel)[level integerValue];
}

/* Each directory under the deployments directory, as a deployment of the
 * files in it by their paths under it. */
static void
WFDeploy(WFProcessEngine *engine, NSString *directory)
{
	NSFileManager *files = [NSFileManager defaultManager];
	NSArray *names = [[files contentsOfDirectoryAtPath:directory error:NULL]
		sortedArrayUsingSelector:@selector(compare:)];
	if (names == nil) {
		WFFail([NSString stringWithFormat:@"-Deployments %@ is not a directory", directory]);
	}
	for (NSString *name in names) {
		NSString *root = [directory stringByAppendingPathComponent:name];
		BOOL isDirectory = NO;
		if ([name hasPrefix:@"."] || ![files fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) {
			continue;
		}
		NSMutableDictionary *resources = [NSMutableDictionary dictionary];
		NSDirectoryEnumerator *walk = [files enumeratorAtPath:root];
		for (NSString *path in walk) {
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
		NSError *error = nil;
		WFDeployment *deployment = [engine.repositoryService deployResources:resources name:name
		                                                     filterDuplicates:YES error:&error];
		if (deployment == nil) {
			WFFail([NSString stringWithFormat:@"deployment %@: %@", name, [error localizedDescription]]);
		}
		fprintf(stderr, "wf-serve: deployment %s: %lu resources\n", [name UTF8String],
		        (unsigned long)[resources count]);
	}
}

/* Who is asking, as ois-serve has it. */
static void
WFAuthenticate(ODataService *service, NSDictionary *settings)
{
	NSString *userHeader = [settings objectForKey:@"TrustedUserHeader"];
	NSString *secretHeader = [settings objectForKey:@"ProxySecretHeader"];
	NSString *issuer = [settings objectForKey:@"JWTIssuer"];
	if ([userHeader length] > 0 && [issuer length] > 0) {
		WFFail(@"one of -TrustedUserHeader and -JWTIssuer: who is asking is known one way");
	}
	if ([userHeader length] > 0) {
		ODataTrustedHeaderAuthenticator *proxy = [[ODataTrustedHeaderAuthenticator alloc] initWithSubjectHeader:userHeader];
		if ([secretHeader length] > 0) {
			/* From the environment, not the command line, where anyone on
			 * the machine can read it. */
			NSString *variable = [settings objectForKey:@"ProxySecretEnvironment"];
			NSString *secret = [variable length] > 0 ? [[[NSProcessInfo processInfo] environment] objectForKey:variable] : nil;
			if ([secret length] == 0) {
				WFFail(@"-ProxySecretHeader needs the secret in the environment variable -ProxySecretEnvironment names");
			}
			proxy.secretHeader = secretHeader;
			proxy.secret = secret;
		}
		service.authenticator = proxy;
	} else if ([secretHeader length] > 0) {
		WFFail(@"-ProxySecretHeader without -TrustedUserHeader: name the header the proxy puts the user in");
	}
	if ([issuer length] > 0) {
		ODataJWTAuthenticator *jwt = [[ODataJWTAuthenticator alloc] initWithIssuer:issuer
		                                                                  audience:[settings objectForKey:@"JWTAudience"]];
		service.authenticator = jwt;
	}
	if ([settings objectForKey:@"AllowAnonymous"] != nil) {
		service.allowsAnonymousRequests = [[settings objectForKey:@"AllowAnonymous"] boolValue];
	}
}

int
main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSDictionary *settings = WFSettings();
		NSError *error = nil;

		NSString *type = WFStoreType([settings objectForKey:@"StoreType"] ?: @"InMemory");
		NSURL *storeURL = WFURL([settings objectForKey:@"StoreURL"]);
		WFStore *store = [[WFStore alloc] initWithStoreType:type URL:storeURL
		                                            options:[settings objectForKey:@"StoreOptions"] error:&error];
		if (store == nil) {
			WFFail([NSString stringWithFormat:@"the %@ store at %@ does not open: %@", type,
				storeURL ?: (id)@"(none)", [error localizedDescription]]);
		}
		WFProcessEngine *engine = [[WFProcessEngine alloc] initWithStore:store];
		engine.historyLevel = WFHistoryLevelNamed([settings objectForKey:@"HistoryLevel"]);
		if ([settings objectForKey:@"JobExecutor"] != nil) {
			engine.jobExecutorActive = [[settings objectForKey:@"JobExecutor"] boolValue];
		}

		/* The application's code, before anything runs. */
		NSString *plugins = [settings objectForKey:@"Plugins"];
		NSMutableArray *configurers = [NSMutableArray array];
		if (plugins != nil) {
			if (![engine loadPluginsInDirectory:WFURL(plugins) error:&error]) {
				WFFail([NSString stringWithFormat:@"-Plugins %@: %@", plugins, [error localizedDescription]]);
			}
			for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:plugins error:NULL]) {
				Class principal = [[NSBundle bundleWithPath:[plugins stringByAppendingPathComponent:name]] principalClass];
				if ([principal conformsToProtocol:@protocol(ODataServiceConfiguring)]) {
					[configurers addObject:principal];
				}
			}
		}
		if (![engine openWithError:&error]) {
			WFFail([NSString stringWithFormat:@"the engine does not open: %@", [error localizedDescription]]);
		}
		if ([settings objectForKey:@"Deployments"] != nil) {
			WFDeploy(engine, [[settings objectForKey:@"Deployments"] stringByExpandingTildeInPath]);
		}

		NSUInteger port = [settings objectForKey:@"Port"] != nil ? (NSUInteger)[[settings objectForKey:@"Port"] integerValue] : 8080;
		NSURL *root = WFURL([settings objectForKey:@"ServiceRoot"])
			?: [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu/api/", (unsigned long)port]];
		ODataService *service = [WFODataService serviceForEngine:engine serviceRoot:root];
		if ([settings objectForKey:@"MaxPageSize"] != nil) {
			service.maxPageSize = (NSUInteger)[[settings objectForKey:@"MaxPageSize"] integerValue];
		}
		WFAuthenticate(service, settings);
		for (Class configurer in configurers) {
			[(id<ODataServiceConfiguring>)configurer configureService:service];
		}
		if ([[settings objectForKey:@"PrintMetadata"] boolValue]) {
			printf("%s\n", [[service metadataXMLForVersion:@"4.01"] UTF8String]);
			[engine close];
			return 0;
		}
		for (NSString *problem in service.metadataProblems) {
			fprintf(stderr, "wf-serve: $metadata: %s\n", [problem UTF8String]);
		}
		for (NSString *problem in service.operationProblems) {
			fprintf(stderr, "wf-serve: operation: %s\n", [problem UTF8String]);
		}
		if ([service.operationProblems count] > 0) {
			WFFail(@"fix the operations above");
		}

		ODataHTTPServer *server = [[ODataHTTPServer alloc] initWithService:service];
		id localhost = [settings objectForKey:@"Localhost"];
		server.bindToLocalhost = localhost != nil ? [localhost boolValue] : YES;
		fprintf(stderr, "wf-serve: %s on port %lu%s\n", [[root absoluteString] UTF8String], (unsigned long)port,
		        server.bindToLocalhost ? " (loopback)" : "");
		if (![server runOnPort:port error:&error]) {
			WFFail([NSString stringWithFormat:@"cannot listen on %lu: %@", (unsigned long)port, [error localizedDescription]]);
		}
		[engine close];
		fprintf(stderr, "wf-serve: stopped\n");
	}
	return 0;
}

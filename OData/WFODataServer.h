#import <ODataService/ODataServer.h>

@class WFProcessEngine;

/*
 * The engine served over HTTP: an HTTPServerKit application, with the
 * OData API (WFODataService.h) as its module. wf-serve is this
 * application and nothing more:
 *
 *   int main(int argc, const char *argv[])
 *   {
 *       return HSMain(argc, argv, [WFServerApplication class]);
 *   }
 *
 * and an application of its own subclasses it for routes, stages or other
 * APIs beside it (HSApplication.h, ODataServer.h), or makes one from
 * settings and starts it in its own process.
 *
 * Settings come from the property list -Config names, then WF_ variables
 * (WF_PORT, WF_STORE_TYPE, WF_DEVELOPMENT_USER), then the command line's
 * -Name value pairs; a later one wins. The engine's:
 *
 *   StoreType     InMemory (the default), SQLite, XML, a name registered
 *                 with +registerStoreType:named: (wf-serve's PostgreSQL and
 *                 MySQL, where built with them), or the type a backend the
 *                 Libraries setting loads registers
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
 *   GroupsClaim   the claim a principal's groups are in (default groups):
 *                 what candidate groups name; any other claim is matched
 *                 by a candidate group name:value
 *   DevelopmentUser, DevelopmentGroups
 *                 for working without an identity provider: every request
 *                 is this user's, in these groups (an array, or text
 *                 separated by commas), with every scope the API has. Never
 *                 where anyone else can reach the port.
 *
 * The service's, as ois-serve has them: ServiceRoot (default
 * http://127.0.0.1:<Port>/api/), MaxPageSize and the other limits,
 * AllowAnonymous, PrintMetadata. The server's, HTTPServerKit's
 * (HSApplication.h): Port, Localhost, who is asking (TrustedUserHeader,
 * JWTIssuer, IntrospectionEndpoint, ...), health and readiness, metrics,
 * the access log, CORS, and traces (OTLPEndpoint, or OpenTelemetry's
 * OTEL_ variables).
 */
@interface WFServerConfiguration : ODataServerConfiguration

/* A store type by a short name, for StoreType: before the configuration
 * is read. */
+ (void)registerStoreType:(NSString *)storeType named:(NSString *)name;

/* The engine, its store open, its plugins loaded and its deployments
 * deployed: made once, by the first to ask. */
- (WFProcessEngine *)engineWithError:(NSError **)error;
@property (nonatomic, readonly, strong) WFProcessEngine *engine;

@end

@interface WFServerApplication : ODataServerApplication

/* Once prepared. Closed when the application stops. */
@property (nonatomic, readonly, strong) WFProcessEngine *engine;

@end

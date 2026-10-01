/*
 * wf-serve -- a WorkflowKit engine served over HTTP: HTTPServerKit's
 * HSMain with WFServerApplication, whose header (OData/WFODataServer.h)
 * has its settings.
 *
 *   wf-serve -Config server.plist
 *   wf-serve -StoreType SQLite -StoreURL /var/lib/workflow.sqlite \
 *            -Deployments /srv/workflow/deployments -Port 8080
 *   WF_PORT=8080 WF_LOCALHOST=NO OTEL_EXPORTER_OTLP_ENDPOINT=http://collector:4318 wf-serve
 *
 * It serves until SIGINT or SIGTERM, runs the engine's jobs meanwhile,
 * logs to standard error, and exits 0 on a clean stop, 1 on a
 * configuration it cannot use.
 */
#import "WFODataServer.h"
#ifdef WF_SERVE_POSTGRESQL
#import <CDPostgreSQLStore/CDPostgreSQLStore.h>
#endif
#ifdef WF_SERVE_MYSQL
#import <CDMySQLStore/CDMySQLStore.h>
#endif

int
main(int argc, const char *argv[])
{
	@autoreleasepool {
		/* FreeCoreData's server stores, where built with them (make
		 * postgresql=yes, mysql=yes): referenced, so that the linker keeps
		 * the backend, which registers itself. */
#ifdef WF_SERVE_POSTGRESQL
		[CDPostgreSQLStore class];
		[WFServerConfiguration registerStoreType:CDPostgreSQLStoreType named:@"PostgreSQL"];
#endif
#ifdef WF_SERVE_MYSQL
		[CDMySQLStore class];
		[WFServerConfiguration registerStoreType:CDMySQLStoreType named:@"MySQL"];
#endif
	}
	return HSMain(argc, argv, [WFServerApplication class]);
}

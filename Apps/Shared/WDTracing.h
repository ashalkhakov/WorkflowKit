#import <Foundation/Foundation.h>

/*
 * The app's traces, when OpenTelemetry's variables say where to send them
 * (OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME, ...: OTelKit's
 * OTTracerProvider). ODataIncrementalStore then makes a client span for
 * each request it sends and passes the trace on, so a server's spans --
 * wf-serve's, the engine's store's -- join the app's own. Without them it
 * records nothing.
 */

/* At launch: whether tracing is on. A variable it cannot use is logged. */
BOOL WDStartTracing(void);
/* At quit: the last spans sent. */
void WDStopTracing(void);

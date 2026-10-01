#import "WDTracing.h"
#import <OTelKit/OTelKit.h>

BOOL
WDStartTracing(void)
{
	NSError *error = nil;
	/* The app by its name, unless OTEL_SERVICE_NAME says otherwise. */
	NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
	NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
	[defaults setObject:[[NSProcessInfo processInfo] processName] forKey:@"service.name"];
	if ([info objectForKey:@"CFBundleShortVersionString"] != nil) {
		[defaults setObject:[info objectForKey:@"CFBundleShortVersionString"] forKey:@"service.version"];
	}
	OTTracerProvider *provider = [OTTracerProvider providerWithEnvironment:[[NSProcessInfo processInfo] environment]
	                                                              defaults:defaults error:&error];
	if (provider == nil) {
		if (error != nil) {
			NSLog(@"No traces: %@", [error localizedDescription]);
		}
		return NO;
	}
	OTTracerProvider.sharedProvider = provider;
	return YES;
}

void
WDStopTracing(void)
{
	OTTracerProvider *provider = OTTracerProvider.sharedProvider;
	if (provider.recording) {
		[provider shutdownWithTimeout:2];
		OTTracerProvider.sharedProvider = nil;
	}
}

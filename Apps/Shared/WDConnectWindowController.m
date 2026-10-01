#import "WDConnectWindowController.h"
#import "WDSession.h"
#import "WDSignIn.h"
#if __has_include(<ODataIncrementalStore/ODataIncrementalStore.h>)
#import <ODataIncrementalStore/ODataIncrementalStore.h>
#else
#import "ODataIncrementalStore.h"
#endif

static NSString * const WDServiceAddressKey = @"WDServiceAddress";
static NSString * const WDClientIDKey = @"WDClientID";
/* What the app asks the identity provider for, besides what the server
 * requires: the API's scopes, and a refresh token. */
static NSString * const WDScopesKey = @"WDScopes";

@implementation WDConnectWindowController
{
	void (^_completion)(WDSession *, WDSignIn *);
	WDSignIn *_signIn;
}

+ (void)initialize
{
	if (self == [WDConnectWindowController class]) {
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{
			WDServiceAddressKey: @"http://localhost:8080/api/",
			WDClientIDKey: @"workflowdesk",
			WDScopesKey: @"profile offline_access Tasks.Work Operations.Read Operations.Manage Deployments.Create" }];
	}
}

- (instancetype)initWithCompletion:(void (^)(WDSession *session, WDSignIn *signIn))completion
{
	if ((self = [super initWithWindowNibName:@"ConnectWindow"])) {
		_completion = [completion copy];
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		_serviceAddress = [[defaults stringForKey:WDServiceAddressKey] copy];
		_clientID = [[defaults stringForKey:WDClientIDKey] copy];
		_status = @"";
		_idle = YES;
	}
	return self;
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[[self window] center];
	[self.progress setHidden:YES];
}

- (void)finishWithStatus:(NSString *)status
{
	[self.progress stopAnimation:self];
	/* Hidden by hand: GNUstep shows a stopped indicator regardless. */
	[self.progress setHidden:YES];
	self.status = status ?: @"";
	self.idle = YES;
	_signIn = nil;
}

- (void)fail:(NSError *)error
{
	[self finishWithStatus:@""];
	if ([[error domain] isEqualToString:WDSignInErrorDomain] && [error code] == WDSignInErrorCancelled) {
		return;
	}
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Could not connect to the server."];
	[alert setInformativeText:[error localizedDescription] ?: @"The server did not answer."];
	[alert beginSheetModalForWindow:[self window] completionHandler:nil];
}

- (IBAction)connect:(id)sender
{
	[[self window] makeFirstResponder:nil];
	NSString *address = [self.serviceAddress stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSURL *url = [address length] > 0 ? [NSURL URLWithString:address] : nil;
	if (url == nil || [url host] == nil || !([[url scheme] isEqualToString:@"http"] || [[url scheme] isEqualToString:@"https"])) {
		[self fail:[NSError errorWithDomain:NSCocoaErrorDomain code:NSFormattingError userInfo:@{
			NSLocalizedDescriptionKey: @"Enter the server's address, as http://host:port/api/." }]];
		return;
	}
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:address forKey:WDServiceAddressKey];
	[defaults setObject:self.clientID ?: @"" forKey:WDClientIDKey];

	WDSignIn *signIn = [[WDSignIn alloc] initWithClientID:self.clientID ?: @""];
	signIn.scopes = [[defaults stringForKey:WDScopesKey] componentsSeparatedByCharactersInSet:
		[NSCharacterSet whitespaceCharacterSet]];
	signIn.openURL = ^BOOL(NSURL *page) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSWorkspace sharedWorkspace] openURL:page];
		});
		return YES;
	};
	_signIn = signIn;
	self.idle = NO;
	self.status = @"Connecting…";
	[self.progress setHidden:NO];
	[self.progress startAnimation:self];

	NSString *clientID = self.clientID;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		@autoreleasepool {
			NSError *error = nil;
			WDSession *session = [[WDSession alloc] initWithServiceURL:url credentials:signIn];
			BOOL done = [session open:&error];
			/* A server that takes OpenID Connect tokens: signed in now,
			 * rather than at its first refusal. */
			ODataSchemaAuthorization *openID = nil;
			for (ODataSchemaAuthorization *authorization in session.store.schema.authorizations) {
				if (authorization.issuerURL != nil) {
					openID = authorization;
					break;
				}
			}
			if (done && openID != nil) {
				if ([clientID length] == 0) {
					error = [NSError errorWithDomain:WDSignInErrorDomain code:WDSignInErrorRefused userInfo:@{
						NSLocalizedDescriptionKey: [NSString stringWithFormat:
							@"The server asks you to sign in at %@: enter WorkflowDesk's client ID there.", openID.issuerURL] }];
					done = NO;
				} else {
					dispatch_async(dispatch_get_main_queue(), ^{
						self.status = @"Sign in with your browser to continue.";
					});
					done = [signIn signInWithIssuer:openID.issuerURL scopes:openID.requiredScopes error:&error];
				}
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				if (signIn != self->_signIn) {
					return;
				}
				if (!done) {
					[self fail:error];
					return;
				}
				[self finishWithStatus:@""];
				self->_completion(session, signIn);
			});
		}
	});
}

- (IBAction)cancel:(id)sender
{
	if (_signIn != nil) {
		[_signIn cancel];
		[self finishWithStatus:@""];
		return;
	}
	[self close];
}

@end

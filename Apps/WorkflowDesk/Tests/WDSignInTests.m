#import <XCTest/XCTest.h>
#import "WDSignIn.h"
#if __has_include(<ODataKit/ODataTransport.h>)
#import <ODataKit/ODataTransport.h>
#import <ODataKit/ODataSchema.h>
#else
#import "ODataTransport.h"
#import "ODataSchema.h"
#endif

/*
 * An identity provider of the test's own: discovery, and a token endpoint
 * that holds the client to PKCE, answering through the transport. The
 * browser is the test too: it follows the authorization URL back to the
 * app's loopback redirect with the code, over real HTTP on 127.0.0.1.
 */
@interface WDTestProvider : NSObject <ODataTransport>
@property (atomic, copy) NSString *challenge;
@property (atomic, copy) NSString *redirect;
@property (atomic) NSUInteger tokens;
@property (atomic, copy) NSDictionary *lastGrant;
@end

static NSDictionary *
WDForm(NSData *body)
{
	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
	for (NSString *pair in [text componentsSeparatedByString:@"&"]) {
		NSArray *parts = [pair componentsSeparatedByString:@"="];
		if ([parts count] == 2) {
			[fields setObject:[[parts lastObject] stringByRemovingPercentEncoding]
			           forKey:[[parts firstObject] stringByRemovingPercentEncoding]];
		}
	}
	return fields;
}

static NSString *
WDTestJWT(NSDictionary *claims)
{
	NSData *header = [@"{\"alg\":\"RS256\",\"typ\":\"JWT\"}" dataUsingEncoding:NSUTF8StringEncoding];
	NSData *payload = [NSJSONSerialization dataWithJSONObject:claims options:0 error:NULL];
	return [NSString stringWithFormat:@"%@.%@.c2ln", WDBase64URL(header), WDBase64URL(payload)];
}

@implementation WDTestProvider

- (void)answer:(ODataExchange *)exchange status:(NSInteger)status JSON:(id)json
{
	exchange.URLResponse = [[NSHTTPURLResponse alloc] initWithURL:[exchange.request URL] statusCode:status
	                                                  HTTPVersion:@"HTTP/1.1"
	                                                 headerFields:@{ @"Content-Type": @"application/json" }];
	exchange.data = [NSJSONSerialization dataWithJSONObject:json options:0 error:NULL];
	[exchange finish];
}

- (void)startExchange:(ODataExchange *)exchange
{
	NSString *path = [[exchange.request URL] path];
	if ([path isEqualToString:@"/realm/.well-known/openid-configuration"]) {
		[self answer:exchange status:200 JSON:@{ @"issuer": @"https://idp.test/realm",
		                                        @"authorization_endpoint": @"https://idp.test/realm/authorize?prompt=login",
		                                        @"token_endpoint": @"https://idp.test/realm/token" }];
		return;
	}
	if ([path isEqualToString:@"/realm/token"]) {
		NSDictionary *grant = WDForm([exchange.request HTTPBody]);
		self.lastGrant = grant;
		BOOL good = NO;
		if ([[grant objectForKey:@"grant_type"] isEqualToString:@"authorization_code"]) {
			good = [[grant objectForKey:@"code"] isEqualToString:@"the-code"]
				&& [[grant objectForKey:@"client_id"] isEqualToString:@"desk"]
				&& [[grant objectForKey:@"redirect_uri"] isEqualToString:self.redirect]
				&& [WDCodeChallenge([grant objectForKey:@"code_verifier"] ?: @"") isEqualToString:self.challenge];
		} else if ([[grant objectForKey:@"grant_type"] isEqualToString:@"refresh_token"]) {
			good = [[grant objectForKey:@"refresh_token"] isEqualToString:@"refresh-1"];
		}
		if (!good) {
			[self answer:exchange status:400 JSON:@{ @"error": @"invalid_grant", @"error_description": @"Bad grant" }];
			return;
		}
		self.tokens += 1;
		[self answer:exchange status:200 JSON:@{
			@"access_token": [NSString stringWithFormat:@"access-%lu", (unsigned long)self.tokens],
			@"refresh_token": @"refresh-1",
			@"id_token": WDTestJWT(@{ @"sub": @"u-17", @"preferred_username": @"ann" }),
			@"token_type": @"Bearer" }];
		return;
	}
	exchange.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:nil];
	[exchange finish];
}

@end

/* A GET of the URL, as the browser sends it; the status line answered. */
static NSString *
WDBrowse(NSURL *url)
{
	__block NSString *status = nil;
	NSCondition *done = [[NSCondition alloc] init];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setTimeoutInterval:10];
	id<ODataTransport> transport = ODataDefaultTransport();
	ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:request target:nil action:NULL];
	[transport startExchange:exchange];
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
	while (!exchange.isFinished && [deadline timeIntervalSinceNow] > 0) {
		[done lock];
		[done waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
		[done unlock];
	}
	if ([exchange.URLResponse isKindOfClass:[NSHTTPURLResponse class]]) {
		status = [NSString stringWithFormat:@"%ld", (long)[(NSHTTPURLResponse *)exchange.URLResponse statusCode]];
	}
	return status ?: [exchange.error localizedDescription] ?: @"no answer";
}

static NSDictionary *
WDQuery(NSURL *url)
{
	NSMutableDictionary *items = [NSMutableDictionary dictionary];
	for (NSURLQueryItem *item in [[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO] queryItems]) {
		[items setObject:[item value] ?: @"" forKey:[item name]];
	}
	return items;
}

@interface WDSignInTests : XCTestCase
@end

@implementation WDSignInTests
{
	WDTestProvider *_provider;
	WDSignIn *_signIn;
	NSURL *_issuer;
	NSDictionary *_authorization;
}

- (void)setUp
{
	[super setUp];
	_provider = [[WDTestProvider alloc] init];
	_signIn = [[WDSignIn alloc] initWithClientID:@"desk"];
	_signIn.transport = _provider;
	_signIn.scopes = @[ @"Tasks.Work", @"offline_access" ];
	_signIn.timeout = 20;
	_issuer = [NSURL URLWithString:@"https://idp.test/realm"];
}

/* A browser that signs the user in and returns with what the callback
 * gets: the query items to add to the redirect, from the authorization
 * request's. */
- (void)browseWith:(NSDictionary *(^)(NSDictionary *request))callback
{
	WDTestProvider *provider = _provider;
	__weak WDSignInTests *weakSelf = self;
	_signIn.openURL = ^BOOL(NSURL *url) {
		NSDictionary *request = WDQuery(url);
		WDSignInTests *strongSelf = weakSelf;
		if (strongSelf != nil) {
			strongSelf->_authorization = request;
		}
		provider.challenge = [request objectForKey:@"code_challenge"];
		provider.redirect = [request objectForKey:@"redirect_uri"];
		NSURLComponents *back = [NSURLComponents componentsWithString:[request objectForKey:@"redirect_uri"]];
		NSMutableArray *items = [NSMutableArray array];
		NSDictionary *answer = callback(request);
		for (NSString *name in answer) {
			[items addObject:[NSURLQueryItem queryItemWithName:name value:[answer objectForKey:name]]];
		}
		[back setQueryItems:items];
		NSURL *returned = [back URL];
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			@autoreleasepool {
				/* What a browser asks for besides the page. */
				WDBrowse([NSURL URLWithString:@"/favicon.ico" relativeToURL:returned]);
				WDBrowse(returned);
			}
		});
		return YES;
	};
}

- (void)testCodeChallengeIsRFC7636s
{
	/* RFC 7636, Appendix B. */
	XCTAssertEqualObjects(WDCodeChallenge(@"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
	                      @"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
}

- (void)testBase64URLHasNoPaddingAndRoundTrips
{
	NSData *bytes = [NSData dataWithBytes:"\xfb\xff\xfe" length:3];
	XCTAssertEqualObjects(WDBase64URL(bytes), @"-__-");
	XCTAssertEqualObjects(WDDataFromBase64URL(@"-__-"), bytes);
	XCTAssertEqualObjects(WDDataFromBase64URL(WDBase64URL([@"ab" dataUsingEncoding:NSUTF8StringEncoding])),
	                      [@"ab" dataUsingEncoding:NSUTF8StringEncoding]);
	XCTAssertEqualObjects([WDJWTClaims(WDTestJWT(@{ @"sub": @"x" })) objectForKey:@"sub"], @"x");
	XCTAssertNil(WDJWTClaims(@"not a token"));
}

- (void)testSignsInWithPKCEThroughTheLoopback
{
	[self browseWith:^NSDictionary *(NSDictionary *request) {
		return @{ @"code": @"the-code", @"state": [request objectForKey:@"state"] };
	}];
	NSError *error = nil;
	XCTAssertTrue([_signIn signInWithIssuer:_issuer scopes:@[ @"Operations.Read" ] error:&error],
	              @"%@", error);
	XCTAssertEqualObjects(_signIn.accessToken, @"access-1");
	XCTAssertEqualObjects(_signIn.userName, @"ann");
	XCTAssertEqualObjects(_signIn.subject, @"u-17", @"who the server takes ann for");
	XCTAssertEqualObjects([_authorization objectForKey:@"response_type"], @"code");
	XCTAssertEqualObjects([_authorization objectForKey:@"code_challenge_method"], @"S256");
	XCTAssertEqualObjects([_authorization objectForKey:@"client_id"], @"desk");
	/* The provider's own parameters are kept. */
	XCTAssertEqualObjects([_authorization objectForKey:@"prompt"], @"login");
	XCTAssertEqualObjects([_authorization objectForKey:@"scope"], @"openid Operations.Read Tasks.Work offline_access");
	XCTAssertTrue([[_authorization objectForKey:@"redirect_uri"] hasPrefix:@"http://127.0.0.1:"]);
}

- (void)testRefreshesARefusedToken
{
	[self browseWith:^NSDictionary *(NSDictionary *request) {
		return @{ @"code": @"the-code", @"state": [request objectForKey:@"state"] };
	}];
	ODataSchemaAuthorization *authorization = [[ODataSchemaAuthorization alloc] init];
	authorization.kind = @"OpenIDConnect";
	authorization.issuerURL = _issuer;
	authorization.requiredScopes = @[];
	__block NSString *first = nil, *again = nil, *refreshed = nil;
	/* Off the main thread, as the store asks. */
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		@autoreleasepool {
			first = [self->_signIn accessTokenForAuthorization:authorization refresh:NO];
			again = [self->_signIn accessTokenForAuthorization:authorization refresh:NO];
			refreshed = [self->_signIn accessTokenForAuthorization:authorization refresh:YES];
		}
		dispatch_semaphore_signal(done);
	});
	XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)), 0L);
	XCTAssertEqualObjects(first, @"access-1");
	XCTAssertEqualObjects(again, @"access-1");
	XCTAssertEqualObjects(refreshed, @"access-2");
	XCTAssertEqualObjects([_provider.lastGrant objectForKey:@"grant_type"], @"refresh_token");
}

- (void)testTheProvidersRefusalIsAnError
{
	[self browseWith:^NSDictionary *(NSDictionary *request) {
		return @{ @"error": @"access_denied", @"error_description": @"The user said no",
		          @"state": [request objectForKey:@"state"] };
	}];
	NSError *error = nil;
	XCTAssertFalse([_signIn signInWithIssuer:_issuer scopes:nil error:&error]);
	XCTAssertEqual([error code], (NSInteger)WDSignInErrorRefused);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"The user said no"].location != NSNotFound,
	              @"%@", error);
	XCTAssertNil(_signIn.accessToken);
}

- (void)testAReturnForAnotherSignInIsRefused
{
	[self browseWith:^NSDictionary *(NSDictionary *request) {
		return @{ @"code": @"the-code", @"state": @"someone else's" };
	}];
	NSError *error = nil;
	XCTAssertFalse([_signIn signInWithIssuer:_issuer scopes:nil error:&error]);
	XCTAssertEqual([error code], (NSInteger)WDSignInErrorProtocol);
	XCTAssertEqual(_provider.tokens, (NSUInteger)0);
}

- (void)testCancelStopsTheWait
{
	_signIn.openURL = ^BOOL(NSURL *url) {
		return YES;
	};
	WDSignIn *signIn = _signIn;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
	               dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[signIn cancel];
	});
	NSError *error = nil;
	NSDate *started = [NSDate date];
	XCTAssertFalse([_signIn signInWithIssuer:_issuer scopes:nil error:&error]);
	XCTAssertEqual([error code], (NSInteger)WDSignInErrorCancelled);
	XCTAssertTrue([[NSDate date] timeIntervalSinceDate:started] < 10.0);
}

@end

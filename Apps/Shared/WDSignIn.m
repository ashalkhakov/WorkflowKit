#import "WDSignIn.h"
#if __has_include(<ODataKit/ODataTransport.h>)
#import <ODataKit/ODataTransport.h>
#import <ODataKit/ODataSchema.h>
#else
#import "ODataTransport.h"
#import "ODataSchema.h"
#endif
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#ifdef __APPLE__
#include <CommonCrypto/CommonDigest.h>
#else
#include <gnutls/gnutls.h>
#include <gnutls/crypto.h>
#endif

NSString * const WDSignInErrorDomain = @"WDSignInErrorDomain";

static NSError *
WDError(WDSignInError code, NSString *message)
{
	return [NSError errorWithDomain:WDSignInErrorDomain code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSData *
WDRandomBytes(NSUInteger count)
{
	NSMutableData *data = [NSMutableData dataWithLength:count];
#ifdef __APPLE__
	arc4random_buf([data mutableBytes], count);
#else
	gnutls_rnd(GNUTLS_RND_KEY, [data mutableBytes], count);
#endif
	return data;
}

NSString *
WDBase64URL(NSData *data)
{
	NSString *text = [data base64EncodedStringWithOptions:0];
	text = [text stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
	text = [text stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	return [text stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

NSData *
WDDataFromBase64URL(NSString *text)
{
	NSMutableString *base64 = [[text stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
	[base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, [base64 length])];
	while ([base64 length] % 4 != 0) {
		[base64 appendString:@"="];
	}
	return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

NSString *
WDCodeChallenge(NSString *verifier)
{
	NSData *bytes = [verifier dataUsingEncoding:NSASCIIStringEncoding];
	unsigned char digest[32];
#ifdef __APPLE__
	CC_SHA256([bytes bytes], (CC_LONG)[bytes length], digest);
#else
	gnutls_hash_fast(GNUTLS_DIG_SHA256, [bytes bytes], [bytes length], digest);
#endif
	return WDBase64URL([NSData dataWithBytes:digest length:sizeof digest]);
}

NSDictionary *
WDJWTClaims(NSString *token)
{
	NSArray *parts = [token componentsSeparatedByString:@"."];
	NSData *payload = [parts count] == 3 ? WDDataFromBase64URL([parts objectAtIndex:1]) : nil;
	id claims = payload != nil ? [NSJSONSerialization JSONObjectWithData:payload options:0 error:NULL] : nil;
	return [claims isKindOfClass:[NSDictionary class]] ? claims : nil;
}

/* application/x-www-form-urlencoded: all but the unreserved escaped. */
static NSString *
WDFormEncoded(NSDictionary *fields)
{
	NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
		@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
	NSMutableArray *pairs = [NSMutableArray array];
	for (NSString *name in [[fields allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSString *value = [fields objectForKey:name];
		[pairs addObject:[NSString stringWithFormat:@"%@=%@",
			[name stringByAddingPercentEncodingWithAllowedCharacters:unreserved],
			[value stringByAddingPercentEncodingWithAllowedCharacters:unreserved]]];
	}
	return [pairs componentsJoinedByString:@"&"];
}

static NSDictionary *
WDQueryItems(NSURLComponents *components)
{
	NSMutableDictionary *items = [NSMutableDictionary dictionary];
	for (NSURLQueryItem *item in [components queryItems]) {
		if ([item value] != nil) {
			[items setObject:[item value] forKey:[item name]];
		}
	}
	return items;
}

/* An exchange waited for. */
@interface WDExchangeWaiter : NSObject
@end

@implementation WDExchangeWaiter
{
	NSCondition *_condition;
	BOOL _done;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_condition = [[NSCondition alloc] init];
	}
	return self;
}

- (void)exchangeDidFinish:(ODataExchange *)exchange
{
	[_condition lock];
	_done = YES;
	[_condition signal];
	[_condition unlock];
}

- (void)wait
{
	[_condition lock];
	while (!_done) {
		[_condition wait];
	}
	[_condition unlock];
}

@end

/*
 * The redirect's end: one request to /callback on 127.0.0.1, answered
 * with a page that sends the user back to the app. Anything else the
 * browser asks for (a favicon) is answered 404.
 */
@interface WDLoopback : NSObject
@property (nonatomic, readonly) NSURL *redirectURL;
@property (atomic) BOOL cancelled;
- (BOOL)listen:(NSError **)error;
/* The callback's query, or nil when cancelled or out of time. */
- (NSDictionary *)waitForCallback:(NSTimeInterval)timeout error:(NSError **)error;
- (void)close;
@end

@implementation WDLoopback
{
	int _socket;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_socket = -1;
	}
	return self;
}

- (void)dealloc
{
	[self close];
}

- (void)close
{
	if (_socket >= 0) {
		close(_socket);
		_socket = -1;
	}
}

- (BOOL)listen:(NSError **)error
{
	_socket = socket(AF_INET, SOCK_STREAM, 0);
	struct sockaddr_in address;
	memset(&address, 0, sizeof address);
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address.sin_port = 0;
	socklen_t length = sizeof address;
	if (_socket < 0 || bind(_socket, (struct sockaddr *)&address, sizeof address) != 0
	    || listen(_socket, 4) != 0 || getsockname(_socket, (struct sockaddr *)&address, &length) != 0) {
		if (error != NULL) {
			*error = WDError(WDSignInErrorNetwork, [NSString stringWithFormat:
				@"Could not listen on 127.0.0.1 for the browser's return (%s).", strerror(errno)]);
		}
		[self close];
		return NO;
	}
	_redirectURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/callback",
		(unsigned)ntohs(address.sin_port)]];
	return YES;
}

/* Polls a while for fd to be readable, minding cancel. */
- (BOOL)waitForInput:(int)fd until:(NSDate *)deadline
{
	while (!self.cancelled && [deadline timeIntervalSinceNow] > 0) {
		struct pollfd ready = { fd, POLLIN, 0 };
		int count = poll(&ready, 1, 250);
		if (count > 0) {
			return YES;
		}
		if (count < 0 && errno != EINTR) {
			return NO;
		}
	}
	return NO;
}

static void
WDSend(int fd, NSString *status, NSString *body)
{
	NSData *content = [body dataUsingEncoding:NSUTF8StringEncoding];
	NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %@\r\nContent-Type: text/html; charset=utf-8\r\n"
		"Content-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",
		status, (unsigned long)[content length]];
	NSMutableData *response = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
	[response appendData:content];
	const char *bytes = [response bytes];
	size_t left = [response length];
	while (left > 0) {
#ifdef MSG_NOSIGNAL
		ssize_t sent = send(fd, bytes, left, MSG_NOSIGNAL);
#else
		ssize_t sent = send(fd, bytes, left, 0);
#endif
		if (sent <= 0) {
			break;
		}
		bytes += sent;
		left -= (size_t)sent;
	}
}

/* The page the browser shows once the app has the code. */
static NSString *
WDPage(NSString *title, NSString *text)
{
	NSXMLElement *html = [NSXMLElement elementWithName:@"html"];
	NSXMLElement *head = [NSXMLElement elementWithName:@"head"];
	[head addChild:[NSXMLElement elementWithName:@"title" stringValue:title]];
	[html addChild:head];
	NSXMLElement *body = [NSXMLElement elementWithName:@"body"];
	[body addAttribute:[NSXMLNode attributeWithName:@"style" stringValue:@"font-family: sans-serif; margin: 3em"]];
	[body addChild:[NSXMLElement elementWithName:@"h1" stringValue:title]];
	[body addChild:[NSXMLElement elementWithName:@"p" stringValue:text]];
	[html addChild:body];
	return [@"<!DOCTYPE html>\n" stringByAppendingString:[html XMLString]];
}

- (NSDictionary *)waitForCallback:(NSTimeInterval)timeout error:(NSError **)error
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while ([self waitForInput:_socket until:deadline]) {
		int client = accept(_socket, NULL, NULL);
		if (client < 0) {
			continue;
		}
#ifdef SO_NOSIGPIPE
		int on = 1;
		setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
#endif
		NSMutableData *request = [NSMutableData data];
		NSData *end = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
		NSDate *patience = [NSDate dateWithTimeIntervalSinceNow:10];
		while ([request length] < 16384
		       && [request rangeOfData:end options:0 range:NSMakeRange(0, [request length])].location == NSNotFound
		       && [self waitForInput:client until:patience]) {
			char buffer[2048];
			ssize_t count = recv(client, buffer, sizeof buffer, 0);
			if (count <= 0) {
				break;
			}
			[request appendBytes:buffer length:(NSUInteger)count];
		}
		NSString *text = [[NSString alloc] initWithData:request encoding:NSISOLatin1StringEncoding];
		NSArray *line = [[[text componentsSeparatedByString:@"\r\n"] firstObject] componentsSeparatedByString:@" "];
		NSURLComponents *target = [line count] >= 2
			? [NSURLComponents componentsWithString:[@"http://127.0.0.1" stringByAppendingString:[line objectAtIndex:1]]]
			: nil;
		if (![[line firstObject] isEqualToString:@"GET"] || ![[target path] isEqualToString:@"/callback"]) {
			WDSend(client, @"404 Not Found", WDPage(@"Not found", @"WorkflowDesk is waiting for a sign-in."));
			close(client);
			continue;
		}
		NSDictionary *query = WDQueryItems(target);
		if ([query objectForKey:@"error"] != nil) {
			WDSend(client, @"200 OK", WDPage(@"Not signed in", @"Return to WorkflowDesk to see why."));
		} else {
			WDSend(client, @"200 OK", WDPage(@"Signed in", @"You can close this page and return to WorkflowDesk."));
		}
		close(client);
		return query;
	}
	if (error != NULL) {
		*error = self.cancelled ? WDError(WDSignInErrorCancelled, @"Signing in was cancelled.")
		                        : WDError(WDSignInErrorTimedOut, @"The browser did not return in time.");
	}
	return nil;
}

@end

@implementation WDSignIn
{
	NSLock *_signingIn;
	NSURL *_issuer;
	NSDictionary *_discovery;
	NSString *_accessToken;
	NSString *_refreshToken;
	NSDictionary *_claims;
	WDLoopback *_loopback;
}

- (instancetype)initWithClientID:(NSString *)clientID
{
	if ((self = [super init])) {
		_clientID = [clientID copy];
		_scopes = @[];
		_timeout = 300;
		_signingIn = [[NSLock alloc] init];
	}
	return self;
}

- (id<ODataTransport>)transport
{
	return _transport ?: ODataDefaultTransport();
}

#pragma mark HTTP

/* A JSON object from the request, or nil and why. */
- (NSDictionary *)JSONFrom:(NSURLRequest *)request error:(NSError **)error
{
	WDExchangeWaiter *waiter = [[WDExchangeWaiter alloc] init];
	ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:request target:waiter
	                                                          action:@selector(exchangeDidFinish:)];
	[self.transport startExchange:exchange];
	[waiter wait];
	if (exchange.error != nil) {
		if (error != NULL) {
			*error = WDError(WDSignInErrorNetwork, [NSString stringWithFormat:@"%@: %@",
				[[request URL] host], [exchange.error localizedDescription]]);
		}
		return nil;
	}
	NSInteger status = [exchange.URLResponse isKindOfClass:[NSHTTPURLResponse class]]
		? [(NSHTTPURLResponse *)exchange.URLResponse statusCode] : 0;
	id json = exchange.data != nil ? [NSJSONSerialization JSONObjectWithData:exchange.data options:0 error:NULL] : nil;
	if (![json isKindOfClass:[NSDictionary class]]) {
		if (error != NULL) {
			*error = WDError(WDSignInErrorProtocol, [NSString stringWithFormat:
				@"%@ answered %ld without a JSON object.", [request URL], (long)status]);
		}
		return nil;
	}
	if (status < 200 || status >= 300 || [json objectForKey:@"error"] != nil) {
		if (error != NULL) {
			*error = [self refusal:json];
		}
		return nil;
	}
	return json;
}

- (NSError *)refusal:(NSDictionary *)answer
{
	NSString *code = [[answer objectForKey:@"error"] description] ?: @"refused";
	NSString *text = [answer objectForKey:@"error_description"];
	return WDError(WDSignInErrorRefused, [text isKindOfClass:[NSString class]] && [text length] > 0
		? [NSString stringWithFormat:@"%@ (%@)", text, code] : [NSString stringWithFormat:@"The sign-in was refused: %@.", code]);
}

/* The issuer's endpoints, from its discovery document (OIDC Discovery). */
- (NSDictionary *)discoveryOf:(NSURL *)issuer error:(NSError **)error
{
	@synchronized(self) {
		if (_discovery != nil && [_issuer isEqual:issuer]) {
			return _discovery;
		}
	}
	NSString *base = [issuer absoluteString];
	while ([base hasSuffix:@"/"]) {
		base = [base substringToIndex:[base length] - 1];
	}
	NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/.well-known/openid-configuration"]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	NSDictionary *discovery = [self JSONFrom:request error:error];
	if (discovery == nil) {
		return nil;
	}
	for (NSString *key in @[ @"authorization_endpoint", @"token_endpoint" ]) {
		if (![[discovery objectForKey:key] isKindOfClass:[NSString class]]) {
			if (error != NULL) {
				*error = WDError(WDSignInErrorProtocol, [NSString stringWithFormat:@"%@ names no %@.", url, key]);
			}
			return nil;
		}
	}
	@synchronized(self) {
		_issuer = [issuer copy];
		_discovery = discovery;
	}
	return discovery;
}

/* What the token endpoint gives for the grant: the tokens, kept. */
- (BOOL)token:(NSDictionary *)grant discovery:(NSDictionary *)discovery error:(NSError **)error
{
	NSMutableDictionary *fields = [grant mutableCopy];
	[fields setObject:_clientID forKey:@"client_id"];
	NSMutableURLRequest *request =
		[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[discovery objectForKey:@"token_endpoint"]]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[request setHTTPBody:[WDFormEncoded(fields) dataUsingEncoding:NSUTF8StringEncoding]];
	NSDictionary *answer = [self JSONFrom:request error:error];
	NSString *access = [answer objectForKey:@"access_token"];
	if (answer != nil && ![access isKindOfClass:[NSString class]]) {
		if (error != NULL) {
			*error = WDError(WDSignInErrorProtocol, @"The token endpoint gave no access token.");
		}
		return NO;
	}
	if (access == nil) {
		return NO;
	}
	NSString *refresh = [answer objectForKey:@"refresh_token"];
	NSString *identity = [answer objectForKey:@"id_token"];
	@synchronized(self) {
		_accessToken = [access copy];
		if ([refresh isKindOfClass:[NSString class]]) {
			_refreshToken = [refresh copy];
		}
		if ([identity isKindOfClass:[NSString class]]) {
			_claims = [WDJWTClaims(identity) copy];
		}
	}
	return YES;
}

#pragma mark Signing in

- (NSArray *)scopesWith:(NSArray *)required
{
	NSMutableArray *scopes = [NSMutableArray arrayWithObject:@"openid"];
	for (NSString *scope in [required arrayByAddingObjectsFromArray:_scopes]) {
		if (![scopes containsObject:scope]) {
			[scopes addObject:scope];
		}
	}
	return scopes;
}

- (BOOL)signInWithIssuer:(NSURL *)issuer scopes:(NSArray *)required error:(NSError **)error
{
	NSArray *scopes = [self scopesWith:required ?: @[]];
	NSDictionary *discovery = [self discoveryOf:issuer error:error];
	if (discovery == nil) {
		return NO;
	}
	WDLoopback *loopback = [[WDLoopback alloc] init];
	if (![loopback listen:error]) {
		return NO;
	}
	@synchronized(self) {
		_loopback = loopback;
	}
	NSString *verifier = WDBase64URL(WDRandomBytes(32));
	NSString *state = WDBase64URL(WDRandomBytes(16));
	NSURLComponents *authorize = [NSURLComponents componentsWithString:[discovery objectForKey:@"authorization_endpoint"]];
	NSMutableArray *items = [NSMutableArray arrayWithArray:[authorize queryItems] ?: @[]];
	NSDictionary *parameters = @{ @"response_type": @"code",
	                              @"client_id": _clientID,
	                              @"redirect_uri": [loopback.redirectURL absoluteString],
	                              @"scope": [scopes componentsJoinedByString:@" "],
	                              @"state": state,
	                              @"code_challenge": WDCodeChallenge(verifier),
	                              @"code_challenge_method": @"S256" };
	for (NSString *name in [[parameters allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		[items addObject:[NSURLQueryItem queryItemWithName:name value:[parameters objectForKey:name]]];
	}
	[authorize setQueryItems:items];
	/* A + in a query item is a space to a form decoder. */
	[authorize setPercentEncodedQuery:[[authorize percentEncodedQuery]
		stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]];

	BOOL (^open)(NSURL *) = self.openURL;
	NSDictionary *callback = nil;
	if (open == nil || !open([authorize URL])) {
		if (error != NULL) {
			*error = WDError(WDSignInErrorNetwork, @"The browser could not be opened to sign in.");
		}
	} else {
		callback = [loopback waitForCallback:_timeout error:error];
	}
	[loopback close];
	@synchronized(self) {
		_loopback = nil;
	}
	if (callback == nil) {
		return NO;
	}
	if ([callback objectForKey:@"error"] != nil) {
		if (error != NULL) {
			*error = [self refusal:callback];
		}
		return NO;
	}
	if (![[callback objectForKey:@"state"] isEqual:state] || [callback objectForKey:@"code"] == nil) {
		if (error != NULL) {
			*error = WDError(WDSignInErrorProtocol, @"The browser returned without this sign-in's state and code.");
		}
		return NO;
	}
	return [self token:@{ @"grant_type": @"authorization_code",
	                      @"code": [callback objectForKey:@"code"],
	                      @"redirect_uri": [loopback.redirectURL absoluteString],
	                      @"code_verifier": verifier }
	         discovery:discovery error:error];
}

- (void)cancel
{
	@synchronized(self) {
		_loopback.cancelled = YES;
	}
}

- (void)signOut
{
	@synchronized(self) {
		_accessToken = nil;
		_refreshToken = nil;
		_claims = nil;
	}
}

- (NSString *)userName
{
	NSDictionary *claims = self.claims;
	for (NSString *claim in @[ @"preferred_username", @"name", @"sub" ]) {
		id value = [claims objectForKey:claim];
		if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
			return value;
		}
	}
	return nil;
}

- (NSString *)subject
{
	id subject = [self.claims objectForKey:@"sub"];
	return [subject isKindOfClass:[NSString class]] ? subject : nil;
}

- (NSString *)accessToken
{
	@synchronized(self) {
		return _accessToken;
	}
}

- (NSDictionary *)claims
{
	@synchronized(self) {
		return _claims;
	}
}

#pragma mark ODataCredentialProviding

- (NSString *)accessTokenForAuthorization:(ODataSchemaAuthorization *)authorization refresh:(BOOL)refresh
{
	NSURL *issuer = authorization.issuerURL;
	NSString *stale = refresh ? self.accessToken : nil;
	/* One sign-in at a time; those waiting take its token. */
	[_signingIn lock];
	NSString *token = self.accessToken;
	if (token != nil && ![token isEqual:stale]) {
		[_signingIn unlock];
		return token;
	}
	if (issuer == nil) {
		@synchronized(self) {
			issuer = _issuer;
		}
	}
	if (issuer != nil) {
		NSDictionary *discovery = [self discoveryOf:issuer error:NULL];
		NSString *refreshToken;
		@synchronized(self) {
			refreshToken = _refreshToken;
		}
		if (discovery != nil && refreshToken != nil
		    && [self token:@{ @"grant_type": @"refresh_token", @"refresh_token": refreshToken } discovery:discovery error:NULL]) {
			token = self.accessToken;
		} else if (![NSThread isMainThread]) {
			[self signOut];
			token = [self signInWithIssuer:issuer scopes:authorization.requiredScopes error:NULL]
				? self.accessToken : nil;
		} else {
			token = nil;
		}
	}
	[_signingIn unlock];
	return token;
}

@end

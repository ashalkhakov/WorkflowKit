#import <Foundation/Foundation.h>
#if __has_include(<ODataIncrementalStore/ODataConfiguration.h>)
#import <ODataIncrementalStore/ODataConfiguration.h>
#else
#import "ODataConfiguration.h"
#endif

@protocol ODataTransport;

/*
 * Signing in to a service that takes OpenID Connect access tokens, as a
 * native app does (RFC 8252): the authorization code flow with PKCE
 * (RFC 7636), in the system browser, back to a loopback redirect, an HTTP
 * listener on 127.0.0.1 at a port of the moment. The client is public: it
 * has no secret, the code verifier stands in for one.
 *
 * As the store's credential provider it gives the token it has, refreshes
 * it when the service answers 401, and signs in when there is none -- on
 * the store's thread, which waits for the browser. Never on the main
 * thread, which the browser's return would need.
 */
@interface WDSignIn : NSObject <ODataCredentialProviding>

- (instancetype)initWithClientID:(NSString *)clientID;

@property (nonatomic, readonly, copy) NSString *clientID;
/* Asked for besides openid, and those the service requires. */
@property (nonatomic, copy) NSArray<NSString *> *scopes;
/* Shows the authorization page: the browser, in the app. */
@property (nonatomic, copy) BOOL (^openURL)(NSURL *url);
/* Discovery and the token endpoint. Default: ODataDefaultTransport(). */
@property (nonatomic, strong) id<ODataTransport> transport;
/* How long the browser has. Default: five minutes. */
@property (nonatomic) NSTimeInterval timeout;

/* Signs in at the issuer for openid, the scopes the service requires
 * and those above, and waits. */
- (BOOL)signInWithIssuer:(NSURL *)issuer scopes:(NSArray<NSString *> *)required error:(NSError **)error;
/* Stops a sign-in waiting for the browser; it fails as cancelled. */
- (void)cancel;
/* Forgets the tokens. */
- (void)signOut;

@property (nonatomic, readonly, copy) NSString *accessToken;
/* The ID token's claims, as the token endpoint gave them over TLS: who
 * signed in, to show. The service checks the access token itself. */
@property (nonatomic, readonly, copy) NSDictionary *claims;
/* preferred_username, else name, else sub: to show. */
@property (nonatomic, readonly, copy) NSString *userName;
/* sub: who the server takes the caller for, as tasks' assignees name them. */
@property (nonatomic, readonly, copy) NSString *subject;

@end

/* PKCE's S256: BASE64URL(SHA256(verifier)). */
NSString *WDCodeChallenge(NSString *verifier);
NSString *WDBase64URL(NSData *data);
NSData *WDDataFromBase64URL(NSString *text);
/* The claims of a JWT, unverified. */
NSDictionary *WDJWTClaims(NSString *token);

extern NSString * const WDSignInErrorDomain;
typedef NS_ENUM(NSInteger, WDSignInError) {
	WDSignInErrorCancelled = 1,
	WDSignInErrorTimedOut,
	/* The provider refused: its error and error_description. */
	WDSignInErrorRefused,
	/* Discovery or the token endpoint answered what it should not. */
	WDSignInErrorProtocol,
	WDSignInErrorNetwork,
};

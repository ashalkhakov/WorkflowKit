#import <AppKit/AppKit.h>

@class WDSession, WDSignIn;

/* Which server: its service root, and the client ID the app has at the
 * identity provider, for a server that asks for a sign-in. The fields
 * bind to the properties here, remembered in the user defaults. Shared by
 * WorkflowDesk and WorkflowDesigner. */
@interface WDConnectWindowController : NSWindowController

/* Called on the main queue with the session open, signed in where the
 * server asks for it. */
- (instancetype)initWithCompletion:(void (^)(WDSession *session, WDSignIn *signIn))completion;

@property (nonatomic, copy) NSString *serviceAddress;
@property (nonatomic, copy) NSString *clientID;
@property (nonatomic, copy) NSString *status;
@property (nonatomic) BOOL idle;

@property (nonatomic, strong) IBOutlet NSProgressIndicator *progress;

- (IBAction)connect:(id)sender;
- (IBAction)cancel:(id)sender;

@end

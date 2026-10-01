#import <AppKit/AppKit.h>

@class WDSession, WKDDocument;

/*
 * The designer's server: one connection for every window, made through
 * WorkflowDesk's connect window and session (Apps/Shared). What needs it --
 * deploying, opening a deployed process -- asks for it, and the connect
 * window comes first when there is none yet.
 */
@interface WKDAppDelegate : NSObject <NSApplicationDelegate>

+ (WKDAppDelegate *)shared;

@property (nonatomic, readonly, strong) WDSession *session;
/* The block with the session, connecting first when there is none. */
- (void)withSession:(void (^)(WDSession *session))block;

/* A process as text -- from the server -- as a new document named so. */
- (WKDDocument *)openDocumentWithXML:(NSString *)xml title:(NSString *)title
                         resourceName:(NSString *)resourceName error:(NSError **)error;

- (IBAction)connect:(id)sender;
- (IBAction)openFromServer:(id)sender;

@end

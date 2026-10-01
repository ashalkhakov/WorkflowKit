#import <AppKit/AppKit.h>

@class WDSession, WDSignIn;

/*
 * WorkflowDesk: a WorkflowKit server's work, through its OData API.
 *
 *   WDConnectWindowController  which server, and signing in to it
 *   WDTasksWindowController    the task list: claim, open a task's form,
 *                              start a process
 *   WDFormWindowController     a form, rendered by XFormsKit, submitted
 *   WDOperationsWindowController
 *                              definitions, their running instances, and
 *                              what each is doing: variables, activities,
 *                              incidents, jobs
 *
 * WDSession holds the server's rows as Core Data has them; WDSignIn signs
 * in with OpenID Connect where the server asks for it.
 */
@interface WDAppDelegate : NSObject <NSApplicationDelegate, NSUserInterfaceValidations>

@property (nonatomic, readonly, strong) WDSession *session;
@property (nonatomic, readonly, strong) WDSignIn *signIn;

/* What the connect window calls once it has a session open. */
- (void)didOpenSession:(WDSession *)session signIn:(WDSignIn *)signIn;

- (IBAction)connect:(id)sender;
- (IBAction)signOut:(id)sender;
- (IBAction)showTasks:(id)sender;
- (IBAction)showOperations:(id)sender;

@end

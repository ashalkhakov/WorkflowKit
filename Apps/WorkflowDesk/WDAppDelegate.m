#import "WDAppDelegate.h"
#import "WDConnectWindowController.h"
#import "WDOperationsWindowController.h"
#import "WDSession.h"
#import "WDSignIn.h"
#import "WDTasksWindowController.h"
#import "WDTracing.h"

@implementation WDAppDelegate
{
	WDConnectWindowController *_connect;
	WDTasksWindowController *_tasks;
	WDOperationsWindowController *_operations;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
	WDStartTracing();
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	WDStopTracing();
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	[self connect:self];
	/* An address on the command line, -WDServiceAddress URL: connected
	 * to straight away. */
	NSDictionary *arguments = [[NSUserDefaults standardUserDefaults] volatileDomainForName:NSArgumentDomain];
	if ([arguments objectForKey:@"WDServiceAddress"] != nil) {
		[_connect connect:self];
	}
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application
{
	return YES;
}

/* The windows of a session, gone with it. */
- (void)closeSession
{
	[_tasks close];
	[_operations close];
	_tasks = nil;
	_operations = nil;
	[_session close];
	_session = nil;
}

- (IBAction)connect:(id)sender
{
	if (_connect == nil) {
		__weak WDAppDelegate *weakSelf = self;
		_connect = [[WDConnectWindowController alloc] initWithCompletion:^(WDSession *session, WDSignIn *signIn) {
			[weakSelf didOpenSession:session signIn:signIn];
		}];
	}
	[_connect showWindow:sender];
}

- (void)didOpenSession:(WDSession *)session signIn:(WDSignIn *)signIn
{
	[self closeSession];
	_session = session;
	_signIn = signIn;
	/* The tasks first: the app ends with its last window. */
	[self showTasks:self];
	[_connect close];
}

- (IBAction)signOut:(id)sender
{
	[_signIn signOut];
	_signIn = nil;
	[self closeSession];
	[self connect:sender];
}

- (IBAction)showTasks:(id)sender
{
	if (_session == nil) {
		return;
	}
	if (_tasks == nil) {
		_tasks = [[WDTasksWindowController alloc] initWithSession:_session userId:_signIn.subject
		                                                 userName:_signIn.userName];
	}
	[_tasks showWindow:sender];
}

- (IBAction)showOperations:(id)sender
{
	if (_session == nil) {
		return;
	}
	if (_operations == nil) {
		_operations = [[WDOperationsWindowController alloc] initWithSession:_session];
	}
	[_operations showWindow:sender];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	SEL action = [item action];
	if (action == @selector(showTasks:) || action == @selector(showOperations:)) {
		return _session != nil;
	}
	if (action == @selector(signOut:)) {
		return _session != nil;
	}
	return YES;
}

@end

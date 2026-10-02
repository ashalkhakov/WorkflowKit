#import "WKDAppDelegate.h"
#import "WKDDocument.h"
#import "WKDServerProcessesController.h"
#import "WDConnectWindowController.h"
#import "WDSession.h"
#import "WDTracing.h"
#import "XFormsDesignKit.h"

@implementation WKDAppDelegate
{
	WDConnectWindowController *_connect;
	WKDServerProcessesController *_processes;
	NSMutableArray *_waiting;
}

+ (WKDAppDelegate *)shared
{
	return (WKDAppDelegate *)[NSApp delegate];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
	WDStartTracing();
	/* The form editor's menu, after Diagram: its items act on the form
	 * window that is key. */
	NSMenu *menu = [NSApp mainMenu];
	NSInteger diagram = [menu indexOfItemWithTitle:@"Diagram"];
	[menu insertItem:[XFDDocument formMenuItem] atIndex:diagram >= 0 ? diagram + 1 : [menu numberOfItems]];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	WDStopTracing();
}

- (void)withSession:(void (^)(WDSession *session))block
{
	if (_session != nil) {
		block(_session);
		return;
	}
	if (_waiting == nil) {
		_waiting = [NSMutableArray array];
	}
	[_waiting addObject:[block copy]];
	[self connect:self];
}

- (IBAction)connect:(id)sender
{
	if (_connect == nil) {
		__weak WKDAppDelegate *weakSelf = self;
		_connect = [[WDConnectWindowController alloc] initWithCompletion:^(WDSession *session, WDSignIn *signIn) {
			[weakSelf didConnect:session];
		}];
	}
	[_connect showWindow:sender];
}

- (void)didConnect:(WDSession *)session
{
	[_session close];
	_session = session;
	_processes = nil;
	[_connect close];
	NSArray *waiting = _waiting;
	_waiting = nil;
	for (void (^block)(WDSession *) in waiting) {
		block(session);
	}
}

- (IBAction)openFromServer:(id)sender
{
	[self withSession:^(WDSession *session) {
		if (self->_processes == nil) {
			self->_processes = [[WKDServerProcessesController alloc] initWithSession:session];
		}
		[self->_processes showWindow:self];
		[self->_processes refresh:self];
	}];
}

- (WKDDocument *)openDocumentWithXML:(NSString *)xml title:(NSString *)title
                         resourceName:(NSString *)resourceName error:(NSError **)error
{
	NSDocumentController *documents = [NSDocumentController sharedDocumentController];
	WKDDocument *document = [[WKDDocument alloc] init];
	if (![document readFromData:[xml dataUsingEncoding:NSUTF8StringEncoding] ofType:[documents defaultType]
	                      error:error]) {
		return nil;
	}
	[document setFileType:[documents defaultType]];
	document.serverTitle = title;
	document.resourceName = resourceName;
	[documents addDocument:document];
	[document makeWindowControllers];
	[document showWindows];
	return document;
}

@end

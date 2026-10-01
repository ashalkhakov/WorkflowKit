#import <AppKit/AppKit.h>

@class WDSession;

/*
 * The task list: the tasks the server shows the user -- theirs, and those
 * offered to them -- through one NSArrayController and the bindings in
 * TasksWindow.xib. Show and the search field filter it in place; Claim,
 * Unclaim and Open act on the selection, and Start Process starts one of
 * the processes the user may start, with its start form when it has one.
 */
@interface WDTasksWindowController : NSWindowController <NSTableViewDelegate>

/* userId: the assignee the user's tasks have, where known; userName: to
 * show. */
- (instancetype)initWithSession:(WDSession *)session userId:(NSString *)userId userName:(NSString *)userName;

@property (nonatomic, strong) IBOutlet NSArrayController *tasks;
@property (nonatomic, strong) IBOutlet NSTableView *tableView;
@property (nonatomic, strong) IBOutlet NSSearchField *searchField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *showPopUp;
@property (nonatomic, strong) IBOutlet NSProgressIndicator *progress;

/* Start Process's sheet. */
@property (nonatomic, strong) IBOutlet NSWindow *startSheet;
@property (nonatomic, strong) IBOutlet NSArrayController *definitions;
@property (nonatomic, copy) NSString *businessKey;

@property (nonatomic, copy) NSString *status;
@property (nonatomic) BOOL canClaim;
@property (nonatomic) BOOL canUnclaim;
@property (nonatomic) BOOL canOpen;

- (IBAction)refresh:(id)sender;
- (IBAction)filterChanged:(id)sender;
- (IBAction)claim:(id)sender;
- (IBAction)unclaim:(id)sender;
- (IBAction)openTask:(id)sender;

- (IBAction)startProcess:(id)sender;
- (IBAction)startSelectedDefinition:(id)sender;
- (IBAction)cancelStart:(id)sender;

@end

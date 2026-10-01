#import <AppKit/AppKit.h>

@class WDSession;

/* File ▸ Open from Server: the process definitions deployed on the
 * server, every version. Opening one reads its BPMN as deployed --
 * Bpmn() -- into a new, unsaved document. */
@interface WKDServerProcessesController : NSWindowController

- (instancetype)initWithSession:(WDSession *)session;

@property (nonatomic, weak) IBOutlet NSTableView *table;
@property (nonatomic, weak) IBOutlet NSProgressIndicator *progress;
@property (nonatomic, strong) IBOutlet NSArrayController *definitions;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, readonly) BOOL definitionSelected;

- (IBAction)refresh:(id)sender;
- (IBAction)open:(id)sender;

@end

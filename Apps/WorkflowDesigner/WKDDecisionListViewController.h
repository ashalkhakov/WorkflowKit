#import <AppKit/AppKit.h>
#import "WKDDecisionEditor.h"

/*
 * The file's decisions, from WKDDecisionList.xib: one listed a row, the
 * one chosen selected; a row selected is the one chosen. With + Table,
 * + Literal and - under it, the Decision menu's first actions.
 */
#if defined(__APPLE__)
@interface WKDDecisionListViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
#else
@interface WKDDecisionListViewController : NSViewController
#endif

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor;
@property (nonatomic, readonly, strong) WKDDecisionEditor *decisionEditor;

@property (nonatomic, strong) IBOutlet NSTableView *tableView;
/* A decision added: its name to be typed. */
@property (nonatomic, copy) void (^added)(void);

- (IBAction)addDecisionTable:(id)sender;
- (IBAction)addLiteralDecision:(id)sender;
- (IBAction)deleteDecision:(id)sender;

@end

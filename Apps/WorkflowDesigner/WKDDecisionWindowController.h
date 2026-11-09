#import <AppKit/AppKit.h>
#import "WKDDecisionEditor.h"
#import "WKDDecisionListViewController.h"
#import "WKDDecisionDetailViewController.h"
#import "WKDRuleGridViewController.h"
#import "WKDColumnViewController.h"
#import "WKDLiteralViewController.h"

/*
 * A DMN document's window, from DecisionWindow.xib: its decisions listed
 * on the left, and on the right the one chosen -- its name, id and the
 * decisions it requires, and either its decision table, with the column
 * chosen under it, or its literal expression. It puts the parts in their
 * places and nothing more: each follows the document's decision editor,
 * and the Decision menu's actions are the list's and the grid's, in its
 * responder chain.
 */
@interface WKDDecisionWindowController : NSWindowController <NSSplitViewDelegate, NSWindowDelegate>

- (instancetype)init;
/* The decision, selected in the list. */
- (void)showDecision:(NSString *)decisionId;

@property (nonatomic, strong) IBOutlet NSSplitView *split;
@property (nonatomic, strong) IBOutlet NSView *listHost;
@property (nonatomic, strong) IBOutlet NSView *detailHost;
@property (nonatomic, strong) IBOutlet NSView *tablePanel;
@property (nonatomic, strong) IBOutlet NSView *gridHost;
@property (nonatomic, strong) IBOutlet NSView *columnHost;
@property (nonatomic, strong) IBOutlet NSView *literalHost;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;

/* The parts, once the window has loaded. */
@property (nonatomic, readonly, strong) WKDDecisionListViewController *listController;
@property (nonatomic, readonly, strong) WKDDecisionDetailViewController *detailController;
@property (nonatomic, readonly, strong) WKDRuleGridViewController *gridController;
@property (nonatomic, readonly, strong) WKDColumnViewController *columnController;
@property (nonatomic, readonly, strong) WKDLiteralViewController *literalController;

/* Server ▸ Deploy: the file, on its own, to the server connected. */
- (IBAction)deploy:(id)sender;

@end

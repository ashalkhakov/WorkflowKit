#import <AppKit/AppKit.h>

/*
 * A DMN document's window: its decisions listed on the left, and on the
 * right the one selected -- its name, id and the decisions it requires,
 * and either its decision table or its literal expression.
 *
 * A table is a grid as DMN draws one: a row per rule, its inputs' columns,
 * then its outputs', then the rule's annotation; the hit policy's letter
 * heads the rule numbers. A cell is typed in place, coloured and checked
 * as the engine reads it -- unary tests for an input, FEEL for an output.
 * Under the grid, the column last clicked: its label, expression, type,
 * and an input's variable or an output's name. Each edit is one undoable
 * change.
 *
 * The window is made in code rather than a XIB: the grid's columns are
 * the table's.
 */
@interface WKDDecisionWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate,
                                                            NSTextFieldDelegate, NSSplitViewDelegate, NSWindowDelegate>

- (instancetype)init;
/* The decision, selected in the list. */
- (void)showDecision:(NSString *)decisionId;

/* The Decision menu, which acts on the decisions window that is key. */
+ (NSMenuItem *)decisionMenuItem;

- (IBAction)addDecisionTable:(id)sender;
- (IBAction)addLiteralDecision:(id)sender;
- (IBAction)deleteDecision:(id)sender;
/* A rule after the selected one, or at the end. */
- (IBAction)addRule:(id)sender;
/* Edit ▸ Duplicate: the selected rule, again, after it. */
- (IBAction)duplicate:(id)sender;
/* Edit ▸ Delete, and Backspace in the grid: the selected rules. */
- (IBAction)delete:(id)sender;
- (IBAction)moveRuleUp:(id)sender;
- (IBAction)moveRuleDown:(id)sender;
/* A column after the current one of its kind, or at the end. */
- (IBAction)addInput:(id)sender;
- (IBAction)addOutput:(id)sender;
- (IBAction)deleteColumn:(id)sender;
- (IBAction)moveColumnLeft:(id)sender;
- (IBAction)moveColumnRight:(id)sender;
/* Server ▸ Deploy: the file, on its own, to the server connected. */
- (IBAction)deploy:(id)sender;

@end

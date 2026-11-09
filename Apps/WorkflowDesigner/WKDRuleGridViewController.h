#import <AppKit/AppKit.h>
#import "WKDDecisionEditor.h"
#import "WKDTableRowController.h"

/* The grid: Backspace or Delete removes the selected rules. */
@interface WKDRuleTable : WKDCellTable
@end

/*
 * The chosen decision's table, from WKDRuleGrid.xib: a grid as DMN draws
 * one -- a row per rule, its inputs' columns, then its outputs', then the
 * rule's annotation; the hit policy's letter heads the rule numbers -- its
 * columns made from the table's, a cell typed in place, coloured and
 * checked as the engine reads it; a column clicked is the one chosen. With
 * the rules' and the columns' buttons under it, the Decision menu's other
 * actions.
 */
#if defined(__APPLE__)
@interface WKDRuleGridViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
#else
@interface WKDRuleGridViewController : NSViewController
#endif

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor;
@property (nonatomic, readonly, strong) WKDDecisionEditor *decisionEditor;

@property (nonatomic, strong) IBOutlet WKDRuleTable *grid;

/* Told, as an entry is typed, why the engine would not read it. */
@property (nonatomic, copy) void (^explained)(NSString *problem);
/* A column added: its settings to be typed. */
@property (nonatomic, copy) void (^columnAdded)(BOOL output);

/* A rule after the selected one, or at the end. */
- (IBAction)addRule:(id)sender;
/* Edit ▸ Duplicate: the selected rule, again, after it. */
- (IBAction)duplicate:(id)sender;
/* Edit ▸ Delete, and Backspace in the grid: the selected rules. */
- (IBAction)delete:(id)sender;
- (IBAction)moveRuleUp:(id)sender;
- (IBAction)moveRuleDown:(id)sender;
/* A column after the chosen one of its kind, or at the end. */
- (IBAction)addInput:(id)sender;
- (IBAction)addOutput:(id)sender;
- (IBAction)deleteColumn:(id)sender;
- (IBAction)moveColumnLeft:(id)sender;
- (IBAction)moveColumnRight:(id)sender;

@end

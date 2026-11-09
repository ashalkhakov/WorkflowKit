#import <AppKit/AppKit.h>
#import "WKDDecisionEditor.h"

/*
 * The decision chosen, from WKDDecisionDetail.xib: its name, its id, a
 * table's hit policy, and the decisions it requires, a menu of them to
 * check. Each change one change.
 */
@interface WKDDecisionDetailViewController : NSViewController

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor;
@property (nonatomic, readonly, strong) WKDDecisionEditor *decisionEditor;

@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSTextField *idField;
@property (nonatomic, strong) IBOutlet NSTextField *hitPolicyLabel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *hitPolicy;
@property (nonatomic, strong) IBOutlet NSPopUpButton *requires;

/* Told why a change was refused: a taken id, a cycle of requirements. */
@property (nonatomic, copy) void (^refused)(NSString *reason);

- (IBAction)nameChanged:(id)sender;
- (IBAction)idChanged:(id)sender;
- (IBAction)hitPolicyChanged:(id)sender;
/* A requirement menu's item (its represented object a decision's id). */
- (IBAction)requirementToggled:(id)sender;

@end

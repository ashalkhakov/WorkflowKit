#import <AppKit/AppKit.h>
#import "WKDDecisionEditor.h"

@class WKDExpressionField;

/* A type pop-up's items -- Any, then the types the engine knows, and one
 * it does not as the file has it -- that one chosen; and what is chosen,
 * nil for Any. */
void WKDFillTypes(NSPopUpButton *popup, NSString *typeRef);
NSString *WKDChosenType(NSPopUpButton *popup);

/*
 * The column chosen in the grid, from WKDColumn.xib: its label, an input's
 * expression and variable or an output's name, and its type. Each change
 * one change.
 */
@interface WKDColumnViewController : NSViewController

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor;
@property (nonatomic, readonly, strong) WKDDecisionEditor *decisionEditor;

@property (nonatomic, strong) IBOutlet NSTextField *titleLabel;
@property (nonatomic, strong) IBOutlet NSTextField *labelField;
@property (nonatomic, strong) IBOutlet NSTextField *expressionLabel;
@property (nonatomic, strong) IBOutlet WKDExpressionField *expressionField;
@property (nonatomic, strong) IBOutlet NSTextField *nameLabel;
@property (nonatomic, strong) IBOutlet NSTextField *outputNameField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *typePopup;
@property (nonatomic, strong) IBOutlet NSTextField *variableLabel;
@property (nonatomic, strong) IBOutlet NSTextField *inputVariableField;
@property (nonatomic, strong) IBOutlet NSTextField *labelLabel;
@property (nonatomic, strong) IBOutlet NSTextField *typeLabel;

/* Told, as the expression is typed, why the engine would not read it. */
@property (nonatomic, copy) void (^explained)(NSString *problem);

/* The field to type in first: an output's name, an input's expression. */
- (void)focus;

- (IBAction)columnLabelChanged:(id)sender;
- (IBAction)columnNameChanged:(id)sender;
- (IBAction)columnTypeChanged:(id)sender;
- (IBAction)columnVariableChanged:(id)sender;

@end

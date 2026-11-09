#import <AppKit/AppKit.h>
#import "WKDDecisionEditor.h"

@class WKDExpressionField;

/*
 * The chosen decision when it is a literal expression, from
 * WKDLiteral.xib: the variable it gives and its type, and the expression,
 * coloured and checked as the engine reads it. Each change one change.
 */
@interface WKDLiteralViewController : NSViewController

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor;
@property (nonatomic, readonly, strong) WKDDecisionEditor *decisionEditor;

@property (nonatomic, strong) IBOutlet NSTextField *variableField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *variableType;
@property (nonatomic, strong) IBOutlet WKDExpressionField *literalField;

/* Told, as the expression is typed, why the engine would not read it. */
@property (nonatomic, copy) void (^explained)(NSString *problem);

- (IBAction)variableChanged:(id)sender;
- (IBAction)variableTypeChanged:(id)sender;

@end

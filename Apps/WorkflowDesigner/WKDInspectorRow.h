#import <AppKit/AppKit.h>
#import "WKDElementModel.h"

/*
 * One row of the inspector, from the XIB of its kind -- WKDRowText,
 * WKDRowExpression, WKDRowLongText, WKDRowCheck, WKDRowChoice,
 * WKDRowButton, WKDRowTable, and a section's title, WKDRowTitle -- its
 * control bound to its property's key in the section's element model.
 * A field writes when it is left or Return is pressed, a check box or a
 * pop-up when it is used: one change each.
 */
@interface WKDInspectorRow : NSObject

/* The row for the property, its XIB loaded with it as owner. */
+ (instancetype)rowForProperty:(WKDProperty *)property model:(WKDElementModel *)model;
/* A section's title. */
+ (instancetype)titleRow:(NSString *)title;

@property (nonatomic, readonly, strong) WKDProperty *property;
@property (nonatomic, readonly, strong) WKDElementModel *model;
@property (nonatomic, readonly, copy) NSString *key;

@property (nonatomic, strong) IBOutlet NSView *view;
@property (nonatomic, strong) IBOutlet NSTextField *label;
/* The field, the check box, the pop-up, the button, the text view, the
 * expression field. */
@property (nonatomic, strong) IBOutlet id control;

/* Told, as an expression is typed, why the engine would not read it; nil
 * once it would, or once the field is left. */
@property (nonatomic, copy) void (^explained)(NSString *problem);

/* Its bindings undone: before it goes. */
- (void)unbind;

@end

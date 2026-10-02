#import <Foundation/Foundation.h>
#if __has_include(<WorkflowKit/WFFeel.h>)
#import <WorkflowKit/WFFeel.h>
#else
#import "WFFeel.h"
#endif

@class WKDEditor;

/*
 * What the inspector shows of an element, declared once per property: where
 * its value lives in the BPMN XML -- an attribute, camunda:assignee; a
 * child's text, a flow's condition; an extension element, the retry cycle; a
 * reference, a message by its name -- how to read it, and how to write it as
 * one undoable change. The inspector builds its rows from these and nothing
 * else, so a property added here is a row there; and they are tested without
 * a window.
 *
 * Values are text throughout: a check box's is "true" or "false", a
 * choice's one of its values.
 */

typedef NS_ENUM(NSInteger, WKDPropertyKind) {
	WKDPropertyText,
	/* Several lines: documentation. */
	WKDPropertyLongText,
	WKDPropertyCheck,
	WKDPropertyChoice,
};

@interface WKDProperty : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic) WKDPropertyKind kind;
/* A choice's values, and what each is called; the first is the default. */
@property (nonatomic, copy) NSArray<NSString *> *values;
@property (nonatomic, copy) NSArray<NSString *> *titles;
/* Shown in an empty text field: what leaving it empty means. */
@property (nonatomic, copy) NSString *placeholder;
/* A text the engine reads as an expression -- a condition -- or as
 * literal text unless it is marked as one -- camunda:assignee: what the
 * inspector colours and checks as it is typed, at that place. */
@property (nonatomic) BOOL holdsExpression;
@property (nonatomic) WFExpressionPlace place;
/* The value now, for the element of that id. */
- (NSString *)valueIn:(WKDEditor *)editor of:(NSString *)elementId;
/* A new value: one change, or nothing when it is the value already. NO,
 * with why, when it is refused -- an id that is taken. */
- (BOOL)setValue:(NSString *)value in:(WKDEditor *)editor of:(NSString *)elementId error:(NSString **)reason;
@end

@interface WKDSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<WKDProperty *> *properties;
@end

/* The sections for the element of that id: a node, a flow, the process. */
NSArray<WKDSection *> *WKDSectionsFor(WKDEditor *editor, NSString *elementId);

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
	/* A list of entries, a row each in a table: input parameters,
	 * listeners, a call activity's variables, a delegate's fields. */
	WKDPropertyTable,
};

/* A table's column: text, a choice or a check box, as a property's value is. */
@interface WKDColumn : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic) WKDPropertyKind kind;
@property (nonatomic, copy) NSArray<NSString *> *values;
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic) BOOL holdsExpression;
@property (nonatomic) WFExpressionPlace place;
/* Of the table's width. */
@property (nonatomic) double share;
@end

/* A table's row: its values, a column each, and which entry it was read
 * from -- its index among the entries, NSNotFound for a row being added --
 * so that writing the rows changes only what changed: an entry written in
 * a form the table does not show (a camunda:list) stays as it is. */
@interface WKDRow : NSObject
@property (nonatomic) NSUInteger source;
@property (nonatomic, copy) NSArray<NSString *> *values;
+ (instancetype)rowWithValues:(NSArray<NSString *> *)values;
@end

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

/* A table's: its columns, what a new row holds, and a table of what each
 * of its rows holds in turn -- a listener's fields -- or nil. */
@property (nonatomic, copy) NSArray<WKDColumn *> *columns;
@property (nonatomic, copy) NSArray<NSString *> *blankRow;
@property (nonatomic, strong) WKDProperty *detail;
/* The rows now: of the element's entries, or, for a detail, of the entries
 * of the master table's row from master (NSNotFound for the element's). */
- (NSArray<WKDRow *> *)rowsIn:(WKDEditor *)editor of:(NSString *)elementId master:(NSUInteger)master;
/* The rows as they are to be -- edited, added, removed, reordered: one
 * change, or nothing when they are as they were. */
- (BOOL)setRows:(NSArray<WKDRow *> *)rows in:(WKDEditor *)editor of:(NSString *)elementId
         master:(NSUInteger)master error:(NSString **)reason;
@end

@interface WKDSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<WKDProperty *> *properties;
@end

/* The sections for the element of that id: a node, a flow, the process. */
NSArray<WKDSection *> *WKDSectionsFor(WKDEditor *editor, NSString *elementId);

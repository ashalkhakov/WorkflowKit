#import <AppKit/AppKit.h>

@class WKDEditor, WKDProperty;

/* A table whose cells Return ends the editing of, as in a field, rather
 * than going on to the next row's cell (gnustep-gui's way). */
@interface WKDCellTable : NSTableView
@end

/*
 * A table property in the inspector: its rows in a table, a cell each
 * column -- text, an expression coloured as the engine reads it, a
 * pop-up for a choice -- with + and - under it, and for a table whose
 * rows hold a table of their own (a listener's fields) that table under
 * it, for the row selected. Editing a cell, adding a row and removing one
 * are each one undoable change.
 */
@interface WKDTableEditor : NSView

- (instancetype)initWithFrame:(NSRect)frame property:(WKDProperty *)property;
@property (nonatomic, readonly, strong) WKDProperty *property;
@property (nonatomic, strong) WKDEditor *editor;
@property (nonatomic, copy) NSString *elementId;
/* As the inspector's: why a change was refused; an expression's problem
 * as it is typed. */
@property (nonatomic, copy) void (^refused)(NSString *reason);
@property (nonatomic, copy) void (^explained)(NSString *problem);

/* The rows read again, unless a cell is being typed in. */
- (void)reload;
/* Whether a cell is being typed in. */
@property (nonatomic, readonly, getter=isEditing) BOOL editing;

/* How tall it is for the property: its table, its buttons, and its
 * detail's. */
+ (double)heightFor:(WKDProperty *)property;

@end

#import <AppKit/AppKit.h>
#import "WKDTableModel.h"

/* A table whose cells Return ends the editing of, as in a field, rather
 * than going on to the next row's cell (gnustep-gui's way). */
@interface WKDCellTable : NSTableView
@end

/*
 * A table property in the inspector, from WKDRowTable.xib: its title, its
 * rows in a table -- the arranged objects of an array controller whose
 * content is the table model's rows -- a column each of the property's,
 * made as the property has them: text, an expression coloured as the
 * engine reads it, a pop-up for a choice, a check box; with + and - under
 * it. Editing a cell, adding a row and removing one are each one change.
 */
#if defined(__APPLE__)
@interface WKDTableRowController : NSObject <NSTableViewDataSource, NSTableViewDelegate>
#else
@interface WKDTableRowController : NSObject
#endif

- (instancetype)initWithTableModel:(WKDTableModel *)tableModel title:(NSString *)title;
/* What it shows: set anew for a detail, as another row is selected. */
@property (nonatomic, strong) WKDTableModel *tableModel;
@property (nonatomic, copy) NSString *title;

@property (nonatomic, strong) IBOutlet NSView *view;
@property (nonatomic, strong) IBOutlet NSTextField *label;
@property (nonatomic, strong) IBOutlet NSTableView *tableView;
@property (nonatomic, strong) IBOutlet NSArrayController *rows;
@property (nonatomic, strong) IBOutlet NSButton *addButton;
@property (nonatomic, strong) IBOutlet NSButton *removeButton;
@property (nonatomic, strong) IBOutlet NSTextField *emptyLabel;

/* A row selected; -1 for none. */
@property (nonatomic, copy) void (^selectionChanged)(NSInteger row);
/* As the inspector's: an expression's problem as it is typed. */
@property (nonatomic, copy) void (^explained)(NSString *problem);

- (IBAction)addRow:(id)sender;
- (IBAction)removeRow:(id)sender;
/* Its bindings undone: before it goes. */
- (void)unbind;

@end

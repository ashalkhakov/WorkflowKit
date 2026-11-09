#import <Foundation/Foundation.h>
#import "WKDProperties.h"

@class WKDTableModel;

/* A table's row, its values under the columns' keys -- c0, c1, ... -- as a
 * view binds to them: a text a string, a check box a boolean number, a
 * choice the index of its value. Set, one change. */
@interface WKDTableItem : NSObject
@property (nonatomic, readonly, weak) WKDTableModel *table;
@property (nonatomic, readonly, strong) WKDRow *row;
@end

/*
 * A table property's rows for one element -- input parameters, listeners,
 * a delegate's fields -- as an array controller's content: rows, each a
 * WKDTableItem. A cell set, a row added, removed: each one change through
 * the property's descriptor (WKDProperties), and the rows read again. A
 * row's own tables (a listener's fields) are table models of their own,
 * for that row.
 */
@interface WKDTableModel : NSObject

- (instancetype)initWithEditor:(WKDEditor *)editor elementId:(NSString *)elementId property:(WKDProperty *)property
                        master:(NSUInteger)master;
@property (nonatomic, readonly, strong) WKDEditor *editor;
@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, strong) WKDProperty *property;
/* For a detail: the master's row its entries are in; NSNotFound for the
 * property's own table. */
@property (nonatomic, readonly) NSUInteger master;

@property (nonatomic, readonly, copy) NSArray<WKDTableItem *> *rows;
/* c0, c1, ...: the columns' keys, as the property's columns go. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *columnKeys;

/* Told why a change was refused; nil once one is taken. */
@property (nonatomic, copy) void (^refused)(NSString *reason);
/* A cell being typed in: the rows are not read again until it is left. */
@property (nonatomic, getter=isEditing) BOOL editing;

/* Read again, for the element of that id (a new one after a rename). */
- (void)reloadOf:(NSString *)elementId;
/* A row of what a new one holds, at the end; the row's index. */
- (NSUInteger)addRow;
- (void)removeRowAtIndex:(NSUInteger)index;
- (void)setValue:(id)value column:(NSUInteger)column row:(NSUInteger)row;

/* The tables of what the row holds, a detail of the property's each. */
- (NSArray<WKDTableModel *> *)detailsForRow:(NSUInteger)row;

@end

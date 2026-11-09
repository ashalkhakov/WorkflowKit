#import <Foundation/Foundation.h>
#import "WKDProperties.h"

@class WKDTableModel;

/*
 * One section of an element's properties as values a view binds to: each
 * property's value under a key of its own -- its label made a key, "Due
 * date" is dueDate -- read and written through the property's descriptor
 * (WKDProperties), each value set one change. A text is a string, a check
 * box's value a boolean number, a choice's the index of its value, a
 * table's a WKDTableModel. -validateValue:forKey:error: says why a value
 * would be refused; set anyway, the refusal is told and the value read
 * again. Observable, every key, by key-value observing.
 */
@interface WKDElementModel : NSObject

- (instancetype)initWithEditor:(WKDEditor *)editor elementId:(NSString *)elementId section:(WKDSection *)section;
@property (nonatomic, readonly, strong) WKDEditor *editor;
/* The element shown: a new one after its id was set. */
@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, strong) WKDSection *section;

/* The section's properties' keys, in their order. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *keys;
- (NSString *)keyOf:(WKDProperty *)property;
- (WKDProperty *)propertyForKey:(NSString *)key;
/* A table property's rows. */
- (WKDTableModel *)tableModelForKey:(NSString *)key;

/* Told why a value set was refused; nil once one is taken. */
@property (nonatomic, copy) void (^refused)(NSString *reason);
/* Why the engine would not read the text, for a property holding an
 * expression: what is shown as it is typed; nil when it would. */
- (NSString *)problemWithText:(NSString *)text forKey:(NSString *)key;

/* The key a view is typing in: not read again until it is left. */
@property (nonatomic, copy) NSString *editingKey;
/* Every value read again: after a change, an undo; observers are told of
 * each key but the one being typed in. */
- (void)reload;

@end

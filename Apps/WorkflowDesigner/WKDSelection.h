#import <Foundation/Foundation.h>

/* Posted, by the selection, when what is selected changes. */
extern NSString * const WKDSelectionDidChangeNotification;

/*
 * What is selected in a process: the ids of its elements, shared by the
 * parts that show them -- the canvas, the outline, the inspector -- each
 * of which sets it when chosen in and follows it otherwise. Observable by
 * its notification, and by key-value observing of selectedIds.
 */
@interface WKDSelection : NSObject

/* In the order chosen: the first is the one the inspector shows. */
@property (nonatomic, copy) NSArray<NSString *> *selectedIds;
/* The first selected, or nil. */
@property (nonatomic, readonly, copy) NSString *selectedId;

/* The ids no longer in the process dropped: after a change, an undo. */
- (void)keepOnly:(NSSet<NSString *> *)existing;

@end

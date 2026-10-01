#import <AppKit/AppKit.h>

@class WKDDiagram, WKDOutline;

@protocol WKDOutlineDelegate <NSObject>
/* A row was chosen: the element's id, the process's for the process. */
- (void)outline:(WKDOutline *)outline didSelect:(NSString *)elementId;
@end

/* The left pane's outline: the process, its nodes -- a subprocess's within
 * it, an activity's boundary events beneath it -- and each node's flows. */
/* gnustep-gui's outline protocols make every method required: there the
 * conformance is left undeclared, and the methods are found all the same. */
#if defined(__APPLE__)
@interface WKDOutline : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
#else
@interface WKDOutline : NSObject
#endif

- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView;
@property (nonatomic, weak) id<WKDOutlineDelegate> delegate;
/* Read again; everything open. */
- (void)showDiagram:(WKDDiagram *)diagram;
/* The row of the element chosen, without telling the delegate. */
- (void)select:(NSString *)elementId;

@end

#import <AppKit/AppKit.h>
#import "WKDOutline.h"
#import "WKDProcessEditor.h"

/*
 * The process's tree, from WKDOutlineView.xib -- the process, its nodes,
 * a subprocess's within it, an activity's boundary events beneath it, each
 * node's flows -- kept to the process editor's model, its row the one
 * selected; a row chosen is the selection.
 */
@interface WKDOutlineViewController : NSViewController <WKDOutlineDelegate>

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor;
@property (nonatomic, readonly, strong) WKDProcessEditor *processEditor;

@property (nonatomic, strong) IBOutlet NSOutlineView *outlineView;
/* The process's own row chosen: nothing selected, the process shown. */
@property (nonatomic, copy) void (^processChosen)(void);

@end

#import <AppKit/AppKit.h>

@class WKDEditor;

/*
 * The right pane: an element's properties, in the sections WKDProperties
 * declares for it, a row each -- a label and a field, a check box, a
 * pop-up, or a text view for what runs to several lines. A field writes
 * when it is left or Return is pressed, a check box or a pop-up when it is
 * used: one change, one undo step.
 *
 * The rows are made again only when another kind of element comes, so
 * moving from field to field is not undone by the change the last one
 * made: otherwise they are refilled, the field being typed in aside.
 */
@interface WKDInspectorView : NSView

@property (nonatomic, strong) WKDEditor *editor;
/* What it shows; nil for nothing. */
@property (nonatomic, copy) NSString *elementId;
/* Told why a value was refused: a taken id. */
@property (nonatomic, copy) void (^refused)(NSString *reason);
/* Told, as an expression is typed, why the engine would not read it; nil
 * once it would, or once the field is left. */
@property (nonatomic, copy) void (^explained)(NSString *problem);

/* After any change to the document. */
- (void)reload;

@end

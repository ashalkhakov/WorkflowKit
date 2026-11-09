#import <AppKit/AppKit.h>
#import "WKDElementModel.h"
#import "WKDProcessEditor.h"

/* The inspector's rows, stacked down from its top. */
@interface WKDInspectorStack : NSView
@end

/*
 * An element's properties, from WKDInspector.xib: a page per section --
 * General, Assignment, Implementation, Decision, Event, Multi-instance,
 * Continuation, ... -- as WKDProperties declares them for its kind, each
 * a WKDElementModel its rows bind to, a row each property from the XIB of
 * its kind. The rows are made again only when another kind of element
 * comes; otherwise the models are read again, the field being typed in
 * aside. The element is the one selected, or the process.
 */
@interface WKDInspectorViewController : NSViewController

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor showingProcess:(BOOL)process;
@property (nonatomic, readonly, strong) WKDProcessEditor *processEditor;
@property (nonatomic, readonly, getter=isShowingProcess) BOOL showingProcess;

@property (nonatomic, strong) IBOutlet WKDInspectorStack *stack;

/* What it shows: the element, and a model each of its sections. */
@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSArray<WKDElementModel *> *models;

/* Told why a value was refused: a taken id. */
@property (nonatomic, copy) void (^refused)(NSString *reason);
/* Told, as an expression is typed, why the engine would not read it. */
@property (nonatomic, copy) void (^explained)(NSString *problem);

@end

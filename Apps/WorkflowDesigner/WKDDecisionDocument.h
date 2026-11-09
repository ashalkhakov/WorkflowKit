#import <AppKit/AppKit.h>

@class WKDDmnEditor, WKDDecisionEditor;

/*
 * A DMN file: its decisions, edited in place through a WKDDecisionEditor on
 * the document's undo manager and written back as they are, as a process
 * is by WKDDocument. After every change the engine says whether it would
 * deploy the file.
 */
@interface WKDDecisionDocument : NSDocument

@property (nonatomic, readonly, strong) WKDDecisionEditor *decisionEditor;
@property (nonatomic, readonly, strong) WKDDmnEditor *editor;
/* Why the engine would not deploy the decisions as they are; nil when it
 * would. */
@property (nonatomic, readonly, copy) NSString *problem;
/* The decision to show, in the window; when it is open, at once. */
- (void)showDecision:(NSString *)decisionId;

@end

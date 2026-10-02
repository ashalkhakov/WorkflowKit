#import <AppKit/AppKit.h>

@class WKDDmnEditor;

/*
 * A DMN file: its decisions, edited in place through a WKDDmnEditor on the
 * document's undo manager and written back as they are, as a process is
 * by WKDDocument. After every change the engine's DMN reader says whether
 * it would deploy the file.
 */
@interface WKDDecisionDocument : NSDocument

@property (nonatomic, readonly, strong) WKDDmnEditor *editor;
/* Why the engine would not deploy the decisions as they are; nil when it
 * would. */
@property (nonatomic, readonly, copy) NSString *problem;
- (void)check;
/* The decision to show, in the window; when it is open, at once. */
- (void)showDecision:(NSString *)decisionId;

@end

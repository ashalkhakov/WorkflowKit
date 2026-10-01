#import <AppKit/AppKit.h>

@class WKDEditor;

/*
 * A BPMN file. Its XML is the document, edited in place through a
 * WKDEditor on the document's undo manager, and written back as it is:
 * what the designer does not draw -- documentation, extensions, other
 * processes -- is kept.
 */
@interface WKDDocument : NSDocument

@property (nonatomic, readonly, strong) WKDEditor *editor;
/* Why the engine would not deploy the process as it is; nil when it would. */
@property (nonatomic, readonly, copy) NSString *problem;
/* Asks the engine again: after every change. */
- (void)check;
/* Opened from a server, never saved: its name until it is -- the
 * definition's key and version. */
@property (nonatomic, copy) NSString *serverTitle;
/* The name it was deployed under, which deploying again keeps. */
@property (nonatomic, copy) NSString *resourceName;

@end

#import <AppKit/AppKit.h>

@class WKDEditor, WKDProcessEditor;

/*
 * A BPMN file. Its XML is the document, edited in place through a
 * WKDEditor on the document's undo manager, and written back as it is:
 * what the designer does not draw -- documentation, extensions, other
 * processes -- is kept.
 */
@interface WKDDocument : NSDocument

/* The process, its selection and what the engine finds wrong with it,
 * checked with the forms beside the file. */
@property (nonatomic, readonly, strong) WKDProcessEditor *processEditor;
@property (nonatomic, readonly, strong) WKDEditor *editor;
/* Why the engine would not deploy the process as it is; nil when it would. */
@property (nonatomic, readonly, copy) NSString *problem;
/* Opened from a server, never saved: its name until it is -- the
 * definition's key and version. */
@property (nonatomic, copy) NSString *serverTitle;
/* The name it was deployed under, which deploying again keeps. */
@property (nonatomic, copy) NSString *resourceName;

@end

#import "WKDDocument.h"
#import "WKDEditor.h"
#import "WKDWindowController.h"
#import "WKDProcessEditor.h"
#import "WKDDeployment.h"
#if __has_include(<WorkflowKit/WFBpmn.h>)
#import <WorkflowKit/WFBpmn.h>
#else
#import "WFBpmn.h"
#endif

@implementation WKDDocument

- (void)makeWindowControllers
{
	if (_processEditor == nil) {
		[self useProcessEditor:[[WKDProcessEditor alloc] initNewProcessWithUndoManager:[self undoManager]]];
	}
	[self addWindowController:[[WKDWindowController alloc] init]];
}

- (void)useProcessEditor:(WKDProcessEditor *)processEditor
{
	_processEditor = processEditor;
	__weak WKDDocument *weakSelf = self;
	processEditor.resourcesBeside = ^NSDictionary *{
		return [weakSelf formsBeside];
	};
	processEditor.fileName = [[self fileURL] lastPathComponent];
	[processEditor checkNow];
}

/* The forms the process names, from beside its file: what deploying it
 * sends with it. */
- (NSDictionary<NSString *, NSData *> *)formsBeside
{
	NSURL *directory = [[self fileURL] URLByDeletingLastPathComponent];
	NSMutableDictionary *forms = [NSMutableDictionary dictionary];
	for (NSString *name in directory != nil ? WKDEmbeddedForms(self.editor.document) : @[]) {
		NSData *bytes = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:name]];
		if (bytes != nil) {
			[forms setObject:bytes forKey:name];
		}
	}
	return forms;
}

- (void)setFileURL:(NSURL *)url
{
	[super setFileURL:url];
	_processEditor.fileName = [url lastPathComponent];
}

- (WKDEditor *)editor
{
	return _processEditor.editor;
}

- (NSString *)problem
{
	return _processEditor.problem;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
	WKDProcessEditor *processEditor = [[WKDProcessEditor alloc] initWithData:data undoManager:[self undoManager]
	                                                                   error:error];
	if (processEditor == nil) {
		return NO;
	}
	[self useProcessEditor:processEditor];
	/* A file without a diagram is laid out: a change, to save. */
	if (processEditor.laidOut) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateChangeCount:NSChangeDone];
		});
	}
	return YES;
}

- (NSData *)dataOfType:(NSString *)type error:(NSError **)error
{
	return [_processEditor data];
}

- (NSString *)displayName
{
	return [self fileURL] == nil && self.serverTitle != nil ? self.serverTitle : [super displayName];
}

+ (BOOL)autosavesInPlace
{
	return NO;
}

@end

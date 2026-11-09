#import "WKDDecisionDocument.h"
#import "WKDDecisionEditor.h"
#import "WKDDecisionWindowController.h"

@implementation WKDDecisionDocument
{
	/* What to show when the window is made. */
	NSString *_shown;
}

- (void)makeWindowControllers
{
	if (_decisionEditor == nil) {
		_decisionEditor = [[WKDDecisionEditor alloc] initNewWithUndoManager:[self undoManager]];
	}
	_decisionEditor.fileName = [[self fileURL] lastPathComponent];
	WKDDecisionWindowController *controller = [[WKDDecisionWindowController alloc] init];
	[self addWindowController:controller];
	if (_shown != nil) {
		[controller showDecision:_shown];
	}
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
	WKDDecisionEditor *decisionEditor = [[WKDDecisionEditor alloc] initWithData:data undoManager:[self undoManager]
	                                                                      error:error];
	if (decisionEditor == nil) {
		return NO;
	}
	_decisionEditor = decisionEditor;
	_decisionEditor.fileName = [[self fileURL] lastPathComponent];
	return YES;
}

- (void)setFileURL:(NSURL *)url
{
	[super setFileURL:url];
	_decisionEditor.fileName = [url lastPathComponent];
}

- (NSData *)dataOfType:(NSString *)type error:(NSError **)error
{
	return [_decisionEditor data];
}

- (WKDDmnEditor *)editor
{
	return _decisionEditor.editor;
}

- (NSString *)problem
{
	return _decisionEditor.problem;
}

+ (BOOL)autosavesInPlace
{
	return NO;
}

- (void)showDecision:(NSString *)decisionId
{
	_shown = [decisionId copy];
	for (NSWindowController *controller in [self windowControllers]) {
		if ([controller isKindOfClass:[WKDDecisionWindowController class]]) {
			[(WKDDecisionWindowController *)controller showDecision:decisionId];
		}
	}
}

@end

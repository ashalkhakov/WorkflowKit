#import "WKDDocument.h"
#import "WKDEditor.h"
#import "WKDWindowController.h"
#if __has_include(<WorkflowKit/WFBpmn.h>)
#import <WorkflowKit/WFBpmn.h>
#else
#import "WFBpmn.h"
#endif

@implementation WKDDocument

- (void)makeWindowControllers
{
	if (_editor == nil) {
		_editor = [[WKDEditor alloc] initWithDocument:[WKDEditor newProcessDocument] undoManager:[self undoManager]];
		[self check];
	}
	[self addWindowController:[[WKDWindowController alloc] init]];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
	NSError *parseError = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:&parseError];
	WKDEditor *editor = document != nil ? [[WKDEditor alloc] initWithDocument:document undoManager:[self undoManager]] : nil;
	if (editor.diagram.process == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{
				NSLocalizedDescriptionKey: @"The file is not a BPMN process.",
				NSLocalizedRecoverySuggestionErrorKey: [parseError localizedDescription]
					?: @"It has no process element in the BPMN 2.0 namespace." }];
		}
		return NO;
	}
	/* A file without a diagram is laid out: a change, to save. */
	BOOL drawn = !editor.diagram.needsLayout;
	[editor completeDiagram];
	_editor = editor;
	[self check];
	if (!drawn) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateChangeCount:NSChangeDone];
		});
	}
	return YES;
}

- (NSData *)dataOfType:(NSString *)type error:(NSError **)error
{
	return [_editor.document XMLDataWithOptions:NSXMLNodePrettyPrint];
}

+ (BOOL)autosavesInPlace
{
	return NO;
}

- (void)check
{
	NSError *error = nil;
	WFProcessDefinition *definition = [WFBpmnReader definitionFromXMLString:[_editor.document XMLString] error:&error];
	_problem = definition != nil ? nil : [[error localizedDescription] copy] ?: @"The engine cannot read the process.";
}

@end

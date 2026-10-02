#import "WKDDecisionDocument.h"
#import "WKDDecisions.h"
#import "WKDDecisionWindowController.h"
#if __has_include(<WorkflowKit/WFDecision.h>)
#import <WorkflowKit/WFDecision.h>
#else
#import "WFDecision.h"
#endif

@implementation WKDDecisionDocument
{
	/* What to show when the window is made. */
	NSString *_shown;
}

- (void)makeWindowControllers
{
	if (_editor == nil) {
		_editor = [[WKDDmnEditor alloc] initWithDocument:[WKDDmnEditor newDecisionsDocument]
		                                     undoManager:[self undoManager]];
		[self check];
	}
	WKDDecisionWindowController *controller = [[WKDDecisionWindowController alloc] init];
	[self addWindowController:controller];
	if (_shown != nil) {
		[controller showDecision:_shown];
	}
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
	NSError *parseError = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:&parseError];
	NSString *uri = [[document rootElement] URI];
	if (![[[document rootElement] localName] isEqualToString:@"definitions"]
	    || [uri rangeOfString:@"/spec/DMN/"].location == NSNotFound) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{
				NSLocalizedDescriptionKey: @"The file is not a DMN document.",
				NSLocalizedRecoverySuggestionErrorKey: [parseError localizedDescription]
					?: @"Its root is not DMN's definitions." }];
		}
		return NO;
	}
	_editor = [[WKDDmnEditor alloc] initWithDocument:document undoManager:[self undoManager]];
	[self check];
	return YES;
}

- (NSData *)dataOfType:(NSString *)type error:(NSError **)error
{
	return [_editor.document XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement];
}

+ (BOOL)autosavesInPlace
{
	return NO;
}

- (void)check
{
	NSError *error = nil;
	NSArray *decisions = [WFDmnReader decisionsFromXMLString:[_editor.document XMLString] error:&error];
	_problem = decisions != nil ? nil : [[error localizedDescription] copy] ?: @"The engine cannot read the decisions.";
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

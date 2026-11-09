#import "WKDDecisionEditor.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

NSString * const WKDDecisionEditorDidChangeNotification = @"WKDDecisionEditorDidChange";
NSString * const WKDDecisionEditorChoiceDidChangeNotification = @"WKDDecisionEditorChoiceDidChange";
NSString * const WKDDecisionEditorProblemsDidChangeNotification = @"WKDDecisionEditorProblemsDidChange";

/* How long after a change the engine is asked: typing an entry checks once. */
static const NSTimeInterval WKDCheckDelay = 0.3;

@implementation WKDDecisionEditor
{
	/* The rename the next change makes. */
	NSDictionary *_renamed;
	/* Where the decision chosen was among them: its neighbour is chosen
	 * when it goes. */
	NSUInteger _index;
}

- (instancetype)initWithEditor:(WKDDmnEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
		_column = NSNotFound;
		_problems = @[];
		_decisionId = [[editor.decisions firstObject].decisionId copy];
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(editorDidChange:) name:WKDDmnEditorDidChangeNotification object:editor];
		[center addObserver:self selector:@selector(editorWillRename:) name:WKDDmnEditorWillRenameNotification object:editor];
		[self checkNow];
	}
	return self;
}

- (instancetype)initWithData:(NSData *)data undoManager:(NSUndoManager *)undoManager error:(NSError **)error
{
	NSError *parseError = nil;
	NSXMLDocument *document = data != nil ? [[NSXMLDocument alloc] initWithData:data options:0 error:&parseError] : nil;
	NSString *uri = [[document rootElement] URI];
	if (![[[document rootElement] localName] isEqualToString:@"definitions"]
	    || [uri rangeOfString:@"/spec/DMN/"].location == NSNotFound) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{
				NSLocalizedDescriptionKey: @"The file is not a DMN document.",
				NSLocalizedRecoverySuggestionErrorKey: [parseError localizedDescription]
					?: @"Its root is not DMN's definitions." }];
		}
		return nil;
	}
	return [self initWithEditor:[[WKDDmnEditor alloc] initWithDocument:document undoManager:undoManager]];
}

- (instancetype)initNewWithUndoManager:(NSUndoManager *)undoManager
{
	return [self initWithEditor:[[WKDDmnEditor alloc] initWithDocument:[WKDDmnEditor newDecisionsDocument]
	                                                      undoManager:undoManager]];
}

- (void)dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkNow) object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSData *)data
{
	return [_editor.document XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement];
}

#pragma mark What is chosen

- (WKDDmnDecision *)decision
{
	return _decisionId != nil ? [_editor decisionWithId:_decisionId] : nil;
}

- (void)setDecisionId:(NSString *)decisionId
{
	if ([_editor decisionWithId:decisionId] == nil || [decisionId isEqualToString:_decisionId]) {
		return;
	}
	_decisionId = [decisionId copy];
	_index = [[_editor.decisions valueForKey:@"decisionId"] indexOfObject:decisionId];
	_column = NSNotFound;
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDDecisionEditorChoiceDidChangeNotification object:self];
}

- (void)setColumn:(NSUInteger)column
{
	if (column == _column || (column != NSNotFound && column >= [self.decision.columns count])) {
		return;
	}
	_column = column;
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDDecisionEditorChoiceDidChangeNotification object:self];
}

#pragma mark Following the editor

- (void)editorWillRename:(NSNotification *)notification
{
	_renamed = [notification userInfo];
}

- (void)editorDidChange:(NSNotification *)notification
{
	if ([[_renamed objectForKey:@"from"] isEqualToString:_decisionId]) {
		_decisionId = [[_renamed objectForKey:@"to"] copy];
	}
	_renamed = nil;
	NSArray *decisions = _editor.decisions;
	/* A decision gone -- deleted, or undone -- chooses its neighbour. */
	if (self.decision == nil) {
		WKDDmnDecision *next = [decisions count] == 0 ? nil
			: [decisions objectAtIndex:MIN(_index, [decisions count] - 1)];
		_decisionId = [next.decisionId copy];
		_column = NSNotFound;
	}
	_index = [[decisions valueForKey:@"decisionId"] indexOfObject:_decisionId ?: @""];
	NSUInteger columns = [self.decision.columns count];
	if (_column != NSNotFound && _column >= columns) {
		_column = columns > 0 ? columns - 1 : NSNotFound;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDDecisionEditorDidChangeNotification object:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkNow) object:nil];
	[self performSelector:@selector(checkNow) withObject:nil afterDelay:WKDCheckDelay];
}

#pragma mark The engine's problems

- (void)checkNow
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkNow) object:nil];
	NSArray *problems = [WFDeploymentChecker problemsInResources:@{ self.fileName ?: @"decisions.dmn": [self data] }];
	if ([[problems valueForKey:@"description"] isEqualToArray:[_problems valueForKey:@"description"]]) {
		return;
	}
	_problems = [problems copy];
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDDecisionEditorProblemsDidChangeNotification
	                                                    object:self];
}

- (NSString *)problem
{
	return [[_problems firstObject] message];
}

@end

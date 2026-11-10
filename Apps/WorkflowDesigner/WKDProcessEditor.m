#import "WKDProcessEditor.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

NSString * const WKDProcessEditorDidChangeNotification = @"WKDProcessEditorDidChange";
NSString * const WKDProcessEditorProblemsDidChangeNotification = @"WKDProcessEditorProblemsDidChange";

/* How long after a change the engine is asked: typing a name checks once. */
static const NSTimeInterval WKDCheckDelay = 0.3;

@implementation WKDProcessEditor
{
	/* The rename the next change makes. */
	NSDictionary *_renamed;
	/* What the process is read again on. */
	NSUndoManager *_undoManager;
}

- (instancetype)initWithEditor:(WKDEditor *)editor undoManager:(NSUndoManager *)undoManager
{
	if ((self = [super init])) {
		_undoManager = undoManager;
		_selection = [[WKDSelection alloc] init];
		_problems = @[];
		[self follow:editor];
		[self checkNow];
	}
	return self;
}

/* The process the text holds, laid out when it has no diagram; nil, with
 * why, when it holds none. */
static WKDEditor *
WKDReadProcess(NSData *data, NSUndoManager *undoManager, BOOL *laidOut, NSError **error)
{
	NSError *parseError = nil;
	NSXMLDocument *document = data != nil ? [[NSXMLDocument alloc] initWithData:data options:0 error:&parseError] : nil;
	WKDEditor *editor = document != nil ? [[WKDEditor alloc] initWithDocument:document undoManager:undoManager] : nil;
	if (editor.model.process == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{
				NSLocalizedDescriptionKey: @"The file is not a BPMN process.",
				NSLocalizedRecoverySuggestionErrorKey: [parseError localizedDescription]
					?: @"It has no process element in the BPMN 2.0 namespace." }];
		}
		return nil;
	}
	*laidOut = editor.model.needsLayout;
	[editor completeDiagram];
	return editor;
}

- (instancetype)initWithData:(NSData *)data undoManager:(NSUndoManager *)undoManager error:(NSError **)error
{
	BOOL laidOut = NO;
	WKDEditor *editor = WKDReadProcess(data, undoManager, &laidOut, error);
	if (editor == nil) {
		return nil;
	}
	if ((self = [self initWithEditor:editor undoManager:undoManager])) {
		_laidOut = laidOut;
	}
	return self;
}

- (BOOL)readData:(NSData *)data error:(NSError **)error
{
	BOOL laidOut = NO;
	WKDEditor *editor = WKDReadProcess(data, _undoManager, &laidOut, error);
	if (editor == nil) {
		return NO;
	}
	_laidOut = laidOut;
	[self follow:editor];
	[self editorDidChange:nil];
	return YES;
}

/* The editor whose changes are followed: this one, not the last. */
- (void)follow:(WKDEditor *)editor
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	if (_editor != nil) {
		[center removeObserver:self name:WKDEditorDidChangeNotification object:_editor];
		[center removeObserver:self name:WKDEditorWillRenameNotification object:_editor];
	}
	_editor = editor;
	[center addObserver:self selector:@selector(editorDidChange:) name:WKDEditorDidChangeNotification object:editor];
	[center addObserver:self selector:@selector(editorWillRename:) name:WKDEditorWillRenameNotification object:editor];
}

- (instancetype)initNewProcessWithUndoManager:(NSUndoManager *)undoManager
{
	return [self initWithEditor:[[WKDEditor alloc] initWithDocument:[WKDEditor newProcessDocument]
	                                                    undoManager:undoManager]
	                undoManager:undoManager];
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

#pragma mark Following the editor

- (NSSet<NSString *> *)elementIds
{
	WKDModel *model = _editor.model;
	NSMutableSet *ids = [NSMutableSet set];
	[ids addObjectsFromArray:[model.nodes valueForKey:@"elementId"]];
	[ids addObjectsFromArray:[model.flows valueForKey:@"elementId"]];
	[ids addObjectsFromArray:[model.lanes valueForKey:@"elementId"]];
	[ids addObjectsFromArray:[model.otherPools valueForKey:@"elementId"]];
	if (model.pool.elementId != nil) {
		[ids addObject:model.pool.elementId];
	}
	return ids;
}

/* An element given another id: still selected, under it. */
- (void)editorWillRename:(NSNotification *)notification
{
	_renamed = [notification userInfo];
}

- (void)editorDidChange:(NSNotification *)notification
{
	NSString *from = [_renamed objectForKey:@"from"], *to = [_renamed objectForKey:@"to"];
	_renamed = nil;
	if (from != nil && [_selection.selectedIds containsObject:from]) {
		NSMutableArray *ids = [_selection.selectedIds mutableCopy];
		[ids replaceObjectAtIndex:[ids indexOfObject:from] withObject:to];
		_selection.selectedIds = ids;
	}
	[_selection keepOnly:[self elementIds]];
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDProcessEditorDidChangeNotification object:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkNow) object:nil];
	[self performSelector:@selector(checkNow) withObject:nil afterDelay:WKDCheckDelay];
}

#pragma mark The engine's problems

- (void)checkNow
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkNow) object:nil];
	NSMutableDictionary *resources = [NSMutableDictionary dictionaryWithDictionary:
		self.resourcesBeside != nil ? self.resourcesBeside() ?: @{} : @{}];
	[resources setObject:[self data] forKey:self.fileName ?: @"process.bpmn"];
	NSArray *problems = [WFDeploymentChecker problemsInResources:resources];
	if ([[problems valueForKey:@"description"] isEqualToArray:[_problems valueForKey:@"description"]]) {
		return;
	}
	_problems = [problems copy];
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDProcessEditorProblemsDidChangeNotification
	                                                    object:self];
}

- (NSString *)problem
{
	return [[_problems firstObject] message];
}

@end

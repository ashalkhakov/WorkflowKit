#import "WKDDecisionWindowController.h"
#import "WKDAppDelegate.h"
#import "WKDDecisionDocument.h"
#import "WKDPane.h"
#import "WKDXML.h"
#import "WDSession.h"

@implementation WKDDecisionWindowController
{
	/* What the last change refused, or a cell's problem as it is typed. */
	NSString *_note;
}

- (instancetype)init
{
	return [super initWithWindowNibPath:WKDNibPath(@"DecisionWindow") owner:self];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (WKDDecisionDocument *)decisionDocument
{
	return (WKDDecisionDocument *)[self document];
}

- (WKDDecisionEditor *)decisionEditor
{
	return [self decisionDocument].decisionEditor;
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
	return [[self document] undoManager];
}

#pragma mark Putting the parts in their places

- (void)windowDidLoad
{
	[super windowDidLoad];
	WKDDecisionEditor *decisionEditor = [self decisionEditor];
	__weak WKDDecisionWindowController *weakSelf = self;
	void (^refused)(NSString *) = ^(NSString *reason) {
		[weakSelf note:reason];
	};
	/* An expression's problem as it is typed: said, not beeped at. */
	void (^explained)(NSString *) = ^(NSString *problem) {
		[weakSelf explain:problem];
	};
	_listController = [[WKDDecisionListViewController alloc] initWithDecisionEditor:decisionEditor];
	_detailController = [[WKDDecisionDetailViewController alloc] initWithDecisionEditor:decisionEditor];
	_gridController = [[WKDRuleGridViewController alloc] initWithDecisionEditor:decisionEditor];
	_columnController = [[WKDColumnViewController alloc] initWithDecisionEditor:decisionEditor];
	_literalController = [[WKDLiteralViewController alloc] initWithDecisionEditor:decisionEditor];
	WKDFillHost(self.listHost, _listController.view);
	WKDFillHost(self.detailHost, _detailController.view);
	WKDFillHost(self.gridHost, _gridController.view);
	WKDFillHost(self.columnHost, _columnController.view);
	WKDFillHost(self.literalHost, _literalController.view);
	_detailController.refused = refused;
	_gridController.explained = explained;
	_columnController.explained = explained;
	_literalController.explained = explained;
	_listController.added = ^{
		[[weakSelf window] makeFirstResponder:weakSelf.detailController.nameField];
	};
	_gridController.columnAdded = ^(BOOL output) {
		[weakSelf.columnController focus];
	};

	/* The Decision menu's actions, after this in the responder chain. */
	[_gridController setNextResponder:[self nextResponder]];
	[_listController setNextResponder:_gridController];
	[self setNextResponder:_listController];

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	for (NSString *name in @[ WKDDecisionEditorDidChangeNotification, WKDDecisionEditorChoiceDidChangeNotification,
	                          WKDDecisionEditorProblemsDidChangeNotification ]) {
		[center addObserver:self selector:@selector(show) name:name object:decisionEditor];
	}
	[self show];
	[[self window] center];
}

- (void)show
{
	WKDDmnDecision *decision = [self decisionEditor].decision;
	[self.tablePanel setHidden:!decision.isTable];
	[self.literalHost setHidden:decision == nil || decision.isTable];
	[self updateStatus];
}

- (void)showDecision:(NSString *)decisionId
{
	[self window];
	[self decisionEditor].decisionId = decisionId;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
	return MAX(proposed, 150);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
	return MIN(proposed, NSWidth([splitView bounds]) - 600);
}

#pragma mark Status

- (void)updateStatus
{
	NSString *problem = [self decisionEditor].problem;
	NSMutableArray *parts = [NSMutableArray array];
	if (_note != nil) {
		[parts addObject:_note];
	}
	[parts addObject:problem == nil ? @"The engine evaluates these decisions."
	                                : [NSString stringWithFormat:@"Not deployable: %@", problem]];
	[self.statusField setStringValue:[parts componentsJoinedByString:@" — "]];
}

/* A change refused: said. */
- (void)note:(NSString *)note
{
	_note = [note copy];
	[self updateStatus];
}

/* An expression's problem as it is typed: said, not beeped at. */
- (void)explain:(NSString *)problem
{
	_note = [problem copy];
	[self updateStatus];
}

#pragma mark Deploying

- (void)alert:(NSString *)message detail:(NSString *)detail
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:message];
	[alert setInformativeText:detail ?: @""];
	[alert beginSheetModalForWindow:[self window] completionHandler:nil];
}

- (IBAction)deploy:(id)sender
{
	WKDDecisionDocument *document = [self decisionDocument];
	WKDDecisionEditor *decisionEditor = [self decisionEditor];
	if (decisionEditor.problem != nil) {
		[self alert:@"The engine would not evaluate these decisions." detail:decisionEditor.problem];
		return;
	}
	NSXMLElement *root = [decisionEditor.editor.document rootElement];
	NSString *fileName = [[document fileURL] lastPathComponent]
		?: [(WKDAttribute(root, @"id") ?: @"decisions") stringByAppendingPathExtension:@"dmn"];
	NSString *name = WKDAttribute(root, @"name") ?: fileName;
	NSDictionary *resources = @{ fileName: [decisionEditor.editor.document XMLStringWithOptions:NSXMLNodePrettyPrint] };
	[[WKDAppDelegate shared] withSession:^(WDSession *session) {
		[self note:nil];
		[self.statusField setStringValue:[NSString stringWithFormat:@"Deploying to %@…", [session.serviceURL host]]];
		[session invoke:@"Deploy" on:nil parameters:@{ @"Name": name, @"Resources": resources }
		     completion:^(id result, NSError *error) {
			if (error != nil) {
				[self updateStatus];
				[self alert:@"Could not deploy." detail:[error localizedDescription]];
				return;
			}
			self->_note = [NSString stringWithFormat:@"Deployed %@", fileName];
			[self updateStatus];
		}];
	}];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	if ([item action] == @selector(deploy:)) {
		return [self decisionEditor].problem == nil;
	}
	return YES;
}

@end

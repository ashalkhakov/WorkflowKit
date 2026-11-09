#import "WKDDecisionListViewController.h"

@implementation WKDDecisionListViewController
{
	/* The list being reloaded: gnustep-gui selects a row of its own as it
	 * does, which is not a choice. */
	BOOL _reloading;
}

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor
{
	if ((self = [super initWithNibName:@"WKDDecisionList"
	                            bundle:[NSBundle bundleForClass:[WKDDecisionListViewController class]]])) {
		_decisionEditor = decisionEditor;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
	[super loadView];
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	for (NSString *name in @[ WKDDecisionEditorDidChangeNotification, WKDDecisionEditorChoiceDidChangeNotification ]) {
		[center addObserver:self selector:@selector(show) name:name object:_decisionEditor];
	}
	[self show];
}

- (void)show
{
	NSArray *decisions = _decisionEditor.editor.decisions;
	_reloading = YES;
	[self.tableView reloadData];
	NSUInteger index = [[decisions valueForKey:@"decisionId"] indexOfObject:_decisionEditor.decisionId ?: @""];
	if (index != NSNotFound) {
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
	}
	_reloading = NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[_decisionEditor.editor.decisions count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *decisions = _decisionEditor.editor.decisions;
	WKDDmnDecision *decision = row < (NSInteger)[decisions count] ? [decisions objectAtIndex:(NSUInteger)row] : nil;
	return decision.isTable ? decision.title : [decision.title stringByAppendingString:@"  (literal)"];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger row = [self.tableView selectedRow];
	NSArray *decisions = _decisionEditor.editor.decisions;
	if (!_reloading && row >= 0 && row < (NSInteger)[decisions count]) {
		_decisionEditor.decisionId = [[decisions objectAtIndex:(NSUInteger)row] decisionId];
	}
}

#pragma mark The Decision menu's

- (void)add:(BOOL)table
{
	_decisionEditor.decisionId = [_decisionEditor.editor addDecisionTable:table withId:nil];
	if (self.added != nil) {
		self.added();
	}
}

- (IBAction)addDecisionTable:(id)sender
{
	[self add:YES];
}

- (IBAction)addLiteralDecision:(id)sender
{
	[self add:NO];
}

- (IBAction)deleteDecision:(id)sender
{
	if (_decisionEditor.decisionId != nil) {
		[_decisionEditor.editor deleteDecision:_decisionEditor.decisionId];
	}
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	if ([item action] == @selector(deleteDecision:)) {
		return _decisionEditor.decision != nil;
	}
	return YES;
}

@end

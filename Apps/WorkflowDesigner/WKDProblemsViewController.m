#import "WKDProblemsViewController.h"
#if __has_include(<WorkflowKit/WorkflowKit.h>)
#import <WorkflowKit/WorkflowKit.h>
#else
#import "WorkflowKit.h"
#endif

@implementation WKDProblemsViewController

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor
{
	if ((self = [super initWithNibName:@"WKDProblems" bundle:[NSBundle bundleForClass:[WKDProblemsViewController class]]])) {
		_processEditor = processEditor;
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
	[self.tableView setDataSource:(id)self];
	[self.tableView setDelegate:(id)self];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(problemsDidChange:)
	                                             name:WKDProcessEditorProblemsDidChangeNotification
	                                           object:_processEditor];
	[self.tableView reloadData];
}

- (void)problemsDidChange:(NSNotification *)notification
{
	[self.tableView reloadData];
}

#pragma mark The list

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	/* None: one row saying so. */
	return (NSInteger)MAX([_processEditor.problems count], (NSUInteger)1);
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	NSArray<WFProblem *> *problems = _processEditor.problems;
	if ([problems count] == 0) {
		return [[column identifier] isEqualToString:@"message"] ? @"The engine runs this process." : @"";
	}
	WFProblem *problem = [problems objectAtIndex:(NSUInteger)row];
	if ([[column identifier] isEqualToString:@"line"]) {
		return problem.line > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)problem.line] : @"";
	}
	return problem.message;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	return [_processEditor.problems count] > 0;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger row = [self.tableView selectedRow];
	NSArray<WFProblem *> *problems = _processEditor.problems;
	if (row < 0 || (NSUInteger)row >= [problems count]) {
		return;
	}
	NSString *elementId = [problems objectAtIndex:(NSUInteger)row].elementId;
	WKDModel *model = _processEditor.editor.model;
	if ([model nodeWithId:elementId] != nil || [model flowWithId:elementId] != nil || [model laneWithId:elementId] != nil) {
		_processEditor.selection.selectedIds = @[ elementId ];
	}
}

@end

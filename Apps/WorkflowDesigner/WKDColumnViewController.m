#import "WKDColumnViewController.h"
#import "WKDExpressionField.h"

void
WKDFillTypes(NSPopUpButton *popup, NSString *typeRef)
{
	[popup removeAllItems];
	[popup addItemWithTitle:@"Any"];
	[popup addItemsWithTitles:WKDDmnTypes()];
	if ([typeRef length] > 0 && ![WKDDmnTypes() containsObject:typeRef]) {
		[popup addItemWithTitle:typeRef];
	}
	if ([typeRef length] > 0) {
		[popup selectItemWithTitle:typeRef];
	} else {
		[popup selectItemAtIndex:0];
	}
}

NSString *
WKDChosenType(NSPopUpButton *popup)
{
	return [popup indexOfSelectedItem] > 0 ? [popup titleOfSelectedItem] : nil;
}

@implementation WKDColumnViewController

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor
{
	if ((self = [super initWithNibName:@"WKDColumn" bundle:[NSBundle bundleForClass:[WKDColumnViewController class]]])) {
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
	/* A view, not a control: its target and its typing set here. */
	self.expressionField.place = WFExpressionPlaceExpression;
	self.expressionField.placeholderString = @"amount, order.total";
	self.expressionField.delegate = self;
	self.expressionField.target = self;
	self.expressionField.action = @selector(columnExpressionChanged:);
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	for (NSString *name in @[ WKDDecisionEditorDidChangeNotification, WKDDecisionEditorChoiceDidChangeNotification ]) {
		[center addObserver:self selector:@selector(show) name:name object:_decisionEditor];
	}
	[self show];
}

- (WKDDmnColumn *)column
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	NSUInteger chosen = _decisionEditor.column;
	return decision.isTable && chosen < [decision.columns count] ? [decision.columns objectAtIndex:chosen] : nil;
}

- (void)show
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	WKDDmnColumn *column = [self column];
	for (NSView *view in @[ self.labelLabel, self.labelField, self.expressionLabel, self.expressionField, self.nameLabel,
	                        self.outputNameField, self.typeLabel, self.typePopup, self.variableLabel,
	                        self.inputVariableField ]) {
		[view setHidden:column == nil];
	}
	if (column == nil) {
		[self.titleLabel setStringValue:@"Click a column's heading, or one of its cells, to edit the column here."];
		[self.titleLabel setFont:[NSFont systemFontOfSize:11]];
		return;
	}
	BOOL output = column.output;
	NSUInteger chosen = _decisionEditor.column;
	NSUInteger number = output ? chosen - [decision.inputs count] + 1 : chosen + 1;
	[self.titleLabel setFont:[NSFont boldSystemFontOfSize:12]];
	[self.titleLabel setStringValue:[NSString stringWithFormat:output ? @"Output %lu: %@" : @"Input %lu: %@",
	                                 (unsigned long)number, column.title]];
	[self.expressionLabel setHidden:output];
	[self.expressionField setHidden:output];
	[self.variableLabel setHidden:output];
	[self.inputVariableField setHidden:output];
	[self.nameLabel setHidden:!output];
	[self.outputNameField setHidden:!output];
	[self.labelField setStringValue:column.label ?: @""];
	if (output) {
		[self.outputNameField setStringValue:column.name ?: @""];
	} else {
		if (![[self.expressionField stringValue] isEqualToString:column.expression ?: @""]) {
			self.expressionField.stringValue = column.expression ?: @"";
		}
		[self.inputVariableField setStringValue:column.inputVariable ?: @""];
	}
	WKDFillTypes(self.typePopup, column.typeRef);
}

- (void)focus
{
	WKDDmnColumn *column = [self column];
	if (column != nil) {
		[[self.view window] makeFirstResponder:column.output ? (NSView *)self.outputNameField
		                                                     : (NSView *)self.expressionField.textView];
	}
}

#pragma mark Changes

- (void)setColumnProperty:(NSString *)property to:(NSString *)value
{
	WKDDmnColumn *column = [self column];
	if (column == nil) {
		return;
	}
	NSString *now = [column valueForKey:property] ?: @"";
	if (![now isEqualToString:value ?: @""]) {
		[_decisionEditor.editor setColumn:_decisionEditor.column property:property to:value
		                              of:_decisionEditor.decisionId];
	}
}

- (IBAction)columnLabelChanged:(id)sender
{
	[self setColumnProperty:@"label" to:[self.labelField stringValue]];
}

- (void)columnExpressionChanged:(id)sender
{
	if (self.explained != nil) {
		self.explained(nil);
	}
	[self setColumnProperty:@"expression" to:[self.expressionField stringValue]];
}

- (IBAction)columnNameChanged:(id)sender
{
	[self setColumnProperty:@"name" to:[self.outputNameField stringValue]];
}

- (IBAction)columnTypeChanged:(id)sender
{
	[self setColumnProperty:@"typeRef" to:WKDChosenType(self.typePopup)];
}

- (IBAction)columnVariableChanged:(id)sender
{
	[self setColumnProperty:@"inputVariable" to:[self.inputVariableField stringValue]];
}

/* The expression being typed: what the engine says of it. */
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] == self.expressionField && self.explained != nil) {
		self.explained(self.expressionField.problem);
	}
}

@end

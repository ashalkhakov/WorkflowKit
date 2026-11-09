#import "WKDLiteralViewController.h"
#import "WKDColumnViewController.h"
#import "WKDExpressionField.h"

@implementation WKDLiteralViewController

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor
{
	if ((self = [super initWithNibName:@"WKDLiteral" bundle:[NSBundle bundleForClass:[WKDLiteralViewController class]]])) {
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
	self.literalField.place = WFExpressionPlaceExpression;
	self.literalField.placeholderString = @"if income > 1000 then \"yes\" else \"no\"";
	self.literalField.delegate = self;
	self.literalField.target = self;
	self.literalField.action = @selector(literalChanged:);
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	for (NSString *name in @[ WKDDecisionEditorDidChangeNotification, WKDDecisionEditorChoiceDidChangeNotification ]) {
		[center addObserver:self selector:@selector(show) name:name object:_decisionEditor];
	}
	[self show];
}

- (void)show
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	if (decision == nil || decision.isTable) {
		return;
	}
	[self.variableField setStringValue:decision.variableName ?: @""];
	WKDFillTypes(self.variableType, decision.variableType);
	if (![[self.literalField stringValue] isEqualToString:decision.expression ?: @""]) {
		self.literalField.stringValue = decision.expression ?: @"";
	}
}

- (IBAction)variableChanged:(id)sender
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	if (decision != nil && ![[self.variableField stringValue] isEqualToString:decision.variableName ?: @""]) {
		[_decisionEditor.editor setLiteral:@"variableName" to:[self.variableField stringValue] of:decision.decisionId];
	}
}

- (IBAction)variableTypeChanged:(id)sender
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	NSString *type = WKDChosenType(self.variableType);
	if (decision != nil && ![type ?: @"" isEqualToString:decision.variableType ?: @""]) {
		[_decisionEditor.editor setLiteral:@"variableType" to:type of:decision.decisionId];
	}
}

- (void)literalChanged:(id)sender
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	if (self.explained != nil) {
		self.explained(nil);
	}
	if (decision != nil && ![[self.literalField stringValue] isEqualToString:decision.expression ?: @""]) {
		[_decisionEditor.editor setLiteral:@"expression" to:[self.literalField stringValue] of:decision.decisionId];
	}
}

/* The expression being typed: what the engine says of it. */
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] == self.literalField && self.explained != nil) {
		self.explained(self.literalField.problem);
	}
}

@end

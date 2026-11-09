#import "WKDDecisionDetailViewController.h"

@implementation WKDDecisionDetailViewController

- (instancetype)initWithDecisionEditor:(WKDDecisionEditor *)decisionEditor
{
	if ((self = [super initWithNibName:@"WKDDecisionDetail"
	                            bundle:[NSBundle bundleForClass:[WKDDecisionDetailViewController class]]])) {
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
	[self.hitPolicy removeAllItems];
	for (NSArray *policy in WKDDmnHitPolicies()) {
		[self.hitPolicy addItemWithTitle:policy[2]];
	}
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	for (NSString *name in @[ WKDDecisionEditorDidChangeNotification, WKDDecisionEditorChoiceDidChangeNotification ]) {
		[center addObserver:self selector:@selector(show) name:name object:_decisionEditor];
	}
	[self show];
}

- (WKDDmnEditor *)editor
{
	return _decisionEditor.editor;
}

- (void)refuse:(NSString *)reason
{
	if (reason != nil) {
		NSBeep();
	}
	if (self.refused != nil) {
		self.refused(reason);
	}
}

- (void)show
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	BOOL table = decision.isTable;
	for (NSControl *control in @[ self.nameField, self.idField, self.requires ]) {
		[control setEnabled:decision != nil];
	}
	[self.nameField setStringValue:decision.name ?: @""];
	[self.idField setStringValue:decision.decisionId ?: @""];
	[self.hitPolicyLabel setHidden:!table];
	[self.hitPolicy setHidden:!table];
	[self showRequirements:decision];
	if (!table) {
		return;
	}
	NSArray *policies = WKDDmnHitPolicies();
	NSInteger chosen = -1;
	for (NSUInteger i = 0; i < [policies count]; i++) {
		NSArray *policy = [policies objectAtIndex:i];
		if ([policy[0] isEqualToString:decision.hitPolicy] && [policy[1] isEqualToString:decision.aggregation ?: @""]) {
			chosen = (NSInteger)i;
		}
	}
	/* One the engine does not evaluate, as the file has it. */
	while ([self.hitPolicy numberOfItems] > (NSInteger)[policies count]) {
		[self.hitPolicy removeItemAtIndex:[self.hitPolicy numberOfItems] - 1];
	}
	if (chosen < 0) {
		[self.hitPolicy addItemWithTitle:[NSString stringWithFormat:@"%@ %@", decision.hitPolicy,
		                                  decision.aggregation ?: @""]];
		chosen = [self.hitPolicy numberOfItems] - 1;
	}
	[self.hitPolicy selectItemAtIndex:chosen];
}

/* The pull-down's title the decisions required; an item each other one,
 * checked when it is. */
- (void)showRequirements:(WKDDmnDecision *)decision
{
	[self.requires removeAllItems];
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *required in decision.required) {
		[names addObject:[[self editor] decisionWithId:required].title ?: required];
	}
	[self.requires addItemWithTitle:[names count] > 0 ? [names componentsJoinedByString:@", "] : @"No other decision"];
	for (WKDDmnDecision *other in [self editor].decisions) {
		if (decision == nil || [other.decisionId isEqualToString:decision.decisionId]) {
			continue;
		}
		NSMenuItem *item = (NSMenuItem *)[[self.requires menu] addItemWithTitle:other.title
		                                                                 action:@selector(requirementToggled:)
		                                                          keyEquivalent:@""];
		[item setTarget:self];
		[item setRepresentedObject:other.decisionId];
		[item setState:[decision.required containsObject:other.decisionId] ? NSControlStateValueOn : NSControlStateValueOff];
	}
}

#pragma mark Changes

- (IBAction)nameChanged:(id)sender
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	if (decision != nil && ![[self.nameField stringValue] isEqualToString:decision.name ?: @""]) {
		[[self editor] setName:[self.nameField stringValue] of:decision.decisionId];
	}
}

- (IBAction)idChanged:(id)sender
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	NSString *newId = [[self.idField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (decision == nil || [newId isEqualToString:decision.decisionId]) {
		return;
	}
	NSString *reason = nil;
	if (![[self editor] renameDecision:decision.decisionId to:newId error:&reason]) {
		[self.idField setStringValue:decision.decisionId];
		[self refuse:reason];
	}
}

- (IBAction)hitPolicyChanged:(id)sender
{
	NSArray *policies = WKDDmnHitPolicies();
	NSInteger index = [self.hitPolicy indexOfSelectedItem];
	WKDDmnDecision *decision = _decisionEditor.decision;
	if (decision == nil || index < 0 || index >= (NSInteger)[policies count]) {
		return;
	}
	NSArray *policy = [policies objectAtIndex:(NSUInteger)index];
	if (![policy[0] isEqualToString:decision.hitPolicy] || ![policy[1] isEqualToString:decision.aggregation ?: @""]) {
		[[self editor] setHitPolicy:policy[0] aggregation:policy[1] of:decision.decisionId];
	}
}

- (IBAction)requirementToggled:(id)sender
{
	WKDDmnDecision *decision = _decisionEditor.decision;
	NSString *other = [sender representedObject];
	if (decision == nil || other == nil) {
		return;
	}
	NSMutableArray *required = [decision.required mutableCopy];
	if ([required containsObject:other]) {
		[required removeObject:other];
	} else {
		[required addObject:other];
	}
	NSString *reason = nil;
	if (![[self editor] setRequired:required of:decision.decisionId error:&reason]) {
		[self refuse:reason];
		[self showRequirements:decision];
	}
}

@end

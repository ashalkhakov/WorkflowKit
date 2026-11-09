#import "WKDProcessCommands.h"
#import "WKDDecisions.h"
#import "WKDDeployment.h"
#import "WKDXML.h"

static NSString * const WKDFragmentPasteboardType = @"local.workflowkit.bpmn-fragment";

@implementation WKDProcessCommands
{
	/* Pastes since the last copy: each lands a step further down. */
	NSUInteger _pastes;
}

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor
{
	if ((self = [super init])) {
		_processEditor = processEditor;
	}
	return self;
}

- (WKDEditor *)editor
{
	return _processEditor.editor;
}

- (WKDSelection *)selection
{
	return _processEditor.selection;
}

/* The one element selected, if one is. */
- (NSString *)selectedId
{
	NSArray *ids = [self selection].selectedIds;
	return [ids count] == 1 ? [ids firstObject] : nil;
}

- (void)refuse:(NSString *)reason
{
	[self.host commands:self refused:reason];
}

- (void)select:(NSArray<NSString *> *)elementIds
{
	[self selection].selectedIds = elementIds;
}

#pragma mark Arranging

- (IBAction)arrange:(id)sender
{
	[self refuse:nil];
	[[self editor] arrange];
	[self.host commandsDidArrange:self];
}

- (NSArray<NSString *> *)selectedShapes
{
	NSMutableArray *shapes = [NSMutableArray array];
	for (NSString *elementId in [self selection].selectedIds) {
		if ([[self editor].model nodeWithId:elementId] != nil) {
			[shapes addObject:elementId];
		}
	}
	return shapes;
}

- (void)align:(WKDAlignment)alignment
{
	[self refuse:[[self editor] alignElements:[self selectedShapes] to:alignment]
	                 ? nil : @"Select two shapes or more to line up with the first."];
}

- (IBAction)alignLeftEdges:(id)sender
{
	[self align:WKDAlignLeft];
}

- (IBAction)alignCentres:(id)sender
{
	[self align:WKDAlignCentre];
}

- (IBAction)alignRightEdges:(id)sender
{
	[self align:WKDAlignRight];
}

- (IBAction)alignTopEdges:(id)sender
{
	[self align:WKDAlignTop];
}

- (IBAction)alignMiddles:(id)sender
{
	[self align:WKDAlignMiddle];
}

- (IBAction)alignBottomEdges:(id)sender
{
	[self align:WKDAlignBottom];
}

- (void)distributeVertically:(BOOL)vertically
{
	[self refuse:[[self editor] distributeElements:[self selectedShapes] vertically:vertically]
	                 ? nil : @"Select three shapes or more to spread out."];
}

- (IBAction)distributeAcross:(id)sender
{
	[self distributeVertically:NO];
}

- (IBAction)distributeDown:(id)sender
{
	[self distributeVertically:YES];
}

#pragma mark Pools, lanes, types and names

- (IBAction)addPool:(id)sender
{
	NSString *pool = [[self editor] addPool];
	if (pool != nil) {
		[self select:@[ pool ]];
	}
}

- (IBAction)addLane:(id)sender
{
	/* After the lane selected, else at the bottom of the pool. */
	NSString *selected = [self selectedId];
	NSString *after = [[self editor].model laneWithId:selected] != nil ? selected : nil;
	NSString *lane = [[self editor] addLaneAfter:after];
	if (lane != nil) {
		[self select:@[ lane ]];
	}
}

- (IBAction)changeType:(id)sender
{
	WKDNodeType *type = [sender representedObject];
	NSString *selected = [self selectedId];
	if (![type isKindOfClass:[WKDNodeType class]] || selected == nil) {
		return;
	}
	NSString *reason = nil;
	BOOL done = [[self editor] changeType:selected to:type error:&reason];
	[self refuse:done ? nil : reason];
}

- (IBAction)rename:(id)sender
{
	if ([self selectedId] != nil) {
		[self.host commands:self rename:[self selectedId]];
	}
}

#pragma mark The clipboard

/* The selection as a fragment of BPMN; nil, with a beep, when there is
 * nothing in it to copy. */
- (NSXMLDocument *)fragmentOfSelection
{
	NSXMLDocument *fragment = [[self editor] fragmentOfElements:[self selection].selectedIds];
	if (fragment == nil) {
		NSBeep();
	}
	return fragment;
}

- (IBAction)copy:(id)sender
{
	NSXMLDocument *fragment = [self fragmentOfSelection];
	if (fragment == nil) {
		return;
	}
	NSString *xml = [fragment XMLStringWithOptions:NSXMLNodePrettyPrint];
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard declareTypes:@[ WKDFragmentPasteboardType, NSPasteboardTypeString ] owner:nil];
	[pasteboard setString:xml forType:WKDFragmentPasteboardType];
	[pasteboard setString:xml forType:NSPasteboardTypeString];
	_pastes = 0;
}

- (IBAction)cut:(id)sender
{
	if ([self fragmentOfSelection] != nil) {
		[self copy:sender];
		[[self editor] deleteElements:[self selection].selectedIds];
	}
}

/* Pasted a step further down each time, the elements pasted selected. */
- (void)pasteFragment:(NSXMLDocument *)fragment
{
	_pastes++;
	NSString *reason = nil;
	NSArray *added = [[self editor] paste:fragment offset:NSMakeSize(30.0 * _pastes, 30.0 * _pastes) error:&reason];
	[self refuse:added == nil ? reason : nil];
	if (added != nil) {
		[self select:added];
	}
}

- (IBAction)paste:(id)sender
{
	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	NSString *xml = [pasteboard stringForType:WKDFragmentPasteboardType] ?: [pasteboard stringForType:NSPasteboardTypeString];
	NSXMLDocument *fragment = [xml length] > 0 ? [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL] : nil;
	if (fragment == nil) {
		[self refuse:@"The clipboard holds no BPMN to paste."];
		NSBeep();
		return;
	}
	[self pasteFragment:fragment];
}

- (IBAction)duplicate:(id)sender
{
	NSXMLDocument *fragment = [self fragmentOfSelection];
	if (fragment != nil) {
		_pastes = 0;
		[self pasteFragment:fragment];
	}
}

#pragma mark Forms and decisions

/* The element whose form is edited: the one selected, a user task or a
 * start event. */
- (NSXMLElement *)formElement
{
	NSString *elementId = [self selectedId];
	NSXMLElement *element = elementId != nil ? [[self editor] elementWithId:elementId] : nil;
	NSString *type = [element localName];
	return [type isEqualToString:@"userTask"] || [type isEqualToString:@"startEvent"] ? element : nil;
}

- (IBAction)editForm:(id)sender
{
	NSXMLElement *element = [self formElement];
	if (element == nil) {
		[self.host commands:self alert:@"Select a user task or a start event."
		              detail:@"Their forms are what the form designer edits."];
		return;
	}
	NSURL *file = [self.host documentURLForCommands:self];
	if (file == nil) {
		[self.host commands:self alert:@"Save the process first." detail:@"Its forms are kept beside it, and deployed with it."];
		return;
	}
	NSXMLDocument *document = [self editor].document;
	NSString *elementId = WKDAttribute(element, @"id");
	NSString *name = WKDEmbeddedFormOf(document, element);
	BOOL named = name != nil;
	if (!named) {
		name = [elementId stringByAppendingPathExtension:@"xhtml"];
	}
	NSURL *form = [[file URLByDeletingLastPathComponent] URLByAppendingPathComponent:name];
	if (![[NSFileManager defaultManager] fileExistsAtPath:[form path]]) {
		NSError *error = nil;
		NSXMLDocument *made = WKDGeneratedForm(document, elementId, &error);
		if (made == nil || ![[made XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement]
		                       writeToURL:form options:NSDataWritingAtomic error:&error]) {
			[self.host commands:self alert:[NSString stringWithFormat:@"Could not make %@.", name]
			              detail:[error localizedDescription]];
			return;
		}
	}
	if (!named) {
		/* One change: the key that names it, undone like any other. */
		[[self editor] edit:elementId action:@"Form key" with:^(NSXMLElement *edited, NSXMLDocument *xml) {
			WKDSetQualifiedAttribute(xml, edited, WKDCamundaNamespace, @"formKey",
			                         [@"embedded:deployment:" stringByAppendingString:name]);
		}];
	}
	[self.host commands:self open:form decision:nil];
}

/* The business rule task selected. */
- (NSXMLElement *)decisionElement
{
	NSString *elementId = [self selectedId];
	NSXMLElement *element = elementId != nil ? [[self editor] elementWithId:elementId] : nil;
	return [[element localName] isEqualToString:@"businessRuleTask"] ? element : nil;
}

- (IBAction)editDecision:(id)sender
{
	NSXMLElement *element = [self decisionElement];
	if (element == nil) {
		[self.host commands:self alert:@"Select a business rule task."
		              detail:@"Its decision is what the decision editor edits."];
		return;
	}
	NSURL *file = [self.host documentURLForCommands:self];
	if (file == nil) {
		[self.host commands:self alert:@"Save the process first."
		              detail:@"Its decisions are kept beside it, and deployed with it."];
		return;
	}
	NSXMLDocument *document = [self editor].document;
	NSString *elementId = WKDAttribute(element, @"id");
	NSString *key = WKDQualifiedAttribute(document, element, WKDCamundaNamespace, @"decisionRef");
	if ([key hasPrefix:@"${"] || [key hasPrefix:@"#{"] || [key hasPrefix:@"="]) {
		[self.host commands:self alert:@"The task names its decision by an expression."
		              detail:@"Which decision it evaluates is known only as it runs."];
		return;
	}
	BOOL named = [key length] > 0;
	if (!named) {
		key = elementId;
	}
	NSURL *directory = [file URLByDeletingLastPathComponent];
	NSString *name = WKDDecisionFileDefining(key, directory, [self.host editedResourcesForCommands:self])
		?: [key stringByAppendingPathExtension:@"dmn"];
	NSURL *url = [directory URLByAppendingPathComponent:name];
	if (![[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
		/* A file of its own, whose one table is the decision. */
		WKDDmnEditor *made = [[WKDDmnEditor alloc] initWithDocument:[WKDDmnEditor newDecisionsDocument] undoManager:nil];
		NSString *first = [made.decisions firstObject].decisionId;
		NSString *title = WKDAttribute(element, @"name");
		[made renameDecision:first to:key error:NULL];
		[made setName:[title length] > 0 ? title : key of:key];
		NSError *error = nil;
		if (![[made.document XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement]
		        writeToURL:url options:NSDataWritingAtomic error:&error]) {
			[self.host commands:self alert:[NSString stringWithFormat:@"Could not make %@.", name]
			              detail:[error localizedDescription]];
			return;
		}
	}
	if (!named) {
		[[self editor] edit:elementId action:@"Decision" with:^(NSXMLElement *edited, NSXMLDocument *xml) {
			WKDSetQualifiedAttribute(xml, edited, WKDCamundaNamespace, @"decisionRef", key);
		}];
	}
	[self.host commands:self open:url decision:key];
}

#pragma mark Validation

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	SEL action = [item action];
	if (action == @selector(editForm:)) {
		return [self formElement] != nil;
	}
	if (action == @selector(editDecision:)) {
		return [self decisionElement] != nil;
	}
	if (action == @selector(addPool:)) {
		return [self editor].model.pool == nil;
	}
	if (action == @selector(copy:) || action == @selector(cut:) || action == @selector(duplicate:)) {
		return [[self selection].selectedIds count] > 0;
	}
	NSString *name = NSStringFromSelector(action);
	if ([name hasPrefix:@"align"]) {
		return [[self selectedShapes] count] >= 2;
	}
	if ([name hasPrefix:@"distribute"]) {
		return [[self selectedShapes] count] >= 3;
	}
	if (action == @selector(rename:) || action == @selector(changeType:)) {
		return [self selectedId] != nil;
	}
	if (action == @selector(paste:)) {
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		return [pasteboard availableTypeFromArray:@[ WKDFragmentPasteboardType, NSPasteboardTypeString ]] != nil;
	}
	return YES;
}

@end

#import "WKDDecisions.h"
#import "WKDDmnModelPriv.h"
#import "WKDXML.h"

NSArray<NSString *> *
WKDDmnTypes(void)
{
	return @[ @"string", @"boolean", @"integer", @"long", @"double", @"date" ];
}

NSArray<NSArray<NSString *> *> *
WKDDmnHitPolicies(void)
{
	return @[ @[ @"UNIQUE", @"", @"Unique" ], @[ @"FIRST", @"", @"First" ], @[ @"ANY", @"", @"Any" ],
	          @[ @"RULE ORDER", @"", @"Rule order" ], @[ @"COLLECT", @"", @"Collect" ],
	          @[ @"COLLECT", @"SUM", @"Collect (sum)" ], @[ @"COLLECT", @"MIN", @"Collect (min)" ],
	          @[ @"COLLECT", @"MAX", @"Collect (max)" ], @[ @"COLLECT", @"COUNT", @"Collect (count)" ] ];
}

static NSString *
WKDNonEmpty(NSString *text)
{
	return [text length] > 0 ? text : nil;
}

/* What is typed, as the file is read back: without the space round it. */
static NSString *
WKDTrimmed(NSString *text)
{
	return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

@implementation WKDDmnEditor
{
	NSUndoManager *_undoManager;
}

+ (NSXMLDocument *)newDecisionsDocument
{
	NSXMLElement *root = [[NSXMLElement alloc] initWithName:@"definitions" URI:WKDDmn13Namespace];
	[root addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:WKDDmn13Namespace]];
	NSDictionary *namespaces = @{ @"dmndi": WKDDmnDI13Namespace, @"dc": WKDDmnDCNamespace,
	                              @"di": WKDDmnDINamespace, @"camunda": WKDCamundaDmnNamespace };
	for (NSString *prefix in @[ @"dmndi", @"dc", @"di", @"camunda" ]) {
		[root addNamespace:[NSXMLNode namespaceWithName:prefix stringValue:[namespaces objectForKey:prefix]]];
	}
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:root];
	[document setVersion:@"1.0"];
	[document setCharacterEncoding:@"UTF-8"];
	WKDSetAttribute(root, @"id", @"Definitions_1");
	WKDSetAttribute(root, @"name", @"Decisions");
	WKDSetAttribute(root, @"namespace", @"https://workflowkit.local/dmn");
	WKDSetAttribute(root, @"exporter", @"WorkflowDesigner");
	NSXMLElement *dmndi = WKDNewElement(document, WKDDmnDI13Namespace, @"DMNDI");
	[root addChild:dmndi];
	NSXMLElement *diagram = WKDNewElement(document, WKDDmnDI13Namespace, @"DMNDiagram");
	WKDSetAttribute(diagram, @"id", @"DMNDiagram_1");
	[dmndi addChild:diagram];
	WKDDmnEditor *editor = [[self alloc] initWithDocument:document undoManager:nil];
	[editor addDecisionTable:YES withId:nil];
	return editor.document;
}

- (instancetype)initWithDocument:(NSXMLDocument *)document undoManager:(NSUndoManager *)undoManager
{
	if ((self = [super init])) {
		_document = document;
		_undoManager = undoManager;
		_model = [WKDDmnModel modelOfDocument:document];
	}
	return self;
}

NSString * const WKDDmnEditorDidChangeNotification = @"WKDDmnEditorDidChange";
NSString * const WKDDmnEditorWillRenameNotification = @"WKDDmnEditorWillRename";

static BOOL WKDDmnChecksAgreement = NO;

+ (BOOL)checksAgreement
{
	return WKDDmnChecksAgreement;
}

+ (void)setChecksAgreement:(BOOL)checks
{
	WKDDmnChecksAgreement = checks;
}

- (NSArray<WKDDmnDecision *> *)decisions
{
	return _model.decisions;
}

- (WKDDmnDecision *)decisionWithId:(NSString *)decisionId
{
	return [_model decisionWithId:decisionId];
}

#pragma mark Changes

/* One undoable step: what it changes in the model, and what that writes,
 * is what undo takes back. NO, and no step, when there is no such
 * decision. */
- (BOOL)change:(NSString *)name of:(NSString *)decisionId with:(void (^)(WKDDmnDecision *decision))change
{
	WKDDmnDecision *decision = decisionId != nil ? [_model decisionWithId:decisionId] : nil;
	if (decisionId != nil && decision == nil) {
		return NO;
	}
	WKDJournal *journal = _model.journal;
	[journal begin];
	change(decision);
	[_model write];
	WKDJournalStep *step = [journal end];
	if (step != nil) {
		[_undoManager registerUndoWithTarget:self selector:@selector(undoStep:) object:step];
		[_undoManager setActionName:name];
	}
	[self didChange];
	return YES;
}

- (void)undoStep:(WKDJournalStep *)step
{
	WKDJournalStep *inverse = [_model.journal undo:step];
	[_undoManager registerUndoWithTarget:self selector:@selector(undoStep:) object:inverse];
	[self didChange];
}

- (void)didChange
{
	if (WKDDmnChecksAgreement) {
		NSString *disagreement = [_model disagreementWith:[WKDDmnModel modelOfDocument:_document]]
			?: [_model.journal indexDisagreement];
		if (disagreement != nil) {
			[NSException raise:NSInternalInconsistencyException format:@"the model disagrees with its document: %@",
			                   disagreement];
		}
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDDmnEditorDidChangeNotification object:self];
}

#pragma mark Decisions

- (NSString *)addDecisionTable:(BOOL)table withId:(NSString *)decisionId
{
	__block NSString *made = nil;
	[self change:@"Add Decision" of:nil with:^(WKDDmnDecision *unused) {
		WKDDmnModel *model = self->_model;
		BOOL free = decisionId != nil && WKDIsName(decisionId) && [model.journal elementWithId:decisionId] == nil
			&& [model decisionWithId:decisionId] == nil;
		made = free ? decisionId : [model freshId:@"Decision"];
		[model makeDecisionWithId:made table:table];
	}];
	return made;
}

- (void)deleteDecision:(NSString *)decisionId
{
	[self change:@"Delete Decision" of:decisionId with:^(WKDDmnDecision *decision) {
		[self->_model removeDecision:decision];
	}];
}

- (BOOL)renameDecision:(NSString *)decisionId to:(NSString *)newId error:(NSString **)reason
{
	NSString *refusal = nil;
	if ([newId isEqualToString:decisionId]) {
		return YES;
	}
	if (!WKDIsName(newId)) {
		refusal = @"An id is a letter or _, then letters, digits, -, _ and dots.";
	} else if ([_model.journal elementWithId:newId] != nil || [_model decisionWithId:newId] != nil) {
		refusal = [NSString stringWithFormat:@"%@ is the id of another element.", newId];
	} else if ([_model decisionWithId:decisionId] == nil) {
		refusal = @"There is no such decision.";
	}
	if (refusal != nil) {
		if (reason != NULL) {
			*reason = refusal;
		}
		return NO;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:WKDDmnEditorWillRenameNotification object:self
	                                                  userInfo:@{ @"from": decisionId, @"to": newId }];
	return [self change:@"Rename" of:decisionId with:^(WKDDmnDecision *decision) {
		WKDJournal *journal = self->_model.journal;
		[self->_model renameDecision:decision to:newId];
		/* What refers to it beyond the model: requirements of input data's
		 * kind aside, the diagram's elements and any other href. */
		NSString *href = [@"#" stringByAppendingString:decisionId];
		NSMutableArray *pending = [NSMutableArray arrayWithObject:[self->_document rootElement]];
		while ([pending count] > 0) {
			NSXMLElement *element = [pending lastObject];
			[pending removeLastObject];
			if ([WKDAttribute(element, @"href") isEqualToString:href]) {
				WKDLogAttribute(journal, element, @"href", [@"#" stringByAppendingString:newId]);
			}
			if ([WKDAttribute(element, @"dmnElementRef") isEqualToString:decisionId]) {
				WKDLogAttribute(journal, element, @"dmnElementRef", newId);
			}
			for (NSXMLNode *child in [element children]) {
				if ([child kind] == NSXMLElementKind) {
					[pending addObject:child];
				}
			}
		}
	}];
}

- (void)setName:(NSString *)name of:(NSString *)decisionId
{
	[self change:@"Name" of:decisionId with:^(WKDDmnDecision *decision) {
		[decision willChange];
		decision.name = WKDNonEmpty(name);
	}];
}

- (void)setHitPolicy:(NSString *)hitPolicy aggregation:(NSString *)aggregation of:(NSString *)decisionId
{
	if (![_model decisionWithId:decisionId].table) {
		return;
	}
	[self change:@"Hit Policy" of:decisionId with:^(WKDDmnDecision *decision) {
		BOOL collect = [hitPolicy isEqualToString:@"COLLECT"];
		[decision willChange];
		decision.hitPolicy = [hitPolicy length] > 0 ? hitPolicy : @"UNIQUE";
		decision.aggregation = collect ? WKDNonEmpty(aggregation) : nil;
	}];
}

/* Whether `from` requires `target`, directly or through others, with the
 * requirements as they would be. */
static BOOL
WKDRequires(NSString *from, NSString *target, NSDictionary<NSString *, NSArray *> *requirements, NSMutableSet *seen)
{
	for (NSString *required in [requirements objectForKey:from]) {
		if ([required isEqualToString:target]) {
			return YES;
		}
		if (![seen containsObject:required]) {
			[seen addObject:required];
			if (WKDRequires(required, target, requirements, seen)) {
				return YES;
			}
		}
	}
	return NO;
}

- (BOOL)setRequired:(NSArray<NSString *> *)required of:(NSString *)decisionId error:(NSString **)reason
{
	NSMutableDictionary *requirements = [NSMutableDictionary dictionary];
	for (WKDDmnDecision *decision in _model.decisions) {
		[requirements setObject:decision.required forKey:decision.decisionId];
	}
	[requirements setObject:required forKey:decisionId];
	NSString *refusal = nil;
	for (NSString *other in required) {
		if ([_model decisionWithId:other] == nil) {
			refusal = [NSString stringWithFormat:@"The file defines no decision %@.", other];
		} else if ([other isEqualToString:decisionId]
		           || WKDRequires(other, decisionId, requirements, [NSMutableSet set])) {
			refusal = [NSString stringWithFormat:@"%@ requires %@ already.", other, decisionId];
		}
		if (refusal != nil) {
			break;
		}
	}
	if (refusal != nil || [_model decisionWithId:decisionId] == nil) {
		if (reason != NULL) {
			*reason = refusal ?: @"There is no such decision.";
		}
		return NO;
	}
	return [self change:@"Requirements" of:decisionId with:^(WKDDmnDecision *decision) {
		WKDDmnModel *model = self->_model;
		NSMutableArray *kept = [NSMutableArray array];
		for (WKDDmnRequirement *requirement in [decision.requirementList copy]) {
			if ([required containsObject:requirement.requiredId]) {
				[kept addObject:requirement.requiredId];
			} else {
				[model removeRequirement:requirement];
			}
		}
		for (NSString *other in required) {
			if (![kept containsObject:other]) {
				[model makeRequirementOf:decision on:[model decisionWithId:other]];
			}
		}
	}];
}

#pragma mark Tables

/* Which kind the column is, and its index among them. */
- (BOOL)column:(NSUInteger)column of:(WKDDmnDecision *)decision output:(BOOL *)output index:(NSUInteger *)index
{
	NSUInteger inputs = [decision.inputList count];
	if (decision == nil || column >= inputs + [decision.outputList count]) {
		return NO;
	}
	*output = column >= inputs;
	*index = *output ? column - inputs : column;
	return YES;
}

- (NSUInteger)insertColumn:(BOOL)output at:(NSUInteger)index of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	if (!decision.table) {
		return NSNotFound;
	}
	index = MIN(index, [output ? decision.outputList : decision.inputList count]);
	[self change:output ? @"Add Output" : @"Add Input" of:decisionId with:^(WKDDmnDecision *changed) {
		[self->_model makeColumn:output at:index of:changed];
	}];
	return output ? [decision.inputList count] + index : index;
}

- (void)deleteColumn:(NSUInteger)column of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	BOOL output;
	NSUInteger index;
	if (![self column:column of:decision output:&output index:&index]) {
		return;
	}
	[self change:output ? @"Delete Output" : @"Delete Input" of:decisionId with:^(WKDDmnDecision *changed) {
		[self->_model removeColumn:[changed.columns objectAtIndex:column]];
	}];
}

- (void)moveColumn:(NSUInteger)column to:(NSUInteger)target of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	BOOL output;
	NSUInteger index;
	if (![self column:column of:decision output:&output index:&index]) {
		return;
	}
	NSUInteger count = output ? [decision.outputList count] : [decision.inputList count];
	NSUInteger first = output ? [decision.inputList count] : 0;
	NSUInteger to = MIN(MAX(target, first), first + count - 1) - first;
	if (to == index) {
		return;
	}
	[self change:@"Move Column" of:decisionId with:^(WKDDmnDecision *changed) {
		[changed willChange];
		NSMutableArray *list = output ? changed.outputList : changed.inputList;
		WKDDmnColumn *moved = [list objectAtIndex:index];
		[list removeObjectAtIndex:index];
		[list insertObject:moved atIndex:to];
		for (WKDDmnRule *rule in changed.ruleList) {
			[rule willChange];
			WKDDmnEntry *entry = [rule.entryList objectAtIndex:first + index];
			[rule.entryList removeObjectAtIndex:first + index];
			[rule.entryList insertObject:entry atIndex:first + to];
		}
	}];
}

- (void)setColumn:(NSUInteger)column property:(NSString *)property to:(NSString *)value of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	BOOL output;
	NSUInteger index;
	if (![self column:column of:decision output:&output index:&index]) {
		return;
	}
	NSDictionary *actions = @{ @"label": @"Label", @"expression": @"Input Expression", @"typeRef": @"Type",
	                           @"inputVariable": @"Input Variable", @"name": @"Output Name" };
	if ([actions objectForKey:property] == nil || (output && ([property isEqualToString:@"expression"]
	                                                         || [property isEqualToString:@"inputVariable"]))
	    || (!output && [property isEqualToString:@"name"])) {
		return;
	}
	[self change:[actions objectForKey:property] of:decisionId with:^(WKDDmnDecision *changed) {
		WKDDmnColumn *clause = [changed.columns objectAtIndex:column];
		[clause willChange];
		if ([property isEqualToString:@"expression"]) {
			clause.expression = WKDTrimmed(value);
		} else {
			[clause setValue:WKDNonEmpty(value) forKey:property];
		}
	}];
}

- (void)insertRuleAt:(NSUInteger)index of:(NSString *)decisionId
{
	if (![_model decisionWithId:decisionId].table) {
		return;
	}
	[self change:@"Add Rule" of:decisionId with:^(WKDDmnDecision *decision) {
		[self->_model makeRuleAt:index of:decision];
	}];
}

- (void)duplicateRule:(NSUInteger)rule of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	if (rule >= [decision.ruleList count]) {
		return;
	}
	[self change:@"Duplicate Rule" of:decisionId with:^(WKDDmnDecision *changed) {
		WKDDmnModel *model = self->_model;
		WKDDmnRule *original = [changed.ruleList objectAtIndex:rule];
		WKDDmnRule *copy = [model makeRuleAt:rule + 1 of:changed];
		copy.annotation = original.annotation;
		/* The copy is the original's XML, what the model does not hold
		 * included, under the copy's ids. */
		NSXMLElement *element = [original.element copy];
		WKDSetAttribute(element, @"id", copy.ruleId);
		[model carry:element];
		NSArray *inputs = WKDChildren(element, model.dmn, @"inputEntry");
		NSArray *outputs = WKDChildren(element, model.dmn, @"outputEntry");
		NSUInteger inputCount = [changed.inputList count];
		for (NSUInteger i = 0; i < [copy.entryList count]; i++) {
			WKDDmnEntry *entry = [copy.entryList objectAtIndex:i];
			entry.text = [[original.entryList objectAtIndex:i] text];
			NSArray *carriers = entry.output ? outputs : inputs;
			NSUInteger at = entry.output ? i - inputCount : i;
			if (at < [carriers count]) {
				entry.element = [carriers objectAtIndex:at];
				WKDSetAttribute(entry.element, @"id", entry.entryId);
				[model carry:entry.element];
			}
		}
		copy.element = element;
	}];
}

- (void)deleteRules:(NSIndexSet *)indexes of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	if ([indexes count] == 0 || [indexes lastIndex] >= [decision.ruleList count]) {
		return;
	}
	[self change:[indexes count] == 1 ? @"Delete Rule" : @"Delete Rules" of:decisionId with:^(WKDDmnDecision *changed) {
		for (WKDDmnRule *rule in [changed.ruleList objectsAtIndexes:indexes]) {
			[self->_model removeRule:rule];
		}
	}];
}

- (void)moveRule:(NSUInteger)rule to:(NSUInteger)index of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	NSUInteger count = [decision.ruleList count];
	if (rule >= count || MIN(index, count - 1) == rule) {
		return;
	}
	[self change:@"Move Rule" of:decisionId with:^(WKDDmnDecision *changed) {
		[changed willChange];
		WKDDmnRule *moved = [changed.ruleList objectAtIndex:rule];
		[changed.ruleList removeObjectAtIndex:rule];
		[changed.ruleList insertObject:moved atIndex:MIN(index, count - 1)];
	}];
}

- (void)setEntry:(NSString *)text rule:(NSUInteger)rule column:(NSUInteger)column of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	BOOL output;
	NSUInteger index;
	if (![self column:column of:decision output:&output index:&index] || rule >= [decision.ruleList count]) {
		return;
	}
	[self change:@"Entry" of:decisionId with:^(WKDDmnDecision *changed) {
		WKDDmnEntry *entry = [[[changed.ruleList objectAtIndex:rule] entryList] objectAtIndex:column];
		[entry willChange];
		entry.text = WKDTrimmed(text);
	}];
}

- (void)setAnnotation:(NSString *)text rule:(NSUInteger)rule of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	if (rule >= [decision.ruleList count]) {
		return;
	}
	[self change:@"Annotation" of:decisionId with:^(WKDDmnDecision *changed) {
		WKDDmnRule *annotated = [changed.ruleList objectAtIndex:rule];
		[annotated willChange];
		annotated.annotation = WKDTrimmed(text);
	}];
}

#pragma mark Literal expressions

- (void)setLiteral:(NSString *)property to:(NSString *)value of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [_model decisionWithId:decisionId];
	NSDictionary *actions = @{ @"expression": @"Expression", @"variableName": @"Variable", @"variableType": @"Type" };
	if (decision == nil || decision.table || [actions objectForKey:property] == nil) {
		return;
	}
	[self change:[actions objectForKey:property] of:decisionId with:^(WKDDmnDecision *changed) {
		[changed willChange];
		if ([property isEqualToString:@"expression"]) {
			changed.expression = WKDTrimmed(value);
		} else if ([property isEqualToString:@"variableName"]) {
			changed.variableName = WKDNonEmpty(value);
		} else {
			/* None of its own: the expression's, as the file is read. */
			changed.variableType = WKDNonEmpty(value) ?: WKDAttribute(changed.literalElement, @"typeRef");
		}
	}];
}

@end

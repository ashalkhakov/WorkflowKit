#import "WKDDmnModelPriv.h"

NSString * const WKDDmn13Namespace = @"https://www.omg.org/spec/DMN/20191111/MODEL/";
NSString * const WKDDmnDI13Namespace = @"https://www.omg.org/spec/DMN/20191111/DMNDI/";
NSString * const WKDDmnDCNamespace = @"http://www.omg.org/spec/DMN/20180521/DC/";
NSString * const WKDDmnDINamespace = @"http://www.omg.org/spec/DMN/20180521/DI/";

@implementation WKDDmnElement

+ (NSArray<NSString *> *)journalKeys
{
	return @[ @"element" ];
}

- (NSDictionary *)journalState
{
	NSMutableDictionary *state = [NSMutableDictionary dictionary];
	for (NSString *key in [[self class] journalKeys]) {
		id value = [self valueForKey:key];
		if ([value isKindOfClass:[NSMutableArray class]]) {
			value = [value copy];
		}
		[state setObject:value ?: [NSNull null] forKey:key];
	}
	return state;
}

- (void)restoreJournalState:(NSDictionary *)state
{
	for (NSString *key in state) {
		id value = [state objectForKey:key];
		if (value == [NSNull null]) {
			value = nil;
		} else if ([value isKindOfClass:[NSArray class]]) {
			value = [value mutableCopy];
		}
		[self setValue:value forKey:key];
	}
}

- (void)willChange
{
	[self.model.journal willChange:self];
	[self.model.changedElements addObject:self];
}

/* BOOL properties set to nil from a state: NO. */
- (void)setNilValueForKey:(NSString *)key
{
	[self setValue:@NO forKey:key];
}

@end

@implementation WKDDmnEntry

+ (NSArray<NSString *> *)journalKeys
{
	return [[super journalKeys] arrayByAddingObjectsFromArray:@[ @"rule", @"entryId", @"output", @"text" ]];
}

@end

@implementation WKDDmnRequirement

+ (NSArray<NSString *> *)journalKeys
{
	return [[super journalKeys] arrayByAddingObjectsFromArray:@[
		@"decision", @"requirementId", @"requiredId", @"requiredDecision", @"edgeElement" ]];
}

@end

@implementation WKDDmnColumn

+ (NSArray<NSString *> *)journalKeys
{
	return [[super journalKeys] arrayByAddingObjectsFromArray:@[
		@"decision", @"columnId", @"output", @"label", @"typeRef", @"expression", @"inputVariable", @"name",
		@"expressionElement", @"expressionId" ]];
}

- (NSString *)title
{
	for (NSString *title in @[ self.label ?: @"", (self.output ? self.name : self.expression) ?: @"" ]) {
		if ([title length] > 0) {
			return title;
		}
	}
	return self.output ? @"Output" : @"Input";
}

@end

@implementation WKDDmnRule

- (instancetype)init
{
	if ((self = [super init])) {
		_entryList = [NSMutableArray array];
		_annotation = @"";
	}
	return self;
}

+ (NSArray<NSString *> *)journalKeys
{
	return [[super journalKeys] arrayByAddingObjectsFromArray:@[ @"decision", @"ruleId", @"annotation", @"entryList" ]];
}

- (NSArray<NSString *> *)entries
{
	NSMutableArray *texts = [NSMutableArray arrayWithCapacity:[_entryList count]];
	for (WKDDmnEntry *entry in _entryList) {
		[texts addObject:entry.text ?: @""];
	}
	return texts;
}

@end

@implementation WKDDmnDecision

- (instancetype)init
{
	if ((self = [super init])) {
		_inputList = [NSMutableArray array];
		_outputList = [NSMutableArray array];
		_ruleList = [NSMutableArray array];
		_requirementList = [NSMutableArray array];
		_dependentList = [NSMutableArray array];
	}
	return self;
}

+ (NSArray<NSString *> *)journalKeys
{
	return [[super journalKeys] arrayByAddingObjectsFromArray:@[
		@"decisionId", @"name", @"table", @"hitPolicy", @"aggregation", @"expression", @"variableName",
		@"variableType", @"inputList", @"outputList", @"ruleList", @"requirementList", @"dependentList",
		@"tableElement", @"tableId", @"literalElement", @"literalId", @"variableElement", @"variableId",
		@"shapeElement" ]];
}

- (NSArray<WKDDmnColumn *> *)inputs { return [_inputList copy]; }
- (NSArray<WKDDmnColumn *> *)outputs { return [_outputList copy]; }
- (NSArray<WKDDmnRule *> *)rules { return [_ruleList copy]; }

- (NSArray<WKDDmnColumn *> *)columns
{
	return [_inputList arrayByAddingObjectsFromArray:_outputList];
}

- (NSArray<NSString *> *)required
{
	NSMutableArray *ids = [NSMutableArray arrayWithCapacity:[_requirementList count]];
	for (WKDDmnRequirement *requirement in _requirementList) {
		[ids addObject:requirement.requiredId];
	}
	return ids;
}

- (NSArray<WKDDmnDecision *> *)requiredBy
{
	NSMutableArray *decisions = [NSMutableArray array];
	for (WKDDmnRequirement *requirement in _dependentList) {
		if (requirement.decision != nil && [decisions indexOfObjectIdenticalTo:requirement.decision] == NSNotFound) {
			[decisions addObject:requirement.decision];
		}
	}
	return decisions;
}

- (NSString *)title
{
	return [self.name length] > 0 ? self.name : self.decisionId;
}

@end

@implementation WKDDmnModel
{
	/* Ids handed out to elements not yet written. */
	NSMutableSet<NSString *> *_pendingIds;
	/* Every element the model holds as its own: kept as themselves when
	 * the XML round them is put back. */
	NSHashTable<NSXMLNode *> *_carriers;
}

+ (instancetype)modelOfDocument:(NSXMLDocument *)document
{
	WKDDmnModel *model = [[self alloc] init];
	[model readDocument:document];
	return model;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_decisionList = [NSMutableArray array];
		_decisionsById = [NSMutableDictionary dictionary];
		_changedElements = [NSMutableSet set];
		_deletedElements = [NSMutableArray array];
		_pendingIds = [NSMutableSet set];
		_carriers = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
		_journal = [[WKDJournal alloc] initWithModel:self];
	}
	return self;
}

- (NSArray<WKDDmnDecision *> *)decisions
{
	return [_decisionList copy];
}

- (WKDDmnDecision *)decisionWithId:(NSString *)decisionId
{
	return decisionId != nil ? [_decisionsById objectForKey:decisionId] : nil;
}

- (BOOL)hasChanges
{
	return [_changedElements count] > 0 || [_deletedElements count] > 0;
}

- (void)write
{
	if (![self hasChanges]) {
		return;
	}
	[self writeChanges];
	[_pendingIds removeAllObjects];
}

- (NSString *)freshId:(NSString *)prefix
{
	for (NSUInteger n = 1;; n++) {
		NSString *candidate = [NSString stringWithFormat:@"%@_%lu", prefix, (unsigned long)n];
		if (![_pendingIds containsObject:candidate] && [_journal elementWithId:candidate] == nil) {
			[_pendingIds addObject:candidate];
			return candidate;
		}
	}
}

#pragma mark The journal

- (NSDictionary *)journalState
{
	return @{ @"decisionList": [_decisionList copy], @"decisionsById": [_decisionsById copy],
	          @"diagram": _diagram ?: [NSNull null] };
}

- (void)restoreJournalState:(NSDictionary *)state
{
	_decisionList = [[state objectForKey:@"decisionList"] mutableCopy];
	_decisionsById = [[state objectForKey:@"decisionsById"] mutableCopy];
	id diagram = [state objectForKey:@"diagram"];
	_diagram = diagram != [NSNull null] ? diagram : nil;
}

- (void)journalDidRestore
{
	[_changedElements removeAllObjects];
	[_deletedElements removeAllObjects];
}

- (void)carry:(NSXMLNode *)node
{
	if (node != nil) {
		[_carriers addObject:node];
	}
}

- (BOOL)carries:(NSXMLNode *)node
{
	return [_carriers containsObject:node];
}

#pragma mark Making and removing

- (NSString *)uniqueOutputName:(WKDDmnDecision *)decision
{
	NSMutableSet *names = [NSMutableSet set];
	for (WKDDmnColumn *existing in decision.outputList) {
		if (existing.name != nil) {
			[names addObject:existing.name];
		}
	}
	NSString *name = @"result";
	for (NSUInteger n = 2; [names containsObject:name]; n++) {
		name = [NSString stringWithFormat:@"result%lu", (unsigned long)n];
	}
	return name;
}

- (WKDDmnColumn *)newColumn:(BOOL)output of:(WKDDmnDecision *)decision
{
	WKDDmnColumn *column = [[WKDDmnColumn alloc] init];
	column.model = self;
	column.decision = decision;
	column.output = output;
	column.typeRef = @"string";
	if (output) {
		column.columnId = [self freshId:@"OutputClause"];
		column.name = [self uniqueOutputName:decision];
	} else {
		column.columnId = [self freshId:@"InputClause"];
		column.expressionId = [self freshId:@"LiteralExpression"];
		column.expression = @"";
	}
	[column willChange];
	return column;
}

- (WKDDmnEntry *)newEntry:(BOOL)output of:(WKDDmnRule *)rule
{
	WKDDmnEntry *entry = [[WKDDmnEntry alloc] init];
	entry.model = self;
	entry.rule = rule;
	entry.output = output;
	entry.entryId = [self freshId:output ? @"LiteralExpression" : @"UnaryTests"];
	entry.text = @"";
	[entry willChange];
	return entry;
}

- (WKDDmnDecision *)makeDecisionWithId:(NSString *)decisionId table:(BOOL)table
{
	[_journal willChangeModel];
	WKDDmnDecision *decision = [[WKDDmnDecision alloc] init];
	decision.model = self;
	decision.decisionId = decisionId;
	[_pendingIds addObject:decisionId];
	[decision willChange];
	decision.name = [decisionId stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	decision.table = table;
	if (table) {
		decision.tableId = [self freshId:@"DecisionTable"];
		decision.hitPolicy = @"UNIQUE";
		[decision.inputList addObject:[self newColumn:NO of:decision]];
		[decision.outputList addObject:[self newColumn:YES of:decision]];
	} else {
		decision.variableId = [self freshId:@"InformationItem"];
		decision.variableName = @"result";
		decision.variableType = @"string";
		decision.literalId = [self freshId:@"LiteralExpression"];
		decision.expression = @"";
	}
	[_decisionList addObject:decision];
	[_decisionsById setObject:decision forKey:decisionId];
	return decision;
}

- (void)removeDecision:(WKDDmnDecision *)decision
{
	if (![self containsElement:decision]) {
		return;
	}
	[_journal willChangeModel];
	for (WKDDmnRequirement *requirement in [decision.requirementList copy]) {
		[self removeRequirement:requirement];
	}
	for (WKDDmnRequirement *requirement in [decision.dependentList copy]) {
		[self removeRequirement:requirement];
	}
	[decision willChange];
	[_decisionList removeObjectIdenticalTo:decision];
	[_decisionsById removeObjectForKey:decision.decisionId];
	[_deletedElements addObject:decision];
}

- (WKDDmnColumn *)makeColumn:(BOOL)output at:(NSUInteger)index of:(WKDDmnDecision *)decision
{
	[decision willChange];
	WKDDmnColumn *column = [self newColumn:output of:decision];
	NSMutableArray *list = output ? decision.outputList : decision.inputList;
	index = MIN(index, [list count]);
	[list insertObject:column atIndex:index];
	NSUInteger at = output ? [decision.inputList count] + index : index;
	for (WKDDmnRule *rule in decision.ruleList) {
		[rule willChange];
		[rule.entryList insertObject:[self newEntry:output of:rule] atIndex:MIN(at, [rule.entryList count])];
	}
	return column;
}

- (void)removeColumn:(WKDDmnColumn *)column
{
	WKDDmnDecision *decision = column.decision;
	NSUInteger at = [decision.inputList indexOfObjectIdenticalTo:column];
	if (at == NSNotFound) {
		NSUInteger index = [decision.outputList indexOfObjectIdenticalTo:column];
		if (index == NSNotFound) {
			return;
		}
		at = [decision.inputList count] + index;
	}
	[decision willChange];
	[column willChange];
	for (WKDDmnRule *rule in decision.ruleList) {
		if (at < [rule.entryList count]) {
			[rule willChange];
			WKDDmnEntry *entry = [rule.entryList objectAtIndex:at];
			[entry willChange];
			[rule.entryList removeObjectAtIndex:at];
			[_deletedElements addObject:entry];
		}
	}
	[decision.inputList removeObjectIdenticalTo:column];
	[decision.outputList removeObjectIdenticalTo:column];
	[_deletedElements addObject:column];
}

- (WKDDmnRule *)makeRuleAt:(NSUInteger)index of:(WKDDmnDecision *)decision
{
	[decision willChange];
	WKDDmnRule *rule = [[WKDDmnRule alloc] init];
	rule.model = self;
	rule.decision = decision;
	rule.ruleId = [self freshId:@"DecisionRule"];
	[rule willChange];
	for (WKDDmnColumn *column in decision.columns) {
		[rule.entryList addObject:[self newEntry:column.output of:rule]];
	}
	[decision.ruleList insertObject:rule atIndex:MIN(index, [decision.ruleList count])];
	return rule;
}

- (void)removeRule:(WKDDmnRule *)rule
{
	WKDDmnDecision *decision = rule.decision;
	if ([decision.ruleList indexOfObjectIdenticalTo:rule] == NSNotFound) {
		return;
	}
	[decision willChange];
	[rule willChange];
	[decision.ruleList removeObjectIdenticalTo:rule];
	[_deletedElements addObject:rule];
}

- (WKDDmnRequirement *)makeRequirementOf:(WKDDmnDecision *)decision on:(WKDDmnDecision *)required
{
	[decision willChange];
	[required willChange];
	WKDDmnRequirement *requirement = [[WKDDmnRequirement alloc] init];
	requirement.model = self;
	requirement.decision = decision;
	requirement.requirementId = [self freshId:@"InformationRequirement"];
	requirement.requiredId = required.decisionId;
	requirement.requiredDecision = required;
	[requirement willChange];
	[decision.requirementList addObject:requirement];
	[required.dependentList addObject:requirement];
	return requirement;
}

- (void)removeRequirement:(WKDDmnRequirement *)requirement
{
	WKDDmnDecision *decision = requirement.decision;
	if ([decision.requirementList indexOfObjectIdenticalTo:requirement] == NSNotFound) {
		return;
	}
	[decision willChange];
	[requirement willChange];
	[decision.requirementList removeObjectIdenticalTo:requirement];
	if (requirement.requiredDecision != nil) {
		[requirement.requiredDecision willChange];
		[requirement.requiredDecision.dependentList removeObjectIdenticalTo:requirement];
	}
	[_deletedElements addObject:requirement];
}

- (void)renameDecision:(WKDDmnDecision *)decision to:(NSString *)decisionId
{
	if ([_decisionsById objectForKey:decision.decisionId] != decision) {
		return;
	}
	[_journal willChangeModel];
	[decision willChange];
	[_decisionsById removeObjectForKey:decision.decisionId];
	decision.decisionId = decisionId;
	[_decisionsById setObject:decision forKey:decisionId];
	for (WKDDmnRequirement *requirement in decision.dependentList) {
		[requirement willChange];
		requirement.requiredId = decisionId;
	}
}

- (BOOL)containsElement:(WKDDmnElement *)element
{
	if ([element isKindOfClass:[WKDDmnDecision class]]) {
		WKDDmnDecision *decision = (WKDDmnDecision *)element;
		return [_decisionsById objectForKey:decision.decisionId] == decision;
	}
	if ([element isKindOfClass:[WKDDmnColumn class]]) {
		WKDDmnColumn *column = (WKDDmnColumn *)element;
		return ([column.decision.inputList indexOfObjectIdenticalTo:column] != NSNotFound
		        || [column.decision.outputList indexOfObjectIdenticalTo:column] != NSNotFound)
			&& [self containsElement:column.decision];
	}
	if ([element isKindOfClass:[WKDDmnRule class]]) {
		WKDDmnRule *rule = (WKDDmnRule *)element;
		return [rule.decision.ruleList indexOfObjectIdenticalTo:rule] != NSNotFound && [self containsElement:rule.decision];
	}
	if ([element isKindOfClass:[WKDDmnEntry class]]) {
		WKDDmnEntry *entry = (WKDDmnEntry *)element;
		return [entry.rule.entryList indexOfObjectIdenticalTo:entry] != NSNotFound && [self containsElement:entry.rule];
	}
	if ([element isKindOfClass:[WKDDmnRequirement class]]) {
		WKDDmnRequirement *requirement = (WKDDmnRequirement *)element;
		return [requirement.decision.requirementList indexOfObjectIdenticalTo:requirement] != NSNotFound
			&& [self containsElement:requirement.decision];
	}
	return NO;
}

@end

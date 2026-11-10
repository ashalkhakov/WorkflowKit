#import "WKDDmnModelPriv.h"
#import "WKDXML.h"

NSString *
WKDDmnText(NSXMLElement *element)
{
	NSXMLElement *text = WKDChild(element, [element URI], @"text");
	return [[text stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

/* The first element below, of any namespace, with the local name. */
static NSXMLElement *
WKDFindLocal(NSXMLElement *element, NSString *local)
{
	for (NSXMLNode *child in [element children]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		if ([[child localName] isEqualToString:local]) {
			return (NSXMLElement *)child;
		}
		NSXMLElement *found = WKDFindLocal((NSXMLElement *)child, local);
		if (found != nil) {
			return found;
		}
	}
	return nil;
}

@implementation WKDDmnModel (WKDDmnReading)

- (void)readDocument:(NSXMLDocument *)document
{
	self.document = document;
	NSXMLElement *root = [document rootElement];
	self.dmn = [root URI] ?: WKDDmn13Namespace;
	self.diagram = WKDFindLocal(root, @"DMNDiagram");
	NSMutableDictionary<NSString *, NSXMLElement *> *shapes = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSXMLElement *> *edges = [NSMutableDictionary dictionary];
	for (NSXMLElement *element in WKDChildren(self.diagram, [self.diagram URI], nil)) {
		NSString *ref = WKDAttribute(element, @"dmnElementRef");
		if (ref == nil) {
			continue;
		}
		if ([[element localName] isEqualToString:@"DMNShape"] && [shapes objectForKey:ref] == nil) {
			[shapes setObject:element forKey:ref];
		} else if ([[element localName] isEqualToString:@"DMNEdge"] && [edges objectForKey:ref] == nil) {
			[edges setObject:element forKey:ref];
		}
	}
	for (NSXMLElement *element in WKDChildren(root, self.dmn, @"decision")) {
		WKDDmnDecision *decision = [self readDecision:element edges:edges];
		decision.shapeElement = [shapes objectForKey:decision.decisionId];
		[self carry:decision.shapeElement];
		[self.decisionList addObject:decision];
		if ([self.decisionsById objectForKey:decision.decisionId] == nil) {
			[self.decisionsById setObject:decision forKey:decision.decisionId];
		}
	}
	for (WKDDmnDecision *decision in self.decisionList) {
		for (WKDDmnRequirement *requirement in decision.requirementList) {
			requirement.requiredDecision = [self decisionWithId:requirement.requiredId];
			[requirement.requiredDecision.dependentList addObject:requirement];
		}
	}
}

- (WKDDmnDecision *)readDecision:(NSXMLElement *)element edges:(NSDictionary *)edges
{
	NSString *dmn = self.dmn;
	WKDDmnDecision *decision = [[WKDDmnDecision alloc] init];
	decision.model = self;
	decision.element = element;
	[self carry:element];
	decision.decisionId = WKDAttribute(element, @"id") ?: @"";
	decision.name = WKDAttribute(element, @"name");
	for (NSXMLElement *carrier in WKDChildren(element, dmn, @"informationRequirement")) {
		NSString *href = WKDAttribute(WKDChild(carrier, dmn, @"requiredDecision"), @"href");
		if (href == nil) {
			continue;
		}
		WKDDmnRequirement *requirement = [[WKDDmnRequirement alloc] init];
		requirement.model = self;
		requirement.element = carrier;
		[self carry:carrier];
		requirement.decision = decision;
		requirement.requirementId = WKDAttribute(carrier, @"id");
		requirement.requiredId = [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href;
		requirement.edgeElement = requirement.requirementId != nil ? [edges objectForKey:requirement.requirementId] : nil;
		[self carry:requirement.edgeElement];
		[decision.requirementList addObject:requirement];
	}
	NSXMLElement *table = WKDChild(element, dmn, @"decisionTable");
	if (table != nil) {
		decision.table = YES;
		decision.tableElement = table;
		[self carry:table];
		decision.tableId = WKDAttribute(table, @"id");
		decision.hitPolicy = WKDAttribute(table, @"hitPolicy") ?: @"UNIQUE";
		decision.aggregation = WKDAttribute(table, @"aggregation");
		for (NSXMLElement *input in WKDChildren(table, dmn, @"input")) {
			WKDDmnColumn *column = [[WKDDmnColumn alloc] init];
			column.model = self;
			column.decision = decision;
			column.element = input;
			[self carry:input];
			NSXMLElement *expression = WKDChild(input, dmn, @"inputExpression");
			column.expressionElement = expression;
			[self carry:expression];
			column.expressionId = WKDAttribute(expression, @"id");
			column.columnId = WKDAttribute(input, @"id");
			column.label = WKDAttribute(input, @"label");
			column.typeRef = WKDAttribute(expression, @"typeRef");
			column.expression = expression != nil ? WKDDmnText(expression) : @"";
			column.inputVariable = WKDQualifiedAttribute(self.document, input, WKDCamundaDmnNamespace, @"inputVariable");
			[decision.inputList addObject:column];
		}
		for (NSXMLElement *output in WKDChildren(table, dmn, @"output")) {
			WKDDmnColumn *column = [[WKDDmnColumn alloc] init];
			column.model = self;
			column.decision = decision;
			column.element = output;
			[self carry:output];
			column.output = YES;
			column.columnId = WKDAttribute(output, @"id");
			column.label = WKDAttribute(output, @"label");
			column.typeRef = WKDAttribute(output, @"typeRef");
			column.name = WKDAttribute(output, @"name");
			[decision.outputList addObject:column];
		}
		for (NSXMLElement *carrier in WKDChildren(table, dmn, @"rule")) {
			[decision.ruleList addObject:[self readRule:carrier of:decision]];
		}
	} else {
		NSXMLElement *literal = WKDChild(element, dmn, @"literalExpression");
		NSXMLElement *variable = WKDChild(element, dmn, @"variable");
		decision.literalElement = literal;
		decision.literalId = WKDAttribute(literal, @"id");
		decision.variableElement = variable;
		decision.variableId = WKDAttribute(variable, @"id");
		[self carry:literal];
		[self carry:variable];
		decision.expression = literal != nil ? WKDDmnText(literal) : @"";
		decision.variableName = WKDAttribute(variable, @"name");
		decision.variableType = WKDAttribute(variable, @"typeRef") ?: WKDAttribute(literal, @"typeRef");
	}
	return decision;
}

- (WKDDmnRule *)readRule:(NSXMLElement *)carrier of:(WKDDmnDecision *)decision
{
	NSString *dmn = self.dmn;
	WKDDmnRule *rule = [[WKDDmnRule alloc] init];
	rule.model = self;
	rule.decision = decision;
	rule.element = carrier;
	[self carry:carrier];
	rule.ruleId = WKDAttribute(carrier, @"id");
	NSArray *inputs = WKDChildren(carrier, dmn, @"inputEntry"), *outputs = WKDChildren(carrier, dmn, @"outputEntry");
	for (NSUInteger i = 0; i < [decision.inputList count] + [decision.outputList count]; i++) {
		BOOL output = i >= [decision.inputList count];
		NSArray *entries = output ? outputs : inputs;
		NSUInteger at = output ? i - [decision.inputList count] : i;
		NSXMLElement *element = at < [entries count] ? [entries objectAtIndex:at] : nil;
		WKDDmnEntry *entry = [[WKDDmnEntry alloc] init];
		entry.model = self;
		entry.rule = rule;
		entry.output = output;
		entry.element = element;
		[self carry:element];
		entry.entryId = WKDAttribute(element, @"id");
		entry.text = element != nil ? WKDDmnText(element) : @"";
		[rule.entryList addObject:entry];
	}
	rule.annotation = [[WKDChild(carrier, dmn, @"description") stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	return rule;
}

@end

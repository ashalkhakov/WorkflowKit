#import "WKDDmnModelPriv.h"
#import "WKDXML.h"

/* Where a new shape goes when the diagram has none, and how big it is. */
static const double WKDShapeWidth = 180;
static const double WKDShapeHeight = 80;
static const double WKDShapeGap = 60;

/* Where each element goes among its siblings, as DMN's schema orders
 * them; a new one is put before the first that comes after it. */
static NSArray *
WKDDecisionOrder(void)
{
	return @[ @"description", @"extensionElements", @"question", @"allowedAnswers", @"variable",
	          @"informationRequirement", @"knowledgeRequirement", @"authorityRequirement", @"supportedObjective",
	          @"impactedPerformanceIndicator", @"decisionMaker", @"decisionOwner", @"usingProcess", @"usingTask",
	          @"decisionTable", @"literalExpression", @"context", @"invocation", @"relation", @"list",
	          @"functionDefinition" ];
}

static NSArray *
WKDTableOrder(void)
{
	return @[ @"description", @"extensionElements", @"input", @"output", @"annotation", @"rule" ];
}

static NSArray *
WKDRuleOrder(void)
{
	return @[ @"description", @"extensionElements", @"inputEntry", @"outputEntry", @"annotationEntry" ];
}

/* Where a child of that name goes, by the order: before the first sibling
 * the order puts after it. */
static NSUInteger
WKDPlaceIndex(NSXMLElement *parent, NSString *local, NSArray *order)
{
	NSUInteger rank = [order indexOfObject:local];
	NSArray *children = [parent children];
	for (NSUInteger i = 0; i < [children count]; i++) {
		NSXMLNode *sibling = [children objectAtIndex:i];
		NSUInteger other = [sibling kind] == NSXMLElementKind ? [order indexOfObject:[sibling localName]] : NSNotFound;
		if (other != NSNotFound && rank != NSNotFound && other > rank) {
			return i;
		}
	}
	return [children count];
}

static void
WKDWrite(WKDJournal *journal, NSXMLElement *element, NSString *name, NSString *value)
{
	NSString *now = WKDAttribute(element, name);
	if (value == now || [value isEqualToString:now]) {
		return;
	}
	WKDLogAttribute(journal, element, name, value);
}

static NSString *
WKDNonEmpty(NSString *text)
{
	return [text length] > 0 ? text : nil;
}

/* The children of that name are the desired ones, in their order, those
 * after them left where they are: each out of place moved, each new one
 * put in. */
static void
WKDArrange(WKDJournal *journal, NSXMLElement *parent, NSArray<NSXMLElement *> *desired, NSString *uri, NSString *local,
           NSArray *order)
{
	NSArray *actual = WKDChildren(parent, uri, local);
	for (NSUInteger i = 0; i < [desired count]; i++) {
		NSXMLElement *wanted = [desired objectAtIndex:i];
		if (i < [actual count] && [actual objectAtIndex:i] == wanted) {
			continue;
		}
		if ([wanted parent] != nil) {
			WKDLogDetach(journal, wanted);
			actual = WKDChildren(parent, uri, local);
		}
		NSUInteger index;
		if (i < [actual count]) {
			index = [[actual objectAtIndex:i] index];
		} else if (i > 0) {
			index = [[desired objectAtIndex:i - 1] index] + 1;
		} else {
			index = WKDPlaceIndex(parent, local, order);
		}
		WKDLogInsert(journal, parent, wanted, index);
		actual = WKDChildren(parent, uri, local);
	}
}

static NSUInteger
WKDDepth(WKDDmnElement *element)
{
	if ([element isKindOfClass:[WKDDmnDecision class]]) {
		return 0;
	}
	return [element isKindOfClass:[WKDDmnEntry class]] ? 2 : 1;
}

static NSInteger
WKDByDepth(id a, id b, void *context)
{
	NSUInteger da = WKDDepth(a), db = WKDDepth(b);
	return da < db ? NSOrderedAscending : da > db ? NSOrderedDescending : NSOrderedSame;
}

/* What holds the element's carrier, which takes it along when it goes. */
static WKDDmnElement *
WKDOwner(WKDDmnElement *element)
{
	if ([element isKindOfClass:[WKDDmnEntry class]]) {
		return ((WKDDmnEntry *)element).rule;
	}
	if ([element isKindOfClass:[WKDDmnRule class]]) {
		return ((WKDDmnRule *)element).decision;
	}
	if ([element isKindOfClass:[WKDDmnColumn class]]) {
		return ((WKDDmnColumn *)element).decision;
	}
	if ([element isKindOfClass:[WKDDmnRequirement class]]) {
		return ((WKDDmnRequirement *)element).decision;
	}
	return nil;
}

@implementation WKDDmnModel (WKDDmnWriting)

- (void)writeChanges
{
	WKDJournal *journal = self.journal;
	NSHashTable *leaving = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	for (WKDDmnElement *element in self.deletedElements) {
		if (![self containsElement:element]) {
			[leaving addObject:element];
		}
	}
	for (WKDDmnElement *element in [leaving allObjects]) {
		BOOL carried = NO;
		for (WKDDmnElement *owner = WKDOwner(element); owner != nil; owner = WKDOwner(owner)) {
			carried = carried || [leaving containsObject:owner];
		}
		if (!carried) {
			WKDLogDetach(journal, element.element);
		}
		if ([element isKindOfClass:[WKDDmnDecision class]]) {
			WKDLogDetach(journal, ((WKDDmnDecision *)element).shapeElement);
		} else if ([element isKindOfClass:[WKDDmnRequirement class]]) {
			WKDLogDetach(journal, ((WKDDmnRequirement *)element).edgeElement);
		}
	}
	NSMutableArray *present = [NSMutableArray array];
	for (WKDDmnElement *element in self.changedElements) {
		if ([self containsElement:element]) {
			[present addObject:element];
		}
	}
	[present sortUsingFunction:WKDByDepth context:NULL];
	NSHashTable *tables = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	NSHashTable *rules = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
	for (WKDDmnElement *element in present) {
		if ([element isKindOfClass:[WKDDmnDecision class]]) {
			[self writeDecision:(WKDDmnDecision *)element];
			[tables addObject:element];
		} else if ([element isKindOfClass:[WKDDmnColumn class]]) {
			[self writeColumn:(WKDDmnColumn *)element];
			[tables addObject:((WKDDmnColumn *)element).decision];
		} else if ([element isKindOfClass:[WKDDmnRule class]]) {
			[self writeRule:(WKDDmnRule *)element];
			[rules addObject:element];
			[tables addObject:((WKDDmnRule *)element).decision];
		} else if ([element isKindOfClass:[WKDDmnEntry class]]) {
			WKDDmnEntry *entry = (WKDDmnEntry *)element;
			if (entry.element == nil) {
				[rules addObject:entry.rule];
			}
			[self writeEntry:entry];
		} else if ([element isKindOfClass:[WKDDmnRequirement class]]) {
			[self writeRequirement:(WKDDmnRequirement *)element];
		}
	}
	/* What is in a table where the model has it, every entry of a rule
	 * written given a carrier: a rule's entries are matched to the columns
	 * by where they are. */
	for (WKDDmnRule *rule in rules) {
		[self arrangeRule:rule];
	}
	for (WKDDmnDecision *decision in tables) {
		if (decision.tableElement == nil) {
			continue;
		}
		NSString *dmn = self.dmn;
		WKDArrange(journal, decision.tableElement, [decision.inputList valueForKey:@"element"], dmn, @"input", WKDTableOrder());
		WKDArrange(journal, decision.tableElement, [decision.outputList valueForKey:@"element"], dmn, @"output",
		           WKDTableOrder());
		WKDArrange(journal, decision.tableElement, [decision.ruleList valueForKey:@"element"], dmn, @"rule", WKDTableOrder());
	}
	[self.changedElements removeAllObjects];
	[self.deletedElements removeAllObjects];
}

- (NSXMLElement *)newElement:(NSString *)local withId:(NSString *)elementId
{
	NSXMLElement *element = WKDNewElement(self.document, self.dmn, local);
	if (elementId != nil) {
		WKDSetAttribute(element, @"id", elementId);
	}
	[self carry:element];
	return element;
}

/* The element's <text>, made when it has none. */
- (void)writeText:(NSString *)text of:(NSXMLElement *)element
{
	if ([WKDDmnText(element) isEqualToString:text ?: @""] && WKDChild(element, [element URI], @"text") != nil) {
		return;
	}
	NSXMLElement *child = WKDChild(element, [element URI], @"text");
	if (child == nil) {
		child = [self newElement:@"text" withId:nil];
		[child setStringValue:text ?: @""];
		WKDLogAdd(self.journal, element, child);
		return;
	}
	WKDLogText(self.journal, child, text ?: @"");
}

- (void)place:(NSXMLElement *)child in:(NSXMLElement *)parent order:(NSArray *)order
{
	WKDLogInsert(self.journal, parent, child, WKDPlaceIndex(parent, [child localName], order));
}

#pragma mark Decisions

- (void)writeDecision:(WKDDmnDecision *)decision
{
	WKDJournal *journal = self.journal;
	BOOL made = decision.element == nil;
	if (made) {
		NSXMLElement *root = [self.document rootElement];
		NSXMLElement *element = [self newElement:@"decision" withId:decision.decisionId];
		decision.element = element;
		/* After the last decision: before the diagram, and what else the
		 * file has after its decisions. */
		NSXMLElement *last = [WKDChildren(root, self.dmn, @"decision") lastObject];
		NSXMLElement *dmndi = WKDChild(root, [self.diagram URI] ?: @"", @"DMNDI");
		NSUInteger index = last != nil ? [last index] + 1 : dmndi != nil ? [dmndi index] : [root childCount];
		WKDLogInsert(journal, root, element, index);
	}
	NSXMLElement *element = decision.element;
	WKDWrite(journal, element, @"id", decision.decisionId);
	WKDWrite(journal, element, @"name", WKDNonEmpty(decision.name));
	if (decision.table) {
		if (decision.tableElement == nil) {
			decision.tableElement = [self newElement:@"decisionTable" withId:decision.tableId];
			[self place:decision.tableElement in:element order:WKDDecisionOrder()];
		}
		NSXMLElement *table = decision.tableElement;
		NSString *policy = WKDAttribute(table, @"hitPolicy") ?: @"UNIQUE";
		if (![policy isEqualToString:decision.hitPolicy ?: @"UNIQUE"]) {
			WKDLogAttribute(journal, table, @"hitPolicy",
			                [decision.hitPolicy length] == 0 || [decision.hitPolicy isEqualToString:@"UNIQUE"]
			                    ? nil : decision.hitPolicy);
		}
		WKDWrite(journal, table, @"aggregation", WKDNonEmpty(decision.aggregation));
	} else {
		if (decision.variableElement == nil && (made || decision.variableName != nil || decision.variableType != nil)) {
			decision.variableElement = [self newElement:@"variable" withId:decision.variableId];
			[self place:decision.variableElement in:element order:WKDDecisionOrder()];
		}
		if (decision.literalElement == nil && (made || [decision.expression length] > 0)) {
			decision.literalElement = [self newElement:@"literalExpression" withId:decision.literalId];
			[self place:decision.literalElement in:element order:WKDDecisionOrder()];
		}
		NSXMLElement *variable = decision.variableElement, *literal = decision.literalElement;
		if (variable != nil) {
			WKDWrite(journal, variable, @"name", WKDNonEmpty(decision.variableName));
			NSString *type = WKDAttribute(variable, @"typeRef") ?: WKDAttribute(literal, @"typeRef");
			if (!(type == decision.variableType || [type isEqualToString:decision.variableType])) {
				WKDWrite(journal, variable, @"typeRef", WKDNonEmpty(decision.variableType));
			}
		}
		if (literal != nil) {
			[self writeText:decision.expression of:literal];
		}
	}
	if (made && self.diagram != nil && decision.shapeElement == nil) {
		[self addShapeFor:decision];
	}
}

/* The namespace the diagram's elements of that name are in, else the one
 * DMN 1.3's diagrams use. */
- (NSString *)diagramNamespaceOf:(NSString *)local fallback:(NSString *)fallback
{
	for (NSXMLElement *element in WKDChildren(self.diagram, [self.diagram URI], nil)) {
		for (NSXMLNode *child in [element children]) {
			if ([[child localName] isEqualToString:local]) {
				return [child URI] ?: fallback;
			}
		}
	}
	return fallback;
}

- (NSRect)boundsOf:(NSXMLElement *)shape
{
	NSXMLElement *bounds = nil;
	for (NSXMLNode *child in [shape children]) {
		if ([[child localName] isEqualToString:@"Bounds"]) {
			bounds = (NSXMLElement *)child;
		}
	}
	return NSMakeRect(WKDNumber(bounds, @"x"), WKDNumber(bounds, @"y"), WKDNumber(bounds, @"width"),
	                  WKDNumber(bounds, @"height"));
}

/* A shape for the decision, right of the others. */
- (void)addShapeFor:(WKDDmnDecision *)decision
{
	NSXMLElement *diagram = self.diagram;
	double right = 0, top = 100;
	BOOL any = NO;
	for (NSXMLElement *shape in WKDChildren(diagram, [diagram URI], @"DMNShape")) {
		NSRect bounds = [self boundsOf:shape];
		right = MAX(right, NSMaxX(bounds));
		top = any ? MIN(top, NSMinY(bounds)) : NSMinY(bounds);
		any = YES;
	}
	NSXMLElement *shape = WKDNewElement(self.document, [diagram URI], @"DMNShape");
	WKDSetAttribute(shape, @"id", [self freshId:@"DMNShape"]);
	WKDSetAttribute(shape, @"dmnElementRef", decision.decisionId);
	NSXMLElement *bounds = WKDNewElement(self.document, [self diagramNamespaceOf:@"Bounds" fallback:WKDDmnDCNamespace],
	                                     @"Bounds");
	[shape addChild:bounds];
	WKDSetAttribute(bounds, @"height", WKDFormat(WKDShapeHeight));
	WKDSetAttribute(bounds, @"width", WKDFormat(WKDShapeWidth));
	WKDSetAttribute(bounds, @"x", WKDFormat(any ? right + WKDShapeGap : 160));
	WKDSetAttribute(bounds, @"y", WKDFormat(top));
	[self carry:shape];
	decision.shapeElement = shape;
	WKDLogAdd(self.journal, diagram, shape);
}

#pragma mark Requirements

- (void)writeRequirement:(WKDDmnRequirement *)requirement
{
	NSString *dmn = self.dmn;
	BOOL made = requirement.element == nil;
	if (made) {
		NSXMLElement *element = [self newElement:@"informationRequirement" withId:requirement.requirementId];
		[element addChild:[self newElement:@"requiredDecision" withId:nil]];
		requirement.element = element;
		[self place:element in:requirement.decision.element order:WKDDecisionOrder()];
	}
	WKDWrite(self.journal, WKDChild(requirement.element, dmn, @"requiredDecision"), @"href",
	         [@"#" stringByAppendingString:requirement.requiredId]);
	if (made && self.diagram != nil && requirement.edgeElement == nil) {
		[self addEdgeFor:requirement];
	}
}

/* An edge from the shape of what is required to the shape of what
 * requires it, when both have one. */
- (void)addEdgeFor:(WKDDmnRequirement *)requirement
{
	NSXMLElement *source = requirement.requiredDecision.shapeElement, *target = requirement.decision.shapeElement;
	if (source == nil || target == nil) {
		return;
	}
	NSRect from = [self boundsOf:source], to = [self boundsOf:target];
	BOOL upward = NSMidY(to) <= NSMidY(from);
	NSPoint points[2] = { NSMakePoint(NSMidX(from), upward ? NSMinY(from) : NSMaxY(from)),
	                      NSMakePoint(NSMidX(to), upward ? NSMaxY(to) : NSMinY(to)) };
	NSXMLElement *diagram = self.diagram;
	NSXMLElement *edge = WKDNewElement(self.document, [diagram URI], @"DMNEdge");
	WKDSetAttribute(edge, @"id", [self freshId:@"DMNEdge"]);
	WKDSetAttribute(edge, @"dmnElementRef", requirement.requirementId);
	NSString *di = [self diagramNamespaceOf:@"waypoint" fallback:WKDDmnDINamespace];
	for (NSUInteger i = 0; i < 2; i++) {
		NSXMLElement *waypoint = WKDNewElement(self.document, di, @"waypoint");
		WKDSetAttribute(waypoint, @"x", WKDFormat(points[i].x));
		WKDSetAttribute(waypoint, @"y", WKDFormat(points[i].y));
		[edge addChild:waypoint];
	}
	[self carry:edge];
	requirement.edgeElement = edge;
	WKDLogAdd(self.journal, diagram, edge);
}

#pragma mark Tables

- (void)writeColumn:(WKDDmnColumn *)column
{
	WKDJournal *journal = self.journal;
	if (column.element == nil) {
		column.element = [self newElement:column.output ? @"output" : @"input" withId:column.columnId];
	}
	NSXMLElement *clause = column.element;
	WKDWrite(journal, clause, @"label", WKDNonEmpty(column.label));
	if (column.output) {
		WKDWrite(journal, clause, @"name", WKDNonEmpty(column.name));
		WKDWrite(journal, clause, @"typeRef", WKDNonEmpty(column.typeRef));
		return;
	}
	if (column.expressionElement == nil) {
		column.expressionElement = [self newElement:@"inputExpression" withId:column.expressionId];
		WKDLogInsert(journal, clause, column.expressionElement, 0);
	}
	WKDWrite(journal, column.expressionElement, @"typeRef", WKDNonEmpty(column.typeRef));
	[self writeText:column.expression of:column.expressionElement];
	WKDLogQualifiedAttribute(journal, self.document, clause, WKDCamundaDmnNamespace, @"inputVariable",
	                         WKDNonEmpty(column.inputVariable));
}

- (void)writeRule:(WKDDmnRule *)rule
{
	if (rule.element == nil) {
		rule.element = [self newElement:@"rule" withId:rule.ruleId];
	}
	NSXMLElement *element = rule.element;
	NSXMLElement *description = WKDChild(element, self.dmn, @"description");
	NSString *now = [[description stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([rule.annotation length] == 0) {
		WKDLogDetach(self.journal, description);
	} else if (description == nil) {
		description = [self newElement:@"description" withId:nil];
		[description setStringValue:rule.annotation];
		[self place:description in:element order:WKDRuleOrder()];
	} else if (![now isEqualToString:rule.annotation]) {
		WKDLogText(self.journal, description, rule.annotation);
	}
}

- (void)writeEntry:(WKDDmnEntry *)entry
{
	if (entry.element == nil) {
		[self.journal willChange:entry];
		if (entry.entryId == nil) {
			entry.entryId = [self freshId:entry.output ? @"LiteralExpression" : @"UnaryTests"];
		}
		entry.element = [self newElement:entry.output ? @"outputEntry" : @"inputEntry" withId:entry.entryId];
	}
	[self writeText:entry.text of:entry.element];
}

/* Its entries in the model's order, each with a carrier. */
- (void)arrangeRule:(WKDDmnRule *)rule
{
	NSMutableArray *inputs = [NSMutableArray array], *outputs = [NSMutableArray array];
	for (WKDDmnEntry *entry in rule.entryList) {
		if (entry.element == nil) {
			[self writeEntry:entry];
		}
		[entry.output ? outputs : inputs addObject:entry.element];
	}
	WKDArrange(self.journal, rule.element, inputs, self.dmn, @"inputEntry", WKDRuleOrder());
	WKDArrange(self.journal, rule.element, outputs, self.dmn, @"outputEntry", WKDRuleOrder());
}

@end

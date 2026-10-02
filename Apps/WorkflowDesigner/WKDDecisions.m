#import "WKDDecisions.h"
#import "WKDXML.h"

static NSString * const WKDDmn13Namespace = @"https://www.omg.org/spec/DMN/20191111/MODEL/";
static NSString * const WKDDmnDI13Namespace = @"https://www.omg.org/spec/DMN/20191111/DMNDI/";
static NSString * const WKDDmnDCNamespace = @"http://www.omg.org/spec/DMN/20180521/DC/";
static NSString * const WKDDmnDINamespace = @"http://www.omg.org/spec/DMN/20180521/DI/";

/* Where a new shape goes when the diagram has none, and how big it is. */
static const double WKDShapeWidth = 180;
static const double WKDShapeHeight = 80;
static const double WKDShapeGap = 60;

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

#pragma mark The model

@interface WKDDmnColumn ()
@property (nonatomic, readwrite, copy) NSString *columnId;
@property (nonatomic, readwrite, getter=isOutput) BOOL output;
@property (nonatomic, readwrite, copy) NSString *label;
@property (nonatomic, readwrite, copy) NSString *typeRef;
@property (nonatomic, readwrite, copy) NSString *expression;
@property (nonatomic, readwrite, copy) NSString *inputVariable;
@property (nonatomic, readwrite, copy) NSString *name;
@end

@implementation WKDDmnColumn

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

@interface WKDDmnRule ()
@property (nonatomic, readwrite, copy) NSString *ruleId;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *entries;
@property (nonatomic, readwrite, copy) NSString *annotation;
@end

@implementation WKDDmnRule
@end

@interface WKDDmnDecision ()
@property (nonatomic, readwrite, copy) NSString *decisionId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, getter=isTable) BOOL table;
@property (nonatomic, readwrite, copy) NSString *hitPolicy;
@property (nonatomic, readwrite, copy) NSString *aggregation;
@property (nonatomic, readwrite, copy) NSArray<WKDDmnColumn *> *inputs;
@property (nonatomic, readwrite, copy) NSArray<WKDDmnColumn *> *outputs;
@property (nonatomic, readwrite, copy) NSArray<WKDDmnRule *> *rules;
@property (nonatomic, readwrite, copy) NSString *expression;
@property (nonatomic, readwrite, copy) NSString *variableName;
@property (nonatomic, readwrite, copy) NSString *variableType;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *required;
@end

@implementation WKDDmnDecision

- (NSArray<WKDDmnColumn *> *)columns
{
	return [self.inputs arrayByAddingObjectsFromArray:self.outputs];
}

- (NSString *)title
{
	return [self.name length] > 0 ? self.name : self.decisionId;
}

@end

#pragma mark XML

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

/* The child put where the order says, after those of its own kind. */
static void
WKDPlace(NSXMLElement *parent, NSXMLElement *child, NSArray *order)
{
	NSUInteger rank = [order indexOfObject:[child localName]];
	NSArray *children = [parent children];
	for (NSUInteger i = 0; i < [children count]; i++) {
		NSXMLNode *sibling = [children objectAtIndex:i];
		NSUInteger other = [sibling kind] == NSXMLElementKind ? [order indexOfObject:[sibling localName]] : NSNotFound;
		if (other != NSNotFound && rank != NSNotFound && other > rank) {
			[parent insertChild:child atIndex:i];
			return;
		}
	}
	[parent addChild:child];
}

/* The child moved to before another of its kind, or after them all. */
static void
WKDPlaceBefore(NSXMLElement *parent, NSXMLElement *child, NSXMLElement *before, NSArray *order)
{
	if (before != nil) {
		[parent insertChild:child atIndex:[before index]];
	} else {
		NSArray *same = WKDChildren(parent, [child URI], [child localName]);
		NSXMLElement *last = [same lastObject];
		if (last != nil) {
			[parent insertChild:child atIndex:[last index] + 1];
		} else {
			WKDPlace(parent, child, order);
		}
	}
}

static NSString *
WKDText(NSXMLElement *element)
{
	NSXMLElement *text = WKDChild(element, [element URI], @"text");
	return [[text stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSString *
WKDNonEmpty(NSString *text)
{
	return [text length] > 0 ? text : nil;
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

@implementation WKDDmnEditor
{
	NSUndoManager *_undoManager;
	/* The ids taken, while a change is made: each new one is added. */
	NSMutableSet *_used;
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
		[self read];
	}
	return self;
}

/* The namespace the file's decisions are in: DMN 1.1's, 1.2's or 1.3's. */
- (NSString *)dmn
{
	return [[_document rootElement] URI] ?: WKDDmn13Namespace;
}

#pragma mark Reading

- (void)read
{
	NSMutableArray *decisions = [NSMutableArray array];
	for (NSXMLElement *element in WKDChildren([_document rootElement], [self dmn], @"decision")) {
		[decisions addObject:[self decisionOf:element]];
	}
	_decisions = decisions;
}

- (WKDDmnDecision *)decisionOf:(NSXMLElement *)element
{
	NSString *dmn = [self dmn];
	WKDDmnDecision *decision = [[WKDDmnDecision alloc] init];
	decision.decisionId = WKDAttribute(element, @"id") ?: @"";
	decision.name = WKDAttribute(element, @"name");
	NSMutableArray *required = [NSMutableArray array];
	for (NSXMLElement *requirement in WKDChildren(element, dmn, @"informationRequirement")) {
		NSString *href = WKDAttribute(WKDChild(requirement, dmn, @"requiredDecision"), @"href");
		if (href != nil) {
			[required addObject:[href hasPrefix:@"#"] ? [href substringFromIndex:1] : href];
		}
	}
	decision.required = required;
	NSXMLElement *table = WKDChild(element, dmn, @"decisionTable");
	NSXMLElement *literal = WKDChild(element, dmn, @"literalExpression");
	if (table != nil) {
		decision.table = YES;
		decision.hitPolicy = WKDAttribute(table, @"hitPolicy") ?: @"UNIQUE";
		decision.aggregation = WKDAttribute(table, @"aggregation");
		NSMutableArray *inputs = [NSMutableArray array];
		for (NSXMLElement *input in WKDChildren(table, dmn, @"input")) {
			WKDDmnColumn *column = [[WKDDmnColumn alloc] init];
			NSXMLElement *expression = WKDChild(input, dmn, @"inputExpression");
			column.columnId = WKDAttribute(input, @"id");
			column.label = WKDAttribute(input, @"label");
			column.typeRef = WKDAttribute(expression, @"typeRef");
			column.expression = expression != nil ? WKDText(expression) : @"";
			column.inputVariable = WKDQualifiedAttribute(_document, input, WKDCamundaDmnNamespace, @"inputVariable");
			[inputs addObject:column];
		}
		NSMutableArray *outputs = [NSMutableArray array];
		for (NSXMLElement *output in WKDChildren(table, dmn, @"output")) {
			WKDDmnColumn *column = [[WKDDmnColumn alloc] init];
			column.output = YES;
			column.columnId = WKDAttribute(output, @"id");
			column.label = WKDAttribute(output, @"label");
			column.typeRef = WKDAttribute(output, @"typeRef");
			column.name = WKDAttribute(output, @"name");
			[outputs addObject:column];
		}
		NSMutableArray *rules = [NSMutableArray array];
		for (NSXMLElement *element in WKDChildren(table, dmn, @"rule")) {
			WKDDmnRule *rule = [[WKDDmnRule alloc] init];
			rule.ruleId = WKDAttribute(element, @"id");
			NSMutableArray *entries = [NSMutableArray array];
			NSArray *inputEntries = WKDChildren(element, dmn, @"inputEntry");
			NSArray *outputEntries = WKDChildren(element, dmn, @"outputEntry");
			for (NSUInteger i = 0; i < [inputs count]; i++) {
				[entries addObject:i < [inputEntries count] ? WKDText([inputEntries objectAtIndex:i]) : @""];
			}
			for (NSUInteger i = 0; i < [outputs count]; i++) {
				[entries addObject:i < [outputEntries count] ? WKDText([outputEntries objectAtIndex:i]) : @""];
			}
			rule.entries = entries;
			rule.annotation = [[WKDChild(element, dmn, @"description") stringValue]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
			[rules addObject:rule];
		}
		decision.inputs = inputs;
		decision.outputs = outputs;
		decision.rules = rules;
	} else {
		NSXMLElement *variable = WKDChild(element, dmn, @"variable");
		decision.expression = literal != nil ? WKDText(literal) : @"";
		decision.variableName = WKDAttribute(variable, @"name");
		decision.variableType = WKDAttribute(variable, @"typeRef") ?: WKDAttribute(literal, @"typeRef");
		decision.inputs = @[];
		decision.outputs = @[];
		decision.rules = @[];
	}
	return decision;
}

- (WKDDmnDecision *)decisionWithId:(NSString *)decisionId
{
	for (WKDDmnDecision *decision in _decisions) {
		if ([decision.decisionId isEqualToString:decisionId]) {
			return decision;
		}
	}
	return nil;
}

- (NSXMLElement *)elementOf:(NSString *)decisionId
{
	for (NSXMLElement *element in WKDChildren([_document rootElement], [self dmn], @"decision")) {
		if ([WKDAttribute(element, @"id") isEqualToString:decisionId]) {
			return element;
		}
	}
	return nil;
}

- (NSXMLElement *)tableOf:(NSString *)decisionId
{
	return WKDChild([self elementOf:decisionId], [self dmn], @"decisionTable");
}

#pragma mark Changes

/* One undoable step: the document as it was is what undo restores. NO,
 * and no step, when there is no such decision. */
- (BOOL)change:(NSString *)name of:(NSString *)decisionId with:(void (^)(NSXMLElement *decision))change
{
	NSXMLElement *element = decisionId != nil ? [self elementOf:decisionId] : nil;
	if (decisionId != nil && element == nil) {
		return NO;
	}
	NSXMLDocument *before = WKDCopyDocument(_document);
	change(element);
	_used = nil;
	[_undoManager registerUndoWithTarget:self selector:@selector(restore:) object:before];
	[_undoManager setActionName:name];
	[self reread];
	return YES;
}

- (void)restore:(NSXMLDocument *)snapshot
{
	[_undoManager registerUndoWithTarget:self selector:@selector(restore:) object:WKDCopyDocument(_document)];
	_document = snapshot;
	[self reread];
}

- (void)reread
{
	[self read];
	if (self.changed != nil) {
		self.changed();
	}
}

/* A new id, Prefix_n, with the least n not taken. */
- (NSString *)freshId:(NSString *)prefix
{
	if (_used == nil) {
		_used = [NSMutableSet set];
		NSMutableArray *pending = [NSMutableArray arrayWithObject:[_document rootElement]];
		while ([pending count] > 0) {
			NSXMLElement *element = [pending lastObject];
			[pending removeLastObject];
			NSString *elementId = WKDAttribute(element, @"id");
			if (elementId != nil) {
				[_used addObject:elementId];
			}
			for (NSXMLNode *child in [element children]) {
				if ([child kind] == NSXMLElementKind) {
					[pending addObject:child];
				}
			}
		}
	}
	for (NSUInteger n = 1;; n++) {
		NSString *candidate = [NSString stringWithFormat:@"%@_%lu", prefix, (unsigned long)n];
		if (![_used containsObject:candidate]) {
			[_used addObject:candidate];
			return candidate;
		}
	}
}

- (NSXMLElement *)newElement:(NSString *)local prefix:(NSString *)prefix
{
	NSXMLElement *element = WKDNewElement(_document, [self dmn], local);
	if (prefix != nil) {
		WKDSetAttribute(element, @"id", [self freshId:prefix]);
	}
	return element;
}

/* The element's <text>, made when it has none. */
- (void)setText:(NSString *)text of:(NSXMLElement *)element
{
	NSXMLElement *child = WKDChild(element, [self dmn], @"text");
	if (child == nil) {
		child = [self newElement:@"text" prefix:nil];
		[element addChild:child];
	}
	[child setStringValue:text ?: @""];
}

/* An expression element -- inputExpression, an entry -- with its text. */
- (NSXMLElement *)newExpression:(NSString *)local prefix:(NSString *)prefix text:(NSString *)text
{
	NSXMLElement *element = [self newElement:local prefix:prefix];
	[self setText:text of:element];
	return element;
}

#pragma mark Diagram

- (NSXMLElement *)diagram
{
	return WKDFindLocal([_document rootElement], @"DMNDiagram");
}

- (NSArray<NSXMLElement *> *)diagramElements:(NSString *)local referring:(NSString *)elementId
{
	NSXMLElement *diagram = [self diagram];
	NSMutableArray *found = [NSMutableArray array];
	for (NSXMLElement *element in WKDChildren(diagram, [diagram URI], local)) {
		if (elementId == nil || [WKDAttribute(element, @"dmnElementRef") isEqualToString:elementId]) {
			[found addObject:element];
		}
	}
	return found;
}

- (NSRect)boundsOf:(NSXMLElement *)shape
{
	NSXMLElement *bounds = WKDFindLocal(shape, @"Bounds");
	return NSMakeRect(WKDNumber(bounds, @"x"), WKDNumber(bounds, @"y"), WKDNumber(bounds, @"width"),
	                  WKDNumber(bounds, @"height"));
}

/* The namespace the diagram's elements of that name are in, else the one
 * DMN 1.3's diagrams use. */
- (NSString *)namespaceOf:(NSString *)local fallback:(NSString *)fallback
{
	NSXMLElement *found = WKDFindLocal([self diagram], local);
	return [found URI] ?: fallback;
}

/* A shape for the decision, right of the others, when there is a diagram. */
- (void)addShapeFor:(NSString *)decisionId
{
	NSXMLElement *diagram = [self diagram];
	if (diagram == nil) {
		return;
	}
	double right = 0, top = 100;
	BOOL any = NO;
	for (NSXMLElement *shape in [self diagramElements:@"DMNShape" referring:nil]) {
		NSRect bounds = [self boundsOf:shape];
		right = MAX(right, NSMaxX(bounds));
		top = any ? MIN(top, NSMinY(bounds)) : NSMinY(bounds);
		any = YES;
	}
	NSXMLElement *shape = WKDNewElement(_document, [diagram URI], @"DMNShape");
	WKDSetAttribute(shape, @"id", [self freshId:@"DMNShape"]);
	WKDSetAttribute(shape, @"dmnElementRef", decisionId);
	[diagram addChild:shape];
	NSXMLElement *bounds = WKDNewElement(_document, [self namespaceOf:@"Bounds" fallback:WKDDmnDCNamespace], @"Bounds");
	[shape addChild:bounds];
	WKDSetAttribute(bounds, @"height", WKDFormat(WKDShapeHeight));
	WKDSetAttribute(bounds, @"width", WKDFormat(WKDShapeWidth));
	WKDSetAttribute(bounds, @"x", WKDFormat(any ? right + WKDShapeGap : 160));
	WKDSetAttribute(bounds, @"y", WKDFormat(top));
}

/* An edge for the requirement, from the shape of what is required to the
 * shape of what requires it, when both have one. */
- (void)addEdgeFor:(NSString *)requirementId from:(NSString *)requiredId to:(NSString *)decisionId
{
	NSXMLElement *diagram = [self diagram];
	NSXMLElement *source = [[self diagramElements:@"DMNShape" referring:requiredId] firstObject];
	NSXMLElement *target = [[self diagramElements:@"DMNShape" referring:decisionId] firstObject];
	if (source == nil || target == nil) {
		return;
	}
	NSRect from = [self boundsOf:source], to = [self boundsOf:target];
	BOOL upward = NSMidY(to) <= NSMidY(from);
	NSPoint points[2] = { NSMakePoint(NSMidX(from), upward ? NSMinY(from) : NSMaxY(from)),
	                      NSMakePoint(NSMidX(to), upward ? NSMaxY(to) : NSMinY(to)) };
	NSXMLElement *edge = WKDNewElement(_document, [diagram URI], @"DMNEdge");
	WKDSetAttribute(edge, @"id", [self freshId:@"DMNEdge"]);
	WKDSetAttribute(edge, @"dmnElementRef", requirementId);
	[diagram addChild:edge];
	NSString *di = [self namespaceOf:@"waypoint" fallback:WKDDmnDINamespace];
	for (NSUInteger i = 0; i < 2; i++) {
		NSXMLElement *waypoint = WKDNewElement(_document, di, @"waypoint");
		[edge addChild:waypoint];
		WKDSetAttribute(waypoint, @"x", WKDFormat(points[i].x));
		WKDSetAttribute(waypoint, @"y", WKDFormat(points[i].y));
	}
}

- (void)removeDiagramOf:(NSString *)elementId
{
	for (NSString *local in @[ @"DMNShape", @"DMNEdge" ]) {
		for (NSXMLElement *element in [self diagramElements:local referring:elementId]) {
			[element detach];
		}
	}
}

#pragma mark Decisions

- (NSString *)addDecisionTable:(BOOL)table withId:(NSString *)decisionId
{
	__block NSString *made = nil;
	[self change:@"Add Decision" of:nil with:^(NSXMLElement *unused) {
		NSXMLElement *root = [self->_document rootElement];
		BOOL free = decisionId != nil && WKDIsName(decisionId) && WKDElementWithId(self->_document, decisionId) == nil;
		NSXMLElement *decision = [self newElement:@"decision" prefix:free ? nil : @"Decision"];
		if (free) {
			WKDSetAttribute(decision, @"id", decisionId);
		}
		made = WKDAttribute(decision, @"id");
		WKDSetAttribute(decision, @"name", [made stringByReplacingOccurrencesOfString:@"_" withString:@" "]);
		/* After the last decision: before the diagram, and what else the
		 * file has after its decisions. */
		NSXMLElement *last = [WKDChildren(root, [self dmn], @"decision") lastObject];
		NSXMLElement *dmndi = WKDChild(root, [[self diagram] URI] ?: @"", @"DMNDI");
		if (last != nil) {
			[root insertChild:decision atIndex:[last index] + 1];
		} else if (dmndi != nil) {
			[root insertChild:decision atIndex:[dmndi index]];
		} else {
			[root addChild:decision];
		}
		if (table) {
			NSXMLElement *element = [self newElement:@"decisionTable" prefix:@"DecisionTable"];
			[decision addChild:element];
			[element addChild:[self newInput]];
			[element addChild:[self newOutputNamed:@"result"]];
		} else {
			NSXMLElement *variable = [self newElement:@"variable" prefix:@"InformationItem"];
			WKDSetAttribute(variable, @"name", @"result");
			WKDSetAttribute(variable, @"typeRef", @"string");
			[decision addChild:variable];
			[decision addChild:[self newExpression:@"literalExpression" prefix:@"LiteralExpression" text:@""]];
		}
		[self addShapeFor:made];
	}];
	return made;
}

- (NSXMLElement *)newInput
{
	NSXMLElement *input = [self newElement:@"input" prefix:@"InputClause"];
	NSXMLElement *expression = [self newExpression:@"inputExpression" prefix:@"LiteralExpression" text:@""];
	WKDSetAttribute(expression, @"typeRef", @"string");
	[input addChild:expression];
	return input;
}

- (NSXMLElement *)newOutputNamed:(NSString *)name
{
	NSXMLElement *output = [self newElement:@"output" prefix:@"OutputClause"];
	WKDSetAttribute(output, @"name", name);
	WKDSetAttribute(output, @"typeRef", @"string");
	return output;
}

- (void)deleteDecision:(NSString *)decisionId
{
	NSString *dmn = [self dmn];
	[self change:@"Delete Decision" of:decisionId with:^(NSXMLElement *decision) {
		for (NSXMLElement *requirement in WKDChildren(decision, dmn, @"informationRequirement")) {
			[self removeDiagramOf:WKDAttribute(requirement, @"id")];
		}
		/* Others' requirements on it. */
		NSString *href = [@"#" stringByAppendingString:decisionId];
		for (NSXMLElement *other in WKDChildren([self->_document rootElement], dmn, @"decision")) {
			for (NSXMLElement *requirement in WKDChildren(other, dmn, @"informationRequirement")) {
				if ([WKDAttribute(WKDChild(requirement, dmn, @"requiredDecision"), @"href") isEqualToString:href]) {
					[self removeDiagramOf:WKDAttribute(requirement, @"id")];
					[requirement detach];
				}
			}
		}
		[self removeDiagramOf:decisionId];
		[decision detach];
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
	} else if (WKDElementWithId(_document, newId) != nil) {
		refusal = [NSString stringWithFormat:@"%@ is the id of another element.", newId];
	} else if ([self elementOf:decisionId] == nil) {
		refusal = @"There is no such decision.";
	}
	if (refusal != nil) {
		if (reason != NULL) {
			*reason = refusal;
		}
		return NO;
	}
	return [self change:@"Rename" of:decisionId with:^(NSXMLElement *decision) {
		WKDSetAttribute(decision, @"id", newId);
		NSString *href = [@"#" stringByAppendingString:decisionId];
		NSMutableArray *pending = [NSMutableArray arrayWithObject:[self->_document rootElement]];
		while ([pending count] > 0) {
			NSXMLElement *element = [pending lastObject];
			[pending removeLastObject];
			if ([WKDAttribute(element, @"href") isEqualToString:href]) {
				WKDSetAttribute(element, @"href", [@"#" stringByAppendingString:newId]);
			}
			if ([WKDAttribute(element, @"dmnElementRef") isEqualToString:decisionId]) {
				WKDSetAttribute(element, @"dmnElementRef", newId);
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
	[self change:@"Name" of:decisionId with:^(NSXMLElement *decision) {
		WKDSetAttribute(decision, @"name", WKDNonEmpty(name));
	}];
}

- (void)setHitPolicy:(NSString *)hitPolicy aggregation:(NSString *)aggregation of:(NSString *)decisionId
{
	NSXMLElement *table = [self tableOf:decisionId];
	if (table == nil) {
		return;
	}
	[self change:@"Hit Policy" of:decisionId with:^(NSXMLElement *decision) {
		BOOL collect = [hitPolicy isEqualToString:@"COLLECT"];
		WKDSetAttribute(table, @"hitPolicy", [hitPolicy length] == 0 || [hitPolicy isEqualToString:@"UNIQUE"]
		                                         ? nil : hitPolicy);
		WKDSetAttribute(table, @"aggregation", collect ? WKDNonEmpty(aggregation) : nil);
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
	for (WKDDmnDecision *decision in _decisions) {
		[requirements setObject:decision.required forKey:decision.decisionId];
	}
	[requirements setObject:required forKey:decisionId];
	NSString *refusal = nil;
	for (NSString *other in required) {
		if ([self decisionWithId:other] == nil) {
			refusal = [NSString stringWithFormat:@"The file defines no decision %@.", other];
		} else if ([other isEqualToString:decisionId]
		           || WKDRequires(other, decisionId, requirements, [NSMutableSet set])) {
			refusal = [NSString stringWithFormat:@"%@ requires %@ already.", other, decisionId];
		}
		if (refusal != nil) {
			break;
		}
	}
	if (refusal != nil || [self elementOf:decisionId] == nil) {
		if (reason != NULL) {
			*reason = refusal ?: @"There is no such decision.";
		}
		return NO;
	}
	NSString *dmn = [self dmn];
	return [self change:@"Requirements" of:decisionId with:^(NSXMLElement *decision) {
		NSMutableArray *kept = [NSMutableArray array];
		for (NSXMLElement *requirement in WKDChildren(decision, dmn, @"informationRequirement")) {
			NSString *href = WKDAttribute(WKDChild(requirement, dmn, @"requiredDecision"), @"href");
			NSString *other = [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href;
			/* What is not a decision's requirement -- on input data -- stays. */
			if (other == nil || [required containsObject:other]) {
				[kept addObject:other ?: [NSNull null]];
			} else {
				[self removeDiagramOf:WKDAttribute(requirement, @"id")];
				[requirement detach];
			}
		}
		for (NSString *other in required) {
			if ([kept containsObject:other]) {
				continue;
			}
			NSXMLElement *requirement = [self newElement:@"informationRequirement" prefix:@"InformationRequirement"];
			NSXMLElement *reference = [self newElement:@"requiredDecision" prefix:nil];
			WKDSetAttribute(reference, @"href", [@"#" stringByAppendingString:other]);
			[requirement addChild:reference];
			WKDPlace(decision, requirement, WKDDecisionOrder());
			[self addEdgeFor:WKDAttribute(requirement, @"id") from:other to:decisionId];
		}
	}];
}

#pragma mark Tables

/* The rule's entries of one kind, as many as there are columns of it:
 * those missing made, empty. */
- (NSArray<NSXMLElement *> *)entriesOf:(NSXMLElement *)rule output:(BOOL)output count:(NSUInteger)count
{
	NSString *local = output ? @"outputEntry" : @"inputEntry";
	NSMutableArray *entries = [WKDChildren(rule, [self dmn], local) mutableCopy];
	while ([entries count] < count) {
		NSXMLElement *entry = [self newExpression:local prefix:output ? @"LiteralExpression" : @"UnaryTests" text:@""];
		WKDPlaceBefore(rule, entry, nil, WKDRuleOrder());
		[entries addObject:entry];
	}
	return entries;
}

/* Which kind the column is, and its index among them. */
- (BOOL)column:(NSUInteger)column of:(WKDDmnDecision *)decision output:(BOOL *)output index:(NSUInteger *)index
{
	NSUInteger inputs = [decision.inputs count];
	if (decision == nil || column >= inputs + [decision.outputs count]) {
		return NO;
	}
	*output = column >= inputs;
	*index = *output ? column - inputs : column;
	return YES;
}

- (NSUInteger)insertColumn:(BOOL)output at:(NSUInteger)index of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [self decisionWithId:decisionId];
	NSXMLElement *table = [self tableOf:decisionId];
	if (table == nil) {
		return NSNotFound;
	}
	NSString *dmn = [self dmn];
	NSArray *columns = output ? decision.outputs : decision.inputs;
	index = MIN(index, [columns count]);
	[self change:output ? @"Add Output" : @"Add Input" of:decisionId with:^(NSXMLElement *element) {
		NSXMLElement *column;
		if (output) {
			NSMutableSet *names = [NSMutableSet set];
			for (WKDDmnColumn *existing in decision.outputs) {
				if (existing.name != nil) {
					[names addObject:existing.name];
				}
			}
			NSString *name = @"result";
			for (NSUInteger n = 2; [names containsObject:name]; n++) {
				name = [NSString stringWithFormat:@"result%lu", (unsigned long)n];
			}
			column = [self newOutputNamed:name];
		} else {
			column = [self newInput];
		}
		NSArray *existing = WKDChildren(table, dmn, output ? @"output" : @"input");
		WKDPlaceBefore(table, column, index < [existing count] ? [existing objectAtIndex:index] : nil, WKDTableOrder());
		for (NSXMLElement *rule in WKDChildren(table, dmn, @"rule")) {
			NSArray *entries = [self entriesOf:rule output:output count:[columns count]];
			NSXMLElement *entry = [self newExpression:output ? @"outputEntry" : @"inputEntry"
			                                   prefix:output ? @"LiteralExpression" : @"UnaryTests" text:@""];
			WKDPlaceBefore(rule, entry, index < [entries count] ? [entries objectAtIndex:index] : nil, WKDRuleOrder());
		}
	}];
	return output ? [decision.inputs count] + index : index;
}

- (void)deleteColumn:(NSUInteger)column of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [self decisionWithId:decisionId];
	BOOL output;
	NSUInteger index;
	if (![self column:column of:decision output:&output index:&index]) {
		return;
	}
	NSXMLElement *table = [self tableOf:decisionId];
	NSString *dmn = [self dmn];
	[self change:output ? @"Delete Output" : @"Delete Input" of:decisionId with:^(NSXMLElement *element) {
		[[WKDChildren(table, dmn, output ? @"output" : @"input") objectAtIndex:index] detach];
		for (NSXMLElement *rule in WKDChildren(table, dmn, @"rule")) {
			NSArray *entries = WKDChildren(rule, dmn, output ? @"outputEntry" : @"inputEntry");
			if (index < [entries count]) {
				[[entries objectAtIndex:index] detach];
			}
		}
	}];
}

- (void)moveColumn:(NSUInteger)column to:(NSUInteger)target of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [self decisionWithId:decisionId];
	BOOL output;
	NSUInteger index;
	if (![self column:column of:decision output:&output index:&index]) {
		return;
	}
	NSUInteger count = output ? [decision.outputs count] : [decision.inputs count];
	NSUInteger first = output ? [decision.inputs count] : 0;
	NSUInteger to = MIN(MAX(target, first), first + count - 1) - first;
	if (to == index) {
		return;
	}
	NSXMLElement *table = [self tableOf:decisionId];
	NSString *dmn = [self dmn];
	[self change:@"Move Column" of:decisionId with:^(NSXMLElement *element) {
		[self move:WKDChildren(table, dmn, output ? @"output" : @"input") from:index to:to in:table
		     order:WKDTableOrder()];
		for (NSXMLElement *rule in WKDChildren(table, dmn, @"rule")) {
			NSArray *entries = [self entriesOf:rule output:output count:count];
			[self move:entries from:index to:to in:rule order:WKDRuleOrder()];
		}
	}];
}

/* One of the siblings moved to the index among them. */
- (void)move:(NSArray<NSXMLElement *> *)siblings from:(NSUInteger)from to:(NSUInteger)to
          in:(NSXMLElement *)parent order:(NSArray *)order
{
	NSXMLElement *moved = [siblings objectAtIndex:from];
	NSMutableArray *rest = [siblings mutableCopy];
	[rest removeObjectAtIndex:from];
	[moved detach];
	WKDPlaceBefore(parent, moved, to < [rest count] ? [rest objectAtIndex:to] : nil, order);
}

- (void)setColumn:(NSUInteger)column property:(NSString *)property to:(NSString *)value of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [self decisionWithId:decisionId];
	BOOL output;
	NSUInteger index;
	if (![self column:column of:decision output:&output index:&index]) {
		return;
	}
	NSXMLElement *table = [self tableOf:decisionId];
	NSString *dmn = [self dmn];
	NSDictionary *actions = @{ @"label": @"Label", @"expression": @"Input Expression", @"typeRef": @"Type",
	                           @"inputVariable": @"Input Variable", @"name": @"Output Name" };
	if ([actions objectForKey:property] == nil || (output && ([property isEqualToString:@"expression"]
	                                                         || [property isEqualToString:@"inputVariable"]))
	    || (!output && [property isEqualToString:@"name"])) {
		return;
	}
	[self change:[actions objectForKey:property] of:decisionId with:^(NSXMLElement *element) {
		NSXMLElement *clause = [WKDChildren(table, dmn, output ? @"output" : @"input") objectAtIndex:index];
		if (output || [property isEqualToString:@"label"]) {
			WKDSetAttribute(clause, property, WKDNonEmpty(value));
		} else if ([property isEqualToString:@"inputVariable"]) {
			WKDSetQualifiedAttribute(self->_document, clause, WKDCamundaDmnNamespace, @"inputVariable", value);
		} else {
			NSXMLElement *expression = WKDChild(clause, dmn, @"inputExpression");
			if (expression == nil) {
				expression = [self newExpression:@"inputExpression" prefix:@"LiteralExpression" text:@""];
				[clause addChild:expression];
			}
			if ([property isEqualToString:@"typeRef"]) {
				WKDSetAttribute(expression, @"typeRef", WKDNonEmpty(value));
			} else {
				[self setText:value of:expression];
			}
		}
	}];
}

- (NSXMLElement *)newRuleFor:(WKDDmnDecision *)decision
{
	NSXMLElement *rule = [self newElement:@"rule" prefix:@"DecisionRule"];
	for (NSUInteger i = 0; i < [decision.inputs count]; i++) {
		[rule addChild:[self newExpression:@"inputEntry" prefix:@"UnaryTests" text:@""]];
	}
	for (NSUInteger i = 0; i < [decision.outputs count]; i++) {
		[rule addChild:[self newExpression:@"outputEntry" prefix:@"LiteralExpression" text:@""]];
	}
	return rule;
}

- (void)insertRuleAt:(NSUInteger)index of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [self decisionWithId:decisionId];
	NSXMLElement *table = [self tableOf:decisionId];
	if (table == nil) {
		return;
	}
	NSString *dmn = [self dmn];
	[self change:@"Add Rule" of:decisionId with:^(NSXMLElement *element) {
		NSArray *rules = WKDChildren(table, dmn, @"rule");
		WKDPlaceBefore(table, [self newRuleFor:decision], index < [rules count] ? [rules objectAtIndex:index] : nil,
		               WKDTableOrder());
	}];
}

- (void)duplicateRule:(NSUInteger)rule of:(NSString *)decisionId
{
	NSXMLElement *table = [self tableOf:decisionId];
	NSArray *rules = WKDChildren(table, [self dmn], @"rule");
	if (rule >= [rules count]) {
		return;
	}
	[self change:@"Duplicate Rule" of:decisionId with:^(NSXMLElement *element) {
		NSXMLElement *original = [rules objectAtIndex:rule];
		NSXMLElement *copy = [original copy];
		WKDSetAttribute(copy, @"id", [self freshId:@"DecisionRule"]);
		for (NSXMLNode *child in [copy children]) {
			if ([child kind] != NSXMLElementKind) {
				continue;
			}
			NSString *local = [child localName];
			if ([local isEqualToString:@"inputEntry"] || [local isEqualToString:@"outputEntry"]) {
				WKDSetAttribute((NSXMLElement *)child, @"id",
				                [self freshId:[local isEqualToString:@"inputEntry"] ? @"UnaryTests" : @"LiteralExpression"]);
			}
		}
		[table insertChild:copy atIndex:[original index] + 1];
	}];
}

- (void)deleteRules:(NSIndexSet *)indexes of:(NSString *)decisionId
{
	NSXMLElement *table = [self tableOf:decisionId];
	NSArray *rules = WKDChildren(table, [self dmn], @"rule");
	if ([indexes count] == 0 || [indexes lastIndex] >= [rules count]) {
		return;
	}
	[self change:[indexes count] == 1 ? @"Delete Rule" : @"Delete Rules" of:decisionId with:^(NSXMLElement *element) {
		for (NSXMLElement *rule in [rules objectsAtIndexes:indexes]) {
			[rule detach];
		}
	}];
}

- (void)moveRule:(NSUInteger)rule to:(NSUInteger)index of:(NSString *)decisionId
{
	NSXMLElement *table = [self tableOf:decisionId];
	NSArray *rules = WKDChildren(table, [self dmn], @"rule");
	if (rule >= [rules count] || MIN(index, [rules count] - 1) == rule) {
		return;
	}
	[self change:@"Move Rule" of:decisionId with:^(NSXMLElement *element) {
		[self move:rules from:rule to:MIN(index, [rules count] - 1) in:table order:WKDTableOrder()];
	}];
}

- (void)setEntry:(NSString *)text rule:(NSUInteger)rule column:(NSUInteger)column of:(NSString *)decisionId
{
	WKDDmnDecision *decision = [self decisionWithId:decisionId];
	BOOL output;
	NSUInteger index;
	NSXMLElement *table = [self tableOf:decisionId];
	NSArray *rules = WKDChildren(table, [self dmn], @"rule");
	if (![self column:column of:decision output:&output index:&index] || rule >= [rules count]) {
		return;
	}
	NSUInteger count = output ? [decision.outputs count] : [decision.inputs count];
	[self change:@"Entry" of:decisionId with:^(NSXMLElement *element) {
		NSArray *entries = [self entriesOf:[rules objectAtIndex:rule] output:output count:count];
		[self setText:text of:[entries objectAtIndex:index]];
	}];
}

- (void)setAnnotation:(NSString *)text rule:(NSUInteger)rule of:(NSString *)decisionId
{
	NSXMLElement *table = [self tableOf:decisionId];
	NSString *dmn = [self dmn];
	NSArray *rules = WKDChildren(table, dmn, @"rule");
	if (rule >= [rules count]) {
		return;
	}
	[self change:@"Annotation" of:decisionId with:^(NSXMLElement *element) {
		NSXMLElement *ruleElement = [rules objectAtIndex:rule];
		NSXMLElement *description = WKDChild(ruleElement, dmn, @"description");
		if ([text length] == 0) {
			[description detach];
			return;
		}
		if (description == nil) {
			description = [self newElement:@"description" prefix:nil];
			WKDPlace(ruleElement, description, WKDRuleOrder());
		}
		[description setStringValue:text];
	}];
}

#pragma mark Literal expressions

- (void)setLiteral:(NSString *)property to:(NSString *)value of:(NSString *)decisionId
{
	NSString *dmn = [self dmn];
	NSXMLElement *element = [self elementOf:decisionId];
	if (element == nil || WKDChild(element, dmn, @"decisionTable") != nil) {
		return;
	}
	NSDictionary *actions = @{ @"expression": @"Expression", @"variableName": @"Variable", @"variableType": @"Type" };
	if ([actions objectForKey:property] == nil) {
		return;
	}
	[self change:[actions objectForKey:property] of:decisionId with:^(NSXMLElement *decision) {
		if ([property isEqualToString:@"expression"]) {
			NSXMLElement *literal = WKDChild(decision, dmn, @"literalExpression");
			if (literal == nil) {
				literal = [self newExpression:@"literalExpression" prefix:@"LiteralExpression" text:@""];
				WKDPlace(decision, literal, WKDDecisionOrder());
			}
			[self setText:value of:literal];
			return;
		}
		NSXMLElement *variable = WKDChild(decision, dmn, @"variable");
		if (variable == nil) {
			variable = [self newElement:@"variable" prefix:@"InformationItem"];
			WKDPlace(decision, variable, WKDDecisionOrder());
		}
		WKDSetAttribute(variable, [property isEqualToString:@"variableName"] ? @"name" : @"typeRef", WKDNonEmpty(value));
	}];
}

@end

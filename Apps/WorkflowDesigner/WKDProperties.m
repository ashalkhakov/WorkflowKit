#import "WKDProperties.h"
#import "WKDDiagram.h"
#import "WKDEditor.h"
#import "WKDXML.h"

typedef NSString *(^WKDRead)(NSXMLElement *element, NSXMLDocument *document);
/* NO, with why, when it cannot be written. */
typedef BOOL (^WKDWrite)(WKDEditor *editor, NSString *elementId, NSString *value, NSString **reason);

/* A table's entries in what holds them -- the element, or a master row's
 * entry -- each read as a row, written from one, made, and what is left
 * empty when they go tidied away. */
typedef NSArray<NSXMLElement *> *(^WKDEntries)(NSXMLElement *container);
typedef NSArray<NSString *> *(^WKDReadRow)(NSXMLElement *entry, NSXMLDocument *document);
typedef void (^WKDWriteRow)(NSXMLElement *entry, NSArray<NSString *> *values, NSXMLDocument *document);
typedef NSXMLElement *(^WKDMakeEntry)(NSXMLElement *container, NSXMLDocument *document);
typedef void (^WKDTidy)(NSXMLElement *container);

@interface WKDProperty ()
@property (nonatomic, copy) WKDRead read;
@property (nonatomic, copy) WKDWrite write;
@property (nonatomic, copy) WKDEntries entries;
@property (nonatomic, copy) WKDReadRow readRow;
@property (nonatomic, copy) WKDWriteRow writeRow;
@property (nonatomic, copy) WKDMakeEntry makeEntry;
@property (nonatomic, copy) WKDTidy tidy;
/* A detail's table, whose rows' entries hold its entries. */
@property (nonatomic, weak) WKDProperty *masterTable;
@end

@implementation WKDColumn
- (instancetype)init
{
	if ((self = [super init])) {
		_share = 1;
	}
	return self;
}
@end

@implementation WKDRow
+ (instancetype)rowWithValues:(NSArray<NSString *> *)values
{
	WKDRow *row = [[self alloc] init];
	row.source = NSNotFound;
	row.values = values;
	return row;
}
@end

@implementation WKDProperty

- (NSString *)valueIn:(WKDEditor *)editor of:(NSString *)elementId
{
	NSXMLElement *element = [editor elementWithId:elementId];
	return element != nil ? self.read(element, editor.document) ?: @"" : @"";
}

- (BOOL)setValue:(NSString *)value in:(WKDEditor *)editor of:(NSString *)elementId error:(NSString **)reason
{
	NSString *trimmed = self.kind == WKDPropertyLongText ? value
		: [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed isEqualToString:[self valueIn:editor of:elementId]]) {
		return YES;
	}
	return self.write(editor, elementId, trimmed ?: @"", reason);
}

- (void)setDetails:(NSArray<WKDProperty *> *)details
{
	_details = [details copy];
	for (WKDProperty *detail in details) {
		detail.masterTable = self;
	}
}

/* What holds the table's entries: the element, or a master row's entry. */
- (NSXMLElement *)containerIn:(NSXMLElement *)element master:(NSUInteger)master
{
	if (master == NSNotFound || self.masterTable == nil) {
		return element;
	}
	NSArray *masters = self.masterTable.entries(element);
	return master < [masters count] ? [masters objectAtIndex:master] : nil;
}

- (NSArray<WKDRow *> *)rowsIn:(WKDEditor *)editor of:(NSString *)elementId master:(NSUInteger)master
{
	NSXMLElement *element = [editor elementWithId:elementId];
	NSXMLElement *container = element != nil ? [self containerIn:element master:master] : nil;
	if (container == nil || self.entries == nil) {
		return @[];
	}
	NSMutableArray *rows = [NSMutableArray array];
	NSArray *entries = self.entries(container);
	for (NSUInteger i = 0; i < [entries count]; i++) {
		WKDRow *row = [WKDRow rowWithValues:self.readRow([entries objectAtIndex:i], editor.document)];
		row.source = i;
		[rows addObject:row];
	}
	return rows;
}

static NSArray<NSString *> *
WKDTrimmed(NSArray<NSString *> *values)
{
	NSMutableArray *trimmed = [NSMutableArray array];
	for (NSString *value in values) {
		[trimmed addObject:[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	}
	return trimmed;
}

- (BOOL)setRows:(NSArray<WKDRow *> *)rows in:(WKDEditor *)editor of:(NSString *)elementId
         master:(NSUInteger)master error:(NSString **)reason
{
	NSArray<WKDRow *> *before = [self rowsIn:editor of:elementId master:master];
	BOOL same = [before count] == [rows count];
	for (NSUInteger i = 0; same && i < [rows count]; i++) {
		WKDRow *was = [before objectAtIndex:i], *now = [rows objectAtIndex:i];
		same = was.source == now.source && [was.values isEqualToArray:WKDTrimmed(now.values)];
	}
	if (same) {
		return YES;
	}
	return [editor edit:elementId action:self.label with:^(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *container = [self containerIn:element master:master];
		if (container == nil) {
			return;
		}
		NSArray *existing = self.entries(container);
		NSMutableArray *kept = [NSMutableArray array];
		for (WKDRow *row in rows) {
			NSXMLElement *entry = row.source < [existing count] ? [existing objectAtIndex:row.source]
				: self.makeEntry(container, document);
			NSArray *values = WKDTrimmed(row.values);
			if (![self.readRow(entry, document) isEqualToArray:values]) {
				self.writeRow(entry, values, document);
			}
			[kept addObject:entry];
		}
		for (NSXMLElement *entry in existing) {
			if ([kept indexOfObjectIdenticalTo:entry] == NSNotFound) {
				[entry detach];
			}
		}
		if (self.tidy != nil) {
			self.tidy(container);
		}
	}];
}

@end

@implementation WKDSection
@end

#pragma mark Building properties

static WKDProperty *
WKDMake(NSString *label, WKDPropertyKind kind, WKDRead read, WKDWrite write)
{
	WKDProperty *property = [[WKDProperty alloc] init];
	property.label = label;
	property.kind = kind;
	property.read = read;
	property.write = write;
	return property;
}

/* A change to the element itself, named for the property. */
static WKDWrite
WKDEditing(NSString *label, void (^edit)(NSXMLElement *element, NSXMLDocument *document, NSString *value,
                                         WKDEditor *editor))
{
	return ^BOOL(WKDEditor *editor, NSString *elementId, NSString *value, NSString **reason) {
		__weak WKDEditor *weakEditor = editor;
		return [editor edit:elementId action:label with:^(NSXMLElement *element, NSXMLDocument *document) {
			edit(element, document, value, weakEditor);
		}];
	};
}

static WKDProperty *
WKDPlain(NSString *label, NSString *attribute)
{
	return WKDMake(label, WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDAttribute(element, attribute);
	}, WKDEditing(label, ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		WKDSetAttribute(element, attribute, [value length] > 0 ? value : nil);
	}));
}

/* camunda:<local>. */
static WKDProperty *
WKDCamunda(NSString *label, NSString *local)
{
	return WKDMake(label, WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDQualifiedAttribute(document, element, WKDCamundaNamespace, local);
	}, WKDEditing(label, ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		WKDSetQualifiedAttribute(document, element, WKDCamundaNamespace, local, value);
	}));
}

/* A check box over a true/false attribute: unset is the default, and
 * writing the default unsets it. */
static WKDProperty *
WKDFlag(NSString *label, NSString *uri, NSString *local, BOOL byDefault)
{
	NSString *fallback = byDefault ? @"true" : @"false";
	return WKDMake(label, WKDPropertyCheck, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		NSString *value = uri != nil ? WKDQualifiedAttribute(document, element, uri, local) : WKDAttribute(element, local);
		return [value isEqualToString:@"true"] || [value isEqualToString:@"false"] ? value : fallback;
	}, WKDEditing(label, ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		NSString *written = [value isEqualToString:fallback] ? nil : value;
		if (uri != nil) {
			WKDSetQualifiedAttribute(document, element, uri, local, written);
		} else {
			WKDSetAttribute(element, local, written);
		}
	}));
}

static WKDProperty *
WKDChoice(WKDProperty *property, NSArray *values, NSArray *titles)
{
	property.kind = WKDPropertyChoice;
	property.values = values;
	property.titles = titles;
	return property;
}

/* An expression as BPMN writes one: a child element of type
 * tFormalExpression. */
static void
WKDSetExpression(NSXMLDocument *document, NSXMLElement *parent, NSString *local, NSString *value)
{
	NSXMLElement *child = WKDSetChildText(document, parent, WKDBpmnNamespace, local, value);
	if (child != nil && WKDQualifiedAttribute(document, child, WKDXSINamespace, @"type") == nil) {
		WKDSetQualifiedAttribute(document, child, WKDXSINamespace, @"type", @"bpmn:tFormalExpression");
	}
}

/* The text of a child of the element's child: an event definition's timer,
 * the loop's cardinality. */
/* An expression, or literal text that may be one, the engine reads. */
static WKDProperty *
WKDHoldingExpression(WKDProperty *property, WFExpressionPlace place)
{
	property.holdsExpression = YES;
	property.place = place;
	return property;
}

static WKDProperty *
WKDNestedExpression(NSString *label, NSString *outer, NSString *inner, BOOL formal)
{
	return WKDHoldingExpression(WKDMake(label, WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDChildText(WKDChild(element, WKDBpmnNamespace, outer), WKDBpmnNamespace, inner);
	}, WKDEditing(label, ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		NSXMLElement *container = WKDEnsureChild(document, element, WKDBpmnNamespace, outer);
		if (formal) {
			WKDSetExpression(document, container, inner, value);
		} else {
			WKDSetChildText(document, container, WKDBpmnNamespace, inner, value);
		}
	})), WFExpressionPlaceExpression);
}

/* An attribute of the element's child: the loop's camunda:collection. */
static WKDProperty *
WKDNestedCamunda(NSString *label, NSString *outer, NSString *local)
{
	return WKDMake(label, WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *child = WKDChild(element, WKDBpmnNamespace, outer);
		return child != nil ? WKDQualifiedAttribute(document, child, WKDCamundaNamespace, local) : nil;
	}, WKDEditing(label, ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		NSXMLElement *child = WKDEnsureChild(document, element, WKDBpmnNamespace, outer);
		WKDSetQualifiedAttribute(document, child, WKDCamundaNamespace, local, value);
	}));
}

#pragma mark General

static WKDProperty *
WKDIdProperty(void)
{
	return WKDMake(@"Id", WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDAttribute(element, @"id");
	}, ^BOOL(WKDEditor *editor, NSString *elementId, NSString *value, NSString **reason) {
		return [editor renameElement:elementId to:value error:reason];
	});
}

static WKDProperty *
WKDNameProperty(NSString *type)
{
	if ([type isEqualToString:@"textAnnotation"]) {
		WKDProperty *text = WKDMake(@"Text", WKDPropertyLongText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
			return WKDChildText(element, WKDBpmnNamespace, @"text");
		}, WKDEditing(@"Text", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
			WKDSetChildText(document, element, WKDBpmnNamespace, @"text", value);
		}));
		return text;
	}
	return WKDPlain(@"Name", @"name");
}

static WKDProperty *
WKDDocumentation(void)
{
	return WKDMake(@"Documentation", WKDPropertyLongText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDChildText(element, WKDBpmnNamespace, @"documentation");
	}, WKDEditing(@"Documentation", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		WKDSetChildText(document, element, WKDBpmnNamespace, @"documentation", value);
	}));
}

static WKDSection *
WKDMakeSection(NSString *title, NSArray *properties)
{
	WKDSection *section = [[WKDSection alloc] init];
	section.title = title;
	section.properties = properties;
	return section;
}

#pragma mark Flows

static NSArray *
WKDFlowSections(void)
{
	WKDProperty *condition = WKDMake(@"Condition", WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDChildText(element, WKDBpmnNamespace, @"conditionExpression");
	}, WKDEditing(@"Condition", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		WKDSetExpression(document, element, @"conditionExpression", value);
	}));
	condition.placeholder = @"amount > 100";
	WKDHoldingExpression(condition, WFExpressionPlaceExpression);
	/* The source's default: written on the source, not the flow. */
	WKDProperty *isDefault = WKDMake(@"Default flow", WKDPropertyCheck, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *source = WKDElementWithId(document, WKDAttribute(element, @"sourceRef"));
		return [WKDAttribute(source, @"default") isEqualToString:WKDAttribute(element, @"id")] ? @"true" : @"false";
	}, ^BOOL(WKDEditor *editor, NSString *elementId, NSString *value, NSString **reason) {
		NSXMLElement *flow = [editor elementWithId:elementId];
		NSString *sourceId = WKDAttribute(flow, @"sourceRef");
		return [editor edit:sourceId action:@"Default Flow" with:^(NSXMLElement *source, NSXMLDocument *document) {
			if ([value isEqualToString:@"true"]) {
				WKDSetAttribute(source, @"default", elementId);
			} else if ([WKDAttribute(source, @"default") isEqualToString:elementId]) {
				WKDSetAttribute(source, @"default", nil);
			}
		}];
	});
	return @[ WKDMakeSection(@"Flow", @[ condition, isDefault ]) ];
}

#pragma mark Activities

static NSArray *
WKDUserTaskProperties(void)
{
	NSMutableArray *properties = [NSMutableArray array];
	for (NSArray *pair in @[ @[ @"Assignee", @"assignee" ], @[ @"Candidate users", @"candidateUsers" ],
	                          @[ @"Candidate groups", @"candidateGroups" ], @[ @"Due date", @"dueDate" ],
	                          @[ @"Follow-up date", @"followUpDate" ], @[ @"Priority", @"priority" ] ]) {
		[properties addObject:WKDHoldingExpression(WKDCamunda(pair[0], pair[1]), WFExpressionPlaceAttribute)];
	}
	((WKDProperty *)properties[2]).placeholder = @"managers, department:purchasing";
	((WKDProperty *)properties[0]).placeholder = @"ann, ${owner}, =reviewer";
	return properties;
}

static NSArray *
WKDFormProperties(void)
{
	WKDProperty *key = WKDCamunda(@"Form key", @"formKey");
	key.placeholder = @"embedded:deployment:order.xhtml";
	/* The form beside the process, in the form designer: made from the
	 * fields first when there is none. */
	WKDProperty *edit = [[WKDProperty alloc] init];
	edit.label = @"Edit Form…";
	edit.kind = WKDPropertyButton;
	edit.actionName = @"editForm:";
	return @[ key, WKDCamunda(@"Form handler", @"formHandlerClass"), edit ];
}

/* How a service or send task runs: by a worker on a topic, or a delegate
 * the host registers, by class name or expression. */
static NSArray *
WKDImplementationProperties(void)
{
	WKDProperty *kind = WKDMake(@"Implementation", WKDPropertyChoice, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		if ([WKDQualifiedAttribute(document, element, WKDCamundaNamespace, @"type") isEqualToString:@"external"]) {
			return @"external";
		}
		if (WKDQualifiedAttribute(document, element, WKDCamundaNamespace, @"class") != nil) {
			return @"class";
		}
		if (WKDQualifiedAttribute(document, element, WKDCamundaNamespace, @"delegateExpression") != nil) {
			return @"expression";
		}
		return @"";
	}, WKDEditing(@"Implementation", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		NSDictionary *kept = @{ @"external": @[ @"type", @"topic" ], @"class": @[ @"class" ],
		                        @"expression": @[ @"delegateExpression" ] };
		for (NSString *local in @[ @"type", @"topic", @"class", @"delegateExpression" ]) {
			if (![[kept objectForKey:value] containsObject:local]) {
				WKDSetQualifiedAttribute(document, element, WKDCamundaNamespace, local, nil);
			}
		}
		if ([value isEqualToString:@"external"]) {
			WKDSetQualifiedAttribute(document, element, WKDCamundaNamespace, @"type", @"external");
		}
	}));
	kind.values = @[ @"", @"external", @"class", @"expression" ];
	kind.titles = @[ @"None", @"External task", @"Delegate class", @"Delegate expression" ];
	WKDProperty *topic = WKDCamunda(@"Topic", @"topic");
	topic.placeholder = @"For an external task";
	WKDProperty *class = WKDCamunda(@"Delegate class", @"class");
	WKDProperty *expression = WKDCamunda(@"Delegate expression", @"delegateExpression");
	expression.placeholder = @"${mailer}";
	WKDHoldingExpression(expression, WFExpressionPlaceAttribute);
	return @[ kind, topic, class, expression, WKDCamunda(@"Task priority", @"taskPriority") ];
}

static NSArray *
WKDBindingChoice(void)
{
	return @[ @[ @"", @"deployment", @"version" ], @[ @"Latest", @"Same deployment", @"Version" ] ];
}

static NSArray *
WKDBusinessRuleProperties(void)
{
	NSArray *binding = WKDBindingChoice();
	/* The decision, in the decision editor: a file of its own made for it
	 * when no DMN file beside the process defines it. */
	WKDProperty *edit = [[WKDProperty alloc] init];
	edit.label = @"Edit Decision…";
	edit.kind = WKDPropertyButton;
	edit.actionName = @"editDecision:";
	return @[ WKDCamunda(@"Decision", @"decisionRef"), edit,
	          WKDChoice(WKDCamunda(@"Binding", @"decisionRefBinding"), binding[0], binding[1]),
	          WKDCamunda(@"Version", @"decisionRefVersion"),
	          WKDCamunda(@"Result variable", @"resultVariable"),
	          WKDChoice(WKDCamunda(@"Map result", @"mapDecisionResult"),
	                    @[ @"", @"singleResult", @"singleEntry", @"collectEntries" ],
	                    @[ @"Result list", @"Single result", @"Single entry", @"Collect entries" ]) ];
}

static NSArray *
WKDCallActivityProperties(void)
{
	NSArray *binding = WKDBindingChoice();
	return @[ WKDPlain(@"Called process", @"calledElement"),
	          WKDChoice(WKDCamunda(@"Binding", @"calledElementBinding"), binding[0], binding[1]),
	          WKDCamunda(@"Version", @"calledElementVersion") ];
}

static WKDProperty *
WKDScriptAction(void)
{
	WKDProperty *action = WKDMake(@"Action", WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDQualifiedAttribute(document, element, WKDExtensionNamespace, @"action");
	}, WKDEditing(@"Action", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		WKDSetQualifiedAttribute(document, element, WKDExtensionNamespace, @"action", value);
	}));
	action.placeholder = @"The service handler's action key";
	return action;
}

/* The retry cycle: camunda:failedJobRetryTimeCycle among the extensions. */
static WKDProperty *
WKDRetryCycle(void)
{
	WKDProperty *retry = WKDMake(@"Retry cycle", WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *extensions = WKDChild(element, WKDBpmnNamespace, @"extensionElements");
		return WKDChildText(extensions, WKDCamundaNamespace, @"failedJobRetryTimeCycle");
	}, WKDEditing(@"Retry Cycle", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		NSXMLElement *extensions = WKDChild(element, WKDBpmnNamespace, @"extensionElements");
		if ([value length] == 0) {
			[WKDChild(extensions, WKDCamundaNamespace, @"failedJobRetryTimeCycle") detach];
			if (extensions != nil && [[extensions children] count] == 0) {
				[extensions detach];
			}
			return;
		}
		extensions = WKDEnsureChild(document, element, WKDBpmnNamespace, @"extensionElements");
		WKDSetChildText(document, extensions, WKDCamundaNamespace, @"failedJobRetryTimeCycle", value);
	}));
	retry.placeholder = @"R3/PT10M";
	return retry;
}

static NSArray *
WKDAsyncProperties(BOOL activity)
{
	NSMutableArray *properties = [NSMutableArray arrayWithObjects:
		WKDFlag(@"Asynchronous before", WKDCamundaNamespace, @"asyncBefore", NO),
		WKDFlag(@"Asynchronous after", WKDCamundaNamespace, @"asyncAfter", NO),
		WKDFlag(@"Exclusive", WKDCamundaNamespace, @"exclusive", YES), nil];
	if (activity) {
		[properties addObject:WKDRetryCycle()];
	}
	return properties;
}

/* Multi-instance: none, parallel or sequential, and what it runs over. */
static NSArray *
WKDLoopProperties(void)
{
	WKDProperty *loop = WKDMake(@"Instances", WKDPropertyChoice, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *characteristics = WKDChild(element, WKDBpmnNamespace, @"multiInstanceLoopCharacteristics");
		if (characteristics == nil) {
			return @"";
		}
		return [WKDAttribute(characteristics, @"isSequential") isEqualToString:@"true"] ? @"sequential" : @"parallel";
	}, WKDEditing(@"Multi-instance", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		if ([value length] == 0) {
			[WKDChild(element, WKDBpmnNamespace, @"multiInstanceLoopCharacteristics") detach];
			return;
		}
		NSXMLElement *characteristics = WKDEnsureChild(document, element, WKDBpmnNamespace,
		                                               @"multiInstanceLoopCharacteristics");
		WKDSetAttribute(characteristics, @"isSequential", [value isEqualToString:@"sequential"] ? @"true" : nil);
	}));
	loop.values = @[ @"", @"parallel", @"sequential" ];
	loop.titles = @[ @"One", @"Parallel", @"Sequential" ];
	WKDProperty *collection = WKDNestedCamunda(@"Collection", @"multiInstanceLoopCharacteristics", @"collection");
	collection.placeholder = @"reviewers";
	WKDHoldingExpression(collection, WFExpressionPlaceExpression);
	return @[ loop, collection,
	          WKDNestedCamunda(@"Element variable", @"multiInstanceLoopCharacteristics", @"elementVariable"),
	          WKDNestedExpression(@"Cardinality", @"multiInstanceLoopCharacteristics", @"loopCardinality", YES),
	          WKDNestedExpression(@"Completion", @"multiInstanceLoopCharacteristics", @"completionCondition", YES) ];
}

#pragma mark Events

/* The definition child's local name, if the event has one. */
static NSString *
WKDDefinitionOf(NSXMLElement *element)
{
	for (NSXMLElement *child in WKDChildren(element, WKDBpmnNamespace, nil)) {
		if ([[child localName] hasSuffix:@"EventDefinition"]) {
			return [child localName];
		}
	}
	return nil;
}

/* A timer's kind -- a date, a duration, a cycle -- and its text. */
static NSArray *
WKDTimerProperties(void)
{
	NSArray *kinds = @[ @"timeDuration", @"timeDate", @"timeCycle" ];
	WKDRead currentKind = ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *timer = WKDChild(element, WKDBpmnNamespace, @"timerEventDefinition");
		for (NSString *kind in kinds) {
			if (WKDChild(timer, WKDBpmnNamespace, kind) != nil) {
				return kind;
			}
		}
		return @"timeDuration";
	};
	WKDProperty *kind = WKDMake(@"Timer", WKDPropertyChoice, currentKind,
		WKDEditing(@"Timer", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
			NSXMLElement *timer = WKDEnsureChild(document, element, WKDBpmnNamespace, @"timerEventDefinition");
			NSString *text = nil;
			for (NSString *other in kinds) {
				NSXMLElement *child = WKDChild(timer, WKDBpmnNamespace, other);
				if (child != nil) {
					text = [child stringValue];
					[child detach];
				}
			}
			WKDSetExpression(document, timer, value, text ?: @"");
		}));
	kind.values = kinds;
	kind.titles = @[ @"Duration", @"Date", @"Cycle" ];
	WKDProperty *value = WKDMake(@"When", WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *timer = WKDChild(element, WKDBpmnNamespace, @"timerEventDefinition");
		return WKDChildText(timer, WKDBpmnNamespace, currentKind(element, document));
	}, WKDEditing(@"Timer", ^(NSXMLElement *element, NSXMLDocument *document, NSString *text, WKDEditor *editor) {
		NSXMLElement *timer = WKDEnsureChild(document, element, WKDBpmnNamespace, @"timerEventDefinition");
		WKDSetExpression(document, timer, currentKind(element, document), text);
	}));
	value.placeholder = @"PT1H, 2026-12-31T09:00, R3/PT10M";
	WKDHoldingExpression(value, WFExpressionPlaceAttribute);
	return @[ kind, value ];
}

/* A reference to a top-level definition, by what the engine reads it by:
 * a message or a signal by its name, an error or an escalation by its code. */
static WKDProperty *
WKDReference(NSString *label, NSString *holder, NSString *attribute, NSString *local, NSString *key)
{
	WKDRead locate = ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *target = holder != nil ? WKDChild(element, WKDBpmnNamespace, holder) : element;
		NSXMLElement *definition = WKDElementWithId(document, WKDAttribute(target, attribute));
		return definition != nil ? WKDAttribute(definition, key) : nil;
	};
	return WKDMake(label, WKDPropertyText, locate, ^BOOL(WKDEditor *editor, NSString *elementId, NSString *value,
	                                                    NSString **reason) {
		__weak WKDEditor *weakEditor = editor;
		return [editor edit:elementId action:label with:^(NSXMLElement *element, NSXMLDocument *document) {
			NSXMLElement *target = holder != nil ? WKDEnsureChild(document, element, WKDBpmnNamespace, holder) : element;
			NSString *definitionId = [value length] > 0 ? [weakEditor definitionOf:local key:key value:value] : nil;
			WKDSetAttribute(target, attribute, definitionId);
		}];
	});
}

static NSArray *
WKDEventProperties(NSXMLElement *element)
{
	NSString *type = [element localName];
	NSString *definition = WKDDefinitionOf(element);
	NSMutableArray *properties = [NSMutableArray array];
	if ([definition isEqualToString:@"timerEventDefinition"]) {
		[properties addObjectsFromArray:WKDTimerProperties()];
	} else if ([definition isEqualToString:@"messageEventDefinition"]) {
		[properties addObject:WKDReference(@"Message", definition, @"messageRef", @"message", @"name")];
	} else if ([definition isEqualToString:@"signalEventDefinition"]) {
		[properties addObject:WKDReference(@"Signal", definition, @"signalRef", @"signal", @"name")];
	} else if ([definition isEqualToString:@"errorEventDefinition"]) {
		[properties addObject:WKDReference(@"Error code", definition, @"errorRef", @"error", @"errorCode")];
		if (![type isEqualToString:@"endEvent"]) {
			[properties addObject:WKDNestedCamunda(@"Code variable", definition, @"errorCodeVariable")];
		}
	} else if ([definition isEqualToString:@"escalationEventDefinition"]) {
		[properties addObject:WKDReference(@"Escalation code", definition, @"escalationRef", @"escalation",
		                                   @"escalationCode")];
	} else if ([definition isEqualToString:@"conditionalEventDefinition"]) {
		[properties addObject:WKDNestedExpression(@"Condition", definition, @"condition", YES)];
		[properties addObject:WKDNestedCamunda(@"Variable", definition, @"variableName")];
		[properties addObject:WKDNestedCamunda(@"Variable events", definition, @"variableEvents")];
	} else if ([definition isEqualToString:@"linkEventDefinition"]) {
		WKDProperty *link = WKDMake(@"Link", WKDPropertyText, ^NSString *(NSXMLElement *e, NSXMLDocument *d) {
			return WKDAttribute(WKDChild(e, WKDBpmnNamespace, @"linkEventDefinition"), @"name");
		}, WKDEditing(@"Link", ^(NSXMLElement *e, NSXMLDocument *d, NSString *value, WKDEditor *editor) {
			WKDSetAttribute(WKDEnsureChild(d, e, WKDBpmnNamespace, @"linkEventDefinition"), @"name",
			                [value length] > 0 ? value : nil);
		}));
		[properties addObject:link];
	}
	if ([type isEqualToString:@"boundaryEvent"]) {
		[properties addObject:WKDFlag(@"Interrupting", nil, @"cancelActivity", YES)];
	}
	return properties;
}

#pragma mark Sections

static NSArray *
WKDProcessSections(void)
{
	WKDProperty *groups = WKDCamunda(@"Starter groups", @"candidateStarterGroups");
	groups.placeholder = @"Anyone may start it";
	return @[ WKDMakeSection(@"Process", @[ WKDIdProperty(), WKDPlain(@"Name", @"name"),
	                                        WKDFlag(@"Executable", nil, @"isExecutable", NO),
	                                        WKDDocumentation() ]),
	          WKDMakeSection(@"Starting", @[ groups, WKDCamunda(@"Starter users", @"candidateStarterUsers") ]),
	          WKDMakeSection(@"Running", @[ WKDCamunda(@"History days", @"historyTimeToLive"),
	                                        WKDCamunda(@"Task priority", @"taskPriority") ]) ];
}

#pragma mark Tables

static WKDColumn *
WKDTextColumn(NSString *title, double share)
{
	WKDColumn *column = [[WKDColumn alloc] init];
	column.title = title;
	column.kind = WKDPropertyText;
	column.share = share;
	return column;
}

/* Text the engine reads as literal unless it is ${...} or =FEEL. */
static WKDColumn *
WKDValueColumn(NSString *title, double share)
{
	WKDColumn *column = WKDTextColumn(title, share);
	column.holdsExpression = YES;
	column.place = WFExpressionPlaceAttribute;
	return column;
}

static WKDColumn *
WKDChoiceColumn(NSString *title, NSArray *values, NSArray *titles, double share)
{
	WKDColumn *column = WKDTextColumn(title, share);
	column.kind = WKDPropertyChoice;
	column.values = values;
	column.titles = titles;
	return column;
}

static WKDProperty *
WKDTable(NSString *label, NSArray<WKDColumn *> *columns, NSArray<NSString *> *blankRow, WKDEntries entries,
         WKDReadRow read, WKDWriteRow write, WKDMakeEntry make, WKDTidy tidy)
{
	WKDProperty *property = [[WKDProperty alloc] init];
	property.label = label;
	property.kind = WKDPropertyTable;
	property.columns = columns;
	property.blankRow = blankRow;
	property.entries = entries;
	property.readRow = read;
	property.writeRow = write;
	property.makeEntry = make;
	property.tidy = tidy;
	return property;
}

static NSXMLElement *
WKDExtensions(NSXMLElement *element)
{
	return WKDChild(element, WKDBpmnNamespace, @"extensionElements");
}

static BOOL
WKDHoldsElements(NSXMLElement *element)
{
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			return YES;
		}
	}
	return NO;
}

/* What is left empty goes: a wrapper with nothing in it, then the
 * extension elements. */
static void
WKDTidyExtensions(NSXMLElement *element, NSString *wrapper)
{
	NSXMLElement *extensions = WKDExtensions(element);
	if (wrapper != nil) {
		NSXMLElement *holder = WKDChild(extensions, WKDCamundaNamespace, wrapper);
		if (holder != nil && !WKDHoldsElements(holder)) {
			[holder detach];
		}
	}
	if (extensions != nil && !WKDHoldsElements(extensions)) {
		[extensions detach];
	}
}

/* A new camunda: element at the end of what holds it. */
static NSXMLElement *
WKDAppendCamunda(NSXMLDocument *document, NSXMLElement *holder, NSString *local)
{
	NSXMLElement *entry = WKDNewElement(document, WKDCamundaNamespace, local);
	[holder addChild:entry];
	return entry;
}

/* A parameter's value as text: the element's own, or a camunda:list or
 * camunda:map written as the FEEL the engine reads it as. */
static NSString *
WKDParameterText(NSXMLElement *parameter)
{
	NSXMLElement *structured = [WKDChildren(parameter, WKDCamundaNamespace, nil) firstObject];
	if (structured == nil) {
		return [[parameter stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}
	NSString *(^item)(NSXMLElement *) = ^NSString *(NSXMLElement *value) {
		NSString *text = WKDParameterText(value);
		if ([text hasPrefix:@"="]) {
			return [text substringFromIndex:1];
		}
		if (([text hasPrefix:@"${"] || [text hasPrefix:@"#{"]) && [text hasSuffix:@"}"]) {
			return [text substringWithRange:NSMakeRange(2, [text length] - 3)];
		}
		return [NSString stringWithFormat:@"\"%@\"", [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
	};
	NSMutableArray *parts = [NSMutableArray array];
	if ([[structured localName] isEqualToString:@"list"]) {
		for (NSXMLElement *value in WKDChildren(structured, WKDCamundaNamespace, nil)) {
			[parts addObject:item(value)];
		}
		return [NSString stringWithFormat:@"=[%@]", [parts componentsJoinedByString:@", "]];
	}
	if ([[structured localName] isEqualToString:@"map"]) {
		for (NSXMLElement *entry in WKDChildren(structured, WKDCamundaNamespace, @"entry")) {
			[parts addObject:[NSString stringWithFormat:@"\"%@\": %@", WKDAttribute(entry, @"key") ?: @"", item(entry)]];
		}
		return [NSString stringWithFormat:@"={%@}", [parts componentsJoinedByString:@", "]];
	}
	return [NSString stringWithFormat:@"camunda:%@", [structured localName]];
}

/* camunda:inputOutput's input or output parameters: a name and a value,
 * literal, ${...} or =FEEL. */
static WKDProperty *
WKDParameters(BOOL inputs)
{
	NSString *local = inputs ? @"inputParameter" : @"outputParameter";
	WKDEntries entries = ^NSArray *(NSXMLElement *element) {
		NSXMLElement *holder = WKDChild(WKDExtensions(element), WKDCamundaNamespace, @"inputOutput");
		return holder != nil ? WKDChildren(holder, WKDCamundaNamespace, local) : @[];
	};
	WKDReadRow read = ^NSArray *(NSXMLElement *entry, NSXMLDocument *document) {
		return @[ WKDAttribute(entry, @"name") ?: @"", WKDParameterText(entry) ];
	};
	WKDWriteRow write = ^(NSXMLElement *entry, NSArray *values, NSXMLDocument *document) {
		WKDSetAttribute(entry, @"name", [values[0] length] > 0 ? values[0] : nil);
		if (![values[1] isEqualToString:WKDParameterText(entry)]) {
			[entry setStringValue:values[1]];
		}
	};
	WKDMakeEntry make = ^NSXMLElement *(NSXMLElement *element, NSXMLDocument *document) {
		NSXMLElement *extensions = WKDEnsureChild(document, element, WKDBpmnNamespace, @"extensionElements");
		NSXMLElement *holder = WKDEnsureChild(document, extensions, WKDCamundaNamespace, @"inputOutput");
		NSXMLElement *entry = WKDNewElement(document, WKDCamundaNamespace, local);
		/* Inputs before outputs, as the schema has them. */
		NSXMLElement *firstOutput = inputs ? WKDChild(holder, WKDCamundaNamespace, @"outputParameter") : nil;
		if (firstOutput != nil) {
			[holder insertChild:entry atIndex:[firstOutput index]];
		} else {
			[holder addChild:entry];
		}
		return entry;
	};
	WKDProperty *table = WKDTable(inputs ? @"Inputs" : @"Outputs",
		@[ WKDTextColumn(@"Variable", 1), WKDValueColumn(@"Value", 1.6) ], @[ @"", @"" ], entries, read, write, make,
		^(NSXMLElement *element) {
			WKDTidyExtensions(element, @"inputOutput");
		});
	table.placeholder = inputs ? @"Local variables, set as the activity is entered"
		: @"Variables set where the activity is, as it completes";
	return table;
}

/* camunda:field, on a delegate or a listener: a name, and text or an
 * expression. */
static WKDProperty *
WKDFields(BOOL inExtensions)
{
	WKDEntries entries = ^NSArray *(NSXMLElement *container) {
		NSXMLElement *holder = inExtensions ? WKDExtensions(container) : container;
		return holder != nil ? WKDChildren(holder, WKDCamundaNamespace, @"field") : @[];
	};
	WKDReadRow read = ^NSArray *(NSXMLElement *field, NSXMLDocument *document) {
		NSString *expression = WKDAttribute(field, @"expression")
			?: WKDChildText(field, WKDCamundaNamespace, @"expression");
		NSString *text = WKDAttribute(field, @"stringValue") ?: WKDChildText(field, WKDCamundaNamespace, @"string");
		return @[ WKDAttribute(field, @"name") ?: @"", expression != nil ? @"expression" : @"string",
		          expression ?: text ?: @"" ];
	};
	WKDWriteRow write = ^(NSXMLElement *field, NSArray *values, NSXMLDocument *document) {
		WKDSetAttribute(field, @"name", [values[0] length] > 0 ? values[0] : nil);
		WKDSetAttribute(field, @"stringValue", nil);
		WKDSetAttribute(field, @"expression", nil);
		for (NSXMLElement *child in WKDChildren(field, WKDCamundaNamespace, nil)) {
			[child detach];
		}
		WKDSetAttribute(field, [values[1] isEqualToString:@"expression"] ? @"expression" : @"stringValue", values[2]);
	};
	WKDMakeEntry make = ^NSXMLElement *(NSXMLElement *container, NSXMLDocument *document) {
		NSXMLElement *holder = inExtensions
			? WKDEnsureChild(document, container, WKDBpmnNamespace, @"extensionElements") : container;
		return WKDAppendCamunda(document, holder, @"field");
	};
	WKDProperty *table = WKDTable(@"Fields",
		@[ WKDTextColumn(@"Field", 1), WKDChoiceColumn(@"As", @[ @"string", @"expression" ], @[ @"Text", @"Expression" ], 0.9),
		   WKDValueColumn(@"Value", 1.4) ], @[ @"", @"string", @"" ], entries, read, write, make,
		inExtensions ? ^(NSXMLElement *element) { WKDTidyExtensions(element, nil); } : nil);
	table.placeholder = @"Set on the delegate by key-value coding";
	return table;
}

/* camunda:executionListener or camunda:taskListener: when, and the delegate
 * it calls, by class or by name, with its fields. */
static WKDProperty *
WKDListeners(BOOL task, NSArray *events)
{
	NSString *local = task ? @"taskListener" : @"executionListener";
	WKDEntries entries = ^NSArray *(NSXMLElement *element) {
		NSXMLElement *extensions = WKDExtensions(element);
		return extensions != nil ? WKDChildren(extensions, WKDCamundaNamespace, local) : @[];
	};
	WKDReadRow read = ^NSArray *(NSXMLElement *listener, NSXMLDocument *document) {
		NSString *expression = WKDAttribute(listener, @"delegateExpression");
		return @[ WKDAttribute(listener, @"event") ?: [events firstObject],
		          expression != nil ? @"delegateExpression" : @"class",
		          expression ?: WKDAttribute(listener, @"class") ?: @"" ];
	};
	WKDWriteRow write = ^(NSXMLElement *listener, NSArray *values, NSXMLDocument *document) {
		WKDSetAttribute(listener, @"event", values[0]);
		WKDSetAttribute(listener, @"class", nil);
		WKDSetAttribute(listener, @"delegateExpression", nil);
		/* Even empty: which it is to be is kept until it is filled in. */
		WKDSetAttribute(listener, values[1], values[2]);
	};
	WKDMakeEntry make = ^NSXMLElement *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDAppendCamunda(document, WKDEnsureChild(document, element, WKDBpmnNamespace, @"extensionElements"), local);
	};
	NSDictionary *titles = @{ @"start": @"Start", @"end": @"End", @"take": @"Take", @"create": @"Create",
	                          @"assignment": @"Assignment", @"complete": @"Complete", @"delete": @"Delete" };
	NSMutableArray *eventTitles = [NSMutableArray array];
	for (NSString *event in events) {
		[eventTitles addObject:[titles objectForKey:event]];
	}
	WKDProperty *table = WKDTable(task ? @"Task listeners" : @"Execution listeners",
		@[ WKDChoiceColumn(@"On", events, eventTitles, 0.9),
		   WKDChoiceColumn(@"By", @[ @"class", @"delegateExpression" ], @[ @"Class", @"Name" ], 0.8),
		   WKDValueColumn(@"Delegate", 1.5) ],
		@[ [events firstObject], @"delegateExpression", @"" ], entries, read, write, make,
		^(NSXMLElement *element) {
			WKDTidyExtensions(element, nil);
		});
	table.details = @[ WKDFields(NO) ];
	table.placeholder = @"Host code, as a delegate is found: a class, or ${name} registered";
	return table;
}

/* A call activity's camunda:in or camunda:out: a variable by name, every
 * variable, or the business key passed on. */
static WKDProperty *
WKDCallVariables(BOOL inputs)
{
	NSString *local = inputs ? @"in" : @"out";
	NSArray *kinds = inputs ? @[ @"variable", @"all", @"businessKey" ] : @[ @"variable", @"all" ];
	NSArray *kindTitles = inputs ? @[ @"Variable", @"All", @"Business key" ] : @[ @"Variable", @"All" ];
	WKDEntries entries = ^NSArray *(NSXMLElement *element) {
		NSXMLElement *extensions = WKDExtensions(element);
		return extensions != nil ? WKDChildren(extensions, WKDCamundaNamespace, local) : @[];
	};
	WKDReadRow read = ^NSArray *(NSXMLElement *mapping, NSXMLDocument *document) {
		if (WKDAttribute(mapping, @"businessKey") != nil) {
			return @[ @"businessKey", @"", @"" ];
		}
		if ([WKDAttribute(mapping, @"variables") isEqualToString:@"all"]) {
			return @[ @"all", @"", @"" ];
		}
		return @[ @"variable", WKDAttribute(mapping, @"source") ?: @"", WKDAttribute(mapping, @"target") ?: @"" ];
	};
	WKDWriteRow write = ^(NSXMLElement *mapping, NSArray *values, NSXMLDocument *document) {
		for (NSString *attribute in @[ @"source", @"target", @"variables", @"businessKey", @"sourceExpression", @"local" ]) {
			WKDSetAttribute(mapping, attribute, nil);
		}
		if ([values[0] isEqualToString:@"businessKey"]) {
			WKDSetAttribute(mapping, @"businessKey", @"#{execution.processBusinessKey}");
		} else if ([values[0] isEqualToString:@"all"]) {
			WKDSetAttribute(mapping, @"variables", @"all");
		} else {
			WKDSetAttribute(mapping, @"source", [values[1] length] > 0 ? values[1] : nil);
			WKDSetAttribute(mapping, @"target", [values[2] length] > 0 ? values[2] : nil);
		}
	};
	WKDMakeEntry make = ^NSXMLElement *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDAppendCamunda(document, WKDEnsureChild(document, element, WKDBpmnNamespace, @"extensionElements"), local);
	};
	WKDProperty *table = WKDTable(inputs ? @"Passed in" : @"Passed back",
		@[ WKDChoiceColumn(@"What", kinds, kindTitles, 1.35), WKDTextColumn(@"From", 1), WKDTextColumn(@"To", 1) ],
		@[ @"variable", @"", @"" ], entries, read, write, make,
		^(NSXMLElement *element) {
			WKDTidyExtensions(element, nil);
		});
	table.placeholder = inputs ? @"Variables of this instance the called one starts with"
		: @"Variables of the called instance this one takes back";
	return table;
}

#pragma mark Forms

static NSXMLElement *
WKDFormData(NSXMLElement *element)
{
	return WKDChild(WKDExtensions(element), WKDCamundaNamespace, @"formData");
}

/* The constraint of that name in the field's validation, or nil. */
static NSXMLElement *
WKDConstraint(NSXMLElement *field, NSString *name)
{
	for (NSXMLElement *constraint in WKDChildren(WKDChild(field, WKDCamundaNamespace, @"validation"),
	                                             WKDCamundaNamespace, @"constraint")) {
		if ([WKDAttribute(constraint, @"name") isEqualToString:name]) {
			return constraint;
		}
	}
	return nil;
}

static void
WKDTidyField(NSXMLElement *field)
{
	for (NSString *local in @[ @"validation", @"properties" ]) {
		NSXMLElement *holder = WKDChild(field, WKDCamundaNamespace, local);
		if (holder != nil && !WKDHoldsElements(holder)) {
			[holder detach];
		}
	}
}

/* A constraint with no configuration -- required, readonly -- there or not. */
static void
WKDSetFlagConstraint(NSXMLDocument *document, NSXMLElement *field, NSString *name, BOOL on)
{
	NSXMLElement *constraint = WKDConstraint(field, name);
	if (on && constraint == nil) {
		NSXMLElement *validation = WKDEnsureChild(document, field, WKDCamundaNamespace, @"validation");
		WKDSetAttribute(WKDAppendCamunda(document, validation, @"constraint"), @"name", name);
	} else if (!on) {
		[constraint detach];
	}
}

/* A form field's constraints other than required and readonly, which are
 * its own columns: a name and its configuration. */
static WKDProperty *
WKDFieldConstraints(void)
{
	NSSet *flags = [NSSet setWithObjects:@"required", @"readonly", nil];
	WKDEntries entries = ^NSArray *(NSXMLElement *field) {
		NSMutableArray *found = [NSMutableArray array];
		for (NSXMLElement *constraint in WKDChildren(WKDChild(field, WKDCamundaNamespace, @"validation"),
		                                             WKDCamundaNamespace, @"constraint")) {
			if (![flags containsObject:WKDAttribute(constraint, @"name") ?: @""]) {
				[found addObject:constraint];
			}
		}
		return found;
	};
	NSArray *names = @[ @"minlength", @"maxlength", @"min", @"max" ];
	WKDProperty *table = WKDTable(@"Constraints",
		@[ WKDChoiceColumn(@"Constraint", names, @[ @"Shortest", @"Longest", @"Least", @"Most" ], 1),
		   WKDTextColumn(@"Value", 1) ],
		@[ @"minlength", @"" ], entries,
		^NSArray *(NSXMLElement *constraint, NSXMLDocument *document) {
			return @[ WKDAttribute(constraint, @"name") ?: @"", WKDAttribute(constraint, @"config") ?: @"" ];
		},
		^(NSXMLElement *constraint, NSArray *values, NSXMLDocument *document) {
			WKDSetAttribute(constraint, @"name", values[0]);
			WKDSetAttribute(constraint, @"config", [values[1] length] > 0 ? values[1] : nil);
		},
		^NSXMLElement *(NSXMLElement *field, NSXMLDocument *document) {
			return WKDAppendCamunda(document, WKDEnsureChild(document, field, WKDCamundaNamespace, @"validation"),
			                        @"constraint");
		},
		^(NSXMLElement *field) {
			WKDTidyField(field);
		});
	table.placeholder = @"A text's length, a number's or a date's bounds";
	return table;
}

/* An enum field's values: an id, what is stored, and its name, what is shown. */
static WKDProperty *
WKDFieldValues(void)
{
	WKDProperty *table = WKDTable(@"Values",
		@[ WKDTextColumn(@"Id", 1), WKDTextColumn(@"Name", 1.4) ], @[ @"", @"" ],
		^NSArray *(NSXMLElement *field) {
			return WKDChildren(field, WKDCamundaNamespace, @"value");
		},
		^NSArray *(NSXMLElement *value, NSXMLDocument *document) {
			return @[ WKDAttribute(value, @"id") ?: @"", WKDAttribute(value, @"name") ?: @"" ];
		},
		^(NSXMLElement *value, NSArray *values, NSXMLDocument *document) {
			WKDSetAttribute(value, @"id", values[0]);
			WKDSetAttribute(value, @"name", [values[1] length] > 0 ? values[1] : nil);
		},
		^NSXMLElement *(NSXMLElement *field, NSXMLDocument *document) {
			/* Values before validation and properties, as Modeler writes them. */
			NSXMLElement *value = WKDNewElement(document, WKDCamundaNamespace, @"value");
			NSXMLElement *after = WKDChild(field, WKDCamundaNamespace, @"validation")
				?: WKDChild(field, WKDCamundaNamespace, @"properties");
			NSArray *existing = WKDChildren(field, WKDCamundaNamespace, @"value");
			if ([existing count] > 0) {
				[field insertChild:value atIndex:[[existing lastObject] index] + 1];
			} else if (after != nil) {
				[field insertChild:value atIndex:[after index]];
			} else {
				[field addChild:value];
			}
			return value;
		}, nil);
	table.placeholder = @"An enum field's choices";
	return table;
}

/* A field's camunda:properties: what the form's renderer is told. */
static WKDProperty *
WKDFieldProperties(void)
{
	WKDProperty *table = WKDTable(@"Properties",
		@[ WKDTextColumn(@"Property", 1), WKDTextColumn(@"Value", 1.4) ], @[ @"", @"" ],
		^NSArray *(NSXMLElement *field) {
			return WKDChildren(WKDChild(field, WKDCamundaNamespace, @"properties"), WKDCamundaNamespace, @"property");
		},
		^NSArray *(NSXMLElement *property, NSXMLDocument *document) {
			return @[ WKDAttribute(property, @"id") ?: @"", WKDAttribute(property, @"value") ?: @"" ];
		},
		^(NSXMLElement *property, NSArray *values, NSXMLDocument *document) {
			WKDSetAttribute(property, @"id", values[0]);
			WKDSetAttribute(property, @"value", values[1]);
		},
		^NSXMLElement *(NSXMLElement *field, NSXMLDocument *document) {
			return WKDAppendCamunda(document, WKDEnsureChild(document, field, WKDCamundaNamespace, @"properties"),
			                        @"property");
		},
		^(NSXMLElement *field) {
			WKDTidyField(field);
		});
	table.placeholder = @"Hints for the form, by name";
	return table;
}

/* camunda:formData's fields: the form the engine makes, a control each. */
static WKDProperty *
WKDFormFields(void)
{
	NSArray *types = @[ @"string", @"long", @"boolean", @"date", @"enum" ];
	/* Short titles: the columns are narrow. */
	WKDColumn *required = WKDTextColumn(@"Req.", 0.55);
	required.kind = WKDPropertyCheck;
	WKDColumn *readonly = WKDTextColumn(@"R/O", 0.55);
	readonly.kind = WKDPropertyCheck;
	WKDColumn *defaultValue = WKDValueColumn(@"Default", 1);
	WKDProperty *table = WKDTable(@"Fields",
		@[ WKDTextColumn(@"Field", 1), WKDTextColumn(@"Label", 1.1),
		   WKDChoiceColumn(@"Type", types, @[ @"Text", @"Number", @"Yes/No", @"Date", @"Choice" ], 0.95),
		   defaultValue, required, readonly ],
		@[ @"", @"", @"string", @"", @"false", @"false" ],
		^NSArray *(NSXMLElement *element) {
			return WKDChildren(WKDFormData(element), WKDCamundaNamespace, @"formField");
		},
		^NSArray *(NSXMLElement *field, NSXMLDocument *document) {
			return @[ WKDAttribute(field, @"id") ?: @"", WKDAttribute(field, @"label") ?: @"",
			          WKDAttribute(field, @"type") ?: @"string", WKDAttribute(field, @"defaultValue") ?: @"",
			          WKDConstraint(field, @"required") != nil ? @"true" : @"false",
			          WKDConstraint(field, @"readonly") != nil ? @"true" : @"false" ];
		},
		^(NSXMLElement *field, NSArray *values, NSXMLDocument *document) {
			WKDSetAttribute(field, @"id", values[0]);
			WKDSetAttribute(field, @"label", [values[1] length] > 0 ? values[1] : nil);
			WKDSetAttribute(field, @"type", values[2]);
			WKDSetAttribute(field, @"defaultValue", [values[3] length] > 0 ? values[3] : nil);
			WKDSetFlagConstraint(document, field, @"required", [values[4] isEqualToString:@"true"]);
			WKDSetFlagConstraint(document, field, @"readonly", [values[5] isEqualToString:@"true"]);
			WKDTidyField(field);
		},
		^NSXMLElement *(NSXMLElement *element, NSXMLDocument *document) {
			NSXMLElement *extensions = WKDEnsureChild(document, element, WKDBpmnNamespace, @"extensionElements");
			return WKDAppendCamunda(document, WKDEnsureChild(document, extensions, WKDCamundaNamespace, @"formData"),
			                        @"formField");
		},
		^(NSXMLElement *element) {
			NSXMLElement *data = WKDFormData(element);
			if (data != nil && !WKDHoldsElements(data) && WKDAttribute(data, @"businessKey") == nil) {
				[data detach];
			}
			WKDTidyExtensions(element, nil);
		});
	table.details = @[ WKDFieldConstraints(), WKDFieldValues(), WKDFieldProperties() ];
	table.placeholder = @"The engine makes the form: a control each, the field's variable bound";
	return table;
}

/* A start form's field whose value is the new instance's business key. */
static WKDProperty *
WKDBusinessKeyField(void)
{
	WKDProperty *property = WKDMake(@"Business key", WKDPropertyText, ^NSString *(NSXMLElement *element, NSXMLDocument *document) {
		return WKDAttribute(WKDFormData(element), @"businessKey");
	}, WKDEditing(@"Business key", ^(NSXMLElement *element, NSXMLDocument *document, NSString *value, WKDEditor *editor) {
		if ([value length] > 0) {
			NSXMLElement *extensions = WKDEnsureChild(document, element, WKDBpmnNamespace, @"extensionElements");
			WKDSetAttribute(WKDEnsureChild(document, extensions, WKDCamundaNamespace, @"formData"), @"businessKey", value);
		} else {
			NSXMLElement *data = WKDFormData(element);
			WKDSetAttribute(data, @"businessKey", nil);
			if (data != nil && !WKDHoldsElements(data)) {
				[data detach];
			}
			WKDTidyExtensions(element, nil);
		}
	}));
	property.placeholder = @"The field that names the instance";
	return property;
}

NSArray<WKDSection *> *
WKDSectionsFor(WKDEditor *editor, NSString *elementId)
{
	NSXMLElement *element = [editor elementWithId:elementId];
	if (element == nil) {
		return @[];
	}
	NSString *type = [element localName];
	if ([type isEqualToString:@"process"]) {
		return [WKDProcessSections() arrayByAddingObject:
			WKDMakeSection(@"Listeners", @[ WKDListeners(NO, @[ @"start", @"end" ]) ])];
	}
	NSMutableArray *sections = [NSMutableArray arrayWithObject:WKDMakeSection(@"General", @[
		WKDIdProperty(), WKDNameProperty(type), WKDDocumentation() ])];
	if ([type isEqualToString:@"sequenceFlow"]) {
		[sections addObjectsFromArray:WKDFlowSections()];
		[sections addObject:WKDMakeSection(@"Listeners", @[ WKDListeners(NO, @[ @"take" ]) ])];
		return sections;
	}
	BOOL flowNode = NO;
	WKDShapeKind kind = WKDKindOfType(type, &flowNode);
	if ([type isEqualToString:@"userTask"]) {
		[sections addObject:WKDMakeSection(@"Assignment", WKDUserTaskProperties())];
		[sections addObject:WKDMakeSection(@"Form", [WKDFormProperties() arrayByAddingObject:WKDFormFields()])];
	} else if ([type isEqualToString:@"serviceTask"] || [type isEqualToString:@"sendTask"]) {
		[sections addObject:WKDMakeSection(@"Implementation",
			[WKDImplementationProperties() arrayByAddingObject:WKDFields(YES)])];
	} else if ([type isEqualToString:@"businessRuleTask"]) {
		[sections addObject:WKDMakeSection(@"Decision", WKDBusinessRuleProperties())];
	} else if ([type isEqualToString:@"scriptTask"]) {
		[sections addObject:WKDMakeSection(@"Script", @[ WKDScriptAction() ])];
	} else if ([type isEqualToString:@"callActivity"]) {
		[sections addObject:WKDMakeSection(@"Called Process", [WKDCallActivityProperties() arrayByAddingObjectsFromArray:
			@[ WKDCallVariables(YES), WKDCallVariables(NO) ]])];
	} else if ([type isEqualToString:@"receiveTask"]) {
		[sections addObject:WKDMakeSection(@"Message", @[ WKDReference(@"Message", nil, @"messageRef", @"message",
		                                                                @"name") ])];
	} else if (WKDIsContainerType(type)) {
		[sections addObject:WKDMakeSection(@"Subprocess", @[ WKDFlag(@"Event subprocess", nil, @"triggeredByEvent", NO) ])];
	}
	if (kind == WKDShapeEvent) {
		NSArray *event = WKDEventProperties(element);
		if ([event count] > 0) {
			[sections addObject:WKDMakeSection(@"Event", event)];
		}
		if ([type isEqualToString:@"startEvent"] && WKDDefinitionOf(element) == nil) {
			[sections addObject:WKDMakeSection(@"Form", [WKDFormProperties() arrayByAddingObjectsFromArray:
				@[ WKDBusinessKeyField(), WKDFormFields() ]])];
		}
	}
	if (kind == WKDShapeActivity) {
		[sections addObject:WKDMakeSection(@"Input/Output", @[ WKDParameters(YES), WKDParameters(NO) ])];
		[sections addObject:WKDMakeSection(@"Multi-instance", WKDLoopProperties())];
	}
	if (flowNode && kind != WKDShapeArtifact) {
		NSMutableArray *listeners = [NSMutableArray arrayWithObject:WKDListeners(NO, @[ @"start", @"end" ])];
		if ([type isEqualToString:@"userTask"]) {
			[listeners addObject:WKDListeners(YES, @[ @"create", @"assignment", @"complete", @"delete" ])];
		}
		[sections addObject:WKDMakeSection(@"Listeners", listeners)];
		[sections addObject:WKDMakeSection(@"Continuation", WKDAsyncProperties(kind == WKDShapeActivity))];
	}
	return sections;
}

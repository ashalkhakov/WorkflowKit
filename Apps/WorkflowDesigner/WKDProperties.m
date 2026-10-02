#import "WKDProperties.h"
#import "WKDDiagram.h"
#import "WKDEditor.h"
#import "WKDXML.h"

typedef NSString *(^WKDRead)(NSXMLElement *element, NSXMLDocument *document);
/* NO, with why, when it cannot be written. */
typedef BOOL (^WKDWrite)(WKDEditor *editor, NSString *elementId, NSString *value, NSString **reason);

@interface WKDProperty ()
@property (nonatomic, copy) WKDRead read;
@property (nonatomic, copy) WKDWrite write;
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
	return @[ key, WKDCamunda(@"Form handler", @"formHandlerClass") ];
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
	return @[ WKDCamunda(@"Decision", @"decisionRef"),
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

NSArray<WKDSection *> *
WKDSectionsFor(WKDEditor *editor, NSString *elementId)
{
	NSXMLElement *element = [editor elementWithId:elementId];
	if (element == nil) {
		return @[];
	}
	NSString *type = [element localName];
	if ([type isEqualToString:@"process"]) {
		return WKDProcessSections();
	}
	NSMutableArray *sections = [NSMutableArray arrayWithObject:WKDMakeSection(@"General", @[
		WKDIdProperty(), WKDNameProperty(type), WKDDocumentation() ])];
	if ([type isEqualToString:@"sequenceFlow"]) {
		[sections addObjectsFromArray:WKDFlowSections()];
		return sections;
	}
	BOOL flowNode = NO;
	WKDShapeKind kind = WKDKindOfType(type, &flowNode);
	if ([type isEqualToString:@"userTask"]) {
		[sections addObject:WKDMakeSection(@"Assignment", WKDUserTaskProperties())];
		[sections addObject:WKDMakeSection(@"Form", WKDFormProperties())];
	} else if ([type isEqualToString:@"serviceTask"] || [type isEqualToString:@"sendTask"]) {
		[sections addObject:WKDMakeSection(@"Implementation", WKDImplementationProperties())];
	} else if ([type isEqualToString:@"businessRuleTask"]) {
		[sections addObject:WKDMakeSection(@"Decision", WKDBusinessRuleProperties())];
	} else if ([type isEqualToString:@"scriptTask"]) {
		[sections addObject:WKDMakeSection(@"Script", @[ WKDScriptAction() ])];
	} else if ([type isEqualToString:@"callActivity"]) {
		[sections addObject:WKDMakeSection(@"Called Process", WKDCallActivityProperties())];
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
			[sections addObject:WKDMakeSection(@"Form", WKDFormProperties())];
		}
	}
	if (kind == WKDShapeActivity) {
		[sections addObject:WKDMakeSection(@"Multi-instance", WKDLoopProperties())];
	}
	if (flowNode && kind != WKDShapeArtifact) {
		[sections addObject:WKDMakeSection(@"Continuation", WKDAsyncProperties(kind == WKDShapeActivity))];
	}
	return sections;
}

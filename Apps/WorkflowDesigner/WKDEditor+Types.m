#import "WKDEditorPriv.h"
#import "WKDXML.h"

@implementation WKDNodeType

+ (instancetype)type:(NSString *)type eventDefinition:(NSString *)eventDefinition title:(NSString *)title
{
	WKDNodeType *nodeType = [[self alloc] init];
	nodeType->_type = [type copy];
	nodeType->_eventDefinition = [eventDefinition length] > 0 ? [eventDefinition copy] : nil;
	nodeType->_title = [title copy];
	return nodeType;
}

- (BOOL)isEqual:(id)other
{
	if (![other isKindOfClass:[WKDNodeType class]]) {
		return NO;
	}
	WKDNodeType *that = other;
	return [_type isEqualToString:that.type]
		&& (_eventDefinition == that.eventDefinition || [_eventDefinition isEqualToString:that.eventDefinition]);
}

- (NSUInteger)hash
{
	return [_type hash] ^ [_eventDefinition hash];
}

- (NSString *)description
{
	return _eventDefinition != nil ? [NSString stringWithFormat:@"%@/%@", _type, _eventDefinition] : _type;
}

@end

/* A type with each of the definitions given: "" for a none event. */
static NSArray<WKDNodeType *> *
WKDEvents(NSString *type, NSString *noun, NSArray<NSString *> *definitions)
{
	NSDictionary *names = @{ @"": @"", @"messageEventDefinition": @"Message ", @"timerEventDefinition": @"Timer ",
	                         @"signalEventDefinition": @"Signal ", @"conditionalEventDefinition": @"Conditional ",
	                         @"errorEventDefinition": @"Error ", @"escalationEventDefinition": @"Escalation ",
	                         @"compensateEventDefinition": @"Compensation ", @"linkEventDefinition": @"Link ",
	                         @"terminateEventDefinition": @"Terminate " };
	NSMutableArray *types = [NSMutableArray array];
	for (NSString *definition in definitions) {
		[types addObject:[WKDNodeType type:type eventDefinition:definition
		                             title:[[names objectForKey:definition] stringByAppendingString:noun]]];
	}
	return types;
}

static NSArray<WKDNodeType *> *
WKDTasks(void)
{
	NSMutableArray *types = [NSMutableArray array];
	for (NSArray *task in @[ @[ @"task", @"Task" ], @[ @"userTask", @"User Task" ], @[ @"serviceTask", @"Service Task" ],
	                         @[ @"scriptTask", @"Script Task" ], @[ @"sendTask", @"Send Task" ],
	                         @[ @"receiveTask", @"Receive Task" ], @[ @"businessRuleTask", @"Business Rule Task" ],
	                         @[ @"manualTask", @"Manual Task" ], @[ @"callActivity", @"Call Activity" ] ]) {
		[types addObject:[WKDNodeType type:task[0] eventDefinition:nil title:task[1]]];
	}
	return types;
}

static NSArray<WKDNodeType *> *
WKDGateways(void)
{
	NSMutableArray *types = [NSMutableArray array];
	for (NSArray *gateway in @[ @[ @"exclusiveGateway", @"Exclusive Gateway" ],
	                            @[ @"parallelGateway", @"Parallel Gateway" ],
	                            @[ @"inclusiveGateway", @"Inclusive Gateway" ],
	                            @[ @"eventBasedGateway", @"Event-based Gateway" ] ]) {
		[types addObject:[WKDNodeType type:gateway[0] eventDefinition:nil title:gateway[1]]];
	}
	return types;
}

/* What only a type has: its attributes (camunda's by local name, qualified
 * as camunda:), and its extension elements. What a type does not list it
 * shares with the others. */
static NSDictionary<NSString *, NSArray<NSString *> *> *
WKDOwnAttributes(void)
{
	NSArray *delegate = @[ @"camunda:class", @"camunda:delegateExpression", @"camunda:expression",
	                       @"camunda:resultVariable", @"camunda:type", @"camunda:topic", @"camunda:taskPriority",
	                       @"implementation" ];
	return @{
		@"userTask": @[ @"camunda:assignee", @"camunda:candidateUsers", @"camunda:candidateGroups", @"camunda:dueDate",
		                @"camunda:followUpDate", @"camunda:priority", @"camunda:formKey", @"camunda:formHandlerClass" ],
		@"serviceTask": delegate,
		@"sendTask": delegate,
		@"businessRuleTask": [delegate arrayByAddingObjectsFromArray:@[
			@"camunda:decisionRef", @"camunda:decisionRefBinding", @"camunda:decisionRefVersion",
			@"camunda:decisionRefVersionTag", @"camunda:decisionRefTenantId", @"camunda:mapDecisionResult" ]],
		@"scriptTask": @[ @"scriptFormat", @"camunda:resultVariable", @"camunda:resource" ],
		@"receiveTask": @[ @"messageRef" ],
		@"callActivity": @[ @"calledElement", @"camunda:calledElementBinding", @"camunda:calledElementVersion",
		                    @"camunda:calledElementVersionTag", @"camunda:calledElementTenantId",
		                    @"camunda:caseRef", @"camunda:variableMappingClass",
		                    @"camunda:variableMappingDelegateExpression" ],
		@"startEvent": @[ @"camunda:formKey", @"camunda:formHandlerClass", @"camunda:initiator", @"isInterrupting" ],
		@"exclusiveGateway": @[ @"default" ],
		@"inclusiveGateway": @[ @"default" ],
	};
}

static NSDictionary<NSString *, NSArray<NSString *> *> *
WKDOwnExtensions(void)
{
	NSArray *fields = @[ @"field", @"connector" ];
	return @{
		@"userTask": @[ @"formData", @"taskListener" ],
		@"startEvent": @[ @"formData" ],
		@"serviceTask": fields,
		@"sendTask": fields,
		@"businessRuleTask": fields,
		@"callActivity": @[ @"in", @"out" ],
	};
}

@implementation WKDEditor (WKDTypes)

- (NSArray<WKDNodeType *> *)typesFor:(NSString *)elementId
{
	WKDShape *shape = [self.diagram shapeWithId:elementId];
	if (shape == nil) {
		return @[];
	}
	switch (shape.kind) {
	case WKDShapeActivity:
		return WKDIsContainerType(shape.type) ? @[] : WKDTasks();
	case WKDShapeGateway:
		return WKDGateways();
	case WKDShapeEvent:
		break;
	default:
		return @[];
	}
	if ([shape.type isEqualToString:@"boundaryEvent"]) {
		return WKDEvents(@"boundaryEvent", @"Boundary Event",
		                 @[ @"messageEventDefinition", @"timerEventDefinition", @"signalEventDefinition",
		                    @"conditionalEventDefinition", @"errorEventDefinition", @"escalationEventDefinition",
		                    @"compensateEventDefinition" ]);
	}
	BOOL incoming = NO, outgoing = NO;
	for (WKDConnection *connection in [self.diagram connectionsOf:shape]) {
		if (connection.isAssociation) {
			continue;
		}
		incoming = incoming || connection.target == shape;
		outgoing = outgoing || connection.source == shape;
	}
	NSMutableArray *types = [NSMutableArray array];
	if (!incoming) {
		NSMutableArray *starts = [@[ @"", @"messageEventDefinition", @"timerEventDefinition", @"signalEventDefinition",
		                            @"conditionalEventDefinition" ] mutableCopy];
		if (shape.parent.eventSubProcess) {
			[starts addObjectsFromArray:@[ @"errorEventDefinition", @"escalationEventDefinition",
			                               @"compensateEventDefinition" ]];
		}
		[types addObjectsFromArray:WKDEvents(@"startEvent", @"Start Event", starts)];
	}
	[types addObjectsFromArray:WKDEvents(@"intermediateCatchEvent", @"Catch Event",
	                                     @[ @"messageEventDefinition", @"timerEventDefinition", @"signalEventDefinition",
	                                        @"conditionalEventDefinition", @"linkEventDefinition" ])];
	[types addObjectsFromArray:WKDEvents(@"intermediateThrowEvent", @"Throw Event",
	                                     @[ @"", @"messageEventDefinition", @"signalEventDefinition",
	                                        @"escalationEventDefinition", @"compensateEventDefinition",
	                                        @"linkEventDefinition" ])];
	if (!outgoing) {
		[types addObjectsFromArray:WKDEvents(@"endEvent", @"End Event",
		                                     @[ @"", @"messageEventDefinition", @"errorEventDefinition",
		                                        @"signalEventDefinition", @"escalationEventDefinition",
		                                        @"compensateEventDefinition", @"terminateEventDefinition" ])];
	}
	return types;
}

/* The attribute's name as the document writes it: camunda:x by the
 * prefix it gives camunda's namespace. */
static void
WKDRemoveOwnAttribute(NSXMLDocument *document, NSXMLElement *element, NSString *name)
{
	if ([name hasPrefix:@"camunda:"]) {
		WKDSetQualifiedAttribute(document, element, WKDCamundaNamespace, [name substringFromIndex:8], nil);
	} else {
		WKDSetAttribute(element, name, nil);
	}
}

- (BOOL)changeType:(NSString *)elementId to:(WKDNodeType *)type error:(NSString **)reason
{
	WKDShape *shape = [self.diagram shapeWithId:elementId];
	WKDNodeType *now = shape != nil ? [WKDNodeType type:shape.type eventDefinition:shape.eventDefinition title:nil] : nil;
	if (shape == nil || type == nil || ![[self typesFor:elementId] containsObject:type]) {
		if (reason != NULL) {
			*reason = shape == nil ? @"There is no such node." : @"The node cannot become that.";
		}
		return NO;
	}
	if ([now isEqual:type]) {
		return YES;
	}
	NSString *oldType = shape.type;
	[self change:@"Change Type" with:^{
		NSXMLDocument *document = self.document;
		NSXMLElement *element = shape.element;
		/* What only the old type had. */
		NSDictionary *attributes = WKDOwnAttributes(), *extensions = WKDOwnExtensions();
		NSArray *kept = [attributes objectForKey:type.type] ?: @[];
		for (NSString *name in [attributes objectForKey:oldType] ?: @[]) {
			if (![kept containsObject:name]) {
				WKDRemoveOwnAttribute(document, element, name);
			}
		}
		NSArray *keptExtensions = [extensions objectForKey:type.type] ?: @[];
		NSXMLElement *extensionElements = WKDChild(element, WKDBpmnNamespace, @"extensionElements");
		for (NSString *local in [extensions objectForKey:oldType] ?: @[]) {
			if (![keptExtensions containsObject:local]) {
				for (NSXMLElement *extension in WKDChildren(extensionElements, WKDCamundaNamespace, local)) {
					[extension detach];
				}
			}
		}
		if (extensionElements != nil && [extensionElements childCount] == 0) {
			[extensionElements detach];
		}
		if ([oldType isEqualToString:@"scriptTask"]) {
			for (NSXMLElement *script in WKDChildren(element, WKDBpmnNamespace, @"script")) {
				[script detach];
			}
		}
		/* The new name, in the namespace and prefix it had. */
		NSString *prefix = [element prefix];
		[element setName:[prefix length] > 0 ? [NSString stringWithFormat:@"%@:%@", prefix, type.type] : type.type];
		/* An event's definition: the old one goes, the new one comes. */
		if (![shape.eventDefinition ?: @"" isEqualToString:type.eventDefinition ?: @""]) {
			for (NSXMLElement *child in WKDChildren(element, WKDBpmnNamespace, nil)) {
				if ([[child localName] hasSuffix:@"EventDefinition"]) {
					[child detach];
				}
			}
			if (type.eventDefinition != nil) {
				NSXMLElement *definition = WKDNewElement(document, WKDBpmnNamespace, type.eventDefinition);
				NSString *local = type.eventDefinition;
				WKDSetAttribute(definition, @"id", [self freshId:[[[local substringToIndex:1] uppercaseString]
				                                                     stringByAppendingString:[local substringFromIndex:1]]]);
				/* After documentation, extensions, incoming and outgoing. */
				NSUInteger index = 0;
				NSArray *children = [element children];
				for (NSUInteger i = 0; i < [children count]; i++) {
					NSXMLNode *child = [children objectAtIndex:i];
					if (WKDIs(child, WKDBpmnNamespace, nil)
					    && [@[ @"documentation", @"extensionElements", @"incoming", @"outgoing", @"property",
					           @"dataOutput", @"dataOutputAssociation", @"outputSet" ] containsObject:[child localName]]) {
						index = i + 1;
					}
				}
				[element insertChild:definition atIndex:index];
			}
		}
	}];
	return YES;
}

@end

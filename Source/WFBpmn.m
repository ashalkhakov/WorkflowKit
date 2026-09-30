#import "WFBpmn.h"
#import "WFFlowElements.h"
#import "WFCondition.h"
#import "WFDuration.h"
#import "WFTimers.h"
#import "WFFeelInternal.h"
#include <math.h>

NSString * const WFBpmnNamespace =
	@"http://www.omg.org/spec/BPMN/20100524/MODEL";
NSString * const WFBpmnDINamespace =
	@"http://www.omg.org/spec/BPMN/20100524/DI";
NSString * const WFBpmnDCNamespace =
	@"http://www.omg.org/spec/DD/20100524/DC";
NSString * const WFBpmnDINodesNamespace =
	@"http://www.omg.org/spec/DD/20100524/DI";
NSString * const WFCamundaNamespace =
	@"http://camunda.org/schema/1.0/bpmn";
NSString * const WFBpmnExtensionNamespace =
	@"https://workflowkit.local/bpmn";
NSString * const WFFeelLanguage =
	@"https://www.omg.org/spec/DMN/20191111/FEEL/";

static NSString * const WFXPathLanguage = @"http://www.w3.org/1999/XPath";

static NSError *
WFBpmnError(NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	return [NSError errorWithDomain:WFErrorDomain
	                           code:WFErrorInvalidBpmn
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

/* An XML id for a name that may contain anything. */
static NSString *
WFXMLId(NSString *prefix, NSString *name)
{
	NSMutableString *id = [NSMutableString stringWithString:prefix];
	NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:
		@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."];
	for (NSUInteger i = 0; i < [name length]; i++) {
		unichar c = [name characterAtIndex:i];
		if (![ok characterIsMember:c]) {
			c = '_';
		}
		[id appendFormat:@"%C", c];
	}
	return id;
}

static NSString *
WFNumber(double value)
{
	if (value == floor(value) && fabs(value) < 1e15) {
		return [NSString stringWithFormat:@"%lld", (long long)value];
	}
	return [NSString stringWithFormat:@"%.3f", value];
}

/* A whole number, possibly negative, and nothing else. */
static BOOL
WFParseWhole(NSString *text, long long *value)
{
	NSScanner *scanner = [NSScanner scannerWithString:
		[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	return [scanner scanLongLong:value] && [scanner isAtEnd];
}

#pragma mark - Writer

static NSString * const WFXSINamespace = @"http://www.w3.org/2001/XMLSchema-instance";

/* An element by its qualified name -- bpmn:task, camunda:in, dc:Bounds --
 * whose prefix the document's root declares. (A URI of its own would have
 * gnustep-base declare the namespace again on every element.) */
static NSXMLElement *
WFElement(NSString *qualifiedName)
{
	return [NSXMLElement elementWithName:qualifiedName];
}

/* Sets the attribute, unless there is no value to give it; a prefixed
 * name's prefix is one the root declares. */
static void
WFSet(NSXMLElement *element, NSString *name, NSString *value)
{
	if (value == nil || [value length] == 0) {
		return;
	}
	[element addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
}

/* <bpmn:name xsi:type="bpmn:tFormalExpression">text</bpmn:name>: an
 * expression as BPMN holds one. */
static NSXMLElement *
WFFormalExpression(NSString *qualifiedName, NSString *text)
{
	NSXMLElement *element = WFElement(qualifiedName);
	WFSet(element, @"xsi:type", @"bpmn:tFormalExpression");
	[element setStringValue:text];
	return element;
}

@interface WFBpmnWriteContext : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *messages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *errors;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *signals;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *escalations;
/* The diagram's plane, which shapes and edges go into as their elements
 * are written. */
@property (nonatomic, strong) NSXMLElement *plane;
@end

@implementation WFBpmnWriteContext
@end

/* The expression Camunda models write to pass the business key on. */
static NSString * const WFBusinessKeyExpression = @"#{execution.processBusinessKey}";

@implementation WFBpmnWriter

/* The id of the top-level element a name or code is written as, made the
 * first time it is asked for. */
+ (NSString *)idFor:(NSString *)name
             prefix:(NSString *)prefix
                 in:(NSMutableDictionary<NSString *, NSString *> *)ids
{
	NSString *id = [ids objectForKey:name];
	if (id == nil) {
		id = WFXMLId(prefix, name);
		[ids setObject:id forKey:name];
	}
	return id;
}

+ (NSXMLDocument *)documentFromDefinition:(WFProcessDefinition *)definition
                                    error:(NSError **)error
{
	if (definition == nil) {
		if (error != NULL) {
			*error = WFBpmnError(@"no definition to export");
		}
		return nil;
	}
	WFBpmnWriteContext *context = [[WFBpmnWriteContext alloc] init];
	context.messages = [NSMutableDictionary dictionary];
	context.errors = [NSMutableDictionary dictionary];
	context.signals = [NSMutableDictionary dictionary];
	context.escalations = [NSMutableDictionary dictionary];
	context.plane = WFElement(@"bpmndi:BPMNPlane");
	WFSet(context.plane, @"id", WFXMLId(@"Plane_", definition.processId));
	WFSet(context.plane, @"bpmnElement", definition.processId);

	NSXMLElement *process = WFElement(@"bpmn:process");
	WFSet(process, @"id", definition.processId);
	if (![definition.name isEqualToString:definition.processId]) {
		WFSet(process, @"name", definition.name);
	}
	WFSet(process, @"isExecutable", @"true");
	WFSet(process, @"camunda:taskPriority", [definition.defaultTaskPriority stringValue]);
	WFSet(process, @"camunda:historyTimeToLive", [definition.historyTimeToLive stringValue]);
	if ([definition.executionListeners count] > 0) {
		NSXMLElement *extensions = WFElement(@"bpmn:extensionElements");
		for (WFListener *listener in definition.executionListeners) {
			[extensions addChild:[self listener:listener named:@"camunda:executionListener"]];
		}
		[process addChild:extensions];
	}
	if (![self appendScope:definition to:process context:context error:error]) {
		return nil;
	}

	NSXMLElement *root = WFElement(@"bpmn:definitions");
	NSDictionary *prefixes = @{ @"bpmn": WFBpmnNamespace, @"bpmndi": WFBpmnDINamespace,
		@"dc": WFBpmnDCNamespace, @"di": WFBpmnDINodesNamespace, @"camunda": WFCamundaNamespace,
		@"wf": WFBpmnExtensionNamespace, @"xsi": WFXSINamespace };
	for (NSString *prefix in @[ @"bpmn", @"bpmndi", @"dc", @"di", @"camunda", @"wf", @"xsi" ]) {
		[root addNamespace:[NSXMLNode namespaceWithName:prefix stringValue:[prefixes objectForKey:prefix]]];
	}
	WFSet(root, @"id", WFXMLId(@"Definitions_", definition.processId));
	WFSet(root, @"targetNamespace", WFBpmnExtensionNamespace);
	WFSet(root, @"expressionLanguage", WFFeelLanguage);
	WFSet(root, @"exporter", @"WorkflowKit");
	/* What events refer to, sorted so the same definition writes the same
	 * document. */
	NSArray *references = @[
		@[ @"bpmn:message", context.messages, @"name" ],
		@[ @"bpmn:signal", context.signals, @"name" ],
		@[ @"bpmn:error", context.errors, @"errorCode" ],
		@[ @"bpmn:escalation", context.escalations, @"escalationCode" ],
	];
	for (NSArray *kind in references) {
		NSDictionary *ids = [kind objectAtIndex:1];
		for (NSString *name in [[ids allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			NSXMLElement *element = WFElement([kind objectAtIndex:0]);
			WFSet(element, @"id", [ids objectForKey:name]);
			WFSet(element, @"name", name);
			if (![[kind objectAtIndex:2] isEqualToString:@"name"]) {
				WFSet(element, [kind objectAtIndex:2], name);
			}
			[root addChild:element];
		}
	}
	[root addChild:process];
	if ([context.plane childCount] > 0) {
		NSXMLElement *diagram = WFElement(@"bpmndi:BPMNDiagram");
		WFSet(diagram, @"id", WFXMLId(@"Diagram_", definition.processId));
		[diagram addChild:context.plane];
		[root addChild:diagram];
	}

	NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:root];
	[document setVersion:@"1.0"];
	[document setCharacterEncoding:@"UTF-8"];
	return document;
}

+ (NSString *)XMLStringFromDefinition:(WFProcessDefinition *)definition
                                error:(NSError **)error
{
	NSXMLDocument *document = [self documentFromDefinition:definition error:error];
	return [document XMLStringWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement];
}

+ (BOOL)appendScope:(WFProcessDefinition *)scope
                 to:(NSXMLElement *)parent
            context:(WFBpmnWriteContext *)context
              error:(NSError **)error
{
	NSArray *nodeIds = [[scope.nodes allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *nodeId in nodeIds) {
		if (![self appendNode:[scope nodeWithId:nodeId] to:parent context:context error:error]) {
			return NO;
		}
	}
	for (NSString *flowId in scope.flowOrder) {
		if (![self appendFlow:[scope flowWithId:flowId] scope:scope to:parent context:context error:error]) {
			return NO;
		}
	}
	/* A compensation boundary event reaches its handler through an
	 * association, not a flow. */
	for (NSString *nodeId in nodeIds) {
		WFFlowNode *node = [scope nodeWithId:nodeId];
		NSString *handler = [node isKindOfClass:[WFEvent class]] ? [(WFEvent *)node compensationHandlerId] : nil;
		if (handler != nil) {
			NSXMLElement *association = WFElement(@"bpmn:association");
			WFSet(association, @"id", WFXMLId(@"Association_", nodeId));
			WFSet(association, @"associationDirection", @"One");
			WFSet(association, @"sourceRef", nodeId);
			WFSet(association, @"targetRef", handler);
			[parent addChild:association];
		}
	}
	return YES;
}

/* A catch's code: nil for one that catches any. */
static NSString *
WFCaughtCode(NSString *code)
{
	return code == nil || [code length] == 0 || [code isEqualToString:@"*"] ? nil : code;
}

+ (NSXMLElement *)eventDefinitionFor:(WFEvent *)event context:(WFBpmnWriteContext *)context
{
	NSXMLElement *definition = nil;
	switch (event.trigger) {
	case WFEventTriggerMessage:
		definition = WFElement(@"bpmn:messageEventDefinition");
		WFSet(definition, @"messageRef",
			[self idFor:event.messageName prefix:@"Message_" in:context.messages]);
		break;
	case WFEventTriggerError: {
		definition = WFElement(@"bpmn:errorEventDefinition");
		NSString *code = WFCaughtCode(event.errorRef);
		if (code != nil) {
			WFSet(definition, @"errorRef", [self idFor:code prefix:@"Error_" in:context.errors]);
		}
		WFSet(definition, @"camunda:errorCodeVariable", event.codeVariable);
		break;
	}
	case WFEventTriggerEscalation: {
		definition = WFElement(@"bpmn:escalationEventDefinition");
		NSString *code = WFCaughtCode(event.escalationCode);
		if (code != nil) {
			WFSet(definition, @"escalationRef", [self idFor:code prefix:@"Escalation_" in:context.escalations]);
		}
		WFSet(definition, @"camunda:escalationCodeVariable", event.codeVariable);
		break;
	}
	case WFEventTriggerCompensation:
		definition = WFElement(@"bpmn:compensateEventDefinition");
		WFSet(definition, @"activityRef", event.activityRef);
		break;
	case WFEventTriggerSignal:
		definition = WFElement(@"bpmn:signalEventDefinition");
		WFSet(definition, @"signalRef", [self idFor:event.signalName prefix:@"Signal_" in:context.signals]);
		break;
	case WFEventTriggerTerminate:
		definition = WFElement(@"bpmn:terminateEventDefinition");
		break;
	case WFEventTriggerTimer: {
		/* A literal as ISO-8601 text, which any modeler reads; a computed
		 * timer as its FEEL. */
		definition = WFElement(@"bpmn:timerEventDefinition");
		NSArray *tags = @[ @"bpmn:timeDate", @"bpmn:timeDuration", @"bpmn:timeCycle" ];
		NSString *text = WFTimerText(event.timer) ?: [event.timer.expression expressionString];
		[definition addChild:WFFormalExpression([tags objectAtIndex:(NSUInteger)event.timer.kind], text)];
		break;
	}
	case WFEventTriggerLink:
		definition = WFElement(@"bpmn:linkEventDefinition");
		WFSet(definition, @"name", event.linkName);
		break;
	case WFEventTriggerConditional: {
		WFEventCondition *condition = event.condition;
		definition = WFElement(@"bpmn:conditionalEventDefinition");
		WFSet(definition, @"camunda:variableName", condition.variableName);
		if ([condition.variableEvents count] > 0) {
			WFSet(definition, @"camunda:variableEvents", [condition.variableEvents componentsJoinedByString:@", "]);
		}
		[definition addChild:WFFormalExpression(@"bpmn:condition", [condition.expression expressionString])];
		break;
	}
	case WFEventTriggerNone:
		break;
	}
	return definition;
}

+ (NSXMLElement *)loopFor:(WFMultiInstance *)loop
{
	NSXMLElement *element = WFElement(@"bpmn:multiInstanceLoopCharacteristics");
	if (loop.isSequential) {
		WFSet(element, @"isSequential", @"true");
	}
	WFSet(element, @"camunda:collection", [loop.collection expressionString]);
	WFSet(element, @"camunda:elementVariable", loop.elementVariable);
	if (loop.loopCardinality != nil) {
		[element addChild:WFFormalExpression(@"bpmn:loopCardinality", [loop.loopCardinality expressionString])];
	}
	if (loop.completionCondition != nil) {
		[element addChild:WFFormalExpression(@"bpmn:completionCondition",
			[loop.completionCondition expressionString])];
	}
	return element;
}

/* A parameter's value into the element: a list as camunda:list, a
 * context as camunda:map, text as itself, anything else as =FEEL. */
+ (void)value:(WFFeelNode *)node into:(NSXMLElement *)element
{
	if (node == nil) {
		return;
	}
	if (node.kind == WFFeelNodeList) {
		NSXMLElement *list = WFElement(@"camunda:list");
		for (WFFeelNode *item in node.children) {
			NSXMLElement *value = WFElement(@"camunda:value");
			[self value:item into:value];
			[list addChild:value];
		}
		[element addChild:list];
		return;
	}
	if (node.kind == WFFeelNodeContext) {
		NSXMLElement *map = WFElement(@"camunda:map");
		for (NSUInteger i = 0; i < [node.children count]; i++) {
			NSXMLElement *entry = WFElement(@"camunda:entry");
			WFSet(entry, @"key", [node.names objectAtIndex:i]);
			[self value:[node.children objectAtIndex:i] into:entry];
			[map addChild:entry];
		}
		[element addChild:map];
		return;
	}
	if (node.kind == WFFeelNodeLiteral && [node.value isKindOfClass:[NSString class]]) {
		[element setStringValue:node.value];
		return;
	}
	[element setStringValue:[@"=" stringByAppendingString:[node description]]];
}

+ (NSXMLElement *)parameter:(WFParameter *)parameter named:(NSString *)name
{
	NSXMLElement *element = WFElement(name);
	WFSet(element, @"name", parameter.name);
	[self value:[parameter.expression root] into:element];
	return element;
}

+ (NSXMLElement *)mapping:(WFVariableMapping *)mapping named:(NSString *)name
{
	NSXMLElement *element = WFElement(name);
	if (mapping.isAllVariables) {
		WFSet(element, @"variables", @"all");
	} else if (mapping.isBusinessKey) {
		WFSet(element, @"businessKey", WFBusinessKeyExpression);
	} else {
		WFSet(element, @"source", mapping.source);
		WFSet(element, @"target", mapping.target);
	}
	return element;
}

/* camunda:class or camunda:delegateExpression, as attributes. */
+ (NSArray *)attributesOf:(WFDelegateReference *)delegate
{
	return delegate.className != nil ? @[ @[ @"camunda:class", delegate.className ] ]
		: @[ @[ @"camunda:delegateExpression", [NSString stringWithFormat:@"${%@}", delegate.delegateName] ] ];
}

/* A delegate's fields: literal text as camunda:string, anything else as
 * camunda:expression holding =FEEL. */
+ (void)appendFieldsOf:(WFDelegateReference *)delegate to:(NSXMLElement *)container
{
	for (WFParameter *field in delegate.fields) {
		NSXMLElement *element = WFElement(@"camunda:field");
		WFSet(element, @"name", field.name);
		WFFeelNode *root = [field.expression root];
		NSXMLElement *value = nil;
		if (root.kind == WFFeelNodeLiteral && [root.value isKindOfClass:[NSString class]]) {
			value = WFElement(@"camunda:string");
			[value setStringValue:root.value];
		} else {
			value = WFElement(@"camunda:expression");
			[value setStringValue:[@"=" stringByAppendingString:[field.expression expressionString]]];
		}
		[element addChild:value];
		[container addChild:element];
	}
}

+ (NSXMLElement *)listener:(WFListener *)listener named:(NSString *)name
{
	NSXMLElement *element = WFElement(name);
	WFSet(element, @"event", [WFListener nameOfEvent:listener.event]);
	for (NSArray *attribute in [self attributesOf:listener.delegate]) {
		WFSet(element, [attribute objectAtIndex:0], [attribute objectAtIndex:1]);
	}
	[self appendFieldsOf:listener.delegate to:element];
	return element;
}

+ (BOOL)appendNode:(WFFlowNode *)node
                to:(NSXMLElement *)parent
           context:(WFBpmnWriteContext *)context
             error:(NSError **)error
{
	NSString *tag = nil;
	/* Attributes in the order they are written. */
	NSMutableArray *attributes = [NSMutableArray array];
	NSXMLElement *eventDefinition = nil;
	WFProcessDefinition *scope = nil;

	if ([node isKindOfClass:[WFEvent class]]) {
		WFEvent *event = (WFEvent *)node;
		switch (event.kind) {
		case WFEventKindStart:
			tag = @"bpmn:startEvent";
			if (!event.isInterrupting) {
				[attributes addObject:@[ @"isInterrupting", @"false" ]];
			}
			break;
		case WFEventKindEnd: tag = @"bpmn:endEvent"; break;
		case WFEventKindIntermediateCatch: tag = @"bpmn:intermediateCatchEvent"; break;
		case WFEventKindIntermediateThrow: tag = @"bpmn:intermediateThrowEvent"; break;
		case WFEventKindBoundary:
			tag = @"bpmn:boundaryEvent";
			[attributes addObject:@[ @"attachedToRef", event.attachedToId ?: @"" ]];
			if (!event.isInterrupting) {
				[attributes addObject:@[ @"cancelActivity", @"false" ]];
			}
			break;
		}
		eventDefinition = [self eventDefinitionFor:event context:context];
	} else if ([node isKindOfClass:[WFTask class]]) {
		WFTask *task = (WFTask *)node;
		if (task.kind == WFTaskKindUser) {
			tag = @"bpmn:userTask";
			NSArray *assignment = @[
				@[ @"camunda:assignee", task.assigneeExpression ?: [NSNull null], @(WFAttributeKindString) ],
				@[ @"camunda:candidateUsers", task.candidateUsers ?: [NSNull null], @(WFAttributeKindList) ],
				@[ @"camunda:candidateGroups", task.candidateGroups ?: [NSNull null], @(WFAttributeKindList) ],
				@[ @"camunda:dueDate", task.dueDate ?: [NSNull null], @(WFAttributeKindDate) ],
				@[ @"camunda:followUpDate", task.followUpDate ?: [NSNull null], @(WFAttributeKindDate) ],
				@[ @"camunda:priority", task.priority ?: [NSNull null], @(WFAttributeKindNumber) ],
			];
			for (NSArray *attribute in assignment) {
				id expression = [attribute objectAtIndex:1];
				if (expression != [NSNull null]) {
					[attributes addObject:@[ [attribute objectAtIndex:0],
						WFAttributeText(expression, (WFAttributeKind)[[attribute objectAtIndex:2] integerValue]) ]];
				}
			}
		} else if (task.kind == WFTaskKindBusinessRule && task.decisionRef != nil) {
			tag = @"bpmn:businessRuleTask";
			[attributes addObject:@[ @"camunda:decisionRef", task.decisionRef ]];
			if (task.decisionBinding == WFCalledElementBindingDeployment) {
				[attributes addObject:@[ @"camunda:decisionRefBinding", @"deployment" ]];
			} else if (task.decisionBinding == WFCalledElementBindingVersion) {
				[attributes addObject:@[ @"camunda:decisionRefBinding", @"version" ]];
				[attributes addObject:@[ @"camunda:decisionRefVersion",
					[NSString stringWithFormat:@"%ld", (long)task.decisionVersion] ]];
			}
			if (task.resultVariable != nil) {
				[attributes addObject:@[ @"camunda:resultVariable", task.resultVariable ]];
			}
			NSArray *mappings = @[ @"resultList", @"singleEntry", @"singleResult", @"collectEntries" ];
			if (task.mapDecisionResult != WFDecisionResultMappingResultList) {
				[attributes addObject:@[ @"camunda:mapDecisionResult",
					[mappings objectAtIndex:(NSUInteger)task.mapDecisionResult] ]];
			}
		} else if (task.delegate != nil) {
			tag = task.kind == WFTaskKindService ? @"bpmn:serviceTask"
				: task.kind == WFTaskKindSend ? @"bpmn:sendTask" : @"bpmn:businessRuleTask";
			[attributes addObjectsFromArray:[self attributesOf:task.delegate]];
		} else if (task.kind == WFTaskKindService || task.kind == WFTaskKindSend
		           || task.kind == WFTaskKindBusinessRule) {
			tag = task.kind == WFTaskKindService ? @"bpmn:serviceTask"
				: task.kind == WFTaskKindSend ? @"bpmn:sendTask" : @"bpmn:businessRuleTask";
			[attributes addObject:@[ @"camunda:type", @"external" ]];
			[attributes addObject:@[ @"camunda:topic", task.actionKey ?: @"" ]];
		} else if (task.kind == WFTaskKindReceive) {
			tag = @"bpmn:receiveTask";
			[attributes addObject:@[ @"messageRef",
				[self idFor:task.messageName prefix:@"Message_" in:context.messages] ]];
		} else if (task.kind == WFTaskKindManual) {
			tag = @"bpmn:manualTask";
		} else if (task.kind == WFTaskKindNone) {
			tag = @"bpmn:task";
		} else {
			/* Camunda script tasks run script text; ours run an action by
			 * key, which only our own attribute can say. */
			tag = @"bpmn:scriptTask";
			[attributes addObject:@[ @"wf:action", task.actionKey ?: @"" ]];
		}
	} else if ([node isKindOfClass:[WFGateway class]]) {
		WFGateway *gateway = (WFGateway *)node;
		switch (gateway.kind) {
		case WFGatewayKindExclusive: tag = @"bpmn:exclusiveGateway"; break;
		case WFGatewayKindInclusive: tag = @"bpmn:inclusiveGateway"; break;
		case WFGatewayKindParallel: tag = @"bpmn:parallelGateway"; break;
		case WFGatewayKindEventBased: tag = @"bpmn:eventBasedGateway"; break;
		}
		[attributes addObject:@[ @"default", gateway.defaultFlowId ?: @"" ]];
	} else if ([node isKindOfClass:[WFCallActivity class]]) {
		WFCallActivity *call = (WFCallActivity *)node;
		tag = @"bpmn:callActivity";
		[attributes addObject:@[ @"calledElement", call.calledElement ?: @"" ]];
		if (call.binding == WFCalledElementBindingDeployment) {
			[attributes addObject:@[ @"camunda:calledElementBinding", @"deployment" ]];
		} else if (call.binding == WFCalledElementBindingVersion) {
			[attributes addObject:@[ @"camunda:calledElementBinding", @"version" ]];
			[attributes addObject:@[ @"camunda:calledElementVersion",
				[NSString stringWithFormat:@"%ld", (long)call.calledElementVersion] ]];
		}
	} else if ([node isKindOfClass:[WFSubProcess class]]) {
		tag = @"bpmn:subProcess";
		if ([(WFSubProcess *)node isTriggeredByEvent]) {
			[attributes addObject:@[ @"triggeredByEvent", @"true" ]];
		}
		/* Its flow elements go in after the wiring, which BPMN puts first. */
		scope = [(WFSubProcess *)node innerDefinition];
	} else {
		if (error != NULL) {
			*error = WFBpmnError(@"%@ cannot be written as BPMN", node.elementId);
		}
		return NO;
	}

	NSXMLElement *element = WFElement(tag);
	WFSet(element, @"id", node.elementId);
	if (node.name != nil && ![node.name isEqualToString:node.elementId]) {
		WFSet(element, @"name", node.name);
	}
	for (NSArray *attribute in attributes) {
		WFSet(element, [attribute objectAtIndex:0], [attribute objectAtIndex:1]);
	}
	if (node.isForCompensation) {
		WFSet(element, @"isForCompensation", @"true");
	}
	if (node.isAsyncBefore) {
		WFSet(element, @"camunda:asyncBefore", @"true");
	}
	if (node.isAsyncAfter) {
		WFSet(element, @"camunda:asyncAfter", @"true");
	}
	if (!node.isExclusive) {
		WFSet(element, @"camunda:exclusive", @"false");
	}
	WFSet(element, @"camunda:taskPriority", [node.taskPriority stringValue]);

	/* BPMN puts extension elements, then incoming and outgoing, then an
	 * activity's loop characteristics or an event's definition, before
	 * everything else -- a subprocess's flow elements included. */
	NSXMLElement *extensions = WFElement(@"bpmn:extensionElements");
	if (node.retryTimeCycle != nil) {
		NSXMLElement *cycle = WFElement(@"camunda:failedJobRetryTimeCycle");
		[cycle setStringValue:node.retryTimeCycle];
		[extensions addChild:cycle];
	}
	if ([node.inputParameters count] > 0 || [node.outputParameters count] > 0) {
		NSXMLElement *inputOutput = WFElement(@"camunda:inputOutput");
		for (WFParameter *parameter in node.inputParameters) {
			[inputOutput addChild:[self parameter:parameter named:@"camunda:inputParameter"]];
		}
		for (WFParameter *parameter in node.outputParameters) {
			[inputOutput addChild:[self parameter:parameter named:@"camunda:outputParameter"]];
		}
		[extensions addChild:inputOutput];
	}
	if ([node isKindOfClass:[WFTask class]]) {
		WFTask *task = (WFTask *)node;
		[self appendFieldsOf:task.delegate to:extensions];
		for (WFListener *listener in task.taskListeners) {
			[extensions addChild:[self listener:listener named:@"camunda:taskListener"]];
		}
	}
	for (WFListener *listener in node.executionListeners) {
		[extensions addChild:[self listener:listener named:@"camunda:executionListener"]];
	}
	if ([node isKindOfClass:[WFCallActivity class]]) {
		WFCallActivity *call = (WFCallActivity *)node;
		for (WFVariableMapping *mapping in call.inputs) {
			[extensions addChild:[self mapping:mapping named:@"camunda:in"]];
		}
		for (WFVariableMapping *mapping in call.outputs) {
			[extensions addChild:[self mapping:mapping named:@"camunda:out"]];
		}
	}
	if ([extensions childCount] > 0) {
		[element addChild:extensions];
	}
	for (NSString *flowId in node.incomingFlowIds) {
		NSXMLElement *incoming = WFElement(@"bpmn:incoming");
		[incoming setStringValue:flowId];
		[element addChild:incoming];
	}
	for (NSString *flowId in node.outgoingFlowIds) {
		NSXMLElement *outgoing = WFElement(@"bpmn:outgoing");
		[outgoing setStringValue:flowId];
		[element addChild:outgoing];
	}
	if (node.multiInstance != nil) {
		[element addChild:[self loopFor:node.multiInstance]];
	}
	if (eventDefinition != nil) {
		[element addChild:eventDefinition];
	}
	[parent addChild:element];
	if (scope != nil && ![self appendScope:scope to:element context:context error:error]) {
		return NO;
	}

	if (node.boundsWidth > 0 || node.boundsHeight > 0) {
		NSXMLElement *shape = WFElement(@"bpmndi:BPMNShape");
		WFSet(shape, @"id", WFXMLId(@"Shape_", node.elementId));
		WFSet(shape, @"bpmnElement", node.elementId);
		if ([node isKindOfClass:[WFSubProcess class]]) {
			WFSet(shape, @"isExpanded", @"true");
		}
		NSXMLElement *bounds = WFElement(@"dc:Bounds");
		WFSet(bounds, @"x", WFNumber(node.boundsX));
		WFSet(bounds, @"y", WFNumber(node.boundsY));
		WFSet(bounds, @"width", WFNumber(node.boundsWidth));
		WFSet(bounds, @"height", WFNumber(node.boundsHeight));
		[shape addChild:bounds];
		[context.plane addChild:shape];
	}
	return YES;
}

+ (BOOL)appendFlow:(WFSequenceFlow *)flow
             scope:(WFProcessDefinition *)scope
                to:(NSXMLElement *)parent
           context:(WFBpmnWriteContext *)context
             error:(NSError **)error
{
	NSXMLElement *element = WFElement(@"bpmn:sequenceFlow");
	WFSet(element, @"id", flow.elementId);
	if (flow.name != nil && ![flow.name isEqualToString:flow.elementId]) {
		WFSet(element, @"name", flow.name);
	}
	WFSet(element, @"sourceRef", flow.sourceId);
	WFSet(element, @"targetRef", flow.targetId);
	if ([flow.listeners count] > 0) {
		NSXMLElement *extensions = WFElement(@"bpmn:extensionElements");
		for (WFListener *listener in flow.listeners) {
			[extensions addChild:[self listener:listener named:@"camunda:executionListener"]];
		}
		[element addChild:extensions];
	}
	id condition = flow.condition;
	if (condition != nil) {
		if (![condition conformsToProtocol:@protocol(WFCondition)]) {
			if (error != NULL) {
				*error = WFBpmnError(@"the condition on %@ cannot be written as BPMN", flow.elementId);
			}
			return NO;
		}
		[element addChild:WFFormalExpression(@"bpmn:conditionExpression", [condition expressionString])];
	}
	[parent addChild:element];

	/* A straight edge between the shapes' centres: the diagram needs an
	 * edge to show the flow at all, and we keep no waypoints. */
	WFFlowNode *source = [scope nodeWithId:flow.sourceId];
	WFFlowNode *target = [scope nodeWithId:flow.targetId];
	if (source.boundsWidth > 0 && target.boundsWidth > 0) {
		NSXMLElement *edge = WFElement(@"bpmndi:BPMNEdge");
		WFSet(edge, @"id", WFXMLId(@"Edge_", flow.elementId));
		WFSet(edge, @"bpmnElement", flow.elementId);
		for (WFFlowNode *end in @[ source, target ]) {
			NSXMLElement *waypoint = WFElement(@"di:waypoint");
			WFSet(waypoint, @"x", WFNumber(end.boundsX + end.boundsWidth / 2));
			WFSet(waypoint, @"y", WFNumber(end.boundsY + end.boundsHeight / 2));
			[edge addChild:waypoint];
		}
		[context.plane addChild:edge];
	}
	return YES;
}

+ (BOOL)writeDefinition:(WFProcessDefinition *)definition
                  toURL:(NSURL *)url
                  error:(NSError **)error
{
	NSXMLDocument *document = [self documentFromDefinition:definition error:error];
	if (document == nil) {
		return NO;
	}
	return [[document XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement]
		writeToURL:url options:NSDataWritingAtomic
	                                                                 error:error];
}

@end

#pragma mark - Reader

/* Children of a process or subprocess that are not flow elements of it. */
static NSSet *
WFIgnoredElements(void)
{
	static NSSet *names = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		names = [NSSet setWithObjects:@"documentation", @"extensionElements",
			@"laneSet", @"textAnnotation", @"association", @"group",
			@"dataObject", @"dataObjectReference", @"dataStoreReference",
			@"property", @"ioSpecification", @"dataInputAssociation",
			@"dataOutputAssociation", @"incoming", @"outgoing",
			/* A subprocess's own loop, read with the subprocess. */
			@"multiInstanceLoopCharacteristics", @"standardLoopCharacteristics", nil];
	});
	return names;
}

@interface WFBpmnReadContext : NSObject
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *messages;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *errors;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *signals;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *escalations;
@property (nonatomic, strong) NSDictionary<NSString *, NSXMLElement *> *shapes;
@property (nonatomic, copy) NSString *expressionLanguage;
@property (nonatomic, strong) NSError *error;
/* Reading an event subprocess's own elements, whose start event may be an
 * error start. */
@property (nonatomic) BOOL inEventSubProcess;
@end

@implementation WFBpmnReadContext
@end

@implementation WFBpmnReader

+ (NSArray<NSXMLElement *> *)children:(NSXMLElement *)element
                                   of:(NSString *)namespace
{
	NSMutableArray *result = [NSMutableArray array];
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind
		    && [[child URI] isEqualToString:namespace]) {
			[result addObject:child];
		}
	}
	return result;
}

+ (NSXMLElement *)child:(NSXMLElement *)element named:(NSString *)name
{
	for (NSXMLElement *child in [self children:element of:WFBpmnNamespace]) {
		if ([[child localName] isEqualToString:name]) {
			return child;
		}
	}
	return nil;
}

+ (NSString *)attr:(NSString *)name of:(NSXMLElement *)element
{
	return [[element attributeForName:name] stringValue];
}

+ (NSString *)attr:(NSString *)name namespace:(NSString *)namespace of:(NSXMLElement *)element
{
	return [[element attributeForLocalName:name URI:namespace] stringValue];
}

+ (NSString *)trimmed:(NSString *)text
{
	return [text stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (void)collectShapes:(NSXMLElement *)element into:(NSMutableDictionary *)shapes
{
	for (NSXMLNode *child in [element children]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *e = (NSXMLElement *)child;
		if ([[e URI] isEqualToString:WFBpmnDINamespace]
		    && [[e localName] isEqualToString:@"BPMNShape"]) {
			NSString *ref = [self attr:@"bpmnElement" of:e];
			for (NSXMLElement *bounds in [self children:e of:WFBpmnDCNamespace]) {
				if (ref != nil && [[bounds localName] isEqualToString:@"Bounds"]) {
					[shapes setObject:bounds forKey:ref];
				}
			}
		}
		[self collectShapes:e into:shapes];
	}
}

+ (NSArray<WFProcessDefinition *> *)definitionsFromData:(NSData *)data
                                                  error:(NSError **)error
{
	NSError *xmlError = nil;
	NSXMLDocument *document = data == nil ? nil
		: [[NSXMLDocument alloc] initWithData:data options:0 error:&xmlError];
	NSXMLElement *root = [document rootElement];
	if (root == nil) {
		if (error != NULL) {
			*error = xmlError ?: WFBpmnError(@"empty BPMN document");
		}
		return nil;
	}
	if (![[root URI] isEqualToString:WFBpmnNamespace]
	    || ![[root localName] isEqualToString:@"definitions"]) {
		if (error != NULL) {
			*error = WFBpmnError(@"not a BPMN 2.0 document: the root is %@",
				[root name]);
		}
		return nil;
	}

	WFBpmnReadContext *context = [[WFBpmnReadContext alloc] init];
	context.expressionLanguage = [self attr:@"expressionLanguage" of:root];
	NSMutableDictionary *messages = [NSMutableDictionary dictionary];
	NSMutableDictionary *errors = [NSMutableDictionary dictionary];
	NSMutableDictionary *signals = [NSMutableDictionary dictionary];
	NSMutableDictionary *escalations = [NSMutableDictionary dictionary];
	NSMutableArray *processes = [NSMutableArray array];
	for (NSXMLElement *element in [self children:root of:WFBpmnNamespace]) {
		NSString *name = [element localName];
		NSString *elementId = [self attr:@"id" of:element];
		if ([name isEqualToString:@"message"] && elementId != nil) {
			[messages setObject:[self attr:@"name" of:element] ?: elementId
			             forKey:elementId];
		} else if ([name isEqualToString:@"signal"] && elementId != nil) {
			[signals setObject:[self attr:@"name" of:element] ?: elementId forKey:elementId];
		} else if ([name isEqualToString:@"escalation"] && elementId != nil) {
			[escalations setObject:[self attr:@"escalationCode" of:element]
				?: [self attr:@"name" of:element] ?: elementId
			                forKey:elementId];
		} else if ([name isEqualToString:@"error"] && elementId != nil) {
			[errors setObject:[self attr:@"errorCode" of:element]
				?: [self attr:@"name" of:element] ?: elementId
			           forKey:elementId];
		} else if ([name isEqualToString:@"process"]
		           && [[self attr:@"isExecutable" of:element] isEqualToString:@"true"]) {
			[processes addObject:element];
		}
	}
	context.messages = messages;
	context.errors = errors;
	context.signals = signals;
	context.escalations = escalations;
	NSMutableDictionary *shapes = [NSMutableDictionary dictionary];
	[self collectShapes:root into:shapes];
	context.shapes = shapes;

	if ([processes count] == 0) {
		if (error != NULL) {
			*error = WFBpmnError(@"no executable process (isExecutable=\"true\")");
		}
		return nil;
	}
	NSMutableArray *definitions = [NSMutableArray array];
	for (NSXMLElement *process in processes) {
		NSString *processId = [self attr:@"id" of:process];
		if (processId == nil) {
			if (error != NULL) {
				*error = WFBpmnError(@"a process has no id");
			}
			return nil;
		}
		WFDefinitionBuilder *builder =
			[WFDefinitionBuilder process:processId
			                        name:[self attr:@"name" of:process] ?: processId];
		NSString *priority = [self attr:@"taskPriority" namespace:WFCamundaNamespace of:process];
		if (priority != nil) {
			long long value = 0;
			if (!WFParseWhole(priority, &value)) {
				[self fail:context error:WFBpmnError(
					@"%@: camunda:taskPriority \"%@\" is not a whole number; expressions are not supported yet",
					processId, priority)];
			}
			[builder setDefaultTaskPriority:(NSInteger)value];
		}
		NSString *ttl = [self attr:@"historyTimeToLive" namespace:WFCamundaNamespace of:process];
		if ([ttl length] > 0) {
			long long days = 0;
			if (!WFParseWhole(ttl, &days)) {
				NSTimeInterval seconds = WFParseISODuration(ttl);
				days = seconds >= 0 && fmod(seconds, 86400) == 0 ? (long long)(seconds / 86400) : -1;
			}
			if (days < 0) {
				[self fail:context error:WFBpmnError(
					@"%@: camunda:historyTimeToLive \"%@\" is neither days nor an ISO-8601 duration in whole days",
					processId, ttl)];
			}
			[builder setHistoryTimeToLive:(NSInteger)days];
		}
		[self readScope:process into:builder context:context];
		[self readListenersOf:process id:processId into:builder context:context];
		if (context.error != nil) {
			if (error != NULL) {
				*error = context.error;
			}
			return nil;
		}
		WFProcessDefinition *definition = [builder build:error];
		if (definition == nil) {
			return nil;
		}
		[definitions addObject:definition];
	}
	return definitions;
}

+ (void)fail:(WFBpmnReadContext *)context error:(NSError *)error
{
	if (context.error == nil) {
		context.error = error;
	}
}

+ (void)readScope:(NSXMLElement *)scope
             into:(WFDefinitionBuilder *)builder
          context:(WFBpmnReadContext *)context
{
	NSMutableArray *associations = [NSMutableArray array];
	[self readElementsOf:scope into:builder associations:associations context:context];
	for (NSXMLElement *association in associations) {
		NSString *source = [self attr:@"sourceRef" of:association];
		NSString *target = [self attr:@"targetRef" of:association];
		if (source != nil && target != nil) {
			[builder setCompensationHandler:target forBoundary:source];
		}
	}
}

+ (void)readElementsOf:(NSXMLElement *)scope
                  into:(WFDefinitionBuilder *)builder
          associations:(NSMutableArray *)associations
               context:(WFBpmnReadContext *)context
{
	for (NSXMLElement *element in [self children:scope of:WFBpmnNamespace]) {
		if (context.error != nil) {
			return;
		}
		NSString *name = [element localName];
		if ([name isEqualToString:@"association"]) {
			/* A compensation boundary event's link to its handler; any
			 * other association is an annotation's, and ignored. */
			[associations addObject:element];
			continue;
		}
		if ([WFIgnoredElements() containsObject:name]) {
			continue;
		}
		NSString *elementId = [self attr:@"id" of:element];
		if (elementId == nil) {
			[self fail:context error:WFBpmnError(@"a %@ has no id", name)];
			return;
		}
		if ([name isEqualToString:@"sequenceFlow"]) {
			[self readFlow:element id:elementId into:builder context:context];
			continue;
		}
		if ([self child:element named:@"standardLoopCharacteristics"] != nil) {
			[self fail:context error:WFBpmnError(
				@"%@: standard loops are not supported; model the loop with a gateway", elementId)];
			return;
		}
		if (![self readNode:element name:name id:elementId into:builder context:context]) {
			return;
		}
		NSXMLElement *loop = [self child:element named:@"multiInstanceLoopCharacteristics"];
		if (loop != nil && ![self readLoop:loop id:elementId into:builder context:context]) {
			return;
		}
		NSString *label = [self attr:@"name" of:element];
		if (label != nil) {
			[builder setName:label forElement:elementId];
		}
		if ([[self attr:@"isForCompensation" of:element] isEqualToString:@"true"]) {
			[builder setForCompensation:YES forElement:elementId];
		}
		for (NSString *definitionName in @[ @"errorEventDefinition", @"escalationEventDefinition" ]) {
			NSXMLElement *definition = [self child:element named:definitionName];
			NSString *variable = [self attr:[definitionName hasPrefix:@"error"] ? @"errorCodeVariable"
				: @"escalationCodeVariable" namespace:WFCamundaNamespace of:definition];
			if (variable != nil) {
				[builder setCodeVariable:variable forElement:elementId];
			}
		}
		[self readJobSettings:element id:elementId into:builder context:context];
		NSXMLElement *bounds = [context.shapes objectForKey:elementId];
		if (bounds != nil) {
			[builder setBoundsFor:elementId
			                    x:[[self attr:@"x" of:bounds] doubleValue]
			                    y:[[self attr:@"y" of:bounds] doubleValue]
			                width:[[self attr:@"width" of:bounds] doubleValue]
			               height:[[self attr:@"height" of:bounds] doubleValue]];
		}
	}
}

+ (void)readJobSettings:(NSXMLElement *)element
                     id:(NSString *)elementId
                   into:(WFDefinitionBuilder *)builder
                context:(WFBpmnReadContext *)context
{
	BOOL before = [[self attr:@"asyncBefore" namespace:WFCamundaNamespace of:element]
		isEqualToString:@"true"];
	BOOL after = [[self attr:@"asyncAfter" namespace:WFCamundaNamespace of:element]
		isEqualToString:@"true"];
	NSString *exclusive = [self attr:@"exclusive" namespace:WFCamundaNamespace of:element];
	if (before || after || exclusive != nil) {
		[builder setAsyncBefore:before
		             asyncAfter:after
		              exclusive:![exclusive isEqualToString:@"false"]
		             forElement:elementId];
	}
	NSString *priority = [self attr:@"taskPriority" namespace:WFCamundaNamespace of:element];
	if (priority != nil) {
		long long value = 0;
		if (WFParseWhole(priority, &value)) {
			[builder setTaskPriority:(NSInteger)value forElement:elementId];
		} else {
			[self fail:context error:WFBpmnError(
				@"%@: camunda:taskPriority \"%@\" is not a whole number; expressions are not supported yet",
				elementId, priority)];
		}
	}
	NSXMLElement *extensions = [self child:element named:@"extensionElements"];
	for (NSXMLElement *extension in [self children:extensions of:WFCamundaNamespace]) {
		if ([[extension localName] isEqualToString:@"inputOutput"]) {
			[self readInputOutput:extension id:elementId into:builder context:context];
		}
		if ([[extension localName] isEqualToString:@"failedJobRetryTimeCycle"]) {
			NSString *cycle = [self trimmed:[extension stringValue]];
			if ([cycle length] > 0) {
				[builder setRetryTimeCycle:cycle forElement:elementId];
			}
		}
	}
	[self readListenersOf:element id:elementId into:builder context:context];
}

/* camunda:executionListener and camunda:taskListener in the element's
 * extensionElements. */
+ (void)readListenersOf:(NSXMLElement *)element
                     id:(NSString *)elementId
                   into:(WFDefinitionBuilder *)builder
                context:(WFBpmnReadContext *)context
{
	NSDictionary *events = @{ @"start": @(WFListenerEventStart), @"end": @(WFListenerEventEnd),
		@"take": @(WFListenerEventTake), @"create": @(WFListenerEventCreate),
		@"assignment": @(WFListenerEventAssignment), @"complete": @(WFListenerEventComplete),
		@"delete": @(WFListenerEventDelete) };
	NSXMLElement *extensions = [self child:element named:@"extensionElements"];
	for (NSXMLElement *extension in [self children:extensions of:WFCamundaNamespace]) {
		NSString *kind = [extension localName];
		if (![kind isEqualToString:@"executionListener"] && ![kind isEqualToString:@"taskListener"]) {
			continue;
		}
		BOOL isFlow = [[element localName] isEqualToString:@"sequenceFlow"];
		NSString *event = [self attr:@"event" of:extension] ?: (isFlow ? @"take" : nil);
		NSNumber *value = [events objectForKey:event ?: @""];
		BOOL taskEvent = [value integerValue] >= WFListenerEventCreate;
		if (value == nil || taskEvent != [kind isEqualToString:@"taskListener"]) {
			[self fail:context error:WFBpmnError(@"%@: camunda:%@ event \"%@\" is not supported",
				elementId, kind, event ?: @"")];
			return;
		}
		WFDelegateReference *delegate = [self delegateOf:extension fieldsIn:extension id:elementId context:context];
		if (delegate == nil) {
			if (context.error == nil) {
				[self fail:context error:WFBpmnError(
					@"%@: a camunda:%@ needs camunda:class or camunda:delegateExpression", elementId, kind)];
			}
			return;
		}
		[builder addListener:[WFListener listenerOn:(WFListenerEvent)[value integerValue] delegate:delegate]
		          forElement:elementId];
	}
}

/* camunda:class or camunda:delegateExpression="${name}" on the element,
 * with the camunda:field elements in container; nil when it has neither,
 * and nil with the read failed for what the engine does not take. */
+ (WFDelegateReference *)delegateOf:(NSXMLElement *)element
                           fieldsIn:(NSXMLElement *)container
                                 id:(NSString *)elementId
                            context:(WFBpmnReadContext *)context
{
	for (NSString *unsupported in @[ @"expression" ]) {
		if ([self attr:unsupported namespace:WFCamundaNamespace of:element] != nil
		    || [self attr:unsupported of:element] != nil) {
			[self fail:context error:WFBpmnError(
				@"%@: camunda:expression calls a method, which the engine cannot; use camunda:delegateExpression",
				elementId)];
			return nil;
		}
	}
	for (NSXMLElement *child in [self children:element of:WFCamundaNamespace]) {
		if ([[child localName] isEqualToString:@"script"]) {
			[self fail:context error:WFBpmnError(@"%@: script listeners are not supported", elementId)];
			return nil;
		}
	}
	NSString *className = [self attr:@"class" namespace:WFCamundaNamespace of:element]
		?: [self attr:@"class" of:element];
	NSString *expression = [self attr:@"delegateExpression" namespace:WFCamundaNamespace of:element]
		?: [self attr:@"delegateExpression" of:element];
	if (className == nil && expression == nil) {
		return nil;
	}
	NSString *delegateName = nil;
	if (expression != nil) {
		NSString *text = [self trimmed:expression];
		if (([text hasPrefix:@"${"] || [text hasPrefix:@"#{"]) && [text hasSuffix:@"}"]) {
			text = [self trimmed:[text substringWithRange:NSMakeRange(2, [text length] - 3)]];
		}
		NSCharacterSet *name = [NSCharacterSet characterSetWithCharactersInString:
			@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_."];
		if ([text length] == 0 || [[text stringByTrimmingCharactersInSet:name] length] > 0) {
			[self fail:context error:WFBpmnError(
				@"%@: camunda:delegateExpression \"%@\" is not a name; register the delegate under a name",
				elementId, expression)];
			return nil;
		}
		delegateName = text;
	}
	NSMutableArray *fields = [NSMutableArray array];
	for (NSXMLElement *field in [self children:container of:WFCamundaNamespace]) {
		if (![[field localName] isEqualToString:@"field"]) {
			continue;
		}
		NSString *fieldName = [self attr:@"name" of:field];
		NSString *literal = [self attr:@"stringValue" of:field];
		NSString *source = [self attr:@"expression" of:field];
		for (NSXMLElement *child in [self children:field of:WFCamundaNamespace]) {
			if ([[child localName] isEqualToString:@"string"]) {
				literal = [child stringValue];
			} else if ([[child localName] isEqualToString:@"expression"]) {
				source = [child stringValue];
			}
		}
		WFFeelExpression *value = nil;
		if (source != nil) {
			value = [self expressionFrom:source language:nil
			                        what:[NSString stringWithFormat:@"%@: field %@", elementId, fieldName]
			                     context:context];
		} else {
			value = [WFFeelExpression expressionWithString:WFFeelLiteralText(literal ?: @"") error:NULL];
		}
		if (fieldName == nil || value == nil) {
			if (context.error == nil) {
				[self fail:context error:WFBpmnError(@"%@: a camunda:field needs a name and a value", elementId)];
			}
			return nil;
		}
		[fields addObject:[WFParameter parameter:fieldName expression:value]];
	}
	return className != nil ? [WFDelegateReference referenceToClass:className fields:fields]
		: [WFDelegateReference referenceToDelegate:delegateName fields:fields];
}

/* A parameter's value as FEEL text: a camunda:list or camunda:map, or the
 * element's text (literal, ${...} or =FEEL); nil for none, and nil with
 * the read failed for one the engine does not take. */
+ (NSString *)valueOf:(NSXMLElement *)element
                   id:(NSString *)elementId
              context:(WFBpmnReadContext *)context
               isNull:(BOOL *)isNull
{
	*isNull = NO;
	NSArray *children = [self children:element of:WFCamundaNamespace];
	NSXMLElement *structured = [children firstObject];
	if (structured != nil && [[structured localName] isEqualToString:@"list"]) {
		NSMutableArray *items = [NSMutableArray array];
		for (NSXMLElement *value in [self children:structured of:WFCamundaNamespace]) {
			BOOL none = NO;
			NSString *item = [self valueOf:value id:elementId context:context isNull:&none];
			if (item == nil && !none) {
				return nil;
			}
			[items addObject:none ? @"null" : item];
		}
		return [NSString stringWithFormat:@"[%@]", [items componentsJoinedByString:@", "]];
	}
	if (structured != nil && [[structured localName] isEqualToString:@"map"]) {
		NSMutableArray *entries = [NSMutableArray array];
		for (NSXMLElement *entry in [self children:structured of:WFCamundaNamespace]) {
			BOOL none = NO;
			NSString *value = [self valueOf:entry id:elementId context:context isNull:&none];
			if (value == nil && !none) {
				return nil;
			}
			[entries addObject:[NSString stringWithFormat:@"%@: %@",
				WFFeelLiteralText([self attr:@"key" of:entry] ?: @""), none ? @"null" : value]];
		}
		return [NSString stringWithFormat:@"{%@}", [entries componentsJoinedByString:@", "]];
	}
	if (structured != nil) {
		[self fail:context error:WFBpmnError(@"%@: camunda:%@ parameters are not supported; use an expression",
			elementId, [structured localName])];
		return nil;
	}
	NSString *text = [self trimmed:[element stringValue]];
	if ([text length] == 0) {
		*isNull = YES;
		return nil;
	}
	NSError *error = nil;
	WFFeelExpression *expression = WFAttributeExpression(text, WFAttributeKindString, &error);
	if (expression == nil) {
		[self fail:context error:WFBpmnError(@"%@: %@", elementId, [error localizedDescription])];
		return nil;
	}
	return [expression expressionString];
}

+ (void)readInputOutput:(NSXMLElement *)inputOutput
                     id:(NSString *)elementId
                   into:(WFDefinitionBuilder *)builder
                context:(WFBpmnReadContext *)context
{
	for (NSXMLElement *parameter in [self children:inputOutput of:WFCamundaNamespace]) {
		BOOL input = [[parameter localName] isEqualToString:@"inputParameter"];
		if (!input && ![[parameter localName] isEqualToString:@"outputParameter"]) {
			continue;
		}
		NSString *name = [self attr:@"name" of:parameter];
		BOOL none = NO;
		NSString *feel = [self valueOf:parameter id:elementId context:context isNull:&none];
		if (context.error != nil) {
			return;
		}
		NSError *error = nil;
		WFFeelExpression *expression = none ? nil : [WFFeelExpression expressionWithString:feel error:&error];
		if (!none && expression == nil) {
			[self fail:context error:WFBpmnError(@"%@: parameter %@: %@", elementId, name,
				[error localizedDescription])];
			return;
		}
		if (input) {
			[builder addInputParameter:name expression:expression forElement:elementId];
		} else {
			[builder addOutputParameter:name expression:expression forElement:elementId];
		}
	}
}

/* The one event definition an event carries: nil for a none event. Sets
 * *unsupported to the name of one the engine does not run. */
+ (NSXMLElement *)eventDefinitionOf:(NSXMLElement *)event
                        unsupported:(NSString **)unsupported
{
	NSXMLElement *found = nil;
	for (NSXMLElement *child in [self children:event of:WFBpmnNamespace]) {
		NSString *name = [child localName];
		if (![name hasSuffix:@"EventDefinition"]) {
			continue;
		}
		if (found != nil) {
			*unsupported = @"multiple event definitions";
			return nil;
		}
		if (![name isEqualToString:@"messageEventDefinition"]
		    && ![name isEqualToString:@"timerEventDefinition"]
		    && ![name isEqualToString:@"errorEventDefinition"]
		    && ![name isEqualToString:@"signalEventDefinition"]
		    && ![name isEqualToString:@"terminateEventDefinition"]
		    && ![name isEqualToString:@"escalationEventDefinition"]
		    && ![name isEqualToString:@"compensateEventDefinition"]
		    && ![name isEqualToString:@"linkEventDefinition"]
		    && ![name isEqualToString:@"conditionalEventDefinition"]) {
			*unsupported = name;
			return nil;
		}
		found = child;
	}
	return found;
}

/* timeDate, timeDuration or timeCycle: ISO-8601 text as a literal, or an
 * expression -- ${...}, =..., or FEEL -- evaluated when the timer is
 * armed. */
+ (WFTimer *)timerOf:(NSXMLElement *)definition
                  id:(NSString *)elementId
             context:(WFBpmnReadContext *)context
{
	NSArray *tags = @[ @"timeDate", @"timeDuration", @"timeCycle" ];
	NSXMLElement *found = nil;
	WFTimerKind kind = WFTimerKindDuration;
	for (NSUInteger i = 0; i < [tags count]; i++) {
		NSXMLElement *child = [self child:definition named:[tags objectAtIndex:i]];
		if (child != nil) {
			if (found != nil) {
				[self fail:context error:WFBpmnError(@"%@: a timer has one of timeDate, timeDuration or timeCycle",
					elementId)];
				return nil;
			}
			found = child;
			kind = (WFTimerKind)i;
		}
	}
	if (found == nil) {
		[self fail:context error:WFBpmnError(@"%@: a timer needs timeDate, timeDuration or timeCycle", elementId)];
		return nil;
	}
	NSString *text = [self trimmed:[found stringValue]];
	WFTimer *literal = [WFTimer timerWithKind:kind text:text];
	if (literal != nil) {
		return literal;
	}
	if (kind == WFTimerKindCycle && [text length] > 0 && ![text hasPrefix:@"$"] && ![text hasPrefix:@"#"]
	    && ![text hasPrefix:@"="] && [text rangeOfString:@" "].location != NSNotFound) {
		[self fail:context error:WFBpmnError(
			@"%@: timer cycle \"%@\" is not R<n>/<duration>; cron expressions are not supported", elementId, text)];
		return nil;
	}
	WFFeelExpression *expression = [self expressionFrom:text
	                                           language:[self attr:@"language" of:found]
	                                               what:[NSString stringWithFormat:@"%@: %@",
	                                                   elementId, [tags objectAtIndex:(NSUInteger)kind]]
	                                            context:context];
	return expression != nil ? [[WFTimer alloc] initWithKind:kind expression:expression] : nil;
}

/* A conditionalEventDefinition's condition, and when it is evaluated:
 * camunda:variableName and camunda:variableEvents narrow the changes that
 * make it look again. */
+ (WFEventCondition *)conditionOf:(NSXMLElement *)definition
                               id:(NSString *)elementId
                          context:(WFBpmnReadContext *)context
{
	NSXMLElement *text = [self child:definition named:@"condition"];
	if ([[self trimmed:[text stringValue]] length] == 0) {
		[self fail:context error:WFBpmnError(@"%@: conditional event without a condition", elementId)];
		return nil;
	}
	WFFeelExpression *expression = [self expressionFrom:[text stringValue]
	                                           language:[self attr:@"language" of:text]
	                                               what:[NSString stringWithFormat:@"%@: condition", elementId]
	                                            context:context];
	if (expression == nil) {
		return nil;
	}
	NSString *variableName = [self trimmed:[self attr:@"variableName" namespace:WFCamundaNamespace
	                                                of:definition]];
	NSMutableArray *events = nil;
	NSString *list = [self attr:@"variableEvents" namespace:WFCamundaNamespace of:definition];
	for (NSString *item in [list componentsSeparatedByString:@","]) {
		NSString *kind = [self trimmed:item];
		if ([kind length] == 0) {
			continue;
		}
		if (![@[ @"create", @"update", @"delete" ] containsObject:kind]) {
			[self fail:context error:WFBpmnError(
				@"%@: variable event \"%@\" is none of create, update and delete", elementId, kind)];
			return nil;
		}
		events = events ?: [NSMutableArray array];
		[events addObject:kind];
	}
	return [[WFEventCondition alloc] initWithExpression:expression
	                                       variableName:[variableName length] > 0 ? variableName : nil
	                                     variableEvents:events];
}

+ (NSString *)messageNameOf:(NSXMLElement *)definition
                         id:(NSString *)elementId
                    context:(WFBpmnReadContext *)context
{
	NSString *ref = [self attr:@"messageRef" of:definition];
	if (ref == nil) {
		[self fail:context error:WFBpmnError(@"%@: message event without messageRef",
			elementId)];
		return nil;
	}
	return [context.messages objectForKey:ref] ?: ref;
}

/* A business rule task that evaluates a decision: camunda:decisionRef,
 * its binding, and where the result goes. */
+ (BOOL)readDecisionTask:(NSXMLElement *)element
                      id:(NSString *)elementId
                    into:(WFDefinitionBuilder *)builder
                 context:(WFBpmnReadContext *)context
{
	NSString *decisionRef = [self attr:@"decisionRef" namespace:WFCamundaNamespace of:element];
	if ([decisionRef hasPrefix:@"${"] || [decisionRef hasPrefix:@"#{"]) {
		[self fail:context error:WFBpmnError(@"%@: expressions in camunda:decisionRef are not supported", elementId)];
		return NO;
	}
	if ([self attr:@"decisionRefTenantId" namespace:WFCamundaNamespace of:element] != nil) {
		[self fail:context error:WFBpmnError(@"%@: camunda:decisionRefTenantId is not supported", elementId)];
		return NO;
	}
	NSDictionary *mappings = @{ @"resultList": @(WFDecisionResultMappingResultList),
		@"singleEntry": @(WFDecisionResultMappingSingleEntry),
		@"singleResult": @(WFDecisionResultMappingSingleResult),
		@"collectEntries": @(WFDecisionResultMappingCollectEntries) };
	NSString *mapping = [self attr:@"mapDecisionResult" namespace:WFCamundaNamespace of:element] ?: @"resultList";
	if ([mappings objectForKey:mapping] == nil) {
		[self fail:context error:WFBpmnError(@"%@: camunda:mapDecisionResult \"%@\" is not supported",
			elementId, mapping)];
		return NO;
	}
	[builder addBusinessRuleTask:elementId
	                    decision:decisionRef
	              resultVariable:[self attr:@"resultVariable" namespace:WFCamundaNamespace of:element]
	                     mapping:(WFDecisionResultMapping)[[mappings objectForKey:mapping] integerValue]];
	NSString *binding = [self attr:@"decisionRefBinding" namespace:WFCamundaNamespace of:element] ?: @"latest";
	NSString *version = [self attr:@"decisionRefVersion" namespace:WFCamundaNamespace of:element];
	long long number = 0;
	if ([binding isEqualToString:@"deployment"]) {
		[builder setDecisionBinding:WFCalledElementBindingDeployment version:0 forElement:elementId];
	} else if ([binding isEqualToString:@"version"] && WFParseWhole(version, &number) && number > 0) {
		[builder setDecisionBinding:WFCalledElementBindingVersion version:(NSInteger)number forElement:elementId];
	} else if (![binding isEqualToString:@"latest"]) {
		[self fail:context error:WFBpmnError(
			@"%@: camunda:decisionRefBinding \"%@\" is not supported; use latest, deployment, or version with a whole camunda:decisionRefVersion",
			elementId, binding)];
		return NO;
	}
	return YES;
}

+ (BOOL)readCall:(NSXMLElement *)element
              id:(NSString *)elementId
            into:(WFDefinitionBuilder *)builder
         context:(WFBpmnReadContext *)context
{
	for (NSString *unsupported in @[ @"calledElementTenantId", @"variableMappingClass",
	                                 @"variableMappingDelegateExpression", @"caseRef" ]) {
		if ([self attr:unsupported namespace:WFCamundaNamespace of:element] != nil) {
			[self fail:context error:WFBpmnError(@"%@: camunda:%@ is not supported",
				elementId, unsupported)];
			return NO;
		}
	}
	NSString *called = [self trimmed:[self attr:@"calledElement" of:element]];
	if ([called length] == 0) {
		[self fail:context error:WFBpmnError(
			@"%@: a call activity needs calledElement, the key of a process", elementId)];
		return NO;
	}
	if ([called rangeOfString:@"{"].location != NSNotFound) {
		[self fail:context error:WFBpmnError(
			@"%@: calledElement \"%@\" is an expression; only process keys are supported",
			elementId, called)];
		return NO;
	}
	[builder addCallActivity:elementId calledElement:called];

	NSString *binding = [self attr:@"calledElementBinding" namespace:WFCamundaNamespace of:element];
	if ([binding isEqualToString:@"deployment"]) {
		[builder setBinding:WFCalledElementBindingDeployment version:0 forElement:elementId];
	} else if ([binding isEqualToString:@"version"]) {
		NSString *text = [self attr:@"calledElementVersion" namespace:WFCamundaNamespace of:element];
		long long version = 0;
		if (text == nil || !WFParseWhole(text, &version) || version < 1) {
			[self fail:context error:WFBpmnError(
				@"%@: the version binding needs camunda:calledElementVersion, a version number",
				elementId)];
			return NO;
		}
		[builder setBinding:WFCalledElementBindingVersion version:(NSInteger)version
		         forElement:elementId];
	} else if (binding != nil && ![binding isEqualToString:@"latest"]) {
		[self fail:context error:WFBpmnError(
			@"%@: camunda:calledElementBinding \"%@\" is not supported", elementId, binding)];
		return NO;
	}

	NSXMLElement *extensions = [self child:element named:@"extensionElements"];
	for (NSXMLElement *extension in [self children:extensions of:WFCamundaNamespace]) {
		NSString *kind = [extension localName];
		BOOL input = [kind isEqualToString:@"in"];
		if (!input && ![kind isEqualToString:@"out"]) {
			continue;
		}
		WFVariableMapping *mapping = [self mappingFrom:extension input:input id:elementId
		                                       context:context];
		if (mapping == nil) {
			return NO;
		}
		if (input) {
			[builder addInput:mapping forElement:elementId];
		} else {
			[builder addOutput:mapping forElement:elementId];
		}
	}
	return context.error == nil;
}

+ (WFVariableMapping *)mappingFrom:(NSXMLElement *)extension
                             input:(BOOL)input
                                id:(NSString *)elementId
                           context:(WFBpmnReadContext *)context
{
	NSString *kind = input ? @"camunda:in" : @"camunda:out";
	if ([self attr:@"sourceExpression" of:extension] != nil) {
		[self fail:context error:WFBpmnError(
			@"%@: %@ sourceExpression is not supported; map variables by name", elementId, kind)];
		return nil;
	}
	if ([[self attr:@"local" of:extension] isEqualToString:@"true"]) {
		[self fail:context error:WFBpmnError(
			@"%@: %@ local=\"true\" is not supported", elementId, kind)];
		return nil;
	}
	NSString *businessKey = [self attr:@"businessKey" of:extension];
	if (businessKey != nil) {
		NSString *compact = [[businessKey componentsSeparatedByCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
		if (!input || !([compact isEqualToString:WFBusinessKeyExpression]
		                || [compact isEqualToString:@"${execution.processBusinessKey}"])) {
			[self fail:context error:WFBpmnError(
				@"%@: %@ businessKey can only pass the calling instance's business key on (%@)",
				elementId, kind, WFBusinessKeyExpression)];
			return nil;
		}
		return [WFVariableMapping businessKey];
	}
	if ([[self attr:@"variables" of:extension] isEqualToString:@"all"]) {
		return [WFVariableMapping allVariables];
	}
	NSString *source = [self attr:@"source" of:extension];
	NSString *target = [self attr:@"target" of:extension];
	if ([source length] == 0 || [target length] == 0) {
		[self fail:context error:WFBpmnError(
			@"%@: %@ needs source and target, variables=\"all\" or businessKey",
			elementId, kind)];
		return nil;
	}
	return [WFVariableMapping mappingFrom:source to:target];
}

+ (BOOL)readNode:(NSXMLElement *)element
            name:(NSString *)name
              id:(NSString *)elementId
            into:(WFDefinitionBuilder *)builder
         context:(WFBpmnReadContext *)context
{
	BOOL isEvent = [name hasSuffix:@"Event"];
	NSXMLElement *definition = nil;
	NSString *trigger = nil;
	if (isEvent) {
		NSString *unsupported = nil;
		definition = [self eventDefinitionOf:element unsupported:&unsupported];
		if (unsupported != nil) {
			[self fail:context error:WFBpmnError(@"%@: %@ is not supported yet",
				elementId, unsupported)];
			return NO;
		}
		trigger = [definition localName];
	}
	BOOL message = [trigger isEqualToString:@"messageEventDefinition"];
	BOOL timer = [trigger isEqualToString:@"timerEventDefinition"];
	BOOL errorTrigger = [trigger isEqualToString:@"errorEventDefinition"];
	BOOL signal = [trigger isEqualToString:@"signalEventDefinition"];
	BOOL terminate = [trigger isEqualToString:@"terminateEventDefinition"];
	BOOL escalation = [trigger isEqualToString:@"escalationEventDefinition"];
	BOOL compensate = [trigger isEqualToString:@"compensateEventDefinition"];
	BOOL link = [trigger isEqualToString:@"linkEventDefinition"];
	NSString *linkName = link ? [self attr:@"name" of:definition] : nil;
	if (link && [linkName length] == 0) {
		[self fail:context error:WFBpmnError(@"%@: link event without a name", elementId)];
		return NO;
	}
	WFEventCondition *condition = nil;
	if ([trigger isEqualToString:@"conditionalEventDefinition"]) {
		condition = [self conditionOf:definition id:elementId context:context];
		if (condition == nil) {
			return NO;
		}
	}
	NSString *escalationCode = nil;
	if (escalation) {
		NSString *ref = [self attr:@"escalationRef" of:definition];
		escalationCode = ref == nil ? nil : ([context.escalations objectForKey:ref] ?: ref);
	}
	NSString *errorCode = nil;
	if (errorTrigger) {
		NSString *ref = [self attr:@"errorRef" of:definition];
		errorCode = ref == nil ? nil : ([context.errors objectForKey:ref] ?: ref);
	}
	if (compensate && [[self attr:@"waitForCompletion" of:definition] isEqualToString:@"false"]) {
		[self fail:context error:WFBpmnError(
			@"%@: waitForCompletion=\"false\" is not supported; compensation is waited for", elementId)];
		return NO;
	}
	NSString *signalName = nil;
	if (signal) {
		NSString *ref = [self attr:@"signalRef" of:definition];
		if (ref == nil) {
			[self fail:context error:WFBpmnError(@"%@: signal event without signalRef", elementId)];
			return NO;
		}
		signalName = [context.signals objectForKey:ref] ?: ref;
	}

	if ([name isEqualToString:@"startEvent"]) {
		if (message) {
			NSString *messageName = [self messageNameOf:definition id:elementId context:context];
			[builder addMessageStart:elementId message:messageName];
		} else if (timer) {
			[[builder addTimerStart:elementId duration:0]
				setTimer:[self timerOf:definition id:elementId context:context] forElement:elementId];
		} else if (signal) {
			[builder addSignalStart:elementId signal:signalName];
		} else if (errorTrigger) {
			if (!context.inEventSubProcess) {
				[self fail:context error:WFBpmnError(
					@"%@: an error start event can only start an event subprocess", elementId)];
				return NO;
			}
			[builder addErrorStart:elementId errorRef:errorCode];
		} else if (escalation) {
			if (!context.inEventSubProcess) {
				[self fail:context error:WFBpmnError(
					@"%@: an escalation start event can only start an event subprocess", elementId)];
				return NO;
			}
			[builder addEscalationStart:elementId code:escalationCode];
		} else if (compensate) {
			[self fail:context error:WFBpmnError(
				@"%@: compensation event subprocesses are not supported yet", elementId)];
			return NO;
		} else if (condition != nil) {
			[[builder addConditionalStart:elementId condition:@"true"]
				setCondition:condition forElement:elementId];
		} else {
			[builder addStart:elementId];
		}
		if ([[self attr:@"isInterrupting" of:element] isEqualToString:@"false"]) {
			[builder setInterrupting:NO forElement:elementId];
		}
	} else if ([name isEqualToString:@"endEvent"]) {
		if (message) {
			[builder addMessageEnd:elementId
			               message:[self messageNameOf:definition id:elementId context:context]];
		} else if (signal) {
			[builder addSignalEnd:elementId signal:signalName];
		} else if (terminate) {
			[builder addTerminateEnd:elementId];
		} else if (errorTrigger) {
			[builder addErrorEnd:elementId errorRef:errorCode];
		} else if (escalation) {
			[builder addEscalationEnd:elementId code:escalationCode];
		} else if (compensate) {
			[builder addCompensationEnd:elementId activity:[self attr:@"activityRef" of:definition]];
		} else if (definition != nil) {
			[self fail:context error:WFBpmnError(
				@"%@: %@ end events are not supported yet", elementId, trigger)];
		} else {
			[builder addEnd:elementId];
		}
	} else if ([name isEqualToString:@"intermediateCatchEvent"]) {
		if (message) {
			[builder addMessageCatch:elementId
			                 message:[self messageNameOf:definition id:elementId context:context]];
		} else if (timer) {
			[[builder addTimerCatch:elementId duration:0]
				setTimer:[self timerOf:definition id:elementId context:context] forElement:elementId];
		} else if (signal) {
			[builder addSignalCatch:elementId signal:signalName];
		} else if (link) {
			[builder addLinkCatch:elementId link:linkName];
		} else if (condition != nil) {
			[[builder addConditionalCatch:elementId condition:@"true"]
				setCondition:condition forElement:elementId];
		} else {
			[self fail:context error:WFBpmnError(
				@"%@: a catch event needs a message, timer, signal, link or condition", elementId)];
		}
	} else if ([name isEqualToString:@"intermediateThrowEvent"]) {
		if (message) {
			[builder addMessageThrow:elementId
			                 message:[self messageNameOf:definition id:elementId context:context]];
		} else if (signal) {
			[builder addSignalThrow:elementId signal:signalName];
		} else if (escalation) {
			[builder addEscalationThrow:elementId code:escalationCode];
		} else if (compensate) {
			[builder addCompensationThrow:elementId activity:[self attr:@"activityRef" of:definition]];
		} else if (link) {
			[builder addLinkThrow:elementId link:linkName];
		} else if (definition == nil) {
			[builder addIntermediateThrow:elementId];
		} else {
			[self fail:context error:WFBpmnError(
				@"%@: only message, signal, escalation, compensation, link and none throw events are supported",
				elementId)];
		}
	} else if ([name isEqualToString:@"boundaryEvent"]) {
		NSString *host = [self attr:@"attachedToRef" of:element];
		BOOL interrupting = ![[self attr:@"cancelActivity" of:element]
			isEqualToString:@"false"];
		if (message) {
			[builder addBoundaryMessage:elementId
			                     onTask:host
			                    message:[self messageNameOf:definition id:elementId context:context]
			               interrupting:interrupting];
		} else if (timer) {
			[[builder addBoundaryTimer:elementId onTask:host duration:0 interrupting:interrupting]
				setTimer:[self timerOf:definition id:elementId context:context] forElement:elementId];
		} else if (signal) {
			[builder addBoundarySignal:elementId onTask:host signal:signalName
			              interrupting:interrupting];
		} else if (errorTrigger) {
			[builder addBoundaryError:elementId onTask:host errorRef:errorCode interrupting:YES];
		} else if (escalation) {
			[builder addBoundaryEscalation:elementId onTask:host code:escalationCode
			                  interrupting:interrupting];
		} else if (compensate) {
			/* Its handler comes from the association, read with the scope. */
			[builder addBoundaryCompensation:elementId onTask:host handler:nil];
		} else if (condition != nil) {
			[[builder addBoundaryConditional:elementId onTask:host condition:@"true"
			                    interrupting:interrupting]
				setCondition:condition forElement:elementId];
		} else {
			[self fail:context error:WFBpmnError(
				@"%@: a boundary event needs a message, timer, signal, error, escalation, compensation or condition",
				elementId)];
		}
	} else if ([name isEqualToString:@"userTask"]) {
		[builder addUserTask:elementId name:[self attr:@"name" of:element] ?: elementId assignee:nil];
		NSMutableDictionary *assignment = [NSMutableDictionary dictionary];
		for (NSString *key in @[ @"assignee", @"candidateUsers", @"candidateGroups", @"dueDate",
		                         @"followUpDate", @"priority" ]) {
			NSString *value = [self attr:key namespace:WFCamundaNamespace of:element];
			if (value != nil) {
				[assignment setObject:value forKey:key];
			}
		}
		if ([assignment count] > 0) {
			[builder setAssignment:assignment forElement:elementId];
		}
	} else if (([name isEqualToString:@"serviceTask"] || [name isEqualToString:@"sendTask"]
	            || [name isEqualToString:@"businessRuleTask"])
	           && ([self attr:@"class" namespace:WFCamundaNamespace of:element] != nil
	               || [self attr:@"delegateExpression" namespace:WFCamundaNamespace of:element] != nil
	               || [self attr:@"expression" namespace:WFCamundaNamespace of:element] != nil)) {
		WFDelegateReference *delegate = [self delegateOf:element
		                                        fieldsIn:[self child:element named:@"extensionElements"]
		                                              id:elementId
		                                         context:context];
		if (delegate == nil) {
			return NO;
		}
		WFTaskKind kind = [name isEqualToString:@"serviceTask"] ? WFTaskKindService
			: [name isEqualToString:@"sendTask"] ? WFTaskKindSend : WFTaskKindBusinessRule;
		if (kind == WFTaskKindSend) {
			[builder addSendTask:elementId action:nil];
		} else if (kind == WFTaskKindBusinessRule) {
			[builder addBusinessRuleTask:elementId action:nil];
		} else {
			[builder addServiceTask:elementId action:nil];
		}
		[builder setDelegate:delegate forElement:elementId];
	} else if ([name isEqualToString:@"serviceTask"]) {
		NSString *type = [self attr:@"type" namespace:WFCamundaNamespace of:element];
		NSString *topic = [self attr:@"topic" namespace:WFCamundaNamespace of:element];
		if (![type isEqualToString:@"external"] || topic == nil) {
			[self fail:context error:WFBpmnError(
				@"%@: service tasks are external tasks (camunda:type=\"external\" with a camunda:topic) or run a delegate (camunda:class, camunda:delegateExpression)",
				elementId)];
			return NO;
		}
		[builder addServiceTask:elementId action:topic];
	} else if ([name isEqualToString:@"businessRuleTask"]
	           && [self attr:@"decisionRef" namespace:WFCamundaNamespace of:element] != nil) {
		return [self readDecisionTask:element id:elementId into:builder context:context];
	} else if ([name isEqualToString:@"sendTask"] || [name isEqualToString:@"businessRuleTask"]) {
		NSString *type = [self attr:@"type" namespace:WFCamundaNamespace of:element];
		NSString *topic = [self attr:@"topic" namespace:WFCamundaNamespace of:element];
		if (![type isEqualToString:@"external"] || topic == nil) {
			[self fail:context error:WFBpmnError(
				@"%@: %@ (camunda:type=\"external\" with a camunda:topic)", elementId,
				[name isEqualToString:@"sendTask"] ? @"send tasks must be external tasks"
					: @"business rule tasks call a decision (camunda:decisionRef) or are external tasks")];
			return NO;
		}
		if ([name isEqualToString:@"sendTask"]) {
			[builder addSendTask:elementId action:topic];
		} else {
			[builder addBusinessRuleTask:elementId action:topic];
		}
	} else if ([name isEqualToString:@"receiveTask"]) {
		if ([[self attr:@"instantiate" of:element] isEqualToString:@"true"]) {
			[self fail:context error:WFBpmnError(
				@"%@: a receive task cannot start a process; use a message start event", elementId)];
			return NO;
		}
		NSString *messageName = [self messageNameOf:element id:elementId context:context];
		if (messageName == nil) {
			return NO;
		}
		[builder addReceiveTask:elementId message:messageName];
	} else if ([name isEqualToString:@"manualTask"]) {
		[builder addManualTask:elementId];
	} else if ([name isEqualToString:@"task"]) {
		[builder addTask:elementId];
	} else if ([name isEqualToString:@"scriptTask"]) {
		NSString *action = [self attr:@"action" namespace:WFBpmnExtensionNamespace of:element];
		if (action == nil) {
			[self fail:context error:WFBpmnError(
				@"%@: script tasks run an action named by wf:action; script text is not supported",
				elementId)];
			return NO;
		}
		[builder addScriptTask:elementId action:action];
	} else if ([name isEqualToString:@"exclusiveGateway"]) {
		[builder addExclusive:elementId defaultFlow:[self attr:@"default" of:element]];
	} else if ([name isEqualToString:@"inclusiveGateway"]) {
		[builder addInclusive:elementId defaultFlow:[self attr:@"default" of:element]];
	} else if ([name isEqualToString:@"parallelGateway"]) {
		[builder addParallel:elementId];
	} else if ([name isEqualToString:@"eventBasedGateway"]) {
		[builder addEventBased:elementId];
	} else if ([name isEqualToString:@"callActivity"]) {
		return [self readCall:element id:elementId into:builder context:context];
	} else if ([name isEqualToString:@"subProcess"]) {
		BOOL triggered = [[self attr:@"triggeredByEvent" of:element] isEqualToString:@"true"];
		WFDefinitionBuilder *inner =
			[WFDefinitionBuilder process:elementId
			                        name:[self attr:@"name" of:element] ?: elementId];
		BOOL outer = context.inEventSubProcess;
		context.inEventSubProcess = triggered;
		[self readScope:element into:inner context:context];
		context.inEventSubProcess = outer;
		if (context.error != nil) {
			return NO;
		}
		NSError *buildError = nil;
		WFProcessDefinition *scope = [inner build:&buildError];
		if (scope == nil) {
			[self fail:context error:WFBpmnError(@"%@: %@", elementId,
				[buildError localizedDescription])];
			return NO;
		}
		if (triggered) {
			[builder addEventSubProcess:elementId
			                       name:[self attr:@"name" of:element] ?: elementId
			                      inner:scope];
		} else {
			[builder addSubProcess:elementId
			                  name:[self attr:@"name" of:element] ?: elementId
			                 inner:scope];
		}
	} else {
		[self fail:context error:WFBpmnError(@"%@: %@ is not supported yet",
			elementId, name)];
		return NO;
	}
	return context.error == nil;
}

/*
 * An expression's language: `${...}` (or `#{...}`) is the Camunda 7
 * expression syntax, read as the subset WFFeelExpression takes, a
 * leading `=` marks FEEL as Camunda 8 writes it, and otherwise the
 * expression's own language attribute or the document's
 * expressionLanguage decides. A document that names none is read as FEEL:
 * the specification's default, XPath, is not supported. what says which
 * expression it is, for errors.
 */
+ (WFFeelExpression *)expressionFrom:(NSString *)source
                            language:(NSString *)language
                                what:(NSString *)what
                             context:(WFBpmnReadContext *)context
{
	NSString *text = [self trimmed:source];
	language = language ?: context.expressionLanguage;
	BOOL camunda7 = ([text hasPrefix:@"${"] || [text hasPrefix:@"#{"]) && [text hasSuffix:@"}"];
	if (camunda7) {
		text = [text substringWithRange:NSMakeRange(2, [text length] - 3)];
	} else if ([text hasPrefix:@"="]) {
		text = [text substringFromIndex:1];
	} else if ([language isEqualToString:WFXPathLanguage]) {
		[self fail:context error:WFBpmnError(@"%@: XPath is not supported", what)];
		return nil;
	}
	NSError *parseError = nil;
	WFFeelExpression *expression = camunda7
		? [WFFeelExpression expressionWithCamunda7String:text error:&parseError]
		: [WFFeelExpression expressionWithString:text error:&parseError];
	if (expression == nil) {
		[self fail:context error:WFBpmnError(@"%@ %@", what, [parseError localizedDescription])];
	}
	return expression;
}

+ (id<WFCondition>)conditionFrom:(NSXMLElement *)expression
                            flow:(NSString *)flowId
                         context:(WFBpmnReadContext *)context
{
	return [self expressionFrom:[expression stringValue]
	                   language:[self attr:@"language" of:expression]
	                       what:[NSString stringWithFormat:@"%@: condition", flowId]
	                    context:context];
}

+ (BOOL)readLoop:(NSXMLElement *)loop
              id:(NSString *)elementId
            into:(WFDefinitionBuilder *)builder
         context:(WFBpmnReadContext *)context
{
	for (NSString *unsupported in @[ @"asyncBefore", @"asyncAfter", @"exclusive" ]) {
		if ([self attr:unsupported namespace:WFCamundaNamespace of:loop] != nil) {
			[self fail:context error:WFBpmnError(
				@"%@: camunda:%@ on the multi-instance body is not supported yet; set it on the activity",
				elementId, unsupported)];
			return NO;
		}
	}
	for (NSString *unsupported in @[ @"loopDataInputRef", @"inputDataItem", @"loopDataOutputRef",
	                                 @"outputDataItem", @"complexBehaviorDefinition" ]) {
		if ([self child:loop named:unsupported] != nil) {
			[self fail:context error:WFBpmnError(
				@"%@: %@ is not supported; use camunda:collection and camunda:elementVariable",
				elementId, unsupported)];
			return NO;
		}
	}
	WFFeelExpression *cardinality = nil;
	WFFeelExpression *collection = nil;
	WFFeelExpression *completion = nil;
	NSXMLElement *cardinalityElement = [self child:loop named:@"loopCardinality"];
	if (cardinalityElement != nil) {
		cardinality = [self expressionFrom:[cardinalityElement stringValue]
		                          language:[self attr:@"language" of:cardinalityElement]
		                              what:[NSString stringWithFormat:@"%@: loop cardinality", elementId]
		                           context:context];
	}
	NSString *collectionText = [self attr:@"collection" namespace:WFCamundaNamespace of:loop];
	if (collectionText != nil) {
		collection = [self expressionFrom:collectionText
		                         language:nil
		                             what:[NSString stringWithFormat:@"%@: collection", elementId]
		                          context:context];
	}
	NSXMLElement *completionElement = [self child:loop named:@"completionCondition"];
	if (completionElement != nil) {
		completion = [self expressionFrom:[completionElement stringValue]
		                         language:[self attr:@"language" of:completionElement]
		                             what:[NSString stringWithFormat:@"%@: completion condition", elementId]
		                          context:context];
	}
	if (context.error != nil) {
		return NO;
	}
	BOOL sequential = [[self attr:@"isSequential" of:loop] isEqualToString:@"true"];
	[builder setMultiInstance:[[WFMultiInstance alloc] initSequential:sequential
		loopCardinality:cardinality
		     collection:collection
		elementVariable:[self attr:@"elementVariable" namespace:WFCamundaNamespace of:loop]
		completionCondition:completion]
	               forElement:elementId];
	return YES;
}

+ (void)readFlow:(NSXMLElement *)element
              id:(NSString *)flowId
            into:(WFDefinitionBuilder *)builder
         context:(WFBpmnReadContext *)context
{
	NSString *source = [self attr:@"sourceRef" of:element];
	NSString *target = [self attr:@"targetRef" of:element];
	if (source == nil || target == nil) {
		[self fail:context error:WFBpmnError(@"%@: sequence flow without source or target",
			flowId)];
		return;
	}
	id<WFCondition> condition = nil;
	NSXMLElement *expression = [self child:element named:@"conditionExpression"];
	if (expression != nil && [[self trimmed:[expression stringValue]] length] > 0) {
		condition = [self conditionFrom:expression flow:flowId context:context];
		if (condition == nil) {
			return;
		}
	}
	[builder connect:source to:target flowId:flowId condition:condition];
	[self readListenersOf:element id:flowId into:builder context:context];
	NSString *label = [self attr:@"name" of:element];
	if (label != nil) {
		[builder setName:label forElement:flowId];
	}
}

+ (WFProcessDefinition *)definitionFromXMLString:(NSString *)xml
                                           error:(NSError **)error
{
	NSArray *definitions = [self definitionsFromData:
			[xml dataUsingEncoding:NSUTF8StringEncoding]
		error:error];
	return [definitions firstObject];
}

+ (WFProcessDefinition *)definitionFromURL:(NSURL *)url
                                     error:(NSError **)error
{
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
	if (data == nil) {
		return nil;
	}
	return [[self definitionsFromData:data error:error] firstObject];
}

@end

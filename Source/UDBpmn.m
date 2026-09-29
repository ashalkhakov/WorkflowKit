#import "UDBpmn.h"
#import "UDFlowElements.h"
#import "UDCondition.h"
#import "UDDuration.h"
#import "UDTimers.h"
#include <math.h>

NSString * const UDBpmnNamespace =
	@"http://www.omg.org/spec/BPMN/20100524/MODEL";
NSString * const UDBpmnDINamespace =
	@"http://www.omg.org/spec/BPMN/20100524/DI";
NSString * const UDBpmnDCNamespace =
	@"http://www.omg.org/spec/DD/20100524/DC";
NSString * const UDBpmnDINodesNamespace =
	@"http://www.omg.org/spec/DD/20100524/DI";
NSString * const UDCamundaNamespace =
	@"http://camunda.org/schema/1.0/bpmn";
NSString * const UDBpmnExtensionNamespace =
	@"https://udworkflow.local/bpmn";
NSString * const UDFeelLanguage =
	@"https://www.omg.org/spec/DMN/20191111/FEEL/";

static NSString * const UDXPathLanguage = @"http://www.w3.org/1999/XPath";

static NSError *
UDBpmnError(NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	return [NSError errorWithDomain:UDWorkflowErrorDomain
	                           code:UDWorkflowErrorInvalidBpmn
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

/* An XML id for a name that may contain anything. */
static NSString *
UDXMLId(NSString *prefix, NSString *name)
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
UDNumber(double value)
{
	if (value == floor(value) && fabs(value) < 1e15) {
		return [NSString stringWithFormat:@"%lld", (long long)value];
	}
	return [NSString stringWithFormat:@"%.3f", value];
}

/* A whole number, possibly negative, and nothing else. */
static BOOL
UDParseWhole(NSString *text, long long *value)
{
	NSScanner *scanner = [NSScanner scannerWithString:
		[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	return [scanner scanLongLong:value] && [scanner isAtEnd];
}

#pragma mark - Writer

static NSString * const UDXSINamespace = @"http://www.w3.org/2001/XMLSchema-instance";

/* An element by its qualified name -- bpmn:task, camunda:in, dc:Bounds --
 * whose prefix the document's root declares. (A URI of its own would have
 * gnustep-base declare the namespace again on every element.) */
static NSXMLElement *
UDElement(NSString *qualifiedName)
{
	return [NSXMLElement elementWithName:qualifiedName];
}

/* Sets the attribute, unless there is no value to give it; a prefixed
 * name's prefix is one the root declares. */
static void
UDSet(NSXMLElement *element, NSString *name, NSString *value)
{
	if (value == nil || [value length] == 0) {
		return;
	}
	[element addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
}

/* <bpmn:name xsi:type="bpmn:tFormalExpression">text</bpmn:name>: an
 * expression as BPMN holds one. */
static NSXMLElement *
UDFormalExpression(NSString *qualifiedName, NSString *text)
{
	NSXMLElement *element = UDElement(qualifiedName);
	UDSet(element, @"xsi:type", @"bpmn:tFormalExpression");
	[element setStringValue:text];
	return element;
}

@interface UDBpmnWriteContext : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *messages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *errors;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *signals;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *escalations;
/* The diagram's plane, which shapes and edges go into as their elements
 * are written. */
@property (nonatomic, strong) NSXMLElement *plane;
@end

@implementation UDBpmnWriteContext
@end

/* The expression Camunda models write to pass the business key on. */
static NSString * const UDBusinessKeyExpression = @"#{execution.processBusinessKey}";

@implementation UDBpmnWriter

/* The id of the top-level element a name or code is written as, made the
 * first time it is asked for. */
+ (NSString *)idFor:(NSString *)name
             prefix:(NSString *)prefix
                 in:(NSMutableDictionary<NSString *, NSString *> *)ids
{
	NSString *id = [ids objectForKey:name];
	if (id == nil) {
		id = UDXMLId(prefix, name);
		[ids setObject:id forKey:name];
	}
	return id;
}

+ (NSXMLDocument *)documentFromDefinition:(UDProcessDefinition *)definition
                                    error:(NSError **)error
{
	if (definition == nil) {
		if (error != NULL) {
			*error = UDBpmnError(@"no definition to export");
		}
		return nil;
	}
	UDBpmnWriteContext *context = [[UDBpmnWriteContext alloc] init];
	context.messages = [NSMutableDictionary dictionary];
	context.errors = [NSMutableDictionary dictionary];
	context.signals = [NSMutableDictionary dictionary];
	context.escalations = [NSMutableDictionary dictionary];
	context.plane = UDElement(@"bpmndi:BPMNPlane");
	UDSet(context.plane, @"id", UDXMLId(@"Plane_", definition.processId));
	UDSet(context.plane, @"bpmnElement", definition.processId);

	NSXMLElement *process = UDElement(@"bpmn:process");
	UDSet(process, @"id", definition.processId);
	if (![definition.name isEqualToString:definition.processId]) {
		UDSet(process, @"name", definition.name);
	}
	UDSet(process, @"isExecutable", @"true");
	UDSet(process, @"camunda:taskPriority", [definition.defaultTaskPriority stringValue]);
	UDSet(process, @"camunda:historyTimeToLive", [definition.historyTimeToLive stringValue]);
	if (![self appendScope:definition to:process context:context error:error]) {
		return nil;
	}

	NSXMLElement *root = UDElement(@"bpmn:definitions");
	NSDictionary *prefixes = @{ @"bpmn": UDBpmnNamespace, @"bpmndi": UDBpmnDINamespace,
		@"dc": UDBpmnDCNamespace, @"di": UDBpmnDINodesNamespace, @"camunda": UDCamundaNamespace,
		@"ud": UDBpmnExtensionNamespace, @"xsi": UDXSINamespace };
	for (NSString *prefix in @[ @"bpmn", @"bpmndi", @"dc", @"di", @"camunda", @"ud", @"xsi" ]) {
		[root addNamespace:[NSXMLNode namespaceWithName:prefix stringValue:[prefixes objectForKey:prefix]]];
	}
	UDSet(root, @"id", UDXMLId(@"Definitions_", definition.processId));
	UDSet(root, @"targetNamespace", UDBpmnExtensionNamespace);
	UDSet(root, @"expressionLanguage", UDFeelLanguage);
	UDSet(root, @"exporter", @"UDWorkflow");
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
			NSXMLElement *element = UDElement([kind objectAtIndex:0]);
			UDSet(element, @"id", [ids objectForKey:name]);
			UDSet(element, @"name", name);
			if (![[kind objectAtIndex:2] isEqualToString:@"name"]) {
				UDSet(element, [kind objectAtIndex:2], name);
			}
			[root addChild:element];
		}
	}
	[root addChild:process];
	if ([context.plane childCount] > 0) {
		NSXMLElement *diagram = UDElement(@"bpmndi:BPMNDiagram");
		UDSet(diagram, @"id", UDXMLId(@"Diagram_", definition.processId));
		[diagram addChild:context.plane];
		[root addChild:diagram];
	}

	NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:root];
	[document setVersion:@"1.0"];
	[document setCharacterEncoding:@"UTF-8"];
	return document;
}

+ (NSString *)XMLStringFromDefinition:(UDProcessDefinition *)definition
                                error:(NSError **)error
{
	NSXMLDocument *document = [self documentFromDefinition:definition error:error];
	return [document XMLStringWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement];
}

+ (BOOL)appendScope:(UDProcessDefinition *)scope
                 to:(NSXMLElement *)parent
            context:(UDBpmnWriteContext *)context
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
		UDFlowNode *node = [scope nodeWithId:nodeId];
		NSString *handler = [node isKindOfClass:[UDEvent class]] ? [(UDEvent *)node compensationHandlerId] : nil;
		if (handler != nil) {
			NSXMLElement *association = UDElement(@"bpmn:association");
			UDSet(association, @"id", UDXMLId(@"Association_", nodeId));
			UDSet(association, @"associationDirection", @"One");
			UDSet(association, @"sourceRef", nodeId);
			UDSet(association, @"targetRef", handler);
			[parent addChild:association];
		}
	}
	return YES;
}

/* A catch's code: nil for one that catches any. */
static NSString *
UDCaughtCode(NSString *code)
{
	return code == nil || [code length] == 0 || [code isEqualToString:@"*"] ? nil : code;
}

+ (NSXMLElement *)eventDefinitionFor:(UDEvent *)event context:(UDBpmnWriteContext *)context
{
	NSXMLElement *definition = nil;
	switch (event.trigger) {
	case UDEventTriggerMessage:
		definition = UDElement(@"bpmn:messageEventDefinition");
		UDSet(definition, @"messageRef",
			[self idFor:event.messageName prefix:@"Message_" in:context.messages]);
		break;
	case UDEventTriggerError: {
		definition = UDElement(@"bpmn:errorEventDefinition");
		NSString *code = UDCaughtCode(event.errorRef);
		if (code != nil) {
			UDSet(definition, @"errorRef", [self idFor:code prefix:@"Error_" in:context.errors]);
		}
		UDSet(definition, @"camunda:errorCodeVariable", event.codeVariable);
		break;
	}
	case UDEventTriggerEscalation: {
		definition = UDElement(@"bpmn:escalationEventDefinition");
		NSString *code = UDCaughtCode(event.escalationCode);
		if (code != nil) {
			UDSet(definition, @"escalationRef", [self idFor:code prefix:@"Escalation_" in:context.escalations]);
		}
		UDSet(definition, @"camunda:escalationCodeVariable", event.codeVariable);
		break;
	}
	case UDEventTriggerCompensation:
		definition = UDElement(@"bpmn:compensateEventDefinition");
		UDSet(definition, @"activityRef", event.activityRef);
		break;
	case UDEventTriggerSignal:
		definition = UDElement(@"bpmn:signalEventDefinition");
		UDSet(definition, @"signalRef", [self idFor:event.signalName prefix:@"Signal_" in:context.signals]);
		break;
	case UDEventTriggerTerminate:
		definition = UDElement(@"bpmn:terminateEventDefinition");
		break;
	case UDEventTriggerTimer: {
		/* A literal as ISO-8601 text, which any modeler reads; a computed
		 * timer as its FEEL. */
		definition = UDElement(@"bpmn:timerEventDefinition");
		NSArray *tags = @[ @"bpmn:timeDate", @"bpmn:timeDuration", @"bpmn:timeCycle" ];
		NSString *text = UDTimerText(event.timer) ?: [event.timer.expression expressionString];
		[definition addChild:UDFormalExpression([tags objectAtIndex:(NSUInteger)event.timer.kind], text)];
		break;
	}
	case UDEventTriggerNone:
		break;
	}
	return definition;
}

+ (NSXMLElement *)loopFor:(UDMultiInstance *)loop
{
	NSXMLElement *element = UDElement(@"bpmn:multiInstanceLoopCharacteristics");
	if (loop.isSequential) {
		UDSet(element, @"isSequential", @"true");
	}
	UDSet(element, @"camunda:collection", [loop.collection expressionString]);
	UDSet(element, @"camunda:elementVariable", loop.elementVariable);
	if (loop.loopCardinality != nil) {
		[element addChild:UDFormalExpression(@"bpmn:loopCardinality", [loop.loopCardinality expressionString])];
	}
	if (loop.completionCondition != nil) {
		[element addChild:UDFormalExpression(@"bpmn:completionCondition",
			[loop.completionCondition expressionString])];
	}
	return element;
}

+ (NSXMLElement *)mapping:(UDVariableMapping *)mapping named:(NSString *)name
{
	NSXMLElement *element = UDElement(name);
	if (mapping.isAllVariables) {
		UDSet(element, @"variables", @"all");
	} else if (mapping.isBusinessKey) {
		UDSet(element, @"businessKey", UDBusinessKeyExpression);
	} else {
		UDSet(element, @"source", mapping.source);
		UDSet(element, @"target", mapping.target);
	}
	return element;
}

+ (BOOL)appendNode:(UDFlowNode *)node
                to:(NSXMLElement *)parent
           context:(UDBpmnWriteContext *)context
             error:(NSError **)error
{
	NSString *tag = nil;
	/* Attributes in the order they are written. */
	NSMutableArray *attributes = [NSMutableArray array];
	NSXMLElement *eventDefinition = nil;
	UDProcessDefinition *scope = nil;

	if ([node isKindOfClass:[UDEvent class]]) {
		UDEvent *event = (UDEvent *)node;
		switch (event.kind) {
		case UDEventKindStart:
			tag = @"bpmn:startEvent";
			if (!event.isInterrupting) {
				[attributes addObject:@[ @"isInterrupting", @"false" ]];
			}
			break;
		case UDEventKindEnd: tag = @"bpmn:endEvent"; break;
		case UDEventKindIntermediateCatch: tag = @"bpmn:intermediateCatchEvent"; break;
		case UDEventKindIntermediateThrow: tag = @"bpmn:intermediateThrowEvent"; break;
		case UDEventKindBoundary:
			tag = @"bpmn:boundaryEvent";
			[attributes addObject:@[ @"attachedToRef", event.attachedToId ?: @"" ]];
			if (!event.isInterrupting) {
				[attributes addObject:@[ @"cancelActivity", @"false" ]];
			}
			break;
		}
		eventDefinition = [self eventDefinitionFor:event context:context];
	} else if ([node isKindOfClass:[UDTask class]]) {
		UDTask *task = (UDTask *)node;
		if (task.kind == UDTaskKindUser) {
			tag = @"bpmn:userTask";
			[attributes addObject:@[ @"camunda:assignee", task.assignee ?: @"" ]];
		} else if (task.kind == UDTaskKindService) {
			tag = @"bpmn:serviceTask";
			[attributes addObject:@[ @"camunda:type", @"external" ]];
			[attributes addObject:@[ @"camunda:topic", task.actionKey ?: @"" ]];
		} else {
			/* Camunda script tasks run script text; ours run an action by
			 * key, which only our own attribute can say. */
			tag = @"bpmn:scriptTask";
			[attributes addObject:@[ @"ud:action", task.actionKey ?: @"" ]];
		}
	} else if ([node isKindOfClass:[UDGateway class]]) {
		UDGateway *gateway = (UDGateway *)node;
		switch (gateway.kind) {
		case UDGatewayKindExclusive: tag = @"bpmn:exclusiveGateway"; break;
		case UDGatewayKindInclusive: tag = @"bpmn:inclusiveGateway"; break;
		case UDGatewayKindParallel: tag = @"bpmn:parallelGateway"; break;
		case UDGatewayKindEventBased: tag = @"bpmn:eventBasedGateway"; break;
		}
		[attributes addObject:@[ @"default", gateway.defaultFlowId ?: @"" ]];
	} else if ([node isKindOfClass:[UDCallActivity class]]) {
		UDCallActivity *call = (UDCallActivity *)node;
		tag = @"bpmn:callActivity";
		[attributes addObject:@[ @"calledElement", call.calledElement ?: @"" ]];
		if (call.binding == UDCalledElementBindingDeployment) {
			[attributes addObject:@[ @"camunda:calledElementBinding", @"deployment" ]];
		} else if (call.binding == UDCalledElementBindingVersion) {
			[attributes addObject:@[ @"camunda:calledElementBinding", @"version" ]];
			[attributes addObject:@[ @"camunda:calledElementVersion",
				[NSString stringWithFormat:@"%ld", (long)call.calledElementVersion] ]];
		}
	} else if ([node isKindOfClass:[UDSubProcess class]]) {
		tag = @"bpmn:subProcess";
		if ([(UDSubProcess *)node isTriggeredByEvent]) {
			[attributes addObject:@[ @"triggeredByEvent", @"true" ]];
		}
		/* Its flow elements go in after the wiring, which BPMN puts first. */
		scope = [(UDSubProcess *)node innerDefinition];
	} else {
		if (error != NULL) {
			*error = UDBpmnError(@"%@ cannot be written as BPMN", node.elementId);
		}
		return NO;
	}

	NSXMLElement *element = UDElement(tag);
	UDSet(element, @"id", node.elementId);
	if (node.name != nil && ![node.name isEqualToString:node.elementId]) {
		UDSet(element, @"name", node.name);
	}
	for (NSArray *attribute in attributes) {
		UDSet(element, [attribute objectAtIndex:0], [attribute objectAtIndex:1]);
	}
	if (node.isForCompensation) {
		UDSet(element, @"isForCompensation", @"true");
	}
	if (node.isAsyncBefore) {
		UDSet(element, @"camunda:asyncBefore", @"true");
	}
	if (node.isAsyncAfter) {
		UDSet(element, @"camunda:asyncAfter", @"true");
	}
	if (!node.isExclusive) {
		UDSet(element, @"camunda:exclusive", @"false");
	}
	UDSet(element, @"camunda:taskPriority", [node.taskPriority stringValue]);

	/* BPMN puts extension elements, then incoming and outgoing, then an
	 * activity's loop characteristics or an event's definition, before
	 * everything else -- a subprocess's flow elements included. */
	NSXMLElement *extensions = UDElement(@"bpmn:extensionElements");
	if (node.retryTimeCycle != nil) {
		NSXMLElement *cycle = UDElement(@"camunda:failedJobRetryTimeCycle");
		[cycle setStringValue:node.retryTimeCycle];
		[extensions addChild:cycle];
	}
	if ([node isKindOfClass:[UDCallActivity class]]) {
		UDCallActivity *call = (UDCallActivity *)node;
		for (UDVariableMapping *mapping in call.inputs) {
			[extensions addChild:[self mapping:mapping named:@"camunda:in"]];
		}
		for (UDVariableMapping *mapping in call.outputs) {
			[extensions addChild:[self mapping:mapping named:@"camunda:out"]];
		}
	}
	if ([extensions childCount] > 0) {
		[element addChild:extensions];
	}
	for (NSString *flowId in node.incomingFlowIds) {
		NSXMLElement *incoming = UDElement(@"bpmn:incoming");
		[incoming setStringValue:flowId];
		[element addChild:incoming];
	}
	for (NSString *flowId in node.outgoingFlowIds) {
		NSXMLElement *outgoing = UDElement(@"bpmn:outgoing");
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
		NSXMLElement *shape = UDElement(@"bpmndi:BPMNShape");
		UDSet(shape, @"id", UDXMLId(@"Shape_", node.elementId));
		UDSet(shape, @"bpmnElement", node.elementId);
		if ([node isKindOfClass:[UDSubProcess class]]) {
			UDSet(shape, @"isExpanded", @"true");
		}
		NSXMLElement *bounds = UDElement(@"dc:Bounds");
		UDSet(bounds, @"x", UDNumber(node.boundsX));
		UDSet(bounds, @"y", UDNumber(node.boundsY));
		UDSet(bounds, @"width", UDNumber(node.boundsWidth));
		UDSet(bounds, @"height", UDNumber(node.boundsHeight));
		[shape addChild:bounds];
		[context.plane addChild:shape];
	}
	return YES;
}

+ (BOOL)appendFlow:(UDSequenceFlow *)flow
             scope:(UDProcessDefinition *)scope
                to:(NSXMLElement *)parent
           context:(UDBpmnWriteContext *)context
             error:(NSError **)error
{
	NSXMLElement *element = UDElement(@"bpmn:sequenceFlow");
	UDSet(element, @"id", flow.elementId);
	if (flow.name != nil && ![flow.name isEqualToString:flow.elementId]) {
		UDSet(element, @"name", flow.name);
	}
	UDSet(element, @"sourceRef", flow.sourceId);
	UDSet(element, @"targetRef", flow.targetId);
	id condition = flow.condition;
	if (condition != nil) {
		if (![condition conformsToProtocol:@protocol(UDCondition)]) {
			if (error != NULL) {
				*error = UDBpmnError(@"the condition on %@ cannot be written as BPMN", flow.elementId);
			}
			return NO;
		}
		[element addChild:UDFormalExpression(@"bpmn:conditionExpression", [condition expressionString])];
	}
	[parent addChild:element];

	/* A straight edge between the shapes' centres: the diagram needs an
	 * edge to show the flow at all, and we keep no waypoints. */
	UDFlowNode *source = [scope nodeWithId:flow.sourceId];
	UDFlowNode *target = [scope nodeWithId:flow.targetId];
	if (source.boundsWidth > 0 && target.boundsWidth > 0) {
		NSXMLElement *edge = UDElement(@"bpmndi:BPMNEdge");
		UDSet(edge, @"id", UDXMLId(@"Edge_", flow.elementId));
		UDSet(edge, @"bpmnElement", flow.elementId);
		for (UDFlowNode *end in @[ source, target ]) {
			NSXMLElement *waypoint = UDElement(@"di:waypoint");
			UDSet(waypoint, @"x", UDNumber(end.boundsX + end.boundsWidth / 2));
			UDSet(waypoint, @"y", UDNumber(end.boundsY + end.boundsHeight / 2));
			[edge addChild:waypoint];
		}
		[context.plane addChild:edge];
	}
	return YES;
}

+ (BOOL)writeDefinition:(UDProcessDefinition *)definition
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
UDIgnoredElements(void)
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

@interface UDBpmnReadContext : NSObject
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

@implementation UDBpmnReadContext
@end

@implementation UDBpmnReader

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
	for (NSXMLElement *child in [self children:element of:UDBpmnNamespace]) {
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
		if ([[e URI] isEqualToString:UDBpmnDINamespace]
		    && [[e localName] isEqualToString:@"BPMNShape"]) {
			NSString *ref = [self attr:@"bpmnElement" of:e];
			for (NSXMLElement *bounds in [self children:e of:UDBpmnDCNamespace]) {
				if (ref != nil && [[bounds localName] isEqualToString:@"Bounds"]) {
					[shapes setObject:bounds forKey:ref];
				}
			}
		}
		[self collectShapes:e into:shapes];
	}
}

+ (NSArray<UDProcessDefinition *> *)definitionsFromData:(NSData *)data
                                                  error:(NSError **)error
{
	NSError *xmlError = nil;
	NSXMLDocument *document = data == nil ? nil
		: [[NSXMLDocument alloc] initWithData:data options:0 error:&xmlError];
	NSXMLElement *root = [document rootElement];
	if (root == nil) {
		if (error != NULL) {
			*error = xmlError ?: UDBpmnError(@"empty BPMN document");
		}
		return nil;
	}
	if (![[root URI] isEqualToString:UDBpmnNamespace]
	    || ![[root localName] isEqualToString:@"definitions"]) {
		if (error != NULL) {
			*error = UDBpmnError(@"not a BPMN 2.0 document: the root is %@",
				[root name]);
		}
		return nil;
	}

	UDBpmnReadContext *context = [[UDBpmnReadContext alloc] init];
	context.expressionLanguage = [self attr:@"expressionLanguage" of:root];
	NSMutableDictionary *messages = [NSMutableDictionary dictionary];
	NSMutableDictionary *errors = [NSMutableDictionary dictionary];
	NSMutableDictionary *signals = [NSMutableDictionary dictionary];
	NSMutableDictionary *escalations = [NSMutableDictionary dictionary];
	NSMutableArray *processes = [NSMutableArray array];
	for (NSXMLElement *element in [self children:root of:UDBpmnNamespace]) {
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
			*error = UDBpmnError(@"no executable process (isExecutable=\"true\")");
		}
		return nil;
	}
	NSMutableArray *definitions = [NSMutableArray array];
	for (NSXMLElement *process in processes) {
		NSString *processId = [self attr:@"id" of:process];
		if (processId == nil) {
			if (error != NULL) {
				*error = UDBpmnError(@"a process has no id");
			}
			return nil;
		}
		UDDefinitionBuilder *builder =
			[UDDefinitionBuilder process:processId
			                        name:[self attr:@"name" of:process] ?: processId];
		NSString *priority = [self attr:@"taskPriority" namespace:UDCamundaNamespace of:process];
		if (priority != nil) {
			long long value = 0;
			if (!UDParseWhole(priority, &value)) {
				[self fail:context error:UDBpmnError(
					@"%@: camunda:taskPriority \"%@\" is not a whole number; expressions are not supported yet",
					processId, priority)];
			}
			[builder setDefaultTaskPriority:(NSInteger)value];
		}
		NSString *ttl = [self attr:@"historyTimeToLive" namespace:UDCamundaNamespace of:process];
		if ([ttl length] > 0) {
			long long days = 0;
			if (!UDParseWhole(ttl, &days)) {
				NSTimeInterval seconds = UDParseISODuration(ttl);
				days = seconds >= 0 && fmod(seconds, 86400) == 0 ? (long long)(seconds / 86400) : -1;
			}
			if (days < 0) {
				[self fail:context error:UDBpmnError(
					@"%@: camunda:historyTimeToLive \"%@\" is neither days nor an ISO-8601 duration in whole days",
					processId, ttl)];
			}
			[builder setHistoryTimeToLive:(NSInteger)days];
		}
		[self readScope:process into:builder context:context];
		if (context.error != nil) {
			if (error != NULL) {
				*error = context.error;
			}
			return nil;
		}
		UDProcessDefinition *definition = [builder build:error];
		if (definition == nil) {
			return nil;
		}
		[definitions addObject:definition];
	}
	return definitions;
}

+ (void)fail:(UDBpmnReadContext *)context error:(NSError *)error
{
	if (context.error == nil) {
		context.error = error;
	}
}

+ (void)readScope:(NSXMLElement *)scope
             into:(UDDefinitionBuilder *)builder
          context:(UDBpmnReadContext *)context
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
                  into:(UDDefinitionBuilder *)builder
          associations:(NSMutableArray *)associations
               context:(UDBpmnReadContext *)context
{
	for (NSXMLElement *element in [self children:scope of:UDBpmnNamespace]) {
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
		if ([UDIgnoredElements() containsObject:name]) {
			continue;
		}
		NSString *elementId = [self attr:@"id" of:element];
		if (elementId == nil) {
			[self fail:context error:UDBpmnError(@"a %@ has no id", name)];
			return;
		}
		if ([name isEqualToString:@"sequenceFlow"]) {
			[self readFlow:element id:elementId into:builder context:context];
			continue;
		}
		if ([self child:element named:@"standardLoopCharacteristics"] != nil) {
			[self fail:context error:UDBpmnError(
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
				: @"escalationCodeVariable" namespace:UDCamundaNamespace of:definition];
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
                   into:(UDDefinitionBuilder *)builder
                context:(UDBpmnReadContext *)context
{
	BOOL before = [[self attr:@"asyncBefore" namespace:UDCamundaNamespace of:element]
		isEqualToString:@"true"];
	BOOL after = [[self attr:@"asyncAfter" namespace:UDCamundaNamespace of:element]
		isEqualToString:@"true"];
	NSString *exclusive = [self attr:@"exclusive" namespace:UDCamundaNamespace of:element];
	if (before || after || exclusive != nil) {
		[builder setAsyncBefore:before
		             asyncAfter:after
		              exclusive:![exclusive isEqualToString:@"false"]
		             forElement:elementId];
	}
	NSString *priority = [self attr:@"taskPriority" namespace:UDCamundaNamespace of:element];
	if (priority != nil) {
		long long value = 0;
		if (UDParseWhole(priority, &value)) {
			[builder setTaskPriority:(NSInteger)value forElement:elementId];
		} else {
			[self fail:context error:UDBpmnError(
				@"%@: camunda:taskPriority \"%@\" is not a whole number; expressions are not supported yet",
				elementId, priority)];
		}
	}
	NSXMLElement *extensions = [self child:element named:@"extensionElements"];
	for (NSXMLElement *extension in [self children:extensions of:UDCamundaNamespace]) {
		if ([[extension localName] isEqualToString:@"failedJobRetryTimeCycle"]) {
			NSString *cycle = [self trimmed:[extension stringValue]];
			if ([cycle length] > 0) {
				[builder setRetryTimeCycle:cycle forElement:elementId];
			}
		}
	}
}

/* The one event definition an event carries: nil for a none event. Sets
 * *unsupported to the name of one the engine does not run. */
+ (NSXMLElement *)eventDefinitionOf:(NSXMLElement *)event
                        unsupported:(NSString **)unsupported
{
	NSXMLElement *found = nil;
	for (NSXMLElement *child in [self children:event of:UDBpmnNamespace]) {
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
		    && ![name isEqualToString:@"compensateEventDefinition"]) {
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
+ (UDTimer *)timerOf:(NSXMLElement *)definition
                  id:(NSString *)elementId
             context:(UDBpmnReadContext *)context
{
	NSArray *tags = @[ @"timeDate", @"timeDuration", @"timeCycle" ];
	NSXMLElement *found = nil;
	UDTimerKind kind = UDTimerKindDuration;
	for (NSUInteger i = 0; i < [tags count]; i++) {
		NSXMLElement *child = [self child:definition named:[tags objectAtIndex:i]];
		if (child != nil) {
			if (found != nil) {
				[self fail:context error:UDBpmnError(@"%@: a timer has one of timeDate, timeDuration or timeCycle",
					elementId)];
				return nil;
			}
			found = child;
			kind = (UDTimerKind)i;
		}
	}
	if (found == nil) {
		[self fail:context error:UDBpmnError(@"%@: a timer needs timeDate, timeDuration or timeCycle", elementId)];
		return nil;
	}
	NSString *text = [self trimmed:[found stringValue]];
	UDTimer *literal = [UDTimer timerWithKind:kind text:text];
	if (literal != nil) {
		return literal;
	}
	if (kind == UDTimerKindCycle && [text length] > 0 && ![text hasPrefix:@"$"] && ![text hasPrefix:@"#"]
	    && ![text hasPrefix:@"="] && [text rangeOfString:@" "].location != NSNotFound) {
		[self fail:context error:UDBpmnError(
			@"%@: timer cycle \"%@\" is not R<n>/<duration>; cron expressions are not supported", elementId, text)];
		return nil;
	}
	UDFeelExpression *expression = [self expressionFrom:text
	                                           language:[self attr:@"language" of:found]
	                                               what:[NSString stringWithFormat:@"%@: %@",
	                                                   elementId, [tags objectAtIndex:(NSUInteger)kind]]
	                                            context:context];
	return expression != nil ? [[UDTimer alloc] initWithKind:kind expression:expression] : nil;
}

+ (NSString *)messageNameOf:(NSXMLElement *)definition
                         id:(NSString *)elementId
                    context:(UDBpmnReadContext *)context
{
	NSString *ref = [self attr:@"messageRef" of:definition];
	if (ref == nil) {
		[self fail:context error:UDBpmnError(@"%@: message event without messageRef",
			elementId)];
		return nil;
	}
	return [context.messages objectForKey:ref] ?: ref;
}

+ (BOOL)readCall:(NSXMLElement *)element
              id:(NSString *)elementId
            into:(UDDefinitionBuilder *)builder
         context:(UDBpmnReadContext *)context
{
	for (NSString *unsupported in @[ @"calledElementTenantId", @"variableMappingClass",
	                                 @"variableMappingDelegateExpression", @"caseRef" ]) {
		if ([self attr:unsupported namespace:UDCamundaNamespace of:element] != nil) {
			[self fail:context error:UDBpmnError(@"%@: camunda:%@ is not supported",
				elementId, unsupported)];
			return NO;
		}
	}
	NSString *called = [self trimmed:[self attr:@"calledElement" of:element]];
	if ([called length] == 0) {
		[self fail:context error:UDBpmnError(
			@"%@: a call activity needs calledElement, the key of a process", elementId)];
		return NO;
	}
	if ([called rangeOfString:@"{"].location != NSNotFound) {
		[self fail:context error:UDBpmnError(
			@"%@: calledElement \"%@\" is an expression; only process keys are supported",
			elementId, called)];
		return NO;
	}
	[builder addCallActivity:elementId calledElement:called];

	NSString *binding = [self attr:@"calledElementBinding" namespace:UDCamundaNamespace of:element];
	if ([binding isEqualToString:@"deployment"]) {
		[builder setBinding:UDCalledElementBindingDeployment version:0 forElement:elementId];
	} else if ([binding isEqualToString:@"version"]) {
		NSString *text = [self attr:@"calledElementVersion" namespace:UDCamundaNamespace of:element];
		long long version = 0;
		if (text == nil || !UDParseWhole(text, &version) || version < 1) {
			[self fail:context error:UDBpmnError(
				@"%@: the version binding needs camunda:calledElementVersion, a version number",
				elementId)];
			return NO;
		}
		[builder setBinding:UDCalledElementBindingVersion version:(NSInteger)version
		         forElement:elementId];
	} else if (binding != nil && ![binding isEqualToString:@"latest"]) {
		[self fail:context error:UDBpmnError(
			@"%@: camunda:calledElementBinding \"%@\" is not supported", elementId, binding)];
		return NO;
	}

	NSXMLElement *extensions = [self child:element named:@"extensionElements"];
	for (NSXMLElement *extension in [self children:extensions of:UDCamundaNamespace]) {
		NSString *kind = [extension localName];
		BOOL input = [kind isEqualToString:@"in"];
		if (!input && ![kind isEqualToString:@"out"]) {
			continue;
		}
		UDVariableMapping *mapping = [self mappingFrom:extension input:input id:elementId
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

+ (UDVariableMapping *)mappingFrom:(NSXMLElement *)extension
                             input:(BOOL)input
                                id:(NSString *)elementId
                           context:(UDBpmnReadContext *)context
{
	NSString *kind = input ? @"camunda:in" : @"camunda:out";
	if ([self attr:@"sourceExpression" of:extension] != nil) {
		[self fail:context error:UDBpmnError(
			@"%@: %@ sourceExpression is not supported; map variables by name", elementId, kind)];
		return nil;
	}
	if ([[self attr:@"local" of:extension] isEqualToString:@"true"]) {
		[self fail:context error:UDBpmnError(
			@"%@: %@ local=\"true\" is not supported", elementId, kind)];
		return nil;
	}
	NSString *businessKey = [self attr:@"businessKey" of:extension];
	if (businessKey != nil) {
		NSString *compact = [[businessKey componentsSeparatedByCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
		if (!input || !([compact isEqualToString:UDBusinessKeyExpression]
		                || [compact isEqualToString:@"${execution.processBusinessKey}"])) {
			[self fail:context error:UDBpmnError(
				@"%@: %@ businessKey can only pass the calling instance's business key on (%@)",
				elementId, kind, UDBusinessKeyExpression)];
			return nil;
		}
		return [UDVariableMapping businessKey];
	}
	if ([[self attr:@"variables" of:extension] isEqualToString:@"all"]) {
		return [UDVariableMapping allVariables];
	}
	NSString *source = [self attr:@"source" of:extension];
	NSString *target = [self attr:@"target" of:extension];
	if ([source length] == 0 || [target length] == 0) {
		[self fail:context error:UDBpmnError(
			@"%@: %@ needs source and target, variables=\"all\" or businessKey",
			elementId, kind)];
		return nil;
	}
	return [UDVariableMapping mappingFrom:source to:target];
}

+ (BOOL)readNode:(NSXMLElement *)element
            name:(NSString *)name
              id:(NSString *)elementId
            into:(UDDefinitionBuilder *)builder
         context:(UDBpmnReadContext *)context
{
	BOOL isEvent = [name hasSuffix:@"Event"];
	NSXMLElement *definition = nil;
	NSString *trigger = nil;
	if (isEvent) {
		NSString *unsupported = nil;
		definition = [self eventDefinitionOf:element unsupported:&unsupported];
		if (unsupported != nil) {
			[self fail:context error:UDBpmnError(@"%@: %@ is not supported yet",
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
		[self fail:context error:UDBpmnError(
			@"%@: waitForCompletion=\"false\" is not supported; compensation is waited for", elementId)];
		return NO;
	}
	NSString *signalName = nil;
	if (signal) {
		NSString *ref = [self attr:@"signalRef" of:definition];
		if (ref == nil) {
			[self fail:context error:UDBpmnError(@"%@: signal event without signalRef", elementId)];
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
				[self fail:context error:UDBpmnError(
					@"%@: an error start event can only start an event subprocess", elementId)];
				return NO;
			}
			[builder addErrorStart:elementId errorRef:errorCode];
		} else if (escalation) {
			if (!context.inEventSubProcess) {
				[self fail:context error:UDBpmnError(
					@"%@: an escalation start event can only start an event subprocess", elementId)];
				return NO;
			}
			[builder addEscalationStart:elementId code:escalationCode];
		} else if (compensate) {
			[self fail:context error:UDBpmnError(
				@"%@: compensation event subprocesses are not supported yet", elementId)];
			return NO;
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
			[self fail:context error:UDBpmnError(
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
		} else {
			[self fail:context error:UDBpmnError(
				@"%@: a catch event needs a message, timer or signal", elementId)];
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
		} else if (definition == nil) {
			[builder addIntermediateThrow:elementId];
		} else {
			[self fail:context error:UDBpmnError(
				@"%@: only message, signal, escalation, compensation and none throw events are supported",
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
		} else {
			[self fail:context error:UDBpmnError(
				@"%@: a boundary event needs a message, timer, signal, error, escalation or compensation",
				elementId)];
		}
	} else if ([name isEqualToString:@"userTask"]) {
		[builder addUserTask:elementId
		                name:[self attr:@"name" of:element] ?: elementId
		            assignee:[self attr:@"assignee" namespace:UDCamundaNamespace of:element]];
	} else if ([name isEqualToString:@"serviceTask"]) {
		NSString *type = [self attr:@"type" namespace:UDCamundaNamespace of:element];
		NSString *topic = [self attr:@"topic" namespace:UDCamundaNamespace of:element];
		if (![type isEqualToString:@"external"] || topic == nil) {
			[self fail:context error:UDBpmnError(
				@"%@: service tasks must be external tasks (camunda:type=\"external\" with a camunda:topic)",
				elementId)];
			return NO;
		}
		[builder addServiceTask:elementId action:topic];
	} else if ([name isEqualToString:@"scriptTask"]) {
		NSString *action = [self attr:@"action" namespace:UDBpmnExtensionNamespace of:element];
		if (action == nil) {
			[self fail:context error:UDBpmnError(
				@"%@: script tasks run an action named by ud:action; script text is not supported",
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
		UDDefinitionBuilder *inner =
			[UDDefinitionBuilder process:elementId
			                        name:[self attr:@"name" of:element] ?: elementId];
		BOOL outer = context.inEventSubProcess;
		context.inEventSubProcess = triggered;
		[self readScope:element into:inner context:context];
		context.inEventSubProcess = outer;
		if (context.error != nil) {
			return NO;
		}
		NSError *buildError = nil;
		UDProcessDefinition *scope = [inner build:&buildError];
		if (scope == nil) {
			[self fail:context error:UDBpmnError(@"%@: %@", elementId,
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
		[self fail:context error:UDBpmnError(@"%@: %@ is not supported yet",
			elementId, name)];
		return NO;
	}
	return context.error == nil;
}

/*
 * An expression's language: `${...}` (or `#{...}`) is the Camunda 7
 * expression syntax, read as the subset UDFeelExpression takes, a
 * leading `=` marks FEEL as Camunda 8 writes it, and otherwise the
 * expression's own language attribute or the document's
 * expressionLanguage decides. A document that names none is read as FEEL:
 * the specification's default, XPath, is not supported. what says which
 * expression it is, for errors.
 */
+ (UDFeelExpression *)expressionFrom:(NSString *)source
                            language:(NSString *)language
                                what:(NSString *)what
                             context:(UDBpmnReadContext *)context
{
	NSString *text = [self trimmed:source];
	language = language ?: context.expressionLanguage;
	BOOL camunda7 = ([text hasPrefix:@"${"] || [text hasPrefix:@"#{"]) && [text hasSuffix:@"}"];
	if (camunda7) {
		text = [text substringWithRange:NSMakeRange(2, [text length] - 3)];
	} else if ([text hasPrefix:@"="]) {
		text = [text substringFromIndex:1];
	} else if ([language isEqualToString:UDXPathLanguage]) {
		[self fail:context error:UDBpmnError(@"%@: XPath is not supported", what)];
		return nil;
	}
	NSError *parseError = nil;
	UDFeelExpression *expression = camunda7
		? [UDFeelExpression expressionWithCamunda7String:text error:&parseError]
		: [UDFeelExpression expressionWithString:text error:&parseError];
	if (expression == nil) {
		[self fail:context error:UDBpmnError(@"%@ %@", what, [parseError localizedDescription])];
	}
	return expression;
}

+ (id<UDCondition>)conditionFrom:(NSXMLElement *)expression
                            flow:(NSString *)flowId
                         context:(UDBpmnReadContext *)context
{
	return [self expressionFrom:[expression stringValue]
	                   language:[self attr:@"language" of:expression]
	                       what:[NSString stringWithFormat:@"%@: condition", flowId]
	                    context:context];
}

+ (BOOL)readLoop:(NSXMLElement *)loop
              id:(NSString *)elementId
            into:(UDDefinitionBuilder *)builder
         context:(UDBpmnReadContext *)context
{
	for (NSString *unsupported in @[ @"asyncBefore", @"asyncAfter", @"exclusive" ]) {
		if ([self attr:unsupported namespace:UDCamundaNamespace of:loop] != nil) {
			[self fail:context error:UDBpmnError(
				@"%@: camunda:%@ on the multi-instance body is not supported yet; set it on the activity",
				elementId, unsupported)];
			return NO;
		}
	}
	for (NSString *unsupported in @[ @"loopDataInputRef", @"inputDataItem", @"loopDataOutputRef",
	                                 @"outputDataItem", @"complexBehaviorDefinition" ]) {
		if ([self child:loop named:unsupported] != nil) {
			[self fail:context error:UDBpmnError(
				@"%@: %@ is not supported; use camunda:collection and camunda:elementVariable",
				elementId, unsupported)];
			return NO;
		}
	}
	UDFeelExpression *cardinality = nil;
	UDFeelExpression *collection = nil;
	UDFeelExpression *completion = nil;
	NSXMLElement *cardinalityElement = [self child:loop named:@"loopCardinality"];
	if (cardinalityElement != nil) {
		cardinality = [self expressionFrom:[cardinalityElement stringValue]
		                          language:[self attr:@"language" of:cardinalityElement]
		                              what:[NSString stringWithFormat:@"%@: loop cardinality", elementId]
		                           context:context];
	}
	NSString *collectionText = [self attr:@"collection" namespace:UDCamundaNamespace of:loop];
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
	[builder setMultiInstance:[[UDMultiInstance alloc] initSequential:sequential
		loopCardinality:cardinality
		     collection:collection
		elementVariable:[self attr:@"elementVariable" namespace:UDCamundaNamespace of:loop]
		completionCondition:completion]
	               forElement:elementId];
	return YES;
}

+ (void)readFlow:(NSXMLElement *)element
              id:(NSString *)flowId
            into:(UDDefinitionBuilder *)builder
         context:(UDBpmnReadContext *)context
{
	NSString *source = [self attr:@"sourceRef" of:element];
	NSString *target = [self attr:@"targetRef" of:element];
	if (source == nil || target == nil) {
		[self fail:context error:UDBpmnError(@"%@: sequence flow without source or target",
			flowId)];
		return;
	}
	id<UDCondition> condition = nil;
	NSXMLElement *expression = [self child:element named:@"conditionExpression"];
	if (expression != nil && [[self trimmed:[expression stringValue]] length] > 0) {
		condition = [self conditionFrom:expression flow:flowId context:context];
		if (condition == nil) {
			return;
		}
	}
	[builder connect:source to:target flowId:flowId condition:condition];
	NSString *label = [self attr:@"name" of:element];
	if (label != nil) {
		[builder setName:label forElement:flowId];
	}
}

+ (UDProcessDefinition *)definitionFromXMLString:(NSString *)xml
                                           error:(NSError **)error
{
	NSArray *definitions = [self definitionsFromData:
			[xml dataUsingEncoding:NSUTF8StringEncoding]
		error:error];
	return [definitions firstObject];
}

+ (UDProcessDefinition *)definitionFromURL:(NSURL *)url
                                     error:(NSError **)error
{
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
	if (data == nil) {
		return nil;
	}
	return [[self definitionsFromData:data error:error] firstObject];
}

@end

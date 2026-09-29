#import "UDBpmn.h"
#import "UDFlowElements.h"
#import "UDCondition.h"
#import "UDDuration.h"
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

static NSString *
UDEscapeXML(NSString *text)
{
	if (text == nil) {
		return @"";
	}
	NSString *s = text;
	s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
	s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
	s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
	s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
	return s;
}

static NSString *
UDAttr(NSString *name, NSString *value)
{
	if (value == nil || [value length] == 0) {
		return @"";
	}
	return [NSString stringWithFormat:@" %@=\"%@\"", name, UDEscapeXML(value)];
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

/* PnDTnHnMnS, seconds with up to millisecond precision. */
static NSString *
UDISODuration(NSTimeInterval seconds)
{
	if (seconds <= 0) {
		return @"PT0S";
	}
	long long millis = llround(seconds * 1000.0);
	long long days = millis / 86400000;
	millis -= days * 86400000;
	long long hours = millis / 3600000;
	millis -= hours * 3600000;
	long long minutes = millis / 60000;
	millis -= minutes * 60000;
	NSMutableString *out = [NSMutableString stringWithString:@"P"];
	if (days > 0) {
		[out appendFormat:@"%lldD", days];
	}
	if (hours > 0 || minutes > 0 || millis > 0) {
		[out appendString:@"T"];
		if (hours > 0) {
			[out appendFormat:@"%lldH", hours];
		}
		if (minutes > 0) {
			[out appendFormat:@"%lldM", minutes];
		}
		if (millis > 0) {
			if (millis % 1000 == 0) {
				[out appendFormat:@"%lldS", millis / 1000];
			} else {
				[out appendFormat:@"%lld.%03lldS", millis / 1000, millis % 1000];
			}
		}
	}
	return out;
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

@interface UDBpmnWriteContext : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *messages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *errors;
@property (nonatomic, strong) NSMutableString *diagram;
@end

@implementation UDBpmnWriteContext
@end

@implementation UDBpmnWriter

+ (NSString *)messageIdFor:(NSString *)name context:(UDBpmnWriteContext *)context
{
	NSString *id = [context.messages objectForKey:name];
	if (id == nil) {
		id = UDXMLId(@"Message_", name);
		[context.messages setObject:id forKey:name];
	}
	return id;
}

+ (NSString *)errorIdFor:(NSString *)code context:(UDBpmnWriteContext *)context
{
	NSString *id = [context.errors objectForKey:code];
	if (id == nil) {
		id = UDXMLId(@"Error_", code);
		[context.errors setObject:id forKey:code];
	}
	return id;
}

+ (NSString *)XMLStringFromDefinition:(UDProcessDefinition *)definition
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
	context.diagram = [NSMutableString string];

	NSMutableString *process = [NSMutableString string];
	[process appendFormat:@"  <bpmn:process%@%@ isExecutable=\"true\"%@%@>\n",
		UDAttr(@"id", definition.processId),
		[definition.name isEqualToString:definition.processId]
			? @"" : UDAttr(@"name", definition.name),
		UDAttr(@"camunda:taskPriority", [definition.defaultTaskPriority stringValue]),
		UDAttr(@"camunda:historyTimeToLive", [definition.historyTimeToLive stringValue])];
	if (![self appendScope:definition
	                    to:process
	                indent:@"    "
	               context:context
	                 error:error]) {
		return nil;
	}
	[process appendString:@"  </bpmn:process>\n"];

	NSMutableString *xml = [NSMutableString string];
	[xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
	[xml appendFormat:
		@"<bpmn:definitions xmlns:bpmn=\"%@\" xmlns:bpmndi=\"%@\" "
		 @"xmlns:dc=\"%@\" xmlns:di=\"%@\" xmlns:camunda=\"%@\" xmlns:ud=\"%@\" "
		 @"xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"%@ "
		 @"targetNamespace=\"%@\" expressionLanguage=\"%@\" "
		 @"exporter=\"UDWorkflow\">\n",
		UDBpmnNamespace, UDBpmnDINamespace, UDBpmnDCNamespace,
		UDBpmnDINodesNamespace, UDCamundaNamespace, UDBpmnExtensionNamespace,
		UDAttr(@"id", UDXMLId(@"Definitions_", definition.processId)),
		UDBpmnExtensionNamespace, UDFeelLanguage];
	for (NSString *name in [[context.messages allKeys]
	         sortedArrayUsingSelector:@selector(compare:)]) {
		[xml appendFormat:@"  <bpmn:message%@%@/>\n",
			UDAttr(@"id", [context.messages objectForKey:name]),
			UDAttr(@"name", name)];
	}
	for (NSString *code in [[context.errors allKeys]
	         sortedArrayUsingSelector:@selector(compare:)]) {
		[xml appendFormat:@"  <bpmn:error%@%@%@/>\n",
			UDAttr(@"id", [context.errors objectForKey:code]),
			UDAttr(@"name", code),
			UDAttr(@"errorCode", code)];
	}
	[xml appendString:process];
	if ([context.diagram length] > 0) {
		[xml appendFormat:@"  <bpmndi:BPMNDiagram%@>\n",
			UDAttr(@"id", UDXMLId(@"Diagram_", definition.processId))];
		[xml appendFormat:@"    <bpmndi:BPMNPlane%@%@>\n",
			UDAttr(@"id", UDXMLId(@"Plane_", definition.processId)),
			UDAttr(@"bpmnElement", definition.processId)];
		[xml appendString:context.diagram];
		[xml appendString:@"    </bpmndi:BPMNPlane>\n  </bpmndi:BPMNDiagram>\n"];
	}
	[xml appendString:@"</bpmn:definitions>\n"];
	return xml;
}

+ (BOOL)appendScope:(UDProcessDefinition *)scope
                 to:(NSMutableString *)out
             indent:(NSString *)indent
            context:(UDBpmnWriteContext *)context
              error:(NSError **)error
{
	NSArray *nodeIds = [[scope.nodes allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *nodeId in nodeIds) {
		if (![self appendNode:[scope nodeWithId:nodeId]
		                   to:out
		               indent:indent
		              context:context
		                error:error]) {
			return NO;
		}
	}
	for (NSString *flowId in scope.flowOrder) {
		if (![self appendFlow:[scope flowWithId:flowId]
		                scope:scope
		                   to:out
		               indent:indent
		              context:context
		                error:error]) {
			return NO;
		}
	}
	return YES;
}

+ (NSString *)eventDefinitionFor:(UDEvent *)event
                          indent:(NSString *)indent
                         context:(UDBpmnWriteContext *)context
{
	switch (event.trigger) {
	case UDEventTriggerMessage:
		return [NSString stringWithFormat:@"%@<bpmn:messageEventDefinition%@/>\n",
			indent, UDAttr(@"messageRef",
				[self messageIdFor:event.messageName context:context])];
	case UDEventTriggerError: {
		NSString *code = event.errorRef;
		BOOL any = code == nil || [code length] == 0 || [code isEqualToString:@"*"];
		return [NSString stringWithFormat:@"%@<bpmn:errorEventDefinition%@/>\n",
			indent, any ? @"" : UDAttr(@"errorRef",
				[self errorIdFor:code context:context])];
	}
	case UDEventTriggerTimer:
		return [NSString stringWithFormat:
			@"%@<bpmn:timerEventDefinition>\n"
			 @"%@  <bpmn:timeDuration xsi:type=\"bpmn:tFormalExpression\">%@</bpmn:timeDuration>\n"
			 @"%@</bpmn:timerEventDefinition>\n",
			indent, indent, UDISODuration(event.timerDuration), indent];
	default:
		return @"";
	}
}

+ (BOOL)appendNode:(UDFlowNode *)node
                to:(NSMutableString *)out
            indent:(NSString *)indent
           context:(UDBpmnWriteContext *)context
             error:(NSError **)error
{
	NSString *tag = nil;
	NSMutableString *attrs = [NSMutableString string];
	NSMutableString *body = [NSMutableString string];
	NSString *inner = [indent stringByAppendingString:@"  "];
	[attrs appendString:UDAttr(@"id", node.elementId)];
	if (node.name != nil && ![node.name isEqualToString:node.elementId]) {
		[attrs appendString:UDAttr(@"name", node.name)];
	}

	if ([node isKindOfClass:[UDEvent class]]) {
		UDEvent *event = (UDEvent *)node;
		switch (event.kind) {
		case UDEventKindStart: tag = @"startEvent"; break;
		case UDEventKindEnd: tag = @"endEvent"; break;
		case UDEventKindIntermediateCatch: tag = @"intermediateCatchEvent"; break;
		case UDEventKindIntermediateThrow: tag = @"intermediateThrowEvent"; break;
		case UDEventKindBoundary:
			tag = @"boundaryEvent";
			[attrs appendString:UDAttr(@"attachedToRef", event.attachedToId)];
			if (!event.isInterrupting) {
				[attrs appendString:@" cancelActivity=\"false\""];
			}
			break;
		}
		[body appendString:[self eventDefinitionFor:event indent:inner context:context]];
	} else if ([node isKindOfClass:[UDTask class]]) {
		UDTask *task = (UDTask *)node;
		if (task.kind == UDTaskKindUser) {
			tag = @"userTask";
			[attrs appendString:UDAttr(@"camunda:assignee", task.assignee)];
		} else if (task.kind == UDTaskKindService) {
			tag = @"serviceTask";
			[attrs appendString:@" camunda:type=\"external\""];
			[attrs appendString:UDAttr(@"camunda:topic", task.actionKey)];
		} else {
			/* Camunda script tasks run script text; ours run an action by
			 * key, which only our own attribute can say. */
			tag = @"scriptTask";
			[attrs appendString:UDAttr(@"ud:action", task.actionKey)];
		}
	} else if ([node isKindOfClass:[UDGateway class]]) {
		UDGateway *gateway = (UDGateway *)node;
		switch (gateway.kind) {
		case UDGatewayKindExclusive: tag = @"exclusiveGateway"; break;
		case UDGatewayKindInclusive: tag = @"inclusiveGateway"; break;
		case UDGatewayKindParallel: tag = @"parallelGateway"; break;
		case UDGatewayKindEventBased: tag = @"eventBasedGateway"; break;
		}
		[attrs appendString:UDAttr(@"default", gateway.defaultFlowId)];
	} else if ([node isKindOfClass:[UDSubProcess class]]) {
		tag = @"subProcess";
		UDProcessDefinition *scope = [(UDSubProcess *)node innerDefinition];
		if (![self appendScope:scope to:body indent:inner context:context error:error]) {
			return NO;
		}
	} else {
		if (error != NULL) {
			*error = UDBpmnError(@"%@ cannot be written as BPMN", node.elementId);
		}
		return NO;
	}

	if (node.isAsyncBefore) {
		[attrs appendString:@" camunda:asyncBefore=\"true\""];
	}
	if (node.isAsyncAfter) {
		[attrs appendString:@" camunda:asyncAfter=\"true\""];
	}
	if (!node.isExclusive) {
		[attrs appendString:@" camunda:exclusive=\"false\""];
	}
	[attrs appendString:UDAttr(@"camunda:taskPriority", [node.taskPriority stringValue])];
	NSMutableString *wiring = [NSMutableString string];
	if (node.retryTimeCycle != nil) {
		[wiring appendFormat:
			@"%@<bpmn:extensionElements>\n"
			 @"%@  <camunda:failedJobRetryTimeCycle>%@</camunda:failedJobRetryTimeCycle>\n"
			 @"%@</bpmn:extensionElements>\n",
			inner, inner, UDEscapeXML(node.retryTimeCycle), inner];
	}
	for (NSString *flowId in node.incomingFlowIds) {
		[wiring appendFormat:@"%@<bpmn:incoming>%@</bpmn:incoming>\n",
			inner, UDEscapeXML(flowId)];
	}
	for (NSString *flowId in node.outgoingFlowIds) {
		[wiring appendFormat:@"%@<bpmn:outgoing>%@</bpmn:outgoing>\n",
			inner, UDEscapeXML(flowId)];
	}
	/* BPMN puts extension elements, then incoming and outgoing, before
	 * everything else. */
	[body insertString:wiring atIndex:0];
	if ([body length] == 0) {
		[out appendFormat:@"%@<bpmn:%@%@/>\n", indent, tag, attrs];
	} else {
		[out appendFormat:@"%@<bpmn:%@%@>\n%@%@</bpmn:%@>\n",
			indent, tag, attrs, body, indent, tag];
	}

	if (node.boundsWidth > 0 || node.boundsHeight > 0) {
		[context.diagram appendFormat:
			@"      <bpmndi:BPMNShape%@%@%@>\n"
			 @"        <dc:Bounds x=\"%@\" y=\"%@\" width=\"%@\" height=\"%@\"/>\n"
			 @"      </bpmndi:BPMNShape>\n",
			UDAttr(@"id", UDXMLId(@"Shape_", node.elementId)),
			UDAttr(@"bpmnElement", node.elementId),
			[node isKindOfClass:[UDSubProcess class]] ? @" isExpanded=\"true\"" : @"",
			UDNumber(node.boundsX), UDNumber(node.boundsY),
			UDNumber(node.boundsWidth), UDNumber(node.boundsHeight)];
	}
	return YES;
}

+ (BOOL)appendFlow:(UDSequenceFlow *)flow
             scope:(UDProcessDefinition *)scope
                to:(NSMutableString *)out
            indent:(NSString *)indent
           context:(UDBpmnWriteContext *)context
             error:(NSError **)error
{
	NSMutableString *attrs = [NSMutableString string];
	[attrs appendString:UDAttr(@"id", flow.elementId)];
	if (flow.name != nil && ![flow.name isEqualToString:flow.elementId]) {
		[attrs appendString:UDAttr(@"name", flow.name)];
	}
	[attrs appendString:UDAttr(@"sourceRef", flow.sourceId)];
	[attrs appendString:UDAttr(@"targetRef", flow.targetId)];

	id condition = flow.condition;
	if (condition == nil) {
		[out appendFormat:@"%@<bpmn:sequenceFlow%@/>\n", indent, attrs];
	} else if ([condition isKindOfClass:[UDComparisonCondition class]]) {
		[out appendFormat:
			@"%@<bpmn:sequenceFlow%@>\n"
			 @"%@  <bpmn:conditionExpression xsi:type=\"bpmn:tFormalExpression\">%@</bpmn:conditionExpression>\n"
			 @"%@</bpmn:sequenceFlow>\n",
			indent, attrs, indent,
			UDEscapeXML([condition expressionString]), indent];
	} else {
		if (error != NULL) {
			*error = UDBpmnError(@"the condition on %@ cannot be written as BPMN",
				flow.elementId);
		}
		return NO;
	}

	/* A straight edge between the shapes' centres: the diagram needs an
	 * edge to show the flow at all, and we keep no waypoints. */
	UDFlowNode *source = [scope nodeWithId:flow.sourceId];
	UDFlowNode *target = [scope nodeWithId:flow.targetId];
	if (source.boundsWidth > 0 && target.boundsWidth > 0) {
		[context.diagram appendFormat:
			@"      <bpmndi:BPMNEdge%@%@>\n"
			 @"        <di:waypoint x=\"%@\" y=\"%@\"/>\n"
			 @"        <di:waypoint x=\"%@\" y=\"%@\"/>\n"
			 @"      </bpmndi:BPMNEdge>\n",
			UDAttr(@"id", UDXMLId(@"Edge_", flow.elementId)),
			UDAttr(@"bpmnElement", flow.elementId),
			UDNumber(source.boundsX + source.boundsWidth / 2),
			UDNumber(source.boundsY + source.boundsHeight / 2),
			UDNumber(target.boundsX + target.boundsWidth / 2),
			UDNumber(target.boundsY + target.boundsHeight / 2)];
	}
	return YES;
}

+ (BOOL)writeDefinition:(UDProcessDefinition *)definition
                  toURL:(NSURL *)url
                  error:(NSError **)error
{
	NSString *xml = [self XMLStringFromDefinition:definition error:error];
	if (xml == nil) {
		return NO;
	}
	return [xml writeToURL:url atomically:YES encoding:NSUTF8StringEncoding
	                 error:error];
}

@end

#pragma mark - Reader

/* Children of a process or subprocess that carry no behaviour. */
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
			@"dataOutputAssociation", @"incoming", @"outgoing", nil];
	});
	return names;
}

@interface UDBpmnReadContext : NSObject
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *messages;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *errors;
@property (nonatomic, strong) NSDictionary<NSString *, NSXMLElement *> *shapes;
@property (nonatomic, copy) NSString *expressionLanguage;
@property (nonatomic, strong) NSError *error;
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
	NSMutableArray *processes = [NSMutableArray array];
	for (NSXMLElement *element in [self children:root of:UDBpmnNamespace]) {
		NSString *name = [element localName];
		NSString *elementId = [self attr:@"id" of:element];
		if ([name isEqualToString:@"message"] && elementId != nil) {
			[messages setObject:[self attr:@"name" of:element] ?: elementId
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
	for (NSXMLElement *element in [self children:scope of:UDBpmnNamespace]) {
		if (context.error != nil) {
			return;
		}
		NSString *name = [element localName];
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
		if ([self child:element named:@"multiInstanceLoopCharacteristics"] != nil
		    || [self child:element named:@"standardLoopCharacteristics"] != nil) {
			[self fail:context error:UDBpmnError(
				@"%@: loops and multi-instance are not supported yet", elementId)];
			return;
		}
		if (![self readNode:element name:name id:elementId into:builder context:context]) {
			return;
		}
		NSString *label = [self attr:@"name" of:element];
		if (label != nil) {
			[builder setName:label forElement:elementId];
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
		    && ![name isEqualToString:@"errorEventDefinition"]) {
			*unsupported = name;
			return nil;
		}
		found = child;
	}
	return found;
}

+ (NSTimeInterval)durationOf:(NSXMLElement *)timer
                          id:(NSString *)elementId
                     context:(UDBpmnReadContext *)context
{
	NSXMLElement *duration = [self child:timer named:@"timeDuration"];
	if (duration == nil) {
		[self fail:context error:UDBpmnError(
			@"%@: only timeDuration timers are supported yet, not timeDate or timeCycle",
			elementId)];
		return -1;
	}
	NSString *text = [self trimmed:[duration stringValue]];
	NSTimeInterval seconds = UDParseISODuration(text);
	if (seconds < 0) {
		[self fail:context error:UDBpmnError(
			@"%@: timer duration \"%@\" is not an ISO-8601 duration in weeks, days, hours, minutes or seconds",
			elementId, text)];
	}
	return seconds;
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

	if ([name isEqualToString:@"startEvent"]) {
		if (message) {
			NSString *messageName = [self messageNameOf:definition id:elementId context:context];
			[builder addMessageStart:elementId message:messageName];
		} else if (timer) {
			[builder addTimerStart:elementId
			              duration:[self durationOf:definition id:elementId context:context]];
		} else if (errorTrigger) {
			[self fail:context error:UDBpmnError(
				@"%@: error start events are not supported yet", elementId)];
		} else {
			[builder addStart:elementId];
		}
	} else if ([name isEqualToString:@"endEvent"]) {
		if (message) {
			[builder addMessageEnd:elementId
			               message:[self messageNameOf:definition id:elementId context:context]];
		} else if (definition != nil) {
			[self fail:context error:UDBpmnError(
				@"%@: error end events are not supported yet", elementId)];
		} else {
			[builder addEnd:elementId];
		}
	} else if ([name isEqualToString:@"intermediateCatchEvent"]) {
		if (message) {
			[builder addMessageCatch:elementId
			                 message:[self messageNameOf:definition id:elementId context:context]];
		} else if (timer) {
			[builder addTimerCatch:elementId
			              duration:[self durationOf:definition id:elementId context:context]];
		} else {
			[self fail:context error:UDBpmnError(
				@"%@: a catch event needs a message or timer", elementId)];
		}
	} else if ([name isEqualToString:@"intermediateThrowEvent"]) {
		if (message) {
			[builder addMessageThrow:elementId
			                 message:[self messageNameOf:definition id:elementId context:context]];
		} else if (definition == nil) {
			[builder addIntermediateThrow:elementId];
		} else {
			[self fail:context error:UDBpmnError(
				@"%@: only message and none throw events are supported", elementId)];
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
			[builder addBoundaryTimer:elementId
			                   onTask:host
			                 duration:[self durationOf:definition id:elementId context:context]
			             interrupting:interrupting];
		} else if (errorTrigger) {
			NSString *ref = [self attr:@"errorRef" of:definition];
			[builder addBoundaryError:elementId
			                   onTask:host
			                 errorRef:ref == nil ? nil
			                     : ([context.errors objectForKey:ref] ?: ref)
			             interrupting:YES];
		} else {
			[self fail:context error:UDBpmnError(
				@"%@: a boundary event needs a message, timer or error", elementId)];
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
	} else if ([name isEqualToString:@"subProcess"]) {
		if ([[self attr:@"triggeredByEvent" of:element] isEqualToString:@"true"]) {
			[self fail:context error:UDBpmnError(
				@"%@: event subprocesses are not supported yet", elementId)];
			return NO;
		}
		UDDefinitionBuilder *inner =
			[UDDefinitionBuilder process:elementId
			                        name:[self attr:@"name" of:element] ?: elementId];
		[self readScope:element into:inner context:context];
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
		[builder addSubProcess:elementId
		                  name:[self attr:@"name" of:element] ?: elementId
		                 inner:scope];
	} else {
		[self fail:context error:UDBpmnError(@"%@: %@ is not supported yet",
			elementId, name)];
		return NO;
	}
	return context.error == nil;
}

/*
 * A condition's language: `${...}` is the Camunda 7 expression syntax, a
 * leading `=` marks FEEL as Camunda 8 writes it, and otherwise the
 * expression's own language attribute or the document's
 * expressionLanguage decides. A document that names none is read as FEEL:
 * the specification's default, XPath, is not supported.
 */
+ (id<UDCondition>)conditionFrom:(NSXMLElement *)expression
                            flow:(NSString *)flowId
                         context:(UDBpmnReadContext *)context
{
	NSString *text = [self trimmed:[expression stringValue]];
	NSString *language = [self attr:@"language" of:expression] ?: context.expressionLanguage;
	if ([text hasPrefix:@"${"] && [text hasSuffix:@"}"]) {
		text = [text substringWithRange:NSMakeRange(2, [text length] - 3)];
	} else if ([text hasPrefix:@"="]) {
		text = [text substringFromIndex:1];
	} else if ([language isEqualToString:UDXPathLanguage]) {
		[self fail:context error:UDBpmnError(
			@"%@: XPath conditions are not supported", flowId)];
		return nil;
	}
	NSError *parseError = nil;
	UDComparisonCondition *condition =
		[UDComparisonCondition conditionWithExpression:text error:&parseError];
	if (condition == nil) {
		[self fail:context error:UDBpmnError(@"%@: condition \"%@\": %@",
			flowId, text, [parseError localizedDescription])];
	}
	return condition;
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

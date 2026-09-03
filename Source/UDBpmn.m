#import "UDBpmn.h"
#import "UDFlowElements.h"
#import "UDCondition.h"

NSString * const UDBpmnNamespace =
	@"http://www.omg.org/spec/BPMN/20100524/MODEL";
NSString * const UDBpmnExtensionNamespace =
	@"https://udworkflow.local/bpmn";

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
	s = [s stringByReplacingOccurrencesOfString:@"'" withString:@"&apos;"];
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

@implementation UDBpmnWriter

+ (NSString *)XMLStringFromDefinition:(UDProcessDefinition *)definition
                                error:(NSError **)error
{
	if (definition == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidBpmn
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"no definition to export" }];
		}
		return nil;
	}

	NSMutableString *xml = [NSMutableString string];
	[xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
	[xml appendFormat:
		@"<definitions xmlns=\"%@\" xmlns:ud=\"%@\" "
		 @"xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
		 @"targetNamespace=\"%@\" id=\"defs_%@\">\n",
		UDBpmnNamespace, UDBpmnExtensionNamespace,
		UDBpmnExtensionNamespace, UDEscapeXML(definition.processId)];
	[xml appendFormat:@"  <process id=\"%@\" name=\"%@\" isExecutable=\"true\""
		 @" ud:version=\"%ld\">\n",
		UDEscapeXML(definition.processId),
		UDEscapeXML(definition.name),
		(long)definition.version];

	NSArray *nodeIds = [[definition.nodes allKeys]
		sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *nodeId in nodeIds) {
		UDFlowNode *node = [definition nodeWithId:nodeId];
		NSString *fragment = [self elementXMLForNode:node
		                                  definition:definition
		                                       error:error];
		if (fragment == nil) {
			return nil;
		}
		[xml appendString:fragment];
	}

	for (NSString *flowId in definition.flowOrder) {
		UDSequenceFlow *flow = [definition flowWithId:flowId];
		NSString *fragment = [self elementXMLForFlow:flow error:error];
		if (fragment == nil) {
			return nil;
		}
		[xml appendString:fragment];
	}

	[xml appendString:@"  </process>\n</definitions>\n"];
	return xml;
}

+ (NSString *)elementXMLForNode:(UDFlowNode *)node
                     definition:(UDProcessDefinition *)definition
                          error:(NSError **)error
{
	NSString *tag = nil;
	NSMutableString *attrs = [NSMutableString string];
	[attrs appendString:UDAttr(@"id", node.elementId)];
	if (node.boundsWidth > 0 || node.boundsHeight > 0) {
		[attrs appendFormat:@" ud:x=\"%.1f\" ud:y=\"%.1f\" ud:w=\"%.1f\" ud:h=\"%.1f\"",
			node.boundsX, node.boundsY, node.boundsWidth, node.boundsHeight];
	}
	if (node.name != nil && ![node.name isEqualToString:node.elementId]) {
		[attrs appendString:UDAttr(@"name", node.name)];
	} else if (node.name != nil) {
		[attrs appendString:UDAttr(@"name", node.name)];
	}

	NSMutableString *body = [NSMutableString string];

	if ([node isKindOfClass:[UDEvent class]]) {
		UDEvent *event = (UDEvent *)node;
		switch (event.kind) {
		case UDEventKindStart:
			tag = @"startEvent";
			break;
		case UDEventKindEnd:
			tag = @"endEvent";
			break;
		case UDEventKindIntermediateCatch:
			tag = @"intermediateCatchEvent";
			break;
		case UDEventKindIntermediateThrow:
			tag = @"intermediateThrowEvent";
			break;
		case UDEventKindBoundary:
			tag = @"boundaryEvent";
			[attrs appendString:UDAttr(@"attachedToRef", event.attachedToId)];
			[attrs appendString:UDAttr(@"cancelActivity",
				event.isInterrupting ? @"true" : @"false")];
			break;
		}
		if (event.trigger == UDEventTriggerMessage) {
			[attrs appendString:UDAttr(@"ud:message", event.messageName)];
			[body appendFormat:@"      <messageEventDefinition messageRef=\"%@\"/>\n",
				UDEscapeXML(event.messageName)];
		} else if (event.trigger == UDEventTriggerError) {
			[attrs appendString:UDAttr(@"ud:error", event.errorRef)];
			[body appendFormat:@"      <errorEventDefinition errorRef=\"%@\"/>\n",
				UDEscapeXML(event.errorRef)];
		} else if (event.trigger == UDEventTriggerTimer) {
			[attrs appendFormat:@" ud:duration=\"%.3f\"", event.timerDuration];
			[body appendFormat:@"      <timerEventDefinition><timeDuration>PT%.3fS</timeDuration></timerEventDefinition>\n",
				event.timerDuration];
		}
	} else if ([node isKindOfClass:[UDTask class]]) {
		UDTask *task = (UDTask *)node;
		if (task.kind == UDTaskKindUser) {
			tag = @"userTask";
			if (task.assignee != nil) {
				[attrs appendString:UDAttr(@"ud:assignee", task.assignee)];
			}
		} else if (task.kind == UDTaskKindService) {
			tag = @"serviceTask";
			if (task.actionKey != nil) {
				[attrs appendString:UDAttr(@"implementation", task.actionKey)];
				[attrs appendString:UDAttr(@"ud:action", task.actionKey)];
			}
		} else {
			tag = @"scriptTask";
			if (task.actionKey != nil) {
				[attrs appendString:UDAttr(@"ud:action", task.actionKey)];
				[body appendFormat:@"      <script>%@</script>\n",
					UDEscapeXML(task.actionKey)];
			}
		}
	} else if ([node isKindOfClass:[UDGateway class]]) {
		UDGateway *gw = (UDGateway *)node;
		if (gw.kind == UDGatewayKindExclusive) {
			tag = @"exclusiveGateway";
			if (gw.defaultFlowId != nil) {
				[attrs appendString:UDAttr(@"default", gw.defaultFlowId)];
			}
		} else if (gw.kind == UDGatewayKindInclusive) {
			tag = @"inclusiveGateway";
			if (gw.defaultFlowId != nil) {
				[attrs appendString:UDAttr(@"default", gw.defaultFlowId)];
			}
		} else if (gw.kind == UDGatewayKindEventBased) {
			tag = @"eventBasedGateway";
		} else {
			tag = @"parallelGateway";
		}
	} else if ([node isKindOfClass:[UDSubProcess class]]) {
		tag = @"subProcess";
		UDSubProcess *sub = (UDSubProcess *)node;
		if (sub.innerDefinition.processId != nil) {
			[attrs appendString:UDAttr(@"ud:inner", sub.innerDefinition.processId)];
		}
	} else {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidBpmn
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"unsupported node for BPMN export" }];
		}
		return nil;
	}

	for (NSString *flowId in node.incomingFlowIds) {
		[body appendFormat:@"      <incoming>%@</incoming>\n",
			UDEscapeXML(flowId)];
	}
	for (NSString *flowId in node.outgoingFlowIds) {
		[body appendFormat:@"      <outgoing>%@</outgoing>\n",
			UDEscapeXML(flowId)];
	}

	(void)definition;
	if ([body length] == 0) {
		return [NSString stringWithFormat:@"    <%@%@/>\n", tag, attrs];
	}
	return [NSString stringWithFormat:@"    <%@%@>\n%@    </%@>\n",
		tag, attrs, body, tag];
}

+ (NSString *)elementXMLForFlow:(UDSequenceFlow *)flow error:(NSError **)error
{
	NSMutableString *attrs = [NSMutableString string];
	[attrs appendString:UDAttr(@"id", flow.elementId)];
	[attrs appendString:UDAttr(@"sourceRef", flow.sourceId)];
	[attrs appendString:UDAttr(@"targetRef", flow.targetId)];
	if (flow.name != nil && ![flow.name isEqualToString:flow.elementId]) {
		[attrs appendString:UDAttr(@"name", flow.name)];
	}

	id cond = flow.condition;
	if (cond == nil) {
		return [NSString stringWithFormat:@"    <sequenceFlow%@/>\n", attrs];
	}
	if (![cond isKindOfClass:[UDComparisonCondition class]]) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidBpmn
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"only comparison conditions export to BPMN" }];
		}
		return nil;
	}
	NSString *expr = [cond expressionString];
	return [NSString stringWithFormat:
		@"    <sequenceFlow%@>\n"
		 @"      <conditionExpression xsi:type=\"tFormalExpression\">%@</conditionExpression>\n"
		 @"    </sequenceFlow>\n",
		attrs, UDEscapeXML(expr)];
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

@interface UDBpmnParseState : NSObject
@property (nonatomic, copy) NSString *processId;
@property (nonatomic, copy) NSString *processName;
@property (nonatomic) NSInteger version;
@property (nonatomic, strong) UDDefinitionBuilder *builder;
@property (nonatomic, copy) NSString *element;
@property (nonatomic, copy) NSString *elementId;
@property (nonatomic, copy) NSString *sourceRef;
@property (nonatomic, copy) NSString *targetRef;
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, strong) NSError *error;
@end

@implementation UDBpmnParseState
@end

@interface UDBpmnParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) UDBpmnParseState *state;
@end

@implementation UDBpmnParser

- (NSString *)localName:(NSString *)qName
{
	NSRange colon = [qName rangeOfString:@":" options:NSBackwardsSearch];
	if (colon.location == NSNotFound) {
		return qName;
	}
	return [qName substringFromIndex:colon.location + 1];
}

- (NSString *)attr:(NSString *)name
        attributes:(NSDictionary *)attributes
{
	NSString *value = [attributes objectForKey:name];
	if (value != nil) {
		return value;
	}
	NSString *ud = [NSString stringWithFormat:@"ud:%@", name];
	value = [attributes objectForKey:ud];
	if (value != nil) {
		return value;
	}
	for (NSString *key in attributes) {
		if ([[self localName:key] isEqualToString:name]) {
			return [attributes objectForKey:key];
		}
	}
	return nil;
}

- (void)fail:(NSString *)message
{
	if (self.state.error != nil) {
		return;
	}
	self.state.error = [NSError errorWithDomain:UDWorkflowErrorDomain
	                                       code:UDWorkflowErrorInvalidBpmn
	                                   userInfo:@{ NSLocalizedDescriptionKey: message }];
}

- (void)parser:(NSXMLParser *)parser
didStartElement:(NSString *)elementName
   namespaceURI:(NSString *)namespaceURI
  qualifiedName:(NSString *)qName
     attributes:(NSDictionary *)attributes
{
	(void)parser;
	(void)namespaceURI;
	(void)qName;
	NSString *name = [self localName:elementName];
	self.state.text = [NSMutableString string];
	self.state.element = name;

	if ([name isEqualToString:@"process"]) {
		self.state.processId = [self attr:@"id" attributes:attributes];
		self.state.processName = [self attr:@"name" attributes:attributes];
		NSString *version = [self attr:@"version" attributes:attributes];
		self.state.version = version ? [version integerValue] : 1;
		if (self.state.processId == nil) {
			[self fail:@"process missing id"];
			return;
		}
		self.state.builder =
			[UDDefinitionBuilder process:self.state.processId
			                        name:self.state.processName ?: self.state.processId
			                     version:self.state.version];
		return;
	}

	if (self.state.builder == nil) {
		return;
	}

	NSString *elementId = [self attr:@"id" attributes:attributes];
	NSString *label = [self attr:@"name" attributes:attributes];
	if (label == nil) {
		label = elementId;
	}

	if ([name isEqualToString:@"startEvent"] && elementId != nil) {
		NSString *message = [self attr:@"message" attributes:attributes];
		NSString *duration = [self attr:@"duration" attributes:attributes];
		if (message != nil) {
			[self.state.builder addMessageStart:elementId message:message];
		} else if (duration != nil) {
			[self.state.builder addTimerStart:elementId duration:[duration doubleValue]];
		} else {
			[self.state.builder addStart:elementId];
		}
	} else if ([name isEqualToString:@"endEvent"] && elementId != nil) {
		NSString *message = [self attr:@"message" attributes:attributes];
		if (message != nil) {
			[self.state.builder addMessageEnd:elementId message:message];
		} else {
			[self.state.builder addEnd:elementId];
		}
	} else if ([name isEqualToString:@"intermediateCatchEvent"] && elementId != nil) {
		NSString *message = [self attr:@"message" attributes:attributes];
		NSString *duration = [self attr:@"duration" attributes:attributes];
		if (message != nil) {
			[self.state.builder addMessageCatch:elementId message:message];
		} else {
			[self.state.builder addTimerCatch:elementId
			                         duration:duration ? [duration doubleValue] : 0];
		}
	} else if ([name isEqualToString:@"intermediateThrowEvent"] && elementId != nil) {
		NSString *message = [self attr:@"message" attributes:attributes];
		[self.state.builder addMessageThrow:elementId message:message ?: elementId];
	} else if ([name isEqualToString:@"boundaryEvent"] && elementId != nil) {
		NSString *host = [self attr:@"attachedToRef" attributes:attributes];
		NSString *cancel = [self attr:@"cancelActivity" attributes:attributes];
		BOOL interrupting = (cancel == nil) || [cancel isEqualToString:@"true"];
		NSString *message = [self attr:@"message" attributes:attributes];
		NSString *duration = [self attr:@"duration" attributes:attributes];
		NSString *err = [self attr:@"error" attributes:attributes];
		if (err != nil) {
			[self.state.builder addBoundaryError:elementId
			                             onTask:host
			                           errorRef:err
			                       interrupting:interrupting];
		} else if (message != nil) {
			[self.state.builder addBoundaryMessage:elementId
			                               onTask:host
			                              message:message
			                         interrupting:interrupting];
		} else {
			[self.state.builder addBoundaryTimer:elementId
			                             onTask:host
			                           duration:duration ? [duration doubleValue] : 0
			                       interrupting:interrupting];
		}
	} else if ([name isEqualToString:@"inclusiveGateway"] && elementId != nil) {
		[self.state.builder addInclusive:elementId
		                     defaultFlow:[self attr:@"default" attributes:attributes]];
	} else if ([name isEqualToString:@"eventBasedGateway"] && elementId != nil) {
		[self.state.builder addEventBased:elementId];
	} else if ([name isEqualToString:@"userTask"] && elementId != nil) {
		NSString *assignee = [self attr:@"assignee" attributes:attributes];
		[self.state.builder addUserTask:elementId name:label assignee:assignee];
	} else if ([name isEqualToString:@"serviceTask"] && elementId != nil) {
		NSString *action = [self attr:@"action" attributes:attributes];
		if (action == nil) {
			action = [self attr:@"implementation" attributes:attributes];
		}
		[self.state.builder addServiceTask:elementId action:action];
	} else if ([name isEqualToString:@"scriptTask"] && elementId != nil) {
		NSString *action = [self attr:@"action" attributes:attributes];
		[self.state.builder addScriptTask:elementId action:action ?: elementId];
	} else if ([name isEqualToString:@"exclusiveGateway"] && elementId != nil) {
		NSString *defFlow = [self attr:@"default" attributes:attributes];
		[self.state.builder addExclusive:elementId defaultFlow:defFlow];
	} else if ([name isEqualToString:@"parallelGateway"] && elementId != nil) {
		[self.state.builder addParallel:elementId];
	} else if ([name isEqualToString:@"sequenceFlow"]) {
		self.state.elementId = elementId;
		self.state.sourceRef = [self attr:@"sourceRef" attributes:attributes];
		self.state.targetRef = [self attr:@"targetRef" attributes:attributes];
	}
	if (elementId != nil && self.state.builder != nil) {
		NSString *x = [self attr:@"x" attributes:attributes];
		NSString *y = [self attr:@"y" attributes:attributes];
		NSString *w = [self attr:@"w" attributes:attributes];
		NSString *h = [self attr:@"h" attributes:attributes];
		if (w != nil || h != nil) {
			[self.state.builder setBoundsFor:elementId
			                               x:[x doubleValue]
			                               y:[y doubleValue]
			                           width:[w doubleValue]
			                          height:[h doubleValue]];
		}
	}
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	(void)parser;
	[self.state.text appendString:string];
}

- (void)parser:(NSXMLParser *)parser
 didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
{
	(void)parser;
	(void)namespaceURI;
	(void)qName;
	NSString *name = [self localName:elementName];
	if ([name isEqualToString:@"script"] && self.state.elementId == nil) {
		/* script body already represented by ud:action when present */
	}
	if ([name isEqualToString:@"sequenceFlow"]) {
		if (self.state.sourceRef == nil || self.state.targetRef == nil) {
			[self fail:@"sequenceFlow missing source or target"];
			self.state.elementId = nil;
			self.state.sourceRef = nil;
			self.state.targetRef = nil;
			self.state.element = nil;
			return;
		}
		id<UDCondition> condition = nil;
		NSString *expr = [self.state.text
			stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([expr length] > 0) {
			NSError *condError = nil;
			condition = [UDComparisonCondition conditionWithExpression:expr
			                                                     error:&condError];
			if (condition == nil) {
				self.state.error = condError;
			}
		}
		[self.state.builder connect:self.state.sourceRef
		                         to:self.state.targetRef
		                     flowId:self.state.elementId
		                  condition:condition];
		self.state.elementId = nil;
		self.state.sourceRef = nil;
		self.state.targetRef = nil;
	}
	if ([name isEqualToString:@"conditionExpression"]) {
		/* text kept until sequenceFlow ends */
		return;
	}
	self.state.element = nil;
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	(void)parser;
	if (self.state.error == nil) {
		self.state.error = parseError;
	}
}

@end

@implementation UDBpmnReader

+ (UDProcessDefinition *)definitionFromXMLString:(NSString *)xml
                                           error:(NSError **)error
{
	if (xml == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidBpmn
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"empty BPMN document" }];
		}
		return nil;
	}
	NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
	NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
	UDBpmnParser *delegate = [[UDBpmnParser alloc] init];
	delegate.state = [[UDBpmnParseState alloc] init];
	[parser setDelegate:delegate];
	[parser setShouldProcessNamespaces:YES];
	if (![parser parse]) {
		if (error != NULL) {
			*error = delegate.state.error ?: [parser parserError];
		}
		return nil;
	}
	if (delegate.state.error != nil) {
		if (error != NULL) {
			*error = delegate.state.error;
		}
		return nil;
	}
	if (delegate.state.builder == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidBpmn
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"no process element" }];
		}
		return nil;
	}
	return [delegate.state.builder build:error];
}

+ (UDProcessDefinition *)definitionFromURL:(NSURL *)url
                                     error:(NSError **)error
{
	NSString *xml = [NSString stringWithContentsOfURL:url
	                                         encoding:NSUTF8StringEncoding
	                                            error:error];
	if (xml == nil) {
		return nil;
	}
	return [self definitionFromXMLString:xml error:error];
}

@end

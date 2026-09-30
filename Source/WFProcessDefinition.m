#import "WFProcessDefinition.h"
#import "WFProcessDefinition+Repository.h"
#import "WFFlowElements.h"
#import "WFDuration.h"
#import "WFFeelInternal.h"

@interface WFFlowNode (WFBuilderAccess)
- (void)addIncomingFlowId:(NSString *)flowId;
- (void)addOutgoingFlowId:(NSString *)flowId;
- (void)setName:(NSString *)name;
- (void)setAsyncBefore:(BOOL)asyncBefore;
- (void)setAsyncAfter:(BOOL)asyncAfter;
- (void)setExclusive:(BOOL)exclusive;
- (void)setRetryTimeCycle:(NSString *)cycle;
- (void)setTaskPriority:(NSNumber *)priority;
- (void)setMultiInstance:(WFMultiInstance *)multiInstance;
- (void)setForCompensation:(BOOL)forCompensation;
- (void)addInputParameter:(WFParameter *)parameter;
- (void)addOutputParameter:(WFParameter *)parameter;
@end

@interface WFTask (WFBuilderAccess)
- (void)setDecisionRef:(NSString *)decisionRef;
- (void)setDecisionBinding:(WFCalledElementBinding)binding;
- (void)setDecisionVersion:(NSInteger)version;
- (void)setResultVariable:(NSString *)resultVariable;
- (void)setMapDecisionResult:(WFDecisionResultMapping)mapping;
- (void)setAssigneeExpression:(WFFeelExpression *)expression;
- (void)setCandidateUsers:(WFFeelExpression *)expression;
- (void)setCandidateGroups:(WFFeelExpression *)expression;
- (void)setDueDate:(WFFeelExpression *)expression;
- (void)setFollowUpDate:(WFFeelExpression *)expression;
- (void)setPriority:(WFFeelExpression *)expression;
@end

@interface WFEvent (WFBuilderAccess)
- (void)setInterrupting:(BOOL)interrupting;
- (void)setTimer:(WFTimer *)timer;
- (void)setCodeVariable:(NSString *)name;
- (void)wf_setMessageName:(NSString *)name;
- (void)wf_setCondition:(WFEventCondition *)condition;
@end

@interface WFSubProcess (WFBuilderAccess)
- (void)setTriggeredByEvent:(BOOL)triggeredByEvent;
@end

@interface WFCallActivity (WFBuilderAccess)
- (void)setBinding:(WFCalledElementBinding)binding;
- (void)setCalledElementVersion:(NSInteger)version;
- (void)addInput:(WFVariableMapping *)mapping;
- (void)addOutput:(WFVariableMapping *)mapping;
@end

@interface WFProcessDefinition ()
@property (nonatomic, readwrite) NSInteger version;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *deploymentId;
@property (nonatomic, readwrite, copy) NSString *resourceName;
@property (nonatomic, readwrite, strong) NSNumber *defaultTaskPriority;
@property (nonatomic, readwrite, strong) NSNumber *historyTimeToLive;
/* Node id to @[node, scope definition], for the whole tree. */
@property (nonatomic, strong) NSDictionary *nodeIndex;
- (instancetype)initWithProcessId:(NSString *)processId
                             name:(NSString *)name
                          version:(NSInteger)version
                            nodes:(NSDictionary *)nodes
                            flows:(NSDictionary *)flows
                        flowOrder:(NSArray *)flowOrder;
@end

@implementation WFProcessDefinition

- (instancetype)initWithProcessId:(NSString *)processId
                             name:(NSString *)name
                          version:(NSInteger)version
                            nodes:(NSDictionary *)nodes
                            flows:(NSDictionary *)flows
                        flowOrder:(NSArray *)flowOrder
{
	self = [super init];
	if (self) {
		_processId = [processId copy];
		_name = [name copy];
		_version = version;
		_nodes = [nodes copy];
		_flows = [flows copy];
		_flowOrder = [flowOrder copy];
		NSMutableDictionary *index = [NSMutableDictionary dictionary];
		for (WFFlowNode *node in [_nodes allValues]) {
			/* The scope is held unretained: this definition owns the index,
			 * and each subprocess node owns its inner definition. */
			[index setObject:@[ node, [NSValue valueWithNonretainedObject:self] ]
			          forKey:node.elementId];
			if ([node isKindOfClass:[WFSubProcess class]]) {
				[index addEntriesFromDictionary:
					[[(WFSubProcess *)node innerDefinition] nodeIndex]];
			}
		}
		_nodeIndex = index;
	}
	return self;
}

- (WFFlowNode *)flowNodeWithId:(NSString *)elementId
{
	return elementId == nil ? nil : [[self.nodeIndex objectForKey:elementId] objectAtIndex:0];
}

- (WFProcessDefinition *)scopeOfFlowNode:(NSString *)elementId
{
	return elementId == nil ? nil
		: [[[self.nodeIndex objectForKey:elementId] objectAtIndex:1] nonretainedObjectValue];
}

- (WFProcessDefinition *)wf_deployedCopyWithVersion:(NSInteger)version
                                        definitionId:(NSString *)definitionId
                                        deploymentId:(NSString *)deploymentId
                                        resourceName:(NSString *)resourceName
{
	/* Nodes and flows are immutable once built, so the copy shares them. */
	WFProcessDefinition *copy =
		[[WFProcessDefinition alloc] initWithProcessId:self.processId
		                                          name:self.name
		                                       version:version
		                                         nodes:self.nodes
		                                         flows:self.flows
		                                     flowOrder:self.flowOrder];
	copy.definitionId = definitionId;
	copy.deploymentId = deploymentId;
	copy.resourceName = resourceName;
	copy.defaultTaskPriority = self.defaultTaskPriority;
	copy.historyTimeToLive = self.historyTimeToLive;
	return copy;
}

- (WFEvent *)startEvent
{
	for (WFFlowNode *node in [self.nodes allValues]) {
		if ([node isKindOfClass:[WFEvent class]]
		    && [(WFEvent *)node kind] == WFEventKindStart) {
			return (WFEvent *)node;
		}
	}
	return nil;
}

- (WFFlowNode *)nodeWithId:(NSString *)elementId
{
	return [self.nodes objectForKey:elementId];
}

- (WFSequenceFlow *)flowWithId:(NSString *)flowId
{
	return [self.flows objectForKey:flowId];
}

- (NSArray<WFSequenceFlow *> *)outgoingFlowsFrom:(NSString *)nodeId
{
	NSMutableArray *result = [NSMutableArray array];
	WFFlowNode *node = [self nodeWithId:nodeId];
	for (NSString *flowId in node.outgoingFlowIds) {
		WFSequenceFlow *flow = [self flowWithId:flowId];
		if (flow != nil) {
			[result addObject:flow];
		}
	}
	return result;
}

- (NSArray<WFSequenceFlow *> *)incomingFlowsTo:(NSString *)nodeId
{
	NSMutableArray *result = [NSMutableArray array];
	WFFlowNode *node = [self nodeWithId:nodeId];
	for (NSString *flowId in node.incomingFlowIds) {
		WFSequenceFlow *flow = [self flowWithId:flowId];
		if (flow != nil) {
			[result addObject:flow];
		}
	}
	return result;
}

- (NSArray *)boundaryEventsAttachedTo:(NSString *)taskId
{
	NSMutableArray *result = [NSMutableArray array];
	for (WFFlowNode *node in [self.nodes allValues]) {
		if (![node isKindOfClass:[WFEvent class]]) {
			continue;
		}
		WFEvent *event = (WFEvent *)node;
		if (event.kind == WFEventKindBoundary
		    && [event.attachedToId isEqualToString:taskId]) {
			[result addObject:event];
		}
	}
	return result;
}

@end

@interface WFDefinitionBuilder ()
@property (nonatomic, copy) NSString *processId;
@property (nonatomic, copy) NSString *processName;
@property (nonatomic, strong) NSNumber *processTaskPriority;
@property (nonatomic, strong) NSNumber *processTimeToLive;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WFFlowNode *> *nodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WFSequenceFlow *> *flows;
@property (nonatomic, strong) NSMutableArray<NSString *> *flowOrder;
@property (nonatomic) NSUInteger flowSerial;
/* The first thing added wrongly, which -build: reports. */
@property (nonatomic, strong) NSError *firstError;
/* Activities compensation boundary events name, made handlers at -build:. */
@property (nonatomic, strong) NSMutableSet<NSString *> *compensationHandlers;
@end

@implementation WFDefinitionBuilder

+ (instancetype)process:(NSString *)processId
{
	return [self process:processId name:processId];
}

+ (instancetype)process:(NSString *)processId name:(NSString *)name
{
	WFDefinitionBuilder *builder = [[self alloc] init];
	builder.processId = processId;
	builder.processName = name;
	builder.nodes = [NSMutableDictionary dictionary];
	builder.flows = [NSMutableDictionary dictionary];
	builder.flowOrder = [NSMutableArray array];
	builder.compensationHandlers = [NSMutableSet set];
	builder.flowSerial = 0;
	return builder;
}

- (instancetype)addNode:(WFFlowNode *)node
{
	if (node.elementId != nil) {
		[self.nodes setObject:node forKey:node.elementId];
	}
	return self;
}

- (instancetype)addEvent:(NSString *)elementId
                    kind:(WFEventKind)kind
                 trigger:(WFEventTrigger)trigger
             messageName:(NSString *)messageName
                   timer:(WFTimer *)timer
            attachedToId:(NSString *)attachedToId
                errorRef:(NSString *)errorRef
            interrupting:(BOOL)interrupting
{
	WFEvent *event = [[WFEvent alloc] initWithElementId:elementId
	                                               name:elementId
	                                               kind:kind
	                                            trigger:trigger
	                                        messageName:messageName
	                                              timer:timer
	                                       attachedToId:attachedToId
	                                           errorRef:errorRef
	                                       interrupting:interrupting];
	return [self addNode:event];
}

- (instancetype)addStart:(NSString *)elementId
{
	return [self addEvent:elementId kind:WFEventKindStart trigger:WFEventTriggerNone
	          messageName:nil timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addMessageStart:(NSString *)elementId message:(NSString *)messageName
{
	return [self addEvent:elementId kind:WFEventKindStart trigger:WFEventTriggerMessage
	          messageName:messageName timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addTimerStart:(NSString *)elementId duration:(NSTimeInterval)duration
{
	return [self addEvent:elementId kind:WFEventKindStart trigger:WFEventTriggerTimer
	          messageName:nil timer:[WFTimer duration:duration] attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addEnd:(NSString *)elementId
{
	return [self addEvent:elementId kind:WFEventKindEnd trigger:WFEventTriggerNone
	          messageName:nil timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addMessageEnd:(NSString *)elementId message:(NSString *)messageName
{
	return [self addEvent:elementId kind:WFEventKindEnd trigger:WFEventTriggerMessage
	          messageName:messageName timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addMessageCatch:(NSString *)elementId message:(NSString *)messageName
{
	return [self addEvent:elementId kind:WFEventKindIntermediateCatch
	              trigger:WFEventTriggerMessage messageName:messageName
	        timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addTimerCatch:(NSString *)elementId duration:(NSTimeInterval)duration
{
	return [self addEvent:elementId kind:WFEventKindIntermediateCatch
	              trigger:WFEventTriggerTimer messageName:nil
	        timer:[WFTimer duration:duration] attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addMessageThrow:(NSString *)elementId message:(NSString *)messageName
{
	return [self addEvent:elementId kind:WFEventKindIntermediateThrow
	              trigger:WFEventTriggerMessage messageName:messageName
	        timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addSignalStart:(NSString *)elementId signal:(NSString *)signalName
{
	return [self addEvent:elementId kind:WFEventKindStart trigger:WFEventTriggerSignal
	          messageName:signalName timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addSignalCatch:(NSString *)elementId signal:(NSString *)signalName
{
	return [self addEvent:elementId kind:WFEventKindIntermediateCatch trigger:WFEventTriggerSignal
	          messageName:signalName timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addSignalThrow:(NSString *)elementId signal:(NSString *)signalName
{
	return [self addEvent:elementId kind:WFEventKindIntermediateThrow trigger:WFEventTriggerSignal
	          messageName:signalName timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addSignalEnd:(NSString *)elementId signal:(NSString *)signalName
{
	return [self addEvent:elementId kind:WFEventKindEnd trigger:WFEventTriggerSignal
	          messageName:signalName timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addBoundarySignal:(NSString *)elementId
                           onTask:(NSString *)taskId
                           signal:(NSString *)signalName
                     interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:WFEventKindBoundary trigger:WFEventTriggerSignal
	          messageName:signalName timer:nil attachedToId:taskId errorRef:nil
	         interrupting:interrupting];
}

- (instancetype)addTerminateEnd:(NSString *)elementId
{
	return [self addEvent:elementId kind:WFEventKindEnd trigger:WFEventTriggerTerminate
	          messageName:nil timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addIntermediateThrow:(NSString *)elementId
{
	return [self addEvent:elementId kind:WFEventKindIntermediateThrow
	              trigger:WFEventTriggerNone messageName:nil
	        timer:nil attachedToId:nil errorRef:nil
	         interrupting:NO];
}

- (instancetype)addBoundaryMessage:(NSString *)elementId
                            onTask:(NSString *)taskId
                           message:(NSString *)messageName
                      interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:WFEventKindBoundary
	              trigger:WFEventTriggerMessage messageName:messageName
	        timer:nil attachedToId:taskId errorRef:nil interrupting:interrupting];
}

- (instancetype)addBoundaryTimer:(NSString *)elementId
                          onTask:(NSString *)taskId
                        duration:(NSTimeInterval)duration
                    interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:WFEventKindBoundary
	              trigger:WFEventTriggerTimer messageName:nil
	        timer:[WFTimer duration:duration] attachedToId:taskId errorRef:nil interrupting:interrupting];
}

- (instancetype)addUserTask:(NSString *)elementId
                       name:(NSString *)name
                   assignee:(NSString *)assignee
{
	WFTask *task = [[WFTask alloc] initWithElementId:elementId
	                                            name:name
	                                            kind:WFTaskKindUser
	                                       actionKey:nil
	                                        assignee:assignee];
	return [self addNode:task];
}

- (instancetype)addServiceTask:(NSString *)elementId
                        action:(NSString *)actionKey
{
	WFTask *task = [[WFTask alloc] initWithElementId:elementId
	                                            name:elementId
	                                            kind:WFTaskKindService
	                                       actionKey:actionKey
	                                        assignee:nil];
	return [self addNode:task];
}

- (instancetype)addScriptTask:(NSString *)elementId
                       action:(NSString *)actionKey
{
	WFTask *task = [[WFTask alloc] initWithElementId:elementId
	                                            name:elementId
	                                            kind:WFTaskKindScript
	                                       actionKey:actionKey
	                                        assignee:nil];
	return [self addNode:task];
}

- (instancetype)addTask:(NSString *)elementId kind:(WFTaskKind)kind actionKey:(NSString *)actionKey
{
	return [self addNode:[[WFTask alloc] initWithElementId:elementId
	                                                  name:elementId
	                                                  kind:kind
	                                             actionKey:actionKey
	                                              assignee:nil]];
}

- (instancetype)addSendTask:(NSString *)elementId action:(NSString *)topic
{
	return [self addTask:elementId kind:WFTaskKindSend actionKey:topic];
}

- (instancetype)addBusinessRuleTask:(NSString *)elementId action:(NSString *)topic
{
	return [self addTask:elementId kind:WFTaskKindBusinessRule actionKey:topic];
}

- (instancetype)addBusinessRuleTask:(NSString *)elementId
                           decision:(NSString *)decisionRef
                     resultVariable:(NSString *)resultVariable
                            mapping:(WFDecisionResultMapping)mapping
{
	[self addTask:elementId kind:WFTaskKindBusinessRule actionKey:nil];
	WFTask *task = (WFTask *)[self.nodes objectForKey:elementId];
	[task setDecisionRef:decisionRef];
	[task setResultVariable:resultVariable];
	[task setMapDecisionResult:mapping];
	return self;
}

- (instancetype)setDecisionBinding:(WFCalledElementBinding)binding
                           version:(NSInteger)version
                        forElement:(NSString *)elementId
{
	WFTask *task = (WFTask *)[self.nodes objectForKey:elementId];
	if ([task isKindOfClass:[WFTask class]]) {
		[task setDecisionBinding:binding];
		[task setDecisionVersion:binding == WFCalledElementBindingVersion ? version : 0];
	}
	return self;
}

- (instancetype)addReceiveTask:(NSString *)elementId message:(NSString *)messageName
{
	return [self addTask:elementId kind:WFTaskKindReceive actionKey:messageName];
}

- (instancetype)addManualTask:(NSString *)elementId
{
	return [self addTask:elementId kind:WFTaskKindManual actionKey:nil];
}

- (instancetype)addTask:(NSString *)elementId
{
	return [self addTask:elementId kind:WFTaskKindNone actionKey:nil];
}

- (instancetype)addLinkThrow:(NSString *)elementId link:(NSString *)linkName
{
	return [self addEvent:elementId kind:WFEventKindIntermediateThrow trigger:WFEventTriggerLink
	          messageName:linkName timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addLinkCatch:(NSString *)elementId link:(NSString *)linkName
{
	return [self addEvent:elementId kind:WFEventKindIntermediateCatch trigger:WFEventTriggerLink
	          messageName:linkName timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addConditional:(NSString *)elementId
                          kind:(WFEventKind)kind
                        onTask:(NSString *)taskId
                     condition:(NSString *)condition
                  interrupting:(BOOL)interrupting
{
	[self addEvent:elementId kind:kind trigger:WFEventTriggerConditional messageName:nil timer:nil
	  attachedToId:taskId errorRef:nil interrupting:interrupting];
	WFFeelExpression *expression = [self feel:condition];
	if (expression == nil) {
		return self;
	}
	return [self setCondition:[[WFEventCondition alloc] initWithExpression:expression
	                                                         variableName:nil
	                                                       variableEvents:nil]
	               forElement:elementId];
}

- (instancetype)addConditionalStart:(NSString *)elementId condition:(NSString *)condition
{
	return [self addConditional:elementId kind:WFEventKindStart onTask:nil condition:condition
	               interrupting:YES];
}

- (instancetype)addConditionalCatch:(NSString *)elementId condition:(NSString *)condition
{
	return [self addConditional:elementId kind:WFEventKindIntermediateCatch onTask:nil
	                  condition:condition interrupting:YES];
}

- (instancetype)addBoundaryConditional:(NSString *)elementId
                                onTask:(NSString *)taskId
                             condition:(NSString *)condition
                          interrupting:(BOOL)interrupting
{
	return [self addConditional:elementId kind:WFEventKindBoundary onTask:taskId condition:condition
	               interrupting:interrupting];
}

- (instancetype)setCondition:(WFEventCondition *)condition forElement:(NSString *)elementId
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	if ([node isKindOfClass:[WFEvent class]]) {
		[(WFEvent *)node wf_setCondition:condition];
	}
	return self;
}

- (instancetype)addExclusive:(NSString *)elementId
                 defaultFlow:(NSString *)defaultFlowId
{
	WFGateway *gw = [[WFGateway alloc] initWithElementId:elementId
	                                                name:elementId
	                                                kind:WFGatewayKindExclusive
	                                       defaultFlowId:defaultFlowId];
	return [self addNode:gw];
}

- (instancetype)addParallel:(NSString *)elementId
{
	WFGateway *gw = [[WFGateway alloc] initWithElementId:elementId
	                                                name:elementId
	                                                kind:WFGatewayKindParallel
	                                       defaultFlowId:nil];
	return [self addNode:gw];
}

- (instancetype)addInclusive:(NSString *)elementId
                 defaultFlow:(NSString *)defaultFlowId
{
	WFGateway *gw = [[WFGateway alloc] initWithElementId:elementId
	                                                name:elementId
	                                                kind:WFGatewayKindInclusive
	                                       defaultFlowId:defaultFlowId];
	return [self addNode:gw];
}

- (instancetype)addEventBased:(NSString *)elementId
{
	WFGateway *gw = [[WFGateway alloc] initWithElementId:elementId
	                                                name:elementId
	                                                kind:WFGatewayKindEventBased
	                                       defaultFlowId:nil];
	return [self addNode:gw];
}

- (instancetype)addSubProcess:(NSString *)elementId
                         name:(NSString *)name
                        inner:(WFProcessDefinition *)inner
{
	WFSubProcess *node = [[WFSubProcess alloc] initWithElementId:elementId
	                                                        name:name
	                                            innerDefinition:inner];
	return [self addNode:node];
}

- (instancetype)addCallActivity:(NSString *)elementId
                  calledElement:(NSString *)processKey
{
	WFCallActivity *node = [[WFCallActivity alloc] initWithElementId:elementId
	                                                            name:elementId
	                                                   calledElement:processKey];
	return [self addNode:node];
}

- (WFCallActivity *)callActivity:(NSString *)elementId
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	return [node isKindOfClass:[WFCallActivity class]] ? (WFCallActivity *)node : nil;
}

- (instancetype)setBinding:(WFCalledElementBinding)binding
                   version:(NSInteger)version
                forElement:(NSString *)elementId
{
	WFCallActivity *node = [self callActivity:elementId];
	[node setBinding:binding];
	[node setCalledElementVersion:binding == WFCalledElementBindingVersion ? version : 0];
	return self;
}

- (instancetype)addInput:(WFVariableMapping *)mapping forElement:(NSString *)elementId
{
	[[self callActivity:elementId] addInput:mapping];
	return self;
}

- (instancetype)addOutput:(WFVariableMapping *)mapping forElement:(NSString *)elementId
{
	[[self callActivity:elementId] addOutput:mapping];
	return self;
}

- (instancetype)addEventSubProcess:(NSString *)elementId
                              name:(NSString *)name
                             inner:(WFProcessDefinition *)inner
{
	WFSubProcess *node = [[WFSubProcess alloc] initWithElementId:elementId
	                                                        name:name
	                                            innerDefinition:inner];
	[node setTriggeredByEvent:YES];
	return [self addNode:node];
}

- (instancetype)addErrorStart:(NSString *)elementId errorRef:(NSString *)errorRef
{
	return [self addEvent:elementId kind:WFEventKindStart trigger:WFEventTriggerError
	          messageName:errorRef timer:nil attachedToId:nil errorRef:errorRef interrupting:YES];
}

- (instancetype)addErrorEnd:(NSString *)elementId errorRef:(NSString *)errorRef
{
	return [self addEvent:elementId kind:WFEventKindEnd trigger:WFEventTriggerError
	          messageName:nil timer:nil attachedToId:nil errorRef:errorRef interrupting:YES];
}

- (instancetype)setAssignment:(NSDictionary<NSString *, NSString *> *)attributes
                   forElement:(NSString *)elementId
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	if (![node isKindOfClass:[WFTask class]] || [(WFTask *)node kind] != WFTaskKindUser) {
		self.firstError = self.firstError ?: [NSError errorWithDomain:WFErrorDomain
			code:WFErrorInvalidDefinition userInfo:@{ NSLocalizedDescriptionKey:
				[NSString stringWithFormat:@"%@: only a user task has an assignment", elementId] }];
		return self;
	}
	WFTask *task = (WFTask *)node;
	NSDictionary *kinds = @{ @"assignee": @(WFAttributeKindString), @"candidateUsers": @(WFAttributeKindList),
		@"candidateGroups": @(WFAttributeKindList), @"dueDate": @(WFAttributeKindDate),
		@"followUpDate": @(WFAttributeKindDate), @"priority": @(WFAttributeKindNumber) };
	for (NSString *key in attributes) {
		NSNumber *kind = [kinds objectForKey:key];
		NSError *error = nil;
		WFFeelExpression *expression = kind != nil
			? WFAttributeExpression([attributes objectForKey:key], (WFAttributeKind)[kind integerValue], &error)
			: nil;
		if (expression == nil) {
			self.firstError = self.firstError ?: [NSError errorWithDomain:WFErrorDomain
				code:WFErrorInvalidDefinition userInfo:@{ NSLocalizedDescriptionKey:
					[NSString stringWithFormat:@"%@: %@: %@", elementId, key,
						kind == nil ? @"not an assignment attribute" : [error localizedDescription]] }];
			continue;
		}
		[task setValue:expression forKey:[key isEqualToString:@"assignee"] ? @"assigneeExpression" : key];
	}
	return self;
}

- (WFFeelExpression *)parameterValue:(NSString *)value name:(NSString *)name element:(NSString *)elementId
{
	NSError *error = nil;
	WFFeelExpression *expression = WFAttributeExpression(value, WFAttributeKindString, &error);
	if (expression == nil && value != nil) {
		self.firstError = self.firstError ?: [NSError errorWithDomain:WFErrorDomain
			code:WFErrorInvalidDefinition userInfo:@{ NSLocalizedDescriptionKey:
				[NSString stringWithFormat:@"%@: parameter %@: %@", elementId, name,
					[error localizedDescription]] }];
	}
	return expression;
}

- (instancetype)addInputParameter:(NSString *)name value:(NSString *)value forElement:(NSString *)elementId
{
	return [self addInputParameter:name expression:[self parameterValue:value name:name element:elementId]
	                    forElement:elementId];
}

- (instancetype)addOutputParameter:(NSString *)name value:(NSString *)value forElement:(NSString *)elementId
{
	return [self addOutputParameter:name expression:[self parameterValue:value name:name element:elementId]
	                     forElement:elementId];
}

- (instancetype)addInputParameter:(NSString *)name
                       expression:(WFFeelExpression *)expression
                       forElement:(NSString *)elementId
{
	[[self.nodes objectForKey:elementId] addInputParameter:[WFParameter parameter:name expression:expression]];
	return self;
}

- (instancetype)addOutputParameter:(NSString *)name
                        expression:(WFFeelExpression *)expression
                        forElement:(NSString *)elementId
{
	[[self.nodes objectForKey:elementId] addOutputParameter:[WFParameter parameter:name expression:expression]];
	return self;
}

- (instancetype)setTimer:(WFTimer *)timer forElement:(NSString *)elementId
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	if ([node isKindOfClass:[WFEvent class]]) {
		[(WFEvent *)node setTimer:timer];
	}
	return self;
}

- (instancetype)setTimer:(WFTimerKind)kind expression:(NSString *)expression forElement:(NSString *)elementId
{
	WFFeelExpression *feel = [self feel:expression];
	return feel != nil ? [self setTimer:[[WFTimer alloc] initWithKind:kind expression:feel] forElement:elementId]
		: self;
}

- (instancetype)addEscalationThrow:(NSString *)elementId code:(NSString *)code
{
	return [self addEvent:elementId kind:WFEventKindIntermediateThrow trigger:WFEventTriggerEscalation
	          messageName:nil timer:nil attachedToId:nil errorRef:code interrupting:YES];
}

- (instancetype)addEscalationEnd:(NSString *)elementId code:(NSString *)code
{
	return [self addEvent:elementId kind:WFEventKindEnd trigger:WFEventTriggerEscalation
	          messageName:nil timer:nil attachedToId:nil errorRef:code interrupting:YES];
}

- (instancetype)addEscalationStart:(NSString *)elementId code:(NSString *)code
{
	return [self addEvent:elementId kind:WFEventKindStart trigger:WFEventTriggerEscalation
	          messageName:nil timer:nil attachedToId:nil errorRef:code interrupting:YES];
}

- (instancetype)addBoundaryEscalation:(NSString *)elementId
                               onTask:(NSString *)taskId
                                 code:(NSString *)code
                         interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:WFEventKindBoundary trigger:WFEventTriggerEscalation
	          messageName:nil timer:nil attachedToId:taskId errorRef:code interrupting:interrupting];
}

- (instancetype)addBoundaryCompensation:(NSString *)elementId
                                 onTask:(NSString *)taskId
                                handler:(NSString *)handlerId
{
	[self addEvent:elementId kind:WFEventKindBoundary trigger:WFEventTriggerCompensation
	   messageName:handlerId timer:nil attachedToId:taskId errorRef:nil interrupting:NO];
	if (handlerId != nil) {
		[self.compensationHandlers addObject:handlerId];
	}
	return self;
}

- (instancetype)addCompensationThrow:(NSString *)elementId activity:(NSString *)activityId
{
	return [self addEvent:elementId kind:WFEventKindIntermediateThrow trigger:WFEventTriggerCompensation
	          messageName:activityId timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addCompensationEnd:(NSString *)elementId activity:(NSString *)activityId
{
	return [self addEvent:elementId kind:WFEventKindEnd trigger:WFEventTriggerCompensation
	          messageName:activityId timer:nil attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)setCodeVariable:(NSString *)name forElement:(NSString *)elementId
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	if ([node isKindOfClass:[WFEvent class]]) {
		[(WFEvent *)node setCodeVariable:name];
	}
	return self;
}

- (instancetype)setForCompensation:(BOOL)forCompensation forElement:(NSString *)elementId
{
	[[self.nodes objectForKey:elementId] setForCompensation:forCompensation];
	return self;
}

- (instancetype)setCompensationHandler:(NSString *)handlerId forBoundary:(NSString *)boundaryId
{
	WFFlowNode *node = [self.nodes objectForKey:boundaryId];
	if ([node isKindOfClass:[WFEvent class]] && [(WFEvent *)node trigger] == WFEventTriggerCompensation) {
		[(WFEvent *)node wf_setMessageName:handlerId];
		[self.compensationHandlers addObject:handlerId];
	}
	return self;
}

- (instancetype)setInterrupting:(BOOL)interrupting forElement:(NSString *)elementId
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	if ([node isKindOfClass:[WFEvent class]]) {
		[(WFEvent *)node setInterrupting:interrupting];
	}
	return self;
}

- (instancetype)addBoundaryError:(NSString *)elementId
                          onTask:(NSString *)taskId
                        errorRef:(NSString *)errorRef
                    interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:WFEventKindBoundary
	              trigger:WFEventTriggerError messageName:errorRef
	        timer:nil attachedToId:taskId errorRef:errorRef
	         interrupting:interrupting];
}

- (instancetype)setAsyncBefore:(BOOL)asyncBefore
                    asyncAfter:(BOOL)asyncAfter
                     exclusive:(BOOL)exclusive
                    forElement:(NSString *)elementId
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	[node setAsyncBefore:asyncBefore];
	[node setAsyncAfter:asyncAfter];
	[node setExclusive:exclusive];
	return self;
}

- (instancetype)setRetryTimeCycle:(NSString *)cycle forElement:(NSString *)elementId
{
	[[self.nodes objectForKey:elementId] setRetryTimeCycle:cycle];
	return self;
}

- (instancetype)setTaskPriority:(NSInteger)priority forElement:(NSString *)elementId
{
	[[self.nodes objectForKey:elementId] setTaskPriority:[NSNumber numberWithInteger:priority]];
	return self;
}

- (instancetype)setMultiInstance:(WFMultiInstance *)multiInstance forElement:(NSString *)elementId
{
	[[self.nodes objectForKey:elementId] setMultiInstance:multiInstance];
	return self;
}

/* FEEL text as an expression, or nil with the builder's first error set. */
- (WFFeelExpression *)feel:(NSString *)text
{
	if (text == nil) {
		return nil;
	}
	NSError *error = nil;
	WFFeelExpression *expression = [WFFeelExpression expressionWithString:text error:&error];
	if (expression == nil) {
		self.firstError = self.firstError ?: error;
	}
	return expression;
}

- (instancetype)setMultiInstanceSequential:(BOOL)sequential
                           loopCardinality:(NSString *)loopCardinality
                                collection:(NSString *)collection
                           elementVariable:(NSString *)elementVariable
                       completionCondition:(NSString *)completionCondition
                                forElement:(NSString *)elementId
{
	WFMultiInstance *multiInstance =
		[[WFMultiInstance alloc] initSequential:sequential
		                        loopCardinality:[self feel:loopCardinality]
		                             collection:[self feel:collection]
		                        elementVariable:elementVariable
		                    completionCondition:[self feel:completionCondition]];
	return [self setMultiInstance:multiInstance forElement:elementId];
}

- (instancetype)setDefaultTaskPriority:(NSInteger)priority
{
	self.processTaskPriority = [NSNumber numberWithInteger:priority];
	return self;
}

- (instancetype)setHistoryTimeToLive:(NSInteger)days
{
	self.processTimeToLive = [NSNumber numberWithInteger:days];
	return self;
}

- (instancetype)setName:(NSString *)name forElement:(NSString *)elementId
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	if (node != nil) {
		[node setName:name];
		return self;
	}
	WFSequenceFlow *flow = [self.flows objectForKey:elementId];
	if (flow != nil) {
		WFSequenceFlow *named =
			[[WFSequenceFlow alloc] initWithElementId:flow.elementId
			                                     name:name
			                                 sourceId:flow.sourceId
			                                 targetId:flow.targetId
			                                condition:flow.condition
			                              defaultFlow:flow.isDefaultFlow];
		[self.flows setObject:named forKey:elementId];
	}
	return self;
}

- (instancetype)setBoundsFor:(NSString *)elementId
                           x:(double)x
                           y:(double)y
                       width:(double)width
                      height:(double)height
{
	WFFlowNode *node = [self.nodes objectForKey:elementId];
	node.boundsX = x;
	node.boundsY = y;
	node.boundsWidth = width;
	node.boundsHeight = height;
	return self;
}

- (NSString *)nextFlowId
{
	self.flowSerial += 1;
	return [NSString stringWithFormat:@"flow_%lu",
		(unsigned long)self.flowSerial];
}

- (instancetype)connect:(NSString *)sourceId to:(NSString *)targetId
{
	return [self connect:sourceId to:targetId flowId:nil condition:nil];
}

- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                 flowId:(NSString *)flowId
{
	return [self connect:sourceId to:targetId flowId:flowId condition:nil];
}

- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
              condition:(id<WFCondition>)condition
{
	return [self connect:sourceId to:targetId flowId:nil condition:condition];
}

- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                   when:(NSString *)condition
{
	NSError *error = nil;
	WFFeelExpression *expression = [WFFeelExpression expressionWithString:condition error:&error];
	if (expression == nil) {
		self.firstError = self.firstError ?: error;
		return self;
	}
	return [self connect:sourceId to:targetId flowId:nil condition:expression];
}

- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                 flowId:(NSString *)flowId
              condition:(id<WFCondition>)condition
{
	if (flowId == nil || [flowId length] == 0) {
		flowId = [self nextFlowId];
	}

	BOOL isDefault = NO;
	WFFlowNode *source = [self.nodes objectForKey:sourceId];
	if ([source isKindOfClass:[WFGateway class]]) {
		WFGateway *gw = (WFGateway *)source;
		if (gw.defaultFlowId != nil
		    && [gw.defaultFlowId isEqualToString:flowId]) {
			isDefault = YES;
		}
	}

	WFSequenceFlow *flow =
		[[WFSequenceFlow alloc] initWithElementId:flowId
		                                     name:flowId
		                                 sourceId:sourceId
		                                 targetId:targetId
		                                condition:condition
		                              defaultFlow:isDefault];
	[self.flows setObject:flow forKey:flowId];
	[self.flowOrder addObject:flowId];
	return self;
}

- (BOOL)fail:(NSError **)error message:(NSString *)message
{
	if (error != NULL) {
		*error = [NSError errorWithDomain:WFErrorDomain
		                             code:WFErrorInvalidDefinition
		                         userInfo:@{ NSLocalizedDescriptionKey: message }];
	}
	return NO;
}

- (BOOL)validateCall:(WFCallActivity *)call error:(NSError **)error
{
	if ([call.calledElement length] == 0) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: a call activity needs the key of the process it calls", call.elementId]];
	}
	if (call.binding == WFCalledElementBindingVersion && call.calledElementVersion < 1) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: the version binding needs a version of 1 or more", call.elementId]];
	}
	NSArray *groups = @[ call.inputs, call.outputs ];
	for (NSUInteger i = 0; i < [groups count]; i++) {
		for (WFVariableMapping *mapping in [groups objectAtIndex:i]) {
			if (mapping.isBusinessKey && i == 1) {
				return [self fail:error message:[NSString stringWithFormat:
					@"%@: the business key can only be passed in", call.elementId]];
			}
			if (!mapping.isBusinessKey && !mapping.isAllVariables
			    && ([mapping.source length] == 0 || [mapping.target length] == 0)) {
				return [self fail:error message:[NSString stringWithFormat:
					@"%@: a variable mapping needs a source and a target", call.elementId]];
			}
		}
	}
	return YES;
}

/* An embedded subprocess starts from a none start event; an event
 * subprocess from a message, timer, signal or error start, and takes no
 * sequence flows. */
- (BOOL)validateSubProcess:(WFSubProcess *)node error:(NSError **)error
{
	WFEvent *start = [node.innerDefinition startEvent];
	if (!node.isTriggeredByEvent) {
		if (start.trigger != WFEventTriggerNone) {
			return [self fail:error message:[NSString stringWithFormat:
				@"%@: an embedded subprocess starts from a none start event", node.elementId]];
		}
		return YES;
	}
	if ([node.incomingFlowIds count] > 0 || [node.outgoingFlowIds count] > 0) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: an event subprocess has no sequence flows in or out", node.elementId]];
	}
	if (node.multiInstance != nil) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: an event subprocess cannot be multi-instance", node.elementId]];
	}
	if (start.trigger != WFEventTriggerMessage && start.trigger != WFEventTriggerTimer
	    && start.trigger != WFEventTriggerSignal && start.trigger != WFEventTriggerError
	    && start.trigger != WFEventTriggerEscalation && start.trigger != WFEventTriggerConditional) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: an event subprocess starts from a message, timer, signal, error, escalation or conditional start event",
			node.elementId]];
	}
	if (start.trigger == WFEventTriggerError && !start.isInterrupting) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: an error start event always interrupts", node.elementId]];
	}
	return YES;
}

- (BOOL)validateMultiInstance:(WFFlowNode *)node error:(NSError **)error
{
	WFMultiInstance *loop = node.multiInstance;
	if (![node isKindOfClass:[WFTask class]] && ![node isKindOfClass:[WFSubProcess class]]
	    && ![node isKindOfClass:[WFCallActivity class]]) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: only tasks, subprocesses and call activities can be multi-instance",
			node.elementId]];
	}
	if ((loop.loopCardinality == nil) == (loop.collection == nil)) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: a multi-instance activity needs a loop cardinality or a collection, not both",
			node.elementId]];
	}
	if (loop.elementVariable != nil && loop.collection == nil) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: an element variable needs a collection", node.elementId]];
	}
	return YES;
}

- (BOOL)validate:(NSError **)error
{
	NSUInteger starts = 0;
	NSUInteger ends = 0;

	for (WFFlowNode *node in [self.nodes allValues]) {
		if ([node isKindOfClass:[WFEvent class]]) {
			WFEvent *event = (WFEvent *)node;
			if (event.kind == WFEventKindStart) {
				starts += 1;
			} else if (event.kind == WFEventKindEnd) {
				ends += 1;
			}
		}
	}
	if (starts != 1) {
		return [self fail:error message:@"definition needs exactly one start event"];
	}
	if (ends < 1) {
		return [self fail:error message:@"definition needs at least one end event"];
	}

	for (WFSequenceFlow *flow in [self.flows allValues]) {
		if ([self.nodes objectForKey:flow.sourceId] == nil) {
			return [self fail:error
			          message:[NSString stringWithFormat:
					@"flow %@ source %@ missing", flow.elementId, flow.sourceId]];
		}
		if ([self.nodes objectForKey:flow.targetId] == nil) {
			return [self fail:error
			          message:[NSString stringWithFormat:
					@"flow %@ target %@ missing", flow.elementId, flow.targetId]];
		}
	}

	/* Link catch events by name: each throw needs one. */
	NSMutableDictionary *linkCatches = [NSMutableDictionary dictionary];
	for (WFFlowNode *node in [self.nodes allValues]) {
		WFEvent *event = [node isKindOfClass:[WFEvent class]] ? (WFEvent *)node : nil;
		if (event.trigger == WFEventTriggerLink && event.kind == WFEventKindIntermediateCatch) {
			if ([event.linkName length] == 0 || [linkCatches objectForKey:event.linkName] != nil) {
				return [self fail:error message:[NSString stringWithFormat:
					@"%@: a link catch event needs a name no other one in its scope has", node.elementId]];
			}
			[linkCatches setObject:event forKey:event.linkName];
		}
	}

	for (WFFlowNode *node in [self.nodes allValues]) {
		WFEvent *event = [node isKindOfClass:[WFEvent class]] ? (WFEvent *)node : nil;
		BOOL isLinkCatch = event.trigger == WFEventTriggerLink && event.kind == WFEventKindIntermediateCatch;
		BOOL isLinkThrow = event.trigger == WFEventTriggerLink && event.kind == WFEventKindIntermediateThrow;
		if (isLinkThrow && [linkCatches objectForKey:event.linkName ?: @""] == nil) {
			return [self fail:error message:[NSString stringWithFormat:
				@"%@: no link catch event in its scope is named \"%@\"", node.elementId, event.linkName]];
		}
		if ((isLinkThrow && [node.outgoingFlowIds count] > 0) || (isLinkCatch && [node.incomingFlowIds count] > 0)) {
			return [self fail:error message:[NSString stringWithFormat:
				@"%@: a link throw event has no outgoing flow, and a link catch event no incoming one",
				node.elementId]];
		}
		if (event.trigger == WFEventTriggerConditional && event.condition == nil) {
			return [self fail:error message:[NSString stringWithFormat:
				@"%@: a conditional event needs its condition", node.elementId]];
		}
		if ([node isKindOfClass:[WFTask class]] && [(WFTask *)node kind] == WFTaskKindBusinessRule
		    && [[(WFTask *)node decisionRef] length] == 0 && [[(WFTask *)node actionKey] length] == 0) {
			return [self fail:error message:[NSString stringWithFormat:
				@"%@: a business rule task needs a decision or an external task's topic", node.elementId]];
		}
		if ([node isKindOfClass:[WFTask class]] && [(WFTask *)node decisionBinding] == WFCalledElementBindingVersion
		    && [(WFTask *)node decisionVersion] < 1) {
			return [self fail:error message:[NSString stringWithFormat:
				@"%@: a decision bound by version needs the version", node.elementId]];
		}
		if ([node isKindOfClass:[WFTask class]] && [(WFTask *)node kind] == WFTaskKindReceive
		    && [[(WFTask *)node messageName] length] == 0) {
			return [self fail:error message:[NSString stringWithFormat:
				@"%@: a receive task needs its message", node.elementId]];
		}
		BOOL isStart = [node isKindOfClass:[WFEvent class]]
			&& [(WFEvent *)node kind] == WFEventKindStart;
		BOOL isEnd = [node isKindOfClass:[WFEvent class]]
			&& [(WFEvent *)node kind] == WFEventKindEnd;
		BOOL isBoundary = [node isKindOfClass:[WFEvent class]]
			&& [(WFEvent *)node kind] == WFEventKindBoundary;

		if ([node isKindOfClass:[WFGateway class]] && node.isAsyncAfter
		    && [(WFGateway *)node kind] == WFGatewayKindEventBased) {
			return [self fail:error
			          message:[NSString stringWithFormat:
					@"%@: an event-based gateway waits for its events; asyncAfter has nothing to defer",
					node.elementId]];
		}

		if ([node isKindOfClass:[WFCallActivity class]]
		    && ![self validateCall:(WFCallActivity *)node error:error]) {
			return NO;
		}
		if (node.multiInstance != nil && ![self validateMultiInstance:node error:error]) {
			return NO;
		}
		if (([node.inputParameters count] > 0 || [node.outputParameters count] > 0)
		    && ![node isKindOfClass:[WFTask class]] && ![node isKindOfClass:[WFSubProcess class]]
		    && ![node isKindOfClass:[WFCallActivity class]]) {
			return [self fail:error message:[NSString stringWithFormat:
				@"%@: only tasks, subprocesses and call activities map inputs and outputs", node.elementId]];
		}
		if ([node isKindOfClass:[WFSubProcess class]] && ![self validateSubProcess:(WFSubProcess *)node error:error]) {
			return NO;
		}
		if ([node isKindOfClass:[WFSubProcess class]] && [(WFSubProcess *)node isTriggeredByEvent]) {
			/* Checked above; it has no flows to check. */
			continue;
		}

		if ([node isKindOfClass:[WFEvent class]] && [(WFEvent *)node trigger] == WFEventTriggerTimer
		    && [(WFEvent *)node timer] == nil) {
			return [self fail:error message:[NSString stringWithFormat:@"%@: a timer event needs its timer",
				node.elementId]];
		}

		if (node.retryTimeCycle != nil) {
			NSInteger attempts = 0;
			NSArray *delays = nil;
			if (!WFParseRetryCycle(node.retryTimeCycle, &attempts, &delays)) {
				return [self fail:error
				          message:[NSString stringWithFormat:
						@"%@: retry time cycle \"%@\" is neither R<n>/<duration> nor a list of durations",
						node.elementId, node.retryTimeCycle]];
			}
		}

		if (isBoundary) {
			WFEvent *boundary = (WFEvent *)node;
			WFFlowNode *host = [self.nodes objectForKey:boundary.attachedToId];
			if (![host isKindOfClass:[WFTask class]] && ![host isKindOfClass:[WFSubProcess class]]
			    && ![host isKindOfClass:[WFCallActivity class]]) {
				return [self fail:error
				          message:[NSString stringWithFormat:
						@"boundary %@ needs a task, subprocess or call activity host",
						node.elementId]];
			}
			if (boundary.trigger == WFEventTriggerCompensation) {
				/* Its handler hangs off an association, not a flow. */
				WFFlowNode *handler = [self.nodes objectForKey:boundary.compensationHandlerId];
				if (handler == nil || [node.outgoingFlowIds count] > 0) {
					return [self fail:error message:[NSString stringWithFormat:
						@"compensation boundary %@ needs a handler in its scope, and no outgoing flow",
						node.elementId]];
				}
				continue;
			}
			if ([node.outgoingFlowIds count] == 0) {
				return [self fail:error
				          message:[NSString stringWithFormat:
						@"boundary %@ has no outgoing flow", node.elementId]];
			}
			continue;
		}

		if (node.isForCompensation) {
			if ([node.incomingFlowIds count] > 0 || [node.outgoingFlowIds count] > 0) {
				return [self fail:error message:[NSString stringWithFormat:
					@"compensation handler %@ has no sequence flows", node.elementId]];
			}
			continue;
		}

		if ([node isKindOfClass:[WFEvent class]] && [(WFEvent *)node trigger] == WFEventTriggerCompensation) {
			NSString *target = [(WFEvent *)node activityRef];
			if (target != nil && [self.nodes objectForKey:target] == nil) {
				return [self fail:error message:[NSString stringWithFormat:
					@"%@ compensates %@, which is not in its scope", node.elementId, target]];
			}
		}

		if (!isStart && !isLinkCatch && [node.incomingFlowIds count] == 0) {
			return [self fail:error
			          message:[NSString stringWithFormat:
					@"node %@ has no incoming flow", node.elementId]];
		}
		if (!isEnd && !isLinkThrow && [node.outgoingFlowIds count] == 0) {
			return [self fail:error
			          message:[NSString stringWithFormat:
					@"node %@ has no outgoing flow", node.elementId]];
		}
	}
	return YES;
}

- (WFProcessDefinition *)build:(NSError **)error
{
	for (WFSequenceFlow *flow in [self.flows allValues]) {
		WFFlowNode *source = [self.nodes objectForKey:flow.sourceId];
		WFFlowNode *target = [self.nodes objectForKey:flow.targetId];
		[source addOutgoingFlowId:flow.elementId];
		[target addIncomingFlowId:flow.elementId];
	}

	if (self.firstError != nil) {
		if (error != NULL) {
			*error = self.firstError;
		}
		return nil;
	}
	for (NSString *handlerId in self.compensationHandlers) {
		[[self.nodes objectForKey:handlerId] setForCompensation:YES];
	}
	if (![self validate:error]) {
		return nil;
	}

	WFProcessDefinition *definition =
		[[WFProcessDefinition alloc] initWithProcessId:self.processId
		                                          name:self.processName
		                                       version:0
		                                         nodes:self.nodes
		                                         flows:self.flows
		                                     flowOrder:self.flowOrder];
	definition.defaultTaskPriority = self.processTaskPriority;
	definition.historyTimeToLive = self.processTimeToLive;
	return definition;
}

@end

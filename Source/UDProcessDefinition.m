#import "UDProcessDefinition.h"
#import "UDProcessDefinition+Repository.h"
#import "UDFlowElements.h"
#import "UDDuration.h"

@interface UDFlowNode (UDBuilderAccess)
- (void)addIncomingFlowId:(NSString *)flowId;
- (void)addOutgoingFlowId:(NSString *)flowId;
- (void)setName:(NSString *)name;
- (void)setAsyncBefore:(BOOL)asyncBefore;
- (void)setAsyncAfter:(BOOL)asyncAfter;
- (void)setExclusive:(BOOL)exclusive;
- (void)setRetryTimeCycle:(NSString *)cycle;
- (void)setTaskPriority:(NSNumber *)priority;
- (void)setMultiInstance:(UDMultiInstance *)multiInstance;
@end

@interface UDEvent (UDBuilderAccess)
- (void)setInterrupting:(BOOL)interrupting;
@end

@interface UDSubProcess (UDBuilderAccess)
- (void)setTriggeredByEvent:(BOOL)triggeredByEvent;
@end

@interface UDCallActivity (UDBuilderAccess)
- (void)setBinding:(UDCalledElementBinding)binding;
- (void)setCalledElementVersion:(NSInteger)version;
- (void)addInput:(UDVariableMapping *)mapping;
- (void)addOutput:(UDVariableMapping *)mapping;
@end

@interface UDProcessDefinition ()
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

@implementation UDProcessDefinition

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
		for (UDFlowNode *node in [_nodes allValues]) {
			/* The scope is held unretained: this definition owns the index,
			 * and each subprocess node owns its inner definition. */
			[index setObject:@[ node, [NSValue valueWithNonretainedObject:self] ]
			          forKey:node.elementId];
			if ([node isKindOfClass:[UDSubProcess class]]) {
				[index addEntriesFromDictionary:
					[[(UDSubProcess *)node innerDefinition] nodeIndex]];
			}
		}
		_nodeIndex = index;
	}
	return self;
}

- (UDFlowNode *)flowNodeWithId:(NSString *)elementId
{
	return elementId == nil ? nil : [[self.nodeIndex objectForKey:elementId] objectAtIndex:0];
}

- (UDProcessDefinition *)scopeOfFlowNode:(NSString *)elementId
{
	return elementId == nil ? nil
		: [[[self.nodeIndex objectForKey:elementId] objectAtIndex:1] nonretainedObjectValue];
}

- (UDProcessDefinition *)ud_deployedCopyWithVersion:(NSInteger)version
                                        definitionId:(NSString *)definitionId
                                        deploymentId:(NSString *)deploymentId
                                        resourceName:(NSString *)resourceName
{
	/* Nodes and flows are immutable once built, so the copy shares them. */
	UDProcessDefinition *copy =
		[[UDProcessDefinition alloc] initWithProcessId:self.processId
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

- (UDEvent *)startEvent
{
	for (UDFlowNode *node in [self.nodes allValues]) {
		if ([node isKindOfClass:[UDEvent class]]
		    && [(UDEvent *)node kind] == UDEventKindStart) {
			return (UDEvent *)node;
		}
	}
	return nil;
}

- (UDFlowNode *)nodeWithId:(NSString *)elementId
{
	return [self.nodes objectForKey:elementId];
}

- (UDSequenceFlow *)flowWithId:(NSString *)flowId
{
	return [self.flows objectForKey:flowId];
}

- (NSArray<UDSequenceFlow *> *)outgoingFlowsFrom:(NSString *)nodeId
{
	NSMutableArray *result = [NSMutableArray array];
	UDFlowNode *node = [self nodeWithId:nodeId];
	for (NSString *flowId in node.outgoingFlowIds) {
		UDSequenceFlow *flow = [self flowWithId:flowId];
		if (flow != nil) {
			[result addObject:flow];
		}
	}
	return result;
}

- (NSArray<UDSequenceFlow *> *)incomingFlowsTo:(NSString *)nodeId
{
	NSMutableArray *result = [NSMutableArray array];
	UDFlowNode *node = [self nodeWithId:nodeId];
	for (NSString *flowId in node.incomingFlowIds) {
		UDSequenceFlow *flow = [self flowWithId:flowId];
		if (flow != nil) {
			[result addObject:flow];
		}
	}
	return result;
}

- (NSArray *)boundaryEventsAttachedTo:(NSString *)taskId
{
	NSMutableArray *result = [NSMutableArray array];
	for (UDFlowNode *node in [self.nodes allValues]) {
		if (![node isKindOfClass:[UDEvent class]]) {
			continue;
		}
		UDEvent *event = (UDEvent *)node;
		if (event.kind == UDEventKindBoundary
		    && [event.attachedToId isEqualToString:taskId]) {
			[result addObject:event];
		}
	}
	return result;
}

@end

@interface UDDefinitionBuilder ()
@property (nonatomic, copy) NSString *processId;
@property (nonatomic, copy) NSString *processName;
@property (nonatomic, strong) NSNumber *processTaskPriority;
@property (nonatomic, strong) NSNumber *processTimeToLive;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDFlowNode *> *nodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDSequenceFlow *> *flows;
@property (nonatomic, strong) NSMutableArray<NSString *> *flowOrder;
@property (nonatomic) NSUInteger flowSerial;
/* The first thing added wrongly, which -build: reports. */
@property (nonatomic, strong) NSError *firstError;
@end

@implementation UDDefinitionBuilder

+ (instancetype)process:(NSString *)processId
{
	return [self process:processId name:processId];
}

+ (instancetype)process:(NSString *)processId name:(NSString *)name
{
	UDDefinitionBuilder *builder = [[self alloc] init];
	builder.processId = processId;
	builder.processName = name;
	builder.nodes = [NSMutableDictionary dictionary];
	builder.flows = [NSMutableDictionary dictionary];
	builder.flowOrder = [NSMutableArray array];
	builder.flowSerial = 0;
	return builder;
}

- (instancetype)addNode:(UDFlowNode *)node
{
	if (node.elementId != nil) {
		[self.nodes setObject:node forKey:node.elementId];
	}
	return self;
}

- (instancetype)addEvent:(NSString *)elementId
                    kind:(UDEventKind)kind
                 trigger:(UDEventTrigger)trigger
             messageName:(NSString *)messageName
           timerDuration:(NSTimeInterval)duration
            attachedToId:(NSString *)attachedToId
                errorRef:(NSString *)errorRef
            interrupting:(BOOL)interrupting
{
	UDEvent *event = [[UDEvent alloc] initWithElementId:elementId
	                                               name:elementId
	                                               kind:kind
	                                            trigger:trigger
	                                        messageName:messageName
	                                      timerDuration:duration
	                                       attachedToId:attachedToId
	                                           errorRef:errorRef
	                                       interrupting:interrupting];
	return [self addNode:event];
}

- (instancetype)addStart:(NSString *)elementId
{
	return [self addEvent:elementId kind:UDEventKindStart trigger:UDEventTriggerNone
	          messageName:nil timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addMessageStart:(NSString *)elementId message:(NSString *)messageName
{
	return [self addEvent:elementId kind:UDEventKindStart trigger:UDEventTriggerMessage
	          messageName:messageName timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addTimerStart:(NSString *)elementId duration:(NSTimeInterval)duration
{
	return [self addEvent:elementId kind:UDEventKindStart trigger:UDEventTriggerTimer
	          messageName:nil timerDuration:duration attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addEnd:(NSString *)elementId
{
	return [self addEvent:elementId kind:UDEventKindEnd trigger:UDEventTriggerNone
	          messageName:nil timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addMessageEnd:(NSString *)elementId message:(NSString *)messageName
{
	return [self addEvent:elementId kind:UDEventKindEnd trigger:UDEventTriggerMessage
	          messageName:messageName timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addMessageCatch:(NSString *)elementId message:(NSString *)messageName
{
	return [self addEvent:elementId kind:UDEventKindIntermediateCatch
	              trigger:UDEventTriggerMessage messageName:messageName
	        timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addTimerCatch:(NSString *)elementId duration:(NSTimeInterval)duration
{
	return [self addEvent:elementId kind:UDEventKindIntermediateCatch
	              trigger:UDEventTriggerTimer messageName:nil
	        timerDuration:duration attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addMessageThrow:(NSString *)elementId message:(NSString *)messageName
{
	return [self addEvent:elementId kind:UDEventKindIntermediateThrow
	              trigger:UDEventTriggerMessage messageName:messageName
	        timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addSignalStart:(NSString *)elementId signal:(NSString *)signalName
{
	return [self addEvent:elementId kind:UDEventKindStart trigger:UDEventTriggerSignal
	          messageName:signalName timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addSignalCatch:(NSString *)elementId signal:(NSString *)signalName
{
	return [self addEvent:elementId kind:UDEventKindIntermediateCatch trigger:UDEventTriggerSignal
	          messageName:signalName timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addSignalThrow:(NSString *)elementId signal:(NSString *)signalName
{
	return [self addEvent:elementId kind:UDEventKindIntermediateThrow trigger:UDEventTriggerSignal
	          messageName:signalName timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addSignalEnd:(NSString *)elementId signal:(NSString *)signalName
{
	return [self addEvent:elementId kind:UDEventKindEnd trigger:UDEventTriggerSignal
	          messageName:signalName timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addBoundarySignal:(NSString *)elementId
                           onTask:(NSString *)taskId
                           signal:(NSString *)signalName
                     interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:UDEventKindBoundary trigger:UDEventTriggerSignal
	          messageName:signalName timerDuration:0 attachedToId:taskId errorRef:nil
	         interrupting:interrupting];
}

- (instancetype)addTerminateEnd:(NSString *)elementId
{
	return [self addEvent:elementId kind:UDEventKindEnd trigger:UDEventTriggerTerminate
	          messageName:nil timerDuration:0 attachedToId:nil errorRef:nil interrupting:YES];
}

- (instancetype)addIntermediateThrow:(NSString *)elementId
{
	return [self addEvent:elementId kind:UDEventKindIntermediateThrow
	              trigger:UDEventTriggerNone messageName:nil
	        timerDuration:0 attachedToId:nil errorRef:nil
	         interrupting:NO];
}

- (instancetype)addBoundaryMessage:(NSString *)elementId
                            onTask:(NSString *)taskId
                           message:(NSString *)messageName
                      interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:UDEventKindBoundary
	              trigger:UDEventTriggerMessage messageName:messageName
	        timerDuration:0 attachedToId:taskId errorRef:nil interrupting:interrupting];
}

- (instancetype)addBoundaryTimer:(NSString *)elementId
                          onTask:(NSString *)taskId
                        duration:(NSTimeInterval)duration
                    interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:UDEventKindBoundary
	              trigger:UDEventTriggerTimer messageName:nil
	        timerDuration:duration attachedToId:taskId errorRef:nil interrupting:interrupting];
}

- (instancetype)addUserTask:(NSString *)elementId
                       name:(NSString *)name
                   assignee:(NSString *)assignee
{
	UDTask *task = [[UDTask alloc] initWithElementId:elementId
	                                            name:name
	                                            kind:UDTaskKindUser
	                                       actionKey:nil
	                                        assignee:assignee];
	return [self addNode:task];
}

- (instancetype)addServiceTask:(NSString *)elementId
                        action:(NSString *)actionKey
{
	UDTask *task = [[UDTask alloc] initWithElementId:elementId
	                                            name:elementId
	                                            kind:UDTaskKindService
	                                       actionKey:actionKey
	                                        assignee:nil];
	return [self addNode:task];
}

- (instancetype)addScriptTask:(NSString *)elementId
                       action:(NSString *)actionKey
{
	UDTask *task = [[UDTask alloc] initWithElementId:elementId
	                                            name:elementId
	                                            kind:UDTaskKindScript
	                                       actionKey:actionKey
	                                        assignee:nil];
	return [self addNode:task];
}

- (instancetype)addExclusive:(NSString *)elementId
                 defaultFlow:(NSString *)defaultFlowId
{
	UDGateway *gw = [[UDGateway alloc] initWithElementId:elementId
	                                                name:elementId
	                                                kind:UDGatewayKindExclusive
	                                       defaultFlowId:defaultFlowId];
	return [self addNode:gw];
}

- (instancetype)addParallel:(NSString *)elementId
{
	UDGateway *gw = [[UDGateway alloc] initWithElementId:elementId
	                                                name:elementId
	                                                kind:UDGatewayKindParallel
	                                       defaultFlowId:nil];
	return [self addNode:gw];
}

- (instancetype)addInclusive:(NSString *)elementId
                 defaultFlow:(NSString *)defaultFlowId
{
	UDGateway *gw = [[UDGateway alloc] initWithElementId:elementId
	                                                name:elementId
	                                                kind:UDGatewayKindInclusive
	                                       defaultFlowId:defaultFlowId];
	return [self addNode:gw];
}

- (instancetype)addEventBased:(NSString *)elementId
{
	UDGateway *gw = [[UDGateway alloc] initWithElementId:elementId
	                                                name:elementId
	                                                kind:UDGatewayKindEventBased
	                                       defaultFlowId:nil];
	return [self addNode:gw];
}

- (instancetype)addSubProcess:(NSString *)elementId
                         name:(NSString *)name
                        inner:(UDProcessDefinition *)inner
{
	UDSubProcess *node = [[UDSubProcess alloc] initWithElementId:elementId
	                                                        name:name
	                                            innerDefinition:inner];
	return [self addNode:node];
}

- (instancetype)addCallActivity:(NSString *)elementId
                  calledElement:(NSString *)processKey
{
	UDCallActivity *node = [[UDCallActivity alloc] initWithElementId:elementId
	                                                            name:elementId
	                                                   calledElement:processKey];
	return [self addNode:node];
}

- (UDCallActivity *)callActivity:(NSString *)elementId
{
	UDFlowNode *node = [self.nodes objectForKey:elementId];
	return [node isKindOfClass:[UDCallActivity class]] ? (UDCallActivity *)node : nil;
}

- (instancetype)setBinding:(UDCalledElementBinding)binding
                   version:(NSInteger)version
                forElement:(NSString *)elementId
{
	UDCallActivity *node = [self callActivity:elementId];
	[node setBinding:binding];
	[node setCalledElementVersion:binding == UDCalledElementBindingVersion ? version : 0];
	return self;
}

- (instancetype)addInput:(UDVariableMapping *)mapping forElement:(NSString *)elementId
{
	[[self callActivity:elementId] addInput:mapping];
	return self;
}

- (instancetype)addOutput:(UDVariableMapping *)mapping forElement:(NSString *)elementId
{
	[[self callActivity:elementId] addOutput:mapping];
	return self;
}

- (instancetype)addEventSubProcess:(NSString *)elementId
                              name:(NSString *)name
                             inner:(UDProcessDefinition *)inner
{
	UDSubProcess *node = [[UDSubProcess alloc] initWithElementId:elementId
	                                                        name:name
	                                            innerDefinition:inner];
	[node setTriggeredByEvent:YES];
	return [self addNode:node];
}

- (instancetype)addErrorStart:(NSString *)elementId errorRef:(NSString *)errorRef
{
	return [self addEvent:elementId kind:UDEventKindStart trigger:UDEventTriggerError
	          messageName:errorRef timerDuration:0 attachedToId:nil errorRef:errorRef interrupting:YES];
}

- (instancetype)setInterrupting:(BOOL)interrupting forElement:(NSString *)elementId
{
	UDFlowNode *node = [self.nodes objectForKey:elementId];
	if ([node isKindOfClass:[UDEvent class]]) {
		[(UDEvent *)node setInterrupting:interrupting];
	}
	return self;
}

- (instancetype)addBoundaryError:(NSString *)elementId
                          onTask:(NSString *)taskId
                        errorRef:(NSString *)errorRef
                    interrupting:(BOOL)interrupting
{
	return [self addEvent:elementId kind:UDEventKindBoundary
	              trigger:UDEventTriggerError messageName:errorRef
	        timerDuration:0 attachedToId:taskId errorRef:errorRef
	         interrupting:interrupting];
}

- (instancetype)setAsyncBefore:(BOOL)asyncBefore
                    asyncAfter:(BOOL)asyncAfter
                     exclusive:(BOOL)exclusive
                    forElement:(NSString *)elementId
{
	UDFlowNode *node = [self.nodes objectForKey:elementId];
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

- (instancetype)setMultiInstance:(UDMultiInstance *)multiInstance forElement:(NSString *)elementId
{
	[[self.nodes objectForKey:elementId] setMultiInstance:multiInstance];
	return self;
}

/* FEEL text as an expression, or nil with the builder's first error set. */
- (UDFeelExpression *)feel:(NSString *)text
{
	if (text == nil) {
		return nil;
	}
	NSError *error = nil;
	UDFeelExpression *expression = [UDFeelExpression expressionWithString:text error:&error];
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
	UDMultiInstance *multiInstance =
		[[UDMultiInstance alloc] initSequential:sequential
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
	UDFlowNode *node = [self.nodes objectForKey:elementId];
	if (node != nil) {
		[node setName:name];
		return self;
	}
	UDSequenceFlow *flow = [self.flows objectForKey:elementId];
	if (flow != nil) {
		UDSequenceFlow *named =
			[[UDSequenceFlow alloc] initWithElementId:flow.elementId
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
	UDFlowNode *node = [self.nodes objectForKey:elementId];
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
              condition:(id<UDCondition>)condition
{
	return [self connect:sourceId to:targetId flowId:nil condition:condition];
}

- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                   when:(NSString *)condition
{
	NSError *error = nil;
	UDFeelExpression *expression = [UDFeelExpression expressionWithString:condition error:&error];
	if (expression == nil) {
		self.firstError = self.firstError ?: error;
		return self;
	}
	return [self connect:sourceId to:targetId flowId:nil condition:expression];
}

- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                 flowId:(NSString *)flowId
              condition:(id<UDCondition>)condition
{
	if (flowId == nil || [flowId length] == 0) {
		flowId = [self nextFlowId];
	}

	BOOL isDefault = NO;
	UDFlowNode *source = [self.nodes objectForKey:sourceId];
	if ([source isKindOfClass:[UDGateway class]]) {
		UDGateway *gw = (UDGateway *)source;
		if (gw.defaultFlowId != nil
		    && [gw.defaultFlowId isEqualToString:flowId]) {
			isDefault = YES;
		}
	}

	UDSequenceFlow *flow =
		[[UDSequenceFlow alloc] initWithElementId:flowId
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
		*error = [NSError errorWithDomain:UDWorkflowErrorDomain
		                             code:UDWorkflowErrorInvalidDefinition
		                         userInfo:@{ NSLocalizedDescriptionKey: message }];
	}
	return NO;
}

- (BOOL)validateCall:(UDCallActivity *)call error:(NSError **)error
{
	if ([call.calledElement length] == 0) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: a call activity needs the key of the process it calls", call.elementId]];
	}
	if (call.binding == UDCalledElementBindingVersion && call.calledElementVersion < 1) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: the version binding needs a version of 1 or more", call.elementId]];
	}
	NSArray *groups = @[ call.inputs, call.outputs ];
	for (NSUInteger i = 0; i < [groups count]; i++) {
		for (UDVariableMapping *mapping in [groups objectAtIndex:i]) {
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
- (BOOL)validateSubProcess:(UDSubProcess *)node error:(NSError **)error
{
	UDEvent *start = [node.innerDefinition startEvent];
	if (!node.isTriggeredByEvent) {
		if (start.trigger != UDEventTriggerNone) {
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
	if (start.trigger != UDEventTriggerMessage && start.trigger != UDEventTriggerTimer
	    && start.trigger != UDEventTriggerSignal && start.trigger != UDEventTriggerError) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: an event subprocess starts from a message, timer, signal or error start event",
			node.elementId]];
	}
	if (start.trigger == UDEventTriggerError && !start.isInterrupting) {
		return [self fail:error message:[NSString stringWithFormat:
			@"%@: an error start event always interrupts", node.elementId]];
	}
	return YES;
}

- (BOOL)validateMultiInstance:(UDFlowNode *)node error:(NSError **)error
{
	UDMultiInstance *loop = node.multiInstance;
	if (![node isKindOfClass:[UDTask class]] && ![node isKindOfClass:[UDSubProcess class]]
	    && ![node isKindOfClass:[UDCallActivity class]]) {
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

	for (UDFlowNode *node in [self.nodes allValues]) {
		if ([node isKindOfClass:[UDEvent class]]) {
			UDEvent *event = (UDEvent *)node;
			if (event.kind == UDEventKindStart) {
				starts += 1;
			} else if (event.kind == UDEventKindEnd) {
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

	for (UDSequenceFlow *flow in [self.flows allValues]) {
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

	for (UDFlowNode *node in [self.nodes allValues]) {
		BOOL isStart = [node isKindOfClass:[UDEvent class]]
			&& [(UDEvent *)node kind] == UDEventKindStart;
		BOOL isEnd = [node isKindOfClass:[UDEvent class]]
			&& [(UDEvent *)node kind] == UDEventKindEnd;
		BOOL isBoundary = [node isKindOfClass:[UDEvent class]]
			&& [(UDEvent *)node kind] == UDEventKindBoundary;

		if ([node isKindOfClass:[UDGateway class]] && node.isAsyncAfter
		    && [(UDGateway *)node kind] == UDGatewayKindEventBased) {
			return [self fail:error
			          message:[NSString stringWithFormat:
					@"%@: an event-based gateway waits for its events; asyncAfter has nothing to defer",
					node.elementId]];
		}

		if ([node isKindOfClass:[UDCallActivity class]]
		    && ![self validateCall:(UDCallActivity *)node error:error]) {
			return NO;
		}
		if (node.multiInstance != nil && ![self validateMultiInstance:node error:error]) {
			return NO;
		}
		if ([node isKindOfClass:[UDSubProcess class]] && ![self validateSubProcess:(UDSubProcess *)node error:error]) {
			return NO;
		}
		if ([node isKindOfClass:[UDSubProcess class]] && [(UDSubProcess *)node isTriggeredByEvent]) {
			/* Checked above; it has no flows to check. */
			continue;
		}

		if (node.retryTimeCycle != nil) {
			NSInteger attempts = 0;
			NSArray *delays = nil;
			if (!UDParseRetryCycle(node.retryTimeCycle, &attempts, &delays)) {
				return [self fail:error
				          message:[NSString stringWithFormat:
						@"%@: retry time cycle \"%@\" is neither R<n>/<duration> nor a list of durations",
						node.elementId, node.retryTimeCycle]];
			}
		}

		if (isBoundary) {
			UDEvent *boundary = (UDEvent *)node;
			UDFlowNode *host = [self.nodes objectForKey:boundary.attachedToId];
			if (![host isKindOfClass:[UDTask class]] && ![host isKindOfClass:[UDSubProcess class]]
			    && ![host isKindOfClass:[UDCallActivity class]]) {
				return [self fail:error
				          message:[NSString stringWithFormat:
						@"boundary %@ needs a task, subprocess or call activity host",
						node.elementId]];
			}
			if ([node.outgoingFlowIds count] == 0) {
				return [self fail:error
				          message:[NSString stringWithFormat:
						@"boundary %@ has no outgoing flow", node.elementId]];
			}
			continue;
		}

		if (!isStart && [node.incomingFlowIds count] == 0) {
			return [self fail:error
			          message:[NSString stringWithFormat:
					@"node %@ has no incoming flow", node.elementId]];
		}
		if (!isEnd && [node.outgoingFlowIds count] == 0) {
			return [self fail:error
			          message:[NSString stringWithFormat:
					@"node %@ has no outgoing flow", node.elementId]];
		}
	}
	return YES;
}

- (UDProcessDefinition *)build:(NSError **)error
{
	for (UDSequenceFlow *flow in [self.flows allValues]) {
		UDFlowNode *source = [self.nodes objectForKey:flow.sourceId];
		UDFlowNode *target = [self.nodes objectForKey:flow.targetId];
		[source addOutgoingFlowId:flow.elementId];
		[target addIncomingFlowId:flow.elementId];
	}

	if (self.firstError != nil) {
		if (error != NULL) {
			*error = self.firstError;
		}
		return nil;
	}
	if (![self validate:error]) {
		return nil;
	}

	UDProcessDefinition *definition =
		[[UDProcessDefinition alloc] initWithProcessId:self.processId
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

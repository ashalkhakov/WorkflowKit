#import "UDProcessDefinition.h"
#import "UDProcessDefinition+Repository.h"
#import "UDFlowElements.h"

@interface UDFlowNode (UDBuilderAccess)
- (void)addIncomingFlowId:(NSString *)flowId;
- (void)addOutgoingFlowId:(NSString *)flowId;
- (void)setName:(NSString *)name;
@end

@interface UDProcessDefinition ()
@property (nonatomic, readwrite) NSInteger version;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *deploymentId;
@property (nonatomic, readwrite, copy) NSString *resourceName;
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
	}
	return self;
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDFlowNode *> *nodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDSequenceFlow *> *flows;
@property (nonatomic, strong) NSMutableArray<NSString *> *flowOrder;
@property (nonatomic) NSUInteger flowSerial;
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
                    key:(NSString *)key
                     op:(UDComparisonOp)op
                  value:(id)value
{
	UDComparisonCondition *condition =
		[[UDComparisonCondition alloc] initWithKey:key op:op value:value];
	return [self connect:sourceId to:targetId flowId:nil condition:condition];
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

		if (isBoundary) {
			UDEvent *boundary = (UDEvent *)node;
			UDFlowNode *host = [self.nodes objectForKey:boundary.attachedToId];
			if (![host isKindOfClass:[UDTask class]]) {
				return [self fail:error
				          message:[NSString stringWithFormat:
						@"boundary %@ needs a task host", node.elementId]];
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

		if ([node isKindOfClass:[UDGateway class]]) {
			UDGateway *gw = (UDGateway *)node;
			if (gw.kind == UDGatewayKindExclusive
			    && [gw.outgoingFlowIds count] > 1) {
				BOOL hasDefault = NO;
				BOOL hasUnconditional = NO;
				for (NSString *flowId in gw.outgoingFlowIds) {
					UDSequenceFlow *flow = [self.flows objectForKey:flowId];
					if (flow.isDefaultFlow
					    || [flow.elementId isEqualToString:gw.defaultFlowId]) {
						hasDefault = YES;
					}
					if (flow.condition == nil && !flow.isDefaultFlow) {
						hasUnconditional = YES;
					}
				}
				if (!hasDefault && !hasUnconditional) {
					return [self fail:error
					          message:[NSString stringWithFormat:
							@"exclusive gateway %@ needs a default or open flow",
							gw.elementId]];
				}
			}
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

	if (![self validate:error]) {
		return nil;
	}

	return [[UDProcessDefinition alloc] initWithProcessId:self.processId
	                                                 name:self.processName
	                                              version:0
	                                                nodes:self.nodes
	                                                flows:self.flows
	                                            flowOrder:self.flowOrder];
}

@end

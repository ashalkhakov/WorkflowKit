#import "UDFlowElements.h"
#import "UDProcessDefinition.h"

NSString * const UDWorkflowErrorDomain = @"UDWorkflowErrorDomain";
NSString * const UDWorkflowErrorRefKey = @"UDWorkflowErrorRef";

@interface UDFlowNode ()
@property (nonatomic, copy, readwrite) NSString *elementId;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, readwrite, getter=isAsyncBefore) BOOL asyncBefore;
@property (nonatomic, readwrite, getter=isAsyncAfter) BOOL asyncAfter;
@property (nonatomic, readwrite, getter=isExclusive) BOOL exclusive;
@property (nonatomic, readwrite, copy) NSString *retryTimeCycle;
@property (nonatomic, readwrite, strong) NSNumber *taskPriority;
@property (nonatomic, readwrite, strong) UDMultiInstance *multiInstance;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableIncoming;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableOutgoing;
- (void)addIncomingFlowId:(NSString *)flowId;
- (void)addOutgoingFlowId:(NSString *)flowId;
- (void)freezeWiring;
@end

@implementation UDFlowNode

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
{
	self = [super init];
	if (self) {
		_elementId = [elementId copy];
		_name = [name copy];
		_exclusive = YES;
		_mutableIncoming = [NSMutableArray array];
		_mutableOutgoing = [NSMutableArray array];
	}
	return self;
}

- (NSArray<NSString *> *)incomingFlowIds
{
	return [_mutableIncoming copy];
}

- (NSArray<NSString *> *)outgoingFlowIds
{
	return [_mutableOutgoing copy];
}

- (void)addIncomingFlowId:(NSString *)flowId
{
	if (flowId != nil) {
		[_mutableIncoming addObject:flowId];
	}
}

- (void)addOutgoingFlowId:(NSString *)flowId
{
	if (flowId != nil) {
		[_mutableOutgoing addObject:flowId];
	}
}

- (void)freezeWiring
{
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@>",
		NSStringFromClass([self class]), self.elementId];
}

@end

@implementation UDMultiInstance

- (instancetype)initSequential:(BOOL)sequential
               loopCardinality:(UDFeelExpression *)loopCardinality
                    collection:(UDFeelExpression *)collection
               elementVariable:(NSString *)elementVariable
           completionCondition:(UDFeelExpression *)completionCondition
{
	self = [super init];
	if (self) {
		_sequential = sequential;
		_loopCardinality = loopCardinality;
		_collection = collection;
		_elementVariable = [elementVariable copy];
		_completionCondition = completionCondition;
	}
	return self;
}

@end

@interface UDEvent ()
@property (nonatomic, readwrite, getter=isInterrupting) BOOL interrupting;
@end

@interface UDSubProcess ()
@property (nonatomic, readwrite, getter=isTriggeredByEvent) BOOL triggeredByEvent;
@end

@implementation UDEvent

- (NSString *)signalName
{
	return self.trigger == UDEventTriggerSignal ? self.messageName : nil;
}

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDEventKind)kind
                          trigger:(UDEventTrigger)trigger
                      messageName:(NSString *)messageName
                    timerDuration:(NSTimeInterval)timerDuration
                     attachedToId:(NSString *)attachedToId
                         errorRef:(NSString *)errorRef
                     interrupting:(BOOL)interrupting
{
	self = [super initWithElementId:elementId name:name];
	if (self) {
		_kind = kind;
		_trigger = trigger;
		_messageName = [messageName copy];
		_timerDuration = timerDuration;
		_attachedToId = [attachedToId copy];
		_errorRef = [errorRef copy];
		_interrupting = interrupting;
	}
	return self;
}

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDEventKind)kind
{
	return [self initWithElementId:elementId
	                          name:name
	                          kind:kind
	                       trigger:UDEventTriggerNone
	                   messageName:nil
	                 timerDuration:0
	                  attachedToId:nil
	                      errorRef:nil
	                  interrupting:YES];
}

@end

@implementation UDTask

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDTaskKind)kind
                        actionKey:(NSString *)actionKey
                         assignee:(NSString *)assignee
{
	self = [super initWithElementId:elementId name:name];
	if (self) {
		_kind = kind;
		_actionKey = [actionKey copy];
		_assignee = [assignee copy];
	}
	return self;
}

@end

@implementation UDGateway

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDGatewayKind)kind
                    defaultFlowId:(NSString *)defaultFlowId
{
	self = [super initWithElementId:elementId name:name];
	if (self) {
		_kind = kind;
		_defaultFlowId = [defaultFlowId copy];
	}
	return self;
}

@end

@implementation UDSubProcess

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                 innerDefinition:(UDProcessDefinition *)innerDefinition
{
	self = [super initWithElementId:elementId name:name];
	if (self) {
		_innerDefinition = innerDefinition;
	}
	return self;
}

@end

@interface UDVariableMapping ()
- (instancetype)initWithSource:(NSString *)source
                        target:(NSString *)target
                  allVariables:(BOOL)allVariables
                   businessKey:(BOOL)businessKey;
@end

@implementation UDVariableMapping

- (instancetype)initWithSource:(NSString *)source
                        target:(NSString *)target
                  allVariables:(BOOL)allVariables
                   businessKey:(BOOL)businessKey
{
	self = [super init];
	if (self) {
		_source = [source copy];
		_target = [target copy];
		_allVariables = allVariables;
		_businessKey = businessKey;
	}
	return self;
}

+ (instancetype)mappingFrom:(NSString *)source to:(NSString *)target
{
	return [[self alloc] initWithSource:source target:target allVariables:NO businessKey:NO];
}

+ (instancetype)allVariables
{
	return [[self alloc] initWithSource:nil target:nil allVariables:YES businessKey:NO];
}

+ (instancetype)businessKey
{
	return [[self alloc] initWithSource:nil target:nil allVariables:NO businessKey:YES];
}

@end

@interface UDCallActivity ()
@property (nonatomic, readwrite) UDCalledElementBinding binding;
@property (nonatomic, readwrite) NSInteger calledElementVersion;
@property (nonatomic, strong) NSMutableArray<UDVariableMapping *> *mutableInputs;
@property (nonatomic, strong) NSMutableArray<UDVariableMapping *> *mutableOutputs;
@end

@implementation UDCallActivity

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                    calledElement:(NSString *)calledElement
{
	self = [super initWithElementId:elementId name:name];
	if (self) {
		_calledElement = [calledElement copy];
		_mutableInputs = [NSMutableArray array];
		_mutableOutputs = [NSMutableArray array];
	}
	return self;
}

- (NSArray<UDVariableMapping *> *)inputs
{
	return [_mutableInputs copy];
}

- (NSArray<UDVariableMapping *> *)outputs
{
	return [_mutableOutputs copy];
}

- (void)addInput:(UDVariableMapping *)mapping
{
	[_mutableInputs addObject:mapping];
}

- (void)addOutput:(UDVariableMapping *)mapping
{
	[_mutableOutputs addObject:mapping];
}

@end

@implementation UDSequenceFlow

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                         sourceId:(NSString *)sourceId
                         targetId:(NSString *)targetId
                        condition:(id)condition
                      defaultFlow:(BOOL)defaultFlow
{
	self = [super init];
	if (self) {
		_elementId = [elementId copy];
		_name = [name copy];
		_sourceId = [sourceId copy];
		_targetId = [targetId copy];
		_condition = condition;
		_defaultFlow = defaultFlow;
	}
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<UDSequenceFlow %@ %@ -> %@>",
		self.elementId, self.sourceId, self.targetId];
}

@end

#import "WFFlowElements.h"
#import "WFProcessDefinition.h"
#import "WFTimers.h"
#import "WFFeelInternal.h"

NSString * const WFErrorDomain = @"WFErrorDomain";
NSString * const WFErrorRefKey = @"WFErrorRef";

@interface WFFlowNode ()
@property (nonatomic, copy, readwrite) NSString *elementId;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, readwrite, getter=isAsyncBefore) BOOL asyncBefore;
@property (nonatomic, readwrite, getter=isAsyncAfter) BOOL asyncAfter;
@property (nonatomic, readwrite, getter=isExclusive) BOOL exclusive;
@property (nonatomic, readwrite, copy) NSString *retryTimeCycle;
@property (nonatomic, readwrite, strong) NSNumber *taskPriority;
@property (nonatomic, readwrite, strong) WFMultiInstance *multiInstance;
@property (nonatomic, readwrite, getter=isForCompensation) BOOL forCompensation;
@property (nonatomic, readwrite, strong) WFFormDefinition *form;
@property (nonatomic, strong) NSMutableArray<WFParameter *> *mutableInputParameters;
@property (nonatomic, strong) NSMutableArray<WFParameter *> *mutableOutputParameters;
@property (nonatomic, strong) NSMutableArray<WFListener *> *mutableExecutionListeners;
- (void)addExecutionListener:(WFListener *)listener;
- (void)addInputParameter:(WFParameter *)parameter;
- (void)addOutputParameter:(WFParameter *)parameter;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableIncoming;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableOutgoing;
- (void)addIncomingFlowId:(NSString *)flowId;
- (void)addOutgoingFlowId:(NSString *)flowId;
- (void)freezeWiring;
@end

@implementation WFFlowNode

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
{
	self = [super init];
	if (self) {
		_elementId = [elementId copy];
		_name = [name copy];
		_exclusive = YES;
		_mutableInputParameters = [NSMutableArray array];
		_mutableOutputParameters = [NSMutableArray array];
		_mutableExecutionListeners = [NSMutableArray array];
		_mutableIncoming = [NSMutableArray array];
		_mutableOutgoing = [NSMutableArray array];
	}
	return self;
}

- (NSArray<WFListener *> *)executionListeners
{
	return [_mutableExecutionListeners copy];
}

- (void)addExecutionListener:(WFListener *)listener
{
	[_mutableExecutionListeners addObject:listener];
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

- (NSArray<WFParameter *> *)inputParameters
{
	return [_mutableInputParameters copy];
}

- (NSArray<WFParameter *> *)outputParameters
{
	return [_mutableOutputParameters copy];
}

- (void)addInputParameter:(WFParameter *)parameter
{
	[_mutableInputParameters addObject:parameter];
}

- (void)addOutputParameter:(WFParameter *)parameter
{
	[_mutableOutputParameters addObject:parameter];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %@>",
		NSStringFromClass([self class]), self.elementId];
}

@end

@interface WFParameter ()
- (instancetype)initWithName:(NSString *)name expression:(WFFeelExpression *)expression;
@end

@implementation WFParameter

- (instancetype)initWithName:(NSString *)name expression:(WFFeelExpression *)expression
{
	self = [super init];
	if (self) {
		_name = [name copy];
		_expression = expression;
	}
	return self;
}

+ (instancetype)parameter:(NSString *)name expression:(WFFeelExpression *)expression
{
	return [[self alloc] initWithName:name expression:expression];
}

@end

@implementation WFTimer

- (instancetype)initWithKind:(WFTimerKind)kind expression:(WFFeelExpression *)expression
{
	self = [super init];
	if (self) {
		_kind = kind;
		_expression = expression;
	}
	return self;
}

+ (instancetype)duration:(NSTimeInterval)seconds
{
	return [self timerWithKind:WFTimerKindDuration text:WFISODurationText(seconds)];
}

+ (instancetype)timerWithKind:(WFTimerKind)kind text:(NSString *)text
{
	NSString *literal = WFTimerLiteral(kind, text);
	if (literal == nil) {
		return nil;
	}
	WFFeelExpression *expression = [WFFeelExpression expressionWithString:literal error:NULL];
	return expression != nil ? [[self alloc] initWithKind:kind expression:expression] : nil;
}

@end

@implementation WFMultiInstance

- (instancetype)initSequential:(BOOL)sequential
               loopCardinality:(WFFeelExpression *)loopCardinality
                    collection:(WFFeelExpression *)collection
               elementVariable:(NSString *)elementVariable
           completionCondition:(WFFeelExpression *)completionCondition
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

@interface WFEvent ()
@property (nonatomic, readwrite, getter=isInterrupting) BOOL interrupting;
@property (nonatomic, readwrite, strong) WFTimer *timer;
@property (nonatomic, readwrite, copy) NSString *codeVariable;
@end

@interface WFSubProcess ()
@property (nonatomic, readwrite, getter=isTriggeredByEvent) BOOL triggeredByEvent;
@end

@implementation WFEventCondition

- (instancetype)initWithExpression:(WFFeelExpression *)expression
                      variableName:(NSString *)variableName
                    variableEvents:(NSArray<NSString *> *)variableEvents
{
	self = [super init];
	if (self) {
		_expression = expression;
		_variableName = [variableName copy];
		_variableEvents = [variableEvents copy];
	}
	return self;
}

@end

@implementation WFEvent

- (NSString *)linkName
{
	return self.trigger == WFEventTriggerLink ? self.messageName : nil;
}

- (void)wf_setCondition:(WFEventCondition *)condition
{
	_condition = condition;
}

- (NSString *)signalName
{
	return self.trigger == WFEventTriggerSignal ? self.messageName : nil;
}

- (NSString *)escalationCode
{
	return self.trigger == WFEventTriggerEscalation ? self.errorRef : nil;
}

- (NSString *)activityRef
{
	return self.trigger == WFEventTriggerCompensation && self.kind != WFEventKindBoundary
		? self.messageName : nil;
}

- (NSString *)compensationHandlerId
{
	return self.trigger == WFEventTriggerCompensation && self.kind == WFEventKindBoundary
		? self.messageName : nil;
}

- (void)wf_setMessageName:(NSString *)name
{
	_messageName = [name copy];
}

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(WFEventKind)kind
                          trigger:(WFEventTrigger)trigger
                      messageName:(NSString *)messageName
                            timer:(WFTimer *)timer
                     attachedToId:(NSString *)attachedToId
                         errorRef:(NSString *)errorRef
                     interrupting:(BOOL)interrupting
{
	self = [super initWithElementId:elementId name:name];
	if (self) {
		_kind = kind;
		_trigger = trigger;
		_messageName = [messageName copy];
		_timer = timer;
		_attachedToId = [attachedToId copy];
		_errorRef = [errorRef copy];
		_interrupting = interrupting;
	}
	return self;
}

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(WFEventKind)kind
{
	return [self initWithElementId:elementId
	                          name:name
	                          kind:kind
	                       trigger:WFEventTriggerNone
	                   messageName:nil
	                         timer:nil
	                  attachedToId:nil
	                      errorRef:nil
	                  interrupting:YES];
}

@end

@interface WFTask ()
@property (nonatomic, readwrite, strong) WFDelegateReference *delegate;
@property (nonatomic, strong) NSMutableArray<WFListener *> *mutableTaskListeners;
@property (nonatomic, readwrite, copy) NSString *decisionRef;
@property (nonatomic, readwrite) WFCalledElementBinding decisionBinding;
@property (nonatomic, readwrite) NSInteger decisionVersion;
@property (nonatomic, readwrite, copy) NSString *resultVariable;
@property (nonatomic, readwrite) WFDecisionResultMapping mapDecisionResult;
@property (nonatomic, readwrite, strong) WFFeelExpression *assigneeExpression;
@property (nonatomic, readwrite, strong) WFFeelExpression *candidateUsers;
@property (nonatomic, readwrite, strong) WFFeelExpression *candidateGroups;
@property (nonatomic, readwrite, strong) WFFeelExpression *dueDate;
@property (nonatomic, readwrite, strong) WFFeelExpression *followUpDate;
@property (nonatomic, readwrite, strong) WFFeelExpression *priority;
@end

@implementation WFTask

@synthesize actionKey = _actionKey;

- (NSArray<WFListener *> *)taskListeners
{
	return [_mutableTaskListeners copy] ?: @[];
}

- (void)addTaskListener:(WFListener *)listener
{
	if (_mutableTaskListeners == nil) {
		_mutableTaskListeners = [NSMutableArray array];
	}
	[_mutableTaskListeners addObject:listener];
}

/* A receive task keeps its message where the others keep their topic. */
- (NSString *)messageName
{
	return self.kind == WFTaskKindReceive ? _actionKey : nil;
}

- (NSString *)actionKey
{
	return self.kind == WFTaskKindReceive ? nil : _actionKey;
}

- (NSString *)assignee
{
	WFFeelNode *root = [self.assigneeExpression root];
	return root.kind == WFFeelNodeLiteral && [root.value isKindOfClass:[NSString class]] ? root.value : nil;
}

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(WFTaskKind)kind
                        actionKey:(NSString *)actionKey
                         assignee:(NSString *)assignee
{
	self = [super initWithElementId:elementId name:name];
	if (self) {
		_kind = kind;
		_actionKey = [actionKey copy];
		_assigneeExpression = assignee != nil
			? [WFFeelExpression expressionWithString:WFFeelLiteralText(assignee) error:NULL] : nil;
	}
	return self;
}

@end

@implementation WFGateway

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(WFGatewayKind)kind
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

@implementation WFSubProcess

- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                 innerDefinition:(WFProcessDefinition *)innerDefinition
{
	self = [super initWithElementId:elementId name:name];
	if (self) {
		_innerDefinition = innerDefinition;
	}
	return self;
}

@end

@interface WFVariableMapping ()
- (instancetype)initWithSource:(NSString *)source
                        target:(NSString *)target
                  allVariables:(BOOL)allVariables
                   businessKey:(BOOL)businessKey;
@end

@implementation WFVariableMapping

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

@interface WFCallActivity ()
@property (nonatomic, readwrite) WFCalledElementBinding binding;
@property (nonatomic, readwrite) NSInteger calledElementVersion;
@property (nonatomic, strong) NSMutableArray<WFVariableMapping *> *mutableInputs;
@property (nonatomic, strong) NSMutableArray<WFVariableMapping *> *mutableOutputs;
@end

@implementation WFCallActivity

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

- (NSArray<WFVariableMapping *> *)inputs
{
	return [_mutableInputs copy];
}

- (NSArray<WFVariableMapping *> *)outputs
{
	return [_mutableOutputs copy];
}

- (void)addInput:(WFVariableMapping *)mapping
{
	[_mutableInputs addObject:mapping];
}

- (void)addOutput:(WFVariableMapping *)mapping
{
	[_mutableOutputs addObject:mapping];
}

@end

@interface WFSequenceFlow ()
@property (nonatomic, strong) NSMutableArray<WFListener *> *mutableListeners;
@end

@implementation WFSequenceFlow

- (NSArray<WFListener *> *)listeners
{
	return [_mutableListeners copy] ?: @[];
}

- (void)addListener:(WFListener *)listener
{
	if (_mutableListeners == nil) {
		_mutableListeners = [NSMutableArray array];
	}
	[_mutableListeners addObject:listener];
}

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
	return [NSString stringWithFormat:@"<WFSequenceFlow %@ %@ -> %@>",
		self.elementId, self.sourceId, self.targetId];
}

@end

@implementation WFDelegateReference

- (instancetype)initWithClass:(NSString *)className name:(NSString *)delegateName fields:(NSArray *)fields
{
	self = [super init];
	if (self) {
		_className = [className copy];
		_delegateName = [delegateName copy];
		_fields = [fields copy] ?: @[];
	}
	return self;
}

+ (instancetype)referenceToClass:(NSString *)className fields:(NSArray<WFParameter *> *)fields
{
	return [[self alloc] initWithClass:className name:nil fields:fields];
}

+ (instancetype)referenceToDelegate:(NSString *)delegateName fields:(NSArray<WFParameter *> *)fields
{
	return [[self alloc] initWithClass:nil name:delegateName fields:fields];
}

- (NSString *)description
{
	return self.className != nil ? [NSString stringWithFormat:@"class %@", self.className]
		: [NSString stringWithFormat:@"delegate %@", self.delegateName];
}

@end

@implementation WFListener

- (instancetype)initWithEvent:(WFListenerEvent)event delegate:(WFDelegateReference *)delegate
{
	self = [super init];
	if (self) {
		_event = event;
		_delegate = delegate;
	}
	return self;
}

+ (instancetype)listenerOn:(WFListenerEvent)event delegate:(WFDelegateReference *)delegate
{
	return [[self alloc] initWithEvent:event delegate:delegate];
}

+ (NSString *)nameOfEvent:(WFListenerEvent)event
{
	switch (event) {
	case WFListenerEventStart: return @"start";
	case WFListenerEventEnd: return @"end";
	case WFListenerEventTake: return @"take";
	case WFListenerEventCreate: return @"create";
	case WFListenerEventAssignment: return @"assignment";
	case WFListenerEventComplete: return @"complete";
	case WFListenerEventDelete: return @"delete";
	}
	return @"";
}

@end

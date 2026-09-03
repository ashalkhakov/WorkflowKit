#import "UDFlowElements.h"
#import "UDProcessDefinition.h"

NSString * const UDWorkflowErrorDomain = @"UDWorkflowErrorDomain";
NSString * const UDWorkflowErrorRefKey = @"UDWorkflowErrorRef";

@interface UDFlowNode ()
@property (nonatomic, copy, readwrite) NSString *elementId;
@property (nonatomic, copy, readwrite) NSString *name;
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

@implementation UDEvent

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

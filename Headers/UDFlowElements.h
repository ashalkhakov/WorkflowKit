#ifndef UDFlowElements_h
#define UDFlowElements_h

#import "UDTypes.h"

@protocol UDFlowElement <NSObject>
@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@end

@interface UDFlowNode : NSObject <UDFlowElement>

@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSArray<NSString *> *incomingFlowIds;
@property (nonatomic, readonly, copy) NSArray<NSString *> *outgoingFlowIds;
@property (nonatomic) double boundsX;
@property (nonatomic) double boundsY;
@property (nonatomic) double boundsWidth;
@property (nonatomic) double boundsHeight;
/* Transaction boundaries, as camunda:asyncBefore and camunda:asyncAfter:
 * the command stops before entering, or after leaving, the node, and a job
 * carries on from there. */
@property (nonatomic, readonly, getter=isAsyncBefore) BOOL asyncBefore;
@property (nonatomic, readonly, getter=isAsyncAfter) BOOL asyncAfter;
/* camunda:exclusive: whether the node's jobs run one after another with the
 * instance's other work. YES unless set otherwise. */
@property (nonatomic, readonly, getter=isExclusive) BOOL exclusive;
/* camunda:failedJobRetryTimeCycle: "R5/PT5M", or a list of ISO-8601
 * durations, one per retry. nil for the default of three attempts. */
@property (nonatomic, readonly, copy) NSString *retryTimeCycle;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_DESIGNATED_INITIALIZER;

@end

@interface UDEvent : UDFlowNode
@property (nonatomic, readonly) UDEventKind kind;
@property (nonatomic, readonly) UDEventTrigger trigger;
@property (nonatomic, readonly, copy) NSString *messageName;
@property (nonatomic, readonly) NSTimeInterval timerDuration;
@property (nonatomic, readonly, copy) NSString *attachedToId;
@property (nonatomic, readonly, copy) NSString *errorRef;
@property (nonatomic, readonly, getter=isInterrupting) BOOL interrupting;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDEventKind)kind
                          trigger:(UDEventTrigger)trigger
                      messageName:(NSString *)messageName
                    timerDuration:(NSTimeInterval)timerDuration
                     attachedToId:(NSString *)attachedToId
                         errorRef:(NSString *)errorRef
                     interrupting:(BOOL)interrupting NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDEventKind)kind;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface UDTask : UDFlowNode
@property (nonatomic, readonly) UDTaskKind kind;
@property (nonatomic, readonly, copy) NSString *actionKey;
@property (nonatomic, readonly, copy) NSString *assignee;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDTaskKind)kind
                        actionKey:(NSString *)actionKey
                         assignee:(NSString *)assignee NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface UDGateway : UDFlowNode
@property (nonatomic, readonly) UDGatewayKind kind;
@property (nonatomic, readonly, copy) NSString *defaultFlowId;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                             kind:(UDGatewayKind)kind
                    defaultFlowId:(NSString *)defaultFlowId NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@class UDProcessDefinition;

@interface UDSubProcess : UDFlowNode
@property (nonatomic, readonly, strong) UDProcessDefinition *innerDefinition;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                 innerDefinition:(UDProcessDefinition *)innerDefinition NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name NS_UNAVAILABLE;
@end

@interface UDSequenceFlow : NSObject <UDFlowElement>

@property (nonatomic, readonly, copy) NSString *elementId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *sourceId;
@property (nonatomic, readonly, copy) NSString *targetId;
@property (nonatomic, readonly, strong) id condition;
@property (nonatomic, readonly, getter=isDefaultFlow) BOOL defaultFlow;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithElementId:(NSString *)elementId
                             name:(NSString *)name
                         sourceId:(NSString *)sourceId
                         targetId:(NSString *)targetId
                        condition:(id)condition
                      defaultFlow:(BOOL)defaultFlow NS_DESIGNATED_INITIALIZER;

@end

#endif /* UDFlowElements_h */

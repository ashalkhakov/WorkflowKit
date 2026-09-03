#ifndef UDProcessDefinition_h
#define UDProcessDefinition_h

#import "UDFlowElements.h"
#import "UDCondition.h"

@interface UDProcessDefinition : NSObject

@property (nonatomic, readonly, copy) NSString *processId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) NSInteger version;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, UDFlowNode *> *nodes;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, UDSequenceFlow *> *flows;
@property (nonatomic, readonly, copy) NSArray<NSString *> *flowOrder;

- (instancetype)init NS_UNAVAILABLE;
- (UDEvent *)startEvent;
- (UDFlowNode *)nodeWithId:(NSString *)elementId;
- (UDSequenceFlow *)flowWithId:(NSString *)flowId;
- (NSArray<UDSequenceFlow *> *)outgoingFlowsFrom:(NSString *)nodeId;
- (NSArray<UDSequenceFlow *> *)incomingFlowsTo:(NSString *)nodeId;
- (NSArray *)boundaryEventsAttachedTo:(NSString *)taskId;

@end

@interface UDDefinitionBuilder : NSObject

+ (instancetype)process:(NSString *)processId version:(NSInteger)version;
+ (instancetype)process:(NSString *)processId
                   name:(NSString *)name
                version:(NSInteger)version;

- (instancetype)addStart:(NSString *)elementId;
- (instancetype)addMessageStart:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addTimerStart:(NSString *)elementId duration:(NSTimeInterval)duration;
- (instancetype)addEnd:(NSString *)elementId;
- (instancetype)addMessageEnd:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addMessageCatch:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addTimerCatch:(NSString *)elementId duration:(NSTimeInterval)duration;
- (instancetype)addMessageThrow:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addBoundaryMessage:(NSString *)elementId
                            onTask:(NSString *)taskId
                           message:(NSString *)messageName
                      interrupting:(BOOL)interrupting;
- (instancetype)addBoundaryTimer:(NSString *)elementId
                          onTask:(NSString *)taskId
                        duration:(NSTimeInterval)duration
                    interrupting:(BOOL)interrupting;

- (instancetype)addUserTask:(NSString *)elementId
                       name:(NSString *)name
                   assignee:(NSString *)assignee;
- (instancetype)addServiceTask:(NSString *)elementId
                        action:(NSString *)actionKey;
- (instancetype)addScriptTask:(NSString *)elementId
                       action:(NSString *)actionKey;

- (instancetype)addExclusive:(NSString *)elementId
                 defaultFlow:(NSString *)defaultFlowId;
- (instancetype)addParallel:(NSString *)elementId;
- (instancetype)addInclusive:(NSString *)elementId
                 defaultFlow:(NSString *)defaultFlowId;
- (instancetype)addEventBased:(NSString *)elementId;
- (instancetype)addSubProcess:(NSString *)elementId
                         name:(NSString *)name
                        inner:(UDProcessDefinition *)inner;
- (instancetype)addBoundaryError:(NSString *)elementId
                          onTask:(NSString *)taskId
                        errorRef:(NSString *)errorRef
                    interrupting:(BOOL)interrupting;
- (instancetype)setBoundsFor:(NSString *)elementId
                           x:(double)x
                           y:(double)y
                       width:(double)width
                      height:(double)height;

- (instancetype)connect:(NSString *)sourceId to:(NSString *)targetId;
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                 flowId:(NSString *)flowId;
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
              condition:(id<UDCondition>)condition;
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                 flowId:(NSString *)flowId
              condition:(id<UDCondition>)condition;
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                    key:(NSString *)key
                     op:(UDComparisonOp)op
                  value:(id)value;

- (UDProcessDefinition *)build:(NSError **)error;

@end

#endif /* UDProcessDefinition_h */

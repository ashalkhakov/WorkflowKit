#import "UDFlowElements.h"
#import "UDFeel.h"

@interface UDProcessDefinition : NSObject

/* The BPMN process id: the key versions are counted under. */
@property (nonatomic, readonly, copy) NSString *processId;
@property (nonatomic, readonly, copy) NSString *name;
/* Assigned by the repository when the definition is deployed: 0, and nil
 * ids, for a definition that was only built or parsed. */
@property (nonatomic, readonly) NSInteger version;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSString *deploymentId;
@property (nonatomic, readonly, copy) NSString *resourceName;
/* camunda:taskPriority on the process: the external tasks' priority where
 * a task sets none. nil when not set; 0 then. */
@property (nonatomic, readonly, strong) NSNumber *defaultTaskPriority;
/* camunda:historyTimeToLive, in days: how long history of an ended
 * instance is kept. nil keeps it. */
@property (nonatomic, readonly, strong) NSNumber *historyTimeToLive;
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
/* Any node in the process, embedded subprocesses included: BPMN ids are
 * unique across the whole document. */
- (UDFlowNode *)flowNodeWithId:(NSString *)elementId;
/* The definition, this one or a subprocess's, whose nodes include it. */
- (UDProcessDefinition *)scopeOfFlowNode:(NSString *)elementId;

@end

@interface UDDefinitionBuilder : NSObject

+ (instancetype)process:(NSString *)processId;
+ (instancetype)process:(NSString *)processId name:(NSString *)name;

- (instancetype)addStart:(NSString *)elementId;
- (instancetype)addMessageStart:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addTimerStart:(NSString *)elementId duration:(NSTimeInterval)duration;
- (instancetype)addEnd:(NSString *)elementId;
- (instancetype)addMessageEnd:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addMessageCatch:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addTimerCatch:(NSString *)elementId duration:(NSTimeInterval)duration;
- (instancetype)addMessageThrow:(NSString *)elementId message:(NSString *)messageName;
- (instancetype)addSignalStart:(NSString *)elementId signal:(NSString *)signalName;
- (instancetype)addSignalCatch:(NSString *)elementId signal:(NSString *)signalName;
- (instancetype)addSignalThrow:(NSString *)elementId signal:(NSString *)signalName;
- (instancetype)addSignalEnd:(NSString *)elementId signal:(NSString *)signalName;
- (instancetype)addBoundarySignal:(NSString *)elementId
                           onTask:(NSString *)taskId
                           signal:(NSString *)signalName
                     interrupting:(BOOL)interrupting;
/* Ends its scope -- the process instance, or the subprocess it is in --
 * with every path in it. */
- (instancetype)addTerminateEnd:(NSString *)elementId;
/* A none intermediate throw event: a milestone the token passes. */
- (instancetype)addIntermediateThrow:(NSString *)elementId;
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
/* Calls the latest version of the process with that key; the binding,
 * inputs and outputs are set afterwards. */
- (instancetype)addCallActivity:(NSString *)elementId
                  calledElement:(NSString *)processKey;
/* version is only read for UDCalledElementBindingVersion. */
- (instancetype)setBinding:(UDCalledElementBinding)binding
                   version:(NSInteger)version
                forElement:(NSString *)elementId;
- (instancetype)addInput:(UDVariableMapping *)mapping forElement:(NSString *)elementId;
- (instancetype)addOutput:(UDVariableMapping *)mapping forElement:(NSString *)elementId;
- (instancetype)addBoundaryError:(NSString *)elementId
                          onTask:(NSString *)taskId
                        errorRef:(NSString *)errorRef
                    interrupting:(BOOL)interrupting;
/* Transaction boundaries and job settings of a node already added. */
- (instancetype)setAsyncBefore:(BOOL)asyncBefore
                    asyncAfter:(BOOL)asyncAfter
                     exclusive:(BOOL)exclusive
                    forElement:(NSString *)elementId;
- (instancetype)setRetryTimeCycle:(NSString *)cycle forElement:(NSString *)elementId;
- (instancetype)setTaskPriority:(NSInteger)priority forElement:(NSString *)elementId;
/* Process-level settings. */
- (instancetype)setDefaultTaskPriority:(NSInteger)priority;
- (instancetype)setHistoryTimeToLive:(NSInteger)days;
/* Names a node or a sequence flow already added. */
- (instancetype)setName:(NSString *)name forElement:(NSString *)elementId;
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
/* A flow taken when the FEEL condition holds: "amount > 1000". A
 * condition that is not FEEL fails -build:. */
- (instancetype)connect:(NSString *)sourceId
                     to:(NSString *)targetId
                   when:(NSString *)condition;

- (UDProcessDefinition *)build:(NSError **)error;

@end

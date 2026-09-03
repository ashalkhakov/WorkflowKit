#ifndef UDRuntimeState_h
#define UDRuntimeState_h

#import "UDTypes.h"
#import <dispatch/dispatch.h>

@class UDProcessDefinition;

@interface UDToken : NSObject

@property (nonatomic, copy) NSString *tokenId;
@property (nonatomic, copy) NSString *nodeId;
@property (nonatomic, copy) NSString *arrivedViaFlowId;
@property (nonatomic) UDTokenState state;
@property (nonatomic, copy) NSString *parentTokenId;
@property (nonatomic, copy) NSString *forkId;
@property (nonatomic) NSUInteger joinExpected;

@end

@interface UDProcessInstance : NSObject

@property (nonatomic, copy) NSString *instanceId;
@property (nonatomic, strong) UDProcessDefinition *definition;
@property (nonatomic, strong) NSMutableDictionary *variables;
@property (nonatomic, strong) NSMutableDictionary *correlationKeys;
@property (nonatomic, strong) NSMutableDictionary *forkExpected;
@property (nonatomic, strong) NSMutableArray<UDToken *> *tokens;
@property (nonatomic, weak) UDProcessInstance *parent;
@property (nonatomic, copy) NSString *hostTokenId;
@property (nonatomic, getter=isCompleted) BOOL completed;
@property (nonatomic, getter=isFailed) BOOL failed;
@property (nonatomic, strong) NSError *error;
@property (nonatomic) NSUInteger tokenSerial;
@property (nonatomic) NSUInteger pendingServices;
@property (nonatomic) NSUInteger pendingTimers;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_semaphore_t quiesce;

- (UDToken *)nextReadyToken;
- (NSArray<UDToken *> *)tokensAtNode:(NSString *)nodeId
                               state:(UDTokenState)state;
- (UDToken *)tokenWithId:(NSString *)tokenId;
- (UDToken *)makeTokenOnNode:(NSString *)nodeId
              arrivedViaFlow:(NSString *)flowId
                      parent:(UDToken *)parent;

@end

#endif /* UDRuntimeState_h */

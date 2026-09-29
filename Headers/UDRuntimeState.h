#ifndef UDRuntimeState_h
#define UDRuntimeState_h

#import "UDTypes.h"

@class UDProcessDefinition;

@interface UDToken : NSObject

/* Unique in the whole instance tree, embedded subprocesses included, so
 * (instanceId, tokenId) names a token from outside the engine. */
@property (nonatomic, copy) NSString *tokenId;
@property (nonatomic, copy) NSString *nodeId;
@property (nonatomic, copy) NSString *arrivedViaFlowId;
@property (nonatomic) UDTokenState state;
@property (nonatomic, copy) NSString *parentTokenId;
@property (nonatomic, copy) NSString *forkId;
@property (nonatomic) NSUInteger joinExpected;
/* When a token waiting on a timer event fires. Absolute, so a restart
 * waits only for the time that is left. */
@property (nonatomic, copy) NSDate *dueAt;

@end

/*
 * The marking of one process instance, or of an embedded subprocess inside
 * one. The engine loads it from the store for a unit of work and drops it
 * afterwards: an object handed out (to a delegate, or by -instanceWithId:)
 * is a snapshot, not a live view.
 */
@interface UDProcessInstance : NSObject

@property (nonatomic, copy) NSString *instanceId;
@property (nonatomic, strong) UDProcessDefinition *definition;
@property (nonatomic, strong) NSMutableDictionary *variables;
@property (nonatomic, strong) NSMutableDictionary *correlationKeys;
@property (nonatomic, strong) NSMutableDictionary *forkExpected;
@property (nonatomic, strong) NSMutableArray<UDToken *> *tokens;
@property (nonatomic, weak) UDProcessInstance *parent;
/* Running embedded subprocesses, keyed by the host token's id. The parent
 * owns them: a child's only other references are weak. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDProcessInstance *> *children;
@property (nonatomic, copy) NSString *hostTokenId;
@property (nonatomic, getter=isCompleted) BOOL completed;
@property (nonatomic, getter=isFailed) BOOL failed;
@property (nonatomic, strong) NSError *error;
/* Kept on the root: children draw their token ids from it. */
@property (nonatomic) NSUInteger tokenSerial;

- (UDProcessInstance *)rootInstance;
- (UDToken *)nextReadyToken;
- (NSArray<UDToken *> *)tokensAtNode:(NSString *)nodeId
                               state:(UDTokenState)state;
- (UDToken *)tokenWithId:(NSString *)tokenId;
/* Searches this instance and its subprocesses; *scope is the one holding
 * the token. */
- (UDToken *)findTokenWithId:(NSString *)tokenId
                       scope:(UDProcessInstance **)scope;
- (UDToken *)makeTokenOnNode:(NSString *)nodeId
              arrivedViaFlow:(NSString *)flowId
                      parent:(UDToken *)parent;
/* Drops completed tokens here and in every subprocess. */
- (void)pruneCompletedTokens;

/* The marking as a property list, subprocesses included, and back. The
 * definition is not in it: the caller supplies the root's, and each
 * child's comes from its host subprocess node. */
- (NSDictionary *)stateDictionary;
+ (instancetype)instanceWithStateDictionary:(NSDictionary *)state
                                 definition:(UDProcessDefinition *)definition
                                      error:(NSError **)error;

@end

#endif /* UDRuntimeState_h */

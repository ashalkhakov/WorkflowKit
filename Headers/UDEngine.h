#ifndef UDEngine_h
#define UDEngine_h

#import "UDProcessDefinition.h"
#import "UDRuntimeState.h"
#import "UDHandlers.h"
#import "UDStore.h"
#import "UDRepositoryService.h"
#import <dispatch/dispatch.h>

@class UDEngine;

/* Called on the engine's callbackQueue, after the unit of work that caused
 * the call has been committed. The instance is a snapshot. */
@protocol UDEngineDelegate <NSObject>
@optional
- (void)engine:(UDEngine *)engine
       instance:(UDProcessInstance *)instance
      didTrace:(NSString *)message;
- (void)engine:(UDEngine *)engine
instanceDidPause:(UDProcessInstance *)instance;
- (void)engine:(UDEngine *)engine
instanceDidFinish:(UDProcessInstance *)instance
         error:(NSError *)error;
- (void)engine:(UDEngine *)engine
       instance:(UDProcessInstance *)instance
didThrowMessage:(NSString *)messageName
        payload:(NSDictionary *)payload;
/* A unit of work could not be committed. Nothing it did took effect; the
 * store still holds the instance as it was before. */
- (void)engine:(UDEngine *)engine
    instanceId:(NSString *)instanceId
didFailToCommit:(NSError *)error;
@end

/*
 * Runs process instances whose state lives in a UDStore.
 *
 * Every input -- a start, a completed user task, a message, a service
 * result, a timer coming due -- is one unit of work: the engine loads the
 * instance, applies the input, fires tokens until none is ready, and
 * commits once. Service calls, work items, thrown messages and delegate
 * callbacks go out only after that commit. The calls below return once
 * their own unit is committed; service tasks it starts run afterwards, and
 * -waitUntilSettled:timeout: waits for them.
 *
 * Variables and correlation values must be property-list values.
 */
@interface UDEngine : NSObject

@property (nonatomic, readonly, strong) UDStore *store;
/* Deployments and definitions. Instances run on the definitions deployed
 * here, read back from the store when the engine has not seen them. */
@property (nonatomic, readonly, strong) UDRepositoryService *repositoryService;
@property (nonatomic, weak) id<UDEngineDelegate> delegate;
@property (nonatomic, strong) id<UDServiceTaskHandler> serviceHandler;
@property (nonatomic, strong) id<UDUserTaskPort> userTaskPort;
/* Where service handlers run. Default: the global default-priority queue. */
@property (nonatomic, UD_DISPATCH_PROPERTY) dispatch_queue_t workerQueue;
/* Where the delegate and the user-task port are called. Default: a serial
 * queue of the engine's own. */
@property (nonatomic, UD_DISPATCH_PROPERTY) dispatch_queue_t callbackQueue;

- (instancetype)initWithStore:(UDStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/* Picks up where a previous run left off: sends the service jobs still in
 * the store again and arms the timers. Call once, after setting the
 * handlers. */
- (BOOL)openWithError:(NSError **)error;
/* Stops the timer scheduler. In-flight service calls still report back. */
- (void)close;

/* Starts the latest deployed version. Answers the new instance's id. */
- (NSString *)startProcess:(NSString *)processId
                 variables:(NSDictionary *)variables
                     error:(NSError **)error;
- (NSString *)startProcess:(NSString *)processId
                 variables:(NSDictionary *)variables
           correlationKeys:(NSDictionary *)correlationKeys
                     error:(NSError **)error;

- (BOOL)completeUserTask:(NSString *)tokenId
              instanceId:(NSString *)instanceId
               variables:(NSDictionary *)variables
                   error:(NSError **)error;

- (BOOL)deliverMessage:(NSString *)messageName
               payload:(NSDictionary *)payload
            instanceId:(NSString *)instanceId
                 error:(NSError **)error;

/* Delivers to every active instance whose correlation key matches. */
- (BOOL)deliverMessage:(NSString *)messageName
               payload:(NSDictionary *)payload
        correlationKey:(NSString *)correlationKey
                 value:(id)value
                 error:(NSError **)error;

- (BOOL)throwError:(NSString *)errorRef
        instanceId:(NSString *)instanceId
             error:(NSError **)error;

/* The instance as last committed. */
- (UDProcessInstance *)instanceWithId:(NSString *)instanceId error:(NSError **)error;

/* Waits until the instance has no service call in flight: every service
 * task it reached has run and its successors have fired. Timers and user
 * tasks are waits, not work, and are not waited for. Answers NO on
 * timeout. */
- (BOOL)waitUntilSettled:(NSString *)instanceId timeout:(NSTimeInterval)timeout;

@end

#endif /* UDEngine_h */

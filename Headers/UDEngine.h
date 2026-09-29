#ifndef UDEngine_h
#define UDEngine_h

#import "UDProcessDefinition.h"
#import "UDRuntimeState.h"
#import "UDHandlers.h"
#import <dispatch/dispatch.h>

@class UDEngine;

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
@end

@interface UDEngine : NSObject

@property (nonatomic, weak) id<UDEngineDelegate> delegate;
@property (nonatomic, strong) id<UDServiceTaskHandler> serviceHandler;
@property (nonatomic, strong) id<UDUserTaskPort> userTaskPort;
@property (nonatomic, strong) id<UDInstanceStore> store;
@property (nonatomic, UD_DISPATCH_PROPERTY) dispatch_queue_t workerQueue;

- (UDProcessInstance *)enqueueProcess:(UDProcessDefinition *)definition
                            variables:(NSDictionary *)variables
                                error:(NSError **)error;

- (UDProcessInstance *)startProcess:(UDProcessDefinition *)definition
                          variables:(NSDictionary *)variables
                              error:(NSError **)error;

- (BOOL)completeUserTask:(NSString *)tokenId
                instance:(UDProcessInstance *)instance
               variables:(NSDictionary *)variables
                   error:(NSError **)error;

- (BOOL)resumeInstance:(UDProcessInstance *)instance error:(NSError **)error;

- (BOOL)deliverMessage:(NSString *)messageName
               payload:(NSDictionary *)payload
              instance:(UDProcessInstance *)instance
                 error:(NSError **)error;

- (BOOL)deliverMessage:(NSString *)messageName
               payload:(NSDictionary *)payload
       correlationKey:(NSString *)correlationKey
                value:(id)value
                error:(NSError **)error;

- (BOOL)throwError:(NSString *)errorRef
          instance:(UDProcessInstance *)instance
             error:(NSError **)error;

- (void)drainInstance:(UDProcessInstance *)instance;

@end

#endif /* UDEngine_h */

#ifndef UDHandlers_h
#define UDHandlers_h

#import "UDRuntimeState.h"

@class UDTask;
@class UDToken;
@class UDProcessInstance;
@class UDServiceInvocation;

@interface UDServiceResult : NSObject
@property (nonatomic, copy) NSString *actionKey;
@property (nonatomic, copy) NSDictionary *variables;
@property (nonatomic, strong) NSError *error;
@end

/*
 * One call of a service or script task. It is sent only after the state
 * that asked for it is committed, and sent again if the engine restarts
 * before the result is committed, so a handler sees each job at least
 * once: jobId stays the same across repeats and is the idempotency key.
 */
@interface UDServiceInvocation : NSObject

@property (nonatomic, readonly, copy) NSString *jobId;
@property (nonatomic, readonly, copy) NSString *actionKey;
@property (nonatomic, readonly, copy) NSDictionary *variables;
@property (nonatomic, readonly, copy) NSString *instanceId;
@property (nonatomic, readonly, copy) NSString *tokenId;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;

- (instancetype)initWithJobId:(NSString *)jobId
                    actionKey:(NSString *)actionKey
                    variables:(NSDictionary *)variables
                   instanceId:(NSString *)instanceId
                      tokenId:(NSString *)tokenId;

/* Variables must be property-list values; anything else fails the task. */
- (void)finishWithVariables:(NSDictionary *)outVars error:(NSError *)error;

@end

@protocol UDServiceTaskHandler <NSObject>
- (void)performInvocation:(UDServiceInvocation *)invocation;
@end

@protocol UDUserTaskPort <NSObject>
- (void)publishWorkItemForToken:(UDToken *)token
                       instance:(UDProcessInstance *)instance
                           task:(UDTask *)task;
@end

#endif /* UDHandlers_h */

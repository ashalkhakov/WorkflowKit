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

@interface UDServiceInvocation : NSObject

@property (nonatomic, readonly, copy) NSString *actionKey;
@property (nonatomic, readonly, copy) NSDictionary *variables;
@property (nonatomic, readonly, copy) NSString *tokenId;
@property (nonatomic, readonly, weak) UDProcessInstance *instance;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;

- (instancetype)initWithActionKey:(NSString *)actionKey
                        variables:(NSDictionary *)variables
                          tokenId:(NSString *)tokenId
                         instance:(UDProcessInstance *)instance;

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

@protocol UDInstanceStore <NSObject>
- (BOOL)saveInstance:(UDProcessInstance *)instance error:(NSError **)error;
- (UDProcessInstance *)loadInstance:(NSString *)instanceId error:(NSError **)error;
@end

#endif /* UDHandlers_h */

#import "WFTypes.h"

@class WFServiceInvocation;

@interface WFServiceResult : NSObject
@property (nonatomic, copy) NSString *topic;
@property (nonatomic, copy) NSDictionary *variables;
@property (nonatomic, strong) NSError *error;
@end

/*
 * One external task, fetched and locked by the engine's in-process worker
 * for the service handler. The task was created by a committed command,
 * and it is offered again if its lock runs out or the engine restarts
 * before the result is committed, so a handler sees each task at least
 * once: externalTaskId is the same across repeats and is the idempotency
 * key.
 */
@interface WFServiceInvocation : NSObject

@property (nonatomic, readonly, copy) NSString *externalTaskId;
@property (nonatomic, readonly, copy) NSString *topic;
@property (nonatomic, readonly, copy) NSDictionary *variables;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *activityId;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;

- (instancetype)initWithExternalTaskId:(NSString *)externalTaskId
                                 topic:(NSString *)topic
                             variables:(NSDictionary *)variables
                     processInstanceId:(NSString *)processInstanceId
                            activityId:(NSString *)activityId;

/*
 * Completes the task. The variables are set on the process (existing ones
 * where they are, new ones on the process instance) and must be values the
 * engine stores: strings, numbers, dates, data, null, or arrays and
 * dictionaries of JSON values.
 *
 * An error whose userInfo carries WFErrorRefKey is a BPMN error
 * with that code, for an error boundary event to catch. Any other error is
 * a failure: the task is retried, three attempts in all.
 */
- (void)finishWithVariables:(NSDictionary *)outVars error:(NSError *)error;

@end

@protocol WFServiceTaskHandler <NSObject>
- (void)performInvocation:(WFServiceInvocation *)invocation;
@end

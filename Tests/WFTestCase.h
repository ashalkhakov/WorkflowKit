#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "WorkflowKit.h"

/* A service handler that answers each topic as the test tells it to. */
@interface WFMapHandler : NSObject <WFServiceTaskHandler>
@property (nonatomic, strong) NSMutableDictionary *results;
/* Topic to the BPMN error code the task answers with. */
@property (nonatomic, strong) NSMutableDictionary *bpmnErrors;
/* Topic to the number of failures before the task succeeds. */
@property (nonatomic, strong) NSMutableDictionary *failures;
/* Invocations taken and never finished, as if the process died mid-call. */
@property (nonatomic) BOOL drops;
@property (nonatomic, strong) NSMutableArray *taskIds;
/* How many invocations it has taken. */
- (NSUInteger)calls;
@end

/* A delegate that completes every task as it is created and records the
 * instances that end. */
@interface WFCompletingDelegate : NSObject <WFProcessEngineDelegate>
@property (nonatomic, strong) NSMutableArray *ended;
@end

/* The engine fixtures and helpers every test case shares. */
@interface WFTestCase : XCTestCase

- (WFProcessEngine *)engineWithHandler:(WFMapHandler *)handler;

- (NSURL *)temporarySQLiteURL;

- (WFProcessEngine *)SQLiteEngineAtURL:(NSURL *)url handler:(WFMapHandler *)handler;

- (void)deploy:(WFProcessDefinition *)definition engine:(WFProcessEngine *)engine;

/* Deploys, starts, and waits for the engine's own work on the instance. */
- (NSString *)run:(WFProcessDefinition *)definition
           engine:(WFProcessEngine *)engine
        variables:(NSDictionary *)variables;

- (BOOL)ended:(NSString *)processInstanceId engine:(WFProcessEngine *)engine;

- (NSDictionary *)variables:(NSString *)processInstanceId engine:(WFProcessEngine *)engine;

- (NSArray *)active:(NSString *)processInstanceId engine:(WFProcessEngine *)engine;

- (WFWorkItem *)task:(NSString *)key of:(NSString *)processInstanceId engine:(WFProcessEngine *)engine;

- (void)complete:(NSString *)key
              of:(NSString *)processInstanceId
          engine:(WFProcessEngine *)engine
       variables:(NSDictionary *)variables;

/* Timers are waits, not work: poll history until the instance ends. */
- (BOOL)waitForEnd:(NSString *)processInstanceId
            engine:(WFProcessEngine *)engine
           seconds:(NSTimeInterval)seconds;

- (BOOL)waitForActive:(NSString *)activityId
                   in:(NSString *)processInstanceId
               engine:(WFProcessEngine *)engine;

- (NSArray *)rows:(NSString *)entity engine:(WFProcessEngine *)engine;

- (WFProcessDefinition *)approvalDefinition;

/* An exclusive gateway behind an async continuation, with no default: it
 * fails until "amount" is set. */
- (WFProcessDefinition *)fragileDefinition:(NSString *)cycle;

- (void)assertNode:(WFFlowNode *)a matches:(WFFlowNode *)b;

- (void)assertDefinition:(WFProcessDefinition *)a matches:(WFProcessDefinition *)b;

@end

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "UDWorkflow.h"

/* A service handler that answers each topic as the test tells it to. */
@interface UDMapHandler : NSObject <UDServiceTaskHandler>
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
@interface UDCompletingDelegate : NSObject <UDProcessEngineDelegate>
@property (nonatomic, strong) NSMutableArray *ended;
@end

/* The engine fixtures and helpers every test case shares. */
@interface UDWorkflowTestCase : XCTestCase

- (UDProcessEngine *)engineWithHandler:(UDMapHandler *)handler;

- (NSURL *)temporarySQLiteURL;

- (UDProcessEngine *)SQLiteEngineAtURL:(NSURL *)url handler:(UDMapHandler *)handler;

- (void)deploy:(UDProcessDefinition *)definition engine:(UDProcessEngine *)engine;

/* Deploys, starts, and waits for the engine's own work on the instance. */
- (NSString *)run:(UDProcessDefinition *)definition
           engine:(UDProcessEngine *)engine
        variables:(NSDictionary *)variables;

- (BOOL)ended:(NSString *)processInstanceId engine:(UDProcessEngine *)engine;

- (NSDictionary *)variables:(NSString *)processInstanceId engine:(UDProcessEngine *)engine;

- (NSArray *)active:(NSString *)processInstanceId engine:(UDProcessEngine *)engine;

- (UDWorkItem *)task:(NSString *)key of:(NSString *)processInstanceId engine:(UDProcessEngine *)engine;

- (void)complete:(NSString *)key
              of:(NSString *)processInstanceId
          engine:(UDProcessEngine *)engine
       variables:(NSDictionary *)variables;

/* Timers are waits, not work: poll history until the instance ends. */
- (BOOL)waitForEnd:(NSString *)processInstanceId
            engine:(UDProcessEngine *)engine
           seconds:(NSTimeInterval)seconds;

- (BOOL)waitForActive:(NSString *)activityId
                   in:(NSString *)processInstanceId
               engine:(UDProcessEngine *)engine;

- (NSArray *)rows:(NSString *)entity engine:(UDProcessEngine *)engine;

- (UDProcessDefinition *)approvalDefinition;

/* An exclusive gateway behind an async continuation, with no default: it
 * fails until "amount" is set. */
- (UDProcessDefinition *)fragileDefinition:(NSString *)cycle;

- (void)assertNode:(UDFlowNode *)a matches:(UDFlowNode *)b;

- (void)assertDefinition:(UDProcessDefinition *)a matches:(UDProcessDefinition *)b;

@end

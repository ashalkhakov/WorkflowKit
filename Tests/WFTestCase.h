#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "WorkflowKit.h"
#ifdef WORKFLOWKIT_ODATA
#import "WFODataService.h"
#endif

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

/* What the delegates and listeners below were called for, in order:
 * "event@activity", with " canceled" when so. */
@interface WFTestRecorder : NSObject
+ (void)reset;
+ (void)record:(NSString *)entry;
+ (NSArray<NSString *> *)entries;
@end

/* Sets "approved" to whether "amount" is below its field "limit" (given
 * by key-value coding), and records "approve". */
@interface WFApproveDelegate : NSObject <WFActivityDelegate>
@property (nonatomic, strong) NSNumber *limit;
@end

/* Fails as its field "mode" says: "bpmn" with a BPMN error REJECTED,
 * anything else with a plain error. */
@interface WFFailingDelegate : NSObject <WFActivityDelegate>
@end

/* Records each call; a task listener with a field "assignee" assigns the
 * task to it. */
@interface WFRecordingListener : NSObject <WFExecutionListener, WFTaskListener>
@end

/* An order form's handler: it opens <order> with the lines variable's
 * lines and its total, and takes back only the total, as a variable, and
 * the number of lines; an order without a total is refused. */
@interface WFOrderFormHandler : NSObject <WFFormHandler>
@end

/* Registers a WFApproveDelegate as "approver" and a WFRecordingListener
 * as "recorder". */
@interface WFTestPlugin : NSObject <WFEnginePlugin>
@end

/* The engine fixtures and helpers every test case shares.
 *
 * The store the engines run on is a backend's choice. Each backend's file
 * (WFInMemoryTests.m, WFSQLiteTests.m, WFPostgreSQLTests.m, WFMySQLTests.m)
 * subclasses this once, saying how to open a store, and gives every area
 * a class of its own - WFGatewayInMemoryTests, WFGatewaySQLiteTests, ... -
 * whose @implementation #includes the area's tests from WFGatewayTests.inc.
 * They are included rather than inherited because tools-xctest runs only
 * the test methods a class declares itself: a subclass of a class full of
 * tests runs none of them. */
@interface WFTestCase : XCTestCase

/* What a backend supplies: a store at url, one that outlives its engine
 * so that a second engine opened there sees what the first saved, or a
 * store of its own when url is nil. */
- (WFStore *)storeAtURL:(NSURL *)url;

/* A fresh engine on a store of its own. */
- (WFProcessEngine *)engineWithHandler:(WFMapHandler *)handler;

/* A new name for a store, to open with -durableEngineAtURL:. */
- (NSURL *)temporaryStoreURL;

- (WFProcessEngine *)durableEngineAtURL:(NSURL *)url handler:(WFMapHandler *)handler;

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

/* A backend on a database server, reached through one of FreeCoreData's
 * SQL stores: each store is a schema of its own in the database the
 * environment names, dropped after the test. */
@interface WFServerTestCase : WFTestCase

- (Class)storeClass;
- (NSString *)storeType;
- (NSString *)schemaNameOptionKey;
- (NSString *)URLEnvironmentVariableName;

@end

#import "WFStore.h"
#import "WFHandlers.h"
#import "WFRepositoryService.h"
#import "WFRuntimeService.h"
#import "WFTaskService.h"
#import "WFHistoryService.h"
#import "WFManagementService.h"
#import "WFExternalTaskService.h"
#import "WFDecisionService.h"
#import "WFDelegation.h"
#import <dispatch/dispatch.h>

@class WFProcessEngine;

/* Called on the engine's callbackQueue after the command that caused the
 * call has committed. */
@protocol WFProcessEngineDelegate <NSObject>
@optional
- (void)processEngine:(WFProcessEngine *)engine
         taskCreated:(WFWorkItem *)task;
- (void)processEngine:(WFProcessEngine *)engine
processInstanceEnded:(WFProcessInstance *)instance;
- (void)processEngine:(WFProcessEngine *)engine
    processInstanceId:(NSString *)processInstanceId
      didThrowMessage:(NSString *)messageName
            variables:(NSDictionary *)variables;
/* A command the engine ran on its own -- a timer, a service result --
 * failed and was rolled back. */
- (void)processEngine:(WFProcessEngine *)engine
        commandFailed:(NSError *)error;
@end

/*
 * The process engine: a Core Data store, the services over it, a job
 * executor for timers, and an in-process worker that hands external tasks
 * to the service handler. See docs/execution-model.md.
 */
@interface WFProcessEngine : NSObject

@property (nonatomic, readonly, strong) WFStore *store;
@property (nonatomic, readonly, strong) WFRepositoryService *repositoryService;
@property (nonatomic, readonly, strong) WFRuntimeService *runtimeService;
@property (nonatomic, readonly, strong) WFTaskService *taskService;
@property (nonatomic, readonly, strong) WFHistoryService *historyService;
@property (nonatomic, readonly, strong) WFManagementService *managementService;
@property (nonatomic, readonly, strong) WFExternalTaskService *externalTaskService;
@property (nonatomic, readonly, strong) WFDecisionService *decisionService;

/* Owner of the engine's job locks and worker id of its in-process worker.
 * Stable across restarts on one host by default, so an engine that
 * restarts takes back what it held. Engines sharing a store need distinct
 * identifiers. */
@property (nonatomic, copy) NSString *identifier;
/* How much history is written. Default WFHistoryLevelAudit. The first
 * -openWithError: records it in the store, and later ones refuse a
 * different level: engines sharing a store write the same history. */
@property (nonatomic) WFHistoryLevel historyLevel;
/* How often history cleanup runs by itself, in seconds, after
 * -openWithError:. 0, the default, leaves it to
 * -[WFHistoryService cleanUpHistory:error:]. */
@property (nonatomic) NSTimeInterval historyCleanupInterval;
/* Whether the job executor runs jobs by itself. With NO, jobs wait until
 * managementService runs them -- for tests that step through async
 * continuations and timers. Default YES. */
@property (nonatomic) BOOL jobExecutorActive;
/* How long a fetched external task or acquired job stays locked. Default
 * five minutes. */
@property (nonatomic) NSTimeInterval lockDuration;

@property (nonatomic, weak) id<WFProcessEngineDelegate> delegate;
/* Handles every external task's topic in process: the engine's own
 * worker fetches each task as it is created and hands it over, with the
 * activity's retry cycle for failures. Without one, external tasks wait
 * for workers using externalTaskService. */
@property (nonatomic, strong) id<WFServiceTaskHandler> serviceHandler;
/* Where the service handler runs. Default: the global default-priority
 * queue. */
@property (nonatomic, WF_DISPATCH_PROPERTY) dispatch_queue_t workerQueue;
/* Where the delegate is called. Default: a serial queue of the engine's. */
@property (nonatomic, WF_DISPATCH_PROPERTY) dispatch_queue_t callbackQueue;

- (instancetype)initWithStore:(WFStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/* Starts the job executor and the in-process worker, taking back the
 * locks this engine held before a restart. Call once, after setting the
 * handler and the delegate. */
/*
 * Delegates and listeners (see WFDelegation.h). An object registered under
 * a name answers camunda:delegateExpression="${name}"; a class registered
 * under a name answers camunda:class="name" -- a Camunda file's Java class
 * name, say -- as any class linked into the host or loaded from a plugin
 * does under its own. Registration is for the engine's life, and may
 * happen before or after it opens.
 */
- (void)registerDelegate:(id)delegate forName:(NSString *)name;
- (void)registerDelegateClass:(Class)delegateClass forName:(NSString *)name;
- (void)addPlugin:(id<WFEnginePlugin>)plugin;
/* Loads every bundle in the directory (.plugin or .bundle) and adds its
 * principal class, which conforms to WFEnginePlugin, as a plugin. NO, with
 * an error, at the first bundle that does not load or is not a plugin. */
- (BOOL)loadPluginsInDirectory:(NSURL *)directory error:(NSError **)error;

- (BOOL)openWithError:(NSError **)error;
- (void)close;

/* Waits until the instance has nothing the engine runs by itself in
 * flight or due now: no external task with the in-process worker, no due
 * timer. Timers due later and user tasks are waits, not work. Answers NO
 * on timeout. For tests and demos. */
- (BOOL)waitUntilSettled:(NSString *)processInstanceId timeout:(NSTimeInterval)timeout;

@end

#ifndef UDProcessEngine_h
#define UDProcessEngine_h

#import "UDStore.h"
#import "UDHandlers.h"
#import "UDRepositoryService.h"
#import "UDRuntimeService.h"
#import "UDTaskService.h"
#import "UDHistoryService.h"
#import "UDManagementService.h"
#import <dispatch/dispatch.h>

@class UDProcessEngine;

/* Called on the engine's callbackQueue after the command that caused the
 * call has committed. */
@protocol UDProcessEngineDelegate <NSObject>
@optional
- (void)processEngine:(UDProcessEngine *)engine
         taskCreated:(UDWorkItem *)task;
- (void)processEngine:(UDProcessEngine *)engine
processInstanceEnded:(UDProcessInstance *)instance;
- (void)processEngine:(UDProcessEngine *)engine
    processInstanceId:(NSString *)processInstanceId
      didThrowMessage:(NSString *)messageName
            variables:(NSDictionary *)variables;
/* A command the engine ran on its own -- a timer, a service result --
 * failed and was rolled back. */
- (void)processEngine:(UDProcessEngine *)engine
        commandFailed:(NSError *)error;
@end

/*
 * The process engine: a Core Data store, the services over it, a job
 * executor for timers, and an in-process worker that hands external tasks
 * to the service handler. See docs/execution-model.md.
 */
@interface UDProcessEngine : NSObject

@property (nonatomic, readonly, strong) UDStore *store;
@property (nonatomic, readonly, strong) UDRepositoryService *repositoryService;
@property (nonatomic, readonly, strong) UDRuntimeService *runtimeService;
@property (nonatomic, readonly, strong) UDTaskService *taskService;
@property (nonatomic, readonly, strong) UDHistoryService *historyService;
@property (nonatomic, readonly, strong) UDManagementService *managementService;

/* Owner of the engine's job locks and worker id of its in-process worker.
 * Stable across restarts on one host by default, so an engine that
 * restarts takes back what it held. Engines sharing a store need distinct
 * identifiers. */
@property (nonatomic, copy) NSString *identifier;
/* Whether the job executor runs jobs by itself. With NO, jobs wait until
 * managementService runs them -- for tests that step through async
 * continuations and timers. Default YES. */
@property (nonatomic) BOOL jobExecutorActive;
/* How long a fetched external task or acquired job stays locked. Default
 * five minutes. */
@property (nonatomic) NSTimeInterval lockDuration;

@property (nonatomic, weak) id<UDProcessEngineDelegate> delegate;
/* Handles every external task's topic in process. Without one, external
 * tasks wait for a worker outside the engine. */
@property (nonatomic, strong) id<UDServiceTaskHandler> serviceHandler;
/* Where the service handler runs. Default: the global default-priority
 * queue. */
@property (nonatomic, UD_DISPATCH_PROPERTY) dispatch_queue_t workerQueue;
/* Where the delegate is called. Default: a serial queue of the engine's. */
@property (nonatomic, UD_DISPATCH_PROPERTY) dispatch_queue_t callbackQueue;

- (instancetype)initWithStore:(UDStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/* Starts the job executor and the in-process worker, taking back the
 * locks this engine held before a restart. Call once, after setting the
 * handler and the delegate. */
- (BOOL)openWithError:(NSError **)error;
- (void)close;

/* Waits until the instance has nothing the engine runs by itself in
 * flight or due now: no external task with the in-process worker, no due
 * timer. Timers due later and user tasks are waits, not work. Answers NO
 * on timeout. For tests and demos. */
- (BOOL)waitUntilSettled:(NSString *)processInstanceId timeout:(NSTimeInterval)timeout;

@end

#endif /* UDProcessEngine_h */

#import "WFProcessEngine+Internal.h"
#import "WFCommandContext.h"
#import "WFEntities.h"
#import "WFFlowElements.h"
#import "WFProcessDefinition.h"
#import "WFDuration.h"
#include <time.h>

/* External-task results and jobs of one process instance run one after
 * another, on the same serial queue -- the reference's exclusive jobs --
 * and the queues are few however many instances there are. */
#define WF_STRIPES 8
/* Jobs and external tasks taken per scheduler pass. */
#define WF_BATCH 64
/* Attempts at a command the engine runs by itself before it gives up on a
 * conflict. */
#define WF_CONFLICT_ATTEMPTS 5

/* Runs the block on the queue inside a pool of its own. Apple's libdispatch
 * drains one after each block; on GNUstep what a block autoreleases waits
 * for its worker thread to go idle, and a busy engine keeps it busy. */
static void
WFAsync(dispatch_queue_t queue, dispatch_block_t block)
{
	dispatch_async(queue, ^{
		@autoreleasepool {
			block();
		}
	});
}

static BOOL
WFIsConflict(NSError *error)
{
	return [[error domain] isEqualToString:WFErrorDomain]
		&& [error code] == WFErrorConflict;
}

@interface WFProcessEngine ()
- (void)wf_invocation:(WFServiceInvocation *)invocation
            didFinish:(WFServiceResult *)result;
@end

@implementation WFProcessEngine
{
	dispatch_queue_t _stripes[WF_STRIPES];
	dispatch_queue_t _schedulerQueue;
	dispatch_source_t _scheduler;
	BOOL _closed;
	NSCondition *_settle;
	NSMutableDictionary *_busy;
	int64_t _sequence;
	dispatch_source_t _cleanup;
	/* Name to a registered delegate object, and to a registered class. */
	NSMutableDictionary *_delegates;
	NSMutableDictionary *_delegateClasses;
	NSMutableArray *_plugins;
}

- (instancetype)initWithStore:(WFStore *)store
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_store = store;
	_repositoryService = [[WFRepositoryService alloc] initWithStore:store];
	[_repositoryService wf_setEngine:self];
	_runtimeService = [[WFRuntimeService alloc] initWithProcessEngine:self];
	_taskService = [[WFTaskService alloc] initWithProcessEngine:self];
	_formService = [[WFFormService alloc] initWithProcessEngine:self];
	_historyService = [[WFHistoryService alloc] initWithProcessEngine:self];
	_managementService = [[WFManagementService alloc] initWithProcessEngine:self];
	_externalTaskService = [[WFExternalTaskService alloc] initWithProcessEngine:self];
	_decisionService = [[WFDecisionService alloc] initWithProcessEngine:self];
	_delegates = [NSMutableDictionary dictionary];
	_delegateClasses = [NSMutableDictionary dictionary];
	_plugins = [NSMutableArray array];
	_jobExecutorActive = YES;
	_historyLevel = WFHistoryLevelAudit;
	_identifier = [NSString stringWithFormat:@"workflowkit@%@",
		[[NSProcessInfo processInfo] hostName]];
	_lockDuration = 300;
	_settle = [[NSCondition alloc] init];
	_busy = [NSMutableDictionary dictionary];
	self.workerQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	{
		dispatch_queue_t q = dispatch_queue_create("workflowkit.callbacks",
			DISPATCH_QUEUE_SERIAL);
		self.callbackQueue = q;
		WFDispatchRelease(q);
	}
	for (NSUInteger i = 0; i < WF_STRIPES; i++) {
		_stripes[i] = dispatch_queue_create("workflowkit.instances", DISPATCH_QUEUE_SERIAL);
	}
	_schedulerQueue = dispatch_queue_create("workflowkit.scheduler", DISPATCH_QUEUE_SERIAL);
	_scheduler = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _schedulerQueue);
	__weak WFProcessEngine *weakSelf = self;
	dispatch_source_set_event_handler(_scheduler, ^{
		@autoreleasepool {
			[weakSelf schedulerFired];
		}
	});
	dispatch_source_set_timer(_scheduler, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
	dispatch_resume(_scheduler);
	_repositoryService.didStoreDeployment = ^{
		[weakSelf reschedule];
	};
	return self;
}

- (void)dealloc
{
	[self close];
	WFDispatchRelease(_scheduler);
	WFDispatchRelease(_schedulerQueue);
	for (NSUInteger i = 0; i < WF_STRIPES; i++) {
		WFDispatchRelease(_stripes[i]);
	}
	if (_workerQueue != NULL) {
		WFDispatchRelease(_workerQueue);
	}
	if (_callbackQueue != NULL) {
		WFDispatchRelease(_callbackQueue);
	}
}

- (void)setWorkerQueue:(dispatch_queue_t)workerQueue
{
	if (workerQueue == _workerQueue) {
		return;
	}
	if (workerQueue != NULL) {
		WFDispatchRetain(workerQueue);
	}
	if (_workerQueue != NULL) {
		WFDispatchRelease(_workerQueue);
	}
	_workerQueue = workerQueue;
}

- (void)setCallbackQueue:(dispatch_queue_t)callbackQueue
{
	if (callbackQueue == _callbackQueue) {
		return;
	}
	if (callbackQueue != NULL) {
		WFDispatchRetain(callbackQueue);
	}
	if (_callbackQueue != NULL) {
		WFDispatchRelease(_callbackQueue);
	}
	_callbackQueue = callbackQueue;
}

- (dispatch_queue_t)stripeFor:(NSString *)processInstanceId
{
	return _stripes[[processInstanceId hash] % WF_STRIPES];
}

- (dispatch_queue_t)wf_queueFor:(NSString *)key
{
	return [self stripeFor:key];
}

#pragma mark - Delegates and plugins

- (void)registerDelegate:(id)delegate forName:(NSString *)name
{
	@synchronized (_delegates) {
		if (delegate == nil) {
			[_delegates removeObjectForKey:name];
		} else {
			[_delegates setObject:delegate forKey:name];
		}
	}
}

- (void)registerDelegateClass:(Class)delegateClass forName:(NSString *)name
{
	@synchronized (_delegates) {
		if (delegateClass == Nil) {
			[_delegateClasses removeObjectForKey:name];
		} else {
			[_delegateClasses setObject:delegateClass forKey:name];
		}
	}
}

- (void)addPlugin:(id<WFEnginePlugin>)plugin
{
	@synchronized (_delegates) {
		[_plugins addObject:plugin];
	}
	[plugin registerWithEngine:self];
}

- (BOOL)loadPluginsInDirectory:(NSURL *)directory error:(NSError **)error
{
	NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory
	                                                 includingPropertiesForKeys:nil
	                                                                    options:0
	                                                                      error:error];
	if (entries == nil) {
		return NO;
	}
	NSArray *sorted = [entries sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
		return [[a lastPathComponent] compare:[b lastPathComponent]];
	}];
	for (NSURL *url in sorted) {
		NSString *extension = [url pathExtension];
		if (![extension isEqualToString:@"plugin"] && ![extension isEqualToString:@"bundle"]) {
			continue;
		}
		NSBundle *bundle = [NSBundle bundleWithURL:url];
		NSError *loadError = nil;
		Class principal = [bundle loadAndReturnError:&loadError] ? [bundle principalClass] : Nil;
		if (principal == Nil || ![principal conformsToProtocol:@protocol(WFEnginePlugin)]) {
			if (error != NULL) {
				*error = [NSError errorWithDomain:WFErrorDomain code:WFErrorInvalidState userInfo:@{
					NSLocalizedDescriptionKey: [NSString stringWithFormat:
						@"%@ is not a plugin: %@", [url lastPathComponent],
						loadError != nil ? [loadError localizedDescription]
							: @"its principal class does not conform to WFEnginePlugin"] }];
			}
			return NO;
		}
		[self addPlugin:[[principal alloc] init]];
	}
	return YES;
}

- (id)wf_delegateFor:(WFDelegateReference *)reference protocol:(Protocol *)protocol error:(NSError **)error
{
	id delegate = nil;
	if (reference.delegateName != nil) {
		@synchronized (_delegates) {
			delegate = [_delegates objectForKey:reference.delegateName];
		}
	} else {
		Class delegateClass = Nil;
		@synchronized (_delegates) {
			delegateClass = [_delegateClasses objectForKey:reference.className];
		}
		delegateClass = delegateClass ?: NSClassFromString(reference.className);
		delegate = [[delegateClass alloc] init];
	}
	if (delegate == nil || ![delegate conformsToProtocol:protocol]) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:WFErrorDomain code:WFErrorHandler userInfo:@{
				NSLocalizedDescriptionKey: [NSString stringWithFormat:delegate == nil
					? @"%@ is not registered, loaded or linked" : @"%@ does not conform to %@",
					reference, NSStringFromProtocol(protocol)] }];
		}
		return nil;
	}
	return delegate;
}

#pragma mark - Commands

- (BOOL)wf_runCommand:(BOOL (^)(WFCommandContext *, NSError **))body error:(NSError **)error
{
	WFCommandContext *command = [[WFCommandContext alloc] initWithEngine:self];
	return [command execute:body error:error];
}

/* A command the engine runs by itself: retried on conflict, and reported
 * to the delegate when it fails for good. */
- (BOOL)runInternal:(BOOL (^)(WFCommandContext *, NSError **))body error:(NSError **)error
{
	NSError *localError = nil;
	for (int attempt = 0; attempt < WF_CONFLICT_ATTEMPTS; attempt++) {
		localError = nil;
		if ([self wf_runCommand:body error:&localError]) {
			return YES;
		}
		if (!WFIsConflict(localError)) {
			break;
		}
	}
	[self notify:^(id<WFProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:@selector(processEngine:commandFailed:)]) {
			[delegate processEngine:self commandFailed:localError];
		}
	}];
	if (error != NULL) {
		*error = localError;
	}
	return NO;
}

- (void)notify:(void (^)(id<WFProcessEngineDelegate> delegate))call
{
	id<WFProcessEngineDelegate> delegate = self.delegate;
	if (delegate == nil) {
		return;
	}
	WFAsync(self.callbackQueue, ^{
		call(delegate);
	});
}

#pragma mark - After commit

- (void)wf_taskCreated:(WFWorkItem *)task
{
	[self notify:^(id<WFProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:@selector(processEngine:taskCreated:)]) {
			[delegate processEngine:self taskCreated:task];
		}
	}];
}

- (void)wf_processInstanceEnded:(WFProcessInstance *)instance
{
	[self notify:^(id<WFProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:@selector(processEngine:processInstanceEnded:)]) {
			[delegate processEngine:self processInstanceEnded:instance];
		}
	}];
}

- (void)wf_messageThrown:(NSString *)messageName
               variables:(NSDictionary *)variables
       processInstanceId:(NSString *)processInstanceId
{
	[self notify:^(id<WFProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:
		         @selector(processEngine:processInstanceId:didThrowMessage:variables:)]) {
			[delegate processEngine:self
			      processInstanceId:processInstanceId
			        didThrowMessage:messageName
			              variables:variables];
		}
	}];
}

- (void)wf_externalTaskCreated:(NSString *)externalTaskId
             processInstanceId:(NSString *)processInstanceId
{
	if (self.serviceHandler == nil) {
		return;
	}
	[self beginWork:processInstanceId];
	WFAsync([self stripeFor:processInstanceId], ^{
		[self lockAndInvoke:externalTaskId processInstanceId:processInstanceId];
	});
}

- (void)wf_jobCreated:(NSString *)jobId
    processInstanceId:(NSString *)processInstanceId
              dueDate:(NSDate *)dueDate
            exclusive:(BOOL)exclusive
{
	if (self.jobExecutorActive && [dueDate timeIntervalSinceNow] <= 0) {
		[self dispatchJob:jobId processInstanceId:processInstanceId exclusive:exclusive];
		return;
	}
	[self reschedule];
}

/* Exclusive jobs run on their instance's queue, one after another with
 * its other work; the rest beside it. A timer start job has no instance:
 * its own id keys it. */
- (void)dispatchJob:(NSString *)jobId
  processInstanceId:(NSString *)processInstanceId
          exclusive:(BOOL)exclusive
{
	NSString *key = processInstanceId ?: jobId;
	[self beginWork:key];
	dispatch_queue_t queue = exclusive ? [self stripeFor:key]
		: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	WFAsync(queue, ^{
		[self wf_runJob:jobId force:NO error:NULL];
		[self reschedule];
		[self endWork:key];
	});
}

#pragma mark - The in-process worker

/* On the instance's stripe. Locks the task for this engine and hands it to
 * the service handler; the matching -endWork: follows its result. */
- (void)lockAndInvoke:(NSString *)externalTaskId processInstanceId:(NSString *)processInstanceId
{
	id<WFServiceTaskHandler> handler = self.serviceHandler;
	WFExternalTask *task = handler == nil ? nil
		: [self.externalTaskService wf_lockTask:externalTaskId
		                               workerId:self.identifier
		                               duration:self.lockDuration];
	if (task == nil) {
		[self endWork:processInstanceId];
		return;
	}
	WFServiceInvocation *invocation =
		[[WFServiceInvocation alloc] initWithExternalTaskId:task.externalTaskId
		                                              topic:task.topic
		                                          variables:task.variables
		                                  processInstanceId:task.processInstanceId
		                                         activityId:task.activityId];
	invocation.target = self;
	invocation.action = @selector(wf_invocation:didFinish:);
	WFAsync(self.workerQueue, ^{
		[handler performInvocation:invocation];
	});
	[self reschedule];
}

- (void)wf_invocation:(WFServiceInvocation *)invocation didFinish:(WFServiceResult *)result
{
	NSString *processInstanceId = invocation.processInstanceId;
	WFAsync([self stripeFor:processInstanceId], ^{
		[self reportResult:result forExternalTask:invocation.externalTaskId];
		[self endWork:processInstanceId];
	});
}

/* The in-process worker's side of the external task service: complete,
 * report a BPMN error, or report a failure with the activity's retry
 * cycle -- three attempts without one. */
- (void)reportResult:(WFServiceResult *)result forExternalTask:(NSString *)externalTaskId
{
	NSString *workerId = self.identifier;
	WFExternalTaskService *service = self.externalTaskService;
	NSError *failure = result.error;
	NSError *invalid = nil;
	if (failure == nil
	    && ![WFCommandContext areStorableVariables:result.variables error:&invalid]) {
		failure = invalid;
	}
	NSString *errorCode = [[failure userInfo] objectForKey:WFErrorRefKey];
	NSError *error = nil;
	for (int attempt = 0; attempt < WF_CONFLICT_ATTEMPTS; attempt++) {
		BOOL ok = NO;
		error = nil;
		if (failure == nil) {
			ok = [service complete:externalTaskId workerId:workerId
			             variables:result.variables error:&error];
		} else if ([errorCode isKindOfClass:[NSString class]]) {
			ok = [service handleBpmnError:externalTaskId workerId:workerId
			                    errorCode:errorCode variables:nil error:&error];
		} else {
			WFExternalTask *task = [service externalTaskWithId:externalTaskId];
			if (task == nil || ![task.workerId isEqualToString:workerId]) {
				return;
			}
			NSString *cycle = [[[self.repositoryService definitionWithId:task.definitionId error:NULL]
				flowNodeWithId:task.activityId] retryTimeCycle];
			NSInteger attempts = WF_DEFAULT_ATTEMPTS;
			NSArray *delays = nil;
			WFParseRetryCycle(cycle, &attempts, &delays);
			NSInteger before = task.retries != nil ? [task.retries integerValue] : attempts;
			ok = [service handleFailure:externalTaskId
			                   workerId:workerId
			               errorMessage:[failure localizedDescription]
			                    retries:before - 1
			               retryTimeout:WFRetryDelay(cycle, before)
			                      error:&error];
		}
		if (ok || !WFIsConflict(error)) {
			break;
		}
	}
	if (error == nil
	    || ([[error domain] isEqualToString:WFErrorDomain]
	        && ([error code] == WFErrorUnknownElement
	            || [error code] == WFErrorInvalidState))) {
		/* Done, or stale: the task is gone (a boundary event took the
		 * activity away) or was taken over after the lock ran out. */
		return;
	}
	[self notify:^(id<WFProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:@selector(processEngine:commandFailed:)]) {
			[delegate processEngine:self commandFailed:error];
		}
	}];
}

- (void)wf_reschedule
{
	[self reschedule];
}

- (int64_t)wf_nextSequence
{
	@synchronized (_busy) {
		_sequence += 1;
		return _sequence;
	}
}

#pragma mark - The job executor

- (WFJobEntity *)job:(NSString *)jobId in:(WFCommandContext *)command
{
	return [[command fetch:@"WFJob"
	             predicate:[NSPredicate predicateWithFormat:@"jobId == %@", jobId]
	                  sort:nil
	                 limit:1] lastObject];
}

/* Acquire the job's lock, run it, and on failure record that -- each in a
 * transaction of its own, as the reference's job executor does. */
- (BOOL)wf_runJob:(NSString *)jobId force:(BOOL)force error:(NSError **)error
{
	NSString *owner = self.identifier;
	NSTimeInterval lockDuration = self.lockDuration;
	__block BOOL acquired = NO;
	[self runInternal:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		WFJobEntity *job = [self job:jobId in:command];
		if (job == nil) {
			return YES;
		}
		if (job.suspended) {
			return YES;
		}
		if (!force && (job.retries <= 0 || [job.dueDate timeIntervalSinceNow] > 0
		               || (job.lockOwner != nil && ![job.lockOwner isEqualToString:owner]
		                   && [job.lockExpiration timeIntervalSinceNow] > 0))) {
			return YES;
		}
		job.lockOwner = owner;
		job.lockExpiration = [NSDate dateWithTimeIntervalSinceNow:lockDuration];
		acquired = YES;
		return YES;
	} error:NULL];
	if (!acquired) {
		return YES;
	}
	NSError *failure = nil;
	BOOL ran = [self runInternal:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		WFJobEntity *job = [self job:jobId in:command];
		if (job == nil || ![job.lockOwner isEqualToString:owner]) {
			return YES;
		}
		[command runJob:job];
		return YES;
	} error:&failure];
	if (ran) {
		return YES;
	}
	/* The job's own work rolled back; the failure is recorded apart from
	 * it: an attempt fewer, the retry cycle's delay, an incident at none
	 * left. */
	[self runInternal:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		WFJobEntity *job = [self job:jobId in:command];
		if (job == nil) {
			return YES;
		}
		NSString *definitionId = job.definitionId ?: job.execution.definitionId;
		NSString *cycle = [[[self.repositoryService definitionWithId:definitionId error:NULL]
			flowNodeWithId:job.activityId] retryTimeCycle];
		NSTimeInterval delay = WFRetryDelay(cycle, job.retries);
		job.retries = job.retries > 0 ? job.retries - 1 : 0;
		job.exceptionMessage = [failure localizedDescription];
		job.lockOwner = nil;
		job.lockExpiration = nil;
		[command historyJob:job state:WFJobLogStateFailed];
		if (job.retries == 0) {
			[command raiseIncident:WFIncidentTypeFailedJob
			         configuration:job.jobId
			               message:job.exceptionMessage
			            activityId:job.activityId
			     processInstanceId:job.processInstanceId
			             execution:job.execution];
		} else if (delay > 0) {
			job.dueDate = [NSDate dateWithTimeIntervalSinceNow:delay];
		}
		return YES;
	} error:NULL];
	if (error != NULL) {
		*error = failure;
	}
	return NO;
}

- (void)reschedule
{
	WFAsync(_schedulerQueue, ^{
		[self rearmScheduler];
	});
}

/* The next moment the engine has something to do by itself: a job falls
 * due, or a lock runs out. */
- (NSDate *)nextWakeUp
{
	__block NSDate *next = nil;
	BOOL runJobs = self.jobExecutorActive;
	[self wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		NSDate *now = [NSDate date];
		/* With the job executor off, jobs wait for managementService: the
		 * scheduler must not aim at ones it will not run. */
		WFJobEntity *job = !runJobs ? nil : [[command fetch:@"WFJob"
		                         predicate:[NSPredicate predicateWithFormat:
		                             @"retries > 0 AND suspended == NO AND (lockExpiration == nil OR lockExpiration < %@)", now]
		                              sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"dueDate"
		                                                                      ascending:YES] ]
		                             limit:1] lastObject];
		next = job.dueDate;
		NSArray *locked = @[
			(runJobs ? [[command fetch:@"WFJob"
			      predicate:[NSPredicate predicateWithFormat:@"lockExpiration > %@", now]
			           sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"lockExpiration"
			                                                   ascending:YES] ]
			          limit:1] lastObject] : nil) ?: [NSNull null],
			[[command fetch:@"WFExternalTask"
			      predicate:[NSPredicate predicateWithFormat:@"lockExpiration > %@", now]
			           sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"lockExpiration"
			                                                   ascending:YES] ]
			          limit:1] lastObject] ?: [NSNull null]
		];
		for (id row in locked) {
			if (row != [NSNull null]) {
				NSDate *expiry = [row valueForKey:@"lockExpiration"];
				if (next == nil || [expiry compare:next] == NSOrderedAscending) {
					next = expiry;
				}
			}
		}
		return YES;
	} error:NULL];
	return next;
}

/* On the scheduler queue. */
- (void)rearmScheduler
{
	if (_closed) {
		return;
	}
	NSDate *next = [self nextWakeUp];
	if (next == nil) {
		dispatch_source_set_timer(_scheduler, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
		return;
	}
	NSTimeInterval seconds = [next timeIntervalSince1970];
	struct timespec when;
	when.tv_sec = (time_t)seconds;
	when.tv_nsec = (long)((seconds - (double)when.tv_sec) * (double)NSEC_PER_SEC);
	dispatch_source_set_timer(_scheduler, dispatch_walltime(&when, 0),
		DISPATCH_TIME_FOREVER, 5 * NSEC_PER_MSEC);
}

/* On the scheduler queue: hands due jobs, and external tasks whose lock
 * ran out, to their instances' queues, then aims at the next wake-up. */
- (void)schedulerFired
{
	if (_closed) {
		return;
	}
	NSMutableArray *jobs = [NSMutableArray array];
	NSMutableArray *tasks = [NSMutableArray array];
	BOOL handler = self.serviceHandler != nil;
	BOOL runJobs = self.jobExecutorActive;
	[self wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		NSDate *now = [NSDate date];
		for (WFJobEntity *job in !runJobs ? @[] : [command fetch:@"WFJob"
		                              predicate:[NSPredicate predicateWithFormat:
		                                  @"dueDate <= %@ AND retries > 0 AND (lockExpiration == nil OR lockExpiration < %@)",
		                                  now, now]
		                                   sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"dueDate"
		                                                                           ascending:YES] ]
		                                  limit:WF_BATCH]) {
			[jobs addObject:@[ job.jobId, job.processInstanceId ?: [NSNull null],
				[NSNumber numberWithBool:job.exclusive] ]];
		}
		if (handler) {
			for (WFExternalTaskEntity *task in [command fetch:@"WFExternalTask"
			                                        predicate:[NSPredicate predicateWithFormat:
			                                            @"lockExpiration != nil AND lockExpiration < %@ AND (retries == nil OR retries > 0)",
			                                            now]
			                                             sort:nil
			                                            limit:WF_BATCH]) {
				[tasks addObject:@[ task.externalTaskId, task.processInstanceId ]];
			}
		}
		return YES;
	} error:NULL];
	for (NSArray *job in jobs) {
		id processInstanceId = [job objectAtIndex:1];
		[self dispatchJob:[job objectAtIndex:0]
		processInstanceId:processInstanceId == [NSNull null] ? nil : processInstanceId
		        exclusive:[[job objectAtIndex:2] boolValue]];
	}
	for (NSArray *task in tasks) {
		[self wf_externalTaskCreated:[task objectAtIndex:0] processInstanceId:[task objectAtIndex:1]];
	}
	[self rearmScheduler];
}

#pragma mark - Lifecycle

- (BOOL)openWithError:(NSError **)error
{
	if (![self checkHistoryLevel:error]) {
		return NO;
	}
	[self startHistoryCleanup];
	NSString *owner = self.identifier;
	NSMutableArray *available = [NSMutableArray array];
	BOOL handler = self.serviceHandler != nil;
	/* Whatever this engine held before it stopped is in flight nowhere:
	 * take it back now rather than waiting for the locks to run out. */
	BOOL ok = [self runInternal:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		for (WFJobEntity *job in [command fetch:@"WFJob"
		                              predicate:[NSPredicate predicateWithFormat:@"lockOwner == %@", owner]
		                                   sort:nil
		                                  limit:0]) {
			job.lockOwner = nil;
			job.lockExpiration = nil;
		}
		for (WFExternalTaskEntity *task in [command fetch:@"WFExternalTask"
		                                        predicate:[NSPredicate predicateWithFormat:@"workerId == %@", owner]
		                                             sort:nil
		                                            limit:0]) {
			task.workerId = nil;
			task.lockExpiration = nil;
		}
		if (handler) {
			for (WFExternalTaskEntity *task in [command fetch:@"WFExternalTask"
			                                        predicate:[NSPredicate predicateWithFormat:
			                                            @"(lockExpiration == nil OR workerId == %@) AND (retries == nil OR retries > 0)",
			                                            owner]
			                                             sort:nil
			                                            limit:0]) {
				[available addObject:@[ task.externalTaskId, task.processInstanceId ]];
			}
		}
		return YES;
	} error:error];
	if (!ok) {
		return NO;
	}
	for (NSArray *task in available) {
		[self wf_externalTaskCreated:[task objectAtIndex:0] processInstanceId:[task objectAtIndex:1]];
	}
	WFAsync(_schedulerQueue, ^{
		[self schedulerFired];
	});
	return YES;
}

- (void)close
{
	if (_closed) {
		return;
	}
	_closed = YES;
	dispatch_source_cancel(_scheduler);
	if (_cleanup != NULL) {
		dispatch_source_cancel(_cleanup);
		WFDispatchRelease(_cleanup);
		_cleanup = NULL;
	}
}

/* The history level is the store's: the first engine to open records it,
 * and an engine configured otherwise does not open. */
- (BOOL)checkHistoryLevel:(NSError **)error
{
	NSString *mine = [NSString stringWithFormat:@"%ld", (long)self.historyLevel];
	return [self wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		NSManagedObject *property = [[command fetch:@"WFProperty"
		                                  predicate:[NSPredicate predicateWithFormat:
		                                      @"name == %@", @"historyLevel"]
		                                       sort:nil
		                                      limit:1] lastObject];
		if (property == nil) {
			property = [command insert:@"WFProperty"];
			[property setValue:@"historyLevel" forKey:@"name"];
			[property setValue:mine forKey:@"value"];
			return YES;
		}
		if ([[property valueForKey:@"value"] isEqualToString:mine]) {
			return YES;
		}
		if (commandError != NULL) {
			*commandError = [NSError errorWithDomain:WFErrorDomain
			                                    code:WFErrorInvalidState
			                                userInfo:@{ NSLocalizedDescriptionKey:
				[NSString stringWithFormat:
					@"the store records history level %@, the engine is set to %@",
					[property valueForKey:@"value"], mine] }];
		}
		return NO;
	} error:error];
}

- (void)startHistoryCleanup
{
	NSTimeInterval interval = self.historyCleanupInterval;
	if (interval <= 0 || _cleanup != NULL) {
		return;
	}
	_cleanup = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
		dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
	__weak WFProcessEngine *weakSelf = self;
	dispatch_source_set_event_handler(_cleanup, ^{
		@autoreleasepool {
			NSError *error = nil;
			WFProcessEngine *engine = weakSelf;
			if (engine != nil && [engine.historyService cleanUpHistory:500 error:&error] < 0) {
				[engine notify:^(id<WFProcessEngineDelegate> delegate) {
					if ([delegate respondsToSelector:@selector(processEngine:commandFailed:)]) {
						[delegate processEngine:engine commandFailed:error];
					}
				}];
			}
		}
	});
	dispatch_source_set_timer(_cleanup,
		dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
		(uint64_t)(interval * NSEC_PER_SEC), NSEC_PER_SEC);
	dispatch_resume(_cleanup);
}

#pragma mark - Settling

- (void)beginWork:(NSString *)processInstanceId
{
	[_settle lock];
	NSUInteger count = [[_busy objectForKey:processInstanceId] unsignedIntegerValue];
	[_busy setObject:[NSNumber numberWithUnsignedInteger:count + 1] forKey:processInstanceId];
	[_settle unlock];
}

- (void)endWork:(NSString *)processInstanceId
{
	[_settle lock];
	NSUInteger count = [[_busy objectForKey:processInstanceId] unsignedIntegerValue];
	if (count <= 1) {
		[_busy removeObjectForKey:processInstanceId];
	} else {
		[_busy setObject:[NSNumber numberWithUnsignedInteger:count - 1] forKey:processInstanceId];
	}
	[_settle broadcast];
	[_settle unlock];
}

- (BOOL)waitUntilSettled:(NSString *)processInstanceId timeout:(NSTimeInterval)timeout
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	BOOL settled = YES;
	[_settle lock];
	while ([_busy objectForKey:processInstanceId] != nil) {
		if (![_settle waitUntilDate:deadline]) {
			settled = [_busy objectForKey:processInstanceId] == nil;
			break;
		}
	}
	[_settle unlock];
	return settled;
}

@end

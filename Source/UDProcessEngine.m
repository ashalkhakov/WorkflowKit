#import "UDProcessEngine+Internal.h"
#import "UDCommandContext.h"
#import "UDEntities.h"
#import "UDFlowElements.h"
#import "UDProcessDefinition.h"
#import "UDDuration.h"
#include <time.h>

/* External-task results and jobs of one process instance run one after
 * another, on the same serial queue -- the reference's exclusive jobs --
 * and the queues are few however many instances there are. */
#define UD_STRIPES 8
/* Jobs and external tasks taken per scheduler pass. */
#define UD_BATCH 64
/* Attempts at a command the engine runs by itself before it gives up on a
 * conflict. */
#define UD_CONFLICT_ATTEMPTS 5

static BOOL
UDIsConflict(NSError *error)
{
	return [[error domain] isEqualToString:UDWorkflowErrorDomain]
		&& [error code] == UDWorkflowErrorConflict;
}

@interface UDProcessEngine ()
- (void)ud_invocation:(UDServiceInvocation *)invocation
            didFinish:(UDServiceResult *)result;
@end

@implementation UDProcessEngine
{
	dispatch_queue_t _stripes[UD_STRIPES];
	dispatch_queue_t _schedulerQueue;
	dispatch_source_t _scheduler;
	BOOL _closed;
	NSCondition *_settle;
	NSMutableDictionary *_busy;
}

- (instancetype)initWithStore:(UDStore *)store
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_store = store;
	_repositoryService = [[UDRepositoryService alloc] initWithStore:store];
	_runtimeService = [[UDRuntimeService alloc] initWithProcessEngine:self];
	_taskService = [[UDTaskService alloc] initWithProcessEngine:self];
	_historyService = [[UDHistoryService alloc] initWithProcessEngine:self];
	_managementService = [[UDManagementService alloc] initWithProcessEngine:self];
	_jobExecutorActive = YES;
	_identifier = [NSString stringWithFormat:@"udworkflow@%@",
		[[NSProcessInfo processInfo] hostName]];
	_lockDuration = 300;
	_settle = [[NSCondition alloc] init];
	_busy = [NSMutableDictionary dictionary];
	self.workerQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	{
		dispatch_queue_t q = dispatch_queue_create("ud.workflow.callbacks",
			DISPATCH_QUEUE_SERIAL);
		self.callbackQueue = q;
		UDDispatchRelease(q);
	}
	for (NSUInteger i = 0; i < UD_STRIPES; i++) {
		_stripes[i] = dispatch_queue_create("ud.workflow.instances", DISPATCH_QUEUE_SERIAL);
	}
	_schedulerQueue = dispatch_queue_create("ud.workflow.scheduler", DISPATCH_QUEUE_SERIAL);
	_scheduler = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _schedulerQueue);
	__weak UDProcessEngine *weakSelf = self;
	dispatch_source_set_event_handler(_scheduler, ^{
		[weakSelf schedulerFired];
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
	UDDispatchRelease(_scheduler);
	UDDispatchRelease(_schedulerQueue);
	for (NSUInteger i = 0; i < UD_STRIPES; i++) {
		UDDispatchRelease(_stripes[i]);
	}
	if (_workerQueue != NULL) {
		UDDispatchRelease(_workerQueue);
	}
	if (_callbackQueue != NULL) {
		UDDispatchRelease(_callbackQueue);
	}
}

- (void)setWorkerQueue:(dispatch_queue_t)workerQueue
{
	if (workerQueue == _workerQueue) {
		return;
	}
	if (workerQueue != NULL) {
		UDDispatchRetain(workerQueue);
	}
	if (_workerQueue != NULL) {
		UDDispatchRelease(_workerQueue);
	}
	_workerQueue = workerQueue;
}

- (void)setCallbackQueue:(dispatch_queue_t)callbackQueue
{
	if (callbackQueue == _callbackQueue) {
		return;
	}
	if (callbackQueue != NULL) {
		UDDispatchRetain(callbackQueue);
	}
	if (_callbackQueue != NULL) {
		UDDispatchRelease(_callbackQueue);
	}
	_callbackQueue = callbackQueue;
}

- (dispatch_queue_t)stripeFor:(NSString *)processInstanceId
{
	return _stripes[[processInstanceId hash] % UD_STRIPES];
}

- (dispatch_queue_t)ud_queueFor:(NSString *)key
{
	return [self stripeFor:key];
}

#pragma mark - Commands

- (BOOL)ud_runCommand:(BOOL (^)(UDCommandContext *, NSError **))body error:(NSError **)error
{
	UDCommandContext *command = [[UDCommandContext alloc] initWithEngine:self];
	return [command execute:body error:error];
}

/* A command the engine runs by itself: retried on conflict, and reported
 * to the delegate when it fails for good. */
- (BOOL)runInternal:(BOOL (^)(UDCommandContext *, NSError **))body error:(NSError **)error
{
	NSError *localError = nil;
	for (int attempt = 0; attempt < UD_CONFLICT_ATTEMPTS; attempt++) {
		localError = nil;
		if ([self ud_runCommand:body error:&localError]) {
			return YES;
		}
		if (!UDIsConflict(localError)) {
			break;
		}
	}
	[self notify:^(id<UDProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:@selector(processEngine:commandFailed:)]) {
			[delegate processEngine:self commandFailed:localError];
		}
	}];
	if (error != NULL) {
		*error = localError;
	}
	return NO;
}

- (void)notify:(void (^)(id<UDProcessEngineDelegate> delegate))call
{
	id<UDProcessEngineDelegate> delegate = self.delegate;
	if (delegate == nil) {
		return;
	}
	dispatch_async(self.callbackQueue, ^{
		call(delegate);
	});
}

#pragma mark - After commit

- (void)ud_taskCreated:(UDWorkItem *)task
{
	[self notify:^(id<UDProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:@selector(processEngine:taskCreated:)]) {
			[delegate processEngine:self taskCreated:task];
		}
	}];
}

- (void)ud_processInstanceEnded:(UDProcessInstance *)instance
{
	[self notify:^(id<UDProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:@selector(processEngine:processInstanceEnded:)]) {
			[delegate processEngine:self processInstanceEnded:instance];
		}
	}];
}

- (void)ud_messageThrown:(NSString *)messageName
               variables:(NSDictionary *)variables
       processInstanceId:(NSString *)processInstanceId
{
	[self notify:^(id<UDProcessEngineDelegate> delegate) {
		if ([delegate respondsToSelector:
		         @selector(processEngine:processInstanceId:didThrowMessage:variables:)]) {
			[delegate processEngine:self
			      processInstanceId:processInstanceId
			        didThrowMessage:messageName
			              variables:variables];
		}
	}];
}

- (void)ud_externalTaskCreated:(NSString *)externalTaskId
             processInstanceId:(NSString *)processInstanceId
{
	if (self.serviceHandler == nil) {
		return;
	}
	[self beginWork:processInstanceId];
	dispatch_async([self stripeFor:processInstanceId], ^{
		[self lockAndInvoke:externalTaskId processInstanceId:processInstanceId];
	});
}

- (void)ud_jobCreated:(NSString *)jobId
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
	dispatch_async(queue, ^{
		[self ud_runJob:jobId force:NO error:NULL];
		[self reschedule];
		[self endWork:key];
	});
}

#pragma mark - The in-process worker

/* On the instance's stripe. Locks the task for this engine and hands it to
 * the service handler; the matching -endWork: follows its result. */
- (void)lockAndInvoke:(NSString *)externalTaskId processInstanceId:(NSString *)processInstanceId
{
	__block UDServiceInvocation *invocation = nil;
	NSString *workerId = self.identifier;
	NSTimeInterval lockDuration = self.lockDuration;
	[self runInternal:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		UDExternalTaskEntity *task = [[command fetch:@"UDExternalTask"
		                                   predicate:[NSPredicate predicateWithFormat:
		                                       @"externalTaskId == %@", externalTaskId]
		                                        sort:nil
		                                       limit:1] lastObject];
		if (task == nil
		    || (task.lockExpiration != nil && [task.lockExpiration timeIntervalSinceNow] > 0)
		    || (task.retries != nil && [task.retries intValue] <= 0)) {
			return YES;
		}
		task.workerId = workerId;
		task.lockExpiration = [NSDate dateWithTimeIntervalSinceNow:lockDuration];
		invocation = [[UDServiceInvocation alloc]
			initWithExternalTaskId:task.externalTaskId
			                 topic:task.topic
			             variables:[command visibleVariables:task.execution]
			     processInstanceId:task.processInstanceId
			            activityId:task.activityId];
		return YES;
	} error:NULL];
	id<UDServiceTaskHandler> handler = self.serviceHandler;
	if (invocation == nil || handler == nil) {
		[self endWork:processInstanceId];
		return;
	}
	invocation.target = self;
	invocation.action = @selector(ud_invocation:didFinish:);
	dispatch_async(self.workerQueue, ^{
		[handler performInvocation:invocation];
	});
	[self reschedule];
}

- (void)ud_invocation:(UDServiceInvocation *)invocation didFinish:(UDServiceResult *)result
{
	NSString *processInstanceId = invocation.processInstanceId;
	dispatch_async([self stripeFor:processInstanceId], ^{
		[self completeExternalTask:invocation.externalTaskId result:result];
		[self endWork:processInstanceId];
	});
}

- (void)completeExternalTask:(NSString *)externalTaskId result:(UDServiceResult *)result
{
	NSString *workerId = self.identifier;
	NSError *failure = result.error;
	NSError *invalid = nil;
	if (failure == nil
	    && ![UDCommandContext areStorableVariables:result.variables error:&invalid]) {
		failure = invalid;
	}
	[self runInternal:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		UDExternalTaskEntity *task = [[command fetch:@"UDExternalTask"
		                                   predicate:[NSPredicate predicateWithFormat:
		                                       @"externalTaskId == %@", externalTaskId]
		                                        sort:nil
		                                       limit:1] lastObject];
		if (task == nil || ![task.workerId isEqualToString:workerId]) {
			/* Gone (a boundary event took the activity away) or taken
			 * over after the lock ran out: this result is stale. */
			return YES;
		}
		UDExecutionEntity *execution = task.execution;
		if (failure != nil) {
			NSString *errorCode = [[failure userInfo] objectForKey:UDWorkflowErrorRefKey];
			if ([errorCode isKindOfClass:[NSString class]]) {
				[command.context deleteObject:task];
				[command throwBpmnError:errorCode fromExecution:execution];
				return YES;
			}
			/* The in-process worker's policy: the activity's retry cycle, as
			 * for a job, three attempts without one. */
			NSString *cycle = [[[command definitionForExecution:execution]
				flowNodeWithId:task.activityId] retryTimeCycle];
			NSInteger attempts = UD_DEFAULT_ATTEMPTS;
			NSArray *delays = nil;
			UDParseRetryCycle(cycle, &attempts, &delays);
			NSInteger before = task.retries != nil ? [task.retries integerValue] : attempts;
			NSInteger left = before - 1;
			NSTimeInterval delay = UDRetryDelay(cycle, before);
			task.retries = [NSNumber numberWithInteger:left];
			task.errorMessage = [failure localizedDescription];
			task.workerId = nil;
			/* Not offered again before the retry's delay is up. */
			task.lockExpiration = delay > 0 && left > 0
				? [NSDate dateWithTimeIntervalSinceNow:delay] : nil;
			if (left <= 0) {
				[command raiseIncident:UDIncidentTypeFailedExternalTask
				         configuration:task.externalTaskId
				               message:task.errorMessage
				            activityId:task.activityId
				     processInstanceId:task.processInstanceId
				             execution:execution];
			} else if (delay > 0) {
				[command afterCommit:^{
					[self reschedule];
				}];
			} else {
				NSString *processInstanceId = task.processInstanceId;
				[command afterCommit:^{
					[self ud_externalTaskCreated:externalTaskId
					           processInstanceId:processInstanceId];
				}];
			}
			return YES;
		}
		if (![command setVariables:result.variables from:execution]) {
			return NO;
		}
		[command.context deleteObject:task];
		[command completeActivity:execution];
		return YES;
	} error:NULL];
}

#pragma mark - The job executor

- (UDJobEntity *)job:(NSString *)jobId in:(UDCommandContext *)command
{
	return [[command fetch:@"UDJob"
	             predicate:[NSPredicate predicateWithFormat:@"jobId == %@", jobId]
	                  sort:nil
	                 limit:1] lastObject];
}

/* Acquire the job's lock, run it, and on failure record that -- each in a
 * transaction of its own, as the reference's job executor does. */
- (BOOL)ud_runJob:(NSString *)jobId force:(BOOL)force error:(NSError **)error
{
	NSString *owner = self.identifier;
	NSTimeInterval lockDuration = self.lockDuration;
	__block BOOL acquired = NO;
	[self runInternal:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		UDJobEntity *job = [self job:jobId in:command];
		if (job == nil) {
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
	BOOL ran = [self runInternal:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		UDJobEntity *job = [self job:jobId in:command];
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
	[self runInternal:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		UDJobEntity *job = [self job:jobId in:command];
		if (job == nil) {
			return YES;
		}
		NSString *definitionId = job.definitionId ?: job.execution.definitionId;
		NSString *cycle = [[[self.repositoryService definitionWithId:definitionId error:NULL]
			flowNodeWithId:job.activityId] retryTimeCycle];
		NSTimeInterval delay = UDRetryDelay(cycle, job.retries);
		job.retries = job.retries > 0 ? job.retries - 1 : 0;
		job.exceptionMessage = [failure localizedDescription];
		job.lockOwner = nil;
		job.lockExpiration = nil;
		if (job.retries == 0) {
			[command raiseIncident:UDIncidentTypeFailedJob
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
	dispatch_async(_schedulerQueue, ^{
		[self rearmScheduler];
	});
}

/* The next moment the engine has something to do by itself: a job falls
 * due, or a lock runs out. */
- (NSDate *)nextWakeUp
{
	__block NSDate *next = nil;
	BOOL runJobs = self.jobExecutorActive;
	[self ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		NSDate *now = [NSDate date];
		/* With the job executor off, jobs wait for managementService: the
		 * scheduler must not aim at ones it will not run. */
		UDJobEntity *job = !runJobs ? nil : [[command fetch:@"UDJob"
		                         predicate:[NSPredicate predicateWithFormat:
		                             @"retries > 0 AND (lockExpiration == nil OR lockExpiration < %@)", now]
		                              sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"dueDate"
		                                                                      ascending:YES] ]
		                             limit:1] lastObject];
		next = job.dueDate;
		NSArray *locked = @[
			(runJobs ? [[command fetch:@"UDJob"
			      predicate:[NSPredicate predicateWithFormat:@"lockExpiration > %@", now]
			           sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"lockExpiration"
			                                                   ascending:YES] ]
			          limit:1] lastObject] : nil) ?: [NSNull null],
			[[command fetch:@"UDExternalTask"
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
	[self ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		NSDate *now = [NSDate date];
		for (UDJobEntity *job in !runJobs ? @[] : [command fetch:@"UDJob"
		                              predicate:[NSPredicate predicateWithFormat:
		                                  @"dueDate <= %@ AND retries > 0 AND (lockExpiration == nil OR lockExpiration < %@)",
		                                  now, now]
		                                   sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"dueDate"
		                                                                           ascending:YES] ]
		                                  limit:UD_BATCH]) {
			[jobs addObject:@[ job.jobId, job.processInstanceId ?: [NSNull null],
				[NSNumber numberWithBool:job.exclusive] ]];
		}
		if (handler) {
			for (UDExternalTaskEntity *task in [command fetch:@"UDExternalTask"
			                                        predicate:[NSPredicate predicateWithFormat:
			                                            @"lockExpiration != nil AND lockExpiration < %@ AND (retries == nil OR retries > 0)",
			                                            now]
			                                             sort:nil
			                                            limit:UD_BATCH]) {
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
		[self ud_externalTaskCreated:[task objectAtIndex:0] processInstanceId:[task objectAtIndex:1]];
	}
	[self rearmScheduler];
}

#pragma mark - Lifecycle

- (BOOL)openWithError:(NSError **)error
{
	NSString *owner = self.identifier;
	NSMutableArray *available = [NSMutableArray array];
	BOOL handler = self.serviceHandler != nil;
	/* Whatever this engine held before it stopped is in flight nowhere:
	 * take it back now rather than waiting for the locks to run out. */
	BOOL ok = [self runInternal:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		for (UDJobEntity *job in [command fetch:@"UDJob"
		                              predicate:[NSPredicate predicateWithFormat:@"lockOwner == %@", owner]
		                                   sort:nil
		                                  limit:0]) {
			job.lockOwner = nil;
			job.lockExpiration = nil;
		}
		for (UDExternalTaskEntity *task in [command fetch:@"UDExternalTask"
		                                        predicate:[NSPredicate predicateWithFormat:@"workerId == %@", owner]
		                                             sort:nil
		                                            limit:0]) {
			task.workerId = nil;
			task.lockExpiration = nil;
		}
		if (handler) {
			for (UDExternalTaskEntity *task in [command fetch:@"UDExternalTask"
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
		[self ud_externalTaskCreated:[task objectAtIndex:0] processInstanceId:[task objectAtIndex:1]];
	}
	dispatch_async(_schedulerQueue, ^{
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

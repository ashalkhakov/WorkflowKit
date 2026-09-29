#import "WFProcessEngine+Internal.h"
#import "WFCommandContext.h"
#import "WFEntities.h"

static NSError *
WFTaskError(WFErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:WFErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@interface WFExternalTask ()
@property (nonatomic, readwrite, copy) NSString *externalTaskId;
@property (nonatomic, readwrite, copy) NSString *topic;
@property (nonatomic, readwrite, copy) NSString *processInstanceId;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *businessKey;
@property (nonatomic, readwrite, copy) NSString *activityId;
@property (nonatomic, readwrite, copy) NSString *workerId;
@property (nonatomic, readwrite, copy) NSDate *lockExpiration;
@property (nonatomic, readwrite, strong) NSNumber *retries;
@property (nonatomic, readwrite, copy) NSString *errorMessage;
@property (nonatomic, readwrite) NSInteger priority;
@property (nonatomic, readwrite, copy) NSDictionary *variables;
@end

@implementation WFExternalTask

+ (instancetype)wf_taskWithEntity:(WFExternalTaskEntity *)entity
                        variables:(NSDictionary *)variables
{
	WFExternalTask *task = [[WFExternalTask alloc] init];
	task.externalTaskId = entity.externalTaskId;
	task.topic = entity.topic;
	task.processInstanceId = entity.processInstanceId;
	task.definitionId = entity.execution.definitionId;
	task.businessKey = [entity.execution processInstance].businessKey;
	task.activityId = entity.activityId;
	task.workerId = entity.workerId;
	task.lockExpiration = entity.lockExpiration;
	task.retries = entity.retries;
	task.errorMessage = entity.errorMessage;
	task.priority = (NSInteger)entity.priority;
	task.variables = variables;
	return task;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<WFExternalTask %@ %@%@>", self.topic,
		self.externalTaskId, self.workerId ? [@" locked by " stringByAppendingString:self.workerId] : @""];
}

@end

@implementation WFExternalTaskService
{
	__weak WFProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(WFProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
	}
	return self;
}

- (WFExternalTaskEntity *)task:(NSString *)externalTaskId in:(WFCommandContext *)command
{
	return [[command fetch:@"WFExternalTask"
	             predicate:[NSPredicate predicateWithFormat:@"externalTaskId == %@",
	                 externalTaskId ?: @""]
	                  sort:nil
	                 limit:1] lastObject];
}

- (BOOL)isAvailable:(WFExternalTaskEntity *)task
{
	return (task.lockExpiration == nil || [task.lockExpiration timeIntervalSinceNow] <= 0)
		&& (task.retries == nil || [task.retries integerValue] > 0);
}

- (WFExternalTask *)lock:(WFExternalTaskEntity *)task
                workerId:(NSString *)workerId
                duration:(NSTimeInterval)duration
           variableNames:(NSArray *)names
                 command:(WFCommandContext *)command
{
	task.workerId = workerId;
	task.lockExpiration = [NSDate dateWithTimeIntervalSinceNow:duration];
	NSDictionary *variables = [command visibleVariables:task.execution];
	if (names != nil) {
		NSMutableDictionary *chosen = [NSMutableDictionary dictionary];
		for (NSString *name in names) {
			id value = [variables objectForKey:name];
			if (value != nil) {
				[chosen setObject:value forKey:name];
			}
		}
		variables = chosen;
	}
	return [WFExternalTask wf_taskWithEntity:task variables:variables];
}

- (NSArray<WFExternalTask *> *)fetchAndLock:(NSUInteger)maxTasks
                                   workerId:(NSString *)workerId
                                     topics:(NSDictionary<NSString *, NSNumber *> *)lockDurations
                                      error:(NSError **)error
{
	return [self fetchAndLock:maxTasks workerId:workerId topics:lockDurations
	            variableNames:nil error:error];
}

- (NSArray<WFExternalTask *> *)fetchAndLock:(NSUInteger)maxTasks
                                   workerId:(NSString *)workerId
                                     topics:(NSDictionary<NSString *, NSNumber *> *)lockDurations
                              variableNames:(NSDictionary<NSString *, NSArray<NSString *> *> *)variableNames
                                      error:(NSError **)error
{
	if ([workerId length] == 0 || [lockDurations count] == 0) {
		if (error != NULL) {
			*error = WFTaskError(WFErrorInvalidState, @"a fetch needs a worker id and topics");
		}
		return nil;
	}
	NSMutableArray *locked = [NSMutableArray array];
	BOOL ok = [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		(void)commandError;
		NSDate *now = [NSDate date];
		NSArray *candidates = [command fetch:@"WFExternalTask"
		                           predicate:[NSPredicate predicateWithFormat:
		                               @"topic IN %@ AND (lockExpiration == nil OR lockExpiration <= %@) AND (retries == nil OR retries > 0)",
		                               [lockDurations allKeys], now]
		                                sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"priority" ascending:NO],
		                                        [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES] ]
		                               limit:maxTasks];
		for (WFExternalTaskEntity *task in candidates) {
			NSTimeInterval duration = [[lockDurations objectForKey:task.topic] doubleValue];
			[locked addObject:[self lock:task workerId:workerId duration:duration
			               variableNames:[variableNames objectForKey:task.topic]
			                     command:command]];
		}
		return YES;
	} error:error];
	/* Two workers fetching at once conflict; the loser fetched nothing. */
	return ok ? locked : nil;
}

/* The task, if the worker holds its lock. */
- (WFExternalTaskEntity *)task:(NSString *)externalTaskId
                    lockedBy:(NSString *)workerId
                     command:(WFCommandContext *)command
                       error:(NSError **)error
{
	WFExternalTaskEntity *task = [self task:externalTaskId in:command];
	if (task == nil) {
		if (error != NULL) {
			*error = WFTaskError(WFErrorUnknownElement,
				[NSString stringWithFormat:@"no external task %@", externalTaskId]);
		}
		return nil;
	}
	if (workerId == nil || ![task.workerId isEqualToString:workerId]) {
		if (error != NULL) {
			*error = WFTaskError(WFErrorInvalidState,
				[NSString stringWithFormat:@"external task %@ is not locked by %@",
					externalTaskId, workerId]);
		}
		return nil;
	}
	return task;
}

- (BOOL)complete:(NSString *)externalTaskId
        workerId:(NSString *)workerId
       variables:(NSDictionary *)variables
           error:(NSError **)error
{
	if (![WFCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFExternalTaskEntity *task = [self task:externalTaskId lockedBy:workerId
		                                command:command error:commandError];
		if (task == nil) {
			return NO;
		}
		WFExecutionEntity *execution = task.execution;
		if (![command setVariables:variables from:execution]) {
			return NO;
		}
		[command.context deleteObject:task];
		[command completeActivity:execution];
		return YES;
	} error:error];
}

- (BOOL)handleFailure:(NSString *)externalTaskId
             workerId:(NSString *)workerId
         errorMessage:(NSString *)errorMessage
              retries:(NSInteger)retries
         retryTimeout:(NSTimeInterval)retryTimeout
                error:(NSError **)error
{
	WFProcessEngine *engine = _engine;
	return [engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFExternalTaskEntity *task = [self task:externalTaskId lockedBy:workerId
		                                command:command error:commandError];
		if (task == nil) {
			return NO;
		}
		NSInteger left = MAX(retries, 0);
		task.retries = [NSNumber numberWithInteger:left];
		task.errorMessage = errorMessage;
		task.workerId = nil;
		/* Not fetchable before the retry timeout is up. */
		task.lockExpiration = left > 0 && retryTimeout > 0
			? [NSDate dateWithTimeIntervalSinceNow:retryTimeout] : nil;
		NSString *processInstanceId = task.processInstanceId;
		if (left == 0) {
			[command raiseIncident:WFIncidentTypeFailedExternalTask
			         configuration:task.externalTaskId
			               message:errorMessage
			            activityId:task.activityId
			     processInstanceId:processInstanceId
			             execution:task.execution];
		} else if (retryTimeout > 0) {
			[command afterCommit:^{
				[engine wf_reschedule];
			}];
		} else {
			[command afterCommit:^{
				[engine wf_externalTaskCreated:externalTaskId processInstanceId:processInstanceId];
			}];
		}
		return YES;
	} error:error];
}

- (BOOL)handleBpmnError:(NSString *)externalTaskId
               workerId:(NSString *)workerId
              errorCode:(NSString *)errorCode
              variables:(NSDictionary *)variables
                  error:(NSError **)error
{
	if (![WFCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFExternalTaskEntity *task = [self task:externalTaskId lockedBy:workerId
		                                command:command error:commandError];
		if (task == nil) {
			return NO;
		}
		WFExecutionEntity *execution = task.execution;
		if (![command setVariables:variables from:execution]) {
			return NO;
		}
		[command.context deleteObject:task];
		[command throwBpmnError:errorCode fromExecution:execution];
		return YES;
	} error:error];
}

- (BOOL)extendLock:(NSString *)externalTaskId
          workerId:(NSString *)workerId
          duration:(NSTimeInterval)duration
             error:(NSError **)error
{
	return [_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFExternalTaskEntity *task = [self task:externalTaskId lockedBy:workerId
		                                command:command error:commandError];
		if (task == nil) {
			return NO;
		}
		if ([task.lockExpiration timeIntervalSinceNow] <= 0) {
			if (commandError != NULL) {
				*commandError = WFTaskError(WFErrorInvalidState,
					[NSString stringWithFormat:@"the lock on external task %@ has run out",
						externalTaskId]);
			}
			return NO;
		}
		task.lockExpiration = [NSDate dateWithTimeIntervalSinceNow:duration];
		return YES;
	} error:error];
}

- (BOOL)unlock:(NSString *)externalTaskId error:(NSError **)error
{
	WFProcessEngine *engine = _engine;
	return [engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFExternalTaskEntity *task = [self task:externalTaskId in:command];
		if (task == nil) {
			if (commandError != NULL) {
				*commandError = WFTaskError(WFErrorUnknownElement,
					[NSString stringWithFormat:@"no external task %@", externalTaskId]);
			}
			return NO;
		}
		task.workerId = nil;
		task.lockExpiration = nil;
		NSString *processInstanceId = task.processInstanceId;
		[command afterCommit:^{
			[engine wf_externalTaskCreated:externalTaskId processInstanceId:processInstanceId];
		}];
		return YES;
	} error:error];
}

- (BOOL)setRetries:(NSInteger)retries
   forExternalTask:(NSString *)externalTaskId
             error:(NSError **)error
{
	WFProcessEngine *engine = _engine;
	return [engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **commandError) {
		WFExternalTaskEntity *task = [self task:externalTaskId in:command];
		if (task == nil) {
			if (commandError != NULL) {
				*commandError = WFTaskError(WFErrorUnknownElement,
					[NSString stringWithFormat:@"no external task %@", externalTaskId]);
			}
			return NO;
		}
		task.retries = [NSNumber numberWithInteger:MAX(retries, 0)];
		if (retries > 0) {
			[command resolveIncidentsFor:externalTaskId];
			NSString *processInstanceId = task.processInstanceId;
			[command afterCommit:^{
				[engine wf_externalTaskCreated:externalTaskId processInstanceId:processInstanceId];
			}];
		}
		return YES;
	} error:error];
}

- (NSArray<WFExternalTask *> *)tasksMatching:(NSPredicate *)predicate
{
	NSMutableArray *tasks = [NSMutableArray array];
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		for (WFExternalTaskEntity *entity in [command fetch:@"WFExternalTask"
		                                         predicate:predicate
		                                              sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
		                                                                                      ascending:YES] ]
		                                             limit:0]) {
			[tasks addObject:[WFExternalTask wf_taskWithEntity:entity variables:nil]];
		}
		return YES;
	} error:NULL];
	return tasks;
}

- (WFExternalTask *)externalTaskWithId:(NSString *)externalTaskId
{
	return [[self tasksMatching:[NSPredicate predicateWithFormat:@"externalTaskId == %@",
		externalTaskId ?: @""]] lastObject];
}

- (NSArray<WFExternalTask *> *)externalTasksForProcessInstance:(NSString *)processInstanceId
{
	return [self tasksMatching:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
		processInstanceId ?: @""]];
}

- (WFExternalTask *)wf_lockTask:(NSString *)externalTaskId
                       workerId:(NSString *)workerId
                       duration:(NSTimeInterval)duration
{
	__block WFExternalTask *locked = nil;
	[_engine wf_runCommand:^BOOL(WFCommandContext *command, NSError **error) {
		(void)error;
		WFExternalTaskEntity *task = [self task:externalTaskId in:command];
		if (task != nil && [self isAvailable:task]) {
			locked = [self lock:task workerId:workerId duration:duration
			      variableNames:nil command:command];
		}
		return YES;
	} error:NULL];
	return locked;
}

@end

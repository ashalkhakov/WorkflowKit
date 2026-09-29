#import "UDProcessEngine+Internal.h"
#import "UDCommandContext.h"
#import "UDEntities.h"

static NSError *
UDTaskError(UDWorkflowErrorCode code, NSString *message)
{
	return [NSError errorWithDomain:UDWorkflowErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@interface UDExternalTask ()
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

@implementation UDExternalTask

+ (instancetype)ud_taskWithEntity:(UDExternalTaskEntity *)entity
                        variables:(NSDictionary *)variables
{
	UDExternalTask *task = [[UDExternalTask alloc] init];
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
	return [NSString stringWithFormat:@"<UDExternalTask %@ %@%@>", self.topic,
		self.externalTaskId, self.workerId ? [@" locked by " stringByAppendingString:self.workerId] : @""];
}

@end

@implementation UDExternalTaskService
{
	__weak UDProcessEngine *_engine;
}

- (instancetype)initWithProcessEngine:(UDProcessEngine *)engine
{
	self = [super init];
	if (self) {
		_engine = engine;
	}
	return self;
}

- (UDExternalTaskEntity *)task:(NSString *)externalTaskId in:(UDCommandContext *)command
{
	return [[command fetch:@"UDExternalTask"
	             predicate:[NSPredicate predicateWithFormat:@"externalTaskId == %@",
	                 externalTaskId ?: @""]
	                  sort:nil
	                 limit:1] lastObject];
}

- (BOOL)isAvailable:(UDExternalTaskEntity *)task
{
	return (task.lockExpiration == nil || [task.lockExpiration timeIntervalSinceNow] <= 0)
		&& (task.retries == nil || [task.retries integerValue] > 0);
}

- (UDExternalTask *)lock:(UDExternalTaskEntity *)task
                workerId:(NSString *)workerId
                duration:(NSTimeInterval)duration
           variableNames:(NSArray *)names
                 command:(UDCommandContext *)command
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
	return [UDExternalTask ud_taskWithEntity:task variables:variables];
}

- (NSArray<UDExternalTask *> *)fetchAndLock:(NSUInteger)maxTasks
                                   workerId:(NSString *)workerId
                                     topics:(NSDictionary<NSString *, NSNumber *> *)lockDurations
                                      error:(NSError **)error
{
	return [self fetchAndLock:maxTasks workerId:workerId topics:lockDurations
	            variableNames:nil error:error];
}

- (NSArray<UDExternalTask *> *)fetchAndLock:(NSUInteger)maxTasks
                                   workerId:(NSString *)workerId
                                     topics:(NSDictionary<NSString *, NSNumber *> *)lockDurations
                              variableNames:(NSDictionary<NSString *, NSArray<NSString *> *> *)variableNames
                                      error:(NSError **)error
{
	if ([workerId length] == 0 || [lockDurations count] == 0) {
		if (error != NULL) {
			*error = UDTaskError(UDWorkflowErrorInvalidState, @"a fetch needs a worker id and topics");
		}
		return nil;
	}
	NSMutableArray *locked = [NSMutableArray array];
	BOOL ok = [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		(void)commandError;
		NSDate *now = [NSDate date];
		NSArray *candidates = [command fetch:@"UDExternalTask"
		                           predicate:[NSPredicate predicateWithFormat:
		                               @"topic IN %@ AND (lockExpiration == nil OR lockExpiration <= %@) AND (retries == nil OR retries > 0)",
		                               [lockDurations allKeys], now]
		                                sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"priority" ascending:NO],
		                                        [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES] ]
		                               limit:maxTasks];
		for (UDExternalTaskEntity *task in candidates) {
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
- (UDExternalTaskEntity *)task:(NSString *)externalTaskId
                    lockedBy:(NSString *)workerId
                     command:(UDCommandContext *)command
                       error:(NSError **)error
{
	UDExternalTaskEntity *task = [self task:externalTaskId in:command];
	if (task == nil) {
		if (error != NULL) {
			*error = UDTaskError(UDWorkflowErrorUnknownElement,
				[NSString stringWithFormat:@"no external task %@", externalTaskId]);
		}
		return nil;
	}
	if (workerId == nil || ![task.workerId isEqualToString:workerId]) {
		if (error != NULL) {
			*error = UDTaskError(UDWorkflowErrorInvalidState,
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
	if (![UDCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDExternalTaskEntity *task = [self task:externalTaskId lockedBy:workerId
		                                command:command error:commandError];
		if (task == nil) {
			return NO;
		}
		UDExecutionEntity *execution = task.execution;
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
	UDProcessEngine *engine = _engine;
	return [engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDExternalTaskEntity *task = [self task:externalTaskId lockedBy:workerId
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
			[command raiseIncident:UDIncidentTypeFailedExternalTask
			         configuration:task.externalTaskId
			               message:errorMessage
			            activityId:task.activityId
			     processInstanceId:processInstanceId
			             execution:task.execution];
		} else if (retryTimeout > 0) {
			[command afterCommit:^{
				[engine ud_reschedule];
			}];
		} else {
			[command afterCommit:^{
				[engine ud_externalTaskCreated:externalTaskId processInstanceId:processInstanceId];
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
	if (![UDCommandContext areStorableVariables:variables error:error]) {
		return NO;
	}
	return [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDExternalTaskEntity *task = [self task:externalTaskId lockedBy:workerId
		                                command:command error:commandError];
		if (task == nil) {
			return NO;
		}
		UDExecutionEntity *execution = task.execution;
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
	return [_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDExternalTaskEntity *task = [self task:externalTaskId lockedBy:workerId
		                                command:command error:commandError];
		if (task == nil) {
			return NO;
		}
		if ([task.lockExpiration timeIntervalSinceNow] <= 0) {
			if (commandError != NULL) {
				*commandError = UDTaskError(UDWorkflowErrorInvalidState,
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
	UDProcessEngine *engine = _engine;
	return [engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDExternalTaskEntity *task = [self task:externalTaskId in:command];
		if (task == nil) {
			if (commandError != NULL) {
				*commandError = UDTaskError(UDWorkflowErrorUnknownElement,
					[NSString stringWithFormat:@"no external task %@", externalTaskId]);
			}
			return NO;
		}
		task.workerId = nil;
		task.lockExpiration = nil;
		NSString *processInstanceId = task.processInstanceId;
		[command afterCommit:^{
			[engine ud_externalTaskCreated:externalTaskId processInstanceId:processInstanceId];
		}];
		return YES;
	} error:error];
}

- (BOOL)setRetries:(NSInteger)retries
   forExternalTask:(NSString *)externalTaskId
             error:(NSError **)error
{
	UDProcessEngine *engine = _engine;
	return [engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **commandError) {
		UDExternalTaskEntity *task = [self task:externalTaskId in:command];
		if (task == nil) {
			if (commandError != NULL) {
				*commandError = UDTaskError(UDWorkflowErrorUnknownElement,
					[NSString stringWithFormat:@"no external task %@", externalTaskId]);
			}
			return NO;
		}
		task.retries = [NSNumber numberWithInteger:MAX(retries, 0)];
		if (retries > 0) {
			[command resolveIncidentsFor:externalTaskId];
			NSString *processInstanceId = task.processInstanceId;
			[command afterCommit:^{
				[engine ud_externalTaskCreated:externalTaskId processInstanceId:processInstanceId];
			}];
		}
		return YES;
	} error:error];
}

- (NSArray<UDExternalTask *> *)tasksMatching:(NSPredicate *)predicate
{
	NSMutableArray *tasks = [NSMutableArray array];
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		for (UDExternalTaskEntity *entity in [command fetch:@"UDExternalTask"
		                                         predicate:predicate
		                                              sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt"
		                                                                                      ascending:YES] ]
		                                             limit:0]) {
			[tasks addObject:[UDExternalTask ud_taskWithEntity:entity variables:nil]];
		}
		return YES;
	} error:NULL];
	return tasks;
}

- (UDExternalTask *)externalTaskWithId:(NSString *)externalTaskId
{
	return [[self tasksMatching:[NSPredicate predicateWithFormat:@"externalTaskId == %@",
		externalTaskId ?: @""]] lastObject];
}

- (NSArray<UDExternalTask *> *)externalTasksForProcessInstance:(NSString *)processInstanceId
{
	return [self tasksMatching:[NSPredicate predicateWithFormat:@"processInstanceId == %@",
		processInstanceId ?: @""]];
}

- (UDExternalTask *)ud_lockTask:(NSString *)externalTaskId
                       workerId:(NSString *)workerId
                       duration:(NSTimeInterval)duration
{
	__block UDExternalTask *locked = nil;
	[_engine ud_runCommand:^BOOL(UDCommandContext *command, NSError **error) {
		(void)error;
		UDExternalTaskEntity *task = [self task:externalTaskId in:command];
		if (task != nil && [self isAvailable:task]) {
			locked = [self lock:task workerId:workerId duration:duration
			      variableNames:nil command:command];
		}
		return YES;
	} error:NULL];
	return locked;
}

@end

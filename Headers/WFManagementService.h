#import "WFTypes.h"

/* WorkflowKit's own: exported where it is built for Windows (the GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef WORKFLOWKIT_EXPORT
#define WORKFLOWKIT_EXPORT FOUNDATION_EXPORT
#endif

WORKFLOWKIT_EXPORT NSString * const WFJobTypeTimerName;
WORKFLOWKIT_EXPORT NSString * const WFJobTypeTimerStartName;
WORKFLOWKIT_EXPORT NSString * const WFJobTypeAsyncBeforeName;
WORKFLOWKIT_EXPORT NSString * const WFJobTypeAsyncAfterName;

/* Work the engine does by itself: a timer, a timer start event, or an
 * async continuation before or after an activity. */
@interface WFJob : NSObject
@property (nonatomic, readonly, copy) NSString *jobId;
@property (nonatomic, readonly, copy) NSString *jobType;
@property (nonatomic, readonly, copy) NSString *activityId;
/* nil for a timer start event's job, which has a definition instead. */
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSDate *dueDate;
/* Attempts left. 0: the job has failed for good and has an incident. */
@property (nonatomic, readonly) NSInteger retries;
@property (nonatomic, readonly, copy) NSString *exceptionMessage;
@property (nonatomic, readonly, getter=isExclusive) BOOL exclusive;
/* Its instance or definition is suspended: it is not run. */
@property (nonatomic, readonly, getter=isSuspended) BOOL suspended;
@end

WORKFLOWKIT_EXPORT NSString * const WFIncidentTypeFailedJobName;
WORKFLOWKIT_EXPORT NSString * const WFIncidentTypeFailedExternalTaskName;

/* A job or external task that ran out of retries and waits for someone to
 * look at it. */
@interface WFIncident : NSObject
@property (nonatomic, readonly, copy) NSString *incidentId;
@property (nonatomic, readonly, copy) NSString *incidentType;
@property (nonatomic, readonly, copy) NSString *message;
@property (nonatomic, readonly, copy) NSString *activityId;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
/* The failed job's or external task's id. */
@property (nonatomic, readonly, copy) NSString *configuration;
@property (nonatomic, readonly, copy) NSDate *createdAt;
@end

/* Jobs and incidents. */
@interface WFManagementService : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (NSArray<WFJob *> *)jobsForProcessInstance:(NSString *)processInstanceId;
- (NSArray<WFJob *> *)jobsForDefinition:(NSString *)definitionId;
- (WFJob *)jobWithId:(NSString *)jobId;

/* Runs the job now, whatever its due date or retries, on the calling
 * thread. A failure is recorded as the job executor records it -- one
 * attempt fewer, an incident at none left -- and answered. */
- (BOOL)executeJob:(NSString *)jobId error:(NSError **)error;
/* Gives a job attempts again; its incident, if any, is resolved. */
- (BOOL)setRetries:(NSInteger)retries forJob:(NSString *)jobId error:(NSError **)error;

- (NSArray<WFIncident *> *)incidentsForProcessInstance:(NSString *)processInstanceId;

@end

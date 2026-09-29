#import "WFTypes.h"

extern NSString * const WFJobTypeTimerName;
extern NSString * const WFJobTypeTimerStartName;
extern NSString * const WFJobTypeAsyncBeforeName;
extern NSString * const WFJobTypeAsyncAfterName;

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
@end

extern NSString * const WFIncidentTypeFailedJobName;
extern NSString * const WFIncidentTypeFailedExternalTaskName;

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

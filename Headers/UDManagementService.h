#ifndef UDManagementService_h
#define UDManagementService_h

#import "UDTypes.h"

extern NSString * const UDJobTypeTimerName;
extern NSString * const UDJobTypeTimerStartName;
extern NSString * const UDJobTypeAsyncBeforeName;
extern NSString * const UDJobTypeAsyncAfterName;

/* Work the engine does by itself: a timer, a timer start event, or an
 * async continuation before or after an activity. */
@interface UDJob : NSObject
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

extern NSString * const UDIncidentTypeFailedJobName;
extern NSString * const UDIncidentTypeFailedExternalTaskName;

/* A job or external task that ran out of retries and waits for someone to
 * look at it. */
@interface UDIncident : NSObject
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
@interface UDManagementService : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (NSArray<UDJob *> *)jobsForProcessInstance:(NSString *)processInstanceId;
- (NSArray<UDJob *> *)jobsForDefinition:(NSString *)definitionId;
- (UDJob *)jobWithId:(NSString *)jobId;

/* Runs the job now, whatever its due date or retries, on the calling
 * thread. A failure is recorded as the job executor records it -- one
 * attempt fewer, an incident at none left -- and answered. */
- (BOOL)executeJob:(NSString *)jobId error:(NSError **)error;
/* Gives a job attempts again; its incident, if any, is resolved. */
- (BOOL)setRetries:(NSInteger)retries forJob:(NSString *)jobId error:(NSError **)error;

- (NSArray<UDIncident *> *)incidentsForProcessInstance:(NSString *)processInstanceId;

@end

#endif /* UDManagementService_h */

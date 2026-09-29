#import "UDTypes.h"

/* How much history the engine writes, as the reference's levels. */
typedef NS_ENUM(NSInteger, UDHistoryLevel) {
	/* Nothing. */
	UDHistoryLevelNone = 0,
	/* Process, activity and task instances. */
	UDHistoryLevelActivity,
	/* The above, and the latest value of each variable. The default. */
	UDHistoryLevelAudit,
	/* The above, every variable update, incidents and the job log. */
	UDHistoryLevelFull
};

extern NSString * const UDProcessInstanceStateActive;
extern NSString * const UDProcessInstanceStateCompleted;
/* Canceled with the call activity that started it. */
extern NSString * const UDProcessInstanceStateInternallyTerminated;

@interface UDHistoricProcessInstance : NSObject
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *businessKey;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSString *definitionKey;
@property (nonatomic, readonly, copy) NSDate *startTime;
/* nil while the instance runs. */
@property (nonatomic, readonly, copy) NSDate *endTime;
@property (nonatomic, readonly, copy) NSString *state;
/* The instance whose call activity started this one; nil otherwise. */
@property (nonatomic, readonly, copy) NSString *superProcessInstanceId;
@end

/* One time a path was at a node: an activity, event or gateway. */
@interface UDHistoricActivityInstance : NSObject
@property (nonatomic, readonly, copy) NSString *activityInstanceId;
@property (nonatomic, readonly, copy) NSString *activityId;
@property (nonatomic, readonly, copy) NSString *activityName;
/* The BPMN element: userTask, exclusiveGateway, boundaryEvent, ... */
@property (nonatomic, readonly, copy) NSString *activityType;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
/* For a call activity: the instance it started. */
@property (nonatomic, readonly, copy) NSString *calledProcessInstanceId;
@property (nonatomic, readonly, copy) NSDate *startTime;
/* nil while running. */
@property (nonatomic, readonly, copy) NSDate *endTime;
/* Ended by an interrupting event or an uncaught error, not completed. */
@property (nonatomic, readonly, getter=isCanceled) BOOL canceled;
@end

extern NSString * const UDTaskDeleteReasonCompleted;
extern NSString * const UDTaskDeleteReasonDeleted;

@interface UDHistoricTaskInstance : NSObject
@property (nonatomic, readonly, copy) NSString *taskId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *taskDefinitionKey;
@property (nonatomic, readonly, copy) NSString *assignee;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSDate *startTime;
@property (nonatomic, readonly, copy) NSDate *endTime;
/* completed, or deleted when a boundary event took the task away. */
@property (nonatomic, readonly, copy) NSString *deleteReason;
@end

@interface UDHistoricVariableUpdate : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, strong) id value;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSDate *time;
@end

extern NSString * const UDIncidentStateOpen;
extern NSString * const UDIncidentStateResolved;
extern NSString * const UDIncidentStateDeleted;

@interface UDHistoricIncident : NSObject
@property (nonatomic, readonly, copy) NSString *incidentId;
@property (nonatomic, readonly, copy) NSString *incidentType;
@property (nonatomic, readonly, copy) NSString *message;
@property (nonatomic, readonly, copy) NSString *activityId;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *configuration;
@property (nonatomic, readonly, copy) NSDate *createdAt;
@property (nonatomic, readonly, copy) NSDate *endTime;
@property (nonatomic, readonly, copy) NSString *state;
@end

extern NSString * const UDJobLogStateCreated;
extern NSString * const UDJobLogStateSuccessful;
extern NSString * const UDJobLogStateFailed;
extern NSString * const UDJobLogStateDeleted;

@interface UDHistoricJobLog : NSObject
@property (nonatomic, readonly, copy) NSString *jobId;
@property (nonatomic, readonly, copy) NSString *jobType;
@property (nonatomic, readonly, copy) NSString *activityId;
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSDate *timestamp;
@property (nonatomic, readonly, copy) NSString *state;
@property (nonatomic, readonly, copy) NSString *exceptionMessage;
/* The job's attempts left when the entry was written. */
@property (nonatomic, readonly) NSInteger retries;
@end

/*
 * What happened, kept after the runtime rows of an instance are gone.
 * Written in the same transaction as the runtime change it records, at
 * the engine's historyLevel. Lists come in the order things happened.
 */
@interface UDHistoryService : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (UDHistoricProcessInstance *)historicProcessInstanceWithId:(NSString *)processInstanceId;
- (NSArray<UDHistoricActivityInstance *> *)historicActivityInstancesForProcessInstance:(NSString *)processInstanceId;
- (NSArray<UDHistoricTaskInstance *> *)historicTaskInstancesForProcessInstance:(NSString *)processInstanceId;
/* Name to latest value. A process instance variable wins over a local
 * variable of the same name in a subprocess. */
- (NSDictionary *)historicVariablesForProcessInstance:(NSString *)processInstanceId;
- (NSArray<UDHistoricVariableUpdate *> *)historicVariableUpdatesForProcessInstance:(NSString *)processInstanceId;
- (NSArray<UDHistoricIncident *> *)historicIncidentsForProcessInstance:(NSString *)processInstanceId;
- (NSArray<UDHistoricJobLog *> *)historicJobLogForProcessInstance:(NSString *)processInstanceId;

/* Removes the history of up to batchSize ended process instances whose
 * definition's historyTimeToLive has run out since they ended, with
 * everything recorded about them. An instance whose definition has no time
 * to live is kept. Answers how many were removed, or -1 with an error. */
- (NSInteger)cleanUpHistory:(NSUInteger)batchSize error:(NSError **)error;

@end

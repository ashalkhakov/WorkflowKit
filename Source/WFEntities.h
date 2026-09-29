#import <CoreData/CoreData.h>
#import "WFTypes.h"
#import "WFManagementService.h"

/*
 * The runtime and history rows of Model/WorkflowKit.xcdatamodeld, as the
 * engine works on them inside a command's context. Internal: the public
 * API hands out value objects instead.
 */

@class WFVariableEntity;

@interface WFExecutionEntity : NSManagedObject
@property (nonatomic, copy) NSString *executionId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSString *businessKey;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *activityInstanceId;
/* On a process instance started by a call activity: the calling
 * instance, and the execution at the call activity. */
@property (nonatomic, copy) NSString *superProcessInstanceId;
@property (nonatomic, strong) WFExecutionEntity *superExecution;
/* On the execution at a call activity: the instance it called. */
@property (nonatomic, strong) WFExecutionEntity *subProcessInstance;
@property (nonatomic) BOOL isActive;
@property (nonatomic) BOOL isConcurrent;
@property (nonatomic) BOOL isScope;
/* The scope a multi-instance activity's instances run under: its
 * activity is the multi-instance activity, and its children are the
 * instances. */
@property (nonatomic) BOOL isMultiInstanceBody;
/* Runs one compensation handler for the compensation throw its parent
 * waits at. */
@property (nonatomic) BOOL isCompensation;
@property (nonatomic) BOOL suspended;
/* Bumped to make concurrent commands that both touch a scope conflict. */
@property (nonatomic) int64_t lockRevision;
@property (nonatomic, strong) WFExecutionEntity *parent;
@property (nonatomic, strong) NSSet *children;
@property (nonatomic, strong) NSSet *variables;
@property (nonatomic, strong) NSSet *tasks;
@property (nonatomic, strong) NSSet *eventSubscriptions;
@property (nonatomic, strong) NSSet *jobs;
@property (nonatomic, strong) NSSet *externalTasks;
@property (nonatomic, strong) NSSet *incidents;

- (BOOL)isProcessInstance;
- (WFExecutionEntity *)processInstance;
/* This execution if it is a scope, else the nearest scope above it. */
- (WFExecutionEntity *)scopeExecution;
- (NSArray<WFExecutionEntity *> *)concurrentChildren;
- (WFVariableEntity *)localVariableNamed:(NSString *)name;
@end

typedef NS_ENUM(int16_t, WFVariableType) {
	WFVariableTypeNull = 0,
	WFVariableTypeString,
	WFVariableTypeBoolean,
	WFVariableTypeInteger,
	WFVariableTypeDouble,
	WFVariableTypeDate,
	WFVariableTypeBytes,
	WFVariableTypeJSON
};

/* A typed value, as both variable rows store it. */
@interface NSManagedObject (WFTypedValue)
- (id)wf_value;
/* NO when the value is not one the engine stores. */
- (BOOL)wf_setValue:(id)value;
@end

@interface WFVariableEntity : NSManagedObject
@property (nonatomic, copy) NSString *variableId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic) int16_t type;
@property (nonatomic, copy) NSString *textValue;
@property (nonatomic, strong) NSNumber *wholeNumber;
@property (nonatomic, strong) NSNumber *realNumber;
@property (nonatomic, copy) NSData *bytesValue;
@property (nonatomic, strong) WFExecutionEntity *execution;
@end

@interface WFTaskEntity : NSManagedObject
@property (nonatomic, copy) NSString *taskId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *taskDefinitionKey;
@property (nonatomic, copy) NSString *assignee;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSString *activityInstanceId;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, copy) NSDate *dueDate;
@property (nonatomic) int32_t priority;
@property (nonatomic, strong) WFExecutionEntity *execution;
@end

extern NSString * const WFEventTypeMessage;
extern NSString * const WFEventTypeSignal;
/* A completed activity's compensation handler, waiting on its scope:
 * activityId the activity, eventName the subprocess it completed in when
 * it was carried up out of one. */
extern NSString * const WFEventTypeCompensate;
/* The same, queued on a compensation throw that works through them. */
extern NSString * const WFEventTypeCompensating;

@interface WFEventSubscriptionEntity : NSManagedObject
@property (nonatomic, copy) NSString *subscriptionId;
@property (nonatomic, copy) NSString *eventType;
@property (nonatomic, copy) NSString *eventName;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *processInstanceId;
/* Set on a start event's subscription, which has no execution. */
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSDate *createdAt;
/* Orders subscriptions made in the same instant: compensation runs the
 * newest first. */
@property (nonatomic) int64_t sequence;
@property (nonatomic, strong) WFExecutionEntity *execution;
@end

#define WFJobTypeTimer WFJobTypeTimerName
/* A timer start event's job: it has a definition, not an execution. */
#define WFJobTypeTimerStart WFJobTypeTimerStartName
#define WFJobTypeAsyncBefore WFJobTypeAsyncBeforeName
#define WFJobTypeAsyncAfter WFJobTypeAsyncAfterName

@interface WFJobEntity : NSManagedObject
@property (nonatomic, copy) NSString *jobId;
@property (nonatomic, copy) NSString *jobType;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSDate *dueDate;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, copy) NSString *lockOwner;
@property (nonatomic, copy) NSDate *lockExpiration;
@property (nonatomic) int32_t retries;
@property (nonatomic) BOOL exclusive;
@property (nonatomic) int64_t priority;
@property (nonatomic, copy) NSString *exceptionMessage;
/* A timer cycle's rest after this firing: R2/PT10M, R/PT1H; nil for a
 * timer that fires once. */
@property (nonatomic, copy) NSString *repeat;
@property (nonatomic, strong) WFExecutionEntity *execution;
@end

@interface WFExternalTaskEntity : NSManagedObject
@property (nonatomic, copy) NSString *externalTaskId;
@property (nonatomic, copy) NSString *topic;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *activityInstanceId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *workerId;
@property (nonatomic, copy) NSDate *lockExpiration;
@property (nonatomic, strong) NSNumber *retries;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic) int64_t priority;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, strong) WFExecutionEntity *execution;
@end

#define WFIncidentTypeFailedJob WFIncidentTypeFailedJobName
#define WFIncidentTypeFailedExternalTask WFIncidentTypeFailedExternalTaskName

/* A job or external task that ran out of retries. configuration is its id. */
@interface WFIncidentEntity : NSManagedObject
@property (nonatomic, copy) NSString *incidentId;
@property (nonatomic, copy) NSString *incidentType;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *configuration;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, strong) WFExecutionEntity *execution;
@end

extern NSString * const WFHistoricStateActive;
extern NSString * const WFHistoricStateCompleted;
extern NSString * const WFHistoricStateInternallyTerminated;

@interface WFHistoricProcessInstanceEntity : NSManagedObject
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *businessKey;
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSString *definitionKey;
@property (nonatomic, copy) NSDate *startTime;
@property (nonatomic, copy) NSDate *endTime;
@property (nonatomic, copy) NSString *state;
@property (nonatomic, copy) NSString *superProcessInstanceId;
@end

@interface WFHistoricVariableEntity : NSManagedObject
@property (nonatomic, copy) NSString *variableId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic) BOOL scopeIsProcessInstance;
@property (nonatomic) int16_t type;
@property (nonatomic, copy) NSString *textValue;
@property (nonatomic, strong) NSNumber *wholeNumber;
@property (nonatomic, strong) NSNumber *realNumber;
@property (nonatomic, copy) NSData *bytesValue;
@property (nonatomic, copy) NSDate *updatedAt;
@end

@interface WFHistoricActivityInstanceEntity : NSManagedObject
@property (nonatomic, copy) NSString *activityInstanceId;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *activityName;
@property (nonatomic, copy) NSString *activityType;
/* For a call activity: the instance it started. */
@property (nonatomic, copy) NSString *calledProcessInstanceId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSDate *startTime;
@property (nonatomic, copy) NSDate *endTime;
@property (nonatomic) BOOL canceled;
@property (nonatomic) int64_t sequence;
@end

@interface WFHistoricTaskInstanceEntity : NSManagedObject
@property (nonatomic, copy) NSString *taskId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *taskDefinitionKey;
@property (nonatomic, copy) NSString *assignee;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSDate *startTime;
@property (nonatomic, copy) NSDate *endTime;
@property (nonatomic, copy) NSString *deleteReason;
@end

@interface WFHistoricVariableUpdateEntity : NSManagedObject
@property (nonatomic, copy) NSString *variableId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSDate *time;
@property (nonatomic) int64_t sequence;
@end

@interface WFHistoricIncidentEntity : NSManagedObject
@property (nonatomic, copy) NSString *incidentId;
@property (nonatomic, copy) NSString *incidentType;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *configuration;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, copy) NSDate *endTime;
@property (nonatomic, copy) NSString *state;
@end

@interface WFHistoricJobLogEntity : NSManagedObject
@property (nonatomic, copy) NSString *jobId;
@property (nonatomic, copy) NSString *jobType;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSDate *timestamp;
@property (nonatomic, copy) NSString *state;
@property (nonatomic, copy) NSString *exceptionMessage;
@property (nonatomic) int32_t retries;
@property (nonatomic) int64_t sequence;
@end

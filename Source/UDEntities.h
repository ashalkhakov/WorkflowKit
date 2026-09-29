#ifndef UDEntities_h
#define UDEntities_h

#import <CoreData/CoreData.h>
#import "UDTypes.h"
#import "UDManagementService.h"

/*
 * The runtime and history rows of Model/UDWorkflow.xcdatamodeld, as the
 * engine works on them inside a command's context. Internal: the public
 * API hands out value objects instead.
 */

@class UDVariableEntity;

@interface UDExecutionEntity : NSManagedObject
@property (nonatomic, copy) NSString *executionId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSString *businessKey;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *activityInstanceId;
@property (nonatomic) BOOL isActive;
@property (nonatomic) BOOL isConcurrent;
@property (nonatomic) BOOL isScope;
@property (nonatomic) BOOL suspended;
/* Bumped to make concurrent commands that both touch a scope conflict. */
@property (nonatomic) int64_t lockRevision;
@property (nonatomic, strong) UDExecutionEntity *parent;
@property (nonatomic, strong) NSSet *children;
@property (nonatomic, strong) NSSet *variables;
@property (nonatomic, strong) NSSet *tasks;
@property (nonatomic, strong) NSSet *eventSubscriptions;
@property (nonatomic, strong) NSSet *jobs;
@property (nonatomic, strong) NSSet *externalTasks;
@property (nonatomic, strong) NSSet *incidents;

- (BOOL)isProcessInstance;
- (UDExecutionEntity *)processInstance;
/* This execution if it is a scope, else the nearest scope above it. */
- (UDExecutionEntity *)scopeExecution;
- (NSArray<UDExecutionEntity *> *)concurrentChildren;
- (UDVariableEntity *)localVariableNamed:(NSString *)name;
@end

typedef NS_ENUM(int16_t, UDVariableType) {
	UDVariableTypeNull = 0,
	UDVariableTypeString,
	UDVariableTypeBoolean,
	UDVariableTypeInteger,
	UDVariableTypeDouble,
	UDVariableTypeDate,
	UDVariableTypeBytes,
	UDVariableTypeJSON
};

/* A typed value, as both variable rows store it. */
@interface NSManagedObject (UDTypedValue)
- (id)ud_value;
/* NO when the value is not one the engine stores. */
- (BOOL)ud_setValue:(id)value;
@end

@interface UDVariableEntity : NSManagedObject
@property (nonatomic, copy) NSString *variableId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic) int16_t type;
@property (nonatomic, copy) NSString *textValue;
@property (nonatomic, strong) NSNumber *wholeNumber;
@property (nonatomic, strong) NSNumber *realNumber;
@property (nonatomic, copy) NSData *bytesValue;
@property (nonatomic, strong) UDExecutionEntity *execution;
@end

@interface UDTaskEntity : NSManagedObject
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
@property (nonatomic, strong) UDExecutionEntity *execution;
@end

extern NSString * const UDEventTypeMessage;
extern NSString * const UDEventTypeSignal;

@interface UDEventSubscriptionEntity : NSManagedObject
@property (nonatomic, copy) NSString *subscriptionId;
@property (nonatomic, copy) NSString *eventType;
@property (nonatomic, copy) NSString *eventName;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *processInstanceId;
/* Set on a start event's subscription, which has no execution. */
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, strong) UDExecutionEntity *execution;
@end

#define UDJobTypeTimer UDJobTypeTimerName
/* A timer start event's job: it has a definition, not an execution. */
#define UDJobTypeTimerStart UDJobTypeTimerStartName
#define UDJobTypeAsyncBefore UDJobTypeAsyncBeforeName
#define UDJobTypeAsyncAfter UDJobTypeAsyncAfterName

@interface UDJobEntity : NSManagedObject
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
@property (nonatomic, strong) UDExecutionEntity *execution;
@end

@interface UDExternalTaskEntity : NSManagedObject
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
@property (nonatomic, strong) UDExecutionEntity *execution;
@end

#define UDIncidentTypeFailedJob UDIncidentTypeFailedJobName
#define UDIncidentTypeFailedExternalTask UDIncidentTypeFailedExternalTaskName

/* A job or external task that ran out of retries. configuration is its id. */
@interface UDIncidentEntity : NSManagedObject
@property (nonatomic, copy) NSString *incidentId;
@property (nonatomic, copy) NSString *incidentType;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *configuration;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, strong) UDExecutionEntity *execution;
@end

extern NSString * const UDHistoricStateActive;
extern NSString * const UDHistoricStateCompleted;

@interface UDHistoricProcessInstanceEntity : NSManagedObject
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSString *businessKey;
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSString *definitionKey;
@property (nonatomic, copy) NSDate *startTime;
@property (nonatomic, copy) NSDate *endTime;
@property (nonatomic, copy) NSString *state;
@end

@interface UDHistoricVariableEntity : NSManagedObject
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

@interface UDHistoricActivityInstanceEntity : NSManagedObject
@property (nonatomic, copy) NSString *activityInstanceId;
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy) NSString *activityName;
@property (nonatomic, copy) NSString *activityType;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSDate *startTime;
@property (nonatomic, copy) NSDate *endTime;
@property (nonatomic) BOOL canceled;
@property (nonatomic) int64_t sequence;
@end

@interface UDHistoricTaskInstanceEntity : NSManagedObject
@property (nonatomic, copy) NSString *taskId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *taskDefinitionKey;
@property (nonatomic, copy) NSString *assignee;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSDate *startTime;
@property (nonatomic, copy) NSDate *endTime;
@property (nonatomic, copy) NSString *deleteReason;
@end

@interface UDHistoricVariableUpdateEntity : NSManagedObject
@property (nonatomic, copy) NSString *variableId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *processInstanceId;
@property (nonatomic, copy) NSDate *time;
@property (nonatomic) int64_t sequence;
@end

@interface UDHistoricIncidentEntity : NSManagedObject
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

@interface UDHistoricJobLogEntity : NSManagedObject
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

#endif /* UDEntities_h */

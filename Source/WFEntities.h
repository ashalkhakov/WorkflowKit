#import <CoreData/CoreData.h>
#import "WFTypes.h"
#import "WFManagementService.h"

/*
 * The runtime and history rows of Model/WorkflowKit.xcdatamodeld, as the
 * engine works on them inside a command's context. Internal: the public
 * API hands out value objects instead.
 *
 * Their classes are generated from the model as the library builds
 * (Codegen Class Definition: WFTaskEntity+CoreDataClass.h and its
 * properties), but for WFExecution's, which has behaviour of its own:
 * written here, its properties generated (Category/Extension).
 */

#import "WFExecutionEntity.h"
#import "WFExecutionEntity+CoreDataProperties.h"

#import "WFDecisionRecordEntity+CoreDataClass.h"
#import "WFDefinitionRecordEntity+CoreDataClass.h"
#import "WFDeploymentEntity+CoreDataClass.h"
#import "WFEventSubscriptionEntity+CoreDataClass.h"
#import "WFExternalTaskEntity+CoreDataClass.h"
#import "WFFormRecordEntity+CoreDataClass.h"
#import "WFHistoricActivityInstanceEntity+CoreDataClass.h"
#import "WFHistoricDecisionInstanceEntity+CoreDataClass.h"
#import "WFHistoricIncidentEntity+CoreDataClass.h"
#import "WFHistoricJobLogEntity+CoreDataClass.h"
#import "WFHistoricProcessInstanceEntity+CoreDataClass.h"
#import "WFHistoricTaskInstanceEntity+CoreDataClass.h"
#import "WFHistoricVariableEntity+CoreDataClass.h"
#import "WFHistoricVariableUpdateEntity+CoreDataClass.h"
#import "WFIdentityLinkEntity+CoreDataClass.h"
#import "WFIncidentEntity+CoreDataClass.h"
#import "WFJobEntity+CoreDataClass.h"
#import "WFPropertyEntity+CoreDataClass.h"
#import "WFResourceEntity+CoreDataClass.h"
#import "WFTaskEntity+CoreDataClass.h"
#import "WFVariableEntity+CoreDataClass.h"

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

/* How a number is stored: a boolean (@YES), a whole number, else a real. */
BOOL WFIsBooleanNumber(NSNumber *number);
BOOL WFIsIntegerNumber(NSNumber *number);

/* A typed value, as both variable rows store it. */
@interface NSManagedObject (WFTypedValue)
- (id)wf_value;
/* NO when the value is not one the engine stores. */
- (BOOL)wf_setValue:(id)value;
@end

extern NSString * const WFIdentityLinkCandidate;
/* Who may start a process definition: camunda:candidateStarterUsers and
 * camunda:candidateStarterGroups, linked to its definition record. */
extern NSString * const WFIdentityLinkStarter;

extern NSString * const WFEventTypeMessage;
extern NSString * const WFEventTypeSignal;
/* A conditional event waiting for its condition to hold; without an
 * execution, a process's conditional start event. */
extern NSString * const WFEventTypeConditional;
/* A completed activity's compensation handler, waiting on its scope:
 * activityId the activity, eventName the subprocess it completed in when
 * it was carried up out of one. */
extern NSString * const WFEventTypeCompensate;
/* The same, queued on a compensation throw that works through them. */
extern NSString * const WFEventTypeCompensating;

#define WFJobTypeTimer WFJobTypeTimerName
/* A timer start event's job: it has a definition, not an execution. */
#define WFJobTypeTimerStart WFJobTypeTimerStartName
#define WFJobTypeAsyncBefore WFJobTypeAsyncBeforeName
#define WFJobTypeAsyncAfter WFJobTypeAsyncAfterName

#define WFIncidentTypeFailedJob WFIncidentTypeFailedJobName
#define WFIncidentTypeFailedExternalTask WFIncidentTypeFailedExternalTaskName

extern NSString * const WFHistoricStateActive;
extern NSString * const WFHistoricStateCompleted;
extern NSString * const WFHistoricStateInternallyTerminated;
extern NSString * const WFHistoricStateExternallyTerminated;


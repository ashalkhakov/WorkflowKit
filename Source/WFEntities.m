#import "WFEntities.h"
#include <string.h>

NSString * const WFEventTypeMessage = @"message";
NSString * const WFEventTypeSignal = @"signal";
NSString * const WFEventTypeCompensate = @"compensate";
NSString * const WFEventTypeCompensating = @"compensating";
NSString * const WFJobTypeTimerName = @"timer";
NSString * const WFJobTypeTimerStartName = @"timer-start";
NSString * const WFJobTypeAsyncBeforeName = @"async-before";
NSString * const WFJobTypeAsyncAfterName = @"async-after";
NSString * const WFIncidentTypeFailedJobName = @"failedJob";
NSString * const WFIncidentTypeFailedExternalTaskName = @"failedExternalTask";
NSString * const WFHistoricStateActive = @"ACTIVE";
NSString * const WFHistoricStateCompleted = @"COMPLETED";
NSString * const WFHistoricStateInternallyTerminated = @"INTERNALLY_TERMINATED";

@implementation WFExecutionEntity
@dynamic executionId, processInstanceId, definitionId, businessKey;
@dynamic activityId, activityInstanceId, isActive, isConcurrent, isScope;
@dynamic suspended, lockRevision, parent, children, variables, tasks;
@dynamic eventSubscriptions, jobs, externalTasks, incidents;
@dynamic superProcessInstanceId, superExecution, subProcessInstance, isMultiInstanceBody;
@dynamic isCompensation;

- (BOOL)isProcessInstance
{
	return self.parent == nil;
}

- (WFExecutionEntity *)processInstance
{
	WFExecutionEntity *execution = self;
	while (execution.parent != nil) {
		execution = execution.parent;
	}
	return execution;
}

- (WFExecutionEntity *)scopeExecution
{
	WFExecutionEntity *execution = self;
	while (!execution.isScope && execution.parent != nil) {
		execution = execution.parent;
	}
	return execution;
}

- (NSArray<WFExecutionEntity *> *)concurrentChildren
{
	NSMutableArray *result = [NSMutableArray array];
	for (WFExecutionEntity *child in self.children) {
		/* A deleted child stays in the set until pending changes are
		 * processed. */
		if (child.isConcurrent && ![child isDeleted]) {
			[result addObject:child];
		}
	}
	/* A stable order, so behaviour does not depend on set iteration. */
	[result sortUsingDescriptors:@[ [NSSortDescriptor
		sortDescriptorWithKey:@"executionId" ascending:YES] ]];
	return result;
}

- (WFVariableEntity *)localVariableNamed:(NSString *)name
{
	for (WFVariableEntity *variable in self.variables) {
		if (![variable isDeleted] && [variable.name isEqualToString:name]) {
			return variable;
		}
	}
	return nil;
}

@end

static BOOL
WFIsBooleanNumber(NSNumber *number)
{
	const char *type = [number objCType];
	return strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(char)) == 0
		|| strcmp(type, "B") == 0;
}

static BOOL
WFIsIntegerNumber(NSNumber *number)
{
	const char *type = [number objCType];
	return strcmp(type, @encode(double)) != 0 && strcmp(type, @encode(float)) != 0;
}

@implementation NSManagedObject (WFTypedValue)

- (id)wf_value
{
	switch ([[self valueForKey:@"type"] shortValue]) {
	case WFVariableTypeString:
		return [self valueForKey:@"textValue"];
	case WFVariableTypeBoolean:
		return [NSNumber numberWithBool:[[self valueForKey:@"wholeNumber"] boolValue]];
	case WFVariableTypeInteger:
		return [NSNumber numberWithLongLong:[[self valueForKey:@"wholeNumber"] longLongValue]];
	case WFVariableTypeDouble:
		return [NSNumber numberWithDouble:[[self valueForKey:@"realNumber"] doubleValue]];
	case WFVariableTypeDate:
		return [NSDate dateWithTimeIntervalSince1970:
			[[self valueForKey:@"realNumber"] doubleValue]];
	case WFVariableTypeBytes:
		return [self valueForKey:@"bytesValue"];
	case WFVariableTypeJSON: {
		NSData *data = [[self valueForKey:@"textValue"] dataUsingEncoding:NSUTF8StringEncoding];
		return data == nil ? nil
			: [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	}
	default:
		return [NSNull null];
	}
}

- (BOOL)wf_setValue:(id)value
{
	WFVariableType type = WFVariableTypeNull;
	NSString *text = nil;
	NSNumber *wholeNumber = nil;
	NSNumber *realNumber = nil;
	NSData *bytes = nil;
	if (value == nil || value == [NSNull null]) {
		type = WFVariableTypeNull;
	} else if ([value isKindOfClass:[NSString class]]) {
		type = WFVariableTypeString;
		text = value;
	} else if ([value isKindOfClass:[NSNumber class]]) {
		if (WFIsBooleanNumber(value)) {
			type = WFVariableTypeBoolean;
			wholeNumber = [NSNumber numberWithLongLong:[value boolValue] ? 1 : 0];
		} else if (WFIsIntegerNumber(value)) {
			type = WFVariableTypeInteger;
			wholeNumber = [NSNumber numberWithLongLong:[value longLongValue]];
		} else {
			type = WFVariableTypeDouble;
			realNumber = [NSNumber numberWithDouble:[value doubleValue]];
		}
	} else if ([value isKindOfClass:[NSDate class]]) {
		type = WFVariableTypeDate;
		realNumber = [NSNumber numberWithDouble:[value timeIntervalSince1970]];
	} else if ([value isKindOfClass:[NSData class]]) {
		type = WFVariableTypeBytes;
		bytes = value;
	} else if (([value isKindOfClass:[NSArray class]]
	            || [value isKindOfClass:[NSDictionary class]])
	           && [NSJSONSerialization isValidJSONObject:value]) {
		type = WFVariableTypeJSON;
		NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
		if (data == nil) {
			return NO;
		}
		text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	} else {
		return NO;
	}
	[self setValue:[NSNumber numberWithShort:type] forKey:@"type"];
	[self setValue:text forKey:@"textValue"];
	[self setValue:wholeNumber forKey:@"wholeNumber"];
	[self setValue:realNumber forKey:@"realNumber"];
	[self setValue:bytes forKey:@"bytesValue"];
	return YES;
}

@end

@implementation WFVariableEntity
@dynamic variableId, name, processInstanceId, type, textValue, wholeNumber;
@dynamic realNumber, bytesValue, execution;
@end

@implementation WFTaskEntity
@dynamic taskId, name, taskDefinitionKey, assignee, processInstanceId;
@dynamic definitionId, activityInstanceId, createdAt, dueDate, priority, execution;
@end

@implementation WFEventSubscriptionEntity
@dynamic subscriptionId, eventType, eventName, activityId, processInstanceId;
@dynamic definitionId, createdAt, sequence, execution;
@end

@implementation WFJobEntity
@dynamic jobId, jobType, activityId, processInstanceId, definitionId, dueDate, createdAt;
@dynamic lockOwner, lockExpiration, retries, exclusive, priority;
@dynamic exceptionMessage, repeat, execution;
@end

@implementation WFExternalTaskEntity
@dynamic externalTaskId, topic, activityId, activityInstanceId, processInstanceId;
@dynamic workerId, lockExpiration, retries, errorMessage, priority, createdAt, execution;
@end

@implementation WFIncidentEntity
@dynamic incidentId, incidentType, message, activityId, processInstanceId;
@dynamic configuration, createdAt, execution;
@end

@implementation WFHistoricProcessInstanceEntity
@dynamic processInstanceId, businessKey, definitionId, definitionKey;
@dynamic startTime, endTime, state, superProcessInstanceId;
@end

@implementation WFHistoricVariableEntity
@dynamic variableId, name, processInstanceId, scopeIsProcessInstance, type;
@dynamic textValue, wholeNumber, realNumber, bytesValue, updatedAt;
@end

@implementation WFHistoricActivityInstanceEntity
@dynamic activityInstanceId, activityId, activityName, activityType;
@dynamic processInstanceId, startTime, endTime, canceled, sequence, calledProcessInstanceId;
@end

@implementation WFHistoricTaskInstanceEntity
@dynamic taskId, name, taskDefinitionKey, assignee, processInstanceId;
@dynamic startTime, endTime, deleteReason;
@end

@implementation WFHistoricVariableUpdateEntity
@dynamic variableId, name, processInstanceId, time, sequence;
@end

@implementation WFHistoricIncidentEntity
@dynamic incidentId, incidentType, message, activityId, processInstanceId;
@dynamic configuration, createdAt, endTime, state;
@end

@implementation WFHistoricJobLogEntity
@dynamic jobId, jobType, activityId, processInstanceId, timestamp, state;
@dynamic exceptionMessage, retries, sequence;
@end

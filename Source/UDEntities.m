#import "UDEntities.h"
#include <string.h>

NSString * const UDEventTypeMessage = @"message";
NSString * const UDJobTypeTimerName = @"timer";
NSString * const UDJobTypeTimerStartName = @"timer-start";
NSString * const UDJobTypeAsyncBeforeName = @"async-before";
NSString * const UDJobTypeAsyncAfterName = @"async-after";
NSString * const UDIncidentTypeFailedJobName = @"failedJob";
NSString * const UDIncidentTypeFailedExternalTaskName = @"failedExternalTask";
NSString * const UDHistoricStateActive = @"ACTIVE";
NSString * const UDHistoricStateCompleted = @"COMPLETED";

@implementation UDExecutionEntity
@dynamic executionId, processInstanceId, definitionId, businessKey;
@dynamic activityId, activityInstanceId, isActive, isConcurrent, isScope;
@dynamic suspended, lockRevision, parent, children, variables, tasks;
@dynamic eventSubscriptions, jobs, externalTasks, incidents;

- (BOOL)isProcessInstance
{
	return self.parent == nil;
}

- (UDExecutionEntity *)processInstance
{
	UDExecutionEntity *execution = self;
	while (execution.parent != nil) {
		execution = execution.parent;
	}
	return execution;
}

- (UDExecutionEntity *)scopeExecution
{
	UDExecutionEntity *execution = self;
	while (!execution.isScope && execution.parent != nil) {
		execution = execution.parent;
	}
	return execution;
}

- (NSArray<UDExecutionEntity *> *)concurrentChildren
{
	NSMutableArray *result = [NSMutableArray array];
	for (UDExecutionEntity *child in self.children) {
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

- (UDVariableEntity *)localVariableNamed:(NSString *)name
{
	for (UDVariableEntity *variable in self.variables) {
		if (![variable isDeleted] && [variable.name isEqualToString:name]) {
			return variable;
		}
	}
	return nil;
}

@end

static BOOL
UDIsBooleanNumber(NSNumber *number)
{
	const char *type = [number objCType];
	return strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(char)) == 0
		|| strcmp(type, "B") == 0;
}

static BOOL
UDIsIntegerNumber(NSNumber *number)
{
	const char *type = [number objCType];
	return strcmp(type, @encode(double)) != 0 && strcmp(type, @encode(float)) != 0;
}

@implementation NSManagedObject (UDTypedValue)

- (id)ud_value
{
	switch ([[self valueForKey:@"type"] shortValue]) {
	case UDVariableTypeString:
		return [self valueForKey:@"textValue"];
	case UDVariableTypeBoolean:
		return [NSNumber numberWithBool:[[self valueForKey:@"wholeNumber"] boolValue]];
	case UDVariableTypeInteger:
		return [NSNumber numberWithLongLong:[[self valueForKey:@"wholeNumber"] longLongValue]];
	case UDVariableTypeDouble:
		return [NSNumber numberWithDouble:[[self valueForKey:@"realNumber"] doubleValue]];
	case UDVariableTypeDate:
		return [NSDate dateWithTimeIntervalSince1970:
			[[self valueForKey:@"realNumber"] doubleValue]];
	case UDVariableTypeBytes:
		return [self valueForKey:@"bytesValue"];
	case UDVariableTypeJSON: {
		NSData *data = [[self valueForKey:@"textValue"] dataUsingEncoding:NSUTF8StringEncoding];
		return data == nil ? nil
			: [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	}
	default:
		return [NSNull null];
	}
}

- (BOOL)ud_setValue:(id)value
{
	UDVariableType type = UDVariableTypeNull;
	NSString *text = nil;
	NSNumber *wholeNumber = nil;
	NSNumber *realNumber = nil;
	NSData *bytes = nil;
	if (value == nil || value == [NSNull null]) {
		type = UDVariableTypeNull;
	} else if ([value isKindOfClass:[NSString class]]) {
		type = UDVariableTypeString;
		text = value;
	} else if ([value isKindOfClass:[NSNumber class]]) {
		if (UDIsBooleanNumber(value)) {
			type = UDVariableTypeBoolean;
			wholeNumber = [NSNumber numberWithLongLong:[value boolValue] ? 1 : 0];
		} else if (UDIsIntegerNumber(value)) {
			type = UDVariableTypeInteger;
			wholeNumber = [NSNumber numberWithLongLong:[value longLongValue]];
		} else {
			type = UDVariableTypeDouble;
			realNumber = [NSNumber numberWithDouble:[value doubleValue]];
		}
	} else if ([value isKindOfClass:[NSDate class]]) {
		type = UDVariableTypeDate;
		realNumber = [NSNumber numberWithDouble:[value timeIntervalSince1970]];
	} else if ([value isKindOfClass:[NSData class]]) {
		type = UDVariableTypeBytes;
		bytes = value;
	} else if (([value isKindOfClass:[NSArray class]]
	            || [value isKindOfClass:[NSDictionary class]])
	           && [NSJSONSerialization isValidJSONObject:value]) {
		type = UDVariableTypeJSON;
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

@implementation UDVariableEntity
@dynamic variableId, name, processInstanceId, type, textValue, wholeNumber;
@dynamic realNumber, bytesValue, execution;
@end

@implementation UDTaskEntity
@dynamic taskId, name, taskDefinitionKey, assignee, processInstanceId;
@dynamic definitionId, activityInstanceId, createdAt, dueDate, priority, execution;
@end

@implementation UDEventSubscriptionEntity
@dynamic subscriptionId, eventType, eventName, activityId, processInstanceId;
@dynamic definitionId, createdAt, execution;
@end

@implementation UDJobEntity
@dynamic jobId, jobType, activityId, processInstanceId, definitionId, dueDate, createdAt;
@dynamic lockOwner, lockExpiration, retries, exclusive, priority;
@dynamic exceptionMessage, execution;
@end

@implementation UDExternalTaskEntity
@dynamic externalTaskId, topic, activityId, activityInstanceId, processInstanceId;
@dynamic workerId, lockExpiration, retries, errorMessage, priority, createdAt, execution;
@end

@implementation UDIncidentEntity
@dynamic incidentId, incidentType, message, activityId, processInstanceId;
@dynamic configuration, createdAt, execution;
@end

@implementation UDHistoricProcessInstanceEntity
@dynamic processInstanceId, businessKey, definitionId, definitionKey;
@dynamic startTime, endTime, state;
@end

@implementation UDHistoricVariableEntity
@dynamic variableId, name, processInstanceId, scopeIsProcessInstance, type;
@dynamic textValue, wholeNumber, realNumber, bytesValue, updatedAt;
@end

@implementation UDHistoricActivityInstanceEntity
@dynamic activityInstanceId, activityId, activityName, activityType;
@dynamic processInstanceId, startTime, endTime, canceled, sequence;
@end

@implementation UDHistoricTaskInstanceEntity
@dynamic taskId, name, taskDefinitionKey, assignee, processInstanceId;
@dynamic startTime, endTime, deleteReason;
@end

@implementation UDHistoricVariableUpdateEntity
@dynamic variableId, name, processInstanceId, time, sequence;
@end

@implementation UDHistoricIncidentEntity
@dynamic incidentId, incidentType, message, activityId, processInstanceId;
@dynamic configuration, createdAt, endTime, state;
@end

@implementation UDHistoricJobLogEntity
@dynamic jobId, jobType, activityId, processInstanceId, timestamp, state;
@dynamic exceptionMessage, retries, sequence;
@end

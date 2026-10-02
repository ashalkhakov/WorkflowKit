#import "WDEntities.h"

NSDictionary *
WDEntityClasses(void)
{
	return @{ @"WFVariable": @"WDVariable", @"WFHistoricVariableUpdate": @"WDVariable",
	          @"WFHistoricVariable": @"WDVariable",
	          @"WFDefinitionRecord": @"WDSuspendable", @"WFExecution": @"WDSuspendable",
	          @"WFHistoricProcessInstance": @"WDHistoricInstance" };
}

@implementation WDVariable

+ (NSSet *)keyPathsForValuesAffectingDisplayValue
{
	return [NSSet setWithObjects:@"textValue", @"jsonText", @"realNumber", @"wholeNumber", @"truthValue",
		@"dateTime", @"bytesValue", nil];
}

- (id)displayValue
{
	for (NSString *key in @[ @"textValue", @"jsonText", @"wholeNumber", @"realNumber", @"dateTime" ]) {
		id value = [self valueForKey:key];
		if (value != nil) {
			return value;
		}
	}
	id truth = [self valueForKey:@"truthValue"];
	if (truth != nil) {
		return [truth boolValue] ? @"true" : @"false";
	}
	NSData *bytes = [self valueForKey:@"bytesValue"];
	return bytes != nil ? [NSString stringWithFormat:@"%lu bytes", (unsigned long)[bytes length]] : nil;
}

@end

@implementation WDSuspendable

+ (NSSet *)keyPathsForValuesAffectingState
{
	return [NSSet setWithObject:@"suspended"];
}

- (NSString *)state
{
	return [[self valueForKey:@"suspended"] boolValue] ? @"Suspended" : @"Active";
}

- (NSDate *)startTime
{
	return nil;
}

- (NSDate *)endTime
{
	return nil;
}

@end

@implementation WDHistoricInstance

+ (NSSet *)keyPathsForValuesAffectingExecutionId
{
	return [NSSet setWithObject:@"processInstanceId"];
}

- (NSString *)executionId
{
	return [self valueForKey:@"processInstanceId"];
}

- (NSString *)state
{
	[self willAccessValueForKey:@"state"];
	NSString *raw = [self primitiveValueForKey:@"state"];
	[self didAccessValueForKey:@"state"];
	NSDictionary *words = @{ @"ACTIVE": @"Active", @"SUSPENDED": @"Suspended", @"COMPLETED": @"Completed",
	                         @"EXTERNALLY_TERMINATED": @"Canceled", @"INTERNALLY_TERMINATED": @"Terminated" };
	return [words objectForKey:raw ?: @""] ?: [raw capitalizedString];
}

- (BOOL)isRunning
{
	return [self valueForKey:@"endTime"] == nil;
}

@end

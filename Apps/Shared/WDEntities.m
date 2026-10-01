#import "WDEntities.h"

NSDictionary *
WDEntityClasses(void)
{
	return @{ @"WFVariable": @"WDVariable", @"WFHistoricVariableUpdate": @"WDVariable",
	          @"WFDefinitionRecord": @"WDSuspendable", @"WFExecution": @"WDSuspendable" };
}

@implementation WDVariable

+ (NSSet *)keyPathsForValuesAffectingDisplayValue
{
	return [NSSet setWithObjects:@"textValue", @"jsonText", @"realNumber", @"truthValue", @"dateTime",
		@"bytesValue", nil];
}

- (id)displayValue
{
	for (NSString *key in @[ @"textValue", @"jsonText", @"realNumber", @"dateTime" ]) {
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

@end

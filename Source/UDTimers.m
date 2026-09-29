#import "UDTimers.h"
#import "UDDuration.h"
#import "UDFeelInternal.h"
#include <math.h>

NSString *
UDISODurationText(NSTimeInterval seconds)
{
	UDFeelDuration *duration = [UDFeelDuration seconds:seconds];
	return duration != nil ? [duration description] : @"PT0S";
}

/* A duration as timers take it: FEEL's, or weeks, which ISO has and
 * FEEL does not. */
static UDFeelDuration *
UDTimerDuration(NSString *text)
{
	UDFeelDuration *duration = UDFeelParseDuration(text);
	if (duration != nil) {
		return duration;
	}
	NSTimeInterval seconds = UDParseISODuration(text);
	return seconds >= 0 ? [UDFeelDuration seconds:seconds] : nil;
}

/* R3/PT10M, R/PT10M, R3/2024-01-01T09:00:00Z/PT10M: *count -1 for
 * forever, *start nil when it starts one period from now. */
static BOOL
UDParseCycle(NSString *text, NSInteger *count, NSDate **start, UDFeelDuration **every)
{
	NSArray *parts = [text componentsSeparatedByString:@"/"];
	if (([parts count] != 2 && [parts count] != 3) || ![[parts objectAtIndex:0] hasPrefix:@"R"]) {
		return NO;
	}
	NSString *repeat = [[parts objectAtIndex:0] substringFromIndex:1];
	if ([repeat length] == 0) {
		*count = -1;
	} else {
		NSScanner *scanner = [NSScanner scannerWithString:repeat];
		NSInteger n = 0;
		if (![scanner scanInteger:&n] || ![scanner isAtEnd] || n < 1) {
			return NO;
		}
		*count = n;
	}
	*start = nil;
	if ([parts count] == 3) {
		*start = UDFeelParseDateTime([parts objectAtIndex:1]);
		if (*start == nil) {
			return NO;
		}
	}
	*every = UDTimerDuration([parts lastObject]);
	return *every != nil && ((*every).yearsAndMonths ? (*every).months > 0 : (*every).seconds > 0);
}

static NSString *
UDRemaining(NSInteger count, UDFeelDuration *every)
{
	if (count < 0) {
		return [NSString stringWithFormat:@"R/%@", every];
	}
	return count > 1 ? [NSString stringWithFormat:@"R%ld/%@", (long)count - 1, every] : nil;
}

static NSDate *
UDAfter(NSDate *date, UDFeelDuration *duration)
{
	id later = UDFeelTemporalArithmetic(UDFeelOperatorAdd, date, duration);
	return [later isKindOfClass:[NSDate class]] ? later : nil;
}

NSString *
UDTimerLiteral(UDTimerKind kind, NSString *text)
{
	text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	switch (kind) {
	case UDTimerKindDate: {
		NSDate *date = UDFeelParseDateTime(text);
		return date != nil ? UDFeelLiteralText(date) : nil;
	}
	case UDTimerKindDuration: {
		UDFeelDuration *duration = UDTimerDuration(text);
		return duration != nil ? UDFeelLiteralText(duration) : nil;
	}
	case UDTimerKindCycle: {
		NSInteger count = 0;
		NSDate *start = nil;
		UDFeelDuration *every = nil;
		return UDParseCycle(text, &count, &start, &every) ? UDFeelLiteralText(text) : nil;
	}
	}
	return nil;
}

NSString *
UDTimerText(UDTimer *timer)
{
	UDFeelNode *root = [timer.expression root];
	if (root.kind != UDFeelNodeLiteral) {
		return nil;
	}
	return UDFeelTemporalText(root.value) ?: ([root.value isKindOfClass:[NSString class]] ? root.value : nil);
}

static NSError *
UDTimerError(NSString *message)
{
	return [NSError errorWithDomain:UDWorkflowErrorDomain
	                           code:UDWorkflowErrorInvalidState
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

BOOL
UDTimerSchedule(UDTimer *timer, NSDictionary *variables, NSDate *now,
                NSDate **due, NSString **repeat, NSError **error)
{
	id value = [timer.expression valueWithVariables:variables];
	*repeat = nil;
	*due = nil;
	switch (timer.kind) {
	case UDTimerKindDate:
		if ([value isKindOfClass:[NSDate class]]) {
			*due = value;
		} else if ([value isKindOfClass:[NSString class]]) {
			*due = UDFeelParseDateTime(value);
		}
		break;
	case UDTimerKindDuration: {
		UDFeelDuration *duration = [value isKindOfClass:[NSString class]] ? UDTimerDuration(value) : nil;
		*due = duration != nil ? UDAfter(now, duration) : nil;
		break;
	}
	case UDTimerKindCycle: {
		NSInteger count = 0;
		NSDate *start = nil;
		UDFeelDuration *every = nil;
		if ([value isKindOfClass:[NSString class]] && UDParseCycle(value, &count, &start, &every)) {
			*due = start ?: UDAfter(now, every);
			*repeat = UDRemaining(count, every);
		}
		break;
	}
	}
	if (*due == nil && error != NULL) {
		NSArray *kinds = @[ @"a date and time", @"a duration", @"a cycle" ];
		*error = UDTimerError([NSString stringWithFormat:@"the timer %@ is %@, not %@",
			[timer.expression expressionString], UDFeelLiteralText(value),
			[kinds objectAtIndex:(NSUInteger)timer.kind]]);
	}
	return *due != nil;
}

BOOL
UDTimerNextDue(NSString *repeat, NSDate *last, NSDate **due, NSString **remaining)
{
	NSInteger count = 0;
	NSDate *start = nil;
	UDFeelDuration *every = nil;
	if (!UDParseCycle(repeat, &count, &start, &every)) {
		return NO;
	}
	*due = UDAfter(last, every);
	*remaining = UDRemaining(count, every);
	return *due != nil;
}

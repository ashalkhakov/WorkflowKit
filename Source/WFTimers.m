#import "WFTimers.h"
#import "WFDuration.h"
#import "WFFeelInternal.h"
#include <math.h>

NSString *
WFISODurationText(NSTimeInterval seconds)
{
	WFFeelDuration *duration = [WFFeelDuration seconds:seconds];
	return duration != nil ? [duration description] : @"PT0S";
}

/* A duration as timers take it: FEEL's, or weeks, which ISO has and
 * FEEL does not. */
static WFFeelDuration *
WFTimerDuration(NSString *text)
{
	WFFeelDuration *duration = WFFeelParseDuration(text);
	if (duration != nil) {
		return duration;
	}
	NSTimeInterval seconds = WFParseISODuration(text);
	return seconds >= 0 ? [WFFeelDuration seconds:seconds] : nil;
}

/* R3/PT10M, R/PT10M, R3/2024-01-01T09:00:00Z/PT10M: *count -1 for
 * forever, *start nil when it starts one period from now. */
static BOOL
WFParseCycle(NSString *text, NSInteger *count, NSDate **start, WFFeelDuration **every)
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
		*start = WFFeelParseDateTime([parts objectAtIndex:1]);
		if (*start == nil) {
			return NO;
		}
	}
	*every = WFTimerDuration([parts lastObject]);
	return *every != nil && ((*every).yearsAndMonths ? (*every).months > 0 : (*every).seconds > 0);
}

static NSString *
WFRemaining(NSInteger count, WFFeelDuration *every)
{
	if (count < 0) {
		return [NSString stringWithFormat:@"R/%@", every];
	}
	return count > 1 ? [NSString stringWithFormat:@"R%ld/%@", (long)count - 1, every] : nil;
}

static NSDate *
WFAfter(NSDate *date, WFFeelDuration *duration)
{
	id later = WFFeelTemporalArithmetic(WFFeelOperatorAdd, date, duration);
	return [later isKindOfClass:[NSDate class]] ? later : nil;
}

NSString *
WFTimerLiteral(WFTimerKind kind, NSString *text)
{
	text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	switch (kind) {
	case WFTimerKindDate: {
		NSDate *date = WFFeelParseDateTime(text);
		return date != nil ? WFFeelLiteralText(date) : nil;
	}
	case WFTimerKindDuration: {
		WFFeelDuration *duration = WFTimerDuration(text);
		return duration != nil ? WFFeelLiteralText(duration) : nil;
	}
	case WFTimerKindCycle: {
		NSInteger count = 0;
		NSDate *start = nil;
		WFFeelDuration *every = nil;
		return WFParseCycle(text, &count, &start, &every) ? WFFeelLiteralText(text) : nil;
	}
	}
	return nil;
}

NSString *
WFTimerText(WFTimer *timer)
{
	WFFeelNode *root = [timer.expression root];
	if (root.kind != WFFeelNodeLiteral) {
		return nil;
	}
	return WFFeelTemporalText(root.value) ?: ([root.value isKindOfClass:[NSString class]] ? root.value : nil);
}

static NSError *
WFTimerError(NSString *message)
{
	return [NSError errorWithDomain:WFErrorDomain
	                           code:WFErrorInvalidState
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

BOOL
WFTimerSchedule(WFTimer *timer, NSDictionary *variables, NSDate *now,
                NSDate **due, NSString **repeat, NSError **error)
{
	id value = [timer.expression valueWithVariables:variables];
	*repeat = nil;
	*due = nil;
	switch (timer.kind) {
	case WFTimerKindDate:
		if ([value isKindOfClass:[NSDate class]]) {
			*due = value;
		} else if ([value isKindOfClass:[NSString class]]) {
			*due = WFFeelParseDateTime(value);
		}
		break;
	case WFTimerKindDuration: {
		WFFeelDuration *duration = [value isKindOfClass:[NSString class]] ? WFTimerDuration(value) : nil;
		*due = duration != nil ? WFAfter(now, duration) : nil;
		break;
	}
	case WFTimerKindCycle: {
		NSInteger count = 0;
		NSDate *start = nil;
		WFFeelDuration *every = nil;
		if ([value isKindOfClass:[NSString class]] && WFParseCycle(value, &count, &start, &every)) {
			*due = start ?: WFAfter(now, every);
			*repeat = WFRemaining(count, every);
		}
		break;
	}
	}
	if (*due == nil && error != NULL) {
		NSArray *kinds = @[ @"a date and time", @"a duration", @"a cycle" ];
		*error = WFTimerError([NSString stringWithFormat:@"the timer %@ is %@, not %@",
			[timer.expression expressionString], WFFeelLiteralText(value),
			[kinds objectAtIndex:(NSUInteger)timer.kind]]);
	}
	return *due != nil;
}

BOOL
WFTimerNextDue(NSString *repeat, NSDate *last, NSDate **due, NSString **remaining)
{
	NSInteger count = 0;
	NSDate *start = nil;
	WFFeelDuration *every = nil;
	if (!WFParseCycle(repeat, &count, &start, &every)) {
		return NO;
	}
	*due = WFAfter(last, every);
	*remaining = WFRemaining(count, every);
	return *due != nil;
}

#import "UDDuration.h"

/* Weeks, days, hours, minutes and seconds. Years and months are calendar
 * lengths, not durations, and are refused. Answers a negative number for
 * anything else. */
NSTimeInterval
UDParseISODuration(NSString *text)
{
	NSString *s = [[text stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
	if (![s hasPrefix:@"P"] || [s length] < 2) {
		return -1;
	}
	NSScanner *scanner = [NSScanner scannerWithString:[s substringFromIndex:1]];
	[scanner setCharactersToBeSkipped:nil];
	NSTimeInterval total = 0;
	BOOL inTime = NO;
	BOOL any = NO;
	while (![scanner isAtEnd]) {
		if ([scanner scanString:@"T" intoString:NULL]) {
			if (inTime) {
				return -1;
			}
			inTime = YES;
			continue;
		}
		double value = 0;
		if (![scanner scanDouble:&value] || [scanner isAtEnd]) {
			return -1;
		}
		unichar unit = [s characterAtIndex:[scanner scanLocation] + 1];
		[scanner setScanLocation:[scanner scanLocation] + 1];
		if (!inTime && unit == 'W') {
			total += value * 7 * 86400;
		} else if (!inTime && unit == 'D') {
			total += value * 86400;
		} else if (inTime && unit == 'H') {
			total += value * 3600;
		} else if (inTime && unit == 'M') {
			total += value * 60;
		} else if (inTime && unit == 'S') {
			total += value;
		} else {
			return -1;
		}
		any = YES;
	}
	return any ? total : -1;
}

BOOL
UDParseRetryCycle(NSString *cycle, NSInteger *attempts, NSArray<NSNumber *> **delays)
{
	if (cycle == nil) {
		*attempts = UD_DEFAULT_ATTEMPTS;
		*delays = @[ @0 ];
		return YES;
	}
	NSString *text = [cycle stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([text hasPrefix:@"R"]) {
		NSRange slash = [text rangeOfString:@"/"];
		if (slash.location == NSNotFound) {
			return NO;
		}
		NSString *count = [text substringWithRange:NSMakeRange(1, slash.location - 1)];
		NSTimeInterval delay = UDParseISODuration([text substringFromIndex:slash.location + 1]);
		NSInteger retries = [count integerValue];
		if (delay < 0 || retries < 0
		    || ![[NSString stringWithFormat:@"%ld", (long)retries] isEqualToString:count]) {
			return NO;
		}
		*attempts = retries + 1;
		*delays = @[ [NSNumber numberWithDouble:delay] ];
		return YES;
	}
	NSMutableArray *list = [NSMutableArray array];
	for (NSString *part in [text componentsSeparatedByString:@","]) {
		NSTimeInterval delay = UDParseISODuration(part);
		if (delay < 0) {
			return NO;
		}
		[list addObject:[NSNumber numberWithDouble:delay]];
	}
	*attempts = [list count] + 1;
	*delays = list;
	return YES;
}

NSTimeInterval
UDRetryDelay(NSString *cycle, NSInteger attemptsLeft)
{
	NSInteger attempts = 0;
	NSArray *delays = nil;
	if (!UDParseRetryCycle(cycle, &attempts, &delays) || [delays count] == 0) {
		return 0;
	}
	/* The retry about to be scheduled is number attempts - attemptsLeft + 1. */
	NSInteger retry = attempts - attemptsLeft;
	if (retry < 0) {
		retry = 0;
	}
	NSUInteger index = (NSUInteger)retry < [delays count] ? (NSUInteger)retry : [delays count] - 1;
	return [[delays objectAtIndex:index] doubleValue];
}

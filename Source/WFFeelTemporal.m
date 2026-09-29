/*
 * FEEL's temporal values (DMN 1.3, section 10.3.2.3): dates, dates and
 * times, and the two kinds of duration, years and months and days and
 * time. A date and time is an NSDate, the type variables already hold;
 * one written without an offset is taken as UTC. Calendar work is
 * Gregorian, in UTC.
 */
#import "WFFeelInternal.h"
#include <math.h>

static NSCalendar *
WFFeelCalendar(void)
{
	NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	return calendar;
}

@implementation WFFeelDateValue

+ (instancetype)year:(NSInteger)year month:(NSInteger)month day:(NSInteger)day
{
	/* Only a day the calendar has: 2021-02-30 is none. */
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setYear:year];
	[components setMonth:month];
	[components setDay:day];
	NSCalendar *calendar = WFFeelCalendar();
	NSDate *date = [calendar dateFromComponents:components];
	if (date == nil || month < 1 || month > 12 || day < 1) {
		return nil;
	}
	NSDateComponents *back = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
	                                     fromDate:date];
	if ([back year] != year || [back month] != month || [back day] != day) {
		return nil;
	}
	WFFeelDateValue *value = [[self alloc] init];
	value->_year = year;
	value->_month = month;
	value->_day = day;
	return value;
}

+ (instancetype)dateOf:(NSDate *)date
{
	NSDateComponents *c = [WFFeelCalendar() components:NSCalendarUnitYear | NSCalendarUnitMonth
		| NSCalendarUnitDay fromDate:date];
	return [self year:[c year] month:[c month] day:[c day]];
}

- (NSDate *)startOfDay
{
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setYear:self.year];
	[components setMonth:self.month];
	[components setDay:self.day];
	return [WFFeelCalendar() dateFromComponents:components];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%04ld-%02ld-%02ld", (long)self.year, (long)self.month, (long)self.day];
}

- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[WFFeelDateValue class]] && [other year] == self.year
		&& [other month] == self.month && [other day] == self.day;
}

- (NSUInteger)hash
{
	return (NSUInteger)(self.year * 400 + self.month * 32 + self.day);
}

@end

@implementation WFFeelDuration

+ (instancetype)months:(long long)months
{
	WFFeelDuration *duration = [[self alloc] init];
	duration->_yearsAndMonths = YES;
	duration->_months = months;
	return duration;
}

+ (instancetype)seconds:(double)seconds
{
	if (seconds != seconds || fabs(seconds) > 1e15) {
		return nil;
	}
	WFFeelDuration *duration = [[self alloc] init];
	duration->_seconds = seconds;
	return duration;
}

- (NSString *)description
{
	if (self.yearsAndMonths) {
		long long months = llabs(self.months);
		NSMutableString *text = [NSMutableString stringWithString:self.months < 0 ? @"-P" : @"P"];
		if (months >= 12) {
			[text appendFormat:@"%lldY", months / 12];
		}
		if (months % 12 != 0 || months == 0) {
			[text appendFormat:@"%lldM", months % 12];
		}
		return text;
	}
	double total = fabs(self.seconds);
	long long whole = (long long)floor(total);
	double fraction = total - (double)whole;
	long long days = whole / 86400, hours = whole % 86400 / 3600, minutes = whole % 3600 / 60;
	double seconds = (double)(whole % 60) + fraction;
	NSMutableString *text = [NSMutableString stringWithString:self.seconds < 0 ? @"-P" : @"P"];
	if (days > 0) {
		[text appendFormat:@"%lldD", days];
	}
	if (hours > 0 || minutes > 0 || seconds > 0 || days == 0) {
		[text appendString:@"T"];
		if (hours > 0) {
			[text appendFormat:@"%lldH", hours];
		}
		if (minutes > 0) {
			[text appendFormat:@"%lldM", minutes];
		}
		if (seconds > 0 || (hours == 0 && minutes == 0)) {
			[text appendFormat:@"%@S", [[NSNumber numberWithDouble:round(seconds * 1000) / 1000] stringValue]];
		}
	}
	return text;
}

- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[WFFeelDuration class]] && [other yearsAndMonths] == self.yearsAndMonths
		&& [other months] == self.months && [other seconds] == self.seconds;
}

- (NSUInteger)hash
{
	return (NSUInteger)(self.months * 31 + (long long)self.seconds);
}

@end

#pragma mark - Reading ISO-8601

/* Digits at i, exactly count of them, as a number; -1 when they are not. */
static NSInteger
WFDigits(NSString *text, NSUInteger i, NSUInteger count)
{
	if (i + count > [text length]) {
		return -1;
	}
	NSInteger value = 0;
	for (NSUInteger k = 0; k < count; k++) {
		unichar c = [text characterAtIndex:i + k];
		if (c < '0' || c > '9') {
			return -1;
		}
		value = value * 10 + (c - '0');
	}
	return value;
}

WFFeelDateValue *
WFFeelParseDate(NSString *text)
{
	if ([text length] != 10 || [text characterAtIndex:4] != '-' || [text characterAtIndex:7] != '-') {
		return nil;
	}
	NSInteger year = WFDigits(text, 0, 4), month = WFDigits(text, 5, 2), day = WFDigits(text, 8, 2);
	if (year < 0 || month < 0 || day < 0) {
		return nil;
	}
	return [WFFeelDateValue year:year month:month day:day];
}

/* 2020-01-02T10:30:00, with .fraction and Z or an offset if there; UTC
 * without one. */
NSDate *
WFFeelParseDateTime(NSString *text)
{
	if ([text length] < 19 || [text characterAtIndex:10] != 'T') {
		return nil;
	}
	WFFeelDateValue *date = WFFeelParseDate([text substringToIndex:10]);
	NSInteger hour = WFDigits(text, 11, 2), minute = WFDigits(text, 14, 2), second = WFDigits(text, 17, 2);
	if (date == nil || hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59
	    || [text characterAtIndex:13] != ':' || [text characterAtIndex:16] != ':') {
		return nil;
	}
	NSUInteger i = 19;
	double fraction = 0;
	if (i < [text length] && [text characterAtIndex:i] == '.') {
		double scale = 0.1;
		i++;
		NSUInteger start = i;
		while (i < [text length] && [text characterAtIndex:i] >= '0' && [text characterAtIndex:i] <= '9') {
			fraction += scale * ([text characterAtIndex:i] - '0');
			scale /= 10;
			i++;
		}
		if (i == start) {
			return nil;
		}
	}
	NSInteger offset = 0;
	if (i < [text length]) {
		unichar sign = [text characterAtIndex:i];
		if (sign == 'Z' && i + 1 == [text length]) {
			offset = 0;
		} else if ((sign == '+' || sign == '-') && i + 6 == [text length]
		           && [text characterAtIndex:i + 3] == ':') {
			NSInteger hours = WFDigits(text, i + 1, 2), minutes = WFDigits(text, i + 4, 2);
			if (hours < 0 || hours > 18 || minutes < 0 || minutes > 59) {
				return nil;
			}
			offset = (hours * 3600 + minutes * 60) * (sign == '-' ? -1 : 1);
		} else {
			return nil;
		}
	}
	NSTimeInterval seconds = [[date startOfDay] timeIntervalSinceReferenceDate]
		+ hour * 3600 + minute * 60 + second + fraction - offset;
	return [NSDate dateWithTimeIntervalSinceReferenceDate:seconds];
}

/* P1Y2M, or P1DT2H30M5.5S, with a leading - for a negative one. A
 * duration that mixes the two kinds is none in FEEL. */
WFFeelDuration *
WFFeelParseDuration(NSString *text)
{
	BOOL negative = [text hasPrefix:@"-"];
	NSString *rest = negative ? [text substringFromIndex:1] : text;
	if (![rest hasPrefix:@"P"] || [rest length] < 3) {
		return nil;
	}
	NSScanner *scanner = [NSScanner scannerWithString:[rest substringFromIndex:1]];
	[scanner setCharactersToBeSkipped:nil];
	long long months = 0;
	double seconds = 0;
	BOOL yearMonth = NO, dayTime = NO, inTime = NO;
	NSString *order = @"YMD";
	NSUInteger position = 0;
	while (![scanner isAtEnd]) {
		if ([scanner scanString:@"T" intoString:NULL]) {
			if (inTime) {
				return nil;
			}
			inTime = YES;
			order = @"HMS";
			position = 0;
			continue;
		}
		double number = 0;
		NSUInteger before = [scanner scanLocation];
		if (![scanner scanDouble:&number] || number < 0
		    || [[[scanner string] substringWithRange:NSMakeRange(before, 1)] isEqualToString:@"+"]) {
			return nil;
		}
		NSString *unit = nil;
		if ([scanner isAtEnd]) {
			return nil;
		}
		unit = [[scanner string] substringWithRange:NSMakeRange([scanner scanLocation], 1)];
		[scanner setScanLocation:[scanner scanLocation] + 1];
		NSRange at = [order rangeOfString:unit];
		if (at.location == NSNotFound || at.location < position) {
			return nil;
		}
		position = at.location + 1;
		BOOL whole = number == floor(number);
		if (!inTime && [unit isEqualToString:@"Y"] && whole) {
			months += (long long)number * 12;
			yearMonth = YES;
		} else if (!inTime && [unit isEqualToString:@"M"] && whole) {
			months += (long long)number;
			yearMonth = YES;
		} else if (!inTime && [unit isEqualToString:@"D"] && whole) {
			seconds += number * 86400;
			dayTime = YES;
		} else if (inTime && [unit isEqualToString:@"H"]) {
			seconds += number * 3600;
			dayTime = YES;
		} else if (inTime && [unit isEqualToString:@"M"]) {
			seconds += number * 60;
			dayTime = YES;
		} else if (inTime && [unit isEqualToString:@"S"]) {
			seconds += number;
			dayTime = YES;
		} else {
			return nil;
		}
	}
	if (yearMonth == dayTime) {
		return nil;
	}
	return yearMonth ? [WFFeelDuration months:negative ? -months : months]
		: [WFFeelDuration seconds:negative ? -seconds : seconds];
}

id
WFFeelParseTemporal(NSString *text)
{
	return WFFeelParseDateTime(text) ?: WFFeelParseDate(text) ?: WFFeelParseDuration(text);
}

NSString *
WFFeelTemporalText(id value)
{
	if ([value isKindOfClass:[NSDate class]]) {
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		[formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
		[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		double seconds = [value timeIntervalSinceReferenceDate];
		BOOL fractional = seconds != floor(seconds);
		[formatter setDateFormat:fractional ? @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" : @"yyyy-MM-dd'T'HH:mm:ss'Z'"];
		return [formatter stringFromDate:value];
	}
	if ([value isKindOfClass:[WFFeelDateValue class]] || [value isKindOfClass:[WFFeelDuration class]]) {
		return [value description];
	}
	return nil;
}

BOOL
WFFeelIsTemporal(id value)
{
	return [value isKindOfClass:[NSDate class]] || [value isKindOfClass:[WFFeelDateValue class]]
		|| [value isKindOfClass:[WFFeelDuration class]];
}

#pragma mark - Order and arithmetic

BOOL
WFFeelTemporalOrder(id a, id b, NSComparisonResult *result)
{
	if ([a isKindOfClass:[WFFeelDateValue class]] && [b isKindOfClass:[WFFeelDateValue class]]) {
		*result = [[a startOfDay] compare:[b startOfDay]];
		return YES;
	}
	if ([a isKindOfClass:[WFFeelDuration class]] && [b isKindOfClass:[WFFeelDuration class]]
	    && [a yearsAndMonths] == [b yearsAndMonths]) {
		double x = [a yearsAndMonths] ? (double)[a months] : [a seconds];
		double y = [b yearsAndMonths] ? (double)[b months] : [b seconds];
		*result = x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
		return YES;
	}
	return NO;
}

static NSDate *
WFAddMonths(NSDate *date, long long months)
{
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setMonth:(NSInteger)months];
	return [WFFeelCalendar() dateByAddingComponents:components toDate:date options:0];
}

static id
WFShift(id when, WFFeelDuration *by, BOOL add)
{
	if (by.yearsAndMonths) {
		long long months = add ? by.months : -by.months;
		if ([when isKindOfClass:[NSDate class]]) {
			return WFAddMonths(when, months) ?: (id)[NSNull null];
		}
		NSDate *shifted = WFAddMonths([when startOfDay], months);
		return shifted != nil ? [WFFeelDateValue dateOf:shifted] : (id)[NSNull null];
	}
	double seconds = add ? by.seconds : -by.seconds;
	if ([when isKindOfClass:[NSDate class]]) {
		return [when dateByAddingTimeInterval:seconds];
	}
	/* A date moves by whole days. */
	return [WFFeelDateValue dateOf:[[when startOfDay] dateByAddingTimeInterval:trunc(seconds / 86400) * 86400]];
}

static BOOL
WFIsWhen(id value)
{
	return [value isKindOfClass:[NSDate class]] || [value isKindOfClass:[WFFeelDateValue class]];
}

/* The temporal cases of + - * /; nil when neither side is temporal. */
id
WFFeelTemporalArithmetic(WFFeelOperator op, id a, id b)
{
	if (!WFFeelIsTemporal(a) && !WFFeelIsTemporal(b)) {
		return nil;
	}
	BOOL durationA = [a isKindOfClass:[WFFeelDuration class]];
	BOOL durationB = [b isKindOfClass:[WFFeelDuration class]];
	switch (op) {
	case WFFeelOperatorAdd:
		if (WFIsWhen(a) && durationB) {
			return WFShift(a, b, YES);
		}
		if (durationA && WFIsWhen(b)) {
			return WFShift(b, a, YES);
		}
		/* Fall through to durations. */
	case WFFeelOperatorSubtract:
		if (op == WFFeelOperatorSubtract && WFIsWhen(a) && durationB) {
			return WFShift(a, b, NO);
		}
		if (op == WFFeelOperatorSubtract && WFIsWhen(a) && WFIsWhen(b)
		    && [a class] == [b class]) {
			NSDate *x = [a isKindOfClass:[NSDate class]] ? a : [a startOfDay];
			NSDate *y = [b isKindOfClass:[NSDate class]] ? b : [b startOfDay];
			return [WFFeelDuration seconds:[x timeIntervalSinceDate:y]] ?: (id)[NSNull null];
		}
		if (durationA && durationB && [a yearsAndMonths] == [b yearsAndMonths]) {
			int sign = op == WFFeelOperatorAdd ? 1 : -1;
			if ([a yearsAndMonths]) {
				return [WFFeelDuration months:[a months] + sign * [b months]];
			}
			return [WFFeelDuration seconds:[a seconds] + sign * [b seconds]] ?: (id)[NSNull null];
		}
		return [NSNull null];
	case WFFeelOperatorMultiply:
	case WFFeelOperatorDivide: {
		if (durationA && durationB && op == WFFeelOperatorDivide && [a yearsAndMonths] == [b yearsAndMonths]) {
			double x = [a yearsAndMonths] ? (double)[a months] : [a seconds];
			double y = [b yearsAndMonths] ? (double)[b months] : [b seconds];
			return y == 0 ? (id)[NSNull null] : WFFeelNumberResult(WFFeelDecimal([NSNumber numberWithDouble:x / y]));
		}
		WFFeelDuration *duration = durationA ? a : (durationB && op == WFFeelOperatorMultiply ? b : nil);
		id factor = duration == a ? b : a;
		if (duration == nil || !WFFeelIsNumber(factor)) {
			return [NSNull null];
		}
		double f = [factor doubleValue];
		if (op == WFFeelOperatorDivide) {
			if (f == 0) {
				return [NSNull null];
			}
			f = 1 / f;
		}
		if (duration.yearsAndMonths) {
			return [WFFeelDuration months:(long long)floor((double)duration.months * f)];
		}
		return [WFFeelDuration seconds:duration.seconds * f] ?: (id)[NSNull null];
	}
	default:
		return [NSNull null];
	}
}

id
WFFeelTemporalNegate(id value)
{
	if (![value isKindOfClass:[WFFeelDuration class]]) {
		return nil;
	}
	WFFeelDuration *duration = value;
	return duration.yearsAndMonths ? [WFFeelDuration months:-duration.months]
		: [WFFeelDuration seconds:-duration.seconds];
}

#pragma mark - Properties

static NSDecimalNumber *
WFWholeNumber(long long value)
{
	return [NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)llabs(value) exponent:0
	                                       isNegative:value < 0];
}

/* date.year, instant.hour, duration.days: the property, or nil when the
 * value has none of that name. */
id
WFFeelTemporalProperty(id value, NSString *name)
{
	if ([value isKindOfClass:[WFFeelDuration class]]) {
		WFFeelDuration *d = value;
		if (d.yearsAndMonths) {
			NSDictionary *parts = @{ @"years": WFWholeNumber(d.months / 12), @"months": WFWholeNumber(d.months % 12) };
			return [parts objectForKey:name];
		}
		long long whole = (long long)trunc(d.seconds);
		NSDictionary *parts = @{
			@"days": WFWholeNumber(whole / 86400),
			@"hours": WFWholeNumber(whole % 86400 / 3600),
			@"minutes": WFWholeNumber(whole % 3600 / 60),
			@"seconds": WFWholeNumber(whole % 60),
		};
		return [parts objectForKey:name];
	}
	if (!WFIsWhen(value)) {
		return nil;
	}
	NSDate *date = [value isKindOfClass:[NSDate class]] ? value : [value startOfDay];
	NSCalendar *calendar = WFFeelCalendar();
	/* ISO weekdays: 1 Monday to 7 Sunday. */
	NSCalendarUnit units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
		| NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitWeekday;
	NSDateComponents *c = [calendar components:units fromDate:date];
	NSMutableDictionary *parts = [NSMutableDictionary dictionaryWithDictionary:@{
		@"year": WFWholeNumber([c year]),
		@"month": WFWholeNumber([c month]),
		@"day": WFWholeNumber([c day]),
		@"weekday": WFWholeNumber(([c weekday] + 5) % 7 + 1),
	}];
	if ([value isKindOfClass:[NSDate class]]) {
		[parts addEntriesFromDictionary:@{
			@"hour": WFWholeNumber([c hour]),
			@"minute": WFWholeNumber([c minute]),
			@"second": WFWholeNumber([c second]),
		}];
	}
	return [parts objectForKey:name];
}

#pragma mark - Functions

WFFeelDateValue *
WFFeelToday(void)
{
	return [WFFeelDateValue dateOf:[NSDate date]];
}

/* What the public API hands out: an NSDate for a date (its midnight, in
 * UTC) and ISO-8601 text for a duration, in lists and contexts too. */
id
WFFeelPublicValue(id value)
{
	if ([value isKindOfClass:[WFFeelDateValue class]]) {
		return [value startOfDay];
	}
	if ([value isKindOfClass:[WFFeelDuration class]]) {
		return [value description];
	}
	if ([value isKindOfClass:[WFFeelRange class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		NSMutableArray *items = [NSMutableArray array];
		for (id item in value) {
			[items addObject:WFFeelPublicValue(item)];
		}
		return items;
	}
	if ([value isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *entries = [NSMutableDictionary dictionary];
		for (id key in value) {
			[entries setObject:WFFeelPublicValue([value objectForKey:key]) forKey:key];
		}
		return entries;
	}
	return value;
}

/*
 * FEEL's built-in functions (DMN 1.3, section 10.3.4) the engine
 * implements: conversion, strings, lists and numbers. Arguments are
 * positional. A call with the wrong number or kinds of arguments is null,
 * as FEEL has it.
 */
#import "WFFeelInternal.h"
#include <math.h>

typedef id (^WFFeelFunction)(NSArray *arguments);

static id
WFNull(void)
{
	return [NSNull null];
}

static NSDecimalNumber *
WFWhole(long long value)
{
	return [NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)llabs(value)
	                                         exponent:0
	                                       isNegative:value < 0];
}

/* The argument as a whole number, if it is one. */
static BOOL
WFInteger(id value, long long *result)
{
	if (!WFFeelIsNumber(value)) {
		return NO;
	}
	NSDecimalNumber *decimal = WFFeelDecimal(value);
	NSDecimal exact = [decimal decimalValue], rounded;
	NSDecimalRound(&rounded, &exact, 0, NSRoundPlain);
	if (NSDecimalCompare(&exact, &rounded) != NSOrderedSame) {
		return NO;
	}
	*result = [decimal longLongValue];
	return YES;
}

static id
WFRounded(id value, NSInteger scale, NSRoundingMode mode)
{
	if (!WFFeelIsNumber(value)) {
		return WFNull();
	}
	NSDecimal exact = [WFFeelDecimal(value) decimalValue], rounded;
	NSDecimalRound(&rounded, &exact, scale, mode);
	return WFFeelNumberResult([NSDecimalNumber decimalNumberWithDecimal:rounded]);
}

/* The list a function over a list takes: one list argument, or the
 * arguments themselves (min(1, 2, 3)). */
static NSArray *
WFListArgument(NSArray *arguments)
{
	if ([arguments count] == 1 && [[arguments objectAtIndex:0] isKindOfClass:[NSArray class]]) {
		return [arguments objectAtIndex:0];
	}
	return [arguments count] > 0 ? arguments : nil;
}

static id
WFExtreme(NSArray *arguments, WFFeelOperator op)
{
	NSArray *items = WFListArgument(arguments);
	if ([items count] == 0) {
		return WFNull();
	}
	id best = [items objectAtIndex:0];
	for (id item in items) {
		id better = WFFeelCompareValues(op, item, best);
		if (!WFFeelIsBoolean(better)) {
			return WFNull();
		}
		if ([better boolValue]) {
			best = item;
		}
	}
	return best;
}

static id
WFSum(NSArray *items)
{
	id total = [NSDecimalNumber zero];
	for (id item in items) {
		if (!WFFeelIsNumber(item)) {
			return WFNull();
		}
		total = WFFeelArithmetic(WFFeelOperatorAdd, total, item);
	}
	return total;
}

static BOOL
WFStrings(NSArray *arguments, NSUInteger count)
{
	if ([arguments count] != count) {
		return NO;
	}
	for (id argument in arguments) {
		if (![argument isKindOfClass:[NSString class]]) {
			return NO;
		}
	}
	return YES;
}

static NSString *
WFStringOf(id value)
{
	if (WFFeelIsNull(value)) {
		return nil;
	}
	if ([value isKindOfClass:[NSString class]]) {
		return value;
	}
	return WFFeelTemporalText(value) ?: WFFeelLiteralText(value);
}

/* A date, a date and time, or its text: the day it falls on. */
static WFFeelDateValue *
WFDateOf(id value)
{
	if ([value isKindOfClass:[WFFeelDateValue class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSDate class]]) {
		return [WFFeelDateValue dateOf:value];
	}
	if ([value isKindOfClass:[NSString class]]) {
		NSDate *instant = WFFeelParseDateTime(value);
		return instant != nil ? [WFFeelDateValue dateOf:instant] : WFFeelParseDate(value);
	}
	return nil;
}

static NSDateComponents *
WFComponents(NSCalendarUnit units, WFFeelDateValue *date)
{
	NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	[calendar setFirstWeekday:2];
	[calendar setMinimumDaysInFirstWeek:4];
	return [calendar components:units fromDate:[date startOfDay]];
}

/* Depth first, keeping the order. */
static void
WFFlattenInto(NSMutableArray *flat, NSArray *list)
{
	for (id item in list) {
		if ([item isKindOfClass:[NSArray class]]) {
			WFFlattenInto(flat, item);
		} else {
			[flat addObject:item];
		}
	}
}

static NSDictionary<NSString *, WFFeelFunction> *
WFFeelFunctions(void)
{
	static NSDictionary *functions = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableDictionary *f = [NSMutableDictionary dictionary];

		/* Conversion and logic. */
		f[@"not"] = ^id(NSArray *a) {
			if ([a count] != 1 || !WFFeelIsBoolean([a objectAtIndex:0])) {
				return WFNull();
			}
			return [NSNumber numberWithBool:![[a objectAtIndex:0] boolValue]];
		};
		f[@"string"] = ^id(NSArray *a) {
			return [a count] == 1 ? (WFStringOf([a objectAtIndex:0]) ?: WFNull()) : WFNull();
		};
		f[@"number"] = ^id(NSArray *a) {
			if ([a count] != 1) {
				return WFNull();
			}
			id value = [a objectAtIndex:0];
			if (WFFeelIsNumber(value)) {
				return value;
			}
			if (![value isKindOfClass:[NSString class]]) {
				return WFNull();
			}
			NSString *text = [value stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]];
			NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
			NSUInteger i = [text hasPrefix:@"-"] ? 1 : 0, digitCount = 0, dots = 0;
			for (; i < [text length]; i++) {
				unichar c = [text characterAtIndex:i];
				if (c == '.') {
					dots += 1;
				} else if ([digits characterIsMember:c]) {
					digitCount += 1;
				} else {
					return WFNull();
				}
			}
			if (digitCount == 0 || dots > 1) {
				return WFNull();
			}
			return [NSDecimalNumber decimalNumberWithString:text locale:@{ NSDecimalSeparator: @"." }];
		};

		/* Strings. */
		f[@"string length"] = ^id(NSArray *a) {
			return WFStrings(a, 1) ? WFWhole((long long)[[a objectAtIndex:0] length]) : WFNull();
		};
		f[@"upper case"] = ^id(NSArray *a) {
			return WFStrings(a, 1) ? [[a objectAtIndex:0] uppercaseString] : WFNull();
		};
		f[@"lower case"] = ^id(NSArray *a) {
			return WFStrings(a, 1) ? [[a objectAtIndex:0] lowercaseString] : WFNull();
		};
		f[@"substring"] = ^id(NSArray *a) {
			long long start = 0, length = 0;
			if (([a count] != 2 && [a count] != 3) || ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
			    || !WFInteger([a objectAtIndex:1], &start)
			    || ([a count] == 3 && (!WFInteger([a objectAtIndex:2], &length) || length < 0))) {
				return WFNull();
			}
			NSString *s = [a objectAtIndex:0];
			long long count = (long long)[s length];
			/* 1 is the first character, -1 the last. */
			long long from = start > 0 ? start - 1 : count + start;
			if (start == 0 || from < 0 || from > count) {
				return WFNull();
			}
			long long to = [a count] == 3 ? MIN(from + length, count) : count;
			return [s substringWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(to - from))];
		};
		f[@"substring before"] = ^id(NSArray *a) {
			if (!WFStrings(a, 2)) {
				return WFNull();
			}
			NSRange r = [[a objectAtIndex:0] rangeOfString:[a objectAtIndex:1]];
			return r.location == NSNotFound ? @"" : [[a objectAtIndex:0] substringToIndex:r.location];
		};
		f[@"substring after"] = ^id(NSArray *a) {
			if (!WFStrings(a, 2)) {
				return WFNull();
			}
			NSRange r = [[a objectAtIndex:0] rangeOfString:[a objectAtIndex:1]];
			if ([[a objectAtIndex:1] length] == 0) {
				return [a objectAtIndex:0];
			}
			return r.location == NSNotFound ? @"" : [[a objectAtIndex:0] substringFromIndex:NSMaxRange(r)];
		};
		f[@"contains"] = ^id(NSArray *a) {
			if (!WFStrings(a, 2)) {
				return WFNull();
			}
			BOOL found = [[a objectAtIndex:1] length] == 0
				|| [[a objectAtIndex:0] rangeOfString:[a objectAtIndex:1]].location != NSNotFound;
			return [NSNumber numberWithBool:found];
		};
		f[@"starts with"] = ^id(NSArray *a) {
			return WFStrings(a, 2) ? [NSNumber numberWithBool:
				[[a objectAtIndex:0] hasPrefix:[a objectAtIndex:1]] || [[a objectAtIndex:1] length] == 0]
				: WFNull();
		};
		f[@"ends with"] = ^id(NSArray *a) {
			return WFStrings(a, 2) ? [NSNumber numberWithBool:
				[[a objectAtIndex:0] hasSuffix:[a objectAtIndex:1]] || [[a objectAtIndex:1] length] == 0]
				: WFNull();
		};
		f[@"string join"] = ^id(NSArray *a) {
			if (([a count] != 1 && [a count] != 2) || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]
			    || ([a count] == 2 && ![[a objectAtIndex:1] isKindOfClass:[NSString class]])) {
				return WFNull();
			}
			NSMutableArray *parts = [NSMutableArray array];
			for (id item in [a objectAtIndex:0]) {
				if (WFFeelIsNull(item)) {
					continue;
				}
				if (![item isKindOfClass:[NSString class]]) {
					return WFNull();
				}
				[parts addObject:item];
			}
			return [parts componentsJoinedByString:[a count] == 2 ? [a objectAtIndex:1] : @""];
		};

		/* Lists. */
		f[@"count"] = ^id(NSArray *a) {
			return [a count] == 1 && [[a objectAtIndex:0] isKindOfClass:[NSArray class]]
				? WFWhole((long long)[[a objectAtIndex:0] count]) : WFNull();
		};
		f[@"min"] = ^id(NSArray *a) {
			return WFExtreme(a, WFFeelOperatorLess);
		};
		f[@"max"] = ^id(NSArray *a) {
			return WFExtreme(a, WFFeelOperatorGreater);
		};
		f[@"sum"] = ^id(NSArray *a) {
			NSArray *items = WFListArgument(a);
			return items != nil ? WFSum(items) : WFNull();
		};
		f[@"mean"] = ^id(NSArray *a) {
			NSArray *items = WFListArgument(a);
			if ([items count] == 0) {
				return WFNull();
			}
			return WFFeelArithmetic(WFFeelOperatorDivide, WFSum(items), WFWhole((long long)[items count]));
		};
		f[@"product"] = ^id(NSArray *a) {
			NSArray *items = WFListArgument(a);
			if ([items count] == 0) {
				return WFNull();
			}
			id total = [NSDecimalNumber one];
			for (id item in items) {
				total = WFFeelArithmetic(WFFeelOperatorMultiply, total, item);
			}
			return total;
		};
		/* all and any: FEEL's and and or over a list. */
		f[@"all"] = ^id(NSArray *a) {
			NSArray *items = WFListArgument(a);
			if (items == nil) {
				return WFNull();
			}
			BOOL unknown = NO;
			for (id item in items) {
				if (WFFeelIsBoolean(item) && ![item boolValue]) {
					return [NSNumber numberWithBool:NO];
				}
				unknown = unknown || !WFFeelIsBoolean(item);
			}
			return unknown ? WFNull() : [NSNumber numberWithBool:YES];
		};
		f[@"any"] = ^id(NSArray *a) {
			NSArray *items = WFListArgument(a);
			if (items == nil) {
				return WFNull();
			}
			BOOL unknown = NO;
			for (id item in items) {
				if (WFFeelIsBoolean(item) && [item boolValue]) {
					return [NSNumber numberWithBool:YES];
				}
				unknown = unknown || !WFFeelIsBoolean(item);
			}
			return unknown ? WFNull() : [NSNumber numberWithBool:NO];
		};
		f[@"sublist"] = ^id(NSArray *a) {
			long long start = 0, length = 0;
			if (([a count] != 2 && [a count] != 3) || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]
			    || !WFInteger([a objectAtIndex:1], &start)
			    || ([a count] == 3 && (!WFInteger([a objectAtIndex:2], &length) || length < 0))) {
				return WFNull();
			}
			NSArray *list = [a objectAtIndex:0];
			long long count = (long long)[list count];
			long long from = start > 0 ? start - 1 : count + start;
			if (start == 0 || from < 0 || from > count) {
				return WFNull();
			}
			long long to = [a count] == 3 ? MIN(from + length, count) : count;
			return [list subarrayWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(to - from))];
		};
		f[@"append"] = ^id(NSArray *a) {
			if ([a count] < 1 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return WFNull();
			}
			return [[a objectAtIndex:0] arrayByAddingObjectsFromArray:
				[a subarrayWithRange:NSMakeRange(1, [a count] - 1)]];
		};
		f[@"concatenate"] = ^id(NSArray *a) {
			NSMutableArray *all = [NSMutableArray array];
			for (id list in a) {
				if (![list isKindOfClass:[NSArray class]]) {
					return WFNull();
				}
				[all addObjectsFromArray:list];
			}
			return all;
		};
		f[@"list contains"] = ^id(NSArray *a) {
			if ([a count] != 2 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return WFNull();
			}
			for (id item in [a objectAtIndex:0]) {
				if ([WFFeelValuesEqual(item, [a objectAtIndex:1]) isEqual:@YES]) {
					return [NSNumber numberWithBool:YES];
				}
			}
			return [NSNumber numberWithBool:NO];
		};
		f[@"index of"] = ^id(NSArray *a) {
			if ([a count] != 2 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return WFNull();
			}
			NSMutableArray *positions = [NSMutableArray array];
			NSArray *list = [a objectAtIndex:0];
			for (NSUInteger i = 0; i < [list count]; i++) {
				if ([WFFeelValuesEqual([list objectAtIndex:i], [a objectAtIndex:1]) isEqual:@YES]) {
					[positions addObject:WFWhole((long long)i + 1)];
				}
			}
			return positions;
		};
		f[@"reverse"] = ^id(NSArray *a) {
			return [a count] == 1 && [[a objectAtIndex:0] isKindOfClass:[NSArray class]]
				? [[[a objectAtIndex:0] reverseObjectEnumerator] allObjects] : WFNull();
		};
		f[@"distinct values"] = ^id(NSArray *a) {
			if ([a count] != 1 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return WFNull();
			}
			NSMutableArray *distinct = [NSMutableArray array];
			for (id item in [a objectAtIndex:0]) {
				BOOL seen = NO;
				for (id other in distinct) {
					seen = seen || [WFFeelValuesEqual(item, other) isEqual:@YES];
				}
				if (!seen) {
					[distinct addObject:item];
				}
			}
			return distinct;
		};
		f[@"flatten"] = ^id(NSArray *a) {
			if ([a count] != 1 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return WFNull();
			}
			NSMutableArray *flat = [NSMutableArray array];
			WFFlattenInto(flat, [a objectAtIndex:0]);
			return flat;
		};

		/* Numbers. */
		f[@"decimal"] = ^id(NSArray *a) {
			long long scale = 0;
			if ([a count] != 2 || !WFInteger([a objectAtIndex:1], &scale) || scale < -6111 || scale > 6176) {
				return WFNull();
			}
			return WFRounded([a objectAtIndex:0], (NSInteger)scale, NSRoundBankers);
		};
		f[@"floor"] = ^id(NSArray *a) {
			return [a count] == 1 ? WFRounded([a objectAtIndex:0], 0, NSRoundDown) : WFNull();
		};
		f[@"ceiling"] = ^id(NSArray *a) {
			return [a count] == 1 ? WFRounded([a objectAtIndex:0], 0, NSRoundUp) : WFNull();
		};
		f[@"abs"] = ^id(NSArray *a) {
			if ([a count] != 1 || !WFFeelIsNumber([a objectAtIndex:0])) {
				return WFNull();
			}
			NSDecimalNumber *value = WFFeelDecimal([a objectAtIndex:0]);
			return [value compare:[NSDecimalNumber zero]] == NSOrderedAscending
				? WFFeelArithmetic(WFFeelOperatorSubtract, [NSDecimalNumber zero], value) : value;
		};
		f[@"modulo"] = ^id(NSArray *a) {
			return [a count] == 2 ? WFFeelArithmetic(WFFeelOperatorModulo, [a objectAtIndex:0],
				[a objectAtIndex:1]) : WFNull();
		};
		f[@"odd"] = ^id(NSArray *a) {
			long long value = 0;
			return [a count] == 1 && WFInteger([a objectAtIndex:0], &value)
				? [NSNumber numberWithBool:llabs(value) % 2 == 1] : WFNull();
		};
		f[@"even"] = ^id(NSArray *a) {
			long long value = 0;
			return [a count] == 1 && WFInteger([a objectAtIndex:0], &value)
				? [NSNumber numberWithBool:value % 2 == 0] : WFNull();
		};

		/* Time. */
		f[@"now"] = ^id(NSArray *a) {
			return [a count] == 0 ? [NSDate date] : WFNull();
		};
		f[@"today"] = ^id(NSArray *a) {
			return [a count] == 0 ? WFFeelToday() : WFNull();
		};
		f[@"date"] = ^id(NSArray *a) {
			if ([a count] == 1) {
				return WFDateOf([a objectAtIndex:0]) ?: WFNull();
			}
			long long y = 0, m = 0, d = 0;
			if ([a count] == 3 && WFInteger([a objectAtIndex:0], &y) && WFInteger([a objectAtIndex:1], &m)
			    && WFInteger([a objectAtIndex:2], &d)) {
				return [WFFeelDateValue year:(NSInteger)y month:(NSInteger)m day:(NSInteger)d] ?: WFNull();
			}
			return WFNull();
		};
		f[@"date and time"] = ^id(NSArray *a) {
			if ([a count] != 1) {
				return WFNull();
			}
			id value = [a objectAtIndex:0];
			if ([value isKindOfClass:[NSDate class]]) {
				return value;
			}
			if ([value isKindOfClass:[WFFeelDateValue class]]) {
				return [value startOfDay];
			}
			return [value isKindOfClass:[NSString class]] ? (WFFeelParseDateTime(value) ?: WFNull()) : WFNull();
		};
		f[@"duration"] = ^id(NSArray *a) {
			return WFStrings(a, 1) ? (WFFeelParseDuration([a objectAtIndex:0]) ?: WFNull()) : WFNull();
		};
		f[@"years and months duration"] = ^id(NSArray *a) {
			WFFeelDateValue *from = [a count] == 2 ? WFDateOf([a objectAtIndex:0]) : nil;
			WFFeelDateValue *to = [a count] == 2 ? WFDateOf([a objectAtIndex:1]) : nil;
			if (from == nil || to == nil || [[a objectAtIndex:0] isKindOfClass:[NSString class]]
			    || [[a objectAtIndex:1] isKindOfClass:[NSString class]]) {
				return WFNull();
			}
			NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
			[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
			NSDateComponents *between = [calendar components:NSCalendarUnitMonth
			                                         fromDate:[from startOfDay]
			                                           toDate:[to startOfDay]
			                                          options:0];
			return [WFFeelDuration months:[between month]];
		};
		f[@"day of week"] = ^id(NSArray *a) {
			WFFeelDateValue *date = [a count] == 1 && ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
				? WFDateOf([a objectAtIndex:0]) : nil;
			if (date == nil) {
				return WFNull();
			}
			NSArray *names = @[ @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday",
				@"Saturday" ];
			return [names objectAtIndex:(NSUInteger)[WFComponents(NSCalendarUnitWeekday, date) weekday] - 1];
		};
		f[@"month of year"] = ^id(NSArray *a) {
			WFFeelDateValue *date = [a count] == 1 && ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
				? WFDateOf([a objectAtIndex:0]) : nil;
			if (date == nil) {
				return WFNull();
			}
			NSArray *names = @[ @"January", @"February", @"March", @"April", @"May", @"June", @"July",
				@"August", @"September", @"October", @"November", @"December" ];
			return [names objectAtIndex:(NSUInteger)date.month - 1];
		};
		f[@"day of year"] = ^id(NSArray *a) {
			WFFeelDateValue *date = [a count] == 1 && ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
				? WFDateOf([a objectAtIndex:0]) : nil;
			if (date == nil) {
				return WFNull();
			}
			WFFeelDateValue *first = [WFFeelDateValue year:date.year month:1 day:1];
			return WFWhole((long long)round([[date startOfDay] timeIntervalSinceDate:[first startOfDay]] / 86400) + 1);
		};
		f[@"week of year"] = ^id(NSArray *a) {
			WFFeelDateValue *date = [a count] == 1 && ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
				? WFDateOf([a objectAtIndex:0]) : nil;
			/* ISO 8601: weeks start on Monday; week 1 holds the year's
			 * first Thursday. */
			return date != nil ? WFWhole([WFComponents(NSCalendarUnitWeekOfYear, date) weekOfYear]) : WFNull();
		};

		functions = [f copy];
	});
	return functions;
}

BOOL
WFFeelIsBuiltin(NSString *name)
{
	return [WFFeelFunctions() objectForKey:name] != nil;
}

NSArray<NSString *> *
WFFeelMultiWordBuiltins(void)
{
	static NSArray *names = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableArray *multi = [NSMutableArray array];
		for (NSString *name in WFFeelFunctions()) {
			if ([name rangeOfString:@" "].location != NSNotFound) {
				[multi addObject:name];
			}
		}
		/* Longest first, so substring before is not taken for a substring
		 * call. */
		names = [multi sortedArrayUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
			NSUInteger wx = [[x componentsSeparatedByString:@" "] count];
			NSUInteger wy = [[y componentsSeparatedByString:@" "] count];
			return wx > wy ? NSOrderedAscending : wx < wy ? NSOrderedDescending : [x compare:y];
		}];
	});
	return names;
}

id
WFFeelCall(NSString *name, NSArray *arguments)
{
	WFFeelFunction function = [WFFeelFunctions() objectForKey:name];
	return function != nil ? (function(arguments) ?: WFNull()) : WFNull();
}

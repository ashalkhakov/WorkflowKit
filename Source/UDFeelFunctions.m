/*
 * FEEL's built-in functions (DMN 1.3, section 10.3.4) the engine
 * implements: conversion, strings, lists and numbers. Arguments are
 * positional. A call with the wrong number or kinds of arguments is null,
 * as FEEL has it.
 */
#import "UDFeelInternal.h"
#include <math.h>

typedef id (^UDFeelFunction)(NSArray *arguments);

static id
UDNull(void)
{
	return [NSNull null];
}

static NSDecimalNumber *
UDWhole(long long value)
{
	return [NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)llabs(value)
	                                         exponent:0
	                                       isNegative:value < 0];
}

/* The argument as a whole number, if it is one. */
static BOOL
UDInteger(id value, long long *result)
{
	if (!UDFeelIsNumber(value)) {
		return NO;
	}
	NSDecimalNumber *decimal = UDFeelDecimal(value);
	NSDecimal exact = [decimal decimalValue], rounded;
	NSDecimalRound(&rounded, &exact, 0, NSRoundPlain);
	if (NSDecimalCompare(&exact, &rounded) != NSOrderedSame) {
		return NO;
	}
	*result = [decimal longLongValue];
	return YES;
}

static id
UDRounded(id value, NSInteger scale, NSRoundingMode mode)
{
	if (!UDFeelIsNumber(value)) {
		return UDNull();
	}
	NSDecimal exact = [UDFeelDecimal(value) decimalValue], rounded;
	NSDecimalRound(&rounded, &exact, scale, mode);
	return UDFeelNumberResult([NSDecimalNumber decimalNumberWithDecimal:rounded]);
}

/* The list a function over a list takes: one list argument, or the
 * arguments themselves (min(1, 2, 3)). */
static NSArray *
UDListArgument(NSArray *arguments)
{
	if ([arguments count] == 1 && [[arguments objectAtIndex:0] isKindOfClass:[NSArray class]]) {
		return [arguments objectAtIndex:0];
	}
	return [arguments count] > 0 ? arguments : nil;
}

static id
UDExtreme(NSArray *arguments, UDFeelOperator op)
{
	NSArray *items = UDListArgument(arguments);
	if ([items count] == 0) {
		return UDNull();
	}
	id best = [items objectAtIndex:0];
	for (id item in items) {
		id better = UDFeelCompareValues(op, item, best);
		if (!UDFeelIsBoolean(better)) {
			return UDNull();
		}
		if ([better boolValue]) {
			best = item;
		}
	}
	return best;
}

static id
UDSum(NSArray *items)
{
	id total = [NSDecimalNumber zero];
	for (id item in items) {
		if (!UDFeelIsNumber(item)) {
			return UDNull();
		}
		total = UDFeelArithmetic(UDFeelOperatorAdd, total, item);
	}
	return total;
}

static BOOL
UDStrings(NSArray *arguments, NSUInteger count)
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
UDStringOf(id value)
{
	if (UDFeelIsNull(value)) {
		return nil;
	}
	if ([value isKindOfClass:[NSString class]]) {
		return value;
	}
	return UDFeelTemporalText(value) ?: UDFeelLiteralText(value);
}

/* A date, a date and time, or its text: the day it falls on. */
static UDFeelDateValue *
UDDateOf(id value)
{
	if ([value isKindOfClass:[UDFeelDateValue class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSDate class]]) {
		return [UDFeelDateValue dateOf:value];
	}
	if ([value isKindOfClass:[NSString class]]) {
		NSDate *instant = UDFeelParseDateTime(value);
		return instant != nil ? [UDFeelDateValue dateOf:instant] : UDFeelParseDate(value);
	}
	return nil;
}

static NSDateComponents *
UDComponents(NSCalendarUnit units, UDFeelDateValue *date)
{
	NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	[calendar setFirstWeekday:2];
	[calendar setMinimumDaysInFirstWeek:4];
	return [calendar components:units fromDate:[date startOfDay]];
}

/* Depth first, keeping the order. */
static void
UDFlattenInto(NSMutableArray *flat, NSArray *list)
{
	for (id item in list) {
		if ([item isKindOfClass:[NSArray class]]) {
			UDFlattenInto(flat, item);
		} else {
			[flat addObject:item];
		}
	}
}

static NSDictionary<NSString *, UDFeelFunction> *
UDFeelFunctions(void)
{
	static NSDictionary *functions = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableDictionary *f = [NSMutableDictionary dictionary];

		/* Conversion and logic. */
		f[@"not"] = ^id(NSArray *a) {
			if ([a count] != 1 || !UDFeelIsBoolean([a objectAtIndex:0])) {
				return UDNull();
			}
			return [NSNumber numberWithBool:![[a objectAtIndex:0] boolValue]];
		};
		f[@"string"] = ^id(NSArray *a) {
			return [a count] == 1 ? (UDStringOf([a objectAtIndex:0]) ?: UDNull()) : UDNull();
		};
		f[@"number"] = ^id(NSArray *a) {
			if ([a count] != 1) {
				return UDNull();
			}
			id value = [a objectAtIndex:0];
			if (UDFeelIsNumber(value)) {
				return value;
			}
			if (![value isKindOfClass:[NSString class]]) {
				return UDNull();
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
					return UDNull();
				}
			}
			if (digitCount == 0 || dots > 1) {
				return UDNull();
			}
			return [NSDecimalNumber decimalNumberWithString:text locale:@{ NSDecimalSeparator: @"." }];
		};

		/* Strings. */
		f[@"string length"] = ^id(NSArray *a) {
			return UDStrings(a, 1) ? UDWhole((long long)[[a objectAtIndex:0] length]) : UDNull();
		};
		f[@"upper case"] = ^id(NSArray *a) {
			return UDStrings(a, 1) ? [[a objectAtIndex:0] uppercaseString] : UDNull();
		};
		f[@"lower case"] = ^id(NSArray *a) {
			return UDStrings(a, 1) ? [[a objectAtIndex:0] lowercaseString] : UDNull();
		};
		f[@"substring"] = ^id(NSArray *a) {
			long long start = 0, length = 0;
			if (([a count] != 2 && [a count] != 3) || ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
			    || !UDInteger([a objectAtIndex:1], &start)
			    || ([a count] == 3 && (!UDInteger([a objectAtIndex:2], &length) || length < 0))) {
				return UDNull();
			}
			NSString *s = [a objectAtIndex:0];
			long long count = (long long)[s length];
			/* 1 is the first character, -1 the last. */
			long long from = start > 0 ? start - 1 : count + start;
			if (start == 0 || from < 0 || from > count) {
				return UDNull();
			}
			long long to = [a count] == 3 ? MIN(from + length, count) : count;
			return [s substringWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(to - from))];
		};
		f[@"substring before"] = ^id(NSArray *a) {
			if (!UDStrings(a, 2)) {
				return UDNull();
			}
			NSRange r = [[a objectAtIndex:0] rangeOfString:[a objectAtIndex:1]];
			return r.location == NSNotFound ? @"" : [[a objectAtIndex:0] substringToIndex:r.location];
		};
		f[@"substring after"] = ^id(NSArray *a) {
			if (!UDStrings(a, 2)) {
				return UDNull();
			}
			NSRange r = [[a objectAtIndex:0] rangeOfString:[a objectAtIndex:1]];
			if ([[a objectAtIndex:1] length] == 0) {
				return [a objectAtIndex:0];
			}
			return r.location == NSNotFound ? @"" : [[a objectAtIndex:0] substringFromIndex:NSMaxRange(r)];
		};
		f[@"contains"] = ^id(NSArray *a) {
			if (!UDStrings(a, 2)) {
				return UDNull();
			}
			BOOL found = [[a objectAtIndex:1] length] == 0
				|| [[a objectAtIndex:0] rangeOfString:[a objectAtIndex:1]].location != NSNotFound;
			return [NSNumber numberWithBool:found];
		};
		f[@"starts with"] = ^id(NSArray *a) {
			return UDStrings(a, 2) ? [NSNumber numberWithBool:
				[[a objectAtIndex:0] hasPrefix:[a objectAtIndex:1]] || [[a objectAtIndex:1] length] == 0]
				: UDNull();
		};
		f[@"ends with"] = ^id(NSArray *a) {
			return UDStrings(a, 2) ? [NSNumber numberWithBool:
				[[a objectAtIndex:0] hasSuffix:[a objectAtIndex:1]] || [[a objectAtIndex:1] length] == 0]
				: UDNull();
		};
		f[@"string join"] = ^id(NSArray *a) {
			if (([a count] != 1 && [a count] != 2) || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]
			    || ([a count] == 2 && ![[a objectAtIndex:1] isKindOfClass:[NSString class]])) {
				return UDNull();
			}
			NSMutableArray *parts = [NSMutableArray array];
			for (id item in [a objectAtIndex:0]) {
				if (UDFeelIsNull(item)) {
					continue;
				}
				if (![item isKindOfClass:[NSString class]]) {
					return UDNull();
				}
				[parts addObject:item];
			}
			return [parts componentsJoinedByString:[a count] == 2 ? [a objectAtIndex:1] : @""];
		};

		/* Lists. */
		f[@"count"] = ^id(NSArray *a) {
			return [a count] == 1 && [[a objectAtIndex:0] isKindOfClass:[NSArray class]]
				? UDWhole((long long)[[a objectAtIndex:0] count]) : UDNull();
		};
		f[@"min"] = ^id(NSArray *a) {
			return UDExtreme(a, UDFeelOperatorLess);
		};
		f[@"max"] = ^id(NSArray *a) {
			return UDExtreme(a, UDFeelOperatorGreater);
		};
		f[@"sum"] = ^id(NSArray *a) {
			NSArray *items = UDListArgument(a);
			return items != nil ? UDSum(items) : UDNull();
		};
		f[@"mean"] = ^id(NSArray *a) {
			NSArray *items = UDListArgument(a);
			if ([items count] == 0) {
				return UDNull();
			}
			return UDFeelArithmetic(UDFeelOperatorDivide, UDSum(items), UDWhole((long long)[items count]));
		};
		f[@"product"] = ^id(NSArray *a) {
			NSArray *items = UDListArgument(a);
			if ([items count] == 0) {
				return UDNull();
			}
			id total = [NSDecimalNumber one];
			for (id item in items) {
				total = UDFeelArithmetic(UDFeelOperatorMultiply, total, item);
			}
			return total;
		};
		/* all and any: FEEL's and and or over a list. */
		f[@"all"] = ^id(NSArray *a) {
			NSArray *items = UDListArgument(a);
			if (items == nil) {
				return UDNull();
			}
			BOOL unknown = NO;
			for (id item in items) {
				if (UDFeelIsBoolean(item) && ![item boolValue]) {
					return [NSNumber numberWithBool:NO];
				}
				unknown = unknown || !UDFeelIsBoolean(item);
			}
			return unknown ? UDNull() : [NSNumber numberWithBool:YES];
		};
		f[@"any"] = ^id(NSArray *a) {
			NSArray *items = UDListArgument(a);
			if (items == nil) {
				return UDNull();
			}
			BOOL unknown = NO;
			for (id item in items) {
				if (UDFeelIsBoolean(item) && [item boolValue]) {
					return [NSNumber numberWithBool:YES];
				}
				unknown = unknown || !UDFeelIsBoolean(item);
			}
			return unknown ? UDNull() : [NSNumber numberWithBool:NO];
		};
		f[@"sublist"] = ^id(NSArray *a) {
			long long start = 0, length = 0;
			if (([a count] != 2 && [a count] != 3) || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]
			    || !UDInteger([a objectAtIndex:1], &start)
			    || ([a count] == 3 && (!UDInteger([a objectAtIndex:2], &length) || length < 0))) {
				return UDNull();
			}
			NSArray *list = [a objectAtIndex:0];
			long long count = (long long)[list count];
			long long from = start > 0 ? start - 1 : count + start;
			if (start == 0 || from < 0 || from > count) {
				return UDNull();
			}
			long long to = [a count] == 3 ? MIN(from + length, count) : count;
			return [list subarrayWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(to - from))];
		};
		f[@"append"] = ^id(NSArray *a) {
			if ([a count] < 1 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return UDNull();
			}
			return [[a objectAtIndex:0] arrayByAddingObjectsFromArray:
				[a subarrayWithRange:NSMakeRange(1, [a count] - 1)]];
		};
		f[@"concatenate"] = ^id(NSArray *a) {
			NSMutableArray *all = [NSMutableArray array];
			for (id list in a) {
				if (![list isKindOfClass:[NSArray class]]) {
					return UDNull();
				}
				[all addObjectsFromArray:list];
			}
			return all;
		};
		f[@"list contains"] = ^id(NSArray *a) {
			if ([a count] != 2 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return UDNull();
			}
			for (id item in [a objectAtIndex:0]) {
				if ([UDFeelValuesEqual(item, [a objectAtIndex:1]) isEqual:@YES]) {
					return [NSNumber numberWithBool:YES];
				}
			}
			return [NSNumber numberWithBool:NO];
		};
		f[@"index of"] = ^id(NSArray *a) {
			if ([a count] != 2 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return UDNull();
			}
			NSMutableArray *positions = [NSMutableArray array];
			NSArray *list = [a objectAtIndex:0];
			for (NSUInteger i = 0; i < [list count]; i++) {
				if ([UDFeelValuesEqual([list objectAtIndex:i], [a objectAtIndex:1]) isEqual:@YES]) {
					[positions addObject:UDWhole((long long)i + 1)];
				}
			}
			return positions;
		};
		f[@"reverse"] = ^id(NSArray *a) {
			return [a count] == 1 && [[a objectAtIndex:0] isKindOfClass:[NSArray class]]
				? [[[a objectAtIndex:0] reverseObjectEnumerator] allObjects] : UDNull();
		};
		f[@"distinct values"] = ^id(NSArray *a) {
			if ([a count] != 1 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return UDNull();
			}
			NSMutableArray *distinct = [NSMutableArray array];
			for (id item in [a objectAtIndex:0]) {
				BOOL seen = NO;
				for (id other in distinct) {
					seen = seen || [UDFeelValuesEqual(item, other) isEqual:@YES];
				}
				if (!seen) {
					[distinct addObject:item];
				}
			}
			return distinct;
		};
		f[@"flatten"] = ^id(NSArray *a) {
			if ([a count] != 1 || ![[a objectAtIndex:0] isKindOfClass:[NSArray class]]) {
				return UDNull();
			}
			NSMutableArray *flat = [NSMutableArray array];
			UDFlattenInto(flat, [a objectAtIndex:0]);
			return flat;
		};

		/* Numbers. */
		f[@"decimal"] = ^id(NSArray *a) {
			long long scale = 0;
			if ([a count] != 2 || !UDInteger([a objectAtIndex:1], &scale) || scale < -6111 || scale > 6176) {
				return UDNull();
			}
			return UDRounded([a objectAtIndex:0], (NSInteger)scale, NSRoundBankers);
		};
		f[@"floor"] = ^id(NSArray *a) {
			return [a count] == 1 ? UDRounded([a objectAtIndex:0], 0, NSRoundDown) : UDNull();
		};
		f[@"ceiling"] = ^id(NSArray *a) {
			return [a count] == 1 ? UDRounded([a objectAtIndex:0], 0, NSRoundUp) : UDNull();
		};
		f[@"abs"] = ^id(NSArray *a) {
			if ([a count] != 1 || !UDFeelIsNumber([a objectAtIndex:0])) {
				return UDNull();
			}
			NSDecimalNumber *value = UDFeelDecimal([a objectAtIndex:0]);
			return [value compare:[NSDecimalNumber zero]] == NSOrderedAscending
				? UDFeelArithmetic(UDFeelOperatorSubtract, [NSDecimalNumber zero], value) : value;
		};
		f[@"modulo"] = ^id(NSArray *a) {
			return [a count] == 2 ? UDFeelArithmetic(UDFeelOperatorModulo, [a objectAtIndex:0],
				[a objectAtIndex:1]) : UDNull();
		};
		f[@"odd"] = ^id(NSArray *a) {
			long long value = 0;
			return [a count] == 1 && UDInteger([a objectAtIndex:0], &value)
				? [NSNumber numberWithBool:llabs(value) % 2 == 1] : UDNull();
		};
		f[@"even"] = ^id(NSArray *a) {
			long long value = 0;
			return [a count] == 1 && UDInteger([a objectAtIndex:0], &value)
				? [NSNumber numberWithBool:value % 2 == 0] : UDNull();
		};

		/* Time. */
		f[@"now"] = ^id(NSArray *a) {
			return [a count] == 0 ? [NSDate date] : UDNull();
		};
		f[@"today"] = ^id(NSArray *a) {
			return [a count] == 0 ? UDFeelToday() : UDNull();
		};
		f[@"date"] = ^id(NSArray *a) {
			if ([a count] == 1) {
				return UDDateOf([a objectAtIndex:0]) ?: UDNull();
			}
			long long y = 0, m = 0, d = 0;
			if ([a count] == 3 && UDInteger([a objectAtIndex:0], &y) && UDInteger([a objectAtIndex:1], &m)
			    && UDInteger([a objectAtIndex:2], &d)) {
				return [UDFeelDateValue year:(NSInteger)y month:(NSInteger)m day:(NSInteger)d] ?: UDNull();
			}
			return UDNull();
		};
		f[@"date and time"] = ^id(NSArray *a) {
			if ([a count] != 1) {
				return UDNull();
			}
			id value = [a objectAtIndex:0];
			if ([value isKindOfClass:[NSDate class]]) {
				return value;
			}
			if ([value isKindOfClass:[UDFeelDateValue class]]) {
				return [value startOfDay];
			}
			return [value isKindOfClass:[NSString class]] ? (UDFeelParseDateTime(value) ?: UDNull()) : UDNull();
		};
		f[@"duration"] = ^id(NSArray *a) {
			return UDStrings(a, 1) ? (UDFeelParseDuration([a objectAtIndex:0]) ?: UDNull()) : UDNull();
		};
		f[@"years and months duration"] = ^id(NSArray *a) {
			UDFeelDateValue *from = [a count] == 2 ? UDDateOf([a objectAtIndex:0]) : nil;
			UDFeelDateValue *to = [a count] == 2 ? UDDateOf([a objectAtIndex:1]) : nil;
			if (from == nil || to == nil || [[a objectAtIndex:0] isKindOfClass:[NSString class]]
			    || [[a objectAtIndex:1] isKindOfClass:[NSString class]]) {
				return UDNull();
			}
			NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
			[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
			NSDateComponents *between = [calendar components:NSCalendarUnitMonth
			                                         fromDate:[from startOfDay]
			                                           toDate:[to startOfDay]
			                                          options:0];
			return [UDFeelDuration months:[between month]];
		};
		f[@"day of week"] = ^id(NSArray *a) {
			UDFeelDateValue *date = [a count] == 1 && ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
				? UDDateOf([a objectAtIndex:0]) : nil;
			if (date == nil) {
				return UDNull();
			}
			NSArray *names = @[ @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday",
				@"Saturday" ];
			return [names objectAtIndex:(NSUInteger)[UDComponents(NSCalendarUnitWeekday, date) weekday] - 1];
		};
		f[@"month of year"] = ^id(NSArray *a) {
			UDFeelDateValue *date = [a count] == 1 && ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
				? UDDateOf([a objectAtIndex:0]) : nil;
			if (date == nil) {
				return UDNull();
			}
			NSArray *names = @[ @"January", @"February", @"March", @"April", @"May", @"June", @"July",
				@"August", @"September", @"October", @"November", @"December" ];
			return [names objectAtIndex:(NSUInteger)date.month - 1];
		};
		f[@"day of year"] = ^id(NSArray *a) {
			UDFeelDateValue *date = [a count] == 1 && ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
				? UDDateOf([a objectAtIndex:0]) : nil;
			if (date == nil) {
				return UDNull();
			}
			UDFeelDateValue *first = [UDFeelDateValue year:date.year month:1 day:1];
			return UDWhole((long long)round([[date startOfDay] timeIntervalSinceDate:[first startOfDay]] / 86400) + 1);
		};
		f[@"week of year"] = ^id(NSArray *a) {
			UDFeelDateValue *date = [a count] == 1 && ![[a objectAtIndex:0] isKindOfClass:[NSString class]]
				? UDDateOf([a objectAtIndex:0]) : nil;
			/* ISO 8601: weeks start on Monday; week 1 holds the year's
			 * first Thursday. */
			return date != nil ? UDWhole([UDComponents(NSCalendarUnitWeekOfYear, date) weekOfYear]) : UDNull();
		};

		functions = [f copy];
	});
	return functions;
}

BOOL
UDFeelIsBuiltin(NSString *name)
{
	return [UDFeelFunctions() objectForKey:name] != nil;
}

NSArray<NSString *> *
UDFeelMultiWordBuiltins(void)
{
	static NSArray *names = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableArray *multi = [NSMutableArray array];
		for (NSString *name in UDFeelFunctions()) {
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
UDFeelCall(NSString *name, NSArray *arguments)
{
	UDFeelFunction function = [UDFeelFunctions() objectForKey:name];
	return function != nil ? (function(arguments) ?: UDNull()) : UDNull();
}

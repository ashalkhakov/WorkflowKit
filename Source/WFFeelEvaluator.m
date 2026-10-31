#import "WFFeelInternal.h"
#include <string.h>

#pragma mark - Values

BOOL
WFFeelIsNull(id value)
{
	return value == nil || value == [NSNull null];
}

BOOL
WFFeelIsBoolean(id value)
{
	if (![value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDecimalNumber class]]) {
		return NO;
	}
	/* true and false: NSNumber's two shared instances, or a number made from
	 * a BOOL or a char, told by its type -- except where BOOL is an int
	 * (Windows), whose type is every int's: there only the instances are. */
	if (value == (id)@YES || value == (id)@NO) {
		return YES;
	}
	const char *type = [(NSNumber *)value objCType];
	return (strcmp(@encode(BOOL), @encode(int)) != 0 && strcmp(type, @encode(BOOL)) == 0)
		|| strcmp(type, @encode(char)) == 0 || strcmp(type, "B") == 0;
}

BOOL
WFFeelIsNumber(id value)
{
	return [value isKindOfClass:[NSNumber class]] && !WFFeelIsBoolean(value);
}

static NSDictionary *
WFFeelDecimalLocale(void)
{
	return @{ NSDecimalSeparator: @"." };
}

NSDecimalNumber *
WFFeelDecimal(NSNumber *number)
{
	if ([number isKindOfClass:[NSDecimalNumber class]]) {
		return (NSDecimalNumber *)number;
	}
	const char *type = [number objCType];
	if (strchr("cCsSiIlLqQ", type[0]) != NULL && type[1] == 0) {
		long long value = [number longLongValue];
		unsigned long long magnitude = value < 0 ? 0ULL - (unsigned long long)value
			: (unsigned long long)value;
		return [NSDecimalNumber decimalNumberWithMantissa:magnitude exponent:0 isNegative:value < 0];
	}
	double value = [number doubleValue];
	if (value != value || value > 1e300 || value < -1e300) {
		return nil;
	}
	/* Fifteen significant digits give back the decimal the double was
	 * written as: 0.1 is 0.1, not 0.1000000000000000055511151231257827. */
	return [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.15g", value]
	                                         locale:WFFeelDecimalLocale()];
}

static NSString *
WFFeelNumberText(NSNumber *number)
{
	NSDecimalNumber *decimal = WFFeelDecimal(number);
	return decimal != nil ? [decimal descriptionWithLocale:WFFeelDecimalLocale()] : @"null";
}

NSString *
WFFeelLiteralText(id value)
{
	if (WFFeelIsNull(value)) {
		return @"null";
	}
	if (WFFeelIsBoolean(value)) {
		return [value boolValue] ? @"true" : @"false";
	}
	if (WFFeelIsNumber(value)) {
		return WFFeelNumberText(value);
	}
	if ([value isKindOfClass:[NSString class]]) {
		NSMutableString *text = [NSMutableString stringWithString:@"\""];
		NSString *string = value;
		for (NSUInteger i = 0; i < [string length]; i++) {
			unichar c = [string characterAtIndex:i];
			switch (c) {
			case '"': [text appendString:@"\\\""]; break;
			case '\\': [text appendString:@"\\\\"]; break;
			case '\n': [text appendString:@"\\n"]; break;
			case '\r': [text appendString:@"\\r"]; break;
			case '\t': [text appendString:@"\\t"]; break;
			default: [text appendFormat:@"%C", c]; break;
			}
		}
		[text appendString:@"\""];
		return text;
	}
	if (WFFeelIsTemporal(value)) {
		return [NSString stringWithFormat:@"@\"%@\"", WFFeelTemporalText(value)];
	}
	if ([value isKindOfClass:[NSArray class]]) {
		NSMutableArray *items = [NSMutableArray array];
		for (id item in value) {
			[items addObject:WFFeelLiteralText(item)];
		}
		return [NSString stringWithFormat:@"[%@]", [items componentsJoinedByString:@", "]];
	}
	if ([value isKindOfClass:[NSDictionary class]]) {
		NSMutableArray *entries = [NSMutableArray array];
		for (NSString *key in [[value allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			[entries addObject:[NSString stringWithFormat:@"%@: %@", WFFeelLiteralText(key),
				WFFeelLiteralText([value objectForKey:key])]];
		}
		return [NSString stringWithFormat:@"{%@}", [entries componentsJoinedByString:@", "]];
	}
	return [value description];
}

@implementation WFFeelRange

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@%@..%@%@", self.startIncluded ? @"[" : @"(",
		WFFeelLiteralText(self.start), WFFeelLiteralText(self.end), self.endIncluded ? @"]" : @")"];
}

@end

#pragma mark - Comparison

/* Two values' order when FEEL orders them: numbers, strings and dates, each
 * with their own kind. NO when it does not. */
static BOOL
WFFeelOrder(id a, id b, NSComparisonResult *result)
{
	if (WFFeelIsNumber(a) && WFFeelIsNumber(b)) {
		NSDecimalNumber *x = WFFeelDecimal(a);
		NSDecimalNumber *y = WFFeelDecimal(b);
		if (x == nil || y == nil) {
			return NO;
		}
		*result = [x compare:y];
		return YES;
	}
	if ([a isKindOfClass:[NSString class]] && [b isKindOfClass:[NSString class]]) {
		*result = [(NSString *)a compare:b options:NSLiteralSearch];
		return YES;
	}
	if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]]) {
		*result = [(NSDate *)a compare:b];
		return YES;
	}
	return WFFeelTemporalOrder(a, b, result);
}

/* FEEL's =: 1 equal, 0 not, -1 no answer (values of different kinds). Null
 * equals null and nothing else. */
static int
WFFeelEquality(id a, id b)
{
	BOOL nullA = WFFeelIsNull(a);
	BOOL nullB = WFFeelIsNull(b);
	if (nullA || nullB) {
		return nullA && nullB;
	}
	if (WFFeelIsBoolean(a) && WFFeelIsBoolean(b)) {
		return [a boolValue] == [b boolValue];
	}
	NSComparisonResult order;
	if (WFFeelOrder(a, b, &order)) {
		return order == NSOrderedSame;
	}
	if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]]) {
		if ([a count] != [b count]) {
			return 0;
		}
		for (NSUInteger i = 0; i < [a count]; i++) {
			int item = WFFeelEquality([a objectAtIndex:i], [b objectAtIndex:i]);
			if (item != 1) {
				return item;
			}
		}
		return 1;
	}
	if ([a isKindOfClass:[NSDictionary class]] && [b isKindOfClass:[NSDictionary class]]) {
		if (![[NSSet setWithArray:[a allKeys]] isEqualToSet:[NSSet setWithArray:[b allKeys]]]) {
			return 0;
		}
		for (NSString *key in a) {
			int entry = WFFeelEquality([a objectForKey:key], [b objectForKey:key]);
			if (entry != 1) {
				return entry;
			}
		}
		return 1;
	}
	if ([a isKindOfClass:[WFFeelRange class]] && [b isKindOfClass:[WFFeelRange class]]) {
		WFFeelRange *x = a, *y = b;
		return x.startIncluded == y.startIncluded && x.endIncluded == y.endIncluded
			&& WFFeelEquality(x.start, y.start) == 1 && WFFeelEquality(x.end, y.end) == 1;
	}
	return -1;
}

static id
WFFeelBool(BOOL value)
{
	return [NSNumber numberWithBool:value];
}

static id
WFFeelCompare(WFFeelOperator op, id a, id b)
{
	if (op == WFFeelOperatorEqual || op == WFFeelOperatorNotEqual) {
		int equal = WFFeelEquality(a, b);
		if (equal < 0) {
			return [NSNull null];
		}
		return WFFeelBool(op == WFFeelOperatorEqual ? equal == 1 : equal == 0);
	}
	NSComparisonResult order;
	if (!WFFeelOrder(a, b, &order)) {
		return [NSNull null];
	}
	switch (op) {
	case WFFeelOperatorLess: return WFFeelBool(order == NSOrderedAscending);
	case WFFeelOperatorLessOrEqual: return WFFeelBool(order != NSOrderedDescending);
	case WFFeelOperatorGreater: return WFFeelBool(order == NSOrderedDescending);
	case WFFeelOperatorGreaterOrEqual: return WFFeelBool(order != NSOrderedAscending);
	default: return [NSNull null];
	}
}

id
WFFeelCompareValues(WFFeelOperator op, id a, id b)
{
	return WFFeelCompare(op, a, b);
}

id
WFFeelValuesEqual(id a, id b)
{
	return WFFeelCompare(WFFeelOperatorEqual, a, b);
}

/* Whether the range holds the value: true, false, or null when they are
 * not of a kind that orders. */
static id
WFFeelRangeContains(WFFeelRange *range, id value)
{
	id low = WFFeelCompare(range.startIncluded ? WFFeelOperatorGreaterOrEqual : WFFeelOperatorGreater,
		value, range.start);
	id high = WFFeelCompare(range.endIncluded ? WFFeelOperatorLessOrEqual : WFFeelOperatorLess,
		value, range.end);
	if (WFFeelIsNull(low) || WFFeelIsNull(high)) {
		return [NSNull null];
	}
	return WFFeelBool([low boolValue] && [high boolValue]);
}

#pragma mark - Arithmetic

static NSDecimalNumberHandler *
WFFeelHandler(void)
{
	static NSDecimalNumberHandler *handler = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		handler = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundBankers
			scale:NSDecimalNoScale raiseOnExactness:NO raiseOnOverflow:NO
			raiseOnUnderflow:NO raiseOnDivideByZero:NO];
	});
	return handler;
}

/* A decimal result, or null when it is not a number (an overflow). */
id
WFFeelNumberResult(NSDecimalNumber *number)
{
	if (number == nil) {
		return [NSNull null];
	}
	NSDecimal value = [number decimalValue];
	return NSDecimalIsNotANumber(&value) ? (id)[NSNull null] : number;
}

static id
WFFeelPower(NSDecimalNumber *base, NSDecimalNumber *exponent)
{
	NSDecimalNumber *whole = [exponent decimalNumberByRoundingAccordingToBehavior:
		[NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundDown scale:0
			raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO]];
	if ([whole compare:exponent] == NSOrderedSame && fabs([whole doubleValue]) <= 999) {
		NSInteger n = [whole integerValue];
		NSDecimalNumber *raised = [base decimalNumberByRaisingToPower:(NSUInteger)labs((long)n)
		                                                withBehavior:WFFeelHandler()];
		if (n >= 0) {
			return WFFeelNumberResult(raised);
		}
		if ([raised compare:[NSDecimalNumber zero]] == NSOrderedSame) {
			return [NSNull null];
		}
		return WFFeelNumberResult([[NSDecimalNumber one] decimalNumberByDividingBy:raised
		                                                             withBehavior:WFFeelHandler()]);
	}
	double value = pow([base doubleValue], [exponent doubleValue]);
	return value == value ? WFFeelNumberResult(WFFeelDecimal([NSNumber numberWithDouble:value]))
		: (id)[NSNull null];
}

id
WFFeelArithmetic(WFFeelOperator op, id a, id b)
{
	if (op == WFFeelOperatorAdd && [a isKindOfClass:[NSString class]]
	    && [b isKindOfClass:[NSString class]]) {
		return [(NSString *)a stringByAppendingString:b];
	}
	id temporal = WFFeelTemporalArithmetic(op, a, b);
	if (temporal != nil) {
		return temporal;
	}
	if (!WFFeelIsNumber(a) || !WFFeelIsNumber(b)) {
		return [NSNull null];
	}
	NSDecimalNumber *x = WFFeelDecimal(a);
	NSDecimalNumber *y = WFFeelDecimal(b);
	if (x == nil || y == nil) {
		return [NSNull null];
	}
	BOOL divisorZero = [y compare:[NSDecimalNumber zero]] == NSOrderedSame;
	switch (op) {
	case WFFeelOperatorAdd:
		return WFFeelNumberResult([x decimalNumberByAdding:y withBehavior:WFFeelHandler()]);
	case WFFeelOperatorSubtract:
		return WFFeelNumberResult([x decimalNumberBySubtracting:y withBehavior:WFFeelHandler()]);
	case WFFeelOperatorMultiply:
		return WFFeelNumberResult([x decimalNumberByMultiplyingBy:y withBehavior:WFFeelHandler()]);
	case WFFeelOperatorDivide:
		return divisorZero ? (id)[NSNull null]
			: WFFeelNumberResult([x decimalNumberByDividingBy:y withBehavior:WFFeelHandler()]);
	case WFFeelOperatorModulo: {
		if (divisorZero) {
			return [NSNull null];
		}
		/* The sign of the divisor, as FEEL's modulo(): a - b * floor(a / b). */
		NSDecimalNumber *quotient = [x decimalNumberByDividingBy:y withBehavior:WFFeelHandler()];
		NSDecimal q = [quotient decimalValue], floored;
		NSDecimalRound(&floored, &q, 0, NSRoundDown);
		NSDecimalNumber *whole = [NSDecimalNumber decimalNumberWithDecimal:floored];
		return WFFeelNumberResult([x decimalNumberBySubtracting:
			[y decimalNumberByMultiplyingBy:whole withBehavior:WFFeelHandler()]
			withBehavior:WFFeelHandler()]);
	}
	case WFFeelOperatorPower:
		return WFFeelPower(x, y);
	default:
		return [NSNull null];
	}
}

#pragma mark - Evaluation

/* The names in scope: an iteration's variable, a filter's item, the
 * entries of a context being built, then the variables. */
@interface WFFeelScope : NSObject
@property (nonatomic, strong) NSDictionary *bindings;
@property (nonatomic, strong) WFFeelScope *parent;
@end

@implementation WFFeelScope

+ (instancetype)scope:(NSDictionary *)bindings parent:(WFFeelScope *)parent
{
	WFFeelScope *scope = [[self alloc] init];
	scope.bindings = bindings ?: @{};
	scope.parent = parent;
	return scope;
}

- (id)valueOf:(NSString *)name
{
	for (WFFeelScope *scope = self; scope != nil; scope = scope.parent) {
		id value = [scope.bindings objectForKey:name];
		if (value != nil) {
			return value;
		}
	}
	return [NSNull null];
}

@end

static id WFFeelEval(WFFeelNode *node, WFFeelScope *scope);

/* What a filter or an iteration goes through: a list's items, a range's
 * whole numbers, or a single value as a list of one. nil for null. */
static NSArray *
WFFeelItems(id value)
{
	if (WFFeelIsNull(value)) {
		return nil;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		return value;
	}
	if ([value isKindOfClass:[WFFeelRange class]]) {
		WFFeelRange *range = value;
		if (!WFFeelIsNumber(range.start) || !WFFeelIsNumber(range.end)) {
			return nil;
		}
		long long from = [range.start longLongValue];
		long long to = [range.end longLongValue];
		long long step = from <= to ? 1 : -1;
		if (!range.startIncluded) {
			from += step;
		}
		if (!range.endIncluded) {
			to -= step;
		}
		NSMutableArray *items = [NSMutableArray array];
		for (long long i = from; step > 0 ? i <= to : i >= to; i += step) {
			[items addObject:[NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)llabs(i)
				exponent:0 isNegative:i < 0]];
			if ([items count] > 1000000) {
				return nil;
			}
		}
		return items;
	}
	return @[ value ];
}

/* A filter's item in scope: `item`, and the item's own entries when it is
 * a context. */
static WFFeelScope *
WFFeelItemScope(id item, WFFeelScope *scope)
{
	NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
	if ([item isKindOfClass:[NSDictionary class]]) {
		[bindings addEntriesFromDictionary:item];
	}
	[bindings setObject:item forKey:@"item"];
	return [WFFeelScope scope:bindings parent:scope];
}

static id
WFFeelFilter(WFFeelNode *node, WFFeelScope *scope)
{
	NSArray *items = WFFeelItems(WFFeelEval([node.children objectAtIndex:0], scope));
	if (items == nil) {
		return [NSNull null];
	}
	WFFeelNode *test = [node.children objectAtIndex:1];
	NSMutableArray *kept = [NSMutableArray array];
	for (NSUInteger i = 0; i < [items count]; i++) {
		id item = [items objectAtIndex:i];
		id result = WFFeelEval(test, WFFeelItemScope(item, scope));
		if (i == 0 && WFFeelIsNumber(result)) {
			/* A number is an index: 1 the first item, -1 the last. */
			long long index = [result longLongValue];
			long long count = (long long)[items count];
			long long at = index > 0 ? index - 1 : count + index;
			if (index == 0 || at < 0 || at >= count
			    || WFFeelEquality(result, [NSNumber numberWithLongLong:index]) != 1) {
				return [NSNull null];
			}
			return [items objectAtIndex:(NSUInteger)at];
		}
		if (WFFeelIsBoolean(result) && [result boolValue]) {
			[kept addObject:item];
		}
	}
	return kept;
}

static id
WFFeelPath(id base, NSString *name)
{
	if (WFFeelIsTemporal(base)) {
		return WFFeelTemporalProperty(base, name) ?: [NSNull null];
	}
	if ([base isKindOfClass:[NSDictionary class]]) {
		return [base objectForKey:name] ?: [NSNull null];
	}
	if ([base isKindOfClass:[NSArray class]]) {
		/* A path over a list is the path of each item. */
		NSMutableArray *values = [NSMutableArray array];
		for (id item in base) {
			[values addObject:WFFeelPath(item, name)];
		}
		return values;
	}
	return [NSNull null];
}

/* FEEL's and and or, over true, false and anything else as null. */
static id
WFFeelLogic(WFFeelNode *node, WFFeelScope *scope)
{
	BOOL isAnd = node.op == WFFeelOperatorAnd;
	/* The value that settles it: false for and, true for or. */
	BOOL settles = !isAnd;
	id left = WFFeelEval([node.children objectAtIndex:0], scope);
	if (WFFeelIsBoolean(left) && [left boolValue] == settles) {
		return WFFeelBool(settles);
	}
	id right = WFFeelEval([node.children objectAtIndex:1], scope);
	if (WFFeelIsBoolean(right) && [right boolValue] == settles) {
		return WFFeelBool(settles);
	}
	if (WFFeelIsBoolean(left) && WFFeelIsBoolean(right)) {
		return WFFeelBool(!settles);
	}
	return [NSNull null];
}

static id
WFFeelTest(WFFeelNode *test, id value, WFFeelScope *scope)
{
	id endpoint = WFFeelEval([test.children objectAtIndex:0], scope);
	if (test.op != WFFeelOperatorEqual) {
		return WFFeelCompare(test.op, value, endpoint);
	}
	if ([endpoint isKindOfClass:[WFFeelRange class]]) {
		return WFFeelRangeContains(endpoint, value);
	}
	if ([endpoint isKindOfClass:[NSArray class]] && ![value isKindOfClass:[NSArray class]]) {
		for (id item in endpoint) {
			if (WFFeelEquality(value, item) == 1) {
				return WFFeelBool(YES);
			}
		}
		return WFFeelBool(NO);
	}
	return WFFeelCompare(WFFeelOperatorEqual, value, endpoint);
}

static id
WFFeelIn(WFFeelNode *node, WFFeelScope *scope)
{
	id value = WFFeelEval([node.children objectAtIndex:0], scope);
	BOOL unknown = NO;
	for (NSUInteger i = 1; i < [node.children count]; i++) {
		id result = WFFeelTest([node.children objectAtIndex:i], value, scope);
		if (WFFeelIsBoolean(result) && [result boolValue]) {
			return WFFeelBool(YES);
		}
		if (!WFFeelIsBoolean(result)) {
			unknown = YES;
		}
	}
	return unknown ? (id)[NSNull null] : WFFeelBool(NO);
}

/* Each combination of the iteration's variables, in order, each later
 * collection seeing the earlier variables; NO when a collection is not
 * one. */
static BOOL
WFFeelIterate(WFFeelNode *node, NSUInteger level, WFFeelScope *scope,
              BOOL (^body)(WFFeelScope *scope))
{
	if (level == [node.names count]) {
		return body(scope);
	}
	NSArray *items = WFFeelItems(WFFeelEval([node.children objectAtIndex:level], scope));
	if (items == nil) {
		return NO;
	}
	NSString *name = [node.names objectAtIndex:level];
	for (id item in items) {
		WFFeelScope *inner = [WFFeelScope scope:@{ name: item } parent:scope];
		if (!WFFeelIterate(node, level + 1, inner, body)) {
			return NO;
		}
	}
	return YES;
}

static id
WFFeelLoop(WFFeelNode *node, WFFeelScope *scope)
{
	WFFeelNode *bodyNode = [node.children lastObject];
	if (node.kind == WFFeelNodeFor) {
		NSMutableArray *results = [NSMutableArray array];
		BOOL ok = WFFeelIterate(node, 0, scope, ^BOOL(WFFeelScope *inner) {
			[results addObject:WFFeelEval(bodyNode, inner)];
			return YES;
		});
		return ok ? (id)results : (id)[NSNull null];
	}
	/* some stops at the first that satisfies, every at the first that does
	 * not; a collection that is not one makes it null. */
	BOOL isSome = node.kind == WFFeelNodeSome;
	__block BOOL decided = NO;
	BOOL ok = WFFeelIterate(node, 0, scope, ^BOOL(WFFeelScope *inner) {
		id result = WFFeelEval(bodyNode, inner);
		BOOL satisfied = WFFeelIsBoolean(result) && [result boolValue];
		if (satisfied == isSome) {
			decided = YES;
		}
		return !decided;
	});
	if (decided) {
		return WFFeelBool(isSome);
	}
	return ok ? WFFeelBool(!isSome) : (id)[NSNull null];
}

static id
WFFeelEval(WFFeelNode *node, WFFeelScope *scope)
{
	NSArray *c = node.children;
	switch (node.kind) {
	case WFFeelNodeLiteral:
		return node.value;
	case WFFeelNodeName:
		return [scope valueOf:node.name];
	case WFFeelNodePath:
		return WFFeelPath(WFFeelEval([c objectAtIndex:0], scope), node.name);
	case WFFeelNodeFilter:
		return WFFeelFilter(node, scope);
	case WFFeelNodeCall: {
		NSMutableArray *arguments = [NSMutableArray array];
		for (WFFeelNode *argument in c) {
			[arguments addObject:WFFeelEval(argument, scope)];
		}
		return WFFeelCall(node.name, arguments);
	}
	case WFFeelNodeNegate: {
		id value = WFFeelEval([c objectAtIndex:0], scope);
		return WFFeelTemporalNegate(value)
			?: WFFeelArithmetic(WFFeelOperatorSubtract, [NSDecimalNumber zero], value);
	}
	case WFFeelNodeBinary:
		if (node.op == WFFeelOperatorAnd || node.op == WFFeelOperatorOr) {
			return WFFeelLogic(node, scope);
		}
		if (node.op >= WFFeelOperatorEqual && node.op <= WFFeelOperatorGreaterOrEqual) {
			return WFFeelCompare(node.op, WFFeelEval([c objectAtIndex:0], scope),
				WFFeelEval([c objectAtIndex:1], scope));
		}
		return WFFeelArithmetic(node.op, WFFeelEval([c objectAtIndex:0], scope),
			WFFeelEval([c objectAtIndex:1], scope));
	case WFFeelNodeBetween: {
		id value = WFFeelEval([c objectAtIndex:0], scope);
		WFFeelRange *range = [[WFFeelRange alloc] init];
		range.start = WFFeelEval([c objectAtIndex:1], scope);
		range.end = WFFeelEval([c objectAtIndex:2], scope);
		range.startIncluded = YES;
		range.endIncluded = YES;
		return WFFeelRangeContains(range, value);
	}
	case WFFeelNodeIn:
		return WFFeelIn(node, scope);
	case WFFeelNodeUnaryTest:
		/* Only ever evaluated by the in that holds it. */
		return [NSNull null];
	case WFFeelNodeList: {
		NSMutableArray *items = [NSMutableArray array];
		for (WFFeelNode *item in c) {
			[items addObject:WFFeelEval(item, scope)];
		}
		return items;
	}
	case WFFeelNodeRange: {
		WFFeelRange *range = [[WFFeelRange alloc] init];
		range.start = WFFeelEval([c objectAtIndex:0], scope);
		range.end = WFFeelEval([c objectAtIndex:1], scope);
		range.startIncluded = node.startIncluded;
		range.endIncluded = node.endIncluded;
		return range;
	}
	case WFFeelNodeContext: {
		/* A later entry sees the earlier ones. */
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		WFFeelScope *inner = [WFFeelScope scope:context parent:scope];
		for (NSUInteger i = 0; i < [c count]; i++) {
			[context setObject:WFFeelEval([c objectAtIndex:i], inner)
			            forKey:[node.names objectAtIndex:i]];
		}
		return [context copy];
	}
	case WFFeelNodeIf: {
		id condition = WFFeelEval([c objectAtIndex:0], scope);
		BOOL holds = WFFeelIsBoolean(condition) && [condition boolValue];
		return WFFeelEval([c objectAtIndex:holds ? 1 : 2], scope);
	}
	case WFFeelNodeFor:
	case WFFeelNodeSome:
	case WFFeelNodeEvery:
		return WFFeelLoop(node, scope);
	}
	return [NSNull null];
}

id
WFFeelEvaluate(WFFeelNode *node, NSDictionary *variables)
{
	return WFFeelEval(node, [WFFeelScope scope:variables parent:nil]) ?: [NSNull null];
}

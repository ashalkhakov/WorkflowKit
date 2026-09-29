#import "UDFeelInternal.h"
#include <string.h>

#pragma mark - Values

BOOL
UDFeelIsNull(id value)
{
	return value == nil || value == [NSNull null];
}

BOOL
UDFeelIsBoolean(id value)
{
	if (![value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDecimalNumber class]]) {
		return NO;
	}
	const char *type = [(NSNumber *)value objCType];
	return strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(char)) == 0
		|| strcmp(type, "B") == 0;
}

BOOL
UDFeelIsNumber(id value)
{
	return [value isKindOfClass:[NSNumber class]] && !UDFeelIsBoolean(value);
}

static NSDictionary *
UDFeelDecimalLocale(void)
{
	return @{ NSDecimalSeparator: @"." };
}

NSDecimalNumber *
UDFeelDecimal(NSNumber *number)
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
	                                         locale:UDFeelDecimalLocale()];
}

static NSString *
UDFeelNumberText(NSNumber *number)
{
	NSDecimalNumber *decimal = UDFeelDecimal(number);
	return decimal != nil ? [decimal descriptionWithLocale:UDFeelDecimalLocale()] : @"null";
}

NSString *
UDFeelLiteralText(id value)
{
	if (UDFeelIsNull(value)) {
		return @"null";
	}
	if (UDFeelIsBoolean(value)) {
		return [value boolValue] ? @"true" : @"false";
	}
	if (UDFeelIsNumber(value)) {
		return UDFeelNumberText(value);
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
	if (UDFeelIsTemporal(value)) {
		return [NSString stringWithFormat:@"@\"%@\"", UDFeelTemporalText(value)];
	}
	if ([value isKindOfClass:[NSArray class]]) {
		NSMutableArray *items = [NSMutableArray array];
		for (id item in value) {
			[items addObject:UDFeelLiteralText(item)];
		}
		return [NSString stringWithFormat:@"[%@]", [items componentsJoinedByString:@", "]];
	}
	if ([value isKindOfClass:[NSDictionary class]]) {
		NSMutableArray *entries = [NSMutableArray array];
		for (NSString *key in [[value allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			[entries addObject:[NSString stringWithFormat:@"%@: %@", UDFeelLiteralText(key),
				UDFeelLiteralText([value objectForKey:key])]];
		}
		return [NSString stringWithFormat:@"{%@}", [entries componentsJoinedByString:@", "]];
	}
	return [value description];
}

@implementation UDFeelRange

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@%@..%@%@", self.startIncluded ? @"[" : @"(",
		UDFeelLiteralText(self.start), UDFeelLiteralText(self.end), self.endIncluded ? @"]" : @")"];
}

@end

#pragma mark - Comparison

/* Two values' order when FEEL orders them: numbers, strings and dates, each
 * with their own kind. NO when it does not. */
static BOOL
UDFeelOrder(id a, id b, NSComparisonResult *result)
{
	if (UDFeelIsNumber(a) && UDFeelIsNumber(b)) {
		NSDecimalNumber *x = UDFeelDecimal(a);
		NSDecimalNumber *y = UDFeelDecimal(b);
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
	return UDFeelTemporalOrder(a, b, result);
}

/* FEEL's =: 1 equal, 0 not, -1 no answer (values of different kinds). Null
 * equals null and nothing else. */
static int
UDFeelEquality(id a, id b)
{
	BOOL nullA = UDFeelIsNull(a);
	BOOL nullB = UDFeelIsNull(b);
	if (nullA || nullB) {
		return nullA && nullB;
	}
	if (UDFeelIsBoolean(a) && UDFeelIsBoolean(b)) {
		return [a boolValue] == [b boolValue];
	}
	NSComparisonResult order;
	if (UDFeelOrder(a, b, &order)) {
		return order == NSOrderedSame;
	}
	if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]]) {
		if ([a count] != [b count]) {
			return 0;
		}
		for (NSUInteger i = 0; i < [a count]; i++) {
			int item = UDFeelEquality([a objectAtIndex:i], [b objectAtIndex:i]);
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
			int entry = UDFeelEquality([a objectForKey:key], [b objectForKey:key]);
			if (entry != 1) {
				return entry;
			}
		}
		return 1;
	}
	if ([a isKindOfClass:[UDFeelRange class]] && [b isKindOfClass:[UDFeelRange class]]) {
		UDFeelRange *x = a, *y = b;
		return x.startIncluded == y.startIncluded && x.endIncluded == y.endIncluded
			&& UDFeelEquality(x.start, y.start) == 1 && UDFeelEquality(x.end, y.end) == 1;
	}
	return -1;
}

static id
UDFeelBool(BOOL value)
{
	return [NSNumber numberWithBool:value];
}

static id
UDFeelCompare(UDFeelOperator op, id a, id b)
{
	if (op == UDFeelOperatorEqual || op == UDFeelOperatorNotEqual) {
		int equal = UDFeelEquality(a, b);
		if (equal < 0) {
			return [NSNull null];
		}
		return UDFeelBool(op == UDFeelOperatorEqual ? equal == 1 : equal == 0);
	}
	NSComparisonResult order;
	if (!UDFeelOrder(a, b, &order)) {
		return [NSNull null];
	}
	switch (op) {
	case UDFeelOperatorLess: return UDFeelBool(order == NSOrderedAscending);
	case UDFeelOperatorLessOrEqual: return UDFeelBool(order != NSOrderedDescending);
	case UDFeelOperatorGreater: return UDFeelBool(order == NSOrderedDescending);
	case UDFeelOperatorGreaterOrEqual: return UDFeelBool(order != NSOrderedAscending);
	default: return [NSNull null];
	}
}

id
UDFeelCompareValues(UDFeelOperator op, id a, id b)
{
	return UDFeelCompare(op, a, b);
}

id
UDFeelValuesEqual(id a, id b)
{
	return UDFeelCompare(UDFeelOperatorEqual, a, b);
}

/* Whether the range holds the value: true, false, or null when they are
 * not of a kind that orders. */
static id
UDFeelRangeContains(UDFeelRange *range, id value)
{
	id low = UDFeelCompare(range.startIncluded ? UDFeelOperatorGreaterOrEqual : UDFeelOperatorGreater,
		value, range.start);
	id high = UDFeelCompare(range.endIncluded ? UDFeelOperatorLessOrEqual : UDFeelOperatorLess,
		value, range.end);
	if (UDFeelIsNull(low) || UDFeelIsNull(high)) {
		return [NSNull null];
	}
	return UDFeelBool([low boolValue] && [high boolValue]);
}

#pragma mark - Arithmetic

static NSDecimalNumberHandler *
UDFeelHandler(void)
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
UDFeelNumberResult(NSDecimalNumber *number)
{
	if (number == nil) {
		return [NSNull null];
	}
	NSDecimal value = [number decimalValue];
	return NSDecimalIsNotANumber(&value) ? (id)[NSNull null] : number;
}

static id
UDFeelPower(NSDecimalNumber *base, NSDecimalNumber *exponent)
{
	NSDecimalNumber *whole = [exponent decimalNumberByRoundingAccordingToBehavior:
		[NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundDown scale:0
			raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO]];
	if ([whole compare:exponent] == NSOrderedSame && fabs([whole doubleValue]) <= 999) {
		NSInteger n = [whole integerValue];
		NSDecimalNumber *raised = [base decimalNumberByRaisingToPower:(NSUInteger)labs((long)n)
		                                                withBehavior:UDFeelHandler()];
		if (n >= 0) {
			return UDFeelNumberResult(raised);
		}
		if ([raised compare:[NSDecimalNumber zero]] == NSOrderedSame) {
			return [NSNull null];
		}
		return UDFeelNumberResult([[NSDecimalNumber one] decimalNumberByDividingBy:raised
		                                                             withBehavior:UDFeelHandler()]);
	}
	double value = pow([base doubleValue], [exponent doubleValue]);
	return value == value ? UDFeelNumberResult(UDFeelDecimal([NSNumber numberWithDouble:value]))
		: (id)[NSNull null];
}

id
UDFeelArithmetic(UDFeelOperator op, id a, id b)
{
	if (op == UDFeelOperatorAdd && [a isKindOfClass:[NSString class]]
	    && [b isKindOfClass:[NSString class]]) {
		return [(NSString *)a stringByAppendingString:b];
	}
	id temporal = UDFeelTemporalArithmetic(op, a, b);
	if (temporal != nil) {
		return temporal;
	}
	if (!UDFeelIsNumber(a) || !UDFeelIsNumber(b)) {
		return [NSNull null];
	}
	NSDecimalNumber *x = UDFeelDecimal(a);
	NSDecimalNumber *y = UDFeelDecimal(b);
	if (x == nil || y == nil) {
		return [NSNull null];
	}
	BOOL divisorZero = [y compare:[NSDecimalNumber zero]] == NSOrderedSame;
	switch (op) {
	case UDFeelOperatorAdd:
		return UDFeelNumberResult([x decimalNumberByAdding:y withBehavior:UDFeelHandler()]);
	case UDFeelOperatorSubtract:
		return UDFeelNumberResult([x decimalNumberBySubtracting:y withBehavior:UDFeelHandler()]);
	case UDFeelOperatorMultiply:
		return UDFeelNumberResult([x decimalNumberByMultiplyingBy:y withBehavior:UDFeelHandler()]);
	case UDFeelOperatorDivide:
		return divisorZero ? (id)[NSNull null]
			: UDFeelNumberResult([x decimalNumberByDividingBy:y withBehavior:UDFeelHandler()]);
	case UDFeelOperatorModulo: {
		if (divisorZero) {
			return [NSNull null];
		}
		/* The sign of the divisor, as FEEL's modulo(): a - b * floor(a / b). */
		NSDecimalNumber *quotient = [x decimalNumberByDividingBy:y withBehavior:UDFeelHandler()];
		NSDecimal q = [quotient decimalValue], floored;
		NSDecimalRound(&floored, &q, 0, NSRoundDown);
		NSDecimalNumber *whole = [NSDecimalNumber decimalNumberWithDecimal:floored];
		return UDFeelNumberResult([x decimalNumberBySubtracting:
			[y decimalNumberByMultiplyingBy:whole withBehavior:UDFeelHandler()]
			withBehavior:UDFeelHandler()]);
	}
	case UDFeelOperatorPower:
		return UDFeelPower(x, y);
	default:
		return [NSNull null];
	}
}

#pragma mark - Evaluation

/* The names in scope: an iteration's variable, a filter's item, the
 * entries of a context being built, then the variables. */
@interface UDFeelScope : NSObject
@property (nonatomic, strong) NSDictionary *bindings;
@property (nonatomic, strong) UDFeelScope *parent;
@end

@implementation UDFeelScope

+ (instancetype)scope:(NSDictionary *)bindings parent:(UDFeelScope *)parent
{
	UDFeelScope *scope = [[self alloc] init];
	scope.bindings = bindings ?: @{};
	scope.parent = parent;
	return scope;
}

- (id)valueOf:(NSString *)name
{
	for (UDFeelScope *scope = self; scope != nil; scope = scope.parent) {
		id value = [scope.bindings objectForKey:name];
		if (value != nil) {
			return value;
		}
	}
	return [NSNull null];
}

@end

static id UDFeelEval(UDFeelNode *node, UDFeelScope *scope);

/* What a filter or an iteration goes through: a list's items, a range's
 * whole numbers, or a single value as a list of one. nil for null. */
static NSArray *
UDFeelItems(id value)
{
	if (UDFeelIsNull(value)) {
		return nil;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		return value;
	}
	if ([value isKindOfClass:[UDFeelRange class]]) {
		UDFeelRange *range = value;
		if (!UDFeelIsNumber(range.start) || !UDFeelIsNumber(range.end)) {
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
static UDFeelScope *
UDFeelItemScope(id item, UDFeelScope *scope)
{
	NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
	if ([item isKindOfClass:[NSDictionary class]]) {
		[bindings addEntriesFromDictionary:item];
	}
	[bindings setObject:item forKey:@"item"];
	return [UDFeelScope scope:bindings parent:scope];
}

static id
UDFeelFilter(UDFeelNode *node, UDFeelScope *scope)
{
	NSArray *items = UDFeelItems(UDFeelEval([node.children objectAtIndex:0], scope));
	if (items == nil) {
		return [NSNull null];
	}
	UDFeelNode *test = [node.children objectAtIndex:1];
	NSMutableArray *kept = [NSMutableArray array];
	for (NSUInteger i = 0; i < [items count]; i++) {
		id item = [items objectAtIndex:i];
		id result = UDFeelEval(test, UDFeelItemScope(item, scope));
		if (i == 0 && UDFeelIsNumber(result)) {
			/* A number is an index: 1 the first item, -1 the last. */
			long long index = [result longLongValue];
			long long count = (long long)[items count];
			long long at = index > 0 ? index - 1 : count + index;
			if (index == 0 || at < 0 || at >= count
			    || UDFeelEquality(result, [NSNumber numberWithLongLong:index]) != 1) {
				return [NSNull null];
			}
			return [items objectAtIndex:(NSUInteger)at];
		}
		if (UDFeelIsBoolean(result) && [result boolValue]) {
			[kept addObject:item];
		}
	}
	return kept;
}

static id
UDFeelPath(id base, NSString *name)
{
	if (UDFeelIsTemporal(base)) {
		return UDFeelTemporalProperty(base, name) ?: [NSNull null];
	}
	if ([base isKindOfClass:[NSDictionary class]]) {
		return [base objectForKey:name] ?: [NSNull null];
	}
	if ([base isKindOfClass:[NSArray class]]) {
		/* A path over a list is the path of each item. */
		NSMutableArray *values = [NSMutableArray array];
		for (id item in base) {
			[values addObject:UDFeelPath(item, name)];
		}
		return values;
	}
	return [NSNull null];
}

/* FEEL's and and or, over true, false and anything else as null. */
static id
UDFeelLogic(UDFeelNode *node, UDFeelScope *scope)
{
	BOOL isAnd = node.op == UDFeelOperatorAnd;
	/* The value that settles it: false for and, true for or. */
	BOOL settles = !isAnd;
	id left = UDFeelEval([node.children objectAtIndex:0], scope);
	if (UDFeelIsBoolean(left) && [left boolValue] == settles) {
		return UDFeelBool(settles);
	}
	id right = UDFeelEval([node.children objectAtIndex:1], scope);
	if (UDFeelIsBoolean(right) && [right boolValue] == settles) {
		return UDFeelBool(settles);
	}
	if (UDFeelIsBoolean(left) && UDFeelIsBoolean(right)) {
		return UDFeelBool(!settles);
	}
	return [NSNull null];
}

static id
UDFeelTest(UDFeelNode *test, id value, UDFeelScope *scope)
{
	id endpoint = UDFeelEval([test.children objectAtIndex:0], scope);
	if (test.op != UDFeelOperatorEqual) {
		return UDFeelCompare(test.op, value, endpoint);
	}
	if ([endpoint isKindOfClass:[UDFeelRange class]]) {
		return UDFeelRangeContains(endpoint, value);
	}
	if ([endpoint isKindOfClass:[NSArray class]] && ![value isKindOfClass:[NSArray class]]) {
		for (id item in endpoint) {
			if (UDFeelEquality(value, item) == 1) {
				return UDFeelBool(YES);
			}
		}
		return UDFeelBool(NO);
	}
	return UDFeelCompare(UDFeelOperatorEqual, value, endpoint);
}

static id
UDFeelIn(UDFeelNode *node, UDFeelScope *scope)
{
	id value = UDFeelEval([node.children objectAtIndex:0], scope);
	BOOL unknown = NO;
	for (NSUInteger i = 1; i < [node.children count]; i++) {
		id result = UDFeelTest([node.children objectAtIndex:i], value, scope);
		if (UDFeelIsBoolean(result) && [result boolValue]) {
			return UDFeelBool(YES);
		}
		if (!UDFeelIsBoolean(result)) {
			unknown = YES;
		}
	}
	return unknown ? (id)[NSNull null] : UDFeelBool(NO);
}

/* Each combination of the iteration's variables, in order, each later
 * collection seeing the earlier variables; NO when a collection is not
 * one. */
static BOOL
UDFeelIterate(UDFeelNode *node, NSUInteger level, UDFeelScope *scope,
              BOOL (^body)(UDFeelScope *scope))
{
	if (level == [node.names count]) {
		return body(scope);
	}
	NSArray *items = UDFeelItems(UDFeelEval([node.children objectAtIndex:level], scope));
	if (items == nil) {
		return NO;
	}
	NSString *name = [node.names objectAtIndex:level];
	for (id item in items) {
		UDFeelScope *inner = [UDFeelScope scope:@{ name: item } parent:scope];
		if (!UDFeelIterate(node, level + 1, inner, body)) {
			return NO;
		}
	}
	return YES;
}

static id
UDFeelLoop(UDFeelNode *node, UDFeelScope *scope)
{
	UDFeelNode *bodyNode = [node.children lastObject];
	if (node.kind == UDFeelNodeFor) {
		NSMutableArray *results = [NSMutableArray array];
		BOOL ok = UDFeelIterate(node, 0, scope, ^BOOL(UDFeelScope *inner) {
			[results addObject:UDFeelEval(bodyNode, inner)];
			return YES;
		});
		return ok ? (id)results : (id)[NSNull null];
	}
	/* some stops at the first that satisfies, every at the first that does
	 * not; a collection that is not one makes it null. */
	BOOL isSome = node.kind == UDFeelNodeSome;
	__block BOOL decided = NO;
	BOOL ok = UDFeelIterate(node, 0, scope, ^BOOL(UDFeelScope *inner) {
		id result = UDFeelEval(bodyNode, inner);
		BOOL satisfied = UDFeelIsBoolean(result) && [result boolValue];
		if (satisfied == isSome) {
			decided = YES;
		}
		return !decided;
	});
	if (decided) {
		return UDFeelBool(isSome);
	}
	return ok ? UDFeelBool(!isSome) : (id)[NSNull null];
}

static id
UDFeelEval(UDFeelNode *node, UDFeelScope *scope)
{
	NSArray *c = node.children;
	switch (node.kind) {
	case UDFeelNodeLiteral:
		return node.value;
	case UDFeelNodeName:
		return [scope valueOf:node.name];
	case UDFeelNodePath:
		return UDFeelPath(UDFeelEval([c objectAtIndex:0], scope), node.name);
	case UDFeelNodeFilter:
		return UDFeelFilter(node, scope);
	case UDFeelNodeCall: {
		NSMutableArray *arguments = [NSMutableArray array];
		for (UDFeelNode *argument in c) {
			[arguments addObject:UDFeelEval(argument, scope)];
		}
		return UDFeelCall(node.name, arguments);
	}
	case UDFeelNodeNegate: {
		id value = UDFeelEval([c objectAtIndex:0], scope);
		return UDFeelTemporalNegate(value)
			?: UDFeelArithmetic(UDFeelOperatorSubtract, [NSDecimalNumber zero], value);
	}
	case UDFeelNodeBinary:
		if (node.op == UDFeelOperatorAnd || node.op == UDFeelOperatorOr) {
			return UDFeelLogic(node, scope);
		}
		if (node.op >= UDFeelOperatorEqual && node.op <= UDFeelOperatorGreaterOrEqual) {
			return UDFeelCompare(node.op, UDFeelEval([c objectAtIndex:0], scope),
				UDFeelEval([c objectAtIndex:1], scope));
		}
		return UDFeelArithmetic(node.op, UDFeelEval([c objectAtIndex:0], scope),
			UDFeelEval([c objectAtIndex:1], scope));
	case UDFeelNodeBetween: {
		id value = UDFeelEval([c objectAtIndex:0], scope);
		UDFeelRange *range = [[UDFeelRange alloc] init];
		range.start = UDFeelEval([c objectAtIndex:1], scope);
		range.end = UDFeelEval([c objectAtIndex:2], scope);
		range.startIncluded = YES;
		range.endIncluded = YES;
		return UDFeelRangeContains(range, value);
	}
	case UDFeelNodeIn:
		return UDFeelIn(node, scope);
	case UDFeelNodeUnaryTest:
		/* Only ever evaluated by the in that holds it. */
		return [NSNull null];
	case UDFeelNodeList: {
		NSMutableArray *items = [NSMutableArray array];
		for (UDFeelNode *item in c) {
			[items addObject:UDFeelEval(item, scope)];
		}
		return items;
	}
	case UDFeelNodeRange: {
		UDFeelRange *range = [[UDFeelRange alloc] init];
		range.start = UDFeelEval([c objectAtIndex:0], scope);
		range.end = UDFeelEval([c objectAtIndex:1], scope);
		range.startIncluded = node.startIncluded;
		range.endIncluded = node.endIncluded;
		return range;
	}
	case UDFeelNodeContext: {
		/* A later entry sees the earlier ones. */
		NSMutableDictionary *context = [NSMutableDictionary dictionary];
		UDFeelScope *inner = [UDFeelScope scope:context parent:scope];
		for (NSUInteger i = 0; i < [c count]; i++) {
			[context setObject:UDFeelEval([c objectAtIndex:i], inner)
			            forKey:[node.names objectAtIndex:i]];
		}
		return [context copy];
	}
	case UDFeelNodeIf: {
		id condition = UDFeelEval([c objectAtIndex:0], scope);
		BOOL holds = UDFeelIsBoolean(condition) && [condition boolValue];
		return UDFeelEval([c objectAtIndex:holds ? 1 : 2], scope);
	}
	case UDFeelNodeFor:
	case UDFeelNodeSome:
	case UDFeelNodeEvery:
		return UDFeelLoop(node, scope);
	}
	return [NSNull null];
}

id
UDFeelEvaluate(UDFeelNode *node, NSDictionary *variables)
{
	return UDFeelEval(node, [UDFeelScope scope:variables parent:nil]) ?: [NSNull null];
}

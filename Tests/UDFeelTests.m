#import "UDWorkflowTestCase.h"

@interface UDFeelTests : UDWorkflowTestCase
@end

@implementation UDFeelTests

- (UDFeelExpression *)parse:(NSString *)text
{
	NSError *error = nil;
	UDFeelExpression *expression = [UDFeelExpression expressionWithString:text error:&error];
	XCTAssertNotNil(expression, @"%@: %@", text, error);
	return expression;
}

/* The value of text over the variables is expected, both written in FEEL;
 * equal as FEEL's = has it, null only to null. */
- (void)check:(NSString *)text is:(NSString *)expected variables:(NSDictionary *)variables
{
	UDFeelExpression *expression = [self parse:text];
	if (expression == nil) {
		return;
	}
	id actual = [expression valueWithVariables:variables];
	id wanted = [[self parse:expected] valueWithVariables:@{}];
	UDFeelExpression *same = [self parse:@"actual = wanted"];
	id equal = [same valueWithVariables:@{ @"actual": actual, @"wanted": wanted }];
	XCTAssertEqualObjects(equal, @YES, @"%@ is %@, not %@", text, actual, expected);
}

- (void)check:(NSString *)text is:(NSString *)expected
{
	[self check:text is:expected variables:@{}];
}

- (void)testArithmeticIsDecimal
{
	[self check:@"1 + 2" is:@"3"];
	[self check:@"0.1 + 0.2" is:@"0.3"];
	XCTAssertEqualObjects([[[self parse:@"0.1 + 0.2"] valueWithVariables:@{}] description], @"0.3");
	[self check:@"10 / 4" is:@"2.5"];
	[self check:@"7 - 2 - 1" is:@"4"];
	[self check:@"2 * 3 + 4" is:@"10"];
	[self check:@"2 * (3 + 4)" is:@"14"];
	[self check:@"2 ** 10" is:@"1024"];
	[self check:@"2 ** -1" is:@"0.5"];
	[self check:@"-2 ** 2" is:@"-4"];
	[self check:@"(-2) ** 2" is:@"4"];
	[self check:@"amount * 2" is:@"42" variables:@{ @"amount": @21 }];
	[self check:@"rate * 3" is:@"0.3" variables:@{ @"rate": @0.1 }];
	[self check:@"\"a\" + \"b\"" is:@"\"ab\""];
	/* Errors are null. */
	[self check:@"1 / 0" is:@"null"];
	[self check:@"1 + \"a\"" is:@"null"];
	[self check:@"missing + 1" is:@"null"];
	[self check:@"-\"a\"" is:@"null"];
}

- (void)testComparisons
{
	[self check:@"1 < 2" is:@"true"];
	[self check:@"2 <= 2" is:@"true"];
	[self check:@"\"a\" < \"b\"" is:@"true"];
	[self check:@"amount > 1000" is:@"true" variables:@{ @"amount": @1500 }];
	[self check:@"1 = 1.0" is:@"true"];
	[self check:@"1 = \"1\"" is:@"null"];
	[self check:@"null = null" is:@"true"];
	[self check:@"missing = null" is:@"true"];
	[self check:@"1 != null" is:@"true"];
	[self check:@"1 < null" is:@"null"];
	[self check:@"true < false" is:@"null"];
	[self check:@"[1, 2] = [1, 2]" is:@"true"];
	[self check:@"[1, 2] = [2, 1]" is:@"false"];
	[self check:@"{a: 1} = {a: 1}" is:@"true"];
	NSDate *earlier = [NSDate dateWithTimeIntervalSince1970:0];
	[self check:@"a < b" is:@"true" variables:@{ @"a": earlier, @"b": [NSDate date] }];
}

- (void)testLogicHasThreeValues
{
	[self check:@"true and null" is:@"null"];
	[self check:@"false and null" is:@"false"];
	[self check:@"null and false" is:@"false"];
	[self check:@"true or null" is:@"true"];
	[self check:@"null or false" is:@"null"];
	[self check:@"true and 1" is:@"null"];
	[self check:@"not(true)" is:@"false"];
	[self check:@"not(1)" is:@"null"];
	[self check:@"a > 1 and b = \"x\"" is:@"true" variables:@{ @"a": @2, @"b": @"x" }];
}

- (void)testBetweenInAndRanges
{
	[self check:@"5 between 1 and 10" is:@"true"];
	[self check:@"11 between 1 and 10" is:@"false"];
	[self check:@"5 in [1..10]" is:@"true"];
	[self check:@"10 in [1..10)" is:@"false"];
	[self check:@"10 in [1..10[" is:@"false"];
	[self check:@"0 in (0..1]" is:@"false"];
	[self check:@"5 in (1..5)" is:@"false"];
	[self check:@"5 in ]1..5]" is:@"true"];
	[self check:@"3 in (1, 2, 3)" is:@"true"];
	[self check:@"3 in (< 2, > 2)" is:@"true"];
	[self check:@"3 in < 3" is:@"false"];
	[self check:@"\"b\" in [\"a\", \"b\"]" is:@"true"];
	[self check:@"\"c\" in [\"a\", \"b\"]" is:@"false"];
	[self check:@"x in [1..10]" is:@"null"];
}

- (void)testTextualForms
{
	[self check:@"if x > 1 then \"big\" else \"small\"" is:@"\"big\"" variables:@{ @"x": @2 }];
	[self check:@"if null then 1 else 2" is:@"2"];
	[self check:@"for i in [1, 2, 3] return i * 2" is:@"[2, 4, 6]"];
	[self check:@"for i in 1..3 return i" is:@"[1, 2, 3]"];
	[self check:@"for i in 3..1 return i" is:@"[3, 2, 1]"];
	[self check:@"for x in [1, 2], y in [10, 20] return x + y" is:@"[11, 21, 12, 22]"];
	[self check:@"some x in [1, 5] satisfies x > 4" is:@"true"];
	[self check:@"every x in [1, 5] satisfies x > 4" is:@"false"];
	[self check:@"every x in [] satisfies x > 4" is:@"true"];
}

- (void)testListsContextsPathsAndFilters
{
	[self check:@"[1, 2, 3][2]" is:@"2"];
	[self check:@"[1, 2, 3][-1]" is:@"3"];
	[self check:@"[1, 2, 3][5]" is:@"null"];
	[self check:@"[1, 2, 3, 4][item > 2]" is:@"[3, 4]"];
	[self check:@"{a: 1, b: a + 1}.b" is:@"2"];
	[self check:@"{\"first name\": \"Ann\"}.first" is:@"null"];
	[self check:@"[{a: 1}, {a: 2}].a" is:@"[1, 2]"];
	NSDictionary *order = @{
		@"customer": @{ @"address": @{ @"city": @"Almaty" } },
		@"lines": @[ @{ @"sku": @"a", @"amount": @5 }, @{ @"sku": @"b", @"amount": @50 } ]
	};
	[self check:@"customer.address.city" is:@"\"Almaty\"" variables:order];
	[self check:@"lines[amount > 10].sku" is:@"[\"b\"]" variables:order];
	[self check:@"sum(lines.amount)" is:@"55" variables:order];
	[self check:@"count(lines[amount > 100])" is:@"0" variables:order];
	[self check:@"customer.missing.city" is:@"null" variables:order];
}

- (void)testBuiltinFunctions
{
	[self check:@"string length(\"abc\")" is:@"3"];
	[self check:@"upper case(\"ab\")" is:@"\"AB\""];
	[self check:@"lower case(\"AB\")" is:@"\"ab\""];
	[self check:@"substring(\"hello\", 2, 3)" is:@"\"ell\""];
	[self check:@"substring(\"hello\", -2)" is:@"\"lo\""];
	[self check:@"substring before(\"a-b\", \"-\")" is:@"\"a\""];
	[self check:@"substring after(\"a-b\", \"-\")" is:@"\"b\""];
	[self check:@"contains(\"abc\", \"b\")" is:@"true"];
	[self check:@"starts with(\"abc\", \"ab\")" is:@"true"];
	[self check:@"ends with(\"abc\", \"ab\")" is:@"false"];
	[self check:@"string join([\"a\", \"b\"], \", \")" is:@"\"a, b\""];
	[self check:@"string(1.50)" is:@"\"1.5\""];
	[self check:@"number(\"1.5\") + 1" is:@"2.5"];
	[self check:@"number(\"x\")" is:@"null"];
	[self check:@"count([1, 2])" is:@"2"];
	[self check:@"sum([1, 2, 3])" is:@"6"];
	[self check:@"mean([1, 2, 3, 4])" is:@"2.5"];
	[self check:@"min(3, 1, 2)" is:@"1"];
	[self check:@"max([1, 3])" is:@"3"];
	[self check:@"product([2, 3])" is:@"6"];
	[self check:@"all([true, true])" is:@"true"];
	[self check:@"all([true, false, null])" is:@"false"];
	[self check:@"any([false, null])" is:@"null"];
	[self check:@"append([1], 2)" is:@"[1, 2]"];
	[self check:@"concatenate([1], [2, 3])" is:@"[1, 2, 3]"];
	[self check:@"list contains([1, 2], 2)" is:@"true"];
	[self check:@"index of([1, 2, 1], 1)" is:@"[1, 3]"];
	[self check:@"distinct values([1, 1, 2])" is:@"[1, 2]"];
	[self check:@"flatten([1, [2, [3]]])" is:@"[1, 2, 3]"];
	[self check:@"reverse([1, 2])" is:@"[2, 1]"];
	[self check:@"sublist([1, 2, 3], 2)" is:@"[2, 3]"];
	[self check:@"floor(1.5)" is:@"1"];
	[self check:@"floor(-1.5)" is:@"-2"];
	[self check:@"ceiling(-1.5)" is:@"-1"];
	[self check:@"decimal(2.345, 2)" is:@"2.34"];
	[self check:@"abs(-3)" is:@"3"];
	[self check:@"modulo(-7, 3)" is:@"2"];
	[self check:@"modulo(7, -3)" is:@"-2"];
	[self check:@"odd(3)" is:@"true"];
	[self check:@"even(3)" is:@"false"];
	[self check:@"string length(1)" is:@"null"];
	XCTAssertTrue([[[self parse:@"now()"] valueWithVariables:@{}] isKindOfClass:[NSDate class]]);
}

/* What an expression prints as, and that the printed text parses back to
 * the same thing. */
- (void)testExpressionsPrintAsCanonicalFeel
{
	NSDictionary *cases = @{
		@"(1 + 2) * 3": @"(1 + 2) * 3",
		@"1 + (2 * 3)": @"1 + 2 * 3",
		@"a - (b - c)": @"a - (b - c)",
		@"(a - b) - c": @"a - b - c",
		@"-(2 ** 2)": @"-2 ** 2",
		@"(-2) ** 2": @"(-2) ** 2",
		@"(a or b) and c": @"(a or b) and c",
		@"a or (b and c)": @"a or b and c",
		@"not(a)   or b": @"not(a) or b",
		@"x in (1..5)": @"x in (1..5)",
		@"x in ((1 + 1))": @"x in 1 + 1",
		@"x in (< 1, [2..3], \"a\")": @"x in (< 1, [2..3], \"a\")",
		@"x between 1 and 2": @"x between 1 and 2",
		@"if a then b else c": @"if a then b else c",
		@"for i in 1..3 return i": @"for i in [1..3] return i",
		@"some x in xs satisfies x > 1": @"some x in xs satisfies x > 1",
		@"[1,2][item>1]": @"[1, 2][item > 1]",
		@"{a:1, \"b c\": \"x\\\"y\"}": @"{a: 1, \"b c\": \"x\\\"y\"}",
		@"string length( \"x\" )": @"string length(\"x\")",
		@"customer.address.city // where it goes": @"customer.address.city",
		@"]1..2[": @"(1..2)",
	};
	for (NSString *text in cases) {
		NSString *printed = [[self parse:text] expressionString];
		XCTAssertEqualObjects(printed, [cases objectForKey:text], @"%@", text);
		if (printed != nil) {
			XCTAssertEqualObjects([[self parse:printed] expressionString], printed, @"%@", text);
		}
	}
}

- (void)testCamunda7SubsetBecomesFeel
{
	NSDictionary *cases = @{
		@"amount > 1000 && approved": @"amount > 1000 and approved",
		@"a == 'x' || !b": @"a = \"x\" or not(b)",
		@"a eq 1 and b ne 2": @"a = 1 and b != 2",
		@"x gt 1 or not y": @"x > 1 or not(y)",
		@"customer.vip == true": @"customer.vip = true",
		@"nrOfCompletedInstances/nrOfInstances >= 0.6": @"nrOfCompletedInstances / nrOfInstances >= 0.6",
		@"(a + 1) * 2 - b": @"(a + 1) * 2 - b",
	};
	for (NSString *text in cases) {
		NSError *error = nil;
		UDFeelExpression *expression = [UDFeelExpression expressionWithCamunda7String:text error:&error];
		XCTAssertNotNil(expression, @"%@: %@", text, error);
		XCTAssertEqualObjects([expression expressionString], [cases objectForKey:text], @"%@", text);
	}
	UDFeelExpression *condition =
		[UDFeelExpression expressionWithCamunda7String:@"amount > 1000 && approved" error:NULL];
	NSDictionary *approved = @{ @"amount": @2000, @"approved": @YES };
	NSDictionary *declined = @{ @"amount": @2000, @"approved": @NO };
	XCTAssertTrue([condition evaluateWithVariables:approved error:NULL]);
	XCTAssertFalse([condition evaluateWithVariables:declined error:NULL]);
	XCTAssertEqualObjects([[UDFeelExpression expressionWithCamunda7String:@"3/5" error:NULL]
		valueWithVariables:@{}], [NSDecimalNumber decimalNumberWithString:@"0.6"
		locale:@{ NSDecimalSeparator: @"." }]);
	/* Only the subset: no lists, no textual forms, no calls, no %. */
	for (NSString *text in @[ @"[1, 2]", @"if a then b else c", @"size(list) > 1", @"a ? b : c",
	                          @"a % 2 == 0" ]) {
		XCTAssertNil([UDFeelExpression expressionWithCamunda7String:text error:NULL], @"%@", text);
	}
}

- (void)testMistakesAreReportedWithWhereTheyAre
{
	NSDictionary *cases = @{
		@"1 +": @"at 4",
		@"foo(1)": @"a function FEEL has",
		@"(1": @"')'",
		@"\"abc": @"a value",
		@"a b": @"the end",
		@"": @"an expression",
		@"if a then b": @"'else'",
		@"x in (1..": @"a value",
	};
	for (NSString *text in cases) {
		NSError *error = nil;
		XCTAssertNil([UDFeelExpression expressionWithString:text error:&error], @"%@", text);
		XCTAssertEqual([error code], (NSInteger)UDWorkflowErrorCondition, @"%@", text);
		XCTAssertTrue([[error localizedDescription] rangeOfString:[cases objectForKey:text]].location
			!= NSNotFound, @"%@: %@", text, [error localizedDescription]);
	}
}

- (void)testConditionsNeedABoolean
{
	NSError *error = nil;
	UDFeelExpression *amount = [self parse:@"amount"];
	XCTAssertFalse([amount evaluateWithVariables:@{ @"amount": @5 } error:&error]);
	XCTAssertEqual([error code], (NSInteger)UDWorkflowErrorCondition);
	error = nil;
	/* No truth is not an error: the flow is just not taken. */
	XCTAssertFalse([[self parse:@"amount > 5"] evaluateWithVariables:@{} error:&error]);
	XCTAssertNil(error);
}

@end

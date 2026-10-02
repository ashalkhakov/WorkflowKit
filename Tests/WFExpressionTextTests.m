#import "WFTestCase.h"

/* Expressions as an editor shows them: tokens to colour, and where the
 * engine stops reading. */
@interface WFExpressionTextTests : WFTestCase
@end

@implementation WFExpressionTextTests

/* Each token as kind:text. */
- (NSArray *)tokens:(NSString *)text place:(WFExpressionPlace)place
{
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *token in [WFFeelExpression tokensOfText:text place:place]) {
		NSRange range = [[token objectForKey:@"range"] rangeValue];
		[out addObject:[NSString stringWithFormat:@"%@:%@", [token objectForKey:@"kind"], [text substringWithRange:range]]];
	}
	return out;
}

- (void)testFEELIsColouredByWhatEachTokenIs
{
	XCTAssertEqualObjects([self tokens:@"amount > 10 and approved" place:WFExpressionPlaceExpression],
		(@[ @"name:amount", @"operator:>", @"number:10", @"keyword:and", @"name:approved" ]));
	XCTAssertEqualObjects([self tokens:@"if x in [1..5] then \"low\" else null" place:WFExpressionPlaceExpression],
		(@[ @"keyword:if", @"name:x", @"keyword:in", @"punctuation:[", @"number:1", @"operator:..", @"number:5",
		    @"punctuation:]", @"keyword:then", @"string:\"low\"", @"keyword:else", @"keyword:null" ]));
}

- (void)testFunctionsTemporalsAndComments
{
	XCTAssertEqualObjects([self tokens:@"string length(name) // how long" place:WFExpressionPlaceExpression],
		(@[ @"function:string length", @"punctuation:(", @"name:name", @"punctuation:)", @"comment:// how long" ]));
	XCTAssertEqualObjects([self tokens:@"sum(prices) > @\"P1D\"" place:WFExpressionPlaceExpression],
		(@[ @"function:sum", @"punctuation:(", @"name:prices", @"punctuation:)", @"operator:>",
		    @"temporal:@\"P1D\"" ]));
}

- (void)testCamunda7IsReadInsideItsDelimiters
{
	XCTAssertEqualObjects([self tokens:@"${amount >= 1000 && kind != 'rush'}" place:WFExpressionPlaceExpression],
		(@[ @"delimiter:${", @"name:amount", @"operator:>=", @"number:1000", @"operator:&&", @"name:kind",
		    @"operator:!=", @"string:'rush'", @"delimiter:}" ]));
	XCTAssertEqualObjects([self tokens:@"${approved eq true}" place:WFExpressionPlaceExpression],
		(@[ @"delimiter:${", @"name:approved", @"keyword:eq", @"keyword:true", @"delimiter:}" ]));
}

- (void)testAnAttributeIsLiteralUnlessMarked
{
	XCTAssertEqualObjects([self tokens:@"alice" place:WFExpressionPlaceAttribute], @[]);
	XCTAssertNil([WFFeelExpression problemInText:@"not ( an expression" place:WFExpressionPlaceAttribute]);
	XCTAssertEqualObjects([self tokens:@"${initiator}" place:WFExpressionPlaceAttribute],
		(@[ @"delimiter:${", @"name:initiator", @"delimiter:}" ]));
	XCTAssertEqualObjects([self tokens:@"=owner.name" place:WFExpressionPlaceAttribute],
		(@[ @"delimiter:=", @"name:owner", @"punctuation:.", @"name:name" ]));
}

- (void)testAStringBeingTypedIsAString
{
	XCTAssertEqualObjects([self tokens:@"name = \"Al" place:WFExpressionPlaceExpression],
		(@[ @"name:name", @"operator:=", @"string:\"Al" ]));
}

/* Where the engine stops, in the text as written: the token it did not
 * expect, or the last character when the text ends too soon. */
- (void)testAProblemSaysWhere
{
	XCTAssertNil([WFFeelExpression problemInText:@"amount > 10" place:WFExpressionPlaceExpression]);
	NSError *error = [WFFeelExpression problemInText:@"amount > " place:WFExpressionPlaceExpression];
	XCTAssertNotNil(error);
	XCTAssertEqual([[[error userInfo] objectForKey:WFErrorRangeKey] rangeValue].location, (NSUInteger)8);
	error = [WFFeelExpression problemInText:@"${amount > )}" place:WFExpressionPlaceExpression];
	NSRange range = [[[error userInfo] objectForKey:WFErrorRangeKey] rangeValue];
	XCTAssertEqualObjects([@"${amount > )}" substringWithRange:range], @")", @"%@", error);
	XCTAssertEqualObjects([error localizedDescription], @"expected a value, found ')'");
	error = [WFFeelExpression problemInText:@"=a +* b" place:WFExpressionPlaceAttribute];
	range = [[[error userInfo] objectForKey:WFErrorRangeKey] rangeValue];
	XCTAssertEqualObjects([@"=a +* b" substringWithRange:range], @"*", @"%@", error);
	/* What the reader refuses, the editor says too. */
	XCTAssertNotNil([WFFeelExpression problemInText:@"${order.total()}" place:WFExpressionPlaceExpression]);
}

@end

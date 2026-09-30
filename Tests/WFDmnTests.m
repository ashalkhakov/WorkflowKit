#import "WFTestCase.h"

/* Decisions read and evaluated on their own: no engine, no store. */
@interface WFDmnTests : WFTestCase
@end

/* A DMN 1.3 document around the decisions' XML. */
static NSString *
WFDmnDocument(NSString *decisions)
{
	return [NSString stringWithFormat:
		@"<definitions xmlns=\"https://www.omg.org/spec/DMN/20191111/MODEL/\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/dmn\" id=\"d\" name=\"D\" namespace=\"n\">%@</definitions>",
		decisions];
}

/* A decision table: inputs as @[label, expression, typeRef], outputs as
 * @[name, typeRef], rules as arrays of entries, inputs' then outputs'. */
static NSString *
WFDmnTable(NSString *key, NSString *hitPolicy, NSArray *inputs, NSArray *outputs, NSArray *rules)
{
	NSMutableString *xml = [NSMutableString stringWithFormat:@"<decision id=\"%@\" name=\"%@\"><decisionTable id=\"t_%@\"%@>",
		key, key, key, hitPolicy != nil ? [NSString stringWithFormat:@" %@", hitPolicy] : @""];
	NSUInteger n = 0;
	for (NSArray *input in inputs) {
		NSString *type = [input count] > 2 ? [NSString stringWithFormat:@" typeRef=\"%@\"", [input objectAtIndex:2]] : @"";
		[xml appendFormat:@"<input id=\"in%lu\" label=\"%@\"><inputExpression id=\"ie%lu\"%@><text>%@</text></inputExpression></input>",
			(unsigned long)n, [input objectAtIndex:0], (unsigned long)n, type, [input objectAtIndex:1]];
		n++;
	}
	n = 0;
	for (NSArray *output in outputs) {
		NSString *type = [output count] > 1 ? [NSString stringWithFormat:@" typeRef=\"%@\"", [output objectAtIndex:1]] : @"";
		[xml appendFormat:@"<output id=\"out%lu\" name=\"%@\"%@/>", (unsigned long)n++, [output objectAtIndex:0], type];
	}
	n = 0;
	for (NSArray *rule in rules) {
		[xml appendFormat:@"<rule id=\"r%lu\">", (unsigned long)++n];
		for (NSUInteger i = 0; i < [rule count]; i++) {
			NSString *tag = i < [inputs count] ? @"inputEntry" : @"outputEntry";
			[xml appendFormat:@"<%@ id=\"e%lu_%lu\"><text>%@</text></%@>", tag, (unsigned long)n, (unsigned long)i,
				[rule objectAtIndex:i], tag];
		}
		[xml appendString:@"</rule>"];
	}
	[xml appendString:@"</decisionTable></decision>"];
	return xml;
}

@implementation WFDmnTests

- (WFDecisionDefinition *)decision:(NSString *)key in:(NSString *)decisions
{
	NSError *error = nil;
	NSArray *parsed = [WFDmnReader decisionsFromXMLString:WFDmnDocument(decisions) error:&error];
	XCTAssertNotNil(parsed, @"%@", error);
	for (WFDecisionDefinition *decision in parsed) {
		if ([decision.key isEqualToString:key]) {
			return decision;
		}
	}
	XCTFail(@"no decision %@", key);
	return nil;
}

- (NSArray *)results:(WFDecisionDefinition *)decision variables:(NSDictionary *)variables
{
	NSError *error = nil;
	WFDecisionResult *result = [decision evaluateWithVariables:variables inputs:nil error:&error];
	XCTAssertNotNil(result, @"%@", error);
	return result.resultList;
}

- (NSString *)failure:(WFDecisionDefinition *)decision variables:(NSDictionary *)variables
{
	NSError *error = nil;
	XCTAssertNil([decision evaluateWithVariables:variables inputs:nil error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorDecision, @"%@", error);
	return [error localizedDescription];
}

- (void)testInputEntriesAreUnaryTests
{
	WFDecisionDefinition *discount = [self decision:@"discount" in:WFDmnTable(@"discount", @"hitPolicy=\"FIRST\"",
		@[ @[ @"Amount", @"amount", @"double" ], @[ @"Tier", @"customer.tier", @"string" ] ],
		@[ @[ @"rate" ] ],
		@[ @[ @"&lt; 0", @"-", @"\"refused\"" ],
		   @[ @"-", @"not(\"gold\", \"platinum\")", @"0" ],
		   @[ @"[0..100)", @"-", @"5" ],
		   @[ @"(100..1000]", @"\"gold\",\"platinum\"", @"10" ],
		   @[ @"&gt;= limit", @"", @"20" ] ])];
	NSDictionary *expected = @{ @-1: @"refused", @50: @0, @2000: @0 };
	for (NSNumber *amount in expected) {
		NSArray *bronze = [self results:discount variables:@{ @"amount": amount, @"customer": @{ @"tier": @"bronze" } }];
		XCTAssertEqualObjects([[bronze firstObject] objectForKey:@"rate"], [expected objectForKey:amount], @"%@", amount);
	}
	NSArray *gold = [self results:discount variables:@{ @"amount": @100, @"customer": @{ @"tier": @"gold" }, @"limit": @90 }];
	XCTAssertEqualObjects([[gold firstObject] objectForKey:@"rate"], @20);
	gold = [self results:discount variables:@{ @"amount": @101, @"customer": @{ @"tier": @"gold" }, @"limit": @5000 }];
	XCTAssertEqualObjects([[gold firstObject] objectForKey:@"rate"], @10);
	/* Nothing matches: no result. */
	gold = [self results:discount variables:@{ @"amount": @2000, @"customer": @{ @"tier": @"gold" }, @"limit": @5000 }];
	XCTAssertEqual([gold count], (NSUInteger)0);
}

- (void)testHitPolicies
{
	NSArray *inputs = @[ @[ @"Score", @"score" ] ];
	NSArray *outputs = @[ @[ @"flag" ] ];
	NSArray *rules = @[ @[ @"&gt; 10", @"\"high\"" ], @[ @"&gt; 5", @"\"medium\"" ], @[ @"-", @"\"any\"" ] ];
	NSDictionary *score = @{ @"score": @12 };

	WFDecisionDefinition *unique = [self decision:@"u" in:WFDmnTable(@"u", nil, inputs, outputs, rules)];
	XCTAssertTrue([[self failure:unique variables:score] rangeOfString:@"UNIQUE"].location != NSNotFound);
	XCTAssertEqualObjects([self results:unique variables:@{ @"score": @1 }], (@[ @{ @"flag": @"any" } ]));

	WFDecisionDefinition *first = [self decision:@"f" in:WFDmnTable(@"f", @"hitPolicy=\"FIRST\"", inputs, outputs, rules)];
	XCTAssertEqualObjects([self results:first variables:score], (@[ @{ @"flag": @"high" } ]));

	WFDecisionDefinition *order = [self decision:@"o" in:WFDmnTable(@"o", @"hitPolicy=\"RULE ORDER\"", inputs, outputs, rules)];
	XCTAssertEqualObjects([[self results:order variables:score] valueForKey:@"flag"], (@[ @"high", @"medium", @"any" ]));

	WFDecisionDefinition *collect = [self decision:@"c" in:WFDmnTable(@"c", @"hitPolicy=\"COLLECT\"", inputs, outputs, rules)];
	XCTAssertEqual([[self results:collect variables:score] count], (NSUInteger)3);

	NSArray *same = @[ @[ @"&gt; 10", @"\"yes\"" ], @[ @"&gt; 5", @"\"yes\"" ] ];
	WFDecisionDefinition *any = [self decision:@"a" in:WFDmnTable(@"a", @"hitPolicy=\"ANY\"", inputs, outputs, same)];
	XCTAssertEqualObjects([self results:any variables:score], (@[ @{ @"flag": @"yes" } ]));
	WFDecisionDefinition *differing = [self decision:@"a2" in:WFDmnTable(@"a2", @"hitPolicy=\"ANY\"", inputs, outputs, rules)];
	XCTAssertTrue([[self failure:differing variables:score] rangeOfString:@"ANY"].location != NSNotFound);
}

- (void)testCollectAggregations
{
	NSArray *inputs = @[ @[ @"Item", @"item" ] ];
	NSArray *rules = @[ @[ @"\"a\",\"b\"", @"3" ], @[ @"\"a\"", @"4" ], @[ @"\"b\"", @"10" ] ];
	NSDictionary *expected = @{ @"SUM": @7, @"MIN": @3, @"MAX": @4, @"COUNT": @2 };
	for (NSString *aggregation in expected) {
		NSString *policy = [NSString stringWithFormat:@"hitPolicy=\"COLLECT\" aggregation=\"%@\"", aggregation];
		WFDecisionDefinition *decision = [self decision:@"sum"
			in:WFDmnTable(@"sum", policy, inputs, @[ @[ @"points", @"integer" ] ], rules)];
		NSArray *results = [self results:decision variables:@{ @"item": @"a" }];
		XCTAssertEqualObjects([[results firstObject] objectForKey:@"points"], [expected objectForKey:aggregation],
			@"%@", aggregation);
		/* No rule matches: a count is 0, the others give nothing. */
		results = [self results:decision variables:@{ @"item": @"z" }];
		if ([aggregation isEqualToString:@"COUNT"]) {
			XCTAssertEqualObjects(results, (@[ @{ @"points": @0 } ]));
		} else {
			XCTAssertEqual([results count], (NSUInteger)0, @"%@", aggregation);
		}
	}
}

- (void)testTypeRefs
{
	WFDecisionDefinition *typed = [self decision:@"typed" in:WFDmnTable(@"typed", @"hitPolicy=\"FIRST\"",
		@[ @[ @"Due", @"due", @"date" ] ],
		@[ @[ @"days", @"integer" ], @[ @"label", @"string" ], @[ @"ratio", @"double" ] ],
		@[ @[ @"&lt; date and time(\"2030-01-01T00:00:00Z\")", @"2.0", @"42", @"1/4" ],
		   @[ @"-", @"2.5", @"\"late\"", @"1" ] ])];
	NSDictionary *early = [[self results:typed variables:@{ @"due": @"2029-06-01T00:00:00Z" }] firstObject];
	XCTAssertEqualObjects([early objectForKey:@"days"], @2);
	XCTAssertEqualObjects([early objectForKey:@"label"], @"42");
	XCTAssertEqualWithAccuracy([[early objectForKey:@"ratio"] doubleValue], 0.25, 1e-9);
	/* 2.5 is not a whole number of days. */
	XCTAssertTrue([[self failure:typed variables:@{ @"due": [NSDate dateWithTimeIntervalSince1970:2e9] }]
		rangeOfString:@"integer"].location != NSNotFound);
	/* Nor is text a date. */
	[self failure:typed variables:@{ @"due": @"soon" }];
}

- (void)testRequiredDecisionsAndLiteralExpressions
{
	NSString *season = WFDmnTable(@"season", nil, @[ @[ @"Month", @"month" ] ], @[ @[ @"season" ] ],
		@[ @[ @"[3..5]", @"\"spring\"" ], @[ @"[6..8]", @"\"summer\"" ], @[ @"not([3..8])", @"\"cold\"" ] ]);
	NSString *dish = [WFDmnTable(@"dish", nil, @[ @[ @"Season", @"season" ], @[ @"Guests", @"guests" ] ],
		@[ @[ @"dish" ] ],
		@[ @[ @"\"summer\"", @"&lt; 8", @"\"salad\"" ], @[ @"\"summer\"", @"&gt;= 8", @"\"barbecue\"" ],
		   @[ @"\"spring\",\"cold\"", @"-", @"\"stew\"" ] ])
		stringByReplacingOccurrencesOfString:@"<decisionTable"
		withString:@"<informationRequirement id=\"ir\"><requiredDecision href=\"#season\"/></informationRequirement><decisionTable"];
	NSString *greeting = @"<decision id=\"greeting\" name=\"Greeting\">"
		@"<informationRequirement id=\"ir2\"><requiredDecision href=\"#dish\"/></informationRequirement>"
		@"<variable id=\"v\" name=\"text\" typeRef=\"string\"/>"
		@"<literalExpression id=\"le\"><text>\"Tonight: \" + dish</text></literalExpression></decision>";
	NSString *all = [@[ season, dish, greeting ] componentsJoinedByString:@""];
	WFDecisionDefinition *decision = [self decision:@"greeting" in:all];
	XCTAssertEqualObjects(decision.requiredDecisionKeys, @[ @"dish" ]);
	XCTAssertEqualObjects([self results:decision variables:(@{ @"month": @7, @"guests": @10 })],
		(@[ @{ @"text": @"Tonight: barbecue" } ]));
	XCTAssertEqualObjects([self results:decision variables:(@{ @"month": @12, @"guests": @2 })],
		(@[ @{ @"text": @"Tonight: stew" } ]));

	NSError *error = nil;
	NSString *circular = [season stringByReplacingOccurrencesOfString:@"<decisionTable"
		withString:@"<informationRequirement id=\"ir3\"><requiredDecision href=\"#dish\"/></informationRequirement><decisionTable"];
	XCTAssertNil([WFDmnReader decisionsFromXMLString:WFDmnDocument([circular stringByAppendingString:dish]) error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"requires itself"].location != NSNotFound, @"%@", error);
	XCTAssertNil([WFDmnReader decisionsFromXMLString:WFDmnDocument(dish) error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"does not define"].location != NSNotFound, @"%@", error);
}

- (void)testResultMappings
{
	WFDecisionResult *two = [[WFDecisionResult alloc] initWithResultList:@[ @{ @"a": @1, @"b": @2 }, @{ @"a": @3 } ]];
	NSError *error = nil;
	XCTAssertNil([two singleResult:&error]);
	XCTAssertNotNil(error);
	XCTAssertEqualObjects([two collectEntries:@"a"], (@[ @1, @3 ]));
	WFDecisionResult *one = [[WFDecisionResult alloc] initWithResultList:@[ @{ @"a": @1, @"b": @2 } ]];
	error = nil;
	XCTAssertNil([one singleEntry:&error]);
	XCTAssertNotNil(error);
	XCTAssertEqualObjects([[[WFDecisionResult alloc] initWithResultList:@[ @{ @"a": @1 } ]] singleEntry:NULL], @1);
	XCTAssertNil([[[WFDecisionResult alloc] initWithResultList:@[]] singleResult:NULL]);
}

- (void)testReadsCamundaDmn
{
	NSError *error = nil;
	/* DMN 1.1, as older Camunda Modelers write it, with camunda:inputVariable
	 * and a Camunda 7 expression. */
	NSString *old =
		@"<definitions xmlns=\"http://www.omg.org/spec/DMN/20151101/dmn.xsd\" "
		 @"xmlns:camunda=\"http://camunda.org/schema/1.0/dmn\" id=\"d\" name=\"D\" namespace=\"n\">"
		 @"<decision id=\"check\" name=\"Check\" camunda:versionTag=\"2\"><decisionTable id=\"t\">"
		 @"<input id=\"i\" label=\"Amount\" camunda:inputVariable=\"value\">"
		 @"<inputExpression id=\"ie\" typeRef=\"long\"><text>${order.amount}</text></inputExpression></input>"
		 @"<output id=\"o\" name=\"ok\" typeRef=\"boolean\"/>"
		 @"<rule id=\"r1\"><inputEntry id=\"a\"><text>value &lt;= cap</text></inputEntry>"
		 @"<outputEntry id=\"b\"><text>true</text></outputEntry></rule>"
		 @"<rule id=\"r2\"><inputEntry id=\"c\"><text>&gt; cap</text></inputEntry>"
		 @"<outputEntry id=\"d\"><text>false</text></outputEntry></rule>"
		 @"</decisionTable></decision></definitions>";
	WFDecisionDefinition *check = [[WFDmnReader decisionsFromXMLString:old error:&error] firstObject];
	XCTAssertNotNil(check, @"%@", error);
	XCTAssertEqualObjects(check.versionTag, @"2");
	XCTAssertEqualObjects(check.table.inputs.firstObject.inputVariable, @"value");
	XCTAssertEqualObjects([self results:check variables:(@{ @"order": @{ @"amount": @50 }, @"cap": @100 })],
		(@[ @{ @"ok": @YES } ]));

	NSDictionary *refused = @{
		@"hitPolicy=\"PRIORITY\"": @"PRIORITY",
		@"hitPolicy=\"FIRST\" aggregation=\"SUM\"": @"aggregation",
	};
	for (NSString *policy in refused) {
		NSString *xml = WFDmnDocument(WFDmnTable(@"x", policy, @[ @[ @"A", @"a" ] ], @[ @[ @"b" ] ], @[ @[ @"-", @"1" ] ]));
		XCTAssertNil([WFDmnReader decisionsFromXMLString:xml error:&error], @"%@", policy);
		XCTAssertTrue([[error localizedDescription] rangeOfString:[refused objectForKey:policy]].location != NSNotFound,
			@"%@", error);
	}
	NSString *javascript = [WFDmnDocument(WFDmnTable(@"x", nil, @[ @[ @"A", @"a" ] ], @[ @[ @"b" ] ], @[ @[ @"-", @"1" ] ]))
		stringByReplacingOccurrencesOfString:@"<inputExpression id=\"ie0\""
		withString:@"<inputExpression id=\"ie0\" expressionLanguage=\"javascript\""];
	XCTAssertNil([WFDmnReader decisionsFromXMLString:javascript error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"javascript"].location != NSNotFound, @"%@", error);
	XCTAssertNil([WFDmnReader decisionsFromXMLString:@"<definitions xmlns=\"urn:other\"/>" error:&error]);
	XCTAssertEqual([error code], (NSInteger)WFErrorInvalidDmn);
}

@end

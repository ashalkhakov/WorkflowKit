#import "WFFeelInternal.h"

#pragma mark - Nodes

static NSString *
WFFeelOperatorText(WFFeelOperator op)
{
	switch (op) {
	case WFFeelOperatorOr: return @"or";
	case WFFeelOperatorAnd: return @"and";
	case WFFeelOperatorEqual: return @"=";
	case WFFeelOperatorNotEqual: return @"!=";
	case WFFeelOperatorLess: return @"<";
	case WFFeelOperatorLessOrEqual: return @"<=";
	case WFFeelOperatorGreater: return @">";
	case WFFeelOperatorGreaterOrEqual: return @">=";
	case WFFeelOperatorAdd: return @"+";
	case WFFeelOperatorSubtract: return @"-";
	case WFFeelOperatorMultiply: return @"*";
	case WFFeelOperatorDivide: return @"/";
	case WFFeelOperatorPower: return @"**";
	/* Only ever a call, modulo(a, b); the parser makes no such operator. */
	case WFFeelOperatorModulo:
	case WFFeelOperatorNone: break;
	}
	return @"?";
}

static BOOL
WFFeelIsComparison(WFFeelOperator op)
{
	return op >= WFFeelOperatorEqual && op <= WFFeelOperatorGreaterOrEqual;
}

/* Words that cannot be a variable's name, because the grammar reads them. */
static BOOL
WFFeelIsReserved(NSString *word)
{
	static NSSet *words = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		words = [NSSet setWithObjects:@"true", @"false", @"null", @"if", @"then", @"else",
			@"for", @"in", @"return", @"some", @"every", @"satisfies", @"and", @"or",
			@"between", @"instance", @"of", @"function", nil];
	});
	return [words containsObject:word];
}

@implementation WFFeelNode

+ (instancetype)node:(WFFeelNodeKind)kind
{
	WFFeelNode *node = [[self alloc] init];
	node.kind = kind;
	node.children = @[];
	return node;
}

+ (instancetype)literal:(id)value
{
	WFFeelNode *node = [self node:WFFeelNodeLiteral];
	node.value = value ?: [NSNull null];
	return node;
}

+ (instancetype)binary:(WFFeelOperator)op left:(WFFeelNode *)left right:(WFFeelNode *)right
{
	WFFeelNode *node = [self node:WFFeelNodeBinary];
	node.op = op;
	node.children = @[ left, right ];
	return node;
}

- (NSInteger)precedence
{
	switch (self.kind) {
	case WFFeelNodeIf:
	case WFFeelNodeFor:
	case WFFeelNodeSome:
	case WFFeelNodeEvery:
		return 1;
	case WFFeelNodeBetween:
	case WFFeelNodeIn:
		return 4;
	case WFFeelNodeNegate:
		/* Looser than **: -2 ** 2 is -(2 ** 2). */
		return 7;
	case WFFeelNodeLiteral:
		/* A negative number is written with a sign, as a negation is. */
		return WFFeelIsNumber(self.value) && [self.value compare:@0] == NSOrderedAscending ? 7 : 9;
	case WFFeelNodeBinary:
		switch (self.op) {
		case WFFeelOperatorOr: return 2;
		case WFFeelOperatorAnd: return 3;
		case WFFeelOperatorAdd:
		case WFFeelOperatorSubtract: return 5;
		case WFFeelOperatorMultiply:
		case WFFeelOperatorDivide: return 6;
		case WFFeelOperatorPower: return 8;
		default: return 4;
		}
	default:
		return 9;
	}
}

/* The child as an operand at that level: in parentheses when it binds more
 * loosely. */
static NSString *
WFFeelOperand(WFFeelNode *child, NSInteger level)
{
	NSString *text = [child description];
	return [child precedence] < level ? [NSString stringWithFormat:@"(%@)", text] : text;
}

static NSString *
WFFeelKeyText(NSString *key)
{
	BOOL plain = [key length] > 0 && !WFFeelIsReserved(key);
	for (NSUInteger i = 0; plain && i < [key length]; i++) {
		unichar c = [key characterAtIndex:i];
		plain = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'
			|| (i > 0 && c >= '0' && c <= '9');
	}
	return plain ? key : WFFeelLiteralText(key);
}

- (NSString *)iterationText:(NSString *)keyword
{
	NSMutableArray *parts = [NSMutableArray array];
	for (NSUInteger i = 0; i < [self.names count]; i++) {
		[parts addObject:[NSString stringWithFormat:@"%@ in %@", [self.names objectAtIndex:i],
			WFFeelOperand([self.children objectAtIndex:i], 2)]];
	}
	return [NSString stringWithFormat:@"%@ %@", keyword, [parts componentsJoinedByString:@", "]];
}

- (NSString *)description
{
	NSArray *c = self.children;
	switch (self.kind) {
	case WFFeelNodeLiteral:
		return WFFeelLiteralText(self.value);
	case WFFeelNodeName:
		return self.name;
	case WFFeelNodePath:
		return [NSString stringWithFormat:@"%@.%@", WFFeelOperand([c objectAtIndex:0], 9),
			self.name];
	case WFFeelNodeFilter:
		return [NSString stringWithFormat:@"%@[%@]", WFFeelOperand([c objectAtIndex:0], 9),
			[c objectAtIndex:1]];
	case WFFeelNodeCall:
		return [NSString stringWithFormat:@"%@(%@)", self.name,
			[[c valueForKey:@"description"] componentsJoinedByString:@", "]];
	case WFFeelNodeNegate:
		return [@"-" stringByAppendingString:WFFeelOperand([c objectAtIndex:0], 7)];
	case WFFeelNodeBinary: {
		NSInteger level = [self precedence];
		/* Operators group to the left, so a right operand of the same
		 * level needs parentheses; comparisons do not chain at all. */
		NSInteger left = WFFeelIsComparison(self.op) || self.op == WFFeelOperatorPower
			? level + 1 : level;
		return [NSString stringWithFormat:@"%@ %@ %@", WFFeelOperand([c objectAtIndex:0], left),
			WFFeelOperatorText(self.op), WFFeelOperand([c objectAtIndex:1], level + 1)];
	}
	case WFFeelNodeBetween:
		return [NSString stringWithFormat:@"%@ between %@ and %@",
			WFFeelOperand([c objectAtIndex:0], 5), WFFeelOperand([c objectAtIndex:1], 5),
			WFFeelOperand([c objectAtIndex:2], 5)];
	case WFFeelNodeIn: {
		NSArray *tests = [c subarrayWithRange:NSMakeRange(1, [c count] - 1)];
		NSString *text = [[tests valueForKey:@"description"] componentsJoinedByString:@", "];
		/* One test is written bare, unless it would read as the start of a
		 * list of tests -- but (1..5) reads back as the range it is. */
		WFFeelNode *only = [tests count] == 1 ? [[tests objectAtIndex:0] children].firstObject : nil;
		BOOL range = only.kind == WFFeelNodeRange && [[tests objectAtIndex:0] op] == WFFeelOperatorEqual;
		if ([tests count] > 1 || ([text hasPrefix:@"("] && !range)) {
			text = [NSString stringWithFormat:@"(%@)", text];
		}
		return [NSString stringWithFormat:@"%@ in %@", WFFeelOperand([c objectAtIndex:0], 5), text];
	}
	case WFFeelNodeUnaryTest:
		if (self.op == WFFeelOperatorEqual) {
			return WFFeelOperand([c objectAtIndex:0], 5);
		}
		return [NSString stringWithFormat:@"%@ %@", WFFeelOperatorText(self.op),
			WFFeelOperand([c objectAtIndex:0], 5)];
	case WFFeelNodeList:
		return [NSString stringWithFormat:@"[%@]",
			[[c valueForKey:@"description"] componentsJoinedByString:@", "]];
	case WFFeelNodeRange:
		return [NSString stringWithFormat:@"%@%@..%@%@", self.startIncluded ? @"[" : @"(",
			WFFeelOperand([c objectAtIndex:0], 5), WFFeelOperand([c objectAtIndex:1], 5),
			self.endIncluded ? @"]" : @")"];
	case WFFeelNodeContext: {
		NSMutableArray *entries = [NSMutableArray array];
		for (NSUInteger i = 0; i < [c count]; i++) {
			[entries addObject:[NSString stringWithFormat:@"%@: %@",
				WFFeelKeyText([self.names objectAtIndex:i]), [c objectAtIndex:i]]];
		}
		return [NSString stringWithFormat:@"{%@}", [entries componentsJoinedByString:@", "]];
	}
	case WFFeelNodeIf:
		return [NSString stringWithFormat:@"if %@ then %@ else %@", [c objectAtIndex:0],
			[c objectAtIndex:1], [c objectAtIndex:2]];
	case WFFeelNodeFor:
		return [NSString stringWithFormat:@"%@ return %@", [self iterationText:@"for"],
			[c lastObject]];
	case WFFeelNodeSome:
		return [NSString stringWithFormat:@"%@ satisfies %@", [self iterationText:@"some"],
			[c lastObject]];
	case WFFeelNodeEvery:
		return [NSString stringWithFormat:@"%@ satisfies %@", [self iterationText:@"every"],
			[c lastObject]];
	}
	return @"?";
}

@end

#pragma mark - Parser

@interface WFFeelParser : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<WFFeelToken *> *tokens;
@property (nonatomic) NSUInteger i;
@property (nonatomic) BOOL camunda7;
/* The first thing that went wrong; parsing stops there. */
@property (nonatomic, strong) NSError *error;
/* Parsing a range's end, where [ closes the range (1..10[) rather than
 * filtering the end. */
@property (nonatomic) BOOL inRangeEnd;
- (WFFeelNode *)parse;
@end

@implementation WFFeelParser

- (WFFeelToken *)peek
{
	return [self.tokens objectAtIndex:MIN(self.i, [self.tokens count] - 1)];
}

- (WFFeelToken *)peekAhead:(NSUInteger)n
{
	return [self.tokens objectAtIndex:MIN(self.i + n, [self.tokens count] - 1)];
}

- (WFFeelToken *)eat
{
	WFFeelToken *token = [self peek];
	if (token.kind != WFFeelTokenEnd) {
		self.i += 1;
	}
	return token;
}

- (BOOL)match:(WFFeelTokenKind)kind
{
	if ([self peek].kind == kind) {
		[self eat];
		return YES;
	}
	return NO;
}

- (BOOL)isWord:(NSString *)word
{
	WFFeelToken *token = [self peek];
	return token.kind == WFFeelTokenName && [token.text isEqualToString:word];
}

- (BOOL)matchWord:(NSString *)word
{
	if ([self isWord:word]) {
		[self eat];
		return YES;
	}
	return NO;
}

/* Records what was expected where; the first failure is the one reported. */
- (WFFeelNode *)fail:(NSString *)expected
{
	if (self.error == nil) {
		WFFeelToken *token = [self peek];
		NSString *message = [NSString stringWithFormat:@"\"%@\": expected %@ at %lu, found %@",
			self.text, expected, (unsigned long)token.range.location + 1, token];
		self.error = [NSError errorWithDomain:WFErrorDomain
		                                 code:WFErrorCondition
		                             userInfo:@{ NSLocalizedDescriptionKey: message }];
	}
	return [WFFeelNode literal:[NSNull null]];
}

- (void)expect:(WFFeelTokenKind)kind what:(NSString *)what
{
	if (![self match:kind]) {
		[self fail:what];
	}
}

- (void)expectWord:(NSString *)word
{
	if (![self matchWord:word]) {
		[self fail:[NSString stringWithFormat:@"'%@'", word]];
	}
}

- (WFFeelNode *)parse
{
	WFFeelNode *node = [self parseExpression];
	if (self.error == nil && [self peek].kind != WFFeelTokenEnd) {
		[self fail:@"the end"];
	}
	return self.error == nil ? node : nil;
}

/* The textual forms, which bind most loosely: if, for, some, every. */
- (WFFeelNode *)parseExpression
{
	if (self.error != nil) {
		return [WFFeelNode literal:[NSNull null]];
	}
	if (!self.camunda7) {
		if ([self matchWord:@"if"]) {
			WFFeelNode *node = [WFFeelNode node:WFFeelNodeIf];
			WFFeelNode *condition = [self parseExpression];
			[self expectWord:@"then"];
			WFFeelNode *then = [self parseExpression];
			[self expectWord:@"else"];
			node.children = @[ condition, then, [self parseExpression] ];
			return node;
		}
		if ([self isWord:@"for"] || [self isWord:@"some"] || [self isWord:@"every"]) {
			NSString *keyword = [self eat].text;
			WFFeelNode *node = [WFFeelNode node:[keyword isEqualToString:@"for"] ? WFFeelNodeFor
				: [keyword isEqualToString:@"some"] ? WFFeelNodeSome : WFFeelNodeEvery];
			NSMutableArray *names = [NSMutableArray array];
			NSMutableArray *children = [NSMutableArray array];
			do {
				[names addObject:[self variableName]];
				[self expectWord:@"in"];
				WFFeelNode *collection = [self parseDisjunction];
				if ([self match:WFFeelTokenDotDot]) {
					/* for i in 1..3: a range of whole numbers, ends included. */
					WFFeelNode *range = [WFFeelNode node:WFFeelNodeRange];
					range.startIncluded = YES;
					range.endIncluded = YES;
					range.children = @[ collection, [self parseAdditive] ];
					collection = range;
				}
				[children addObject:collection];
			} while ([self match:WFFeelTokenComma]);
			[self expectWord:[keyword isEqualToString:@"for"] ? @"return" : @"satisfies"];
			[children addObject:[self parseExpression]];
			node.names = names;
			node.children = children;
			return node;
		}
	}
	return [self parseDisjunction];
}

- (NSString *)variableName
{
	WFFeelToken *token = [self peek];
	if (token.kind != WFFeelTokenName || WFFeelIsReserved(token.text)) {
		[self fail:@"a name"];
		return @"?";
	}
	return [self eat].text;
}

- (WFFeelNode *)parseDisjunction
{
	WFFeelNode *left = [self parseConjunction];
	while ([self matchWord:@"or"] || (self.camunda7 && [self match:WFFeelTokenOrOr])) {
		left = [WFFeelNode binary:WFFeelOperatorOr left:left right:[self parseConjunction]];
	}
	return left;
}

- (WFFeelNode *)parseConjunction
{
	WFFeelNode *left = [self parseComparison];
	while ([self matchWord:@"and"] || (self.camunda7 && [self match:WFFeelTokenAndAnd])) {
		left = [WFFeelNode binary:WFFeelOperatorAnd left:left right:[self parseComparison]];
	}
	return left;
}

/* The comparison operator at the head of the input, eaten; None if there
 * is none. Camunda 7 also has them as words. */
- (WFFeelOperator)matchComparison
{
	WFFeelToken *token = [self peek];
	WFFeelOperator op = WFFeelOperatorNone;
	switch (token.kind) {
	case WFFeelTokenEqual: op = WFFeelOperatorEqual; break;
	case WFFeelTokenNotEqual: op = WFFeelOperatorNotEqual; break;
	case WFFeelTokenLess: op = WFFeelOperatorLess; break;
	case WFFeelTokenLessOrEqual: op = WFFeelOperatorLessOrEqual; break;
	case WFFeelTokenGreater: op = WFFeelOperatorGreater; break;
	case WFFeelTokenGreaterOrEqual: op = WFFeelOperatorGreaterOrEqual; break;
	case WFFeelTokenName:
		if (self.camunda7) {
			NSDictionary *words = @{ @"eq": @(WFFeelOperatorEqual), @"ne": @(WFFeelOperatorNotEqual),
				@"lt": @(WFFeelOperatorLess), @"le": @(WFFeelOperatorLessOrEqual),
				@"gt": @(WFFeelOperatorGreater), @"ge": @(WFFeelOperatorGreaterOrEqual) };
			op = (WFFeelOperator)[[words objectForKey:token.text] integerValue];
		}
		break;
	default:
		break;
	}
	if (op != WFFeelOperatorNone) {
		[self eat];
	}
	return op;
}

- (WFFeelNode *)parseComparison
{
	WFFeelNode *left = [self parseAdditive];
	WFFeelOperator op = [self matchComparison];
	if (op != WFFeelOperatorNone) {
		return [WFFeelNode binary:op left:left right:[self parseAdditive]];
	}
	if (self.camunda7) {
		return left;
	}
	if ([self matchWord:@"between"]) {
		WFFeelNode *node = [WFFeelNode node:WFFeelNodeBetween];
		WFFeelNode *low = [self parseAdditive];
		[self expectWord:@"and"];
		node.children = @[ left, low, [self parseAdditive] ];
		return node;
	}
	if ([self matchWord:@"in"]) {
		WFFeelNode *node = [WFFeelNode node:WFFeelNodeIn];
		node.children = [@[ left ] arrayByAddingObjectsFromArray:[self parseUnaryTests]];
		return node;
	}
	return left;
}

/* After `in`: one test, or several in parentheses -- where `(1..5)` is
 * one range that excludes its ends. */
- (NSArray<WFFeelNode *> *)parseUnaryTests
{
	if (![self match:WFFeelTokenLParen]) {
		return @[ [self parseUnaryTest] ];
	}
	WFFeelNode *first = [self parseUnaryTest];
	if (first.op == WFFeelOperatorEqual && [self match:WFFeelTokenDotDot]) {
		first.children = @[ [self finishRangeFrom:[first.children objectAtIndex:0] startIncluded:NO] ];
		return @[ first ];
	}
	NSMutableArray *tests = [NSMutableArray arrayWithObject:first];
	while ([self match:WFFeelTokenComma]) {
		[tests addObject:[self parseUnaryTest]];
	}
	[self expect:WFFeelTokenRParen what:@"')'"];
	return tests;
}

- (WFFeelNode *)parseUnaryTest
{
	WFFeelNode *test = [WFFeelNode node:WFFeelNodeUnaryTest];
	WFFeelOperator op = [self matchComparison];
	test.op = op == WFFeelOperatorNone ? WFFeelOperatorEqual : op;
	test.children = @[ [self parseAdditive] ];
	return test;
}

- (WFFeelNode *)parseAdditive
{
	WFFeelNode *left = [self parseMultiplicative];
	for (;;) {
		if ([self match:WFFeelTokenPlus]) {
			left = [WFFeelNode binary:WFFeelOperatorAdd left:left right:[self parseMultiplicative]];
		} else if ([self match:WFFeelTokenMinus]) {
			left = [WFFeelNode binary:WFFeelOperatorSubtract left:left right:[self parseMultiplicative]];
		} else {
			return left;
		}
	}
}

- (WFFeelNode *)parseMultiplicative
{
	WFFeelNode *left = [self parseUnary];
	for (;;) {
		if ([self match:WFFeelTokenStar]) {
			left = [WFFeelNode binary:WFFeelOperatorMultiply left:left right:[self parseUnary]];
		} else if ([self match:WFFeelTokenSlash]) {
			left = [WFFeelNode binary:WFFeelOperatorDivide left:left right:[self parseUnary]];
		} else {
			return left;
		}
	}
}

/* A sign binds more loosely than **, so -2 ** 2 is -(2 ** 2). */
- (WFFeelNode *)parseUnary
{
	if ([self match:WFFeelTokenMinus]) {
		WFFeelNode *node = [WFFeelNode node:WFFeelNodeNegate];
		node.children = @[ [self parseUnary] ];
		return node;
	}
	if (self.camunda7 && ([self match:WFFeelTokenBang] || [self matchWord:@"not"])) {
		WFFeelNode *node = [WFFeelNode node:WFFeelNodeCall];
		node.name = @"not";
		node.children = @[ [self parseUnary] ];
		return node;
	}
	return [self parsePower];
}

- (WFFeelNode *)parsePower
{
	WFFeelNode *left = [self parsePostfix];
	while ([self match:WFFeelTokenStarStar]) {
		left = [WFFeelNode binary:WFFeelOperatorPower left:left right:[self parsePowerOperand]];
	}
	return left;
}

/* The right operand of ** may carry a sign of its own: 2 ** -1. */
- (WFFeelNode *)parsePowerOperand
{
	if ([self match:WFFeelTokenMinus]) {
		WFFeelNode *node = [WFFeelNode node:WFFeelNodeNegate];
		node.children = @[ [self parsePowerOperand] ];
		return node;
	}
	return [self parsePostfix];
}

- (WFFeelNode *)parsePostfix
{
	WFFeelNode *node = [self parsePrimary];
	for (;;) {
		if (self.error != nil) {
			return node;
		}
		if ([self match:WFFeelTokenDot]) {
			WFFeelNode *path = [WFFeelNode node:WFFeelNodePath];
			WFFeelToken *token = [self peek];
			if (token.kind != WFFeelTokenName) {
				return [self fail:@"a name after '.'"];
			}
			path.name = [self eat].text;
			path.children = @[ node ];
			node = path;
		} else if (!self.camunda7 && !self.inRangeEnd && [self match:WFFeelTokenLBracket]) {
			WFFeelNode *filter = [WFFeelNode node:WFFeelNodeFilter];
			filter.children = @[ node, [self parseExpression] ];
			[self expect:WFFeelTokenRBracket what:@"']'"];
			node = filter;
		} else {
			return node;
		}
	}
}

/* A built-in whose name has several words, if one starts here and is
 * called: its name, with the words eaten. */
- (NSString *)matchMultiWordCall
{
	for (NSString *name in WFFeelMultiWordBuiltins()) {
		NSArray *words = [name componentsSeparatedByString:@" "];
		NSUInteger k = 0;
		for (; k < [words count]; k++) {
			WFFeelToken *token = [self peekAhead:k];
			if (token.kind != WFFeelTokenName || ![token.text isEqualToString:[words objectAtIndex:k]]) {
				break;
			}
		}
		if (k == [words count] && [self peekAhead:k].kind == WFFeelTokenLParen) {
			self.i += k;
			return name;
		}
	}
	return nil;
}

- (WFFeelNode *)parseCall:(NSString *)name
{
	WFFeelNode *call = [WFFeelNode node:WFFeelNodeCall];
	call.name = name;
	[self expect:WFFeelTokenLParen what:@"'('"];
	NSMutableArray *arguments = [NSMutableArray array];
	if (![self match:WFFeelTokenRParen]) {
		do {
			[arguments addObject:[self parseExpression]];
		} while ([self match:WFFeelTokenComma]);
		[self expect:WFFeelTokenRParen what:@"')'"];
	}
	call.children = arguments;
	return call;
}

- (WFFeelNode *)finishRangeFrom:(WFFeelNode *)start startIncluded:(BOOL)startIncluded
{
	WFFeelNode *range = [WFFeelNode node:WFFeelNodeRange];
	range.startIncluded = startIncluded;
	BOOL outer = self.inRangeEnd;
	self.inRangeEnd = YES;
	WFFeelNode *end = [self parseAdditive];
	self.inRangeEnd = outer;
	if ([self match:WFFeelTokenRBracket]) {
		range.endIncluded = YES;
	} else if ([self match:WFFeelTokenRParen] || [self match:WFFeelTokenLBracket]) {
		range.endIncluded = NO;
	} else {
		[self fail:@"']', ')' or '[' to end the range"];
	}
	range.children = @[ start, end ];
	return range;
}

- (WFFeelNode *)parsePrimary
{
	if (self.error != nil) {
		return [WFFeelNode literal:[NSNull null]];
	}
	WFFeelToken *token = [self peek];
	switch (token.kind) {
	case WFFeelTokenNumber:
		[self eat];
		return [WFFeelNode literal:[NSDecimalNumber decimalNumberWithString:token.text
			locale:@{ NSDecimalSeparator: @"." }]];
	case WFFeelTokenString:
		[self eat];
		return [WFFeelNode literal:token.text];
	case WFFeelTokenName:
		return [self parseName];
	case WFFeelTokenLParen: {
		[self eat];
		WFFeelNode *inner = [self parseExpression];
		if (!self.camunda7 && [self match:WFFeelTokenDotDot]) {
			return [self finishRangeFrom:inner startIncluded:NO];
		}
		[self expect:WFFeelTokenRParen what:@"')'"];
		return inner;
	}
	default:
		break;
	}
	if (self.camunda7) {
		return [self fail:@"a value"];
	}
	if ([self match:WFFeelTokenLBracket]) {
		if ([self match:WFFeelTokenRBracket]) {
			return [WFFeelNode node:WFFeelNodeList];
		}
		WFFeelNode *first = [self parseExpression];
		if ([self match:WFFeelTokenDotDot]) {
			return [self finishRangeFrom:first startIncluded:YES];
		}
		NSMutableArray *items = [NSMutableArray arrayWithObject:first];
		while ([self match:WFFeelTokenComma]) {
			[items addObject:[self parseExpression]];
		}
		[self expect:WFFeelTokenRBracket what:@"']'"];
		WFFeelNode *list = [WFFeelNode node:WFFeelNodeList];
		list.children = items;
		return list;
	}
	if ([self match:WFFeelTokenRBracket]) {
		/* ]1..5]: a range that excludes its start. */
		WFFeelNode *start = [self parseAdditive];
		[self expect:WFFeelTokenDotDot what:@"'..'"];
		return [self finishRangeFrom:start startIncluded:NO];
	}
	if ([self match:WFFeelTokenLBrace]) {
		return [self parseContext];
	}
	if ([self match:WFFeelTokenAt]) {
		/* @"2020-01-01", @"2020-01-01T10:00:00Z", @"P1D": a temporal
		 * literal, read now. */
		WFFeelToken *text = [self peek];
		id value = text.kind == WFFeelTokenString ? WFFeelParseTemporal(text.text) : nil;
		if (value == nil) {
			return [self fail:@"a date, date and time or duration in quotes after '@'"];
		}
		[self eat];
		return [WFFeelNode literal:value];
	}
	return [self fail:@"a value"];
}

- (WFFeelNode *)parseName
{
	WFFeelToken *token = [self peek];
	NSString *word = token.text;
	if ([word isEqualToString:@"true"] || [word isEqualToString:@"false"]) {
		[self eat];
		return [WFFeelNode literal:[NSNumber numberWithBool:[word isEqualToString:@"true"]]];
	}
	if ([word isEqualToString:@"null"]) {
		[self eat];
		return [WFFeelNode literal:[NSNull null]];
	}
	if (!self.camunda7) {
		NSString *multiWord = [self matchMultiWordCall];
		if (multiWord != nil) {
			return [self parseCall:multiWord];
		}
		if ([self peekAhead:1].kind == WFFeelTokenLParen) {
			if (!WFFeelIsBuiltin(word)) {
				return [self fail:@"a function FEEL has"];
			}
			[self eat];
			return [self parseCall:word];
		}
	}
	if (WFFeelIsReserved(word)) {
		return [self fail:@"a value"];
	}
	[self eat];
	WFFeelNode *name = [WFFeelNode node:WFFeelNodeName];
	name.name = word;
	return name;
}

/* {a: 1, "b c": 2, d e: 3}: keys are names, several words, or strings. */
- (WFFeelNode *)parseContext
{
	WFFeelNode *context = [WFFeelNode node:WFFeelNodeContext];
	NSMutableArray *keys = [NSMutableArray array];
	NSMutableArray *values = [NSMutableArray array];
	if (![self match:WFFeelTokenRBrace]) {
		do {
			WFFeelToken *token = [self peek];
			NSString *key = nil;
			if (token.kind == WFFeelTokenString) {
				key = [self eat].text;
			} else {
				NSMutableArray *words = [NSMutableArray array];
				while ([self peek].kind == WFFeelTokenName) {
					[words addObject:[self eat].text];
				}
				if ([words count] == 0) {
					return [self fail:@"a key"];
				}
				key = [words componentsJoinedByString:@" "];
			}
			[self expect:WFFeelTokenColon what:@"':'"];
			[keys addObject:key];
			[values addObject:[self parseExpression]];
		} while ([self match:WFFeelTokenComma]);
		[self expect:WFFeelTokenRBrace what:@"'}'"];
	}
	context.names = keys;
	context.children = values;
	return context;
}

@end

WFFeelNode *
WFFeelParse(NSString *text, BOOL camunda7, NSError **error)
{
	WFFeelParser *parser = [[WFFeelParser alloc] init];
	parser.text = text ?: @"";
	parser.camunda7 = camunda7;
	parser.tokens = [[[WFFeelLexer alloc] initWithString:parser.text camunda7:camunda7] tokens];
	WFFeelNode *node = nil;
	if ([parser peek].kind == WFFeelTokenEnd) {
		[parser fail:@"an expression"];
	} else {
		node = [parser parse];
	}
	if (node == nil && error != NULL) {
		*error = parser.error;
	}
	return node;
}

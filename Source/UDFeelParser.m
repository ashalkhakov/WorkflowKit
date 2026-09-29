#import "UDFeelInternal.h"

#pragma mark - Nodes

static NSString *
UDFeelOperatorText(UDFeelOperator op)
{
	switch (op) {
	case UDFeelOperatorOr: return @"or";
	case UDFeelOperatorAnd: return @"and";
	case UDFeelOperatorEqual: return @"=";
	case UDFeelOperatorNotEqual: return @"!=";
	case UDFeelOperatorLess: return @"<";
	case UDFeelOperatorLessOrEqual: return @"<=";
	case UDFeelOperatorGreater: return @">";
	case UDFeelOperatorGreaterOrEqual: return @">=";
	case UDFeelOperatorAdd: return @"+";
	case UDFeelOperatorSubtract: return @"-";
	case UDFeelOperatorMultiply: return @"*";
	case UDFeelOperatorDivide: return @"/";
	case UDFeelOperatorPower: return @"**";
	/* Only ever a call, modulo(a, b); the parser makes no such operator. */
	case UDFeelOperatorModulo:
	case UDFeelOperatorNone: break;
	}
	return @"?";
}

static BOOL
UDFeelIsComparison(UDFeelOperator op)
{
	return op >= UDFeelOperatorEqual && op <= UDFeelOperatorGreaterOrEqual;
}

/* Words that cannot be a variable's name, because the grammar reads them. */
static BOOL
UDFeelIsReserved(NSString *word)
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

@implementation UDFeelNode

+ (instancetype)node:(UDFeelNodeKind)kind
{
	UDFeelNode *node = [[self alloc] init];
	node.kind = kind;
	node.children = @[];
	return node;
}

+ (instancetype)literal:(id)value
{
	UDFeelNode *node = [self node:UDFeelNodeLiteral];
	node.value = value ?: [NSNull null];
	return node;
}

+ (instancetype)binary:(UDFeelOperator)op left:(UDFeelNode *)left right:(UDFeelNode *)right
{
	UDFeelNode *node = [self node:UDFeelNodeBinary];
	node.op = op;
	node.children = @[ left, right ];
	return node;
}

- (NSInteger)precedence
{
	switch (self.kind) {
	case UDFeelNodeIf:
	case UDFeelNodeFor:
	case UDFeelNodeSome:
	case UDFeelNodeEvery:
		return 1;
	case UDFeelNodeBetween:
	case UDFeelNodeIn:
		return 4;
	case UDFeelNodeNegate:
		/* Looser than **: -2 ** 2 is -(2 ** 2). */
		return 7;
	case UDFeelNodeLiteral:
		/* A negative number is written with a sign, as a negation is. */
		return UDFeelIsNumber(self.value) && [self.value compare:@0] == NSOrderedAscending ? 7 : 9;
	case UDFeelNodeBinary:
		switch (self.op) {
		case UDFeelOperatorOr: return 2;
		case UDFeelOperatorAnd: return 3;
		case UDFeelOperatorAdd:
		case UDFeelOperatorSubtract: return 5;
		case UDFeelOperatorMultiply:
		case UDFeelOperatorDivide: return 6;
		case UDFeelOperatorPower: return 8;
		default: return 4;
		}
	default:
		return 9;
	}
}

/* The child as an operand at that level: in parentheses when it binds more
 * loosely. */
static NSString *
UDFeelOperand(UDFeelNode *child, NSInteger level)
{
	NSString *text = [child description];
	return [child precedence] < level ? [NSString stringWithFormat:@"(%@)", text] : text;
}

static NSString *
UDFeelKeyText(NSString *key)
{
	BOOL plain = [key length] > 0 && !UDFeelIsReserved(key);
	for (NSUInteger i = 0; plain && i < [key length]; i++) {
		unichar c = [key characterAtIndex:i];
		plain = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'
			|| (i > 0 && c >= '0' && c <= '9');
	}
	return plain ? key : UDFeelLiteralText(key);
}

- (NSString *)iterationText:(NSString *)keyword
{
	NSMutableArray *parts = [NSMutableArray array];
	for (NSUInteger i = 0; i < [self.names count]; i++) {
		[parts addObject:[NSString stringWithFormat:@"%@ in %@", [self.names objectAtIndex:i],
			UDFeelOperand([self.children objectAtIndex:i], 2)]];
	}
	return [NSString stringWithFormat:@"%@ %@", keyword, [parts componentsJoinedByString:@", "]];
}

- (NSString *)description
{
	NSArray *c = self.children;
	switch (self.kind) {
	case UDFeelNodeLiteral:
		return UDFeelLiteralText(self.value);
	case UDFeelNodeName:
		return self.name;
	case UDFeelNodePath:
		return [NSString stringWithFormat:@"%@.%@", UDFeelOperand([c objectAtIndex:0], 9),
			self.name];
	case UDFeelNodeFilter:
		return [NSString stringWithFormat:@"%@[%@]", UDFeelOperand([c objectAtIndex:0], 9),
			[c objectAtIndex:1]];
	case UDFeelNodeCall:
		return [NSString stringWithFormat:@"%@(%@)", self.name,
			[[c valueForKey:@"description"] componentsJoinedByString:@", "]];
	case UDFeelNodeNegate:
		return [@"-" stringByAppendingString:UDFeelOperand([c objectAtIndex:0], 7)];
	case UDFeelNodeBinary: {
		NSInteger level = [self precedence];
		/* Operators group to the left, so a right operand of the same
		 * level needs parentheses; comparisons do not chain at all. */
		NSInteger left = UDFeelIsComparison(self.op) || self.op == UDFeelOperatorPower
			? level + 1 : level;
		return [NSString stringWithFormat:@"%@ %@ %@", UDFeelOperand([c objectAtIndex:0], left),
			UDFeelOperatorText(self.op), UDFeelOperand([c objectAtIndex:1], level + 1)];
	}
	case UDFeelNodeBetween:
		return [NSString stringWithFormat:@"%@ between %@ and %@",
			UDFeelOperand([c objectAtIndex:0], 5), UDFeelOperand([c objectAtIndex:1], 5),
			UDFeelOperand([c objectAtIndex:2], 5)];
	case UDFeelNodeIn: {
		NSArray *tests = [c subarrayWithRange:NSMakeRange(1, [c count] - 1)];
		NSString *text = [[tests valueForKey:@"description"] componentsJoinedByString:@", "];
		/* One test is written bare, unless it would read as the start of a
		 * list of tests -- but (1..5) reads back as the range it is. */
		UDFeelNode *only = [tests count] == 1 ? [[tests objectAtIndex:0] children].firstObject : nil;
		BOOL range = only.kind == UDFeelNodeRange && [[tests objectAtIndex:0] op] == UDFeelOperatorEqual;
		if ([tests count] > 1 || ([text hasPrefix:@"("] && !range)) {
			text = [NSString stringWithFormat:@"(%@)", text];
		}
		return [NSString stringWithFormat:@"%@ in %@", UDFeelOperand([c objectAtIndex:0], 5), text];
	}
	case UDFeelNodeUnaryTest:
		if (self.op == UDFeelOperatorEqual) {
			return UDFeelOperand([c objectAtIndex:0], 5);
		}
		return [NSString stringWithFormat:@"%@ %@", UDFeelOperatorText(self.op),
			UDFeelOperand([c objectAtIndex:0], 5)];
	case UDFeelNodeList:
		return [NSString stringWithFormat:@"[%@]",
			[[c valueForKey:@"description"] componentsJoinedByString:@", "]];
	case UDFeelNodeRange:
		return [NSString stringWithFormat:@"%@%@..%@%@", self.startIncluded ? @"[" : @"(",
			UDFeelOperand([c objectAtIndex:0], 5), UDFeelOperand([c objectAtIndex:1], 5),
			self.endIncluded ? @"]" : @")"];
	case UDFeelNodeContext: {
		NSMutableArray *entries = [NSMutableArray array];
		for (NSUInteger i = 0; i < [c count]; i++) {
			[entries addObject:[NSString stringWithFormat:@"%@: %@",
				UDFeelKeyText([self.names objectAtIndex:i]), [c objectAtIndex:i]]];
		}
		return [NSString stringWithFormat:@"{%@}", [entries componentsJoinedByString:@", "]];
	}
	case UDFeelNodeIf:
		return [NSString stringWithFormat:@"if %@ then %@ else %@", [c objectAtIndex:0],
			[c objectAtIndex:1], [c objectAtIndex:2]];
	case UDFeelNodeFor:
		return [NSString stringWithFormat:@"%@ return %@", [self iterationText:@"for"],
			[c lastObject]];
	case UDFeelNodeSome:
		return [NSString stringWithFormat:@"%@ satisfies %@", [self iterationText:@"some"],
			[c lastObject]];
	case UDFeelNodeEvery:
		return [NSString stringWithFormat:@"%@ satisfies %@", [self iterationText:@"every"],
			[c lastObject]];
	}
	return @"?";
}

@end

#pragma mark - Parser

@interface UDFeelParser : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<UDFeelToken *> *tokens;
@property (nonatomic) NSUInteger i;
@property (nonatomic) BOOL camunda7;
/* The first thing that went wrong; parsing stops there. */
@property (nonatomic, strong) NSError *error;
/* Parsing a range's end, where [ closes the range (1..10[) rather than
 * filtering the end. */
@property (nonatomic) BOOL inRangeEnd;
- (UDFeelNode *)parse;
@end

@implementation UDFeelParser

- (UDFeelToken *)peek
{
	return [self.tokens objectAtIndex:MIN(self.i, [self.tokens count] - 1)];
}

- (UDFeelToken *)peekAhead:(NSUInteger)n
{
	return [self.tokens objectAtIndex:MIN(self.i + n, [self.tokens count] - 1)];
}

- (UDFeelToken *)eat
{
	UDFeelToken *token = [self peek];
	if (token.kind != UDFeelTokenEnd) {
		self.i += 1;
	}
	return token;
}

- (BOOL)match:(UDFeelTokenKind)kind
{
	if ([self peek].kind == kind) {
		[self eat];
		return YES;
	}
	return NO;
}

- (BOOL)isWord:(NSString *)word
{
	UDFeelToken *token = [self peek];
	return token.kind == UDFeelTokenName && [token.text isEqualToString:word];
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
- (UDFeelNode *)fail:(NSString *)expected
{
	if (self.error == nil) {
		UDFeelToken *token = [self peek];
		NSString *message = [NSString stringWithFormat:@"\"%@\": expected %@ at %lu, found %@",
			self.text, expected, (unsigned long)token.range.location + 1, token];
		self.error = [NSError errorWithDomain:UDWorkflowErrorDomain
		                                 code:UDWorkflowErrorCondition
		                             userInfo:@{ NSLocalizedDescriptionKey: message }];
	}
	return [UDFeelNode literal:[NSNull null]];
}

- (void)expect:(UDFeelTokenKind)kind what:(NSString *)what
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

- (UDFeelNode *)parse
{
	UDFeelNode *node = [self parseExpression];
	if (self.error == nil && [self peek].kind != UDFeelTokenEnd) {
		[self fail:@"the end"];
	}
	return self.error == nil ? node : nil;
}

/* The textual forms, which bind most loosely: if, for, some, every. */
- (UDFeelNode *)parseExpression
{
	if (self.error != nil) {
		return [UDFeelNode literal:[NSNull null]];
	}
	if (!self.camunda7) {
		if ([self matchWord:@"if"]) {
			UDFeelNode *node = [UDFeelNode node:UDFeelNodeIf];
			UDFeelNode *condition = [self parseExpression];
			[self expectWord:@"then"];
			UDFeelNode *then = [self parseExpression];
			[self expectWord:@"else"];
			node.children = @[ condition, then, [self parseExpression] ];
			return node;
		}
		if ([self isWord:@"for"] || [self isWord:@"some"] || [self isWord:@"every"]) {
			NSString *keyword = [self eat].text;
			UDFeelNode *node = [UDFeelNode node:[keyword isEqualToString:@"for"] ? UDFeelNodeFor
				: [keyword isEqualToString:@"some"] ? UDFeelNodeSome : UDFeelNodeEvery];
			NSMutableArray *names = [NSMutableArray array];
			NSMutableArray *children = [NSMutableArray array];
			do {
				[names addObject:[self variableName]];
				[self expectWord:@"in"];
				UDFeelNode *collection = [self parseDisjunction];
				if ([self match:UDFeelTokenDotDot]) {
					/* for i in 1..3: a range of whole numbers, ends included. */
					UDFeelNode *range = [UDFeelNode node:UDFeelNodeRange];
					range.startIncluded = YES;
					range.endIncluded = YES;
					range.children = @[ collection, [self parseAdditive] ];
					collection = range;
				}
				[children addObject:collection];
			} while ([self match:UDFeelTokenComma]);
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
	UDFeelToken *token = [self peek];
	if (token.kind != UDFeelTokenName || UDFeelIsReserved(token.text)) {
		[self fail:@"a name"];
		return @"?";
	}
	return [self eat].text;
}

- (UDFeelNode *)parseDisjunction
{
	UDFeelNode *left = [self parseConjunction];
	while ([self matchWord:@"or"] || (self.camunda7 && [self match:UDFeelTokenOrOr])) {
		left = [UDFeelNode binary:UDFeelOperatorOr left:left right:[self parseConjunction]];
	}
	return left;
}

- (UDFeelNode *)parseConjunction
{
	UDFeelNode *left = [self parseComparison];
	while ([self matchWord:@"and"] || (self.camunda7 && [self match:UDFeelTokenAndAnd])) {
		left = [UDFeelNode binary:UDFeelOperatorAnd left:left right:[self parseComparison]];
	}
	return left;
}

/* The comparison operator at the head of the input, eaten; None if there
 * is none. Camunda 7 also has them as words. */
- (UDFeelOperator)matchComparison
{
	UDFeelToken *token = [self peek];
	UDFeelOperator op = UDFeelOperatorNone;
	switch (token.kind) {
	case UDFeelTokenEqual: op = UDFeelOperatorEqual; break;
	case UDFeelTokenNotEqual: op = UDFeelOperatorNotEqual; break;
	case UDFeelTokenLess: op = UDFeelOperatorLess; break;
	case UDFeelTokenLessOrEqual: op = UDFeelOperatorLessOrEqual; break;
	case UDFeelTokenGreater: op = UDFeelOperatorGreater; break;
	case UDFeelTokenGreaterOrEqual: op = UDFeelOperatorGreaterOrEqual; break;
	case UDFeelTokenName:
		if (self.camunda7) {
			NSDictionary *words = @{ @"eq": @(UDFeelOperatorEqual), @"ne": @(UDFeelOperatorNotEqual),
				@"lt": @(UDFeelOperatorLess), @"le": @(UDFeelOperatorLessOrEqual),
				@"gt": @(UDFeelOperatorGreater), @"ge": @(UDFeelOperatorGreaterOrEqual) };
			op = (UDFeelOperator)[[words objectForKey:token.text] integerValue];
		}
		break;
	default:
		break;
	}
	if (op != UDFeelOperatorNone) {
		[self eat];
	}
	return op;
}

- (UDFeelNode *)parseComparison
{
	UDFeelNode *left = [self parseAdditive];
	UDFeelOperator op = [self matchComparison];
	if (op != UDFeelOperatorNone) {
		return [UDFeelNode binary:op left:left right:[self parseAdditive]];
	}
	if (self.camunda7) {
		return left;
	}
	if ([self matchWord:@"between"]) {
		UDFeelNode *node = [UDFeelNode node:UDFeelNodeBetween];
		UDFeelNode *low = [self parseAdditive];
		[self expectWord:@"and"];
		node.children = @[ left, low, [self parseAdditive] ];
		return node;
	}
	if ([self matchWord:@"in"]) {
		UDFeelNode *node = [UDFeelNode node:UDFeelNodeIn];
		node.children = [@[ left ] arrayByAddingObjectsFromArray:[self parseUnaryTests]];
		return node;
	}
	return left;
}

/* After `in`: one test, or several in parentheses -- where `(1..5)` is
 * one range that excludes its ends. */
- (NSArray<UDFeelNode *> *)parseUnaryTests
{
	if (![self match:UDFeelTokenLParen]) {
		return @[ [self parseUnaryTest] ];
	}
	UDFeelNode *first = [self parseUnaryTest];
	if (first.op == UDFeelOperatorEqual && [self match:UDFeelTokenDotDot]) {
		first.children = @[ [self finishRangeFrom:[first.children objectAtIndex:0] startIncluded:NO] ];
		return @[ first ];
	}
	NSMutableArray *tests = [NSMutableArray arrayWithObject:first];
	while ([self match:UDFeelTokenComma]) {
		[tests addObject:[self parseUnaryTest]];
	}
	[self expect:UDFeelTokenRParen what:@"')'"];
	return tests;
}

- (UDFeelNode *)parseUnaryTest
{
	UDFeelNode *test = [UDFeelNode node:UDFeelNodeUnaryTest];
	UDFeelOperator op = [self matchComparison];
	test.op = op == UDFeelOperatorNone ? UDFeelOperatorEqual : op;
	test.children = @[ [self parseAdditive] ];
	return test;
}

- (UDFeelNode *)parseAdditive
{
	UDFeelNode *left = [self parseMultiplicative];
	for (;;) {
		if ([self match:UDFeelTokenPlus]) {
			left = [UDFeelNode binary:UDFeelOperatorAdd left:left right:[self parseMultiplicative]];
		} else if ([self match:UDFeelTokenMinus]) {
			left = [UDFeelNode binary:UDFeelOperatorSubtract left:left right:[self parseMultiplicative]];
		} else {
			return left;
		}
	}
}

- (UDFeelNode *)parseMultiplicative
{
	UDFeelNode *left = [self parseUnary];
	for (;;) {
		if ([self match:UDFeelTokenStar]) {
			left = [UDFeelNode binary:UDFeelOperatorMultiply left:left right:[self parseUnary]];
		} else if ([self match:UDFeelTokenSlash]) {
			left = [UDFeelNode binary:UDFeelOperatorDivide left:left right:[self parseUnary]];
		} else {
			return left;
		}
	}
}

/* A sign binds more loosely than **, so -2 ** 2 is -(2 ** 2). */
- (UDFeelNode *)parseUnary
{
	if ([self match:UDFeelTokenMinus]) {
		UDFeelNode *node = [UDFeelNode node:UDFeelNodeNegate];
		node.children = @[ [self parseUnary] ];
		return node;
	}
	if (self.camunda7 && ([self match:UDFeelTokenBang] || [self matchWord:@"not"])) {
		UDFeelNode *node = [UDFeelNode node:UDFeelNodeCall];
		node.name = @"not";
		node.children = @[ [self parseUnary] ];
		return node;
	}
	return [self parsePower];
}

- (UDFeelNode *)parsePower
{
	UDFeelNode *left = [self parsePostfix];
	while ([self match:UDFeelTokenStarStar]) {
		left = [UDFeelNode binary:UDFeelOperatorPower left:left right:[self parsePowerOperand]];
	}
	return left;
}

/* The right operand of ** may carry a sign of its own: 2 ** -1. */
- (UDFeelNode *)parsePowerOperand
{
	if ([self match:UDFeelTokenMinus]) {
		UDFeelNode *node = [UDFeelNode node:UDFeelNodeNegate];
		node.children = @[ [self parsePowerOperand] ];
		return node;
	}
	return [self parsePostfix];
}

- (UDFeelNode *)parsePostfix
{
	UDFeelNode *node = [self parsePrimary];
	for (;;) {
		if (self.error != nil) {
			return node;
		}
		if ([self match:UDFeelTokenDot]) {
			UDFeelNode *path = [UDFeelNode node:UDFeelNodePath];
			UDFeelToken *token = [self peek];
			if (token.kind != UDFeelTokenName) {
				return [self fail:@"a name after '.'"];
			}
			path.name = [self eat].text;
			path.children = @[ node ];
			node = path;
		} else if (!self.camunda7 && !self.inRangeEnd && [self match:UDFeelTokenLBracket]) {
			UDFeelNode *filter = [UDFeelNode node:UDFeelNodeFilter];
			filter.children = @[ node, [self parseExpression] ];
			[self expect:UDFeelTokenRBracket what:@"']'"];
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
	for (NSString *name in UDFeelMultiWordBuiltins()) {
		NSArray *words = [name componentsSeparatedByString:@" "];
		NSUInteger k = 0;
		for (; k < [words count]; k++) {
			UDFeelToken *token = [self peekAhead:k];
			if (token.kind != UDFeelTokenName || ![token.text isEqualToString:[words objectAtIndex:k]]) {
				break;
			}
		}
		if (k == [words count] && [self peekAhead:k].kind == UDFeelTokenLParen) {
			self.i += k;
			return name;
		}
	}
	return nil;
}

- (UDFeelNode *)parseCall:(NSString *)name
{
	UDFeelNode *call = [UDFeelNode node:UDFeelNodeCall];
	call.name = name;
	[self expect:UDFeelTokenLParen what:@"'('"];
	NSMutableArray *arguments = [NSMutableArray array];
	if (![self match:UDFeelTokenRParen]) {
		do {
			[arguments addObject:[self parseExpression]];
		} while ([self match:UDFeelTokenComma]);
		[self expect:UDFeelTokenRParen what:@"')'"];
	}
	call.children = arguments;
	return call;
}

- (UDFeelNode *)finishRangeFrom:(UDFeelNode *)start startIncluded:(BOOL)startIncluded
{
	UDFeelNode *range = [UDFeelNode node:UDFeelNodeRange];
	range.startIncluded = startIncluded;
	BOOL outer = self.inRangeEnd;
	self.inRangeEnd = YES;
	UDFeelNode *end = [self parseAdditive];
	self.inRangeEnd = outer;
	if ([self match:UDFeelTokenRBracket]) {
		range.endIncluded = YES;
	} else if ([self match:UDFeelTokenRParen] || [self match:UDFeelTokenLBracket]) {
		range.endIncluded = NO;
	} else {
		[self fail:@"']', ')' or '[' to end the range"];
	}
	range.children = @[ start, end ];
	return range;
}

- (UDFeelNode *)parsePrimary
{
	if (self.error != nil) {
		return [UDFeelNode literal:[NSNull null]];
	}
	UDFeelToken *token = [self peek];
	switch (token.kind) {
	case UDFeelTokenNumber:
		[self eat];
		return [UDFeelNode literal:[NSDecimalNumber decimalNumberWithString:token.text
			locale:@{ NSDecimalSeparator: @"." }]];
	case UDFeelTokenString:
		[self eat];
		return [UDFeelNode literal:token.text];
	case UDFeelTokenName:
		return [self parseName];
	case UDFeelTokenLParen: {
		[self eat];
		UDFeelNode *inner = [self parseExpression];
		if (!self.camunda7 && [self match:UDFeelTokenDotDot]) {
			return [self finishRangeFrom:inner startIncluded:NO];
		}
		[self expect:UDFeelTokenRParen what:@"')'"];
		return inner;
	}
	default:
		break;
	}
	if (self.camunda7) {
		return [self fail:@"a value"];
	}
	if ([self match:UDFeelTokenLBracket]) {
		if ([self match:UDFeelTokenRBracket]) {
			return [UDFeelNode node:UDFeelNodeList];
		}
		UDFeelNode *first = [self parseExpression];
		if ([self match:UDFeelTokenDotDot]) {
			return [self finishRangeFrom:first startIncluded:YES];
		}
		NSMutableArray *items = [NSMutableArray arrayWithObject:first];
		while ([self match:UDFeelTokenComma]) {
			[items addObject:[self parseExpression]];
		}
		[self expect:UDFeelTokenRBracket what:@"']'"];
		UDFeelNode *list = [UDFeelNode node:UDFeelNodeList];
		list.children = items;
		return list;
	}
	if ([self match:UDFeelTokenRBracket]) {
		/* ]1..5]: a range that excludes its start. */
		UDFeelNode *start = [self parseAdditive];
		[self expect:UDFeelTokenDotDot what:@"'..'"];
		return [self finishRangeFrom:start startIncluded:NO];
	}
	if ([self match:UDFeelTokenLBrace]) {
		return [self parseContext];
	}
	if ([self match:UDFeelTokenAt]) {
		/* @"2020-01-01", @"2020-01-01T10:00:00Z", @"P1D": a temporal
		 * literal, read now. */
		UDFeelToken *text = [self peek];
		id value = text.kind == UDFeelTokenString ? UDFeelParseTemporal(text.text) : nil;
		if (value == nil) {
			return [self fail:@"a date, date and time or duration in quotes after '@'"];
		}
		[self eat];
		return [UDFeelNode literal:value];
	}
	return [self fail:@"a value"];
}

- (UDFeelNode *)parseName
{
	UDFeelToken *token = [self peek];
	NSString *word = token.text;
	if ([word isEqualToString:@"true"] || [word isEqualToString:@"false"]) {
		[self eat];
		return [UDFeelNode literal:[NSNumber numberWithBool:[word isEqualToString:@"true"]]];
	}
	if ([word isEqualToString:@"null"]) {
		[self eat];
		return [UDFeelNode literal:[NSNull null]];
	}
	if (!self.camunda7) {
		NSString *multiWord = [self matchMultiWordCall];
		if (multiWord != nil) {
			return [self parseCall:multiWord];
		}
		if ([self peekAhead:1].kind == UDFeelTokenLParen) {
			if (!UDFeelIsBuiltin(word)) {
				return [self fail:@"a function FEEL has"];
			}
			[self eat];
			return [self parseCall:word];
		}
	}
	if (UDFeelIsReserved(word)) {
		return [self fail:@"a value"];
	}
	[self eat];
	UDFeelNode *name = [UDFeelNode node:UDFeelNodeName];
	name.name = word;
	return name;
}

/* {a: 1, "b c": 2, d e: 3}: keys are names, several words, or strings. */
- (UDFeelNode *)parseContext
{
	UDFeelNode *context = [UDFeelNode node:UDFeelNodeContext];
	NSMutableArray *keys = [NSMutableArray array];
	NSMutableArray *values = [NSMutableArray array];
	if (![self match:UDFeelTokenRBrace]) {
		do {
			UDFeelToken *token = [self peek];
			NSString *key = nil;
			if (token.kind == UDFeelTokenString) {
				key = [self eat].text;
			} else {
				NSMutableArray *words = [NSMutableArray array];
				while ([self peek].kind == UDFeelTokenName) {
					[words addObject:[self eat].text];
				}
				if ([words count] == 0) {
					return [self fail:@"a key"];
				}
				key = [words componentsJoinedByString:@" "];
			}
			[self expect:UDFeelTokenColon what:@"':'"];
			[keys addObject:key];
			[values addObject:[self parseExpression]];
		} while ([self match:UDFeelTokenComma]);
		[self expect:UDFeelTokenRBrace what:@"'}'"];
	}
	context.names = keys;
	context.children = values;
	return context;
}

@end

UDFeelNode *
UDFeelParse(NSString *text, BOOL camunda7, NSError **error)
{
	UDFeelParser *parser = [[UDFeelParser alloc] init];
	parser.text = text ?: @"";
	parser.camunda7 = camunda7;
	parser.tokens = [[[UDFeelLexer alloc] initWithString:parser.text camunda7:camunda7] tokens];
	UDFeelNode *node = nil;
	if ([parser peek].kind == UDFeelTokenEnd) {
		[parser fail:@"an expression"];
	} else {
		node = [parser parse];
	}
	if (node == nil && error != NULL) {
		*error = parser.error;
	}
	return node;
}

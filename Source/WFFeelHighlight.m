#import "WFFeelInternal.h"

/*
 * Expressions as an editor shows them: the lexer's tokens, classified, and
 * the parser's first error, both over the text as it is written in the
 * file -- ${...} and a leading = included -- so that their ranges are the
 * editor's.
 */

NSString * const WFExpressionTokenName = @"name";
NSString * const WFExpressionTokenKeyword = @"keyword";
NSString * const WFExpressionTokenFunction = @"function";
NSString * const WFExpressionTokenNumber = @"number";
NSString * const WFExpressionTokenString = @"string";
NSString * const WFExpressionTokenTemporal = @"temporal";
NSString * const WFExpressionTokenOperator = @"operator";
NSString * const WFExpressionTokenPunctuation = @"punctuation";
NSString * const WFExpressionTokenDelimiter = @"delimiter";
NSString * const WFExpressionTokenComment = @"comment";
NSString * const WFExpressionTokenInvalid = @"invalid";

/* The expression inside the text: where it begins and how long it is, and
 * whether it is the Camunda 7 subset. NO for literal text. */
static BOOL
WFExpressionBody(NSString *text, WFExpressionPlace place, NSRange *body, BOOL *camunda7, NSRange *opening, NSRange *closing)
{
	NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSUInteger length = [text length], start = 0, end = length;
	while (start < length && [space characterIsMember:[text characterAtIndex:start]]) {
		start++;
	}
	while (end > start && [space characterIsMember:[text characterAtIndex:end - 1]]) {
		end--;
	}
	NSString *trimmed = [text substringWithRange:NSMakeRange(start, end - start)];
	*opening = NSMakeRange(NSNotFound, 0);
	*closing = NSMakeRange(NSNotFound, 0);
	*camunda7 = NO;
	if (([trimmed hasPrefix:@"${"] || [trimmed hasPrefix:@"#{"]) && [trimmed hasSuffix:@"}"] && [trimmed length] >= 3) {
		*camunda7 = YES;
		*opening = NSMakeRange(start, 2);
		*closing = NSMakeRange(end - 1, 1);
		*body = NSMakeRange(start + 2, end - start - 3);
		return YES;
	}
	if (place == WFExpressionPlaceUnaryTests) {
		*body = NSMakeRange(start, end - start);
		return YES;
	}
	if ([trimmed hasPrefix:@"="]) {
		*opening = NSMakeRange(start, 1);
		*body = NSMakeRange(start + 1, length - start - 1);
		return YES;
	}
	if (place == WFExpressionPlaceAttribute) {
		return NO;
	}
	*body = NSMakeRange(0, length);
	return YES;
}

static NSDictionary *
WFToken(NSString *kind, NSRange range)
{
	return @{ @"kind": kind, @"range": [NSValue valueWithRange:range] };
}

static NSSet *
WFFeelKeywords(BOOL camunda7)
{
	return camunda7
		? [NSSet setWithObjects:@"and", @"or", @"not", @"eq", @"ne", @"lt", @"le", @"gt", @"ge", @"true",
		                        @"false", @"null", @"empty", @"div", @"mod", nil]
		: [NSSet setWithObjects:@"if", @"then", @"else", @"for", @"in", @"return", @"some", @"every",
		                        @"satisfies", @"and", @"or", @"not", @"between", @"instance", @"of", @"true",
		                        @"false", @"null", @"function", nil];
}

static NSString *
WFKindOf(WFFeelTokenKind kind)
{
	switch (kind) {
	case WFFeelTokenNumber:
		return WFExpressionTokenNumber;
	case WFFeelTokenString:
		return WFExpressionTokenString;
	case WFFeelTokenLParen: case WFFeelTokenRParen: case WFFeelTokenLBracket: case WFFeelTokenRBracket:
	case WFFeelTokenLBrace: case WFFeelTokenRBrace: case WFFeelTokenComma: case WFFeelTokenDot:
	case WFFeelTokenColon:
		return WFExpressionTokenPunctuation;
	case WFFeelTokenInvalid:
		return WFExpressionTokenInvalid;
	default:
		return WFExpressionTokenOperator;
	}
}

@implementation WFFeelExpression (WFEditing)

+ (NSArray<NSDictionary *> *)tokensOfText:(NSString *)text place:(WFExpressionPlace)place
{
	NSRange body, opening, closing;
	BOOL camunda7 = NO;
	if (text == nil || !WFExpressionBody(text, place, &body, &camunda7, &opening, &closing)) {
		return @[];
	}
	NSMutableArray *tokens = [NSMutableArray array];
	if (opening.location != NSNotFound) {
		[tokens addObject:WFToken(WFExpressionTokenDelimiter, opening)];
	}
	NSString *inner = [text substringWithRange:body];
	NSArray<WFFeelToken *> *lexed = [[[WFFeelLexer alloc] initWithString:inner camunda7:camunda7] tokens];
	NSSet *keywords = WFFeelKeywords(camunda7);
	NSArray *multiWord = WFFeelMultiWordBuiltins();
	NSUInteger covered = 0;  /* in inner: what the tokens so far reach */
	for (NSUInteger i = 0; i < [lexed count]; i++) {
		WFFeelToken *token = [lexed objectAtIndex:i];
		NSRange range = token.range;
		/* What the lexer skipped that is not space is a comment. */
		if (range.location > covered) {
			NSString *gap = [inner substringWithRange:NSMakeRange(covered, range.location - covered)];
			NSRange slash = [gap rangeOfString:@"/"];
			if (slash.location != NSNotFound) {
				NSString *rest = [gap substringFromIndex:slash.location];
				rest = [rest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				[tokens addObject:WFToken(WFExpressionTokenComment,
				                          NSMakeRange(body.location + covered + slash.location, [rest length]))];
			}
		}
		if (token.kind == WFFeelTokenEnd) {
			break;
		}
		NSString *kind = WFKindOf(token.kind);
		if (token.kind == WFFeelTokenName) {
			WFFeelToken *next = i + 1 < [lexed count] ? [lexed objectAtIndex:i + 1] : nil;
			NSString *called = nil;
			/* A built-in whose name has spaces: string length(...). */
			for (NSString *name in multiWord) {
				if ([inner length] >= range.location + [name length]
				    && [[inner substringWithRange:NSMakeRange(range.location, [name length])] isEqualToString:name]) {
					NSUInteger after = range.location + [name length];
					while (after < [inner length] && [inner characterAtIndex:after] == ' ') {
						after++;
					}
					if (after < [inner length] && [inner characterAtIndex:after] == '(') {
						called = name;
						break;
					}
				}
			}
			if (called != nil) {
				range.length = [called length];
				kind = WFExpressionTokenFunction;
				while (i + 1 < [lexed count] && NSMaxRange([[lexed objectAtIndex:i + 1] range]) <= range.location + range.length) {
					i++;
				}
			} else if (next.kind == WFFeelTokenLParen && ![keywords containsObject:token.text]) {
				kind = WFExpressionTokenFunction;
			} else if ([keywords containsObject:token.text]) {
				kind = WFExpressionTokenKeyword;
			} else {
				kind = WFExpressionTokenName;
			}
		} else if (token.kind == WFFeelTokenAt) {
			WFFeelToken *next = i + 1 < [lexed count] ? [lexed objectAtIndex:i + 1] : nil;
			if (next.kind == WFFeelTokenString) {
				range = NSUnionRange(range, next.range);
				kind = WFExpressionTokenTemporal;
				i++;
			}
		} else if (token.kind == WFFeelTokenInvalid && range.location < [inner length]) {
			unichar c = [inner characterAtIndex:range.location];
			/* A string not closed: string to the end, which is what the
			 * author is typing. */
			if (c == '"' || (camunda7 && c == '\'')) {
				range = NSMakeRange(range.location, [inner length] - range.location);
				kind = WFExpressionTokenString;
			} else if (range.length == 0) {
				range.length = 1;
			}
		}
		if (range.length == 0) {
			continue;
		}
		covered = NSMaxRange(range);
		[tokens addObject:WFToken(kind, NSMakeRange(body.location + range.location, range.length))];
	}
	if (closing.location != NSNotFound) {
		[tokens addObject:WFToken(WFExpressionTokenDelimiter, closing)];
	}
	return tokens;
}

+ (NSError *)problemInText:(NSString *)text place:(WFExpressionPlace)place
{
	NSRange body, opening, closing;
	BOOL camunda7 = NO;
	if (text == nil || !WFExpressionBody(text, place, &body, &camunda7, &opening, &closing)) {
		return nil;
	}
	NSString *inner = [text substringWithRange:body];
	NSError *error = nil;
	if (place == WFExpressionPlaceUnaryTests && !camunda7) {
		/* As the engine reads an input entry: tests of the value, or else
		 * an expression true when it passes; what is wrong is said of the
		 * tests. */
		if (WFFeelParseUnaryTests(inner, &error) != nil || WFFeelParse(inner, NO, NULL) != nil) {
			return nil;
		}
	} else if (WFFeelParse(inner, camunda7, &error) != nil) {
		return nil;
	}
	NSMutableDictionary *info = [[error userInfo] mutableCopy] ?: [NSMutableDictionary dictionary];
	NSValue *where = [info objectForKey:WFErrorRangeKey];
	NSRange range = where != nil ? [where rangeValue] : NSMakeRange(0, [inner length]);
	/* Where is shown by the range; the message says what. */
	if ([info objectForKey:WFFeelExpectedKey] != nil) {
		[info setObject:[info objectForKey:WFFeelExpectedKey] forKey:NSLocalizedDescriptionKey];
		[info removeObjectForKey:WFFeelExpectedKey];
	}
	if ([inner length] == 0) {
		/* Nothing inside ${}: the delimiters are what is wrong. */
		range = NSMakeRange(0, 0);
		[info setObject:@"an empty expression" forKey:NSLocalizedDescriptionKey];
	}
	[info setObject:[NSValue valueWithRange:NSMakeRange(body.location + range.location,
	                                                    MAX(range.length, (NSUInteger)([inner length] == 0 ? 0 : 1)))]
	         forKey:WFErrorRangeKey];
	return [NSError errorWithDomain:[error domain] ?: WFErrorDomain code:[error code] ?: WFErrorCondition userInfo:info];
}

@end

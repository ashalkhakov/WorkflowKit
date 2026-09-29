#import "WFFeelInternal.h"

@implementation WFFeelToken

- (NSString *)description
{
	return self.kind == WFFeelTokenEnd ? @"the end"
		: [NSString stringWithFormat:@"'%@'", self.text];
}

@end

static BOOL
WFFeelIsDigit(unichar c)
{
	return c >= '0' && c <= '9';
}

static BOOL
WFFeelIsNameStart(unichar c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c == '?'
		|| c >= 0x80;
}

static BOOL
WFFeelIsNamePart(unichar c)
{
	return WFFeelIsNameStart(c) || WFFeelIsDigit(c);
}

@implementation WFFeelLexer
{
	NSString *_s;
	NSUInteger _i;
	NSUInteger _n;
	BOOL _camunda7;
}

- (instancetype)initWithString:(NSString *)string camunda7:(BOOL)camunda7
{
	self = [super init];
	if (self) {
		_s = [string copy] ?: @"";
		_n = [_s length];
		_camunda7 = camunda7;
	}
	return self;
}

- (unichar)at:(NSUInteger)i
{
	return i < _n ? [_s characterAtIndex:i] : 0;
}

- (WFFeelToken *)token:(WFFeelTokenKind)kind from:(NSUInteger)start text:(NSString *)text
{
	WFFeelToken *token = [[WFFeelToken alloc] init];
	token.kind = kind;
	token.text = text ?: [_s substringWithRange:NSMakeRange(start, _i - start)];
	token.range = NSMakeRange(start, _i - start);
	return token;
}

- (NSArray<WFFeelToken *> *)tokens
{
	NSMutableArray *tokens = [NSMutableArray array];
	for (;;) {
		WFFeelToken *token = [self next];
		[tokens addObject:token];
		if (token.kind == WFFeelTokenEnd) {
			return tokens;
		}
	}
}

- (WFFeelToken *)next
{
	NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	for (;;) {
		while (_i < _n && [space characterIsMember:[self at:_i]]) {
			_i++;
		}
		/* Comments, as FEEL has them: // to the end of the line, and
		 * between slash-star and star-slash. */
		if ([self at:_i] == '/' && [self at:_i + 1] == '/') {
			while (_i < _n && [self at:_i] != '\n') {
				_i++;
			}
			continue;
		}
		if ([self at:_i] == '/' && [self at:_i + 1] == '*') {
			_i += 2;
			while (_i < _n && !([self at:_i] == '*' && [self at:_i + 1] == '/')) {
				_i++;
			}
			_i = MIN(_i + 2, _n);
			continue;
		}
		break;
	}
	NSUInteger start = _i;
	if (_i >= _n) {
		return [self token:WFFeelTokenEnd from:start text:@""];
	}
	unichar c = [self at:_i];

	if (c == '"' || (c == '\'' && _camunda7)) {
		NSString *text = [self quotedAt:&_i];
		if (text == nil) {
			return [self token:WFFeelTokenInvalid from:start text:nil];
		}
		return [self token:WFFeelTokenString from:start text:text];
	}
	/* A dot starts a number only before a digit: 1..5 is a range. */
	if (WFFeelIsDigit(c) || (c == '.' && WFFeelIsDigit([self at:_i + 1]))) {
		while (WFFeelIsDigit([self at:_i])) {
			_i++;
		}
		if ([self at:_i] == '.' && WFFeelIsDigit([self at:_i + 1])) {
			_i++;
			while (WFFeelIsDigit([self at:_i])) {
				_i++;
			}
		}
		return [self token:WFFeelTokenNumber from:start text:nil];
	}
	if (WFFeelIsNameStart(c)) {
		while (_i < _n && WFFeelIsNamePart([self at:_i])) {
			_i++;
		}
		return [self token:WFFeelTokenName from:start text:nil];
	}

	unichar d = [self at:_i + 1];
	_i++;
	switch (c) {
	case '(': return [self token:WFFeelTokenLParen from:start text:nil];
	case ')': return [self token:WFFeelTokenRParen from:start text:nil];
	case '[': return [self token:WFFeelTokenLBracket from:start text:nil];
	case ']': return [self token:WFFeelTokenRBracket from:start text:nil];
	case '{': return [self token:WFFeelTokenLBrace from:start text:nil];
	case '}': return [self token:WFFeelTokenRBrace from:start text:nil];
	case ',': return [self token:WFFeelTokenComma from:start text:nil];
	case ':': return [self token:WFFeelTokenColon from:start text:nil];
	case '@': return [self token:WFFeelTokenAt from:start text:nil];
	case '+': return [self token:WFFeelTokenPlus from:start text:nil];
	case '-': return [self token:WFFeelTokenMinus from:start text:nil];
	case '/': return [self token:WFFeelTokenSlash from:start text:nil];
	case '.':
		if (d == '.') {
			_i++;
			return [self token:WFFeelTokenDotDot from:start text:nil];
		}
		return [self token:WFFeelTokenDot from:start text:nil];
	case '*':
		if (d == '*') {
			_i++;
			return [self token:WFFeelTokenStarStar from:start text:nil];
		}
		return [self token:WFFeelTokenStar from:start text:nil];
	case '=':
		if (d == '=' && _camunda7) {
			_i++;
		}
		return [self token:WFFeelTokenEqual from:start text:nil];
	case '!':
		if (d == '=') {
			_i++;
			return [self token:WFFeelTokenNotEqual from:start text:nil];
		}
		if (_camunda7) {
			return [self token:WFFeelTokenBang from:start text:nil];
		}
		break;
	case '<':
		if (d == '=') {
			_i++;
			return [self token:WFFeelTokenLessOrEqual from:start text:nil];
		}
		return [self token:WFFeelTokenLess from:start text:nil];
	case '>':
		if (d == '=') {
			_i++;
			return [self token:WFFeelTokenGreaterOrEqual from:start text:nil];
		}
		return [self token:WFFeelTokenGreater from:start text:nil];
	case '&':
		if (d == '&' && _camunda7) {
			_i++;
			return [self token:WFFeelTokenAndAnd from:start text:nil];
		}
		break;
	case '|':
		if (d == '|' && _camunda7) {
			_i++;
			return [self token:WFFeelTokenOrOr from:start text:nil];
		}
		break;
	default:
		break;
	}
	return [self token:WFFeelTokenInvalid from:start text:nil];
}

/* "a \"b\"\n": the text between the quotes with its escapes resolved;
 * nil when the string is not closed or an escape is not one. */
- (NSString *)quotedAt:(NSUInteger *)i
{
	unichar quote = [self at:*i];
	NSMutableString *text = [NSMutableString string];
	NSUInteger j = *i + 1;
	while (j < _n) {
		unichar c = [self at:j];
		if (c == quote) {
			*i = j + 1;
			return text;
		}
		if (c != '\\') {
			[text appendFormat:@"%C", c];
			j++;
			continue;
		}
		unichar e = [self at:j + 1];
		j += 2;
		switch (e) {
		case '"': [text appendString:@"\""]; break;
		case '\'': [text appendString:@"'"]; break;
		case '\\': [text appendString:@"\\"]; break;
		case 'n': [text appendString:@"\n"]; break;
		case 'r': [text appendString:@"\r"]; break;
		case 't': [text appendString:@"\t"]; break;
		case 'u': {
			unsigned value = 0;
			for (NSUInteger k = 0; k < 4; k++) {
				unichar h = [self at:j + k];
				int digit = WFFeelIsDigit(h) ? h - '0'
					: (h >= 'a' && h <= 'f') ? h - 'a' + 10
					: (h >= 'A' && h <= 'F') ? h - 'A' + 10 : -1;
				if (digit < 0) {
					*i = j;
					return nil;
				}
				value = value * 16 + (unsigned)digit;
			}
			j += 4;
			[text appendFormat:@"%C", (unichar)value];
			break;
		}
		default:
			*i = j;
			return nil;
		}
	}
	*i = j;
	return nil;
}

@end

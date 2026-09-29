#import "UDFeelInternal.h"

@implementation UDFeelToken

- (NSString *)description
{
	return self.kind == UDFeelTokenEnd ? @"the end"
		: [NSString stringWithFormat:@"'%@'", self.text];
}

@end

static BOOL
UDFeelIsDigit(unichar c)
{
	return c >= '0' && c <= '9';
}

static BOOL
UDFeelIsNameStart(unichar c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c == '?'
		|| c >= 0x80;
}

static BOOL
UDFeelIsNamePart(unichar c)
{
	return UDFeelIsNameStart(c) || UDFeelIsDigit(c);
}

@implementation UDFeelLexer
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

- (UDFeelToken *)token:(UDFeelTokenKind)kind from:(NSUInteger)start text:(NSString *)text
{
	UDFeelToken *token = [[UDFeelToken alloc] init];
	token.kind = kind;
	token.text = text ?: [_s substringWithRange:NSMakeRange(start, _i - start)];
	token.range = NSMakeRange(start, _i - start);
	return token;
}

- (NSArray<UDFeelToken *> *)tokens
{
	NSMutableArray *tokens = [NSMutableArray array];
	for (;;) {
		UDFeelToken *token = [self next];
		[tokens addObject:token];
		if (token.kind == UDFeelTokenEnd) {
			return tokens;
		}
	}
}

- (UDFeelToken *)next
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
		return [self token:UDFeelTokenEnd from:start text:@""];
	}
	unichar c = [self at:_i];

	if (c == '"' || (c == '\'' && _camunda7)) {
		NSString *text = [self quotedAt:&_i];
		if (text == nil) {
			return [self token:UDFeelTokenInvalid from:start text:nil];
		}
		return [self token:UDFeelTokenString from:start text:text];
	}
	/* A dot starts a number only before a digit: 1..5 is a range. */
	if (UDFeelIsDigit(c) || (c == '.' && UDFeelIsDigit([self at:_i + 1]))) {
		while (UDFeelIsDigit([self at:_i])) {
			_i++;
		}
		if ([self at:_i] == '.' && UDFeelIsDigit([self at:_i + 1])) {
			_i++;
			while (UDFeelIsDigit([self at:_i])) {
				_i++;
			}
		}
		return [self token:UDFeelTokenNumber from:start text:nil];
	}
	if (UDFeelIsNameStart(c)) {
		while (_i < _n && UDFeelIsNamePart([self at:_i])) {
			_i++;
		}
		return [self token:UDFeelTokenName from:start text:nil];
	}

	unichar d = [self at:_i + 1];
	_i++;
	switch (c) {
	case '(': return [self token:UDFeelTokenLParen from:start text:nil];
	case ')': return [self token:UDFeelTokenRParen from:start text:nil];
	case '[': return [self token:UDFeelTokenLBracket from:start text:nil];
	case ']': return [self token:UDFeelTokenRBracket from:start text:nil];
	case '{': return [self token:UDFeelTokenLBrace from:start text:nil];
	case '}': return [self token:UDFeelTokenRBrace from:start text:nil];
	case ',': return [self token:UDFeelTokenComma from:start text:nil];
	case ':': return [self token:UDFeelTokenColon from:start text:nil];
	case '+': return [self token:UDFeelTokenPlus from:start text:nil];
	case '-': return [self token:UDFeelTokenMinus from:start text:nil];
	case '/': return [self token:UDFeelTokenSlash from:start text:nil];
	case '.':
		if (d == '.') {
			_i++;
			return [self token:UDFeelTokenDotDot from:start text:nil];
		}
		return [self token:UDFeelTokenDot from:start text:nil];
	case '*':
		if (d == '*') {
			_i++;
			return [self token:UDFeelTokenStarStar from:start text:nil];
		}
		return [self token:UDFeelTokenStar from:start text:nil];
	case '=':
		if (d == '=' && _camunda7) {
			_i++;
		}
		return [self token:UDFeelTokenEqual from:start text:nil];
	case '!':
		if (d == '=') {
			_i++;
			return [self token:UDFeelTokenNotEqual from:start text:nil];
		}
		if (_camunda7) {
			return [self token:UDFeelTokenBang from:start text:nil];
		}
		break;
	case '<':
		if (d == '=') {
			_i++;
			return [self token:UDFeelTokenLessOrEqual from:start text:nil];
		}
		return [self token:UDFeelTokenLess from:start text:nil];
	case '>':
		if (d == '=') {
			_i++;
			return [self token:UDFeelTokenGreaterOrEqual from:start text:nil];
		}
		return [self token:UDFeelTokenGreater from:start text:nil];
	case '&':
		if (d == '&' && _camunda7) {
			_i++;
			return [self token:UDFeelTokenAndAnd from:start text:nil];
		}
		break;
	case '|':
		if (d == '|' && _camunda7) {
			_i++;
			return [self token:UDFeelTokenOrOr from:start text:nil];
		}
		break;
	default:
		break;
	}
	return [self token:UDFeelTokenInvalid from:start text:nil];
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
				int digit = UDFeelIsDigit(h) ? h - '0'
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

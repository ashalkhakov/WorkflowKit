#import "WFFeelInternal.h"

@interface WFFeelExpression ()
@property (nonatomic, strong) WFFeelNode *root;
- (instancetype)initWithRoot:(WFFeelNode *)root;
@end

@implementation WFFeelExpression

+ (instancetype)expressionWithString:(NSString *)text camunda7:(BOOL)camunda7 error:(NSError **)error
{
	WFFeelNode *root = WFFeelParse(text, camunda7, error);
	if (root == nil) {
		return nil;
	}
	return [[self alloc] initWithRoot:root];
}

+ (instancetype)expressionWithString:(NSString *)text error:(NSError **)error
{
	return [self expressionWithString:text camunda7:NO error:error];
}

+ (instancetype)expressionWithCamunda7String:(NSString *)text error:(NSError **)error
{
	return [self expressionWithString:text camunda7:YES error:error];
}

- (instancetype)initWithRoot:(WFFeelNode *)root
{
	self = [super init];
	if (self) {
		_root = root;
	}
	return self;
}

- (id)valueWithVariables:(NSDictionary *)variables
{
	return WFFeelPublicValue(WFFeelEvaluate(self.root, variables ?: @{}));
}

- (BOOL)evaluateWithVariables:(NSDictionary *)variables error:(NSError **)error
{
	id value = [self valueWithVariables:variables];
	if (WFFeelIsBoolean(value)) {
		return [value boolValue];
	}
	if (!WFFeelIsNull(value) && error != NULL) {
		*error = [NSError errorWithDomain:WFErrorDomain
		                             code:WFErrorCondition
		                         userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:
			@"condition \"%@\" is %@, not true or false", [self expressionString],
			WFFeelLiteralText(value)] }];
	}
	return NO;
}

- (NSString *)expressionString
{
	return [self.root description];
}

- (NSString *)description
{
	return [self expressionString];
}

@end

#pragma mark - Camunda attributes

WFFeelExpression *
WFAttributeExpression(NSString *text, WFAttributeKind kind, NSError **error)
{
	if (text == nil) {
		return nil;
	}
	NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (([trimmed hasPrefix:@"${"] || [trimmed hasPrefix:@"#{"]) && [trimmed hasSuffix:@"}"]) {
		return [WFFeelExpression expressionWithCamunda7String:
			[trimmed substringWithRange:NSMakeRange(2, [trimmed length] - 3)] error:error];
	}
	if ([trimmed hasPrefix:@"="]) {
		return [WFFeelExpression expressionWithString:[trimmed substringFromIndex:1] error:error];
	}
	NSString *literal = nil;
	switch (kind) {
	case WFAttributeKindString:
		literal = WFFeelLiteralText(trimmed);
		break;
	case WFAttributeKindList: {
		NSMutableArray *items = [NSMutableArray array];
		for (NSString *part in [trimmed componentsSeparatedByString:@","]) {
			NSString *item = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if ([item length] > 0) {
				[items addObject:item];
			}
		}
		literal = WFFeelLiteralText(items);
		break;
	}
	case WFAttributeKindDate: {
		id date = WFFeelParseDateTime(trimmed) ?: (id)WFFeelParseDate(trimmed);
		literal = date != nil ? WFFeelLiteralText(date) : nil;
		break;
	}
	case WFAttributeKindNumber: {
		NSScanner *scanner = [NSScanner scannerWithString:trimmed];
		long long whole = 0;
		literal = [scanner scanLongLong:&whole] && [scanner isAtEnd]
			? [NSString stringWithFormat:@"%lld", whole] : nil;
		break;
	}
	}
	if (literal == nil) {
		if (error != NULL) {
			NSArray *kinds = @[ @"text", @"a list", @"an ISO-8601 date", @"a whole number" ];
			*error = [NSError errorWithDomain:WFErrorDomain code:WFErrorCondition userInfo:@{
				NSLocalizedDescriptionKey: [NSString stringWithFormat:@"\"%@\" is not %@ or an expression",
					trimmed, [kinds objectAtIndex:(NSUInteger)kind]] }];
		}
		return nil;
	}
	return [WFFeelExpression expressionWithString:literal error:error];
}

NSString *
WFAttributeText(WFFeelExpression *expression, WFAttributeKind kind)
{
	if (expression == nil) {
		return nil;
	}
	WFFeelNode *root = [expression root];
	if (root.kind == WFFeelNodeLiteral) {
		id value = root.value;
		if (kind == WFAttributeKindString && [value isKindOfClass:[NSString class]]) {
			return value;
		}
		if (kind == WFAttributeKindDate && WFFeelIsTemporal(value)) {
			return WFFeelTemporalText(value);
		}
		if (kind == WFAttributeKindNumber && WFFeelIsNumber(value)) {
			return [expression expressionString];
		}
	}
	if (kind == WFAttributeKindList && root.kind == WFFeelNodeList) {
		NSMutableArray *items = [NSMutableArray array];
		for (WFFeelNode *item in root.children) {
			if (item.kind != WFFeelNodeLiteral || ![item.value isKindOfClass:[NSString class]]
			    || [item.value rangeOfString:@","].location != NSNotFound) {
				items = nil;
				break;
			}
			[items addObject:item.value];
		}
		if (items != nil) {
			return [items componentsJoinedByString:@","];
		}
	}
	return [@"=" stringByAppendingString:[expression expressionString]];
}

#import "UDCondition.h"

@implementation UDComparisonCondition

- (instancetype)initWithKey:(NSString *)key
                         op:(UDComparisonOp)op
                      value:(id)value
{
	self = [super init];
	if (self) {
		_key = [key copy];
		_op = op;
		_value = value;
	}
	return self;
}

+ (instancetype)key:(NSString *)key equals:(id)value
{
	return [[self alloc] initWithKey:key op:UDComparisonOpEqual value:value];
}

+ (instancetype)key:(NSString *)key greaterThan:(id)value
{
	return [[self alloc] initWithKey:key op:UDComparisonOpGreater value:value];
}

- (NSComparisonResult)compareLeft:(id)left right:(id)right
{
	if ([left isKindOfClass:[NSNumber class]]
	    && [right isKindOfClass:[NSNumber class]]) {
		return [(NSNumber *)left compare:(NSNumber *)right];
	}
	if ([left isKindOfClass:[NSString class]]
	    && [right isKindOfClass:[NSString class]]) {
		return [(NSString *)left compare:(NSString *)right];
	}
	if ([left respondsToSelector:@selector(compare:)]) {
		return [left compare:right];
	}
	return NSOrderedSame;
}

- (BOOL)evaluateWithVariables:(NSDictionary *)variables
                        error:(NSError **)error
{
	id left = [variables objectForKey:self.key];
	id right = self.value;

	if (self.op == UDComparisonOpEqual) {
		if (left == nil) {
			return right == nil || right == [NSNull null];
		}
		return [left isEqual:right];
	}
	if (self.op == UDComparisonOpNotEqual) {
		if (left == nil) {
			return !(right == nil || right == [NSNull null]);
		}
		return ![left isEqual:right];
	}
	if (left == nil) {
		return NO;
	}

	NSComparisonResult cmp = [self compareLeft:left right:right];
	switch (self.op) {
	case UDComparisonOpGreater:
		return cmp == NSOrderedDescending;
	case UDComparisonOpGreaterOrEqual:
		return cmp != NSOrderedAscending;
	case UDComparisonOpLess:
		return cmp == NSOrderedAscending;
	case UDComparisonOpLessOrEqual:
		return cmp != NSOrderedDescending;
	default:
		return NO;
	}
}

- (NSString *)expressionString
{
	/* FEEL: `=` for equality, `true`/`false`, double-quoted strings. */
	NSString *op = @"=";
	switch (self.op) {
	case UDComparisonOpNotEqual: op = @"!="; break;
	case UDComparisonOpGreater: op = @">"; break;
	case UDComparisonOpGreaterOrEqual: op = @">="; break;
	case UDComparisonOpLess: op = @"<"; break;
	case UDComparisonOpLessOrEqual: op = @"<="; break;
	default: break;
	}

	id value = self.value;
	NSString *rhs = @"null";
	if ([value isKindOfClass:[NSNumber class]]) {
		NSNumber *number = (NSNumber *)value;
		if (strcmp([number objCType], @encode(BOOL)) == 0
		    || strcmp([number objCType], @encode(char)) == 0) {
			rhs = [number boolValue] ? @"true" : @"false";
		} else {
			rhs = [number stringValue];
		}
	} else if ([value isKindOfClass:[NSString class]]) {
		NSString *escaped =
			[(NSString *)value stringByReplacingOccurrencesOfString:@"\""
			                                           withString:@"\\\""];
		rhs = [NSString stringWithFormat:@"\"%@\"", escaped];
	} else if (value != nil) {
		rhs = [value description];
	}
	return [NSString stringWithFormat:@"%@ %@ %@", self.key, op, rhs];
}

+ (instancetype)conditionWithExpression:(NSString *)expression
                                  error:(NSError **)error
{
	NSString *text = [expression stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([text length] == 0) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorCondition
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"empty condition expression" }];
		}
		return nil;
	}

	NSScanner *scanner = [NSScanner scannerWithString:text];
	[scanner setCharactersToBeSkipped:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	NSString *key = nil;
	NSCharacterSet *ident = [NSCharacterSet characterSetWithCharactersInString:
		@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
	if (![scanner scanCharactersFromSet:ident intoString:&key] || [key length] == 0) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorCondition
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"condition key expected" }];
		}
		return nil;
	}

	UDComparisonOp op = UDComparisonOpEqual;
	if ([scanner scanString:@">=" intoString:NULL]) {
		op = UDComparisonOpGreaterOrEqual;
	} else if ([scanner scanString:@"<=" intoString:NULL]) {
		op = UDComparisonOpLessOrEqual;
	} else if ([scanner scanString:@"!=" intoString:NULL]) {
		op = UDComparisonOpNotEqual;
	} else if ([scanner scanString:@"==" intoString:NULL]
	           || [scanner scanString:@"=" intoString:NULL]) {
		op = UDComparisonOpEqual;
	} else if ([scanner scanString:@">" intoString:NULL]) {
		op = UDComparisonOpGreater;
	} else if ([scanner scanString:@"<" intoString:NULL]) {
		op = UDComparisonOpLess;
	} else {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorCondition
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"condition operator expected" }];
		}
		return nil;
	}

	id value = nil;
	if ([scanner scanString:@"YES" intoString:NULL]
	    || [scanner scanString:@"true" intoString:NULL]) {
		value = @YES;
	} else if ([scanner scanString:@"NO" intoString:NULL]
	           || [scanner scanString:@"false" intoString:NULL]) {
		value = @NO;
	} else if ([scanner scanString:@"\"" intoString:NULL]) {
		NSMutableString *buf = [NSMutableString string];
		while (![scanner isAtEnd]) {
			NSString *chunk = nil;
			if ([scanner scanUpToString:@"\"" intoString:&chunk]) {
				[buf appendString:chunk];
			}
			if ([scanner scanString:@"\"" intoString:NULL]) {
				break;
			}
		}
		value = buf;
	} else {
		double number = 0;
		if ([scanner scanDouble:&number]) {
			if (number == (NSInteger)number) {
				value = [NSNumber numberWithInteger:(NSInteger)number];
			} else {
				value = [NSNumber numberWithDouble:number];
			}
		}
	}

	if (value == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorCondition
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"condition value expected" }];
		}
		return nil;
	}
	return [[self alloc] initWithKey:key op:op value:value];
}

@end

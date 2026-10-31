#import "WFCondition.h"

/* WorkflowKit's own: exported where it is built for Windows (the GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef WORKFLOWKIT_EXPORT
#define WORKFLOWKIT_EXPORT FOUNDATION_EXPORT
#endif

/*
 * An expression in FEEL, the expression language of DMN, parsed once and
 * evaluated over variables.
 *
 * The engine implements FEEL's core: null, boolean, number (decimal),
 * string, list, context and range values, dates, dates and times and
 * both kinds of duration (@"2020-01-01", @"P1D"); names, paths (a.b), filters
 * and indexes (list[item > 1], list[1]); arithmetic, comparison,
 * between, in with unary tests (x in [1..10], x in (< 5, > 10)), and and
 * or with FEEL's three-valued logic; if/then/else, for/return,
 * some/every/satisfies; and the built-in functions for strings, lists and
 * numbers. Names are single words; the built-ins' own names may have
 * spaces (string length). Errors are null, as FEEL has it: a missing
 * variable, a comparison across types, a division by zero.
 *
 * Camunda 7 files write `${...}`; what is inside is read as a small
 * subset: literals (single- or double-quoted strings), names and paths,
 * arithmetic (+ - * /), comparisons (== != < <= > >= and eq ne lt le gt
 * ge), && || ! (and or not), and parentheses. It becomes the same FEEL;
 * a division is a decimal one, 3/5 is 0.6.
 */
/* Where text in a BPMN file is, which says how the engine reads it. */
typedef NS_ENUM(NSInteger, WFExpressionPlace) {
	/* A condition, a cardinality, a collection: FEEL, unless it is
	 * ${...} (the Camunda 7 subset); a leading = is FEEL too. */
	WFExpressionPlaceExpression = 0,
	/* An attribute such as camunda:assignee or a timer's value: literal
	 * text, unless it is ${...} or begins with =. */
	WFExpressionPlaceAttribute,
	/* A decision table's input entry: FEEL's unary tests -- a value,
	 * < 10, [1..5], "a","b", not(...), - for any -- or else an
	 * expression true when the input passes; ${...} as above. */
	WFExpressionPlaceUnaryTests
};

/* What a token of an expression's text is, for an editor to colour. */
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenName;      /* amount, order.total */
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenKeyword;   /* if, and, true, null, eq */
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenFunction;  /* a name called: sum(, string length( */
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenNumber;
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenString;
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenTemporal;  /* @"2020-01-01" */
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenOperator;  /* + <= && .. */
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenPunctuation; /* ( ) [ ] { } , . : */
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenDelimiter; /* ${ and }, a leading = */
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenComment;
WORKFLOWKIT_EXPORT NSString * const WFExpressionTokenInvalid;   /* a character that begins no token */

@interface WFFeelExpression : NSObject <WFCondition>

- (instancetype)init NS_UNAVAILABLE;

/* nil, with a WFErrorCondition error saying where, for text that
 * is not FEEL the engine implements. */
+ (instancetype)expressionWithString:(NSString *)text error:(NSError **)error;
/* The inside of a Camunda 7 `${...}`. */
+ (instancetype)expressionWithCamunda7String:(NSString *)text error:(NSError **)error;

/* The value over the variables: NSNull for null, an NSDecimalNumber for a
 * number, a boolean NSNumber, an NSString, an NSArray for a list, an
 * NSDictionary for a context; an NSDate for a date and time, and for a
 * date its midnight in UTC; a duration as its ISO-8601 text, P1DT2H. */
- (id)valueWithVariables:(NSDictionary *)variables;

/* Canonical FEEL: parsing it gives the same expression. */
- (NSString *)expressionString;

@end

/* For an editor of expressions. */
@interface WFFeelExpression (WFEditing)
/* The text as an editor shows it, read as the engine reads text in that
 * place: its tokens, in order, each a dictionary of @"kind" (one of the
 * kinds above) and @"range" (an NSValue); none for literal text. */
+ (NSArray<NSDictionary *> *)tokensOfText:(NSString *)text place:(WFExpressionPlace)place;
/* Why the engine would not read the text there; nil when it would, and for
 * literal text. Its WFErrorRangeKey says where in the text. */
+ (NSError *)problemInText:(NSString *)text place:(WFExpressionPlace)place;
@end

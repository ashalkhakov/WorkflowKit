#import "UDCondition.h"

/*
 * An expression in FEEL, the expression language of DMN, parsed once and
 * evaluated over variables.
 *
 * The engine implements FEEL's core: null, boolean, number (decimal),
 * string, list, context and range values; names, paths (a.b), filters
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
@interface UDFeelExpression : NSObject <UDCondition>

- (instancetype)init NS_UNAVAILABLE;

/* nil, with a UDWorkflowErrorCondition error saying where, for text that
 * is not FEEL the engine implements. */
+ (instancetype)expressionWithString:(NSString *)text error:(NSError **)error;
/* The inside of a Camunda 7 `${...}`. */
+ (instancetype)expressionWithCamunda7String:(NSString *)text error:(NSError **)error;

/* The value over the variables: NSNull for null, an NSDecimalNumber for a
 * number, a boolean NSNumber, an NSString, an NSDate, an NSArray for a
 * list, an NSDictionary for a context. */
- (id)valueWithVariables:(NSDictionary *)variables;

/* Canonical FEEL: parsing it gives the same expression. */
- (NSString *)expressionString;

@end

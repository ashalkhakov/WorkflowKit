/*
 * The FEEL engine's parts, internal to the library: a lexer that turns the
 * text into tokens, a recursive descent parser with one method per
 * precedence level (DMN 1.3, section 10.3.1), the tree it builds, and an
 * evaluator that walks the tree. WFFeelExpression, in WFFeel.h, is the way
 * in from the rest of the engine.
 *
 * Every node describes itself as canonical FEEL, with parentheses only
 * where precedence needs them, so parsing what a node describes gives the
 * same tree back.
 */
#import "WFFeel.h"

typedef NS_ENUM(NSInteger, WFFeelTokenKind) {
	WFFeelTokenEnd = 0,
	WFFeelTokenName,        /* amount, if, and, string -- keywords are names */
	WFFeelTokenNumber,      /* 12, 1.5, .5 (text as written) */
	WFFeelTokenString,      /* "text" (text unescaped) */
	WFFeelTokenLParen,
	WFFeelTokenRParen,
	WFFeelTokenLBracket,
	WFFeelTokenRBracket,
	WFFeelTokenLBrace,
	WFFeelTokenRBrace,
	WFFeelTokenComma,
	WFFeelTokenDot,
	WFFeelTokenDotDot,
	WFFeelTokenColon,
	WFFeelTokenPlus,
	WFFeelTokenMinus,
	WFFeelTokenStar,
	WFFeelTokenStarStar,
	WFFeelTokenSlash,
	WFFeelTokenEqual,       /* =, and == in Camunda 7 */
	WFFeelTokenNotEqual,
	WFFeelTokenLess,
	WFFeelTokenLessOrEqual,
	WFFeelTokenGreater,
	WFFeelTokenGreaterOrEqual,
	WFFeelTokenAndAnd,      /* Camunda 7 only */
	WFFeelTokenOrOr,        /* Camunda 7 only */
	WFFeelTokenBang,        /* Camunda 7 only */
	WFFeelTokenAt,          /* @, before a temporal literal's string */
	WFFeelTokenInvalid      /* a character that begins no token */
};

@interface WFFeelToken : NSObject
@property (nonatomic) WFFeelTokenKind kind;
@property (nonatomic, copy) NSString *text;
/* In the source, for errors. */
@property (nonatomic) NSRange range;
@end

@interface WFFeelLexer : NSObject
/* camunda7: the `${...}` syntax, whose strings may be single-quoted and
 * whose operators include == && || and !. */
- (instancetype)initWithString:(NSString *)string camunda7:(BOOL)camunda7;
/* Every token, the end token last. */
- (NSArray<WFFeelToken *> *)tokens;
@end

typedef NS_ENUM(NSInteger, WFFeelNodeKind) {
	WFFeelNodeLiteral,      /* value: NSNull, a boolean NSNumber, an NSDecimalNumber, an NSString */
	WFFeelNodeName,         /* name */
	WFFeelNodePath,         /* name, of children[0] */
	WFFeelNodeFilter,       /* children[0][children[1]] */
	WFFeelNodeCall,         /* name (a built-in); children the arguments */
	WFFeelNodeNegate,       /* -children[0] */
	WFFeelNodeBinary,       /* op; children[0] op children[1] */
	WFFeelNodeBetween,      /* children[0] between children[1] and children[2] */
	WFFeelNodeIn,           /* children[0] in the tests children[1...] */
	WFFeelNodeUnaryTest,    /* op (a comparison) and children[0]: < 10; op Equal: a value to match */
	WFFeelNodeList,         /* children */
	WFFeelNodeRange,        /* children[0]..children[1]; startIncluded, endIncluded */
	WFFeelNodeContext,      /* names the keys, children their values */
	WFFeelNodeIf,           /* if children[0] then children[1] else children[2] */
	WFFeelNodeFor,          /* for names[i] in children[i] ... return children.lastObject */
	WFFeelNodeSome,         /* some names[i] in children[i] ... satisfies children.lastObject */
	WFFeelNodeEvery         /* every ... likewise */
};

typedef NS_ENUM(NSInteger, WFFeelOperator) {
	WFFeelOperatorNone = 0,
	WFFeelOperatorOr,
	WFFeelOperatorAnd,
	WFFeelOperatorEqual,
	WFFeelOperatorNotEqual,
	WFFeelOperatorLess,
	WFFeelOperatorLessOrEqual,
	WFFeelOperatorGreater,
	WFFeelOperatorGreaterOrEqual,
	WFFeelOperatorAdd,
	WFFeelOperatorSubtract,
	WFFeelOperatorMultiply,
	WFFeelOperatorDivide,
	WFFeelOperatorModulo,   /* modulo(a, b); FEEL has no operator for it */
	WFFeelOperatorPower
};

@interface WFFeelNode : NSObject
@property (nonatomic) WFFeelNodeKind kind;
@property (nonatomic) WFFeelOperator op;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) id value;
@property (nonatomic, copy) NSArray<WFFeelNode *> *children;
@property (nonatomic, copy) NSArray<NSString *> *names;
@property (nonatomic) BOOL startIncluded;
@property (nonatomic) BOOL endIncluded;
+ (instancetype)node:(WFFeelNodeKind)kind;
+ (instancetype)literal:(id)value;
+ (instancetype)binary:(WFFeelOperator)op left:(WFFeelNode *)left right:(WFFeelNode *)right;
/* How tightly it binds, for printing: 1, the textual forms, to 9, a
 * primary. */
- (NSInteger)precedence;
/* The node as canonical FEEL. */
- (NSString *)description;
@end

/* Parses FEEL, or the Camunda 7 subset: literals, names and paths,
 * + - * /, comparisons, && || ! and their word forms, parentheses. nil, with an
 * error saying where, for text that is neither. */
WFFeelNode *WFFeelParse(NSString *text, BOOL camunda7, NSError **error);

/* The node's value over the variables: FEEL's null is NSNull. Never nil. */
id WFFeelEvaluate(WFFeelNode *node, NSDictionary *variables);

/* Whether a built-in function of that name exists, and the multi-word
 * names among them, longest first. */
BOOL WFFeelIsBuiltin(NSString *name);
NSArray<NSString *> *WFFeelMultiWordBuiltins(void);

@interface WFFeelExpression (WFInternal)
- (WFFeelNode *)root;
@end

/* A range's value: [1..10], (0..1], x between a and b. */
@interface WFFeelRange : NSObject
@property (nonatomic, strong) id start;
@property (nonatomic, strong) id end;
@property (nonatomic) BOOL startIncluded;
@property (nonatomic) BOOL endIncluded;
@end

/* A date without a time. */
@interface WFFeelDateValue : NSObject
@property (nonatomic, readonly) NSInteger year;
@property (nonatomic, readonly) NSInteger month;
@property (nonatomic, readonly) NSInteger day;
/* nil for a day the calendar does not have. */
+ (instancetype)year:(NSInteger)year month:(NSInteger)month day:(NSInteger)day;
/* The date of that instant, in UTC. */
+ (instancetype)dateOf:(NSDate *)date;
- (NSDate *)startOfDay;
@end

/* A years-and-months duration (in months) or a days-and-time one (in
 * seconds); FEEL keeps the two apart. */
@interface WFFeelDuration : NSObject
@property (nonatomic, readonly) BOOL yearsAndMonths;
@property (nonatomic, readonly) long long months;
@property (nonatomic, readonly) double seconds;
+ (instancetype)months:(long long)months;
+ (instancetype)seconds:(double)seconds;
@end

/* ISO-8601 text as FEEL reads it: nil when it is not one. */
WFFeelDateValue *WFFeelParseDate(NSString *text);
NSDate *WFFeelParseDateTime(NSString *text);
WFFeelDuration *WFFeelParseDuration(NSString *text);
/* A date and time, a date, or a duration. */
id WFFeelParseTemporal(NSString *text);
/* Its ISO-8601 text; nil for a value that is not temporal. */
NSString *WFFeelTemporalText(id value);
BOOL WFFeelIsTemporal(id value);
BOOL WFFeelTemporalOrder(id a, id b, NSComparisonResult *result);
/* nil when neither operand is temporal. */
id WFFeelTemporalArithmetic(WFFeelOperator op, id a, id b);
id WFFeelTemporalNegate(id value);
id WFFeelTemporalProperty(id value, NSString *name);
WFFeelDateValue *WFFeelToday(void);
/* A value as the public API gives it out. */
id WFFeelPublicValue(id value);

/* Between the evaluator and the built-in functions. */
id WFFeelCall(NSString *name, NSArray *arguments);
/* A comparison: a boolean NSNumber, or NSNull when the values do not
 * compare. */
id WFFeelCompareValues(WFFeelOperator op, id a, id b);
id WFFeelValuesEqual(id a, id b);
/* + - * / ** and modulo over numbers (and + over strings); NSNull
 * otherwise. */
id WFFeelArithmetic(WFFeelOperator op, id a, id b);
/* The decimal, or NSNull when it is not a number. */
id WFFeelNumberResult(NSDecimalNumber *number);

/* What a Camunda attribute's literal text is: a user, users or groups
 * separated by commas, a date, a number. */
typedef NS_ENUM(NSInteger, WFAttributeKind) {
	WFAttributeKindString = 0,
	WFAttributeKindList,
	WFAttributeKindDate,
	WFAttributeKindNumber
};

/* A Camunda attribute's value as an expression: ${...} or #{...} is the
 * Camunda 7 subset, =... FEEL, and anything else literal text of the
 * kind. nil, with an error, for text that is none of these. */
WFFeelExpression *WFAttributeExpression(NSString *text, WFAttributeKind kind, NSError **error);
/* The expression back as attribute text: a literal as its plain text, a
 * computed value as =FEEL. */
NSString *WFAttributeText(WFFeelExpression *expression, WFAttributeKind kind);

/* FEEL's view of a value. */
BOOL WFFeelIsNull(id value);
BOOL WFFeelIsBoolean(id value);
BOOL WFFeelIsNumber(id value);
/* A number as the decimal FEEL computes with. */
NSDecimalNumber *WFFeelDecimal(NSNumber *number);
/* A literal as FEEL writes it. */
NSString *WFFeelLiteralText(id value);

/*
 * The FEEL engine's parts, internal to the library: a lexer that turns the
 * text into tokens, a recursive descent parser with one method per
 * precedence level (DMN 1.3, section 10.3.1), the tree it builds, and an
 * evaluator that walks the tree. UDFeelExpression, in UDFeel.h, is the way
 * in from the rest of the engine.
 *
 * Every node describes itself as canonical FEEL, with parentheses only
 * where precedence needs them, so parsing what a node describes gives the
 * same tree back.
 */
#import "UDFeel.h"

typedef NS_ENUM(NSInteger, UDFeelTokenKind) {
	UDFeelTokenEnd = 0,
	UDFeelTokenName,        /* amount, if, and, string -- keywords are names */
	UDFeelTokenNumber,      /* 12, 1.5, .5 (text as written) */
	UDFeelTokenString,      /* "text" (text unescaped) */
	UDFeelTokenLParen,
	UDFeelTokenRParen,
	UDFeelTokenLBracket,
	UDFeelTokenRBracket,
	UDFeelTokenLBrace,
	UDFeelTokenRBrace,
	UDFeelTokenComma,
	UDFeelTokenDot,
	UDFeelTokenDotDot,
	UDFeelTokenColon,
	UDFeelTokenPlus,
	UDFeelTokenMinus,
	UDFeelTokenStar,
	UDFeelTokenStarStar,
	UDFeelTokenSlash,
	UDFeelTokenEqual,       /* =, and == in Camunda 7 */
	UDFeelTokenNotEqual,
	UDFeelTokenLess,
	UDFeelTokenLessOrEqual,
	UDFeelTokenGreater,
	UDFeelTokenGreaterOrEqual,
	UDFeelTokenAndAnd,      /* Camunda 7 only */
	UDFeelTokenOrOr,        /* Camunda 7 only */
	UDFeelTokenBang,        /* Camunda 7 only */
	UDFeelTokenInvalid      /* a character that begins no token */
};

@interface UDFeelToken : NSObject
@property (nonatomic) UDFeelTokenKind kind;
@property (nonatomic, copy) NSString *text;
/* In the source, for errors. */
@property (nonatomic) NSRange range;
@end

@interface UDFeelLexer : NSObject
/* camunda7: the `${...}` syntax, whose strings may be single-quoted and
 * whose operators include == && || and !. */
- (instancetype)initWithString:(NSString *)string camunda7:(BOOL)camunda7;
/* Every token, the end token last. */
- (NSArray<UDFeelToken *> *)tokens;
@end

typedef NS_ENUM(NSInteger, UDFeelNodeKind) {
	UDFeelNodeLiteral,      /* value: NSNull, a boolean NSNumber, an NSDecimalNumber, an NSString */
	UDFeelNodeName,         /* name */
	UDFeelNodePath,         /* name, of children[0] */
	UDFeelNodeFilter,       /* children[0][children[1]] */
	UDFeelNodeCall,         /* name (a built-in); children the arguments */
	UDFeelNodeNegate,       /* -children[0] */
	UDFeelNodeBinary,       /* op; children[0] op children[1] */
	UDFeelNodeBetween,      /* children[0] between children[1] and children[2] */
	UDFeelNodeIn,           /* children[0] in the tests children[1...] */
	UDFeelNodeUnaryTest,    /* op (a comparison) and children[0]: < 10; op Equal: a value to match */
	UDFeelNodeList,         /* children */
	UDFeelNodeRange,        /* children[0]..children[1]; startIncluded, endIncluded */
	UDFeelNodeContext,      /* names the keys, children their values */
	UDFeelNodeIf,           /* if children[0] then children[1] else children[2] */
	UDFeelNodeFor,          /* for names[i] in children[i] ... return children.lastObject */
	UDFeelNodeSome,         /* some names[i] in children[i] ... satisfies children.lastObject */
	UDFeelNodeEvery         /* every ... likewise */
};

typedef NS_ENUM(NSInteger, UDFeelOperator) {
	UDFeelOperatorNone = 0,
	UDFeelOperatorOr,
	UDFeelOperatorAnd,
	UDFeelOperatorEqual,
	UDFeelOperatorNotEqual,
	UDFeelOperatorLess,
	UDFeelOperatorLessOrEqual,
	UDFeelOperatorGreater,
	UDFeelOperatorGreaterOrEqual,
	UDFeelOperatorAdd,
	UDFeelOperatorSubtract,
	UDFeelOperatorMultiply,
	UDFeelOperatorDivide,
	UDFeelOperatorModulo,   /* modulo(a, b); FEEL has no operator for it */
	UDFeelOperatorPower
};

@interface UDFeelNode : NSObject
@property (nonatomic) UDFeelNodeKind kind;
@property (nonatomic) UDFeelOperator op;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) id value;
@property (nonatomic, copy) NSArray<UDFeelNode *> *children;
@property (nonatomic, copy) NSArray<NSString *> *names;
@property (nonatomic) BOOL startIncluded;
@property (nonatomic) BOOL endIncluded;
+ (instancetype)node:(UDFeelNodeKind)kind;
+ (instancetype)literal:(id)value;
+ (instancetype)binary:(UDFeelOperator)op left:(UDFeelNode *)left right:(UDFeelNode *)right;
/* How tightly it binds, for printing: 1, the textual forms, to 9, a
 * primary. */
- (NSInteger)precedence;
/* The node as canonical FEEL. */
- (NSString *)description;
@end

/* Parses FEEL, or the Camunda 7 subset: literals, names and paths,
 * + - * /, comparisons, && || ! and their word forms, parentheses. nil, with an
 * error saying where, for text that is neither. */
UDFeelNode *UDFeelParse(NSString *text, BOOL camunda7, NSError **error);

/* The node's value over the variables: FEEL's null is NSNull. Never nil. */
id UDFeelEvaluate(UDFeelNode *node, NSDictionary *variables);

/* Whether a built-in function of that name exists, and the multi-word
 * names among them, longest first. */
BOOL UDFeelIsBuiltin(NSString *name);
NSArray<NSString *> *UDFeelMultiWordBuiltins(void);

/* A range's value: [1..10], (0..1], x between a and b. */
@interface UDFeelRange : NSObject
@property (nonatomic, strong) id start;
@property (nonatomic, strong) id end;
@property (nonatomic) BOOL startIncluded;
@property (nonatomic) BOOL endIncluded;
@end

/* Between the evaluator and the built-in functions. */
id UDFeelCall(NSString *name, NSArray *arguments);
/* A comparison: a boolean NSNumber, or NSNull when the values do not
 * compare. */
id UDFeelCompareValues(UDFeelOperator op, id a, id b);
id UDFeelValuesEqual(id a, id b);
/* + - * / ** and modulo over numbers (and + over strings); NSNull
 * otherwise. */
id UDFeelArithmetic(UDFeelOperator op, id a, id b);
/* The decimal, or NSNull when it is not a number. */
id UDFeelNumberResult(NSDecimalNumber *number);

/* FEEL's view of a value. */
BOOL UDFeelIsNull(id value);
BOOL UDFeelIsBoolean(id value);
BOOL UDFeelIsNumber(id value);
/* A number as the decimal FEEL computes with. */
NSDecimalNumber *UDFeelDecimal(NSNumber *number);
/* A literal as FEEL writes it. */
NSString *UDFeelLiteralText(id value);

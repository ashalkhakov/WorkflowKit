#import "WFTypes.h"

@class WFFeelExpression;

/* How a decision table's matching rules become its result, as DMN's
 * hitPolicy says. Camunda 7's: PRIORITY and OUTPUT ORDER are refused. */
typedef NS_ENUM(NSInteger, WFHitPolicy) {
	/* At most one rule may match. */
	WFHitPolicyUnique = 0,
	/* The first matching rule, in the table's order. */
	WFHitPolicyFirst,
	/* Any matching rule: they must all give the same outputs. */
	WFHitPolicyAny,
	/* Every matching rule, in the table's order. */
	WFHitPolicyRuleOrder,
	/* Every matching rule, in no particular order, or with an aggregation
	 * one value from them all. */
	WFHitPolicyCollect
};

/* A COLLECT table's aggregation over its single output. */
typedef NS_ENUM(NSInteger, WFCollectAggregation) {
	WFCollectAggregationNone = 0,
	WFCollectAggregationSum,
	WFCollectAggregationMin,
	WFCollectAggregationMax,
	WFCollectAggregationCount
};

/* A decision table's input: the expression over the variables whose value
 * the rules' entries test, as that type. */
@interface WFDecisionInput : NSObject
@property (nonatomic, readonly, copy) NSString *inputId;
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, strong) WFFeelExpression *expression;
/* string, boolean, integer, long, double or date; nil for any. */
@property (nonatomic, readonly, copy) NSString *typeRef;
/* The name the entries see the value under, besides ?: camunda:inputVariable,
 * cellInput when not set. */
@property (nonatomic, readonly, copy) NSString *inputVariable;
@end

/* A decision table's output: the name its value has in a rule's result. */
@interface WFDecisionOutput : NSObject
@property (nonatomic, readonly, copy) NSString *outputId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, copy) NSString *typeRef;
@end

/* One rule: an input entry per input, unary tests of its value (nil for
 * any), and an output entry per output (NSNull for none). */
@interface WFDecisionRule : NSObject
@property (nonatomic, readonly, copy) NSString *ruleId;
@property (nonatomic, readonly, copy) NSArray *inputEntries;
@property (nonatomic, readonly, copy) NSArray *outputEntries;
@end

@interface WFDecisionTable : NSObject
@property (nonatomic, readonly) WFHitPolicy hitPolicy;
@property (nonatomic, readonly) WFCollectAggregation aggregation;
@property (nonatomic, readonly, copy) NSArray<WFDecisionInput *> *inputs;
@property (nonatomic, readonly, copy) NSArray<WFDecisionOutput *> *outputs;
@property (nonatomic, readonly, copy) NSArray<WFDecisionRule *> *rules;
@end

/*
 * What a decision gave: one result per matching rule, each its outputs by
 * name -- a rule whose output entry is empty has no value for it. A
 * literal expression gives one result holding its variable.
 */
@interface WFDecisionResult : NSObject
@property (nonatomic, readonly, copy) NSArray<NSDictionary<NSString *, id> *> *resultList;
- (instancetype)initWithResultList:(NSArray<NSDictionary<NSString *, id> *> *)resultList;
/* The only result: nil for none, and nil with an error for several. */
- (NSDictionary<NSString *, id> *)singleResult:(NSError **)error;
/* The only result's only value: nil for none, and nil with an error for
 * several results or outputs. NSNull when that one value is null. */
- (id)singleEntry:(NSError **)error;
/* The value of the output of that name in each result, in order. */
- (NSArray *)collectEntries:(NSString *)name;
@end

/*
 * A decision, as a DMN file defines it: a decision table or a literal
 * expression, evaluated over variables. A decision may require others of
 * the same file; they are evaluated first, and their outputs are
 * variables of the one that requires them: each output's value, or, when
 * the required decision had several results, the list of them.
 *
 * Deployed, a decision has a version per key, as a process does.
 */
@interface WFDecisionDefinition : NSObject
/* The decision's id, the key its versions are counted under. */
@property (nonatomic, readonly, copy) NSString *key;
@property (nonatomic, readonly, copy) NSString *name;
/* camunda:versionTag; nil when not set. */
@property (nonatomic, readonly, copy) NSString *versionTag;
/* Set once deployed: 0 and nil before. */
@property (nonatomic, readonly) NSInteger version;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSString *deploymentId;
@property (nonatomic, readonly, copy) NSString *resourceName;
/* A decision table, or nil for a literal expression. */
@property (nonatomic, readonly, strong) WFDecisionTable *table;
/* A literal expression's, the variable it gives. */
@property (nonatomic, readonly, strong) WFFeelExpression *literalExpression;
@property (nonatomic, readonly, copy) NSString *literalVariable;
@property (nonatomic, readonly, copy) NSString *literalTypeRef;
/* The decisions it requires, by key. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *requiredDecisionKeys;
- (instancetype)init NS_UNAVAILABLE;
/* The decision over the variables. nil, with a WFErrorDecision error, when
 * it cannot be evaluated. inputs, when given, receives the values of the
 * table's inputs by input id. */
- (WFDecisionResult *)evaluateWithVariables:(NSDictionary *)variables
                                     inputs:(NSMutableDictionary *)inputs
                                      error:(NSError **)error;
@end

/*
 * Reads DMN 1.1, 1.2 and 1.3, as Camunda Modeler writes it: decisions
 * with a decision table or a literal expression, and the decisions they
 * require. Expressions are FEEL -- input expressions, output entries and
 * literal expressions; input entries are unary tests -- and Camunda 7's
 * `${...}` is read as for BPMN. Anything else is refused, with an error
 * saying what.
 */
@interface WFDmnReader : NSObject
+ (NSArray<WFDecisionDefinition *> *)decisionsFromData:(NSData *)data error:(NSError **)error;
+ (NSArray<WFDecisionDefinition *> *)decisionsFromXMLString:(NSString *)xml error:(NSError **)error;
@end

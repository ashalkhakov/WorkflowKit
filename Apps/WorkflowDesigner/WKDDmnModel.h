#import <Foundation/Foundation.h>

/*
 * A DMN file's decisions, as objects: each decision with its table -- its
 * columns, and its rules with an entry per column -- or its literal
 * expression, and the decisions it requires. The objects are the model, as
 * WKDModel is a process's: read once from the document, which is kept as
 * the carrier, and written into it where they changed (WKDDmnWriter).
 * What the model does not hold -- input data, knowledge sources, extension
 * elements -- stays in the carrier as it was read. Outside the decision
 * editor the model is read-only.
 */

@class WKDDmnModel, WKDDmnDecision;

@interface WKDDmnElement : NSObject
@property (nonatomic, readonly, weak) WKDDmnModel *model;
/* The carrier's element it was read from or written to. */
@property (nonatomic, readonly, strong) NSXMLElement *element;
@end

/* A decision table's column. An input is the expression whose value the
 * rules test, with its label and type; an output is the name a rule's
 * value has in the result, with its label and type. */
@interface WKDDmnColumn : WKDDmnElement
@property (nonatomic, readonly, weak) WKDDmnDecision *decision;
@property (nonatomic, readonly, copy) NSString *columnId;
@property (nonatomic, readonly, getter=isOutput) BOOL output;
@property (nonatomic, readonly, copy) NSString *label;
/* typeRef: string, boolean, integer, long, double, date; nil for any. */
@property (nonatomic, readonly, copy) NSString *typeRef;
/* An input's: its inputExpression's text, and camunda:inputVariable, the
 * name its entries see the value under besides ?. */
@property (nonatomic, readonly, copy) NSString *expression;
@property (nonatomic, readonly, copy) NSString *inputVariable;
/* An output's. */
@property (nonatomic, readonly, copy) NSString *name;
/* What the column is called: its label, else its expression or name. */
@property (nonatomic, readonly, copy) NSString *title;
@end

/* A rule: an entry per column, inputs first -- "" where the file has none
 * -- and its annotation, the rule's description. */
@interface WKDDmnRule : WKDDmnElement
@property (nonatomic, readonly, weak) WKDDmnDecision *decision;
@property (nonatomic, readonly, copy) NSString *ruleId;
@property (nonatomic, readonly, copy) NSArray<NSString *> *entries;
@property (nonatomic, readonly, copy) NSString *annotation;
@end

@interface WKDDmnDecision : WKDDmnElement
@property (nonatomic, readonly, copy) NSString *decisionId;
@property (nonatomic, readonly, copy) NSString *name;
/* A decision table; NO for a literal expression, or for neither. */
@property (nonatomic, readonly, getter=isTable) BOOL table;
/* A table's: its hitPolicy as written, UNIQUE when not, and its
 * aggregation (SUM, MIN, MAX, COUNT) or nil. */
@property (nonatomic, readonly, copy) NSString *hitPolicy;
@property (nonatomic, readonly, copy) NSString *aggregation;
@property (nonatomic, readonly, copy) NSArray<WKDDmnColumn *> *inputs;
@property (nonatomic, readonly, copy) NSArray<WKDDmnColumn *> *outputs;
/* The inputs, then the outputs: what a rule's entries are for. */
@property (nonatomic, readonly, copy) NSArray<WKDDmnColumn *> *columns;
@property (nonatomic, readonly, copy) NSArray<WKDDmnRule *> *rules;
/* A literal expression's: its text, and the variable it gives. */
@property (nonatomic, readonly, copy) NSString *expression;
@property (nonatomic, readonly, copy) NSString *variableName;
@property (nonatomic, readonly, copy) NSString *variableType;
/* The decisions it requires, by id, and those that require it. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *required;
@property (nonatomic, readonly, copy) NSArray<WKDDmnDecision *> *requiredBy;
/* Its name, else its id. */
@property (nonatomic, readonly, copy) NSString *title;
@end

@interface WKDDmnModel : NSObject

/* The document's decisions read into a model, the document kept as the
 * carrier. */
+ (instancetype)modelOfDocument:(NSXMLDocument *)document;

@property (nonatomic, readonly, strong) NSXMLDocument *document;
@property (nonatomic, readonly, copy) NSArray<WKDDmnDecision *> *decisions;
- (WKDDmnDecision *)decisionWithId:(NSString *)decisionId;

/* What changed since the last write, written into the carrier where it
 * differs from what is there. An unchanged model writes nothing. */
- (void)write;
@property (nonatomic, readonly) BOOL hasChanges;

@end

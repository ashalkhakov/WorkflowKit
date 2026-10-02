#import <Foundation/Foundation.h>

/*
 * A DMN file's decisions, as the decision editor shows them: read from the
 * XML after every change, as WKDDiagram is from a process's.
 */

/* A decision table's column. An input is the expression whose value the
 * rules test, with its label and type; an output is the name a rule's
 * value has in the result, with its label and type. */
@interface WKDDmnColumn : NSObject
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
@interface WKDDmnRule : NSObject
@property (nonatomic, readonly, copy) NSString *ruleId;
@property (nonatomic, readonly, copy) NSArray<NSString *> *entries;
@property (nonatomic, readonly, copy) NSString *annotation;
@end

@interface WKDDmnDecision : NSObject
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
/* The decisions it requires, by id. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *required;
/* Its name, else its id. */
@property (nonatomic, readonly, copy) NSString *title;
@end

/* The types a column or a variable can have, as the engine knows them. */
NSArray<NSString *> *WKDDmnTypes(void);
/* The hit policies and aggregations the engine evaluates, as one list:
 * each an array of policy and aggregation (or ""), with what to call it. */
NSArray<NSArray<NSString *> *> *WKDDmnHitPolicies(void);

/*
 * Every change to a DMN document goes through here, as WKDEditor's do to
 * a process: each one undo step that restores the document as it was. A
 * table's rules keep an entry per column as columns come, go and move;
 * a decision's references -- requirements on it, its diagram shape -- go
 * with it, and change with its id. Where the file has a DMN diagram
 * (DMNDI), a decision added gets a shape and a requirement an edge.
 */
@interface WKDDmnEditor : NSObject

/* A new DMN 1.3 file with one decision table: an input and an output. */
+ (NSXMLDocument *)newDecisionsDocument;

- (instancetype)initWithDocument:(NSXMLDocument *)document undoManager:(NSUndoManager *)undoManager;

@property (nonatomic, readonly, strong) NSXMLDocument *document;
/* Read again after every change. */
@property (nonatomic, readonly, copy) NSArray<WKDDmnDecision *> *decisions;
/* Called after every change, undo and redo included. */
@property (nonatomic, copy) void (^changed)(void);

- (WKDDmnDecision *)decisionWithId:(NSString *)decisionId;

#pragma mark Decisions

/* A new decision, a table with an input and an output or a literal
 * expression, after the others; its id. With an id, under it -- for a
 * business rule task naming one there is not yet -- else one of its own. */
- (NSString *)addDecisionTable:(BOOL)table withId:(NSString *)decisionId;
/* The decision, and the requirements on it. */
- (void)deleteDecision:(NSString *)decisionId;
/* A new id, and what refers to it with it. NO, with why, for an id that is
 * taken or not an XML name. */
- (BOOL)renameDecision:(NSString *)decisionId to:(NSString *)newId error:(NSString **)reason;
- (void)setName:(NSString *)name of:(NSString *)decisionId;
/* UNIQUE, FIRST, ANY, RULE ORDER, COLLECT, and for COLLECT an aggregation
 * or nil. */
- (void)setHitPolicy:(NSString *)hitPolicy aggregation:(NSString *)aggregation of:(NSString *)decisionId;
/* The decisions it requires, which are evaluated first. NO, with why, for
 * one the file does not define, or one that requires it in turn. */
- (BOOL)setRequired:(NSArray<NSString *> *)required of:(NSString *)decisionId error:(NSString **)reason;

#pragma mark Tables

/* A new column -- an input, or an output -- at the index among its kind;
 * each rule gets an empty entry for it. Its index among the columns. */
- (NSUInteger)insertColumn:(BOOL)output at:(NSUInteger)index of:(NSString *)decisionId;
/* The column (an index among the columns) and the rules' entries for it. */
- (void)deleteColumn:(NSUInteger)column of:(NSString *)decisionId;
/* The column to the index among the columns, among its own kind. */
- (void)moveColumn:(NSUInteger)column to:(NSUInteger)index of:(NSString *)decisionId;
/* A column's label, expression, typeRef, inputVariable or name; nil or
 * empty for none. */
- (void)setColumn:(NSUInteger)column property:(NSString *)property to:(NSString *)value of:(NSString *)decisionId;

/* A rule of empty entries -- any input, no output -- at the index. */
- (void)insertRuleAt:(NSUInteger)index of:(NSString *)decisionId;
/* A copy of the rule, under ids of its own, after it. */
- (void)duplicateRule:(NSUInteger)rule of:(NSString *)decisionId;
- (void)deleteRules:(NSIndexSet *)rules of:(NSString *)decisionId;
- (void)moveRule:(NSUInteger)rule to:(NSUInteger)index of:(NSString *)decisionId;
/* A rule's entry for the column: unary tests for an input, an expression
 * for an output; empty for any input, or no output. */
- (void)setEntry:(NSString *)text rule:(NSUInteger)rule column:(NSUInteger)column of:(NSString *)decisionId;
- (void)setAnnotation:(NSString *)text rule:(NSUInteger)rule of:(NSString *)decisionId;

#pragma mark Literal expressions

/* A literal expression's expression, variableName or variableType. */
- (void)setLiteral:(NSString *)property to:(NSString *)value of:(NSString *)decisionId;

@end

#import "WKDDmnModel.h"
#import "WKDJournal.h"

/* The decision editor's side of the model: what it changes, and what the
 * reader and the writer keep. */

extern NSString * const WKDDmn13Namespace;
extern NSString * const WKDDmnDI13Namespace;
extern NSString * const WKDDmnDCNamespace;
extern NSString * const WKDDmnDINamespace;

@class WKDDmnRule, WKDDmnColumn;

@interface WKDDmnElement () <WKDJournalElement>
@property (nonatomic, readwrite, weak) WKDDmnModel *model;
@property (nonatomic, readwrite, strong) NSXMLElement *element;
/* What journal states hold: values, links and carriers, not positions. */
+ (NSArray<NSString *> *)journalKeys;
/* Before its values or links change: recorded, and written at the next
 * write. */
- (void)willChange;
@end

/* A rule's entry for one column: unary tests for an input, an expression
 * for an output. Without a carrier until it is written. */
@interface WKDDmnEntry : WKDDmnElement
@property (nonatomic, weak) WKDDmnRule *rule;
@property (nonatomic, copy) NSString *entryId;
@property (nonatomic) BOOL output;
@property (nonatomic, copy) NSString *text;
@end

/* A decision's information requirement on another decision, by id: the
 * one it names, nil when the file defines none of that id. */
@interface WKDDmnRequirement : WKDDmnElement
@property (nonatomic, weak) WKDDmnDecision *decision;
@property (nonatomic, copy) NSString *requirementId;
@property (nonatomic, copy) NSString *requiredId;
@property (nonatomic, weak) WKDDmnDecision *requiredDecision;
/* Its DMNEdge, when the diagram draws it. */
@property (nonatomic, strong) NSXMLElement *edgeElement;
@end

@interface WKDDmnColumn ()
@property (nonatomic, readwrite, weak) WKDDmnDecision *decision;
@property (nonatomic, readwrite, copy) NSString *columnId;
@property (nonatomic, readwrite, getter=isOutput) BOOL output;
@property (nonatomic, readwrite, copy) NSString *label;
@property (nonatomic, readwrite, copy) NSString *typeRef;
@property (nonatomic, readwrite, copy) NSString *expression;
@property (nonatomic, readwrite, copy) NSString *inputVariable;
@property (nonatomic, readwrite, copy) NSString *name;
/* An input's inputExpression, and its id. */
@property (nonatomic, strong) NSXMLElement *expressionElement;
@property (nonatomic, copy) NSString *expressionId;
@end

@interface WKDDmnRule ()
@property (nonatomic, readwrite, weak) WKDDmnDecision *decision;
@property (nonatomic, readwrite, copy) NSString *ruleId;
@property (nonatomic, readwrite, copy) NSString *annotation;
/* An entry per column, as the decision's columns go. */
@property (nonatomic, strong) NSMutableArray<WKDDmnEntry *> *entryList;
@end

@interface WKDDmnDecision ()
@property (nonatomic, readwrite, copy) NSString *decisionId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, getter=isTable) BOOL table;
@property (nonatomic, readwrite, copy) NSString *hitPolicy;
@property (nonatomic, readwrite, copy) NSString *aggregation;
@property (nonatomic, readwrite, copy) NSString *expression;
@property (nonatomic, readwrite, copy) NSString *variableName;
@property (nonatomic, readwrite, copy) NSString *variableType;
@property (nonatomic, strong) NSMutableArray<WKDDmnColumn *> *inputList;
@property (nonatomic, strong) NSMutableArray<WKDDmnColumn *> *outputList;
@property (nonatomic, strong) NSMutableArray<WKDDmnRule *> *ruleList;
@property (nonatomic, strong) NSMutableArray<WKDDmnRequirement *> *requirementList;
/* The requirements naming it. */
@property (nonatomic, strong) NSMutableArray<WKDDmnRequirement *> *dependentList;
/* Its decisionTable, or its literalExpression and variable, and the ids
 * each is made with. */
@property (nonatomic, strong) NSXMLElement *tableElement;
@property (nonatomic, copy) NSString *tableId;
@property (nonatomic, strong) NSXMLElement *literalElement;
@property (nonatomic, copy) NSString *literalId;
@property (nonatomic, strong) NSXMLElement *variableElement;
@property (nonatomic, copy) NSString *variableId;
/* Its DMNShape, when the diagram draws it. */
@property (nonatomic, strong) NSXMLElement *shapeElement;
@end

@interface WKDDmnModel () <WKDJournalModel>
@property (nonatomic, readwrite, strong) NSXMLDocument *document;
/* The namespace its decisions are in: DMN 1.1's, 1.2's or 1.3's. */
@property (nonatomic, copy) NSString *dmn;
/* The DMNDiagram that draws them; nil when the file has none. */
@property (nonatomic, strong) NSXMLElement *diagram;
@property (nonatomic, strong) NSMutableArray<WKDDmnDecision *> *decisionList;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WKDDmnDecision *> *decisionsById;
@property (nonatomic, strong) NSMutableSet<WKDDmnElement *> *changedElements;
@property (nonatomic, strong) NSMutableArray<WKDDmnElement *> *deletedElements;
@property (nonatomic, strong) WKDJournal *journal;

/* A new id, Prefix_n, with the least n neither the document nor an element
 * not yet written has. */
- (NSString *)freshId:(NSString *)prefix;
/* An element of the carrier the model holds as its own. */
- (void)carry:(NSXMLNode *)node;

/* What the editor makes and removes; each made one is written at the
 * next write. */
- (WKDDmnDecision *)makeDecisionWithId:(NSString *)decisionId table:(BOOL)table;
- (void)removeDecision:(WKDDmnDecision *)decision;
- (WKDDmnColumn *)makeColumn:(BOOL)output at:(NSUInteger)index of:(WKDDmnDecision *)decision;
- (void)removeColumn:(WKDDmnColumn *)column;
- (WKDDmnRule *)makeRuleAt:(NSUInteger)index of:(WKDDmnDecision *)decision;
- (void)removeRule:(WKDDmnRule *)rule;
- (WKDDmnRequirement *)makeRequirementOf:(WKDDmnDecision *)decision on:(WKDDmnDecision *)required;
- (void)removeRequirement:(WKDDmnRequirement *)requirement;
- (void)renameDecision:(WKDDmnDecision *)decision to:(NSString *)decisionId;
- (BOOL)containsElement:(WKDDmnElement *)element;
@end

@interface WKDDmnModel (WKDDmnReading)
- (void)readDocument:(NSXMLDocument *)document;
@end

@interface WKDDmnModel (WKDDmnWriting)
- (void)writeChanges;
@end

@interface WKDDmnModel (WKDDmnChecking)
/* How the model differs from another, read afresh: nil when it does not. */
- (NSString *)disagreementWith:(WKDDmnModel *)other;
@end

/* The text of an element's <text>, trimmed; "" when it has none. */
NSString *WKDDmnText(NSXMLElement *element);

#import <Foundation/Foundation.h>

@class WKDModel, WKDModelElement;

/*
 * What one editor operation changed, to undo and redo it: each element it
 * touched -- its values and links -- as it was before and after, recorded
 * the first time it is touched in the step, the model's own lists, and every
 * change the writer made to the XML. An operation touches a few elements,
 * so neither the step nor its undo costs the size of the model, and undoing
 * it gives back the XML exactly as it was: the writer's edits are reversed,
 * not written again.
 */
@interface WKDJournalStep : NSObject
@end

@interface WKDJournal : NSObject

- (instancetype)initWithModel:(WKDModel *)model;

/* A step begins; until it ends, what is touched and written is recorded. */
- (void)begin;
/* The step, with the model's state after it; nil when nothing changed. */
- (WKDJournalStep *)end;
@property (nonatomic, readonly) BOOL isRecording;

/* Before an element's values or links change. */
- (void)willChange:(WKDModelElement *)element;
/* Before the model's own lists change: its nodes, flows, lanes. */
- (void)willChangeModel;

/* The writer's edits of the XML, recorded while a step is. */
- (void)didSetAttribute:(NSString *)name of:(NSXMLElement *)element from:(NSString *)before to:(NSString *)after;
- (void)didInsert:(NSXMLNode *)child into:(NSXMLElement *)parent at:(NSUInteger)index;
- (void)didDetach:(NSXMLNode *)child from:(NSXMLElement *)parent at:(NSUInteger)index;
- (void)didSetText:(NSXMLNode *)node from:(NSString *)before to:(NSString *)after;

/* An edit of an element's own XML done by code that changes it through any
 * helper: its attributes, namespaces and children before and after, the
 * children that carry model elements kept as the same objects. Around an
 * inspector's edit of an element, or of the document's root. */
- (void)willEditXML:(NSXMLElement *)element;
- (void)didEditXML:(NSXMLElement *)element;

/* The step undone -- the model and the XML as they were before it -- and
 * the step that redoes it. */
- (WKDJournalStep *)undo:(WKDJournalStep *)step;

/* The later step's changes made part of the earlier: for a burst of nudges
 * undone at once. */
- (void)merge:(WKDJournalStep *)later into:(WKDJournalStep *)earlier;

@end

/* Edits of the XML, recorded in the journal (nil: not recorded) so that
 * undo takes them back exactly. Every edit made inside a step goes through
 * these or the model's writer. */
void WKDLogAttribute(WKDJournal *journal, NSXMLElement *element, NSString *name, NSString *value);
void WKDLogInsert(WKDJournal *journal, NSXMLElement *parent, NSXMLNode *child, NSUInteger index);
void WKDLogAdd(WKDJournal *journal, NSXMLElement *parent, NSXMLNode *child);
void WKDLogDetach(WKDJournal *journal, NSXMLNode *child);
void WKDLogText(WKDJournal *journal, NSXMLNode *node, NSString *text);

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

/* The step undone -- the model and the XML as they were before it -- and
 * the step that redoes it. */
- (WKDJournalStep *)undo:(WKDJournalStep *)step;

@end

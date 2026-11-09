#import "WKDJournal.h"
#import "WKDModelPriv.h"
#import "WKDXML.h"

typedef NS_ENUM(NSInteger, WKDEditKind) {
	WKDEditAttribute,
	WKDEditInsert,
	WKDEditDetach,
	WKDEditText,
};

/* One of the writer's edits of the XML, and how to make it again or take it
 * back. */
@interface WKDXMLEdit : NSObject
@property (nonatomic) WKDEditKind kind;
@property (nonatomic, strong) NSXMLNode *node;
@property (nonatomic, strong) NSXMLElement *parent;
@property (nonatomic) NSUInteger index;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *before;
@property (nonatomic, copy) NSString *after;
@end

@implementation WKDXMLEdit

- (WKDXMLEdit *)inverse
{
	WKDXMLEdit *inverse = [[WKDXMLEdit alloc] init];
	inverse.kind = _kind == WKDEditInsert ? WKDEditDetach : _kind == WKDEditDetach ? WKDEditInsert : _kind;
	inverse.node = _node;
	inverse.parent = _parent;
	inverse.index = _index;
	inverse.name = _name;
	inverse.before = _after;
	inverse.after = _before;
	return inverse;
}

- (void)apply
{
	switch (_kind) {
	case WKDEditAttribute:
		WKDSetAttribute((NSXMLElement *)_node, _name, _after);
		break;
	case WKDEditInsert:
		[_parent insertChild:_node atIndex:MIN(_index, [[_parent children] count])];
		break;
	case WKDEditDetach:
		[_node detach];
		break;
	case WKDEditText:
		[_node setStringValue:_after ?: @""];
		break;
	}
}

@end

@interface WKDJournalStep ()
@property (nonatomic, strong) NSMapTable<WKDModelElement *, NSDictionary *> *before;
@property (nonatomic, strong) NSMapTable<WKDModelElement *, NSDictionary *> *after;
@property (nonatomic, strong) NSMutableArray<WKDModelElement *> *order;
@property (nonatomic, strong) NSDictionary *modelBefore;
@property (nonatomic, strong) NSDictionary *modelAfter;
@property (nonatomic, strong) NSMutableArray<WKDXMLEdit *> *edits;
@end

@implementation WKDJournalStep

- (instancetype)init
{
	if ((self = [super init])) {
		NSPointerFunctionsOptions keys = NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsStrongMemory;
		_before = [NSMapTable mapTableWithKeyOptions:keys valueOptions:NSPointerFunctionsStrongMemory];
		_after = [NSMapTable mapTableWithKeyOptions:keys valueOptions:NSPointerFunctionsStrongMemory];
		_order = [NSMutableArray array];
		_edits = [NSMutableArray array];
	}
	return self;
}

/* The step that takes this one back: the edits reversed and inverted, the
 * states the other way round. */
- (WKDJournalStep *)inverse
{
	WKDJournalStep *inverse = [[WKDJournalStep alloc] init];
	inverse.before = _after;
	inverse.after = _before;
	inverse.order = _order;
	inverse.modelBefore = _modelAfter;
	inverse.modelAfter = _modelBefore;
	for (WKDXMLEdit *edit in [_edits reverseObjectEnumerator]) {
		[inverse.edits addObject:[edit inverse]];
	}
	return inverse;
}

@end

@implementation WKDJournal
{
	__weak WKDModel *_model;
	WKDJournalStep *_step;
}

- (instancetype)initWithModel:(WKDModel *)model
{
	if ((self = [super init])) {
		_model = model;
	}
	return self;
}

- (BOOL)isRecording
{
	return _step != nil;
}

- (void)begin
{
	_step = [[WKDJournalStep alloc] init];
}

- (WKDJournalStep *)end
{
	WKDJournalStep *step = _step;
	_step = nil;
	if ([step.order count] == 0 && step.modelBefore == nil && [step.edits count] == 0) {
		return nil;
	}
	for (WKDModelElement *element in step.order) {
		[step.after setObject:[element journalState] forKey:element];
	}
	if (step.modelBefore != nil) {
		step.modelAfter = [_model journalState];
	}
	return step;
}

- (void)willChange:(WKDModelElement *)element
{
	if (_step == nil || element == nil || [_step.before objectForKey:element] != nil) {
		return;
	}
	[_step.before setObject:[element journalState] forKey:element];
	[_step.order addObject:element];
}

- (void)willChangeModel
{
	if (_step != nil && _step.modelBefore == nil) {
		_step.modelBefore = [_model journalState];
	}
}

- (void)record:(WKDXMLEdit *)edit
{
	if (_step != nil) {
		[_step.edits addObject:edit];
	}
}

- (void)didSetAttribute:(NSString *)name of:(NSXMLElement *)element from:(NSString *)before to:(NSString *)after
{
	WKDXMLEdit *edit = [[WKDXMLEdit alloc] init];
	edit.kind = WKDEditAttribute;
	edit.node = element;
	edit.name = name;
	edit.before = before;
	edit.after = after;
	[self record:edit];
}

- (void)didInsert:(NSXMLNode *)child into:(NSXMLElement *)parent at:(NSUInteger)index
{
	WKDXMLEdit *edit = [[WKDXMLEdit alloc] init];
	edit.kind = WKDEditInsert;
	edit.node = child;
	edit.parent = parent;
	edit.index = index;
	[self record:edit];
}

- (void)didDetach:(NSXMLNode *)child from:(NSXMLElement *)parent at:(NSUInteger)index
{
	WKDXMLEdit *edit = [[WKDXMLEdit alloc] init];
	edit.kind = WKDEditDetach;
	edit.node = child;
	edit.parent = parent;
	edit.index = index;
	[self record:edit];
}

- (void)didSetText:(NSXMLNode *)node from:(NSString *)before to:(NSString *)after
{
	WKDXMLEdit *edit = [[WKDXMLEdit alloc] init];
	edit.kind = WKDEditText;
	edit.node = node;
	edit.before = before;
	edit.after = after;
	[self record:edit];
}

- (WKDJournalStep *)undo:(WKDJournalStep *)step
{
	WKDJournalStep *inverse = [step inverse];
	for (WKDXMLEdit *edit in inverse.edits) {
		[edit apply];
	}
	if (inverse.modelAfter != nil) {
		[_model restoreJournalState:inverse.modelAfter];
	}
	for (WKDModelElement *element in inverse.order) {
		[element restoreJournalState:[inverse.after objectForKey:element]];
	}
	/* The XML is as the states say: nothing is left to write. */
	[_model.changedElements removeAllObjects];
	[_model.deletedElements removeAllObjects];
	return inverse;
}

@end

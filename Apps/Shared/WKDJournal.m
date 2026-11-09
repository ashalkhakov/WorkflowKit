#import "WKDJournal.h"
#import "WKDModelPriv.h"
#import "WKDXML.h"

typedef NS_ENUM(NSInteger, WKDEditKind) {
	WKDEditAttribute,
	WKDEditInsert,
	WKDEditDetach,
	WKDEditText,
	/* An element's attributes, namespaces and children swapped. */
	WKDEditWhole,
};

/* An element's own XML: its attributes, its namespaces and its children --
 * those carrying model elements as themselves, the rest as copies, so that
 * putting them back neither loses what the model points to nor shares a
 * child with the state put back later. */
@interface WKDXMLState : NSObject
@property (nonatomic, copy) NSArray *attributes;
@property (nonatomic, copy) NSArray *namespaces;
@property (nonatomic, copy) NSArray *children;
@end

@implementation WKDXMLState
@end

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
@property (nonatomic, strong) WKDXMLState *wholeBefore;
@property (nonatomic, strong) WKDXMLState *wholeAfter;
@end

static BOOL
WKDSameNodes(NSArray *a, NSArray *b)
{
	if ([a count] != [b count]) {
		return NO;
	}
	for (NSUInteger i = 0; i < [a count]; i++) {
		if ([a objectAtIndex:i] != [b objectAtIndex:i]) {
			return NO;
		}
	}
	return YES;
}

/* Only the declarations that differ: the element and what it holds use the
 * ones it has, which are not to be freed under them. */
static void
WKDRestoreNamespaces(NSXMLElement *element, NSArray<NSXMLNode *> *namespaces)
{
	NSMutableDictionary *wanted = [NSMutableDictionary dictionary];
	for (NSXMLNode *ns in namespaces) {
		[wanted setObject:[ns stringValue] ?: @"" forKey:[ns name] ?: @""];
	}
	for (NSXMLNode *ns in [element namespaces]) {
		NSString *prefix = [ns name] ?: @"", *uri = [wanted objectForKey:prefix];
		if (uri == nil || ![uri isEqualToString:[ns stringValue] ?: @""]) {
			[element removeNamespaceForPrefix:prefix];
		} else {
			[wanted removeObjectForKey:prefix];
		}
	}
	for (NSXMLNode *ns in namespaces) {
		if ([wanted objectForKey:[ns name] ?: @""] != nil) {
			[element addNamespace:[ns copy]];
		}
	}
}

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
	inverse.wholeBefore = _wholeAfter;
	inverse.wholeAfter = _wholeBefore;
	return inverse;
}

- (void)apply
{
	switch (_kind) {
	case WKDEditAttribute:
		WKDSetAttribute((NSXMLElement *)_node, _name, _after);
		break;
	case WKDEditInsert:
		/* Put back already by its parent's whole edit, redone first. */
		if ([_node parent] != nil) {
			[_node detach];
		}
		[_parent insertChild:_node atIndex:MIN(_index, [[_parent children] count])];
		break;
	case WKDEditDetach:
		[_node detach];
		break;
	case WKDEditText:
		[_node setStringValue:_after ?: @""];
		break;
	case WKDEditWhole: {
		NSXMLElement *element = (NSXMLElement *)_node;
		WKDXMLState *state = _wholeAfter;
		if (!WKDSameNodes([element children] ?: @[], state.children ?: @[])) {
			for (NSXMLNode *child in [[element children] copy]) {
				[child detach];
			}
			/* Undo and redo come in stack order, so each state's children
			 * are free to go back in as themselves. */
			for (NSXMLNode *child in state.children) {
				[child detach];
				[element addChild:child];
			}
		}
		[element setAttributes:[[NSArray alloc] initWithArray:state.attributes copyItems:YES]];
		WKDRestoreNamespaces(element, state.namespaces);
		break;
	}
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
	NSMapTable<NSXMLElement *, WKDXMLEdit *> *_pending;
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
	/* A scope left open ends with the step. */
	for (NSXMLElement *element in [[_pending keyEnumerator] allObjects]) {
		[self didEditXML:element];
	}
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

/* The element's XML now, the children that carry model elements as
 * themselves and the rest copied. */
- (WKDXMLState *)stateOfXML:(NSXMLElement *)element
{
	NSSet *carriers = [_model carrierElements];
	WKDXMLState *state = [[WKDXMLState alloc] init];
	state.attributes = [[NSArray alloc] initWithArray:[element attributes] ?: @[] copyItems:YES];
	state.namespaces = [[NSArray alloc] initWithArray:[element namespaces] ?: @[] copyItems:YES];
	NSMutableArray *children = [NSMutableArray array];
	for (NSXMLNode *child in [element children]) {
		[children addObject:[self holdsCarrier:child among:carriers] ? child : [child copy]];
	}
	state.children = children;
	return state;
}

- (BOOL)holdsCarrier:(NSXMLNode *)node among:(NSSet *)carriers
{
	if ([carriers containsObject:node]) {
		return YES;
	}
	for (NSXMLNode *child in [node children]) {
		if ([child kind] == NSXMLElementKind && [self holdsCarrier:child among:carriers]) {
			return YES;
		}
	}
	return NO;
}

- (void)willEditXML:(NSXMLElement *)element
{
	if (_step == nil || element == nil) {
		return;
	}
	if (_pending == nil) {
		_pending = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsStrongMemory
		                                 valueOptions:NSPointerFunctionsStrongMemory];
	}
	if ([_pending objectForKey:element] == nil) {
		/* In the step where the edit began: what is logged inside it is
		 * undone before the element is put back, and redone after. */
		WKDXMLEdit *edit = [[WKDXMLEdit alloc] init];
		edit.kind = WKDEditWhole;
		edit.node = element;
		edit.wholeBefore = [self stateOfXML:element];
		[_step.edits addObject:edit];
		[_pending setObject:edit forKey:element];
	}
}

- (void)didEditXML:(NSXMLElement *)element
{
	WKDXMLEdit *edit = element != nil ? [_pending objectForKey:element] : nil;
	if (_step == nil || edit == nil) {
		return;
	}
	edit.wholeAfter = [self stateOfXML:element];
	[_pending removeObjectForKey:element];
}

- (void)merge:(WKDJournalStep *)later into:(WKDJournalStep *)earlier
{
	for (WKDModelElement *element in later.order) {
		if ([earlier.before objectForKey:element] == nil) {
			[earlier.before setObject:[later.before objectForKey:element] forKey:element];
			[earlier.order addObject:element];
		}
		[earlier.after setObject:[later.after objectForKey:element] forKey:element];
	}
	if (later.modelBefore != nil) {
		if (earlier.modelBefore == nil) {
			earlier.modelBefore = later.modelBefore;
		}
		earlier.modelAfter = later.modelAfter;
	}
	[earlier.edits addObjectsFromArray:later.edits];
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

void
WKDLogAttribute(WKDJournal *journal, NSXMLElement *element, NSString *name, NSString *value)
{
	NSString *before = WKDAttribute(element, name);
	if (value == before || [value isEqualToString:before]) {
		return;
	}
	WKDSetAttribute(element, name, value);
	[journal didSetAttribute:name of:element from:before to:value];
}

void
WKDLogInsert(WKDJournal *journal, NSXMLElement *parent, NSXMLNode *child, NSUInteger index)
{
	[parent insertChild:child atIndex:index];
	[journal didInsert:child into:parent at:index];
}

void
WKDLogAdd(WKDJournal *journal, NSXMLElement *parent, NSXMLNode *child)
{
	WKDLogInsert(journal, parent, child, [[parent children] count]);
}

void
WKDLogDetach(WKDJournal *journal, NSXMLNode *child)
{
	NSXMLElement *parent = (NSXMLElement *)[child parent];
	if (parent == nil) {
		return;
	}
	NSUInteger index = [child index];
	[child detach];
	[journal didDetach:child from:parent at:index];
}

void
WKDLogText(WKDJournal *journal, NSXMLNode *node, NSString *text)
{
	NSString *before = [node stringValue];
	if ([before isEqualToString:text ?: @""]) {
		return;
	}
	[node setStringValue:text ?: @""];
	[journal didSetText:node from:before to:text];
}

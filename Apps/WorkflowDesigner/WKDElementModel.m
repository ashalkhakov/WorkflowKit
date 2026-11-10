#import "WKDElementModel.h"
#import "WKDTableModel.h"
#import "WKDEditor.h"

/* "Due date" as a key: dueDate; "Id" is id. */
static NSString *
WKDKeyOfLabel(NSString *label)
{
	NSMutableString *key = [NSMutableString string];
	BOOL upper = NO;
	for (NSUInteger i = 0; i < [label length]; i++) {
		unichar c = [label characterAtIndex:i];
		if (![[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
			upper = [key length] > 0;
			continue;
		}
		NSString *letter = [NSString stringWithCharacters:&c length:1];
		[key appendString:[key length] == 0 ? [letter lowercaseString] : upper ? [letter uppercaseString] : letter];
		upper = NO;
	}
	return [key length] > 0 ? key : @"value";
}

@implementation WKDElementModel
{
	NSMutableArray<NSString *> *_keys;
	NSMutableDictionary<NSString *, WKDProperty *> *_properties;
	NSMutableDictionary<NSString *, WKDTableModel *> *_tables;
}

- (instancetype)initWithEditor:(WKDEditor *)editor elementId:(NSString *)elementId section:(WKDSection *)section
{
	if ((self = [super init])) {
		_editor = editor;
		_elementId = [elementId copy];
		_section = section;
		_keys = [NSMutableArray array];
		_properties = [NSMutableDictionary dictionary];
		_tables = [NSMutableDictionary dictionary];
		for (WKDProperty *property in section.properties) {
			NSString *key = WKDKeyOfLabel(property.label);
			for (NSUInteger n = 2; [_properties objectForKey:key] != nil; n++) {
				key = [NSString stringWithFormat:@"%@%lu", WKDKeyOfLabel(property.label), (unsigned long)n];
			}
			[_keys addObject:key];
			[_properties setObject:property forKey:key];
			if (property.kind == WKDPropertyTable) {
				[_tables setObject:[[WKDTableModel alloc] initWithEditor:editor elementId:elementId property:property
				                                                  master:NSNotFound]
				            forKey:key];
			}
		}
	}
	return self;
}

/* The properties' keys are told of by hand: once, when they change. */
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
	return [key isEqualToString:@"editingKey"] || [key isEqualToString:@"refused"]
		? [super automaticallyNotifiesObserversForKey:key] : NO;
}

- (NSString *)keyOf:(WKDProperty *)property
{
	for (NSString *key in _keys) {
		if ([_properties objectForKey:key] == property) {
			return key;
		}
	}
	return nil;
}

- (WKDProperty *)propertyForKey:(NSString *)key
{
	return [_properties objectForKey:key];
}

- (WKDTableModel *)tableModelForKey:(NSString *)key
{
	return [_tables objectForKey:key];
}

#pragma mark Values

/* A property's value as a view shows it. */
- (id)valueForUndefinedKey:(NSString *)key
{
	WKDProperty *property = [_properties objectForKey:key];
	if (property == nil) {
		return [super valueForUndefinedKey:key];
	}
	if (property.kind == WKDPropertyTable) {
		return [_tables objectForKey:key];
	}
	if (property.kind == WKDPropertyButton) {
		return nil;
	}
	NSString *value = [property valueIn:_editor of:_elementId] ?: @"";
	if (property.kind == WKDPropertyCheck) {
		return @([value isEqualToString:@"true"]);
	}
	if (property.kind == WKDPropertyChoice) {
		NSUInteger index = [property.values indexOfObject:value];
		return @(index == NSNotFound ? 0 : (NSInteger)index);
	}
	return value;
}

/* What a view gives as the descriptor's text. */
- (NSString *)textOf:(id)value property:(WKDProperty *)property
{
	if (property.kind == WKDPropertyCheck) {
		return [value boolValue] ? @"true" : @"false";
	}
	if (property.kind == WKDPropertyChoice) {
		NSInteger index = MAX(0, MIN([value integerValue], (NSInteger)[property.values count] - 1));
		return [property.values count] > 0 ? [property.values objectAtIndex:(NSUInteger)index] : @"";
	}
	return [value isKindOfClass:[NSString class]] ? value : [value description] ?: @"";
}

- (BOOL)validateValue:(id *)value forKey:(NSString *)key error:(NSError **)error
{
	WKDProperty *property = [_properties objectForKey:key];
	if (property == nil) {
		return [super validateValue:value forKey:key error:error];
	}
	NSString *refusal = property.refusal != nil
		? property.refusal(_editor, _elementId, [self textOf:value != NULL ? *value : nil property:property]) : nil;
	if (refusal != nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"WKDElementModel" code:1
			                         userInfo:@{ NSLocalizedDescriptionKey: refusal }];
		}
		return NO;
	}
	return YES;
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
	WKDProperty *property = [_properties objectForKey:key];
	if (property == nil) {
		[super setValue:value forUndefinedKey:key];
		return;
	}
	if (property.kind == WKDPropertyTable || property.kind == WKDPropertyButton) {
		return;
	}
	NSString *text = [self textOf:value property:property];
	NSError *invalid = nil;
	id checked = value;
	NSString *reason = nil;
	NSString *elementId = _elementId;
	if (![self validateValue:&checked forKey:key error:&invalid]) {
		reason = [invalid localizedDescription];
	} else {
		/* A new id: the element is the same one under it, from the change
		 * on, which tells the views while it is made. */
		BOOL renaming = property.identifies && ![text isEqualToString:elementId];
		if (renaming) {
			_elementId = [text copy];
		}
		if (![property setValue:text in:_editor of:elementId error:&reason]) {
			_elementId = [elementId copy];
		} else {
			reason = nil;
		}
	}
	if (self.refused != nil) {
		self.refused(reason);
	}
	if (reason != nil) {
		/* Refused: the value as it is, again. */
		[self willChangeValueForKey:key];
		[self didChangeValueForKey:key];
	}
}

- (NSString *)problemWithText:(NSString *)text forKey:(NSString *)key
{
	WKDProperty *property = [_properties objectForKey:key];
	if (!property.holdsExpression) {
		return nil;
	}
	return [[WFFeelExpression problemInText:text ?: @"" place:property.place] localizedDescription];
}

- (void)reload
{
	for (NSString *key in _keys) {
		[[_tables objectForKey:key] reloadOf:_elementId];
		if ([key isEqualToString:self.editingKey]) {
			continue;
		}
		[self willChangeValueForKey:key];
		[self didChangeValueForKey:key];
	}
}

@end

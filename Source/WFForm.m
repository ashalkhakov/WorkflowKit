#import "WFForm.h"
#import "WFFeel.h"
#import "WFFeelInternal.h"
#import "WFEntities.h"

static NSError *
WFFormError(NSString *fieldId, NSString *message)
{
	return [NSError errorWithDomain:WFErrorDomain code:WFErrorInvalidFormData
	                       userInfo:@{ NSLocalizedDescriptionKey:
	                                       [NSString stringWithFormat:@"%@: %@", fieldId, message] }];
}

/* ISO-8601 text as a date: a date and time, else a date's midnight in UTC. */
static NSDate *
WFFormParseDate(NSString *text)
{
	NSDate *date = WFFeelParseDateTime(text);
	if (date == nil) {
		date = [WFFeelParseDate(text) startOfDay];
	}
	return date;
}

/* Text that is a whole number, and nothing else. */
static NSNumber *
WFFormParseWhole(NSString *text)
{
	NSScanner *scanner = [NSScanner scannerWithString:
		[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	long long value = 0;
	if (![scanner scanLongLong:&value] || ![scanner isAtEnd]) {
		return nil;
	}
	return [NSNumber numberWithLongLong:value];
}

@implementation WFFormFieldValue

+ (instancetype)valueWithId:(NSString *)valueId name:(NSString *)name
{
	WFFormFieldValue *value = [[self alloc] wf_init];
	value->_valueId = [valueId copy];
	value->_name = [name copy];
	return value;
}

- (instancetype)wf_init
{
	return [super init];
}

@end

@implementation WFFormConstraint

+ (instancetype)constraint:(NSString *)name configuration:(NSString *)configuration
{
	WFFormConstraint *constraint = [[self alloc] wf_init];
	constraint->_name = [name copy];
	constraint->_configuration = [configuration copy];
	return constraint;
}

- (instancetype)wf_init
{
	return [super init];
}

@end

@implementation WFFormField

+ (instancetype)fieldWithId:(NSString *)fieldId
                      label:(NSString *)label
                       type:(WFFormFieldType)type
               defaultValue:(WFFeelExpression *)defaultValue
                     values:(NSArray<WFFormFieldValue *> *)values
                constraints:(NSArray<WFFormConstraint *> *)constraints
                 properties:(NSDictionary<NSString *, NSString *> *)properties
{
	WFFormField *field = [[self alloc] wf_init];
	field->_fieldId = [fieldId copy];
	field->_label = [label copy];
	field->_type = type;
	field->_defaultValue = defaultValue;
	field->_values = [values copy] ?: @[];
	field->_constraints = [constraints copy] ?: @[];
	field->_properties = [properties copy] ?: @{};
	return field;
}

- (instancetype)wf_init
{
	return [super init];
}

+ (NSArray *)typeNames
{
	return @[ @"string", @"long", @"boolean", @"date", @"enum" ];
}

+ (NSString *)nameOfType:(WFFormFieldType)type
{
	return [[self typeNames] objectAtIndex:(NSUInteger)type];
}

+ (NSNumber *)typeNamed:(NSString *)name
{
	NSUInteger index = [[self typeNames] indexOfObject:name ?: @""];
	return index == NSNotFound ? nil : [NSNumber numberWithUnsignedInteger:index];
}

- (WFFormConstraint *)constraintNamed:(NSString *)name
{
	for (WFFormConstraint *constraint in _constraints) {
		if ([constraint.name isEqualToString:name]) {
			return constraint;
		}
	}
	return nil;
}

- (BOOL)isRequired
{
	return [self constraintNamed:@"required"] != nil;
}

- (BOOL)isReadOnly
{
	return [self constraintNamed:@"readonly"] != nil;
}

/* The value as the field's type has it; nil, with the reason, when it is
 * not one. NSNull stays null. */
- (id)convert:(id)value reason:(NSString **)reason
{
	if (value == nil || value == [NSNull null]) {
		return [NSNull null];
	}
	switch (_type) {
	case WFFormFieldTypeString:
		if ([value isKindOfClass:[NSString class]]) {
			return value;
		}
		*reason = @"is not text";
		return nil;
	case WFFormFieldTypeLong: {
		NSNumber *number = nil;
		if ([value isKindOfClass:[NSNumber class]] && !WFIsBooleanNumber(value)
		    && [value doubleValue] == (double)[value longLongValue]) {
			number = [NSNumber numberWithLongLong:[value longLongValue]];
		} else if ([value isKindOfClass:[NSString class]]) {
			number = WFFormParseWhole(value);
		}
		if (number == nil) {
			*reason = @"is not a whole number";
		}
		return number;
	}
	case WFFormFieldTypeBoolean:
		if ([value isKindOfClass:[NSNumber class]] && WFIsBooleanNumber(value)) {
			return [NSNumber numberWithBool:[value boolValue]];
		}
		if ([value isEqual:@"true"] || [value isEqual:@"false"]) {
			return [NSNumber numberWithBool:[value isEqual:@"true"]];
		}
		*reason = @"is not true or false";
		return nil;
	case WFFormFieldTypeDate: {
		NSDate *date = [value isKindOfClass:[NSDate class]] ? value
			: [value isKindOfClass:[NSString class]] ? WFFormParseDate(value) : nil;
		if (date == nil) {
			*reason = @"is not a date";
		}
		return date;
	}
	case WFFormFieldTypeEnum:
		for (WFFormFieldValue *option in _values) {
			if ([option.valueId isEqual:value]) {
				return option.valueId;
			}
		}
		*reason = [NSString stringWithFormat:@"is not one of %@",
			[[_values valueForKey:@"valueId"] componentsJoinedByString:@", "]];
		return nil;
	}
	return value;
}

/* A number or a date, as a constraint's configuration gives it. */
- (id)bound:(NSString *)configuration
{
	if (_type == WFFormFieldTypeDate) {
		return WFFormParseDate(configuration ?: @"");
	}
	return WFFormParseWhole(configuration ?: @"");
}

/* Why the converted value breaks a constraint; nil when it keeps them. */
- (NSString *)violationBy:(id)value
{
	BOOL null = value == [NSNull null]
		|| ([value isKindOfClass:[NSString class]] && [(NSString *)value length] == 0);
	for (WFFormConstraint *constraint in _constraints) {
		NSString *name = constraint.name;
		if ([name isEqualToString:@"required"]) {
			if (null) {
				return @"is required";
			}
		} else if (null || [name isEqualToString:@"readonly"]) {
			continue;
		} else if ([name isEqualToString:@"minlength"] || [name isEqualToString:@"maxlength"]) {
			NSInteger length = (NSInteger)[[value description] length];
			NSInteger limit = [[self bound:constraint.configuration] integerValue];
			if ([name isEqualToString:@"minlength"] ? length < limit : length > limit) {
				return [NSString stringWithFormat:@"is %@ than %ld characters",
					[name isEqualToString:@"minlength"] ? @"shorter" : @"longer", (long)limit];
			}
		} else if ([name isEqualToString:@"min"] || [name isEqualToString:@"max"]) {
			id bound = [self bound:constraint.configuration];
			NSComparisonResult order = [value compare:bound];
			if ([name isEqualToString:@"min"] ? order == NSOrderedAscending : order == NSOrderedDescending) {
				return [NSString stringWithFormat:@"is %@ than %@",
					[name isEqualToString:@"min"] ? @"less" : @"more", constraint.configuration];
			}
		}
	}
	return nil;
}

@end

@implementation WFFormDefinition

+ (instancetype)formWithKey:(NSString *)formKey
                     fields:(NSArray<WFFormField *> *)fields
         businessKeyFieldId:(NSString *)businessKeyFieldId
{
	WFFormDefinition *form = [[self alloc] wf_init];
	form->_formKey = [formKey copy];
	form->_fields = [fields copy] ?: @[];
	form->_businessKeyFieldId = [businessKeyFieldId copy];
	return form;
}

- (instancetype)wf_init
{
	return [super init];
}

- (WFFormField *)fieldWithId:(NSString *)fieldId
{
	for (WFFormField *field in _fields) {
		if ([field.fieldId isEqualToString:fieldId]) {
			return field;
		}
	}
	return nil;
}

- (NSString *)problem
{
	NSMutableSet *ids = [NSMutableSet set];
	NSSet *checked = [NSSet setWithObjects:@"required", @"readonly", @"minlength", @"maxlength", @"min", @"max", nil];
	for (WFFormField *field in _fields) {
		if ([field.fieldId length] == 0) {
			return @"a form field needs an id";
		}
		if ([ids containsObject:field.fieldId]) {
			return [NSString stringWithFormat:@"form field %@ is there twice", field.fieldId];
		}
		[ids addObject:field.fieldId];
		if (field.type == WFFormFieldTypeEnum && [field.values count] == 0) {
			return [NSString stringWithFormat:@"form field %@: an enum needs its values", field.fieldId];
		}
		for (WFFormConstraint *constraint in field.constraints) {
			if (![checked containsObject:constraint.name]) {
				return [NSString stringWithFormat:@"form field %@: constraint %@ is not one the engine checks",
					field.fieldId, constraint.name];
			}
			BOOL bounded = [constraint.name hasPrefix:@"min"] || [constraint.name hasPrefix:@"max"];
			if (bounded && [field bound:constraint.configuration] == nil) {
				return [NSString stringWithFormat:@"form field %@: constraint %@ needs %@, not \"%@\"",
					field.fieldId, constraint.name,
					field.type == WFFormFieldTypeDate && ![constraint.name hasSuffix:@"length"] ? @"a date"
						: @"a whole number", constraint.configuration ?: @""];
			}
		}
	}
	if (_businessKeyFieldId != nil && ![ids containsObject:_businessKeyFieldId]) {
		return [NSString stringWithFormat:@"the business key field %@ is not a form field", _businessKeyFieldId];
	}
	return nil;
}

- (NSDictionary *)variablesFromValues:(NSDictionary *)values error:(NSError **)error
{
	NSMutableDictionary *variables = [NSMutableDictionary dictionaryWithDictionary:values ?: @{}];
	for (WFFormField *field in _fields) {
		id given = [values objectForKey:field.fieldId];
		if (given != nil && field.readOnly) {
			if (error != NULL) {
				*error = WFFormError(field.fieldId, @"is read-only");
			}
			return nil;
		}
		NSString *reason = nil;
		id value = [field convert:given reason:&reason];
		if (value == nil) {
			if (error != NULL) {
				*error = WFFormError(field.fieldId, [NSString stringWithFormat:@"\"%@\" %@", given, reason]);
			}
			return nil;
		}
		NSString *violation = field.readOnly ? nil : [field violationBy:value];
		if (violation != nil) {
			if (error != NULL) {
				*error = WFFormError(field.fieldId, violation);
			}
			return nil;
		}
		if (given != nil) {
			[variables setObject:value forKey:field.fieldId];
		}
	}
	return variables;
}

- (id)displayValue:(id)value ofField:(WFFormField *)field
{
	/* FEEL's numbers are decimals, and its dates text or dates. */
	if (field.type == WFFormFieldTypeString && [value isKindOfClass:[NSNumber class]]) {
		return [value description];
	}
	NSString *reason = nil;
	return [field convert:value reason:&reason] ?: [NSNull null];
}

@end

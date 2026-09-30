#import "WFTypes.h"

@class WFFeelExpression;

/* A field's type, as camunda:formField's type names it. */
typedef NS_ENUM(NSInteger, WFFormFieldType) {
	/* An NSString. */
	WFFormFieldTypeString = 0,
	/* A whole NSNumber, or text that is one. */
	WFFormFieldTypeLong,
	/* A boolean NSNumber, or true or false as text. */
	WFFormFieldTypeBoolean,
	/* An NSDate, or ISO-8601 text: a date, or a date and time. */
	WFFormFieldTypeDate,
	/* The id of one of the field's values. */
	WFFormFieldTypeEnum
};

/* One value an enum field may take: its id, and the name shown for it. */
@interface WFFormFieldValue : NSObject
@property (nonatomic, readonly, copy) NSString *valueId;
@property (nonatomic, readonly, copy) NSString *name;
+ (instancetype)valueWithId:(NSString *)valueId name:(NSString *)name;
- (instancetype)init NS_UNAVAILABLE;
@end

/*
 * What a field's value must be, as camunda:constraint names it: required
 * (a value, and not empty text), readonly (shown, never submitted),
 * minlength and maxlength (of text), min and max (of a number or a date,
 * a date as ISO-8601 text in the configuration).
 */
@interface WFFormConstraint : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *configuration;
+ (instancetype)constraint:(NSString *)name configuration:(NSString *)configuration;
- (instancetype)init NS_UNAVAILABLE;
@end

/* One field of a form: a variable, as the form shows and takes it. */
@interface WFFormField : NSObject
/* The variable's name. */
@property (nonatomic, readonly, copy) NSString *fieldId;
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly) WFFormFieldType type;
/* The value shown when the variable is not set, evaluated over the
 * variables; nil for none. */
@property (nonatomic, readonly, strong) WFFeelExpression *defaultValue;
/* An enum field's values, in order. */
@property (nonatomic, readonly, copy) NSArray<WFFormFieldValue *> *values;
@property (nonatomic, readonly, copy) NSArray<WFFormConstraint *> *constraints;
/* camunda:properties: whatever the application reads (a hint to the UI). */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *properties;
@property (nonatomic, readonly, getter=isRequired) BOOL required;
@property (nonatomic, readonly, getter=isReadOnly) BOOL readOnly;
+ (instancetype)fieldWithId:(NSString *)fieldId
                      label:(NSString *)label
                       type:(WFFormFieldType)type
               defaultValue:(WFFeelExpression *)defaultValue
                     values:(NSArray<WFFormFieldValue *> *)values
                constraints:(NSArray<WFFormConstraint *> *)constraints
                 properties:(NSDictionary<NSString *, NSString *> *)properties;
- (instancetype)init NS_UNAVAILABLE;
/* The type's name: string, long, boolean, date, enum; and back, nil for
 * a name that is none of them. */
+ (NSString *)nameOfType:(WFFormFieldType)type;
+ (NSNumber *)typeNamed:(NSString *)name;
@end

/*
 * The form of a user task or a start event: what a person sees and fills
 * in. The engine renders nothing; it keeps what the form is, gives its
 * values, and checks what comes back.
 *
 * Two kinds, alone or together, as Camunda 7 has them:
 *
 *  - fields (camunda:formData): the variables the form shows and takes,
 *    each typed and constrained. From them an application generates a
 *    form, or checks one of its own.
 *  - a form key (camunda:formKey): the name of a form the application
 *    has -- a native view, an XForms document -- which it resolves itself.
 */
@interface WFFormDefinition : NSObject
@property (nonatomic, readonly, copy) NSString *formKey;
@property (nonatomic, readonly, copy) NSArray<WFFormField *> *fields;
/* A start form's field whose value becomes the instance's business key
 * (camunda:formData businessKey); nil for none. */
@property (nonatomic, readonly, copy) NSString *businessKeyFieldId;
+ (instancetype)formWithKey:(NSString *)formKey
                     fields:(NSArray<WFFormField *> *)fields
         businessKeyFieldId:(NSString *)businessKeyFieldId;
- (instancetype)init NS_UNAVAILABLE;
- (WFFormField *)fieldWithId:(NSString *)fieldId;
/* What is wrong with the definition -- two fields of one id, an enum
 * without values, a constraint the engine does not check or whose
 * configuration is not of its kind, a business key field that is not a
 * field -- or nil. */
- (NSString *)problem;
/*
 * Values submitted, as the variables they set: each field's value
 * converted to its type (text to a number, a boolean or a date), and
 * checked against the field's constraints. A value of no field is passed
 * as it is. nil, with a WFErrorInvalidFormData error naming the field,
 * for a value the form does not take: of another type, not one of an
 * enum's values, a required field without one, a read-only one given.
 */
- (NSDictionary *)variablesFromValues:(NSDictionary *)values error:(NSError **)error;
/* A value shown in a field, as its type has it; NSNull when it has none
 * or is not of the type. */
- (id)displayValue:(id)value ofField:(WFFormField *)field;
@end

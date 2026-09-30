#import "WFDecision.h"
#import "WFDecision+Repository.h"
#import "WFFeel.h"
#import "WFFeelInternal.h"

static NSString * const WFDmnNamespaces[] = {
	@"https://www.omg.org/spec/DMN/20191111/MODEL/",
	@"http://www.omg.org/spec/DMN/20180521/MODEL/",
	@"http://www.omg.org/spec/DMN/20151101/dmn.xsd",
};
static NSString * const WFCamundaDmnNamespace = @"http://camunda.org/schema/1.0/dmn";

static NSError *
WFDmnError(WFErrorCode code, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	return [NSError errorWithDomain:WFErrorDomain
	                           code:code
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

#pragma mark - Types

/* The value as the typeRef has it, or nil with an error when it cannot
 * be: numbers become whole numbers or doubles, text a date. Null stays
 * null, and a value with no typeRef stays as it is. */
static id
WFDmnCoerce(id value, NSString *typeRef, NSString *what, NSError **error)
{
	if ([typeRef length] == 0 || value == nil || value == [NSNull null]) {
		return value ?: [NSNull null];
	}
	BOOL isBoolean = WFFeelIsBoolean(value);
	BOOL isNumber = [value isKindOfClass:[NSNumber class]] && !isBoolean;
	NSString *type = [typeRef lowercaseString];
	if ([type isEqualToString:@"string"]) {
		if ([value isKindOfClass:[NSString class]]) {
			return value;
		}
		if (isBoolean) {
			return [value boolValue] ? @"true" : @"false";
		}
		if (isNumber) {
			return [value stringValue];
		}
	} else if ([type isEqualToString:@"boolean"]) {
		if (isBoolean) {
			return value;
		}
		if ([value isEqual:@"true"] || [value isEqual:@"false"]) {
			return [NSNumber numberWithBool:[value isEqual:@"true"]];
		}
	} else if ([type isEqualToString:@"integer"] || [type isEqualToString:@"long"]) {
		if (isNumber) {
			double number = [value doubleValue];
			if (number == floor(number)) {
				return [NSNumber numberWithLongLong:[value longLongValue]];
			}
		}
	} else if ([type isEqualToString:@"double"]) {
		if (isNumber) {
			return [NSNumber numberWithDouble:[value doubleValue]];
		}
	} else if ([type isEqualToString:@"date"]) {
		if ([value isKindOfClass:[NSDate class]]) {
			return value;
		}
		if ([value isKindOfClass:[NSString class]]) {
			id date = [[WFFeelExpression expressionWithString:@"date and time(text)" error:NULL]
				valueWithVariables:@{ @"text": value }];
			if ([date isKindOfClass:[NSDate class]]) {
				return date;
			}
		}
	} else {
		/* A type the engine does not know is taken as it comes. */
		return value;
	}
	if (error != NULL) {
		*error = WFDmnError(WFErrorDecision, @"%@ is %@, not a %@", what, value, typeRef);
	}
	return nil;
}

#pragma mark - Model

@interface WFDecisionInput ()
@property (nonatomic, readwrite, copy) NSString *inputId;
@property (nonatomic, readwrite, copy) NSString *label;
@property (nonatomic, readwrite, strong) WFFeelExpression *expression;
@property (nonatomic, readwrite, copy) NSString *typeRef;
@property (nonatomic, readwrite, copy) NSString *inputVariable;
@end

@implementation WFDecisionInput
@end

@interface WFDecisionOutput ()
@property (nonatomic, readwrite, copy) NSString *outputId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *label;
@property (nonatomic, readwrite, copy) NSString *typeRef;
@end

@implementation WFDecisionOutput
@end

@interface WFDecisionRule ()
@property (nonatomic, readwrite, copy) NSString *ruleId;
@property (nonatomic, readwrite, copy) NSArray *inputEntries;
@property (nonatomic, readwrite, copy) NSArray *outputEntries;
@end

@implementation WFDecisionRule
@end

@interface WFDecisionTable ()
@property (nonatomic, readwrite) WFHitPolicy hitPolicy;
@property (nonatomic, readwrite) WFCollectAggregation aggregation;
@property (nonatomic, readwrite, copy) NSArray<WFDecisionInput *> *inputs;
@property (nonatomic, readwrite, copy) NSArray<WFDecisionOutput *> *outputs;
@property (nonatomic, readwrite, copy) NSArray<WFDecisionRule *> *rules;
@end

@implementation WFDecisionTable
@end

@implementation WFDecisionResult

- (instancetype)initWithResultList:(NSArray<NSDictionary<NSString *, id> *> *)resultList
{
	self = [super init];
	if (self) {
		_resultList = [resultList copy] ?: @[];
	}
	return self;
}

- (NSDictionary<NSString *, id> *)singleResult:(NSError **)error
{
	if ([_resultList count] > 1) {
		if (error != NULL) {
			*error = WFDmnError(WFErrorDecision, @"the decision gave %lu results, not one",
				(unsigned long)[_resultList count]);
		}
		return nil;
	}
	return [_resultList firstObject];
}

- (id)singleEntry:(NSError **)error
{
	NSDictionary *result = [self singleResult:error];
	if ([result count] > 1) {
		if (error != NULL) {
			*error = WFDmnError(WFErrorDecision, @"the decision's result has %lu values, not one: %@",
				(unsigned long)[result count], [[result allKeys] componentsJoinedByString:@", "]);
		}
		return nil;
	}
	return [[result allValues] firstObject];
}

- (NSArray *)collectEntries:(NSString *)name
{
	NSMutableArray *entries = [NSMutableArray array];
	for (NSDictionary *result in _resultList) {
		id value = [result objectForKey:name];
		if (value != nil) {
			[entries addObject:value];
		}
	}
	return entries;
}

- (NSString *)description
{
	return [_resultList description];
}

@end

@interface WFDecisionDefinition ()
@property (nonatomic, readwrite, copy) NSString *key;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *versionTag;
@property (nonatomic, readwrite) NSInteger version;
@property (nonatomic, readwrite, copy) NSString *definitionId;
@property (nonatomic, readwrite, copy) NSString *deploymentId;
@property (nonatomic, readwrite, copy) NSString *resourceName;
@property (nonatomic, readwrite, strong) WFDecisionTable *table;
@property (nonatomic, readwrite, strong) WFFeelExpression *literalExpression;
@property (nonatomic, readwrite, copy) NSString *literalVariable;
@property (nonatomic, readwrite, copy) NSString *literalTypeRef;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *requiredDecisionKeys;
/* The decisions it requires themselves, from the same file. */
@property (nonatomic, copy) NSArray<WFDecisionDefinition *> *requiredDecisions;
- (instancetype)initEmpty;
@end

@implementation WFDecisionDefinition

- (instancetype)initEmpty
{
	return [super init];
}

- (WFDecisionDefinition *)wf_deployedCopyWithVersion:(NSInteger)version
                                        definitionId:(NSString *)definitionId
                                        deploymentId:(NSString *)deploymentId
                                        resourceName:(NSString *)resourceName
{
	WFDecisionDefinition *copy = [[WFDecisionDefinition alloc] initEmpty];
	copy.key = self.key;
	copy.name = self.name;
	copy.versionTag = self.versionTag;
	copy.table = self.table;
	copy.literalExpression = self.literalExpression;
	copy.literalVariable = self.literalVariable;
	copy.literalTypeRef = self.literalTypeRef;
	copy.requiredDecisionKeys = self.requiredDecisionKeys;
	copy.requiredDecisions = self.requiredDecisions;
	copy.version = version;
	copy.definitionId = definitionId;
	copy.deploymentId = deploymentId;
	copy.resourceName = resourceName;
	return copy;
}

- (NSError *)failure:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	return WFDmnError(WFErrorDecision, @"decision %@: %@", self.key, message);
}

/* The variables with what the required decisions give. */
- (NSDictionary *)variablesWithRequired:(NSDictionary *)variables error:(NSError **)error
{
	if ([self.requiredDecisions count] == 0) {
		return variables;
	}
	NSMutableDictionary *merged = [variables mutableCopy];
	for (WFDecisionDefinition *required in self.requiredDecisions) {
		WFDecisionResult *result = [required evaluateWithVariables:variables inputs:nil error:error];
		if (result == nil) {
			return nil;
		}
		if ([result.resultList count] == 1) {
			[merged addEntriesFromDictionary:[result.resultList firstObject]];
			continue;
		}
		NSMutableSet *names = [NSMutableSet set];
		for (NSDictionary *each in result.resultList) {
			[names addObjectsFromArray:[each allKeys]];
		}
		for (NSString *name in names) {
			[merged setObject:[result collectEntries:name] forKey:name];
		}
	}
	return merged;
}

- (WFDecisionResult *)evaluateWithVariables:(NSDictionary *)variables
                                     inputs:(NSMutableDictionary *)inputs
                                      error:(NSError **)error
{
	NSDictionary *scope = [self variablesWithRequired:variables ?: @{} error:error];
	if (scope == nil) {
		return nil;
	}
	if (self.table == nil) {
		id value = WFDmnCoerce([self.literalExpression valueWithVariables:scope], self.literalTypeRef,
			[NSString stringWithFormat:@"decision %@: %@", self.key, self.literalVariable], error);
		if (value == nil) {
			return nil;
		}
		return [[WFDecisionResult alloc] initWithResultList:@[ @{ self.literalVariable: value } ]];
	}
	return [self evaluateTable:self.table variables:scope inputs:inputs error:error];
}

- (WFDecisionResult *)evaluateTable:(WFDecisionTable *)table
                          variables:(NSDictionary *)variables
                             inputs:(NSMutableDictionary *)inputs
                              error:(NSError **)error
{
	NSMutableArray *values = [NSMutableArray array];
	for (WFDecisionInput *input in table.inputs) {
		id value = WFDmnCoerce([input.expression valueWithVariables:variables], input.typeRef,
			[NSString stringWithFormat:@"decision %@: input %@", self.key, input.label ?: input.inputId], error);
		if (value == nil) {
			return nil;
		}
		[values addObject:value];
		[inputs setObject:value forKey:input.inputId];
	}
	NSMutableArray *matchedRules = [NSMutableArray array];
	for (WFDecisionRule *rule in table.rules) {
		BOOL matches = YES;
		for (NSUInteger i = 0; i < [table.inputs count] && matches; i++) {
			id entry = [rule.inputEntries objectAtIndex:i];
			if (entry == [NSNull null]) {
				continue;
			}
			WFDecisionInput *input = [table.inputs objectAtIndex:i];
			NSMutableDictionary *cell = [variables mutableCopy];
			id value = [values objectAtIndex:i];
			[cell setObject:value forKey:@"?"];
			[cell setObject:value forKey:input.inputVariable ?: @"cellInput"];
			NSError *entryError = nil;
			matches = [entry evaluateWithVariables:cell error:&entryError];
			if (entryError != nil) {
				if (error != NULL) {
					*error = [self failure:@"rule %@: %@", rule.ruleId, [entryError localizedDescription]];
				}
				return nil;
			}
		}
		if (matches) {
			[matchedRules addObject:rule];
		}
	}
	/* Which rules give the result; only theirs are computed. */
	if (table.hitPolicy == WFHitPolicyUnique && [matchedRules count] > 1) {
		if (error != NULL) {
			*error = [self failure:@"rules %@ match, and at most one may (hit policy UNIQUE)",
				[[matchedRules valueForKey:@"ruleId"] componentsJoinedByString:@", "]];
		}
		return nil;
	}
	if (table.hitPolicy == WFHitPolicyFirst && [matchedRules count] > 1) {
		[matchedRules removeObjectsInRange:NSMakeRange(1, [matchedRules count] - 1)];
	}
	NSMutableArray *matched = [NSMutableArray array];
	for (WFDecisionRule *rule in matchedRules) {
		NSDictionary *outputs = [self outputsOf:rule table:table variables:variables error:error];
		if (outputs == nil) {
			return nil;
		}
		[matched addObject:outputs];
	}
	if (table.hitPolicy == WFHitPolicyAny) {
		for (NSDictionary *other in matched) {
			if (![other isEqual:[matched firstObject]]) {
				if (error != NULL) {
					*error = [self failure:@"rules %@ match with different outputs (hit policy ANY)",
						[[matchedRules valueForKey:@"ruleId"] componentsJoinedByString:@", "]];
				}
				return nil;
			}
		}
		if ([matched count] > 1) {
			[matched removeObjectsInRange:NSMakeRange(1, [matched count] - 1)];
		}
	}
	if (table.hitPolicy == WFHitPolicyCollect && table.aggregation != WFCollectAggregationNone) {
		return [self aggregate:table.aggregation of:matched output:[table.outputs firstObject] error:error];
	}
	return [[WFDecisionResult alloc] initWithResultList:matched];
}

/* A matching rule's outputs by name; an empty output entry gives none. */
- (NSDictionary *)outputsOf:(WFDecisionRule *)rule
                      table:(WFDecisionTable *)table
                  variables:(NSDictionary *)variables
                      error:(NSError **)error
{
	NSMutableDictionary *outputs = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [table.outputs count]; i++) {
		id entry = [rule.outputEntries objectAtIndex:i];
		if (entry == [NSNull null]) {
			continue;
		}
		WFDecisionOutput *output = [table.outputs objectAtIndex:i];
		NSString *name = output.name ?: output.outputId;
		id value = WFDmnCoerce([entry valueWithVariables:variables], output.typeRef,
			[NSString stringWithFormat:@"decision %@: rule %@ output %@", self.key, rule.ruleId, name], error);
		if (value == nil) {
			return nil;
		}
		[outputs setObject:value forKey:name];
	}
	return outputs;
}

/* A COLLECT table's single output over the matching rules, as one value:
 * nothing when no rule gave one, except a count, which is then 0. */
- (WFDecisionResult *)aggregate:(WFCollectAggregation)aggregation
                             of:(NSArray *)matched
                         output:(WFDecisionOutput *)output
                          error:(NSError **)error
{
	NSString *name = output.name ?: output.outputId;
	NSMutableArray *values = [NSMutableArray array];
	for (NSDictionary *result in matched) {
		id value = [result objectForKey:name];
		if (value != nil && value != [NSNull null]) {
			[values addObject:value];
		}
	}
	if (aggregation == WFCollectAggregationCount) {
		return [[WFDecisionResult alloc] initWithResultList:@[
			@{ name: [NSNumber numberWithUnsignedInteger:[values count]] } ]];
	}
	if ([values count] == 0) {
		return [[WFDecisionResult alloc] initWithResultList:@[]];
	}
	NSString *function = aggregation == WFCollectAggregationSum ? @"sum"
		: aggregation == WFCollectAggregationMin ? @"min" : @"max";
	id value = [[WFFeelExpression expressionWithString:[function stringByAppendingString:@"(values)"] error:NULL]
		valueWithVariables:@{ @"values": values }];
	if (value == [NSNull null]) {
		if (error != NULL) {
			*error = [self failure:@"%@ of %@ is not defined: %@", function, name, values];
		}
		return nil;
	}
	value = WFDmnCoerce(value, output.typeRef, [NSString stringWithFormat:@"decision %@: %@", self.key, name], error);
	return value != nil ? [[WFDecisionResult alloc] initWithResultList:@[ @{ name: value } ]] : nil;
}

@end

#pragma mark - Reader

@interface WFDmnReadContext : NSObject
@property (nonatomic, copy) NSString *namespace;
@property (nonatomic, copy) NSString *expressionLanguage;
@property (nonatomic, strong) NSError *error;
@end

@implementation WFDmnReadContext
@end

@implementation WFDmnReader

+ (NSArray<WFDecisionDefinition *> *)decisionsFromXMLString:(NSString *)xml error:(NSError **)error
{
	return [self decisionsFromData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:error];
}

+ (NSArray<NSXMLElement *> *)children:(NSXMLElement *)element context:(WFDmnReadContext *)context
{
	NSMutableArray *found = [NSMutableArray array];
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind && [[child URI] isEqualToString:context.namespace]) {
			[found addObject:child];
		}
	}
	return found;
}

+ (NSXMLElement *)child:(NSXMLElement *)element named:(NSString *)name context:(WFDmnReadContext *)context
{
	for (NSXMLElement *child in [self children:element context:context]) {
		if ([[child localName] isEqualToString:name]) {
			return child;
		}
	}
	return nil;
}

+ (NSString *)attr:(NSString *)name of:(NSXMLElement *)element
{
	return [[element attributeForName:name] stringValue];
}

+ (NSString *)camunda:(NSString *)name of:(NSXMLElement *)element
{
	return [[element attributeForLocalName:name URI:WFCamundaDmnNamespace] stringValue];
}

+ (id)fail:(WFDmnReadContext *)context message:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	if (context.error == nil) {
		context.error = WFDmnError(WFErrorInvalidDmn, @"%@", message);
	}
	return nil;
}

/* An element's <text>, trimmed; nil for none or empty. */
+ (NSString *)textOf:(NSXMLElement *)element context:(WFDmnReadContext *)context
{
	NSString *text = [[[self child:element named:@"text" context:context] stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return [text length] > 0 ? text : nil;
}

/* The language an element's expression is in: FEEL, whatever its
 * version's URI, unless the element or the document says otherwise. */
+ (BOOL)isFeel:(NSXMLElement *)element context:(WFDmnReadContext *)context
{
	NSString *language = [self attr:@"expressionLanguage" of:element] ?: context.expressionLanguage;
	return language == nil || [[language lowercaseString] rangeOfString:@"feel"].location != NSNotFound;
}

/* An expression: `${...}` as Camunda 7's subset, `=...` or anything else
 * as FEEL. unaryTests reads an input entry. */
+ (WFFeelExpression *)expression:(NSString *)text
                              of:(NSXMLElement *)element
                            what:(NSString *)what
                      unaryTests:(BOOL)unaryTests
                         context:(WFDmnReadContext *)context
{
	NSError *parseError = nil;
	WFFeelExpression *expression = nil;
	if (([text hasPrefix:@"${"] || [text hasPrefix:@"#{"]) && [text hasSuffix:@"}"]) {
		expression = [WFFeelExpression expressionWithCamunda7String:
			[text substringWithRange:NSMakeRange(2, [text length] - 3)] error:&parseError];
	} else if (![self isFeel:element context:context]) {
		return [self fail:context message:@"%@: expression language %@ is not supported; use FEEL",
			what, [self attr:@"expressionLanguage" of:element] ?: context.expressionLanguage];
	} else if (unaryTests) {
		expression = [WFFeelExpression unaryTestsWithString:text error:&parseError];
	} else {
		expression = [WFFeelExpression expressionWithString:[text hasPrefix:@"="] ? [text substringFromIndex:1] : text
		                                              error:&parseError];
	}
	if (expression == nil) {
		return [self fail:context message:@"%@: %@", what, [parseError localizedDescription]];
	}
	return expression;
}

+ (NSArray<WFDecisionDefinition *> *)decisionsFromData:(NSData *)data error:(NSError **)error
{
	NSError *xmlError = nil;
	NSXMLDocument *document = data == nil ? nil
		: [[NSXMLDocument alloc] initWithData:data options:0 error:&xmlError];
	NSXMLElement *root = [document rootElement];
	WFDmnReadContext *context = [[WFDmnReadContext alloc] init];
	for (NSUInteger i = 0; i < sizeof(WFDmnNamespaces) / sizeof(WFDmnNamespaces[0]); i++) {
		if ([[root URI] isEqualToString:WFDmnNamespaces[i]]) {
			context.namespace = WFDmnNamespaces[i];
		}
	}
	if (root == nil || context.namespace == nil || ![[root localName] isEqualToString:@"definitions"]) {
		if (error != NULL) {
			*error = root == nil && xmlError != nil ? xmlError
				: WFDmnError(WFErrorInvalidDmn, @"not a DMN 1.1, 1.2 or 1.3 document: the root is %@",
					[root name] ?: @"missing");
		}
		return nil;
	}
	context.expressionLanguage = [self attr:@"expressionLanguage" of:root];

	NSMutableArray *decisions = [NSMutableArray array];
	NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
	NSMutableDictionary *requirements = [NSMutableDictionary dictionary];
	for (NSXMLElement *element in [self children:root context:context]) {
		NSString *name = [element localName];
		if ([name isEqualToString:@"businessKnowledgeModel"] || [name isEqualToString:@"decisionService"]) {
			[self fail:context message:@"%@ %@ is not supported", name, [self attr:@"id" of:element]];
			break;
		}
		if (![name isEqualToString:@"decision"]) {
			/* inputData, knowledgeSource, textAnnotation, association, ... */
			continue;
		}
		NSMutableArray *required = [NSMutableArray array];
		WFDecisionDefinition *decision = [self decision:element required:required context:context];
		if (decision == nil) {
			break;
		}
		if ([byKey objectForKey:decision.key] != nil) {
			[self fail:context message:@"decision %@ is defined twice", decision.key];
			break;
		}
		[decisions addObject:decision];
		[byKey setObject:decision forKey:decision.key];
		[requirements setObject:required forKey:decision.key];
	}
	for (WFDecisionDefinition *decision in decisions) {
		if (context.error != nil) {
			break;
		}
		NSMutableArray *required = [NSMutableArray array];
		for (NSString *key in [requirements objectForKey:decision.key]) {
			WFDecisionDefinition *other = [byKey objectForKey:key];
			if (other == nil) {
				[self fail:context message:@"decision %@ requires %@, which the file does not define",
					decision.key, key];
				break;
			}
			[required addObject:other];
		}
		decision.requiredDecisionKeys = [requirements objectForKey:decision.key];
		decision.requiredDecisions = required;
	}
	for (WFDecisionDefinition *decision in decisions) {
		if (context.error == nil && [self requires:decision itself:decision seen:[NSMutableSet set]]) {
			[self fail:context message:@"decision %@ requires itself", decision.key];
		}
	}
	if (context.error == nil && [decisions count] == 0) {
		[self fail:context message:@"the DMN document defines no decision"];
	}
	if (context.error != nil) {
		if (error != NULL) {
			*error = context.error;
		}
		return nil;
	}
	return decisions;
}

+ (BOOL)requires:(WFDecisionDefinition *)decision itself:(WFDecisionDefinition *)start seen:(NSMutableSet *)seen
{
	for (WFDecisionDefinition *required in decision.requiredDecisions) {
		if (required == start) {
			return YES;
		}
		if (![seen containsObject:required.key]) {
			[seen addObject:required.key];
			if ([self requires:required itself:start seen:seen]) {
				return YES;
			}
		}
	}
	return NO;
}

+ (WFDecisionDefinition *)decision:(NSXMLElement *)element
                          required:(NSMutableArray *)required
                           context:(WFDmnReadContext *)context
{
	NSString *key = [self attr:@"id" of:element];
	if ([key length] == 0) {
		return [self fail:context message:@"a decision has no id"];
	}
	WFDecisionDefinition *decision = [[WFDecisionDefinition alloc] initEmpty];
	decision.key = key;
	decision.name = [self attr:@"name" of:element] ?: key;
	decision.versionTag = [self camunda:@"versionTag" of:element];
	for (NSXMLElement *child in [self children:element context:context]) {
		NSString *name = [child localName];
		if ([name isEqualToString:@"informationRequirement"]) {
			NSXMLElement *requiredDecision = [self child:child named:@"requiredDecision" context:context];
			NSString *href = [self attr:@"href" of:requiredDecision];
			if (href != nil) {
				[required addObject:[href hasPrefix:@"#"] ? [href substringFromIndex:1] : href];
			}
		} else if ([name isEqualToString:@"knowledgeRequirement"]) {
			return [self fail:context message:@"decision %@: knowledge requirements are not supported", key];
		} else if ([name isEqualToString:@"decisionTable"]) {
			decision.table = [self table:child decision:key context:context];
			if (decision.table == nil) {
				return nil;
			}
		} else if ([name isEqualToString:@"literalExpression"]) {
			NSXMLElement *variable = [self child:element named:@"variable" context:context];
			NSString *text = [self textOf:child context:context];
			if (text == nil) {
				return [self fail:context message:@"decision %@: the literal expression is empty", key];
			}
			decision.literalExpression = [self expression:text of:child
			                                         what:[NSString stringWithFormat:@"decision %@", key]
			                                   unaryTests:NO context:context];
			decision.literalVariable = [self attr:@"name" of:variable] ?: key;
			decision.literalTypeRef = [self attr:@"typeRef" of:variable] ?: [self attr:@"typeRef" of:child];
			if (decision.literalExpression == nil) {
				return nil;
			}
		} else if ([@[ @"context", @"invocation", @"relation", @"list", @"functionDefinition" ] containsObject:name]) {
			return [self fail:context message:@"decision %@: %@ is not supported", key, name];
		}
	}
	if (decision.table == nil && decision.literalExpression == nil) {
		return [self fail:context message:@"decision %@ has neither a decision table nor a literal expression", key];
	}
	return decision;
}

+ (WFDecisionTable *)table:(NSXMLElement *)element decision:(NSString *)key context:(WFDmnReadContext *)context
{
	WFDecisionTable *table = [[WFDecisionTable alloc] init];
	NSDictionary *policies = @{ @"UNIQUE": @(WFHitPolicyUnique), @"FIRST": @(WFHitPolicyFirst),
		@"ANY": @(WFHitPolicyAny), @"RULE ORDER": @(WFHitPolicyRuleOrder), @"COLLECT": @(WFHitPolicyCollect) };
	NSString *policy = [self attr:@"hitPolicy" of:element] ?: @"UNIQUE";
	if ([policies objectForKey:policy] == nil) {
		return [self fail:context message:@"decision %@: hit policy %@ is not supported", key, policy];
	}
	table.hitPolicy = (WFHitPolicy)[[policies objectForKey:policy] integerValue];
	NSString *aggregation = [self attr:@"aggregation" of:element];
	if (aggregation != nil) {
		NSDictionary *aggregations = @{ @"SUM": @(WFCollectAggregationSum), @"MIN": @(WFCollectAggregationMin),
			@"MAX": @(WFCollectAggregationMax), @"COUNT": @(WFCollectAggregationCount) };
		if (table.hitPolicy != WFHitPolicyCollect || [aggregations objectForKey:aggregation] == nil) {
			return [self fail:context message:@"decision %@: aggregation %@ is only SUM, MIN, MAX or COUNT, with COLLECT",
				key, aggregation];
		}
		table.aggregation = (WFCollectAggregation)[[aggregations objectForKey:aggregation] integerValue];
	}
	NSMutableArray *inputs = [NSMutableArray array];
	NSMutableArray *outputs = [NSMutableArray array];
	NSMutableArray *rules = [NSMutableArray array];
	for (NSXMLElement *child in [self children:element context:context]) {
		NSString *name = [child localName];
		NSString *childId = [self attr:@"id" of:child] ?: [NSString stringWithFormat:@"%@_%lu", name,
			(unsigned long)([inputs count] + [outputs count] + [rules count])];
		if ([name isEqualToString:@"input"]) {
			WFDecisionInput *input = [[WFDecisionInput alloc] init];
			input.inputId = childId;
			input.label = [self attr:@"label" of:child];
			input.inputVariable = [self camunda:@"inputVariable" of:child] ?: @"cellInput";
			NSXMLElement *inputExpression = [self child:child named:@"inputExpression" context:context];
			input.typeRef = [self attr:@"typeRef" of:inputExpression];
			NSString *text = [self textOf:inputExpression context:context];
			if (text == nil) {
				return [self fail:context message:@"decision %@: input %@ has no expression", key, childId];
			}
			input.expression = [self expression:text of:inputExpression
			                               what:[NSString stringWithFormat:@"decision %@: input %@", key, childId]
			                         unaryTests:NO context:context];
			if (input.expression == nil) {
				return nil;
			}
			[inputs addObject:input];
		} else if ([name isEqualToString:@"output"]) {
			WFDecisionOutput *output = [[WFDecisionOutput alloc] init];
			output.outputId = childId;
			output.name = [self attr:@"name" of:child];
			output.label = [self attr:@"label" of:child];
			output.typeRef = [self attr:@"typeRef" of:child];
			[outputs addObject:output];
		} else if ([name isEqualToString:@"rule"]) {
			WFDecisionRule *rule = [self rule:child id:childId decision:key context:context];
			if (rule == nil) {
				return nil;
			}
			[rules addObject:rule];
		}
	}
	if ([outputs count] == 0) {
		return [self fail:context message:@"decision %@: the decision table has no output", key];
	}
	if ([outputs count] > 1) {
		for (WFDecisionOutput *output in outputs) {
			if ([output.name length] == 0) {
				return [self fail:context message:@"decision %@: output %@ needs a name, as the table has several",
					key, output.outputId];
			}
		}
	}
	if (table.aggregation != WFCollectAggregationNone && [outputs count] != 1) {
		return [self fail:context message:@"decision %@: an aggregation needs exactly one output", key];
	}
	for (WFDecisionRule *rule in rules) {
		if ([rule.inputEntries count] != [inputs count] || [rule.outputEntries count] != [outputs count]) {
			return [self fail:context message:@"decision %@: rule %@ has %lu input and %lu output entries, not %lu and %lu",
				key, rule.ruleId, (unsigned long)[rule.inputEntries count], (unsigned long)[rule.outputEntries count],
				(unsigned long)[inputs count], (unsigned long)[outputs count]];
		}
	}
	table.inputs = inputs;
	table.outputs = outputs;
	table.rules = rules;
	return table;
}

+ (WFDecisionRule *)rule:(NSXMLElement *)element
                      id:(NSString *)ruleId
                decision:(NSString *)key
                 context:(WFDmnReadContext *)context
{
	WFDecisionRule *rule = [[WFDecisionRule alloc] init];
	rule.ruleId = ruleId;
	NSMutableArray *inputEntries = [NSMutableArray array];
	NSMutableArray *outputEntries = [NSMutableArray array];
	for (NSXMLElement *child in [self children:element context:context]) {
		NSString *name = [child localName];
		BOOL input = [name isEqualToString:@"inputEntry"];
		if (!input && ![name isEqualToString:@"outputEntry"]) {
			/* description, annotationEntry */
			continue;
		}
		NSString *text = [self textOf:child context:context];
		NSMutableArray *entries = input ? inputEntries : outputEntries;
		if (text == nil || (input && [text isEqualToString:@"-"])) {
			[entries addObject:[NSNull null]];
			continue;
		}
		WFFeelExpression *expression = [self expression:text of:child
		                                           what:[NSString stringWithFormat:@"decision %@: rule %@", key, ruleId]
		                                     unaryTests:input context:context];
		if (expression == nil) {
			return nil;
		}
		[entries addObject:expression];
	}
	rule.inputEntries = inputEntries;
	rule.outputEntries = outputEntries;
	return rule;
}

@end

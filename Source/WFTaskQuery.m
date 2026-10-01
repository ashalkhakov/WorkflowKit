#import "WFTaskQuery+Internal.h"
#import "WFEntities.h"
#import "WFIdentity+Internal.h"

static NSError *
WFQueryError(NSString *message)
{
	return [NSError errorWithDomain:WFErrorDomain code:WFErrorInvalidQuery
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSPredicate *
WFCompare(NSExpression *left, NSPredicateOperatorType type, id value)
{
	return [NSComparisonPredicate predicateWithLeftExpression:left
	                                          rightExpression:[NSExpression expressionForConstantValue:value]
	                                                 modifier:NSDirectPredicateModifier
	                                                     type:type
	                                                  options:0];
}

static NSPredicate *
WFKeyCompare(NSString *key, NSPredicateOperatorType type, id value)
{
	return WFCompare([NSExpression expressionForKeyPath:key], type, value);
}

/* A key path off the subquery's variable: generated names only. */
static NSExpression *
WFVariableKey(NSString *key)
{
	return [NSExpression expressionWithFormat:[NSString stringWithFormat:@"$v.%@", key]];
}

static NSPredicate *
WFAnd(NSArray *predicates)
{
	return [NSCompoundPredicate andPredicateWithSubpredicates:predicates];
}

static NSPredicateOperatorType
WFOperatorType(WFQueryOperator op)
{
	switch (op) {
	case WFQueryNotEqual:
		return NSNotEqualToPredicateOperatorType;
	case WFQueryGreater:
		return NSGreaterThanPredicateOperatorType;
	case WFQueryGreaterOrEqual:
		return NSGreaterThanOrEqualToPredicateOperatorType;
	case WFQueryLess:
		return NSLessThanPredicateOperatorType;
	case WFQueryLessOrEqual:
		return NSLessThanOrEqualToPredicateOperatorType;
	case WFQueryLike:
		return NSLikePredicateOperatorType;
	case WFQueryEqual:
	default:
		return NSEqualToPredicateOperatorType;
	}
}

/* A pattern's % and _ as LIKE's * and ?, which stand for themselves in it. */
static NSString *
WFLikePattern(NSString *pattern)
{
	NSMutableString *like = [NSMutableString string];
	for (NSUInteger i = 0; i < [pattern length]; i++) {
		unichar c = [pattern characterAtIndex:i];
		if (c == '%') {
			[like appendString:@"*"];
		} else if (c == '_') {
			[like appendString:@"?"];
		} else {
			if (c == '*' || c == '?' || c == '\\') {
				[like appendString:@"\\"];
			}
			[like appendFormat:@"%C", c];
		}
	}
	return like;
}

/* A value in its column: one that holds it, so that NOT of it holds for
 * a row whose value is of another type, in SQL's logic as in memory's. */
static NSPredicate *
WFColumn(NSString *key, NSPredicateOperatorType type, id value)
{
	return WFAnd(@[ WFCompare(WFVariableKey(key), NSNotEqualToPredicateOperatorType, nil),
	                WFCompare(WFVariableKey(key), type, value) ]);
}

/* What a variable row holding the value, by the operator, is; ne aside. */
static NSPredicate *
WFTypedCondition(NSString *name, WFQueryOperator op, id value, NSError **error)
{
	NSExpression *type = WFVariableKey(@"type");
	BOOL ordered = op != WFQueryEqual && op != WFQueryLike;
	if (value == nil || value == [NSNull null]) {
		if (op != WFQueryEqual) {
			if (error != NULL) {
				*error = WFQueryError([NSString stringWithFormat:@"%@: null is only compared for equality", name]);
			}
			return nil;
		}
		return WFCompare(type, NSEqualToPredicateOperatorType, @(WFVariableTypeNull));
	}
	if (op == WFQueryLike && ![value isKindOfClass:[NSString class]]) {
		if (error != NULL) {
			*error = WFQueryError([NSString stringWithFormat:@"%@: like matches a string", name]);
		}
		return nil;
	}
	/* Each type in a column of its own: a value is compared in its type's. */
	if ([value isKindOfClass:[NSString class]]) {
		id operand = op == WFQueryLike ? WFLikePattern(value) : value;
		return WFColumn(@"textValue", WFOperatorType(op), operand);
	}
	if ([value isKindOfClass:[NSNumber class]] && WFIsBooleanNumber(value)) {
		if (ordered) {
			if (error != NULL) {
				*error = WFQueryError([NSString stringWithFormat:@"%@: a boolean is only compared for equality", name]);
			}
			return nil;
		}
		return WFColumn(@"truthValue", NSEqualToPredicateOperatorType, [NSNumber numberWithBool:[value boolValue]]);
	}
	if ([value isKindOfClass:[NSNumber class]]) {
		return WFColumn(@"realNumber", WFOperatorType(op), [NSNumber numberWithDouble:[value doubleValue]]);
	}
	if ([value isKindOfClass:[NSDate class]]) {
		return WFColumn(@"dateTime", WFOperatorType(op), value);
	}
	if (error != NULL) {
		*error = WFQueryError([NSString stringWithFormat:@"%@: a %@ is not a value a query compares",
			name, NSStringFromClass([value class])]);
	}
	return nil;
}

NSPredicate *
WFVariablePredicate(NSString *variablesKeyPath, NSString *name, WFQueryOperator op, id value, NSError **error)
{
	if (name == nil) {
		if (error != NULL) {
			*error = WFQueryError(@"a variable condition needs the variable's name");
		}
		return nil;
	}
	/* ne: set, to anything else. */
	NSPredicate *typed = WFTypedCondition(name, op == WFQueryNotEqual ? WFQueryEqual : op, value, error);
	if (typed == nil) {
		return nil;
	}
	if (op == WFQueryNotEqual) {
		typed = [NSCompoundPredicate notPredicateWithSubpredicate:typed];
	}
	NSPredicate *row = WFAnd(@[ WFCompare(WFVariableKey(@"name"), NSEqualToPredicateOperatorType, name), typed ]);
	NSExpression *matching = [NSExpression expressionForSubquery:[NSExpression expressionForKeyPath:variablesKeyPath]
	                                       usingIteratorVariable:@"v"
	                                                   predicate:row];
	return WFCompare([NSExpression expressionForFunction:@"count:" arguments:@[ matching ]],
	                 NSGreaterThanPredicateOperatorType, @0);
}

@implementation WFTaskQuery
{
	NSMutableArray<NSPredicate *> *_conditions;
	NSMutableArray<NSSortDescriptor *> *_order;
	NSString *_definitionKey;
	NSError *_error;
}

+ (instancetype)query
{
	return [[self alloc] init];
}

- (instancetype)init
{
	if ((self = [super init])) {
		_conditions = [NSMutableArray array];
		_order = [NSMutableArray array];
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	WFTaskQuery *copy = [[[self class] allocWithZone:zone] init];
	[copy->_conditions addObjectsFromArray:_conditions];
	[copy->_order addObjectsFromArray:_order];
	copy->_definitionKey = [_definitionKey copy];
	copy->_error = _error;
	return copy;
}

- (instancetype)where:(NSPredicate *)condition
{
	[_conditions addObject:condition];
	return self;
}

- (instancetype)processInstanceId:(NSString *)processInstanceId
{
	return [self where:WFKeyCompare(@"processInstanceId", NSEqualToPredicateOperatorType, processInstanceId)];
}

- (instancetype)businessKey:(NSString *)businessKey
{
	return [self where:WFKeyCompare(@"processInstance.businessKey", NSEqualToPredicateOperatorType, businessKey)];
}

- (instancetype)processDefinitionId:(NSString *)definitionId
{
	return [self where:WFKeyCompare(@"definitionId", NSEqualToPredicateOperatorType, definitionId)];
}

- (instancetype)processDefinitionKey:(NSString *)key
{
	/* A second key matches nothing, as two conditions on one would. */
	if (_definitionKey != nil && ![_definitionKey isEqualToString:key]) {
		return [self where:[NSPredicate predicateWithValue:NO]];
	}
	_definitionKey = [key copy];
	return self;
}

- (instancetype)taskDefinitionKey:(NSString *)key
{
	return [self where:WFKeyCompare(@"taskDefinitionKey", NSEqualToPredicateOperatorType, key)];
}

- (instancetype)nameLike:(NSString *)pattern
{
	return [self where:WFKeyCompare(@"name", NSLikePredicateOperatorType, WFLikePattern(pattern ?: @""))];
}

- (instancetype)assignee:(NSString *)userId
{
	return [self where:WFKeyCompare(@"assignee", NSEqualToPredicateOperatorType, userId)];
}

- (instancetype)unassigned
{
	return [self where:WFKeyCompare(@"assignee", NSEqualToPredicateOperatorType, nil)];
}

- (instancetype)assigned
{
	return [self where:WFKeyCompare(@"assignee", NSNotEqualToPredicateOperatorType, nil)];
}

/* Unclaimed, with a candidate link the condition holds for. */
- (instancetype)offeredTo:(NSPredicate *)link
{
	NSPredicate *candidate = WFAnd(@[ WFCompare(WFVariableKey(@"type"), NSEqualToPredicateOperatorType,
	                                            WFIdentityLinkCandidate),
	                                  link ]);
	NSExpression *links = [NSExpression expressionForSubquery:[NSExpression expressionForKeyPath:@"identityLinks"]
	                                    usingIteratorVariable:@"v"
	                                                predicate:candidate];
	[self unassigned];
	return [self where:WFCompare([NSExpression expressionForFunction:@"count:" arguments:@[ links ]],
	                             NSGreaterThanPredicateOperatorType, @0)];
}

- (instancetype)candidateUser:(NSString *)userId groups:(NSArray<NSString *> *)groupIds
{
	NSMutableArray *either = [NSMutableArray array];
	if (userId != nil) {
		[either addObject:WFCompare(WFVariableKey(@"userId"), NSEqualToPredicateOperatorType, userId)];
	}
	if ([groupIds count] > 0) {
		[either addObject:WFCompare(WFVariableKey(@"groupId"), NSInPredicateOperatorType, groupIds)];
	}
	if ([either count] == 0) {
		return [self where:[NSPredicate predicateWithValue:NO]];
	}
	return [self offeredTo:[NSCompoundPredicate orPredicateWithSubpredicates:either]];
}

- (instancetype)candidateGroup:(NSString *)groupId
{
	return [self candidateUser:nil groups:groupId != nil ? @[ groupId ] : nil];
}

- (instancetype)visibleTo:(WFIdentity *)identity
{
	NSPredicate *offered = [NSCompoundPredicate andPredicateWithSubpredicates:@[
		WFKeyCompare(@"assignee", NSEqualToPredicateOperatorType, nil),
		WFLinksMatch(@"identityLinks", WFIdentityLinkCandidate, identity) ]];
	if (identity.userId == nil) {
		return [self where:offered];
	}
	return [self where:[NSCompoundPredicate orPredicateWithSubpredicates:@[
		WFKeyCompare(@"assignee", NSEqualToPredicateOperatorType, identity.userId), offered ]]];
}

- (instancetype)minPriority:(NSInteger)priority
{
	return [self where:WFKeyCompare(@"priority", NSGreaterThanOrEqualToPredicateOperatorType,
	                                [NSNumber numberWithInteger:priority])];
}

- (instancetype)maxPriority:(NSInteger)priority
{
	return [self where:WFKeyCompare(@"priority", NSLessThanOrEqualToPredicateOperatorType,
	                                [NSNumber numberWithInteger:priority])];
}

- (instancetype)dueBefore:(NSDate *)date
{
	return [self where:WFKeyCompare(@"dueDate", NSLessThanPredicateOperatorType, date)];
}

- (instancetype)dueAfter:(NSDate *)date
{
	return [self where:WFKeyCompare(@"dueDate", NSGreaterThanPredicateOperatorType, date)];
}

- (instancetype)followUpBefore:(NSDate *)date
{
	return [self where:WFKeyCompare(@"followUpDate", NSLessThanPredicateOperatorType, date)];
}

- (instancetype)suspended:(BOOL)suspended
{
	return [self where:WFKeyCompare(@"suspended", NSEqualToPredicateOperatorType, [NSNumber numberWithBool:suspended])];
}

- (instancetype)processVariable:(NSString *)name operator:(WFQueryOperator)op value:(id)value
{
	NSError *error = nil;
	NSPredicate *condition = WFVariablePredicate(@"processInstance.variables", name, op, value, &error);
	if (condition == nil) {
		if (_error == nil) {
			_error = error;
		}
		return self;
	}
	return [self where:condition];
}

- (instancetype)orderBy:(WFTaskOrder)order ascending:(BOOL)ascending
{
	NSString *key;
	switch (order) {
	case WFTaskOrderDueDate:
		key = @"dueDate";
		break;
	case WFTaskOrderFollowUpDate:
		key = @"followUpDate";
		break;
	case WFTaskOrderPriority:
		key = @"priority";
		break;
	case WFTaskOrderName:
		key = @"name";
		break;
	case WFTaskOrderAssignee:
		key = @"assignee";
		break;
	case WFTaskOrderCreated:
	default:
		key = @"createdAt";
		break;
	}
	[_order addObject:[NSSortDescriptor sortDescriptorWithKey:key ascending:ascending]];
	return self;
}

@end

@implementation WFTaskQuery (Internal)

- (NSString *)wf_processDefinitionKey
{
	return _definitionKey;
}

- (NSPredicate *)wf_predicateWithDefinitionIds:(NSArray<NSString *> *)definitionIds error:(NSError **)error
{
	if (_error != nil) {
		if (error != NULL) {
			*error = _error;
		}
		return nil;
	}
	NSMutableArray *conditions = [NSMutableArray arrayWithArray:_conditions];
	if (_definitionKey != nil) {
		[conditions addObject:WFKeyCompare(@"definitionId", NSInPredicateOperatorType, definitionIds ?: @[])];
	}
	if ([conditions count] == 0) {
		return [NSPredicate predicateWithValue:YES];
	}
	return WFAnd(conditions);
}

- (NSArray<NSSortDescriptor *> *)wf_sortDescriptors
{
	/* Then by creation, and by id for an order that does not change. */
	NSMutableArray *order = [NSMutableArray arrayWithArray:_order];
	[order addObject:[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]];
	[order addObject:[NSSortDescriptor sortDescriptorWithKey:@"taskId" ascending:YES]];
	return order;
}

@end

#import "WFIdentity.h"
#import "WFIdentity+Internal.h"

@implementation WFIdentity

+ (instancetype)identityWithUserId:(NSString *)userId
                            groups:(NSArray<NSString *> *)groups
                            claims:(NSDictionary<NSString *, id> *)claims
{
	WFIdentity *identity = [[self alloc] wf_init];
	identity->_userId = [userId copy];
	identity->_groups = [groups copy] ?: @[];
	identity->_claims = [claims copy] ?: @{};
	return identity;
}

- (instancetype)wf_init
{
	return [super init];
}

- (NSArray<NSString *> *)valuesOfClaim:(NSString *)name
{
	id value = [_claims objectForKey:name];
	NSMutableArray *values = [NSMutableArray array];
	for (id item in [value isKindOfClass:[NSArray class]] ? value : (value != nil ? @[ value ] : @[])) {
		if ([item isKindOfClass:[NSString class]] || [item isKindOfClass:[NSNumber class]]) {
			[values addObject:[item description]];
		}
	}
	return values;
}

@end

/* key == value, built, never formatted. */
static NSPredicate *
WFIdentityCompare(NSExpression *left, NSPredicateOperatorType type, id value)
{
	return [NSComparisonPredicate predicateWithLeftExpression:left
	                                          rightExpression:[NSExpression expressionForConstantValue:value]
	                                                 modifier:NSDirectPredicateModifier
	                                                     type:type
	                                                  options:0];
}

static NSExpression *
WFIdentityKey(NSString *variable, NSString *key)
{
	return [NSExpression expressionWithFormat:[NSString stringWithFormat:@"$%@.%@", variable, key]];
}

NSPredicate *
WFIdentityLinkMatches(NSString *variable, WFIdentity *identity)
{
	NSMutableArray *either = [NSMutableArray array];
	if (identity.userId != nil) {
		[either addObject:WFIdentityCompare(WFIdentityKey(variable, @"userId"), NSEqualToPredicateOperatorType,
		                                    identity.userId)];
	}
	if ([identity.groups count] > 0) {
		[either addObject:WFIdentityCompare(WFIdentityKey(variable, @"groupId"), NSInPredicateOperatorType,
		                                    identity.groups)];
	}
	for (NSString *name in [[identity.claims allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSArray *values = [identity valuesOfClaim:name];
		if ([values count] == 0) {
			continue;
		}
		[either addObject:[NSCompoundPredicate andPredicateWithSubpredicates:@[
			WFIdentityCompare(WFIdentityKey(variable, @"claimName"), NSEqualToPredicateOperatorType, name),
			WFIdentityCompare(WFIdentityKey(variable, @"claimValue"), NSInPredicateOperatorType, values) ]]];
	}
	return [either count] > 0 ? [NSCompoundPredicate orPredicateWithSubpredicates:either]
		: [NSPredicate predicateWithValue:NO];
}

NSPredicate *
WFLinksMatch(NSString *linksKeyPath, NSString *type, WFIdentity *identity)
{
	NSPredicate *link = [NSCompoundPredicate andPredicateWithSubpredicates:@[
		WFIdentityCompare(WFIdentityKey(@"l", @"type"), NSEqualToPredicateOperatorType, type),
		WFIdentityLinkMatches(@"l", identity) ]];
	NSExpression *matching = [NSExpression expressionForSubquery:[NSExpression expressionForKeyPath:linksKeyPath]
	                                       usingIteratorVariable:@"l"
	                                                   predicate:link];
	return WFIdentityCompare([NSExpression expressionForFunction:@"count:" arguments:@[ matching ]],
	                         NSGreaterThanPredicateOperatorType, @0);
}

void
WFSplitCandidate(NSString *entry, NSString **groupId, NSString **claimName, NSString **claimValue)
{
	NSRange colon = [entry rangeOfString:@":"];
	if (colon.location == NSNotFound || colon.location == 0 || NSMaxRange(colon) == [entry length]) {
		*groupId = entry;
		*claimName = nil;
		*claimValue = nil;
		return;
	}
	*groupId = nil;
	*claimName = [entry substringToIndex:colon.location];
	*claimValue = [entry substringFromIndex:NSMaxRange(colon)];
}

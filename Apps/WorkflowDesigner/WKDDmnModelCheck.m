#import "WKDDmnModelPriv.h"

static BOOL
WKDSame(id a, id b)
{
	return a == b || [a isEqual:b];
}

static NSString *
WKDColumnDifference(WKDDmnColumn *column, WKDDmnColumn *read)
{
	if (!WKDSame(column.columnId, read.columnId)) return @"id";
	if (column.output != read.output) return @"kind";
	if (!WKDSame(column.label, read.label)) return @"label";
	if (!WKDSame(column.typeRef, read.typeRef)) return @"type";
	if (!WKDSame(column.expression, read.expression)) return @"expression";
	if (!WKDSame(column.inputVariable, read.inputVariable)) return @"input variable";
	if (!WKDSame(column.name, read.name)) return @"name";
	return nil;
}

@implementation WKDDmnModel (WKDDmnChecking)

- (NSString *)disagreementWith:(WKDDmnModel *)other
{
	NSArray *ids = [self.decisionList valueForKey:@"decisionId"], *read = [other.decisionList valueForKey:@"decisionId"];
	if (!WKDSame(ids, read)) {
		return [NSString stringWithFormat:@"decisions %@, read afresh %@", ids, read];
	}
	for (WKDDmnDecision *decision in self.decisionList) {
		WKDDmnDecision *again = [other decisionWithId:decision.decisionId];
		NSString *differs = nil;
		if (!WKDSame(decision.name, again.name)) differs = @"name";
		else if (decision.table != again.table) differs = @"kind";
		else if (!WKDSame(decision.hitPolicy, again.hitPolicy)) differs = @"hit policy";
		else if (!WKDSame(decision.aggregation, again.aggregation)) differs = @"aggregation";
		else if (!WKDSame(decision.expression, again.expression)) differs = @"expression";
		else if (!WKDSame(decision.variableName, again.variableName)) differs = @"variable";
		else if (!WKDSame(decision.variableType, again.variableType)) differs = @"variable's type";
		else if (!WKDSame(decision.required, again.required)) {
			differs = [NSString stringWithFormat:@"requirements %@, read %@", decision.required, again.required];
		} else if ([decision.columns count] != [again.columns count]) differs = @"columns";
		else if ([decision.rules count] != [again.rules count]) differs = @"rules";
		for (NSUInteger i = 0; differs == nil && i < [decision.columns count]; i++) {
			NSString *column = WKDColumnDifference([decision.columns objectAtIndex:i], [again.columns objectAtIndex:i]);
			if (column != nil) {
				differs = [NSString stringWithFormat:@"column %lu's %@", (unsigned long)i, column];
			}
		}
		for (NSUInteger i = 0; differs == nil && i < [decision.rules count]; i++) {
			WKDDmnRule *rule = [decision.rules objectAtIndex:i], *ruleAgain = [again.rules objectAtIndex:i];
			if (!WKDSame(rule.ruleId, ruleAgain.ruleId)) {
				differs = [NSString stringWithFormat:@"rule %lu's id %@, read %@", (unsigned long)i, rule.ruleId,
					ruleAgain.ruleId];
			} else if (!WKDSame(rule.entries, ruleAgain.entries)) {
				differs = [NSString stringWithFormat:@"rule %@'s entries %@, read %@", rule.ruleId, rule.entries,
					ruleAgain.entries];
			} else if (!WKDSame(rule.annotation, ruleAgain.annotation)) {
				differs = [NSString stringWithFormat:@"rule %@'s annotation", rule.ruleId];
			}
		}
		if (differs != nil) {
			return [NSString stringWithFormat:@"decision %@: its %@", decision.decisionId, differs];
		}
	}
	return nil;
}

@end

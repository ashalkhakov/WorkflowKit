#import "WFTypes.h"

/*
 * Who is asking: a user, the groups they are in, and whatever else their
 * identity provider says of them (department, cost centre, ...), as an
 * API's sign-in hands them over. The engine keeps no users or groups of
 * its own; it matches these against what a process names:
 *
 *  - a task's assignee and candidate users, against the user;
 *  - its candidate groups, against the groups -- or, for an entry
 *    name:value (department:purchasing), against the claim of that name;
 *  - a process's candidate starters (camunda:candidateStarterUsers,
 *    camunda:candidateStarterGroups), the same way.
 *
 * Naming claims rather than groups keeps a process to what a person is
 * (in purchasing), not to an organization's group names, which change.
 */
@interface WFIdentity : NSObject
@property (nonatomic, readonly, copy) NSString *userId;
@property (nonatomic, readonly, copy) NSArray<NSString *> *groups;
/* By name: text, a number, or a list of them. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *claims;
+ (instancetype)identityWithUserId:(NSString *)userId
                            groups:(NSArray<NSString *> *)groups
                            claims:(NSDictionary<NSString *, id> *)claims;
- (instancetype)init NS_UNAVAILABLE;
/* A claim's values as text: one for a single value, each of a list's. */
- (NSArray<NSString *> *)valuesOfClaim:(NSString *)name;
@end

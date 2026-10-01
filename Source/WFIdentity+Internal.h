#import "WFIdentity.h"

/* An identity link (the iterator variable's) that the identity matches:
 * its user, one of its groups, or one of its claims' values. */
NSPredicate *WFIdentityLinkMatches(NSString *variable, WFIdentity *identity);
/* Some link of the type, among those the key path reaches, matches. */
NSPredicate *WFLinksMatch(NSString *linksKeyPath, NSString *type, WFIdentity *identity);
/* A candidate group entry: a group, or name:value, a claim to match. */
void WFSplitCandidate(NSString *entry, NSString **groupId, NSString **claimName, NSString **claimValue);

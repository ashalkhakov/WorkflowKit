#import "WFTestCase.h"

/* Every area's tests, with the engines' stores in memory. */

@interface WFInMemoryTestCase : WFTestCase
@end

@implementation WFInMemoryTestCase

/* A store that has to outlive its engine cannot be in memory: those are
 * SQLite files. */
- (WFStore *)storeAtURL:(NSURL *)url
{
	NSError *error = nil;
	WFStore *store = url == nil ? [WFStore inMemoryStore:&error] : [WFStore SQLiteStoreAtURL:url error:&error];
	XCTAssertNotNil(store, @"%@", error);
	return store;
}

@end

@interface WFGatewayInMemoryTests : WFInMemoryTestCase
@end

@implementation WFGatewayInMemoryTests
#include "WFGatewayTests.inc"
@end

@interface WFEventInMemoryTests : WFInMemoryTestCase
@end

@implementation WFEventInMemoryTests
#include "WFEventTests.inc"
@end

@interface WFSubprocessInMemoryTests : WFInMemoryTestCase
@end

@implementation WFSubprocessInMemoryTests
#include "WFSubprocessTests.inc"
@end

@interface WFCallActivityInMemoryTests : WFInMemoryTestCase
@end

@implementation WFCallActivityInMemoryTests
#include "WFCallActivityTests.inc"
@end

@interface WFExternalTaskInMemoryTests : WFInMemoryTestCase
@end

@implementation WFExternalTaskInMemoryTests
#include "WFExternalTaskTests.inc"
@end

@interface WFJobInMemoryTests : WFInMemoryTestCase
@end

@implementation WFJobInMemoryTests
#include "WFJobTests.inc"
@end

@interface WFHistoryInMemoryTests : WFInMemoryTestCase
@end

@implementation WFHistoryInMemoryTests
#include "WFHistoryTests.inc"
@end

@interface WFDeploymentInMemoryTests : WFInMemoryTestCase
@end

@implementation WFDeploymentInMemoryTests
#include "WFDeploymentTests.inc"
@end

@interface WFDurabilityInMemoryTests : WFInMemoryTestCase
@end

@implementation WFDurabilityInMemoryTests
#include "WFDurabilityTests.inc"
@end

@interface WFBpmnInMemoryTests : WFInMemoryTestCase
@end

@implementation WFBpmnInMemoryTests
#include "WFBpmnTests.inc"
@end

@interface WFMultiInstanceInMemoryTests : WFInMemoryTestCase
@end

@implementation WFMultiInstanceInMemoryTests
#include "WFMultiInstanceTests.inc"
@end

@interface WFEventSubProcessInMemoryTests : WFInMemoryTestCase
@end

@implementation WFEventSubProcessInMemoryTests
#include "WFEventSubProcessTests.inc"
@end

@interface WFTimerInMemoryTests : WFInMemoryTestCase
@end

@implementation WFTimerInMemoryTests
#include "WFTimerTests.inc"
@end

@interface WFEscalationInMemoryTests : WFInMemoryTestCase
@end

@implementation WFEscalationInMemoryTests
#include "WFEscalationTests.inc"
@end

@interface WFCompensationInMemoryTests : WFInMemoryTestCase
@end

@implementation WFCompensationInMemoryTests
#include "WFCompensationTests.inc"
@end

@interface WFOperationsInMemoryTests : WFInMemoryTestCase
@end

@implementation WFOperationsInMemoryTests
#include "WFOperationsTests.inc"
@end

@interface WFTaskAssignmentInMemoryTests : WFInMemoryTestCase
@end

@implementation WFTaskAssignmentInMemoryTests
#include "WFTaskAssignmentTests.inc"
@end

@interface WFInputOutputInMemoryTests : WFInMemoryTestCase
@end

@implementation WFInputOutputInMemoryTests
#include "WFInputOutputTests.inc"
@end

@interface WFTaskKindsInMemoryTests : WFInMemoryTestCase
@end

@implementation WFTaskKindsInMemoryTests
#include "WFTaskKindsTests.inc"
@end

@interface WFLinkEventInMemoryTests : WFInMemoryTestCase
@end

@implementation WFLinkEventInMemoryTests
#include "WFLinkEventTests.inc"
@end

@interface WFConditionalEventInMemoryTests : WFInMemoryTestCase
@end

@implementation WFConditionalEventInMemoryTests
#include "WFConditionalEventTests.inc"
@end

@interface WFDecisionInMemoryTests : WFInMemoryTestCase
@end

@implementation WFDecisionInMemoryTests
#include "WFDecisionTests.inc"
@end

@interface WFModificationInMemoryTests : WFInMemoryTestCase
@end

@implementation WFModificationInMemoryTests
#include "WFModificationTests.inc"
@end

@interface WFMigrationInMemoryTests : WFInMemoryTestCase
@end

@implementation WFMigrationInMemoryTests
#include "WFMigrationTests.inc"
@end

@interface WFDelegationInMemoryTests : WFInMemoryTestCase
@end

@implementation WFDelegationInMemoryTests
#include "WFDelegationTests.inc"
@end

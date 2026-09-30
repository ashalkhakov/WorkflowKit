#import "WFTestCase.h"

/* Every area's tests, with the engines' stores in SQLite files. */

@interface WFSQLiteTestCase : WFTestCase
@end

@implementation WFSQLiteTestCase

- (WFStore *)storeAtURL:(NSURL *)url
{
	NSError *error = nil;
	WFStore *store = [WFStore SQLiteStoreAtURL:(url ?: [self temporaryStoreURL]) error:&error];
	XCTAssertNotNil(store, @"%@", error);
	return store;
}

@end

@interface WFGatewaySQLiteTests : WFSQLiteTestCase
@end

@implementation WFGatewaySQLiteTests
#include "WFGatewayTests.inc"
@end

@interface WFEventSQLiteTests : WFSQLiteTestCase
@end

@implementation WFEventSQLiteTests
#include "WFEventTests.inc"
@end

@interface WFSubprocessSQLiteTests : WFSQLiteTestCase
@end

@implementation WFSubprocessSQLiteTests
#include "WFSubprocessTests.inc"
@end

@interface WFCallActivitySQLiteTests : WFSQLiteTestCase
@end

@implementation WFCallActivitySQLiteTests
#include "WFCallActivityTests.inc"
@end

@interface WFExternalTaskSQLiteTests : WFSQLiteTestCase
@end

@implementation WFExternalTaskSQLiteTests
#include "WFExternalTaskTests.inc"
@end

@interface WFJobSQLiteTests : WFSQLiteTestCase
@end

@implementation WFJobSQLiteTests
#include "WFJobTests.inc"
@end

@interface WFHistorySQLiteTests : WFSQLiteTestCase
@end

@implementation WFHistorySQLiteTests
#include "WFHistoryTests.inc"
@end

@interface WFDeploymentSQLiteTests : WFSQLiteTestCase
@end

@implementation WFDeploymentSQLiteTests
#include "WFDeploymentTests.inc"
@end

@interface WFDurabilitySQLiteTests : WFSQLiteTestCase
@end

@implementation WFDurabilitySQLiteTests
#include "WFDurabilityTests.inc"
@end

@interface WFBpmnSQLiteTests : WFSQLiteTestCase
@end

@implementation WFBpmnSQLiteTests
#include "WFBpmnTests.inc"
@end

@interface WFMultiInstanceSQLiteTests : WFSQLiteTestCase
@end

@implementation WFMultiInstanceSQLiteTests
#include "WFMultiInstanceTests.inc"
@end

@interface WFEventSubProcessSQLiteTests : WFSQLiteTestCase
@end

@implementation WFEventSubProcessSQLiteTests
#include "WFEventSubProcessTests.inc"
@end

@interface WFTimerSQLiteTests : WFSQLiteTestCase
@end

@implementation WFTimerSQLiteTests
#include "WFTimerTests.inc"
@end

@interface WFEscalationSQLiteTests : WFSQLiteTestCase
@end

@implementation WFEscalationSQLiteTests
#include "WFEscalationTests.inc"
@end

@interface WFCompensationSQLiteTests : WFSQLiteTestCase
@end

@implementation WFCompensationSQLiteTests
#include "WFCompensationTests.inc"
@end

@interface WFOperationsSQLiteTests : WFSQLiteTestCase
@end

@implementation WFOperationsSQLiteTests
#include "WFOperationsTests.inc"
@end

@interface WFTaskAssignmentSQLiteTests : WFSQLiteTestCase
@end

@implementation WFTaskAssignmentSQLiteTests
#include "WFTaskAssignmentTests.inc"
@end

@interface WFInputOutputSQLiteTests : WFSQLiteTestCase
@end

@implementation WFInputOutputSQLiteTests
#include "WFInputOutputTests.inc"
@end

@interface WFTaskKindsSQLiteTests : WFSQLiteTestCase
@end

@implementation WFTaskKindsSQLiteTests
#include "WFTaskKindsTests.inc"
@end

@interface WFLinkEventSQLiteTests : WFSQLiteTestCase
@end

@implementation WFLinkEventSQLiteTests
#include "WFLinkEventTests.inc"
@end

@interface WFConditionalEventSQLiteTests : WFSQLiteTestCase
@end

@implementation WFConditionalEventSQLiteTests
#include "WFConditionalEventTests.inc"
@end

@interface WFDecisionSQLiteTests : WFSQLiteTestCase
@end

@implementation WFDecisionSQLiteTests
#include "WFDecisionTests.inc"
@end

@interface WFModificationSQLiteTests : WFSQLiteTestCase
@end

@implementation WFModificationSQLiteTests
#include "WFModificationTests.inc"
@end

@interface WFMigrationSQLiteTests : WFSQLiteTestCase
@end

@implementation WFMigrationSQLiteTests
#include "WFMigrationTests.inc"
@end

@interface WFDelegationSQLiteTests : WFSQLiteTestCase
@end

@implementation WFDelegationSQLiteTests
#include "WFDelegationTests.inc"
@end

@interface WFTaskQuerySQLiteTests : WFSQLiteTestCase
@end

@implementation WFTaskQuerySQLiteTests
#include "WFTaskQueryTests.inc"
@end

#ifdef WORKFLOWKIT_ODATA
@interface WFODataSQLiteTests : WFSQLiteTestCase
@end

@implementation WFODataSQLiteTests
#include "WFODataTests.inc"
@end
#endif

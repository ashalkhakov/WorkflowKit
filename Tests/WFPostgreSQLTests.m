#import "WFTestCase.h"
#import <CDPostgreSQLStore/CDPostgreSQLStore.h>

/* Every area's tests, with the engines' stores on PostgreSQL through
 * FreeCoreData's CDPostgreSQLStore. Built only when
 * WORKFLOWKIT_TEST_POSTGRES_URL names a database (see the GNUmakefile). */

@interface WFPostgreSQLTestCase : WFServerTestCase
@end

@implementation WFPostgreSQLTestCase

- (Class)storeClass                      { return [CDPostgreSQLStore class]; }
- (NSString *)storeType                  { return CDPostgreSQLStoreType; }
- (NSString *)schemaNameOptionKey        { return CDPostgreSQLSchemaNameOption; }
- (NSString *)URLEnvironmentVariableName { return @"WORKFLOWKIT_TEST_POSTGRES_URL"; }

@end

@interface WFGatewayPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFGatewayPostgreSQLTests
#include "WFGatewayTests.inc"
@end

@interface WFEventPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFEventPostgreSQLTests
#include "WFEventTests.inc"
@end

@interface WFSubprocessPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFSubprocessPostgreSQLTests
#include "WFSubprocessTests.inc"
@end

@interface WFCallActivityPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFCallActivityPostgreSQLTests
#include "WFCallActivityTests.inc"
@end

@interface WFExternalTaskPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFExternalTaskPostgreSQLTests
#include "WFExternalTaskTests.inc"
@end

@interface WFJobPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFJobPostgreSQLTests
#include "WFJobTests.inc"
@end

@interface WFTracingPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFTracingPostgreSQLTests
#include "WFTracingTests.inc"
@end

@interface WFExamplesPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFExamplesPostgreSQLTests
#include "WFExamplesTests.inc"
@end

@interface WFHistoryPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFHistoryPostgreSQLTests
#include "WFHistoryTests.inc"
@end

@interface WFDeploymentPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFDeploymentPostgreSQLTests
#include "WFDeploymentTests.inc"
@end

@interface WFDurabilityPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFDurabilityPostgreSQLTests
#include "WFDurabilityTests.inc"
@end

@interface WFBpmnPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFBpmnPostgreSQLTests
#include "WFBpmnTests.inc"
@end

@interface WFMultiInstancePostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFMultiInstancePostgreSQLTests
#include "WFMultiInstanceTests.inc"
@end

@interface WFEventSubProcessPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFEventSubProcessPostgreSQLTests
#include "WFEventSubProcessTests.inc"
@end

@interface WFTimerPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFTimerPostgreSQLTests
#include "WFTimerTests.inc"
@end

@interface WFEscalationPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFEscalationPostgreSQLTests
#include "WFEscalationTests.inc"
@end

@interface WFCompensationPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFCompensationPostgreSQLTests
#include "WFCompensationTests.inc"
@end

@interface WFOperationsPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFOperationsPostgreSQLTests
#include "WFOperationsTests.inc"
@end

@interface WFTaskAssignmentPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFTaskAssignmentPostgreSQLTests
#include "WFTaskAssignmentTests.inc"
@end

@interface WFInputOutputPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFInputOutputPostgreSQLTests
#include "WFInputOutputTests.inc"
@end

@interface WFTaskKindsPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFTaskKindsPostgreSQLTests
#include "WFTaskKindsTests.inc"
@end

@interface WFLinkEventPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFLinkEventPostgreSQLTests
#include "WFLinkEventTests.inc"
@end

@interface WFConditionalEventPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFConditionalEventPostgreSQLTests
#include "WFConditionalEventTests.inc"
@end

@interface WFDecisionPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFDecisionPostgreSQLTests
#include "WFDecisionTests.inc"
@end

@interface WFModificationPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFModificationPostgreSQLTests
#include "WFModificationTests.inc"
@end

@interface WFMigrationPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFMigrationPostgreSQLTests
#include "WFMigrationTests.inc"
@end

@interface WFDelegationPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFDelegationPostgreSQLTests
#include "WFDelegationTests.inc"
@end

@interface WFTaskQueryPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFTaskQueryPostgreSQLTests
#include "WFTaskQueryTests.inc"
@end

@interface WFFormPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFFormPostgreSQLTests
#include "WFFormTests.inc"
@end

#ifdef WORKFLOWKIT_ODATA
@interface WFODataPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFODataPostgreSQLTests
#include "WFODataTests.inc"
@end

@interface WFODataExternalTasksPostgreSQLTests : WFPostgreSQLTestCase
@end

@implementation WFODataExternalTasksPostgreSQLTests
#include "WFODataExternalTasksTests.inc"
@end
#endif

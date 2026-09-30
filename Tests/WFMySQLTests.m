#import "WFTestCase.h"
#import <CDMySQLStore/CDMySQLStore.h>

/* Every area's tests, with the engines' stores on MySQL or MariaDB through
 * FreeCoreData's CDMySQLStore. Built only when WORKFLOWKIT_TEST_MYSQL_URL
 * names a database (see the GNUmakefile). */

@interface WFMySQLTestCase : WFServerTestCase
@end

@implementation WFMySQLTestCase

- (Class)storeClass                      { return [CDMySQLStore class]; }
- (NSString *)storeType                  { return CDMySQLStoreType; }
- (NSString *)schemaNameOptionKey        { return CDMySQLSchemaNameOption; }
- (NSString *)URLEnvironmentVariableName { return @"WORKFLOWKIT_TEST_MYSQL_URL"; }

@end

@interface WFGatewayMySQLTests : WFMySQLTestCase
@end

@implementation WFGatewayMySQLTests
#include "WFGatewayTests.inc"
@end

@interface WFEventMySQLTests : WFMySQLTestCase
@end

@implementation WFEventMySQLTests
#include "WFEventTests.inc"
@end

@interface WFSubprocessMySQLTests : WFMySQLTestCase
@end

@implementation WFSubprocessMySQLTests
#include "WFSubprocessTests.inc"
@end

@interface WFCallActivityMySQLTests : WFMySQLTestCase
@end

@implementation WFCallActivityMySQLTests
#include "WFCallActivityTests.inc"
@end

@interface WFExternalTaskMySQLTests : WFMySQLTestCase
@end

@implementation WFExternalTaskMySQLTests
#include "WFExternalTaskTests.inc"
@end

@interface WFJobMySQLTests : WFMySQLTestCase
@end

@implementation WFJobMySQLTests
#include "WFJobTests.inc"
@end

@interface WFHistoryMySQLTests : WFMySQLTestCase
@end

@implementation WFHistoryMySQLTests
#include "WFHistoryTests.inc"
@end

@interface WFDeploymentMySQLTests : WFMySQLTestCase
@end

@implementation WFDeploymentMySQLTests
#include "WFDeploymentTests.inc"
@end

@interface WFDurabilityMySQLTests : WFMySQLTestCase
@end

@implementation WFDurabilityMySQLTests
#include "WFDurabilityTests.inc"
@end

@interface WFBpmnMySQLTests : WFMySQLTestCase
@end

@implementation WFBpmnMySQLTests
#include "WFBpmnTests.inc"
@end

@interface WFMultiInstanceMySQLTests : WFMySQLTestCase
@end

@implementation WFMultiInstanceMySQLTests
#include "WFMultiInstanceTests.inc"
@end

@interface WFEventSubProcessMySQLTests : WFMySQLTestCase
@end

@implementation WFEventSubProcessMySQLTests
#include "WFEventSubProcessTests.inc"
@end

@interface WFTimerMySQLTests : WFMySQLTestCase
@end

@implementation WFTimerMySQLTests
#include "WFTimerTests.inc"
@end

@interface WFEscalationMySQLTests : WFMySQLTestCase
@end

@implementation WFEscalationMySQLTests
#include "WFEscalationTests.inc"
@end

@interface WFCompensationMySQLTests : WFMySQLTestCase
@end

@implementation WFCompensationMySQLTests
#include "WFCompensationTests.inc"
@end

@interface WFOperationsMySQLTests : WFMySQLTestCase
@end

@implementation WFOperationsMySQLTests
#include "WFOperationsTests.inc"
@end

@interface WFTaskAssignmentMySQLTests : WFMySQLTestCase
@end

@implementation WFTaskAssignmentMySQLTests
#include "WFTaskAssignmentTests.inc"
@end

@interface WFInputOutputMySQLTests : WFMySQLTestCase
@end

@implementation WFInputOutputMySQLTests
#include "WFInputOutputTests.inc"
@end

@interface WFTaskKindsMySQLTests : WFMySQLTestCase
@end

@implementation WFTaskKindsMySQLTests
#include "WFTaskKindsTests.inc"
@end

@interface WFLinkEventMySQLTests : WFMySQLTestCase
@end

@implementation WFLinkEventMySQLTests
#include "WFLinkEventTests.inc"
@end

@interface WFConditionalEventMySQLTests : WFMySQLTestCase
@end

@implementation WFConditionalEventMySQLTests
#include "WFConditionalEventTests.inc"
@end

@interface WFDecisionMySQLTests : WFMySQLTestCase
@end

@implementation WFDecisionMySQLTests
#include "WFDecisionTests.inc"
@end

@interface WFModificationMySQLTests : WFMySQLTestCase
@end

@implementation WFModificationMySQLTests
#include "WFModificationTests.inc"
@end

@interface WFMigrationMySQLTests : WFMySQLTestCase
@end

@implementation WFMigrationMySQLTests
#include "WFMigrationTests.inc"
@end

@interface WFDelegationMySQLTests : WFMySQLTestCase
@end

@implementation WFDelegationMySQLTests
#include "WFDelegationTests.inc"
@end

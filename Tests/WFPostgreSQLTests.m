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

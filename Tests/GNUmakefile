# The XCTest suite, run by tools-xctest.
#
#   make -C Tests run-tests     (or `make test` from the top)
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = WorkflowKitTests

WorkflowKitTests_OBJC_FILES = \
	WFTestCase.m \
	WFGatewayTests.m \
	WFEventTests.m \
	WFSubprocessTests.m \
	WFCallActivityTests.m \
	WFExternalTaskTests.m \
	WFJobTests.m \
	WFHistoryTests.m \
	WFDeploymentTests.m \
	WFDurabilityTests.m \
	WFBpmnTests.m \
	WFFeelTests.m \
	WFMultiInstanceTests.m \
	WFEventSubProcessTests.m \
	WFTimerTests.m \
	WFEscalationTests.m \
	WFCompensationTests.m \
	WFOperationsTests.m \
	WFTaskAssignmentTests.m \
	WFInputOutputTests.m
WorkflowKitTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
WorkflowKitTests_INCLUDE_DIRS = -I../Headers
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR)
WorkflowKitTests_BUNDLE_LIBS += -lWorkflowKit -lCoreData -lXCTest -ldispatch
WorkflowKitTests_XCDATAMODELD_FILES = ../Model/WorkflowKit.xcdatamodeld
WorkflowKitTests_NEEDS_GUI = no
WorkflowKitTests_PRINCIPAL_CLASS = WFTestCase

include $(GNUSTEP_MAKEFILES)/coredata-model.make
include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

# Bounded: a test waiting on an instance that never settles would otherwise
# hang the job until CI kills it, saying nothing about which test it was in.
TEST_TIMEOUT ?= 300

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(CURDIR)/../$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle

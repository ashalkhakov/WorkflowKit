# The XCTest suite, run by tools-xctest.
#
#   make -C Tests run-tests     (or `make test` from the top)
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = UDWorkflowTests

UDWorkflowTests_OBJC_FILES = UDWorkflowTests.m
UDWorkflowTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
UDWorkflowTests_INCLUDE_DIRS = -I../Headers
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR)
UDWorkflowTests_BUNDLE_LIBS += -lUDWorkflow -lXCTest -ldispatch
UDWorkflowTests_NEEDS_GUI = no
UDWorkflowTests_PRINCIPAL_CLASS = UDWorkflowTests

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

# Bounded: the engine's synchronous entry points wait on semaphores, and a
# token that never quiesces would otherwise hang the job until CI kills it,
# saying nothing about which test it was in.
TEST_TIMEOUT ?= 300

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(CURDIR)/../$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle

# WorkflowDesk's tests: what it does without a window -- signing in with
# OpenID Connect through a loopback redirect, and putting a task's instance
# into its form. Run with `make check` one level up.
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = WorkflowDeskTests

WorkflowDeskTests_OBJC_FILES = \
	../WDFormDocument.m \
	../WDSignIn.m \
	WDFormDocumentTests.m \
	WDSignInTests.m

WorkflowDeskTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
WorkflowDeskTests_INCLUDE_DIRS = -I.. \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataIncrementalStore/include
ADDITIONAL_LIB_DIRS += -L$(ODATAKIT)/obj
WorkflowDeskTests_BUNDLE_LIBS += -lODataKit -lXCTest -ldispatch -lgnutls
WorkflowDeskTests_NEEDS_GUI = no

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 120

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(ODATAKIT)/obj:$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle

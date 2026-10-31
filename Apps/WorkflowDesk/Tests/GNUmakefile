# WorkflowDesk's tests: what it does without a window -- signing in with
# OpenID Connect through a loopback redirect, and putting a task's instance
# into its form. Run with `make check` one level up.
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = WorkflowDeskTests

WorkflowDeskTests_OBJC_FILES = \
	../WDFormDocument.m \
	../../Shared/WDSignIn.m \
	../../Shared/WDSockets-posix.m \
	WDFormDocumentTests.m \
	WDSignInTests.m

WorkflowDeskTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
WorkflowDeskTests_INCLUDE_DIRS = -I.. -I../../Shared
ifneq ($(ODATAKIT),)
WorkflowDeskTests_INCLUDE_DIRS += \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataIncrementalStore/include
ADDITIONAL_LIB_DIRS += -L$(ODATAKIT)/obj
ODATAKIT_LIBRARY_PATH = $(ODATAKIT)/obj:
endif
WorkflowDeskTests_BUNDLE_LIBS += -lODataKit -lXCTest -ldispatch -lgnutls
WorkflowDeskTests_NEEDS_GUI = no

# Sockets for signing in (../Shared/WDSockets.h): Winsock's on Windows.
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
WorkflowDeskTests_OBJC_FILES := $(subst WDSockets-posix.m,WDSockets-windows.m,$(WorkflowDeskTests_OBJC_FILES))
WorkflowDeskTests_BUNDLE_LIBS += -lws2_32
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 120

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(ODATAKIT_LIBRARY_PATH)$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle

# The XCTest suite, run by tools-xctest.
#
#   make -C Tests run-tests     (or `make test` from the top)
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = WorkflowKitTests

# One class per area and backend: the areas' tests are in WF*Tests.inc,
# included by each backend's file (see WFTestCase.h).
WorkflowKitTests_OBJC_FILES = \
	WFTestCase.m \
	../Examples/Plugins/WFExampleDelegates.m \
	WFFeelTests.m \
	WFExpressionTextTests.m \
	WFDmnTests.m \
	WFInMemoryTests.m \
	WFSQLiteTests.m

# The database servers, each tested when its URL is given, through the
# FreeCoreData store installed for it (make -C Backends/PostgreSQL install,
# or MySQL). Each test works in a schema of its own, dropped afterwards.
#
#   make test WORKFLOWKIT_TEST_POSTGRES_URL=postgresql://user:secret@host/db \
#             WORKFLOWKIT_TEST_MYSQL_URL=mysql://user:secret@host/db
#
# The classes are compiled in or left out by the URL, so after changing
# which are given, make clean first.
export WORKFLOWKIT_TEST_POSTGRES_URL WORKFLOWKIT_TEST_MYSQL_URL
ifneq ($(WORKFLOWKIT_TEST_POSTGRES_URL),)
WorkflowKitTests_OBJC_FILES += WFPostgreSQLTests.m
WorkflowKitTests_BUNDLE_LIBS += -lCDPostgreSQLStore
endif
ifneq ($(WORKFLOWKIT_TEST_MYSQL_URL),)
WorkflowKitTests_OBJC_FILES += WFMySQLTests.m
WorkflowKitTests_BUNDLE_LIBS += -lCDMySQLStore
endif
ifneq ($(WORKFLOWKIT_TEST_POSTGRES_URL)$(WORKFLOWKIT_TEST_MYSQL_URL),)
WorkflowKitTests_BUNDLE_LIBS += -lCDSQLStore
endif
# The OData API's tests, where it is built (make test ODATAKIT=...).
ifeq ($(odata),yes)
WorkflowKitTests_OBJCFLAGS += -DWORKFLOWKIT_ODATA=1
WorkflowKitTests_BUNDLE_LIBS += -lWorkflowKitOData -lODataService -lHTTPServerKit -lOTelKit -lODataKit
ifneq ($(ODATAKIT),)
WorkflowKitTests_INCLUDE_DIRS += -I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataService/include \
	-I$(ODATAKIT)/Source/HTTPServerKit/include -I$(ODATAKIT)/Source/OTelKit/include
ADDITIONAL_LIB_DIRS += -L$(ODATAKIT)/obj
ODATAKIT_LIBRARY_PATH = $(ODATAKIT)/obj:
endif
WorkflowKitTests_INCLUDE_DIRS += -I../OData
endif
WorkflowKitTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
WorkflowKitTests_INCLUDE_DIRS += -I../Headers -I../Examples/Plugins
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
	LD_LIBRARY_PATH="$(CURDIR)/../$(GNUSTEP_OBJ_DIR):$(ODATAKIT_LIBRARY_PATH)$$LD_LIBRARY_PATH" \
	PATH="$(CURDIR)/../$(GNUSTEP_OBJ_DIR):$(ODATAKIT_LIBRARY_PATH)$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle

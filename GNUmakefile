# WorkflowKit on GNUstep.
#
#   make                 the library, obj/libWorkflowKit.so; with ODataKit
#                        installed (or ODATAKIT, below) its OData API,
#                        wf-serve (Server/) and the apps (Apps/) too
#   make check           the XCTest suite, on every store there is a server
#                        for; wf-serve over HTTP; the apps' tests; the demo
#   make install         the library, and wf-serve and the apps
#   make examples        the demo tools in Examples/
#   make test            the library, then the XCTest suite (tools-xctest)
#
# Built against the patched GNUstep stack and the releases of FreeCoreData,
# ODataKit and XFormsKit that .github/pins.env names, which
# gnustep-release-actions' scripts/deps.sh unpacks into /opt/gnustep (CI,
# .github/workflows/build.yml); see CLAUDE.md for the docker box.
#
# A library rather than a framework, like RDLKit: on GNUstep a framework puts
# its binary under WorkflowKit.framework/Versions/<v>/<target>/, which every
# tool and test bundle in the tree then has to name to link against it.
include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = WorkflowKit

WorkflowKit_OBJC_FILES = \
	Source/WFFlowElements.m \
	Source/WFFeelLexer.m \
	Source/WFFeelParser.m \
	Source/WFFeelHighlight.m \
	Source/WFFeelEvaluator.m \
	Source/WFFeelFunctions.m \
	Source/WFFeelTemporal.m \
	Source/WFFeel.m \
	Source/WFTimers.m \
	Source/WFProcessDefinition.m \
	Source/WFHandlers.m \
	Source/WFStore.m \
	Source/WFRepositoryService.m \
	Source/WFDuration.m \
	Source/WFBpmn.m \
	Source/WFDmn.m \
	Source/WFEntities.m \
	Source/WFCommandContext.m \
	Source/WFServices.m \
	Source/WFTaskQuery.m \
	Source/WFIdentity.m \
	Source/WFForm.m \
	Source/WFFormService.m \
	Source/WFExternalTaskService.m \
	Source/WFProcessEngine.m

WorkflowKit_HEADER_FILES_DIR = Headers
WorkflowKit_HEADER_FILES_INSTALL_DIR = WorkflowKit
WorkflowKit_HEADER_FILES = \
	WFTypes.h \
	WFCondition.h \
	WFFeel.h \
	WFDelegation.h \
	WFFlowElements.h \
	WFProcessDefinition.h \
	WFDecision.h \
	WFHandlers.h \
	WFStore.h \
	WFRepositoryService.h \
	WFRuntimeService.h \
	WFIdentity.h \
	WFTaskQuery.h \
	WFForm.h \
	WFFormService.h \
	WFTaskService.h \
	WFHistoryService.h \
	WFManagementService.h \
	WFExternalTaskService.h \
	WFDecisionService.h \
	WFProcessEngine.h \
	WFBpmn.h \
	WorkflowKit.h

WorkflowKit_INCLUDE_DIRS = -IHeaders -ISource
WorkflowKit_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=objc-method-access
WorkflowKit_LIBRARIES_DEPEND_UPON += -lCoreData -ldispatch $(FND_LIBS) $(OBJC_LIBS)

# The store's Core Data model, compiled by FreeCoreData's momc into
# WorkflowKit.momd and installed in the library's resource bundle, where
# +[NSBundle bundleForClass:] finds it. Uninstalled, the test bundle and
# the examples carry their own copy.
WorkflowKit_XCDATAMODELD_FILES = Model/WorkflowKit.xcdatamodeld
# Its entities' classes too, generated from the model as it builds
# (obj/CoreDataGenerated/WorkflowKit): Source/WFEntities.h imports them.
WorkflowKit_COREDATA_CODEGEN = yes
WorkflowKit_HAS_RESOURCE_BUNDLE = yes

# The OData API (OData/, WorkflowKitOData) over ODataKit's server, and the
# engine's HTTP server (WFServerApplication) over its HTTPServerKit, built
# when ODATAKIT names a built ODataKit checkout, or with odata=yes against
# an installed ODataKit:
#
#   make ODATAKIT=../ODataStore      (after make in ../ODataStore)
#   make test ODATAKIT=../ODataStore
#
# An installed ODataKit (its ODataService headers) builds them as well.
ifneq ($(ODATAKIT),)
override ODATAKIT := $(abspath $(ODATAKIT))
odata = yes
endif
ifeq ($(odata),)
ifneq ($(wildcard $(GNUSTEP_LOCAL_HEADERS)/ODataService $(GNUSTEP_SYSTEM_HEADERS)/ODataService),)
odata = yes
endif
endif
export ODATAKIT odata
ifeq ($(odata),yes)
LIBRARY_NAME += WorkflowKitOData
WorkflowKitOData_OBJC_FILES = \
	OData/WFODataService.m \
	OData/WFODataOperations.m \
	OData/WFODataServer.m
WorkflowKitOData_HEADER_FILES_DIR = OData
WorkflowKitOData_HEADER_FILES_INSTALL_DIR = WorkflowKitOData
WorkflowKitOData_HEADER_FILES = WFODataService.h WFODataServer.h
ifneq ($(ODATAKIT),)
WorkflowKitOData_INCLUDE_DIRS = -I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataService/include \
	-I$(ODATAKIT)/Source/HTTPServerKit/include -I$(ODATAKIT)/Source/OTelKit/include
WorkflowKitOData_LIB_DIRS = -L$(ODATAKIT)/obj
endif
WorkflowKitOData_INCLUDE_DIRS += -IHeaders -ISource -IOData -I$(GNUSTEP_OBJ_DIR)/CoreDataGenerated/WorkflowKit
WorkflowKitOData_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)
WorkflowKitOData_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=objc-method-access
WorkflowKitOData_LIBRARIES_DEPEND_UPON += -lWorkflowKit -lODataService -lHTTPServerKit -lOTelKit -lODataKit \
	-lCoreData -ldispatch \
	$(FND_LIBS) $(OBJC_LIBS)
endif

include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/library.make

# WorkflowKitOData links WorkflowKit: under make -j it waits for it, which
# gnustep-make would otherwise build alongside.
ifeq ($(odata),yes)
WorkflowKitOData.all.library.variables: WorkflowKit.all.library.variables
endif

# wf-serve with FreeCoreData's PostgreSQL and MySQL stores, where they are
# installed (FREECOREDATA_PARTS in .github/pins.env).
ifneq ($(wildcard $(GNUSTEP_LOCAL_LIBRARIES)/libCDPostgreSQLStore*),)
postgresql ?= yes
endif
ifneq ($(wildcard $(GNUSTEP_LOCAL_LIBRARIES)/libCDMySQLStore*),)
mysql ?= yes
endif
export postgresql mysql

# The tests' databases: gnustep-release-actions' databases.sh names its
# servers POSTGRES_URL and MYSQL_URL.
export WORKFLOWKIT_TEST_POSTGRES_URL ?= $(POSTGRES_URL)
export WORKFLOWKIT_TEST_MYSQL_URL ?= $(MYSQL_URL)

# wf-serve and the apps, over the OData API.
WF_PARTS = $(if $(filter yes,$(odata)),Server Apps/WorkflowDesk Apps/WorkflowDesigner)

after-all::
	@for part in $(WF_PARTS); do $(MAKE) -C $$part || exit 1; done

after-install::
	@for part in $(WF_PARTS); do $(MAKE) -C $$part install || exit 1; done

after-clean::
	@for part in $(WF_PARTS) Tests Examples Examples/Plugins; do $(MAKE) -C $$part clean || exit 1; done

check:: all
	$(MAKE) -C Tests run-tests
	$(MAKE) examples
ifeq ($(odata),yes)
	$(MAKE) -C Examples/Plugins
	$(MAKE) -C Server check
	$(MAKE) -C Apps/WorkflowDesk check
	$(MAKE) -C Apps/WorkflowDesigner check
	$(MAKE) -C Apps/WorkflowDesigner/Tools
endif
	timeout 120 $(MAKE) -C Examples run

.PHONY: examples test server
examples: all
	$(MAKE) -C Examples

# wf-serve (Server/), with the OData API.
server: all
	$(MAKE) -C Server

test: all
	$(MAKE) -C Tests run-tests

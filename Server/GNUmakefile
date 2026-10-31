# wf-serve: the engine served over HTTP, WorkflowKitOData's
# WFServerApplication (see OData/WFODataServer.h for its settings). Built
# against ODataKit, whose HTTPServerKit serves it: installed (the release
# .github/pins.env names), or a built checkout that ODATAKIT names:
#
#   make server                                      # here, from the top
#   make ODATAKIT=$ODATAKIT && make server           # against a checkout
#   make -C Server check                             # a purchase request, over HTTP
#
# FreeCoreData's PostgreSQL and MySQL stores are built in with
# postgresql=yes and mysql=yes.
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = wf-serve
wf-serve_OBJC_FILES = wf-serve.m
wf-serve_OBJCFLAGS += -fobjc-arc -fblocks -Wall
wf-serve_INCLUDE_DIRS = -I../Headers -I../OData
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR)
ifneq ($(ODATAKIT),)
wf-serve_INCLUDE_DIRS += \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataService/include \
	-I$(ODATAKIT)/Source/HTTPServerKit/include -I$(ODATAKIT)/Source/OTelKit/include
ADDITIONAL_LIB_DIRS += -L$(ODATAKIT)/obj
ODATAKIT_LIBRARY_PATH = $(ODATAKIT)/obj:
endif
wf-serve_TOOL_LIBS += -lWorkflowKitOData -lWorkflowKit -lODataService -lHTTPServerKit -lOTelKit -lODataKit \
	-lCoreData
ifeq ($(postgresql),yes)
wf-serve_OBJCFLAGS += -DWF_SERVE_POSTGRESQL=1
wf-serve_TOOL_LIBS += -lCDPostgreSQLStore -lCDSQLStore
endif
ifeq ($(mysql),yes)
wf-serve_OBJCFLAGS += -DWF_SERVE_MYSQL=1
wf-serve_TOOL_LIBS += -lCDMySQLStore -lCDSQLStore
endif

include $(GNUSTEP_MAKEFILES)/tool.make

# The uninstalled libraries (on LD_LIBRARY_PATH, and on Windows on PATH),
# and the model the library build compiled.
export LD_LIBRARY_PATH := $(CURDIR)/../$(GNUSTEP_OBJ_DIR):$(ODATAKIT_LIBRARY_PATH)$(LD_LIBRARY_PATH)
export PATH := $(CURDIR)/../$(GNUSTEP_OBJ_DIR):$(ODATAKIT_LIBRARY_PATH)$(PATH)
export WORKFLOWKIT_MODEL ?= $(CURDIR)/../WorkflowKit/Versions/0/Resources/WorkflowKit.momd

.PHONY: run check
# The example processes' delegates and form handlers first: the example
# configuration loads them.
run: all
	$(MAKE) -C ../Examples/Plugins
	$(GNUSTEP_OBJ_DIR)/wf-serve -Config Examples/server.plist

check:: all
	./check.sh $(GNUSTEP_OBJ_DIR)/wf-serve

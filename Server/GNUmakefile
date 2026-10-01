# wf-serve: the engine served over HTTP, WorkflowKitOData's
# WFServerApplication (see OData/WFODataServer.h for its settings). Built
# against ODataKit, whose HTTPServerKit serves it:
#
#   make -C $ODATAKIT                                # ODataKit's libraries
#   make ODATAKIT=$ODATAKIT && make server           # here, from the top
#   make -C Server check                             # a purchase request, over HTTP
#
# FreeCoreData's PostgreSQL and MySQL stores are built in with
# postgresql=yes and mysql=yes.
include $(GNUSTEP_MAKEFILES)/common.make

ifeq ($(ODATAKIT),)
$(error Set ODATAKIT to a built ODataKit checkout: make server ODATAKIT=../ODataKit)
endif

TOOL_NAME = wf-serve
wf-serve_OBJC_FILES = wf-serve.m
wf-serve_OBJCFLAGS += -fobjc-arc -fblocks -Wall
wf-serve_INCLUDE_DIRS = -I../Headers -I../OData \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataService/include \
	-I$(ODATAKIT)/Source/HTTPServerKit/include -I$(ODATAKIT)/Source/OTelKit/include
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR) -L$(ODATAKIT)/obj
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

# The uninstalled libraries, and the model the library build compiled.
export LD_LIBRARY_PATH := $(CURDIR)/../$(GNUSTEP_OBJ_DIR):$(ODATAKIT)/obj:$(LD_LIBRARY_PATH)
export WORKFLOWKIT_MODEL ?= $(CURDIR)/../WorkflowKit/Versions/0/Resources/WorkflowKit.momd

.PHONY: run check
run: all
	$(GNUSTEP_OBJ_DIR)/wf-serve -Config Examples/server.plist

check:: all
	./check.sh $(GNUSTEP_OBJ_DIR)/wf-serve

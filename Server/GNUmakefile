# wf-serve: the engine served over OData (see wf-serve.m for its settings).
# Built against ODataKit, whose Server/ has the HTTP adapter:
#
#   make -C $ODATAKIT && make -C $ODATAKIT/Server   # ODataKit and its server
#   make ODATAKIT=$ODATAKIT && make server           # here, from the top
#   make -C Server check                             # a purchase request, over HTTP
#
# FreeCoreData's PostgreSQL and MySQL stores are built in with
# postgresql=yes and mysql=yes.
include $(GNUSTEP_MAKEFILES)/common.make

ifeq ($(ODATAKIT),)
$(error Set ODATAKIT to a built ODataKit checkout: make server ODATAKIT=../ODataKit)
endif

GCDWebServer_DIR = $(ODATAKIT)/ThirdParty/GCDWebServer
include $(GCDWebServer_DIR)/GCDWebServer.make

TOOL_NAME = wf-serve
wf-serve_OBJC_FILES = wf-serve.m
wf-serve_OBJCFLAGS += -fobjc-arc -fblocks -Wall
wf-serve_INCLUDE_DIRS = -I../Headers -I../OData -I$(ODATAKIT)/Server \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataService/include
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR) -L$(ODATAKIT)/obj -L$(ODATAKIT)/Server/obj
wf-serve_TOOL_LIBS += -lWorkflowKitOData -lWorkflowKit -lODataHTTPServer -lODataService -lODataKit \
	-lCoreData $(GCDWebServer_LIBS)
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
export LD_LIBRARY_PATH := $(CURDIR)/../$(GNUSTEP_OBJ_DIR):$(ODATAKIT)/obj:$(ODATAKIT)/Server/obj:$(LD_LIBRARY_PATH)
export WORKFLOWKIT_MODEL ?= $(CURDIR)/../WorkflowKit/Versions/0/Resources/WorkflowKit.momd

.PHONY: run check
run: all
	$(GNUSTEP_OBJ_DIR)/wf-serve -Config Examples/server.plist

check:: all
	./check.sh $(GNUSTEP_OBJ_DIR)/wf-serve

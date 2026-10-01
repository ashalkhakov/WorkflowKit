# WorkflowDesk on GNUstep: the task list and operations app, a client of
# wf-serve's OData API. Needs gnustep-gui, FreeCoreData installed (with
# momc), and built checkouts of ODataKit and XFormsKit:
#
#   make -C $ODATAKIT && make -C $XFORMSKIT
#   make ODATAKIT=$ODATAKIT XFORMSKIT=$XFORMSKIT          # WorkflowDesk.app
#   make ODATAKIT=... XFORMSKIT=... run                   # open it
#   make ODATAKIT=... check                               # its tests
#
# Its model is the engine's, compiled from ../../Model into its resources.
include $(GNUSTEP_MAKEFILES)/common.make

ifeq ($(ODATAKIT),)
$(error Set ODATAKIT to a built ODataKit checkout)
endif
override ODATAKIT := $(abspath $(ODATAKIT))
export ODATAKIT

APP_NAME = WorkflowDesk

WorkflowDesk_OBJC_FILES = \
	main.m \
	WDAppDelegate.m \
	WDConnectWindowController.m \
	WDEntities.m \
	WDFormDocument.m \
	WDFormWindowController.m \
	WDInterface.m \
	WDOperationsWindowController.m \
	WDSession.m \
	WDSignIn.m \
	WDTasksWindowController.m

WorkflowDesk_RESOURCE_FILES = \
	Resources/MainMenu.xib \
	Resources/ConnectWindow.xib \
	Resources/TasksWindow.xib \
	Resources/FormWindow.xib \
	Resources/OperationsWindow.xib

WorkflowDesk_XCDATAMODELD_FILES = ../../Model/WorkflowKit.xcdatamodeld

WorkflowDesk_OBJCFLAGS += -fobjc-arc -fblocks -Wall
WorkflowDesk_INCLUDE_DIRS = \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataIncrementalStore/include
WorkflowDesk_LIB_DIRS = -L$(ODATAKIT)/obj
WorkflowDesk_GUI_LIBS += -lODataIncrementalStore -lODataKit -lCoreData -ldispatch -lgnutls

ifneq ($(XFORMSKIT),)
override XFORMSKIT := $(abspath $(XFORMSKIT))
WorkflowDesk_INCLUDE_DIRS += -I$(XFORMSKIT)/Sources -I$(XFORMSKIT)/Sources/XFormsKit
WorkflowDesk_LIB_DIRS += -L$(XFORMSKIT)/XFormsKit.framework/Versions/Current
WorkflowDesk_GUI_LIBS += -lXFormsKit
XFORMSKIT_LIBRARY_PATH = $(XFORMSKIT)/XFormsKit.framework/Versions/Current:
endif

include $(GNUSTEP_MAKEFILES)/coredata-model.make
include $(GNUSTEP_MAKEFILES)/application.make

ifeq ($(XFORMSKIT),)
before-all::
	@echo "Set XFORMSKIT to a built XFormsKit checkout" >&2; exit 1
endif

export LD_LIBRARY_PATH := $(ODATAKIT)/obj:$(XFORMSKIT_LIBRARY_PATH)$(LD_LIBRARY_PATH)

.PHONY: run check
run: all
	openapp ./WorkflowDesk.app

# The parts with no window: signing in, and forms.
check::
	$(MAKE) -C Tests run-tests

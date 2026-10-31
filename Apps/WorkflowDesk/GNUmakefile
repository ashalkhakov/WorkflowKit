# WorkflowDesk on GNUstep: the task list and operations app, a client of
# wf-serve's OData API. Needs gnustep-gui, FreeCoreData (with momc),
# ODataKit and XFormsKit installed (the releases .github/pins.env names), or
# built checkouts of the last two that ODATAKIT and XFORMSKIT name:
#
#   make                                                  # WorkflowDesk.app
#   make ODATAKIT=$ODATAKIT XFORMSKIT=$XFORMSKIT          # against checkouts
#   make run                                              # open it
#   make check                                            # its tests
#
# Its model is the engine's, compiled from ../../Model into its resources.
include $(GNUSTEP_MAKEFILES)/common.make

ifneq ($(ODATAKIT),)
override ODATAKIT := $(abspath $(ODATAKIT))
endif
export ODATAKIT

APP_NAME = WorkflowDesk

WorkflowDesk_OBJC_FILES = \
	main.m \
	WDAppDelegate.m \
	../Shared/WDConnectWindowController.m \
	WDDiagramView.m \
	../Shared/WKDXML.m \
	../Shared/WKDDiagram.m \
	../Shared/WKDRenderer.m \
	../Shared/WKDEditor.m \
	../Shared/WKDEditor+Canvas.m \
	../Shared/WKDEditor+Lanes.m \
	../Shared/WKDLayout.m \
	../Shared/WDEntities.m \
	WDFormDocument.m \
	WDFormWindowController.m \
	WDInterface.m \
	WDOperationsWindowController.m \
	../Shared/WDSession.m \
	../Shared/WDSignIn.m \
	../Shared/WDSockets-posix.m \
	../Shared/WDTracing.m \
	../Shared/WKDUpdater-GNUstep.m \
	WDTasksWindowController.m

WorkflowDesk_RESOURCE_FILES = \
	Resources/MainMenu.xib \
	../Shared/Resources/ConnectWindow.xib \
	Resources/TasksWindow.xib \
	Resources/FormWindow.xib \
	Resources/OperationsWindow.xib \
	WorkflowDesk.png

WorkflowDesk_XCDATAMODELD_FILES = ../../Model/WorkflowKit.xcdatamodeld

WorkflowDesk_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include WKDGNUstepCompat.h
WorkflowDesk_INCLUDE_DIRS = -I../Shared
# GSUpdater, the stack's: updates on Windows (../Shared/WKDUpdater.h).
WorkflowDesk_GUI_LIBS += -lODataIncrementalStore -lODataKit -lOTelKit -lXFormsKit -lGSUpdater -lCoreData -ldispatch -lgnutls
ifneq ($(ODATAKIT),)
WorkflowDesk_INCLUDE_DIRS += \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataIncrementalStore/include \
	-I$(ODATAKIT)/Source/OTelKit/include
WorkflowDesk_LIB_DIRS += -L$(ODATAKIT)/obj
ODATAKIT_LIBRARY_PATH = $(ODATAKIT)/obj:
endif
ifneq ($(XFORMSKIT),)
override XFORMSKIT := $(abspath $(XFORMSKIT))
WorkflowDesk_INCLUDE_DIRS += -I$(XFORMSKIT)/Sources -I$(XFORMSKIT)/Sources/XFormsKit
WorkflowDesk_LIB_DIRS += -L$(XFORMSKIT)/XFormsKit.framework/Versions/Current
XFORMSKIT_LIBRARY_PATH = $(XFORMSKIT)/XFormsKit.framework/Versions/Current:
endif

# Sockets for signing in (../Shared/WDSockets.h): Winsock's on Windows.
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
WorkflowDesk_OBJC_FILES := $(subst WDSockets-posix.m,WDSockets-windows.m,$(WorkflowDesk_OBJC_FILES))
WorkflowDesk_GUI_LIBS += -lws2_32
endif

include $(GNUSTEP_MAKEFILES)/coredata-model.make
include $(GNUSTEP_MAKEFILES)/application.make

export LD_LIBRARY_PATH := $(ODATAKIT_LIBRARY_PATH)$(XFORMSKIT_LIBRARY_PATH)$(LD_LIBRARY_PATH)

.PHONY: run check
run: all
	openapp ./WorkflowDesk.app

# The parts with no window: signing in, and forms.
check::
	$(MAKE) -C Tests run-tests

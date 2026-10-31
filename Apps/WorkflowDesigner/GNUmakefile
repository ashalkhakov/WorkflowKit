# WorkflowDesigner on GNUstep: the BPMN process designer. It needs
# gnustep-gui, the engine library, built at the top of this repository
# (`make`), whose reader checks that the process is one the engine runs,
# and -- to deploy, and to open what is deployed -- FreeCoreData installed
# (with momc) and ODataKit, as WorkflowDesk does; and, to edit forms,
# XFormsKit with its XFormsDesignKit, whose editor opens a process's forms
# in this app. Installed (the releases .github/pins.env names), or built
# checkouts that ODATAKIT and XFORMSKIT name (`make designkit` in the
# latter):
#
#   make                                           # WorkflowDesigner.app
#   make ODATAKIT=$ODATAKIT XFORMSKIT=$XFORMSKIT   # against checkouts
#   make run                                       # open it
#   make check                                     # its tests: the document
#                                                  # model, edits, layout,
#                                                  # deployments
include $(GNUSTEP_MAKEFILES)/common.make

ifneq ($(ODATAKIT),)
override ODATAKIT := $(abspath $(ODATAKIT))
endif
export ODATAKIT
ifneq ($(XFORMSKIT),)
override XFORMSKIT := $(abspath $(XFORMSKIT))
XFORMSDESIGNKIT = $(XFORMSKIT)/Sources/XFormsDesignKit
else
# Installed, its headers are laid out as in its tree.
XFORMSDESIGNKIT = $(GNUSTEP_LOCAL_HEADERS)/XFormsDesignKit
endif
export XFORMSKIT

APP_NAME = WorkflowDesigner

WorkflowDesigner_OBJC_FILES = \
	main.m \
	WKDCanvasView.m \
	WKDPaletteView.m \
	WKDProperties.m \
	WKDPane.m \
	WKDOutline.m \
	WKDInspectorView.m \
	WKDExpressionField.m \
	WKDTableEditor.m \
	WKDDeployment.m \
	WKDDecisions.m \
	WKDDecisionDocument.m \
	WKDDecisionWindowController.m \
	WKDDocument.m \
	WKDWindowController.m \
	WKDServerProcessesController.m \
	WKDAppDelegate.m \
	../Shared/WKDXML.m \
	../Shared/WKDEditor.m \
	../Shared/WKDEditor+Canvas.m \
	../Shared/WKDEditor+Clipboard.m \
	../Shared/WKDEditor+Types.m \
	../Shared/WKDEditor+Alignment.m \
	../Shared/WKDEditor+Lanes.m \
	../Shared/WKDLayout.m \
	../Shared/WKDDiagram.m \
	../Shared/WKDRenderer.m \
	../Shared/WDConnectWindowController.m \
	../Shared/WDEntities.m \
	../Shared/WDSession.m \
	../Shared/WDSignIn.m \
	../Shared/WDTracing.m

WorkflowDesigner_RESOURCE_FILES = \
	Resources/MainMenu.xib \
	Resources/DesignerWindow.xib \
	Resources/ServerProcesses.xib \
	../Shared/Resources/ConnectWindow.xib

# The engine's model, which the server's API is read through.
WorkflowDesigner_XCDATAMODELD_FILES = ../../Model/WorkflowKit.xcdatamodeld

WorkflowDesigner_MAIN_MODEL_FILE = MainMenu.xib
WorkflowDesigner_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include WKDGNUstepCompat.h
WorkflowDesigner_INCLUDE_DIRS = -I../../Headers -I../Shared \
	-I$(XFORMSDESIGNKIT) -I$(XFORMSDESIGNKIT)/ThirdParty/DMTabBar
WorkflowDesigner_LIB_DIRS = -L../../$(GNUSTEP_OBJ_DIR)
ifneq ($(ODATAKIT),)
WorkflowDesigner_INCLUDE_DIRS += \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataIncrementalStore/include \
	-I$(ODATAKIT)/Source/OTelKit/include
WorkflowDesigner_LIB_DIRS += -L$(ODATAKIT)/obj
ODATAKIT_LIBRARY_PATH = $(ODATAKIT)/obj:
endif
ifneq ($(XFORMSKIT),)
WorkflowDesigner_INCLUDE_DIRS += -I$(XFORMSKIT)/Sources -I$(XFORMSKIT)/Sources/XFormsKit
WorkflowDesigner_LIB_DIRS += \
	-L$(XFORMSDESIGNKIT)/XFormsDesignKit.framework/Versions/Current \
	-L$(XFORMSKIT)/XFormsKit.framework/Versions/Current
XFORMSKIT_LIBRARY_PATH = $(XFORMSDESIGNKIT)/XFormsDesignKit.framework/Versions/Current:$(XFORMSKIT)/XFormsKit.framework/Versions/Current:
endif
WorkflowDesigner_GUI_LIBS += -lWorkflowKit -lODataIncrementalStore -lODataKit -lOTelKit \
	-lXFormsDesignKit -lXFormsKit -lCoreData -ldispatch -lgnutls

include $(GNUSTEP_MAKEFILES)/coredata-model.make
include $(GNUSTEP_MAKEFILES)/application.make

export LD_LIBRARY_PATH := $(CURDIR)/../../$(GNUSTEP_OBJ_DIR):$(ODATAKIT_LIBRARY_PATH)$(XFORMSKIT_LIBRARY_PATH)$(LD_LIBRARY_PATH)

.PHONY: run check
run: all
	openapp ./WorkflowDesigner.app

check::
	$(MAKE) -C Tests run-tests

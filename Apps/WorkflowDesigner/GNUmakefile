# WorkflowDesigner on GNUstep: the BPMN process designer. It needs
# gnustep-gui, the engine library, built at the top of this repository
# (`make`), whose reader checks that the process is one the engine runs,
# and -- to deploy, and to open what is deployed -- FreeCoreData installed
# (with momc) and a built ODataKit checkout, as WorkflowDesk does:
#
#   make ODATAKIT=$ODATAKIT          # WorkflowDesigner.app
#   make ODATAKIT=... run            # open it
#   make ODATAKIT=... check          # its tests: the document model, edits,
#                                    # layout, deployments
include $(GNUSTEP_MAKEFILES)/common.make

ifeq ($(ODATAKIT),)
$(error Set ODATAKIT to a built ODataKit checkout)
endif
override ODATAKIT := $(abspath $(ODATAKIT))
export ODATAKIT

APP_NAME = WorkflowDesigner

WorkflowDesigner_OBJC_FILES = \
	main.m \
	WKDXML.m \
	WKDDiagram.m \
	WKDLayout.m \
	WKDEditor.m \
	WKDRenderer.m \
	WKDCanvasView.m \
	WKDPaletteView.m \
	WKDProperties.m \
	WKDPane.m \
	WKDOutline.m \
	WKDInspectorView.m \
	WKDDeployment.m \
	WKDDocument.m \
	WKDWindowController.m \
	WKDServerProcessesController.m \
	WKDAppDelegate.m \
	../Shared/WDConnectWindowController.m \
	../Shared/WDEntities.m \
	../Shared/WDSession.m \
	../Shared/WDSignIn.m \
	../Shared/WDTracing.m \
	ThirdParty/DMTabBar/DMTabBar.m \
	ThirdParty/DMTabBar/DMTabBarItem.m

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
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataIncrementalStore/include \
	-I$(ODATAKIT)/Source/OTelKit/include
WorkflowDesigner_LIB_DIRS = -L../../$(GNUSTEP_OBJ_DIR) -L$(ODATAKIT)/obj
WorkflowDesigner_GUI_LIBS += -lWorkflowKit -lODataIncrementalStore -lODataKit -lOTelKit -lCoreData -ldispatch -lgnutls

include $(GNUSTEP_MAKEFILES)/coredata-model.make
include $(GNUSTEP_MAKEFILES)/application.make

export LD_LIBRARY_PATH := $(CURDIR)/../../$(GNUSTEP_OBJ_DIR):$(ODATAKIT)/obj:$(LD_LIBRARY_PATH)

.PHONY: run check
run: all
	openapp ./WorkflowDesigner.app

check::
	$(MAKE) -C Tests run-tests

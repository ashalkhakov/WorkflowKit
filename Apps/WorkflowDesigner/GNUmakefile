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

include designer.make

APP_NAME = WorkflowDesigner

WorkflowDesigner_OBJC_FILES = \
	main.m \
	WKDCanvasView.m \
	WKDCanvasViewController.m \
	WKDOutlineViewController.m \
	WKDPaletteViewController.m \
	WKDProblemsViewController.m \
	WKDProcessCommands.m \
	WKDPaletteView.m \
	WKDProperties.m \
	WKDElementModel.m \
	WKDTableModel.m \
	WKDInspectorRow.m \
	WKDTableRowController.m \
	WKDInspectorViewController.m \
	WKDPane.m \
	WKDOutline.m \
	WKDExpressionField.m \
	WKDDeployment.m \
	WKDSelection.m \
	WKDProcessEditor.m \
	WKDDecisions.m \
	WKDDmnModel.m \
	WKDDmnReader.m \
	WKDDmnWriter.m \
	WKDDmnModelCheck.m \
	WKDDecisionDocument.m \
	WKDDecisionEditor.m \
	WKDDecisionListViewController.m \
	WKDDecisionDetailViewController.m \
	WKDRuleGridViewController.m \
	WKDColumnViewController.m \
	WKDLiteralViewController.m \
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
	../Shared/WKDNotation.m \
	../Shared/WKDModel.m \
	../Shared/WKDBpmnReader.m \
	../Shared/WKDBpmnWriter.m \
	../Shared/WKDModelCheck.m \
	../Shared/WKDJournal.m \
	../Shared/WKDRenderer.m \
	../Shared/WDConnectWindowController.m \
	../Shared/WDEntities.m \
	../Shared/WDSession.m \
	../Shared/WDSignIn.m \
	../Shared/WDSockets-posix.m \
	../Shared/WDTracing.m \
	../Shared/WKDUpdater-GNUstep.m

WorkflowDesigner_RESOURCE_FILES = \
	Resources/MainMenu.xib \
	Resources/DesignerWindow.xib \
	Resources/WKDCanvas.xib \
	Resources/WKDOutlineView.xib \
	Resources/WKDPalette.xib \
	Resources/WKDProblems.xib \
	Resources/WKDInspector.xib \
	Resources/WKDRowTitle.xib \
	Resources/WKDRowText.xib \
	Resources/WKDRowExpression.xib \
	Resources/WKDRowLongText.xib \
	Resources/WKDRowCheck.xib \
	Resources/WKDRowChoice.xib \
	Resources/WKDRowButton.xib \
	Resources/WKDRowTable.xib \
	Resources/DecisionWindow.xib \
	Resources/WKDDecisionList.xib \
	Resources/WKDDecisionDetail.xib \
	Resources/WKDRuleGrid.xib \
	Resources/WKDColumn.xib \
	Resources/WKDLiteral.xib \
	Resources/ServerProcesses.xib \
	../Shared/Resources/ConnectWindow.xib \
	Resources/WorkflowDesigner.png

# The engine's model, which the server's API is read through.
WorkflowDesigner_XCDATAMODELD_FILES = ../../Model/WorkflowKit.xcdatamodeld

WorkflowDesigner_MAIN_MODEL_FILE = MainMenu.xib
WorkflowDesigner_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include WKDGNUstepCompat.h
WorkflowDesigner_INCLUDE_DIRS = $(WKD_INCLUDE_DIRS)
WorkflowDesigner_LIB_DIRS = $(WKD_LIB_DIRS)
WorkflowDesigner_GUI_LIBS += $(WKD_LIBS)

# Sockets for signing in (../Shared/WDSockets.h): Winsock's on Windows.
ifeq ($(WKD_WINDOWS),yes)
WorkflowDesigner_OBJC_FILES := $(subst WDSockets-posix.m,WDSockets-windows.m,$(WorkflowDesigner_OBJC_FILES))
endif

include $(GNUSTEP_MAKEFILES)/coredata-model.make
include $(GNUSTEP_MAKEFILES)/application.make

export LD_LIBRARY_PATH := $(WKD_LIBRARY_PATH)$(LD_LIBRARY_PATH)
export PATH := $(WKD_LIBRARY_PATH)$(PATH)

.PHONY: run check
run: all
	openapp ./WorkflowDesigner.app

# The tests open windows: under xvfb-run where there is no display, as
# ORMKit's designer tests are.
XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))

check::
	$(XVFB) $(MAKE) -C Tests run-tests

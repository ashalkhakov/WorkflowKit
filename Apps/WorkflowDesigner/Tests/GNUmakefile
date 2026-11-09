# WorkflowDesigner's tests: the document model and its edits, the layout,
# that the engine takes what the designer writes, and the parts' XIBs
# loaded and connected; run with `make check` one level up, which gives
# them a display (xvfb-run) where there is none.
include $(GNUSTEP_MAKEFILES)/common.make
include ../designer.make

BUNDLE_NAME = WorkflowDesignerTests

WorkflowDesignerTests_OBJC_FILES = \
	../WKDCanvasView.m \
	../WKDCanvasViewController.m \
	../WKDOutlineViewController.m \
	../WKDPaletteViewController.m \
	../WKDProblemsViewController.m \
	../WKDProcessCommands.m \
	../WKDPaletteView.m \
	../WKDProperties.m \
	../WKDElementModel.m \
	../WKDTableModel.m \
	../WKDInspectorRow.m \
	../WKDTableRowController.m \
	../WKDInspectorViewController.m \
	../WKDPane.m \
	../WKDOutline.m \
	../WKDExpressionField.m \
	../WKDDeployment.m \
	../WKDSelection.m \
	../WKDProcessEditor.m \
	../WKDDecisions.m \
	../WKDDmnModel.m \
	../WKDDmnReader.m \
	../WKDDmnWriter.m \
	../WKDDmnModelCheck.m \
	../WKDDecisionDocument.m \
	../WKDDecisionWindowController.m \
	../WKDDocument.m \
	../WKDWindowController.m \
	../WKDServerProcessesController.m \
	../WKDAppDelegate.m \
	../../Shared/WKDXML.m \
	../../Shared/WKDEditor.m \
	../../Shared/WKDEditor+Canvas.m \
	../../Shared/WKDEditor+Clipboard.m \
	../../Shared/WKDEditor+Types.m \
	../../Shared/WKDEditor+Alignment.m \
	../../Shared/WKDEditor+Lanes.m \
	../../Shared/WKDNotation.m \
	../../Shared/WKDModel.m \
	../../Shared/WKDBpmnReader.m \
	../../Shared/WKDBpmnWriter.m \
	../../Shared/WKDModelCheck.m \
	../../Shared/WKDJournal.m \
	../../Shared/WKDRenderer.m \
	../../Shared/WDConnectWindowController.m \
	../../Shared/WDEntities.m \
	../../Shared/WDSession.m \
	../../Shared/WDSignIn.m \
	../../Shared/WDSockets-posix.m \
	../../Shared/WDTracing.m \
	../../Shared/WKDUpdater-GNUstep.m \
	WKDDiagramTests.m \
	WKDModelTests.m \
	WKDProcessEditorTests.m \
	WKDPartsTests.m \
	WKDElementModelTests.m \
	WKDInspectorTests.m \
	WKDTimingTests.m \
	WKDEditorTests.m \
	WKDCanvasEditsTests.m \
	WKDClipboardTests.m \
	WKDTypesTests.m \
	WKDAlignmentTests.m \
	WKDLanesTests.m \
	WKDLayoutTests.m \
	WKDPropertiesTests.m \
	WKDTablesTests.m \
	WKDDeploymentTests.m \
	WKDDecisionsTests.m

# The app's parts and their XIBs: the bundle is what -bundleForClass:
# finds them in, as ORMKit's designer tests have it.
WorkflowDesignerTests_RESOURCE_FILES = \
	../Resources/DesignerWindow.xib \
	../Resources/WKDCanvas.xib \
	../Resources/WKDOutlineView.xib \
	../Resources/WKDPalette.xib \
	../Resources/WKDProblems.xib \
	../Resources/WKDInspector.xib \
	../Resources/WKDRowTitle.xib \
	../Resources/WKDRowText.xib \
	../Resources/WKDRowExpression.xib \
	../Resources/WKDRowLongText.xib \
	../Resources/WKDRowCheck.xib \
	../Resources/WKDRowChoice.xib \
	../Resources/WKDRowButton.xib \
	../Resources/WKDRowTable.xib \
	../Resources/ServerProcesses.xib \
	../../Shared/Resources/ConnectWindow.xib

ifeq ($(WKD_WINDOWS),yes)
WorkflowDesignerTests_OBJC_FILES := $(subst WDSockets-posix.m,WDSockets-windows.m,$(WorkflowDesignerTests_OBJC_FILES))
endif
WorkflowDesignerTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include WKDGNUstepCompat.h
WorkflowDesignerTests_INCLUDE_DIRS = $(WKD_INCLUDE_DIRS)
ADDITIONAL_LIB_DIRS += $(WKD_LIB_DIRS)
WorkflowDesignerTests_BUNDLE_LIBS += $(WKD_LIBS) -lXCTest
WorkflowDesignerTests_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 120

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(WKD_LIBRARY_PATH)$$LD_LIBRARY_PATH" \
	PATH="$(WKD_LIBRARY_PATH)$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle

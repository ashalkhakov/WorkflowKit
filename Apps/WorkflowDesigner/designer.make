# The designer's parts -- the BPMN and DMN editors' models, session
# objects, view controllers and their XIBs -- and what they are built
# against: what UDCode's extension (UDCodeExtension/) and the tests
# (Tests/) compile and carry, each including this after common.make.
# Paths are this directory's; an includer adds its prefix.
#
#   WKD_OBJC_FILES      the sources
#   WKD_RESOURCE_FILES  the XIBs
#   WKD_INCLUDE_DIRS    the headers' directories
#   WKD_LIB_DIRS        the libraries' directories
#   WKD_LIBS            the libraries: the engine's, at the top of this
#                       repository, DiagramKit's canvas, Core Data's
#   WKD_OBJCFLAGS       how the sources are compiled
#   WKD_LIBRARY_PATH    what the uninstalled engine is run from

WKD_DESIGNER := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

WKD_OBJC_FILES = \
	WKDCanvasView.m \
	WKDCanvasViewController.m \
	WKDOutlineViewController.m \
	WKDPaletteViewController.m \
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
	WKDDecisionEditor.m \
	WKDDecisionListViewController.m \
	WKDDecisionDetailViewController.m \
	WKDRuleGridViewController.m \
	WKDColumnViewController.m \
	WKDLiteralViewController.m \
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
	../Shared/WKDRenderer.m

WKD_RESOURCE_FILES = \
	Resources/WKDCanvas.xib \
	Resources/WKDOutlineView.xib \
	Resources/WKDPalette.xib \
	Resources/WKDInspector.xib \
	Resources/WKDRowTitle.xib \
	Resources/WKDRowText.xib \
	Resources/WKDRowExpression.xib \
	Resources/WKDRowLongText.xib \
	Resources/WKDRowCheck.xib \
	Resources/WKDRowChoice.xib \
	Resources/WKDRowButton.xib \
	Resources/WKDRowTable.xib \
	Resources/WKDDecisionList.xib \
	Resources/WKDDecisionDetail.xib \
	Resources/WKDRuleGrid.xib \
	Resources/WKDColumn.xib \
	Resources/WKDLiteral.xib

WKD_INCLUDE_DIRS = -I$(WKD_DESIGNER) -I$(WKD_DESIGNER)/../../Headers -I$(WKD_DESIGNER)/../Shared
WKD_LIB_DIRS = -L$(WKD_DESIGNER)/../../$(GNUSTEP_OBJ_DIR)
WKD_LIBRARY_PATH = $(WKD_DESIGNER)/../../$(GNUSTEP_OBJ_DIR):
# DiagramKit: the process diagram's layout (../Shared/WKDEditor.m); and
# DiagramKitUI's canvas, which WKDCanvasView is. Core Data: the engine's.
WKD_LIBS = -lWorkflowKit -lDiagramKitUI -lDiagramKit -lCoreData -ldispatch
# AppKit names gnustep-gui lacks (../Shared/WKDGNUstepCompat.h).
WKD_OBJCFLAGS = -fobjc-arc -fblocks -Wall -include $(WKD_DESIGNER)/../Shared/WKDGNUstepCompat.h

# WorkflowDesigner on GNUstep: the BPMN process designer. It needs
# gnustep-gui and the engine library, built at the top of this repository
# (`make`), whose reader checks that the process is one the engine runs:
#
#   make                  # WorkflowDesigner.app
#   make run              # open it
#   make check            # its tests: the document model, edits, layout
include $(GNUSTEP_MAKEFILES)/common.make

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
	WKDDocument.m \
	WKDWindowController.m

WorkflowDesigner_RESOURCE_FILES = \
	Resources/MainMenu.xib \
	Resources/DesignerWindow.xib

WorkflowDesigner_MAIN_MODEL_FILE = MainMenu.xib
WorkflowDesigner_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include WKDGNUstepCompat.h
WorkflowDesigner_INCLUDE_DIRS = -I../../Headers
WorkflowDesigner_LIB_DIRS = -L../../$(GNUSTEP_OBJ_DIR)
WorkflowDesigner_GUI_LIBS += -lWorkflowKit -lCoreData -ldispatch

include $(GNUSTEP_MAKEFILES)/application.make

export LD_LIBRARY_PATH := $(CURDIR)/../../$(GNUSTEP_OBJ_DIR):$(LD_LIBRARY_PATH)

.PHONY: run check
run: all
	openapp ./WorkflowDesigner.app

check::
	$(MAKE) -C Tests run-tests

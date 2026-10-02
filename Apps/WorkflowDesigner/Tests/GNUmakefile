# WorkflowDesigner's tests: the document model and its edits, the layout,
# and that the engine takes what the designer writes. No window; run with
# `make check` one level up.
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = WorkflowDesignerTests

WorkflowDesignerTests_OBJC_FILES = \
	../../Shared/WKDXML.m \
	../../Shared/WKDDiagram.m \
	../../Shared/WKDLayout.m \
	../../Shared/WKDEditor.m \
	../../Shared/WKDEditor+Canvas.m \
	../../Shared/WKDEditor+Clipboard.m \
	../../Shared/WKDEditor+Types.m \
	../../Shared/WKDEditor+Alignment.m \
	../WKDProperties.m \
	../WKDDeployment.m \
	WKDDiagramTests.m \
	WKDEditorTests.m \
	WKDCanvasEditsTests.m \
	WKDClipboardTests.m \
	WKDTypesTests.m \
	WKDAlignmentTests.m \
	WKDLayoutTests.m \
	WKDPropertiesTests.m \
	WKDTablesTests.m \
	WKDDeploymentTests.m

WorkflowDesignerTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
WorkflowDesignerTests_INCLUDE_DIRS = -I.. -I../../Shared -I../../../Headers
ADDITIONAL_LIB_DIRS += -L../../../$(GNUSTEP_OBJ_DIR)
WorkflowDesignerTests_BUNDLE_LIBS += -lWorkflowKit -lCoreData -lXCTest -ldispatch
WorkflowDesignerTests_NEEDS_GUI = no

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 120

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(CURDIR)/../../../$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle

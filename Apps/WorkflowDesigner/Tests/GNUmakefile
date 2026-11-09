# The designer's parts' tests: the models and their edits, the layout,
# that the engine takes what they write, and the parts' XIBs
# loaded and connected; run with `make check` one level up, which gives
# them a display (xvfb-run) where there is none.
include $(GNUSTEP_MAKEFILES)/common.make
include ../designer.make

BUNDLE_NAME = WorkflowDesignerTests

WorkflowDesignerTests_OBJC_FILES = \
	$(addprefix ../,$(WKD_OBJC_FILES)) \
	WKDDiagramTests.m \
	WKDModelTests.m \
	WKDProcessEditorTests.m \
	WKDPartsTests.m \
	WKDElementModelTests.m \
	WKDInspectorTests.m \
	WKDDecisionPartsTests.m \
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

# The parts' XIBs: the bundle is what -bundleForClass: finds them in, as
# ORMKit's designer tests have it.
WorkflowDesignerTests_RESOURCE_FILES = $(addprefix ../,$(WKD_RESOURCE_FILES))

WorkflowDesignerTests_OBJCFLAGS += $(WKD_OBJCFLAGS)
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

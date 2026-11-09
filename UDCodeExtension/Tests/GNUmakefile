# The BPMN and DMN extension's tests (an XCTest bundle; tools-xctest),
# against UDCode's SDK installed: the extension's sources and the
# designer's parts compiled in (their XIBs found in this bundle, as in
# WorkflowDesigner.bundle), UDCodeKit's document and text model linked.
#
#   make            build the bundle
#   make run-tests  build and run it (make check one level up gives it a
#                   display, xvfb-run, where there is none)
include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

BUNDLE_NAME = WKUTests
WKUTests_STANDARD_INSTALL = no
WKUTests_NEEDS_GUI = yes
WKUTests_PRINCIPAL_CLASS = XCTestCase

WKD_DIR = ../../Apps/WorkflowDesigner
include $(WKD_DIR)/designer.make
WKUTests_OBJC_FILES = \
	WKUTests.m \
	../WKUExtension.m \
	../WKUEditorView.m \
	../WKUProcessEditorViewController.m \
	../WKUDecisionEditorViewController.m \
	../WKUTextEdits.m \
	$(addprefix $(WKD_DIR)/,$(WKD_OBJC_FILES))
WKUTests_RESOURCE_FILES = \
	../WKUProcessEditor.xib \
	../WKUDecisionEditor.xib \
	../WKUEditorMenus.xib \
	$(addprefix $(WKD_DIR)/,$(WKD_RESOURCE_FILES))
WKUTests_INCLUDE_DIRS = -I.. -I$(WKD_DIR)/Tests $(WKD_INCLUDE_DIRS)
WKUTests_OBJCFLAGS += $(WKD_OBJCFLAGS)
ADDITIONAL_LIB_DIRS += $(WKD_LIB_DIRS)
WKUTests_BUNDLE_LIBS += $(WKD_LIBS) -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 300

# What it prints goes to a file, of which the end is shown: a daemon a test
# starts (GNUstep's gpbs, gdnc) inherits where the output goes, and one
# holding the output's pipe keeps a CI step that reads it from ending.
.PHONY: run-tests
run-tests: all
	@LD_LIBRARY_PATH="$(WKD_LIBRARY_PATH)$$LD_LIBRARY_PATH" PATH="$(WKD_LIBRARY_PATH)$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle > $(BUNDLE_NAME).log 2>&1; \
	status=$$?; grep -v "unknown control size\|unknown custom color space\|_NET_WORKAREA\|given negative width" \
	  $(BUNDLE_NAME).log | tail -n 150; \
	[ $$status = 0 ] || echo "== $(BUNDLE_NAME) exited $$status"; exit $$status

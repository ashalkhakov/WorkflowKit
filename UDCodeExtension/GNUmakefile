include $(GNUSTEP_MAKEFILES)/common.make

# UDCode's BPMN and DMN extension (docs/UDCODE.md): WorkflowDesigner.bundle,
# the designer's parts (Apps/WorkflowDesigner, designer.make) in UDCode
# tabs. Built against UDCode's SDK (its udcodekit archive, .github/pins.env's
# UDCODEKIT_VERSION) installed on a GNUstep stack; the top GNUmakefile
# builds it only where that SDK is. The parts' sources and XIBs are
# compiled in; the engine's library goes beside its binary.
# Scripts/udcx.sh packages it, its libraries inside it.
#
#   make          the bundle
#   make check    its tests (Tests/), under xvfb-run where there is no display
CC = clang
OBJC = clang

BUNDLE_NAME = WorkflowDesigner
BUNDLE_EXTENSION = .bundle
WorkflowDesigner_PRINCIPAL_CLASS = WKUExtension
WorkflowDesigner_NEEDS_GUI = yes
WorkflowDesigner_STANDARD_INSTALL = no

WKD_DIR = ../Apps/WorkflowDesigner
include $(WKD_DIR)/designer.make

# The extension's own, as the tests compile them too.
WKU_OBJC_FILES = \
	WKUExtension.m \
	WKUEditorView.m \
	WKUProcessEditorViewController.m \
	WKUDecisionEditorViewController.m \
	WKUTextEdits.m
WKU_RESOURCE_FILES = \
	WKUProcessEditor.xib \
	WKUDecisionEditor.xib \
	WKUEditorMenus.xib

WorkflowDesigner_OBJC_FILES = $(WKU_OBJC_FILES) $(addprefix $(WKD_DIR)/,$(WKD_OBJC_FILES))
WorkflowDesigner_RESOURCE_FILES = Resources/LanguageInfo.plist $(WKU_RESOURCE_FILES) \
	$(addprefix $(WKD_DIR)/,$(WKD_RESOURCE_FILES))
WorkflowDesigner_INCLUDE_DIRS = $(WKD_INCLUDE_DIRS)
WorkflowDesigner_OBJCFLAGS += $(WKD_OBJCFLAGS)
WorkflowDesigner_LIB_DIRS += $(WKD_LIB_DIRS)
# Its own libraries (the engine's; on GNUstep Core Data's too): found from
# where the binary is. UDCode's own (UDCodeKit, DiagramKit, GNUstep's) are
# the running UDCode's: on Linux left for it, as UDCode's own plug-ins
# leave them; a Windows DLL is linked against all it uses.
WorkflowDesigner_BUNDLE_LIBS += $(WKD_LIBS)
ifneq ($(OS),Windows_NT)
WorkflowDesigner_LDFLAGS += -Wl,-rpath,'$$ORIGIN'
else
WorkflowDesigner_BUNDLE_LIBS += -lUDCodeKit -lUDPieceTable -lLSPKit -lgnustep-gui -lgnustep-base -lobjc
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

# The tests open windows: under xvfb-run where there is no display.
XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))


check:: all
	$(XVFB) $(MAKE) -C Tests run-tests

after-clean::
	$(MAKE) -C Tests clean

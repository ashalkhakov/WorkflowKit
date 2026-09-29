# UDWorkflow on GNUstep.
#
#   make                 the library, obj/libUDWorkflow.so
#   make examples        the demo tools in Examples/
#   make test            the library, then the XCTest suite (tools-xctest)
#
# Built against the patched stack from ../gnustep-patches, never a distro
# GNUstep: see CLAUDE.md for the docker box and CI for the pinned recipe.
#
# A library rather than a framework, like RDLKit: on GNUstep a framework puts
# its binary under UDWorkflow.framework/Versions/<v>/<target>/, which every
# tool and test bundle in the tree then has to name to link against it.
include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = UDWorkflow

UDWorkflow_OBJC_FILES = \
	Source/UDFlowElements.m \
	Source/UDCondition.m \
	Source/UDProcessDefinition.m \
	Source/UDRuntimeState.m \
	Source/UDHandlers.m \
	Source/UDMemoryStore.m \
	Source/UDBpmn.m \
	Source/UDEngine.m

UDWorkflow_HEADER_FILES_DIR = Headers
UDWorkflow_HEADER_FILES_INSTALL_DIR = UDWorkflow
UDWorkflow_HEADER_FILES = \
	UDTypes.h \
	UDCondition.h \
	UDFlowElements.h \
	UDProcessDefinition.h \
	UDRuntimeState.h \
	UDHandlers.h \
	UDMemoryStore.h \
	UDEngine.h \
	UDBpmn.h \
	UDWorkflow.h

UDWorkflow_INCLUDE_DIRS = -IHeaders
UDWorkflow_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=objc-method-access
UDWorkflow_LIBRARIES_DEPEND_UPON += -ldispatch $(FND_LIBS) $(OBJC_LIBS)

include $(GNUSTEP_MAKEFILES)/library.make

.PHONY: examples test
examples: all
	$(MAKE) -C Examples

test: all
	$(MAKE) -C Tests run-tests

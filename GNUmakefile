include $(GNUSTEP_MAKEFILES)/common.make

FRAMEWORK_NAME = UDWorkflow

UDWorkflow_OBJC_FILES = \
	Source/UDFlowElements.m \
	Source/UDCondition.m \
	Source/UDProcessDefinition.m \
	Source/UDRuntimeState.m \
	Source/UDHandlers.m \
	Source/UDMemoryStore.m \
	Source/UDBpmn.m \
	Source/UDEngine.m

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

UDWorkflow_HEADER_FILES_DIR = Headers
UDWorkflow_HEADER_FILES_INSTALL_DIR = UDWorkflow

UDWorkflow_INCLUDE_DIRS = -IHeaders
UDWorkflow_OBJCFLAGS += -fobjc-arc -fblocks -Wall
UDWorkflow_LDFLAGS += -ldispatch

TOOL_NAME = PurchaseRequestDemo

PurchaseRequestDemo_OBJC_FILES = Examples/PurchaseRequestDemo.m
PurchaseRequestDemo_OBJCFLAGS += -fobjc-arc -fblocks -Wall
PurchaseRequestDemo_INCLUDE_DIRS = -IHeaders
PurchaseRequestDemo_TOOL_LIBS += -lUDWorkflow -ldispatch
PurchaseRequestDemo_LIB_DIRS += -L$(GNUSTEP_OBJ_DIR)

include $(GNUSTEP_MAKEFILES)/framework.make
include $(GNUSTEP_MAKEFILES)/tool.make

# XCTest bundle (tools-xctest):
#   make -C Tests
#   xctest Tests/obj/UDWorkflowTests.bundle

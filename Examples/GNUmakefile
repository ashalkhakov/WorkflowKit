# Demo tools. Build the library first (`make` at the top), or use
# `make examples` there, which does both; `make -C Examples run` runs the
# demo against the uninstalled library and its model.
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = PurchaseRequestDemo

PurchaseRequestDemo_OBJC_FILES = PurchaseRequestDemo.m
PurchaseRequestDemo_OBJCFLAGS += -fobjc-arc -fblocks -Wall
PurchaseRequestDemo_INCLUDE_DIRS = -I../Headers
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR)
PurchaseRequestDemo_TOOL_LIBS += -lWorkflowKit -lCoreData -ldispatch

include $(GNUSTEP_MAKEFILES)/tool.make

.PHONY: run
run: all
	LD_LIBRARY_PATH="$(CURDIR)/../$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	PATH="$(CURDIR)/../$(GNUSTEP_OBJ_DIR):$$PATH" \
	WORKFLOWKIT_MODEL="$(CURDIR)/../WorkflowKit/Versions/0/Resources/WorkflowKit.momd" \
	  $(GNUSTEP_OBJ_DIR)/PurchaseRequestDemo

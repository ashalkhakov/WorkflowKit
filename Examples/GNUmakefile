# Demo tools. Build the library first (`make` at the top), or use
# `make examples` there, which does both.
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = PurchaseRequestDemo

PurchaseRequestDemo_OBJC_FILES = PurchaseRequestDemo.m
PurchaseRequestDemo_OBJCFLAGS += -fobjc-arc -fblocks -Wall
PurchaseRequestDemo_INCLUDE_DIRS = -I../Headers
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR)
PurchaseRequestDemo_TOOL_LIBS += -lUDWorkflow -ldispatch

include $(GNUSTEP_MAKEFILES)/tool.make

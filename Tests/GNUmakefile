include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = UDWorkflowTests

UDWorkflowTests_OBJC_FILES = UDWorkflowTests.m
UDWorkflowTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall
UDWorkflowTests_INCLUDE_DIRS = -I../Headers
UDWorkflowTests_LIB_DIRS += -L$(GNUSTEP_OBJ_DIR) -L../$(GNUSTEP_OBJ_DIR)
UDWorkflowTests_BUNDLE_LIBS += -lUDWorkflow -lXCTest -ldispatch
UDWorkflowTests_NEEDS_GUI = no
UDWorkflowTests_PRINCIPAL_CLASS = UDWorkflowTests

include $(GNUSTEP_MAKEFILES)/bundle.make

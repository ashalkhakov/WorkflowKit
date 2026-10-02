# The example processes' delegates and listeners as a plugin bundle, for
# wf-serve to load (WFExampleDelegates.h):
#
#   make -C Examples/Plugins
#   wf-serve -Deployments Examples/Processes -Plugins Examples/Plugins/obj
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ExampleDelegates
ExampleDelegates_OBJC_FILES = WFExampleDelegates.m
ExampleDelegates_PRINCIPAL_CLASS = WFExamplePlugin
ExampleDelegates_OBJCFLAGS += -fobjc-arc -fblocks -Wall
ExampleDelegates_INCLUDE_DIRS = -I../../Headers
ADDITIONAL_LIB_DIRS += -L../../$(GNUSTEP_OBJ_DIR)
ExampleDelegates_BUNDLE_LIBS += -lWorkflowKit

include $(GNUSTEP_MAKEFILES)/bundle.make

# Where wf-serve looks for it: obj/ExampleDelegates.bundle.
after-all::
	@mkdir -p obj && rm -rf obj/ExampleDelegates.bundle && cp -R ExampleDelegates.bundle obj/

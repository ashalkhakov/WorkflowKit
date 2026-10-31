#
# WorkflowLauncher — the app chooser the AppImage and the Windows installer
# open (GNUstep only). A Mac ships WorkflowDesk.app and WorkflowDesigner.app
# separately and has nothing to choose between.
#

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error GNUSTEP_MAKEFILES is not set. Source GNUstep.sh or install gnustep-make.)
endif

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = WorkflowLauncher

WorkflowLauncher_OBJC_FILES = \
	main.m \
	WKLauncherAppDelegate.m

WorkflowLauncher_RESOURCE_FILES = \
	WorkflowLauncher.png

WorkflowLauncher_OBJCFLAGS += -fobjc-arc -Wall -Wextra
WorkflowLauncher_MAIN_MODEL_FILE =

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/application.make
-include GNUmakefile.postamble

# What WorkflowDesigner and its tests are built against, which both
# include after common.make: the engine library at the top of this
# repository, DiagramKit's canvas, ODataKit and XFormsKit with its
# XFormsDesignKit -- installed (the releases .github/pins.env names), or
# built checkouts that ODATAKIT and XFORMSKIT name.
#
#   WKD_INCLUDE_DIRS  the headers' directories
#   WKD_LIB_DIRS      the libraries' directories
#   WKD_LIBS          the libraries
#   WKD_LIBRARY_PATH  what the uninstalled libraries are run from

WKD_DESIGNER := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

ifneq ($(ODATAKIT),)
override ODATAKIT := $(abspath $(ODATAKIT))
endif
export ODATAKIT
ifneq ($(XFORMSKIT),)
override XFORMSKIT := $(abspath $(XFORMSKIT))
XFORMSDESIGNKIT = $(XFORMSKIT)/Sources/XFormsDesignKit
else
# Installed, its headers are laid out as in its tree.
XFORMSDESIGNKIT = $(GNUSTEP_LOCAL_HEADERS)/XFormsDesignKit
endif
export XFORMSKIT

WKD_INCLUDE_DIRS = -I$(WKD_DESIGNER) -I$(WKD_DESIGNER)/../../Headers -I$(WKD_DESIGNER)/../Shared \
	-I$(XFORMSDESIGNKIT) -I$(XFORMSDESIGNKIT)/ThirdParty/DMTabBar
WKD_LIB_DIRS = -L$(WKD_DESIGNER)/../../$(GNUSTEP_OBJ_DIR)
WKD_LIBRARY_PATH = $(WKD_DESIGNER)/../../$(GNUSTEP_OBJ_DIR):
ifneq ($(ODATAKIT),)
WKD_INCLUDE_DIRS += \
	-I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataIncrementalStore/include \
	-I$(ODATAKIT)/Source/OTelKit/include
WKD_LIB_DIRS += -L$(ODATAKIT)/obj
WKD_LIBRARY_PATH := $(WKD_LIBRARY_PATH)$(ODATAKIT)/obj:
endif
ifneq ($(XFORMSKIT),)
WKD_INCLUDE_DIRS += -I$(XFORMSKIT)/Sources -I$(XFORMSKIT)/Sources/XFormsKit
WKD_LIB_DIRS += \
	-L$(XFORMSDESIGNKIT)/XFormsDesignKit.framework/Versions/Current \
	-L$(XFORMSKIT)/XFormsKit.framework/Versions/Current
WKD_LIBRARY_PATH := $(WKD_LIBRARY_PATH)$(XFORMSDESIGNKIT)/XFormsDesignKit.framework/Versions/Current:$(XFORMSKIT)/XFormsKit.framework/Versions/Current:
endif
# DiagramKit: the process diagram's layout (../Shared/WKDEditor.m); and
# DiagramKitUI's canvas, which WKDCanvasView is.
WKD_LIBS = -lWorkflowKit -lDiagramKitUI -lDiagramKit -lODataIncrementalStore -lODataKit -lOTelKit \
	-lXFormsDesignKit -lXFormsKit -lGSUpdater -lCoreData -ldispatch -lgnutls
# Sockets for signing in (../Shared/WDSockets.h): Winsock's on Windows.
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
WKD_LIBS += -lws2_32
WKD_WINDOWS = yes
endif

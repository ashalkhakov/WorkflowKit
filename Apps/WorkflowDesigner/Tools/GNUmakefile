# The designer's tools, for BPMN files kept in the repository
# (Examples/Processes):
#
#   wkd-arrange file.bpmn...         Diagram > Arrange without a window
#   wkd-render file.bpmn out.png     the diagram as a picture (needs a
#                                    display: run it under Xvfb)
#
#   make -C Apps/WorkflowDesigner/Tools
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = wkd-arrange wkd-render
WKD_MODEL = ../WKDXML.m ../WKDDiagram.m ../WKDLayout.m ../WKDEditor.m

wkd-arrange_OBJC_FILES = wkd-arrange.m $(WKD_MODEL)
wkd-arrange_OBJCFLAGS += -fobjc-arc -fblocks -Wall
wkd-arrange_INCLUDE_DIRS = -I..
wkd-arrange_TOOL_LIBS += -ldispatch

wkd-render_OBJC_FILES = wkd-render.m $(WKD_MODEL) ../WKDRenderer.m ../WKDCanvasView.m
wkd-render_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include ../WKDGNUstepCompat.h
wkd-render_INCLUDE_DIRS = -I..
wkd-render_TOOL_LIBS += -lgnustep-gui -ldispatch

include $(GNUSTEP_MAKEFILES)/tool.make

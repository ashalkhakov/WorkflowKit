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
WKD_MODEL = ../../Shared/WKDXML.m ../../Shared/WKDDiagram.m ../../Shared/WKDEditor.m \
	../../Shared/WKDEditor+Canvas.m ../../Shared/WKDEditor+Clipboard.m ../../Shared/WKDEditor+Types.m ../../Shared/WKDEditor+Alignment.m ../../Shared/WKDEditor+Lanes.m

wkd-arrange_OBJC_FILES = wkd-arrange.m $(WKD_MODEL)
wkd-arrange_OBJCFLAGS += -fobjc-arc -fblocks -Wall
wkd-arrange_INCLUDE_DIRS = -I.. -I../../Shared
wkd-arrange_TOOL_LIBS += -lDiagramKit -ldispatch

wkd-render_OBJC_FILES = wkd-render.m $(WKD_MODEL) ../../Shared/WKDRenderer.m ../WKDCanvasView.m
wkd-render_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include ../../Shared/WKDGNUstepCompat.h
wkd-render_INCLUDE_DIRS = -I.. -I../../Shared
wkd-render_TOOL_LIBS += -lDiagramKitUI -lDiagramKit -lgnustep-gui -ldispatch

include $(GNUSTEP_MAKEFILES)/tool.make

# Both compile ../../Shared, whose objects gnustep-make puts in one
# directory for both: under make -j they would make it at once.
wkd-render.all.tool.variables: wkd-arrange.all.tool.variables

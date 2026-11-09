# wf-build, which builds a deployment's directory into the .wfdeployment
# an application ships (WFBuiltDeployment.h), and workflow-deployment.make,
# which runs it in an application's build: both installed with the
# library, as FreeCoreData installs momc and coredata-model.make.
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = wf-build
wf-build_OBJC_FILES = wf-build.m
wf-build_OBJCFLAGS += -fobjc-arc -fblocks -Wall
wf-build_INCLUDE_DIRS = -I../Headers
ADDITIONAL_LIB_DIRS += -L../$(GNUSTEP_OBJ_DIR)
wf-build_TOOL_LIBS += -lWorkflowKit -lCoreData

include $(GNUSTEP_MAKEFILES)/tool.make

after-install::
	$(MKINSTALLDIRS) $(DESTDIR)$(GNUSTEP_MAKEFILES)
	$(INSTALL_DATA) workflow-deployment.make $(DESTDIR)$(GNUSTEP_MAKEFILES)/workflow-deployment.make

after-uninstall::
	rm -f $(DESTDIR)$(GNUSTEP_MAKEFILES)/workflow-deployment.make

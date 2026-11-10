# workflow-deployment.make - build an application's processes with
# WorkflowKit's wf-build as part of any gnustep-make project, as
# coredata-model.make builds its model.
#
# Usage, in a project's GNUmakefile:
#
#     include $(GNUSTEP_MAKEFILES)/common.make
#
#     APP_NAME = MyApp
#     MyApp_OBJC_FILES = ...
#     MyApp_WORKFLOW_DEPLOYMENTS = Processes/orders Processes/billing
#
#     include $(GNUSTEP_MAKEFILES)/workflow-deployment.make
#     include $(GNUSTEP_MAKEFILES)/application.make
#
# Every <target>_WORKFLOW_DEPLOYMENTS entry is a deployment's directory --
# its BPMN files, the decisions and the forms they use -- checked and
# built into <name>.wfdeployment, its name the directory's without an
# extension, and added to that target's resources: what
# -[WFRepositoryService deployBuiltDeploymentsInBundle:error:] deploys
# when the application opens its engine. A deployment the engine would
# refuse fails the build, each problem said as compilers say them. Set the
# variables BEFORE including this file, and include this file BEFORE the
# target's {application,tool,framework,bundle}.make.
#
# wf-build is looked up on PATH; override with WF_BUILD=... (WorkflowKit's
# own tests point it at the tool built in the tree).

WF_BUILD ?= wf-build

_WF_TARGETS = $(FRAMEWORK_NAME) $(APP_NAME) $(TOOL_NAME) $(BUNDLE_NAME) $(LIBRARY_NAME) $(CTOOL_NAME)
_WF_DIR = $(GNUSTEP_OBJ_DIR)/WorkflowDeployments

# A directory's deployment: its name without a trailing slash or an
# extension.
_wf_built = $(_WF_DIR)/$(basename $(notdir $(patsubst %/,%,$(1)))).wfdeployment

define _wf_target_template
$(1)_BUILT_DEPLOYMENTS = $$(foreach _wf_source,$$($(1)_WORKFLOW_DEPLOYMENTS),$$(call _wf_built,$$(_wf_source)))
$(1)_RESOURCE_FILES += $$($(1)_BUILT_DEPLOYMENTS)
_WF_ALL_SOURCES += $$($(1)_WORKFLOW_DEPLOYMENTS)
_WF_ALL_BUILT += $$($(1)_BUILT_DEPLOYMENTS)
endef

$(foreach _wf_target,$(_WF_TARGETS),$(eval $(call _wf_target_template,$(_wf_target))))

# As coredata-model.make does: the first rule here would otherwise become
# make's default goal, and a plain 'make' would build the deployments and
# not the target.
_WF_SAVED_DEFAULT_GOAL := $(.DEFAULT_GOAL)

# Built on every build: a directory's own mtime does not change when a
# file in it is edited, and checking a deployment takes milliseconds.
.PHONY: _wf-force-build
_wf-force-build:

define _wf_rule_template
$(call _wf_built,$(1)): _wf-force-build
	@mkdir -p $(_WF_DIR)
	$$(WF_BUILD) -o $$@ $(patsubst %/,%,$(1))
endef

$(foreach _wf_source,$(sort $(_WF_ALL_SOURCES)),$(eval $(call _wf_rule_template,$(_wf_source))))

# Deployments build before any target does.
before-all:: $(_WF_ALL_BUILT)

after-clean::
	rm -rf $(_WF_DIR)

ifeq ($(_WF_SAVED_DEFAULT_GOAL),)
.DEFAULT_GOAL := all
else
.DEFAULT_GOAL := $(_WF_SAVED_DEFAULT_GOAL)
endif

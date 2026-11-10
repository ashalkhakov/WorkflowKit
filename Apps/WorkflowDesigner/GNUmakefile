# The BPMN and DMN designer's parts on GNUstep (designer.make lists them):
# UDCode's extension (UDCodeExtension/ at the top of this repository) is
# built from them, against the engine library built at the top (`make`)
# and DiagramKit installed (the release .github/pins.env names).
#
#   make          the tools (Tools/: wkd-arrange, wkd-render)
#   make check    the parts' tests (Tests/): the models, their edits, the
#                 layout, that the engine takes what they write, and the
#                 XIBs loaded and connected
include $(GNUSTEP_MAKEFILES)/common.make

include designer.make

export LD_LIBRARY_PATH := $(WKD_LIBRARY_PATH)$(LD_LIBRARY_PATH)
export PATH := $(WKD_LIBRARY_PATH)$(PATH)

.PHONY: all install clean check
all:
	$(MAKE) -C Tools

install:

clean:
	$(MAKE) -C Tools clean
	$(MAKE) -C Tests clean

# The tests open windows: under xvfb-run where there is no display, as
# ORMKit's designer tests are.
XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))

check:
	$(XVFB) $(MAKE) -C Tests run-tests

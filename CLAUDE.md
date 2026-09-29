# UDWorkflow

A BPMN 2.0 workflow engine in Objective-C (ARC, libdispatch) for GNUstep and
Cocoa. `Headers/` and `Source/` are the engine library, `Examples/` the demo
tools, `Tests/` the XCTest suite. `UDWorkflow-BPMN-Subset.md` is the scope:
what the engine loads, persists and fires, and what it rejects.

## Build against the patched GNUstep, never a distro one

The stack comes from `../gnustep-patches`, which this machine's GNUstep
projects share, built by its `Scripts/build-gnustep.sh`. CI checks that
repository out at the commit pinned by `GNUSTEP_PATCHES_REF` in
`.github/workflows/ci.yml` and builds only what the engine needs:
`libobjc2 libdispatch tools-make libs-base tools-xctest`. The designer will
add `libs-gui libs-back eau` when it exists.

If a bug here turns out to be GNUstep's, work in that repository and read its
`CLAUDE.md` first: reproduce in the docker container, fix, turn the
reproduction into a test in GNUstep's own suite, and push it there.

## Building and testing

```sh
make                 # obj/libUDWorkflow.so
make examples        # Examples/obj/PurchaseRequestDemo
make test            # the library, then the XCTest bundle under xctest
```

Locally that runs in the `ois-dev` container, which has the stack in
`/w/build`: `.tools/gnustep.sh make test` copies this checkout in and runs
the command there. Against a prefix of your own, source
`$PREFIX/System/Library/Makefiles/GNUstep.sh` and put `$PREFIX/lib` on
`LD_LIBRARY_PATH` first: libobjc2 and libdispatch live there, outside the
roots the gnustep layout knows.

## macOS

`UDWorkflow.xcworkspace` holds `UDWorkflow.xcodeproj`: the `UDWorkflow`
framework, the `UDWorkflowTests` bundle and the `PurchaseRequestDemo` tool,
with shared settings in `Xcode/Configs` (the same as ODataKit's). The project
is generated from the GNUmakefiles' source lists, so after adding a file run
`python3 .tools/genxcodeproj.py` rather than editing `project.pbxproj`.

```sh
xcodebuild -workspace UDWorkflow.xcworkspace -scheme UDWorkflow \
    -destination 'platform=macOS' test
```

## Portability rules the build has already caught

- Dispatch objects are Objective-C objects only on Apple. On GNUstep
  `OS_OBJECT_USE_OBJC` is 0, so a `dispatch_queue_t` cannot be `strong` or go
  into a collection. Properties use `UD_DISPATCH_PROPERTY` with setters that
  retain, owners release with `UDDispatchRelease`, and a timer source goes
  into the engine's table inside a `UDTimerHandle`.
- tools-xctest's `XCTAssertEqualWithAccuracy` needs floating-point
  arguments: write `10.0`, not `10`.

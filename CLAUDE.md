# WorkflowKit

A BPMN 2.0 workflow engine in Objective-C (ARC, libdispatch) for GNUstep and
Cocoa. `Headers/` and `Source/` are the engine library, `Examples/` the demo
tools, `Tests/` the XCTest suite. `WorkflowKit-BPMN-Subset.md` is the scope:
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

## Design reference and the clean-room rule

The engine follows Camunda 7's execution model: `docs/execution-model.md`
is the design, and Camunda's documented behaviour settles open questions.
WorkflowKit is meant to be LGPL-licensed and Camunda 7 is Apache-2.0, so work
from its public documentation and the BPMN spec only. Never read, copy or
paraphrase its source code, SQL or documentation text into this repository.

## Building and testing

```sh
make                 # obj/libWorkflowKit.so
make examples        # Examples/obj/PurchaseRequestDemo
make test            # the library, then the XCTest bundle under xctest
```

Locally that runs in the `ois-dev` container, which has the stack in
`/w/build`: `.tools/gnustep.sh make test` copies this checkout in and runs
the command there. Against a prefix of your own, source
`$PREFIX/System/Library/Makefiles/GNUstep.sh` and put `$PREFIX/lib` on
`LD_LIBRARY_PATH` first: libobjc2 and libdispatch live there, outside the
roots the gnustep layout knows.

The store is Core Data: FreeCoreData on GNUstep (installed in `ois-dev`,
built from the pinned `FREECOREDATA_REF` in CI), Apple's on macOS. Its model
is `Model/WorkflowKit.xcdatamodeld`, compiled by `momc`; edit it there, never
build a model in code. Uninstalled, the library finds the model through
`WORKFLOWKIT_MODEL` (`make -C Examples run` sets it) or a copy in the calling
bundle (the test bundle carries one).

The tests run on every store: each area's tests are in `Tests/WF*Tests.inc`,
and each backend's file (`WFInMemoryTests.m`, `WFSQLiteTests.m`,
`WFPostgreSQLTests.m`, `WFMySQLTests.m`) gives every area a class that
includes them; `Tests/WFTestCase.h` says why they are included and not
inherited. A new area is a new `.inc` and one class in each backend's file.
The server backends are built in when their URLs are given, through
FreeCoreData's stores installed for them, and each test works in a schema of
its own:

```sh
.tools/gnustep.sh make test \
    WORKFLOWKIT_TEST_POSTGRES_URL=postgresql://postgres:test@172.17.0.4/workflowkit_test \
    WORKFLOWKIT_TEST_MYSQL_URL=mysql://root:test@172.17.0.3/coredata_test
```

In `ois-dev` those are the `cdpgtest` and `cdmytest` containers (their
addresses change when docker restarts: `docker inspect` them); CI starts
its own.

The OData API (`OData/`, `WorkflowKitOData`) is built only against
ODataKit: `ODATAKIT` names a built checkout (`/w/odatakit-*` in
`ois-dev`), or `odata=yes` finds an installed one. Its tests are the
`WFOData*Tests` classes, compiled in with it:

```sh
.tools/gnustep.sh make test ODATAKIT=/w/odatakit-master
```

CI builds ODataKit at the commit pinned by `ODATAKIT_REF` in
`.github/workflows/ci.yml`, and the OData API with it. It is not built on
macOS yet.

## macOS

`WorkflowKit.xcworkspace` holds `WorkflowKit.xcodeproj`: the `WorkflowKit`
framework, the `WorkflowKitTests` bundle and the `PurchaseRequestDemo` tool,
with shared settings in `Xcode/Configs` (the same as ODataKit's). The project
is generated from the GNUmakefiles' source lists, so after adding a file run
`python3 .tools/genxcodeproj.py` rather than editing `project.pbxproj`.

```sh
xcodebuild -workspace WorkflowKit.xcworkspace -scheme WorkflowKit \
    -destination 'platform=macOS' test
```

## Portability rules the build has already caught

- Dispatch objects are Objective-C objects only on Apple. On GNUstep
  `OS_OBJECT_USE_OBJC` is 0, so a `dispatch_queue_t` cannot be `strong` or go
  into a collection. Properties use `WF_DISPATCH_PROPERTY` with setters that
  retain, owners release with `WFDispatchRelease`, and a timer source goes
  into the engine's table inside a `WFTimerHandle`.
- libdispatch on GNUstep drains a worker thread's autorelease pool only when
  the thread goes idle, not after each block as Apple's does, so whatever a
  busy engine's blocks autorelease - command contexts, and through their
  after-commit blocks the engine and its store's connection - lives on.
  Every block the engine dispatches runs in a pool of its own (`WFAsync`),
  and so must a test's.
- tools-xctest's `XCTAssertEqualWithAccuracy` needs floating-point
  arguments: write `10.0`, not `10`.
- gnustep-base's `NSPredicate` parser takes only object arguments: pass
  numbers as `%@` with an `NSNumber`, never `%ld` or `%d`.
- gnustep-base's `+predicateWithFormat:` raises on a nil argument; check
  ids before building a predicate from them.
- Core Data attribute names must not be selectors `NSNumber` or `NSString`
  already has (`doubleValue`, `longValue`, ...): a message sent to `id`
  then has two signatures and the compiler refuses it.
- gnustep-base answers NO from
  `+[NSPropertyListSerialization propertyList:isValidForFormat:]` for valid
  dictionaries; the engine checks property-list values itself.

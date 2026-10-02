# WorkflowKit

A BPMN 2.0 workflow engine in Objective-C (ARC, libdispatch) for GNUstep and
Cocoa. `Headers/` and `Source/` are the engine library, `OData/` its API,
`Server/` `wf-serve`, `Apps/` the desktop apps, `Examples/` the demo tools
and `Examples/Processes` the example BPMN processes, one deployment each,
which `Tests/WFExamplesTests.inc` runs (see its README),
`Tests/` the XCTest suite. `WorkflowKit-BPMN-Subset.md` is the scope:
what the engine loads, persists and fires, and what it rejects.

## Build against the patched GNUstep, never a distro one

The stack comes from `../gnustep-patches`, which this machine's GNUstep
projects share, built by its `Scripts/build-gnustep.sh`. CI checks that
repository out at the commit pinned by `GNUSTEP_PATCHES_REF` in
`.github/workflows/ci.yml` and builds what the engine and WorkflowDesk need:
`libobjc2 libdispatch tools-make libs-base libs-gui libs-back libs-corebase
libs-opal tools-xctest` (CoreBase and Opal for XFormsKit). `ois-dev` has
them all.

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
build a model in code. Its entities' classes are generated from it as the
library builds -- by Xcode, and on GNUstep by FreeCoreData's
`coredata-model.make` (`WorkflowKit_COREDATA_CODEGEN`) -- so use their typed
properties, not `valueForKey:`. Every entity is Codegen Class Definition but
`WFExecution`, Category/Extension: its class, with behaviour of its own, is
`Source/WFExecutionEntity.h`. `Source/WFEntities.h` imports them all. Uninstalled, the library finds the model through
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
.tools/gnustep.sh make test ODATAKIT=/w/odatakit-host
```

CI builds ODataKit at the commit pinned by `ODATAKIT_REF` in
`.github/workflows/ci.yml`, and the OData API with it.

The engine's server is `WFServerApplication` (`OData/WFODataServer.h`, in
WorkflowKitOData): an application of ODataKit's HTTPServerKit that opens a
store, deploys a directory, loads plugins, runs the job executor and serves
the OData API as its module. HTTPServerKit adds what every server has --
who is asking, health and readiness, metrics, the access log, CORS, and
OpenTelemetry traces (OTelKit) -- from settings its header lists; the
header lists the engine's own. An app that needs routes or APIs beside
OData subclasses it, or adds an `HSModule`; never write another HTTP
server. `wf-serve` (`Server/`) is `HSMain` with it and nothing more; its
example configuration (`Server/Examples/server.plist`, which `make -C
Server run` and the Xcode scheme use) deploys the purchase request and
every process in `Examples/Processes`, with `Examples/Plugins`; with
`postgresql=yes` and `mysql=yes` it has FreeCoreData's server stores.
`make -C Server check` drives a purchase request through it with curl and
asks for its health, readiness and metrics:

```sh
.tools/gnustep.sh "make server ODATAKIT=/w/odatakit-host && make -C Server check ODATAKIT=/w/odatakit-host"
```

On macOS it is the `wf-serve` scheme, which links ODataKit's HTTPServerKit
and OTelKit frameworks. The apps trace too: given OpenTelemetry's
`OTEL_EXPORTER_OTLP_ENDPOINT`, their requests are client spans whose
traces wf-serve's spans continue (`Apps/Shared/WDTracing.h`). The engine traces through
`WFProcessEngine.tracer` (`WFTracer`, which OTelKit's `OTTracer` is,
without the engine linking it): a command is a span named for the service
method that ran it, so a service runs its commands with
`wf_runCommand:_cmd of:self body:...`.

The API requires a signed-in caller with the scopes its sets and actions
declare (`OData/WFODataService.h`). Without an identity provider,
`-DevelopmentUser` signs every request in as one user with every scope:
the example config and the check use it; never expose such a server.

## Apps

`Apps/WorkflowDesk` is the task list and operations app (see its README).
It is a client of `wf-serve` and nothing else. It opens the engine's own model
on its `API` configuration over ODataIncrementalStore, with plain managed
objects in place of the engine's classes, and it never links the engine.
Its windows are XIBs with Cocoa Bindings, and its forms are XFormsKit's.

- It builds with `make ODATAKIT=... XFORMSKIT=...`, and `make check` runs its
  tests, which need no display.
- To see it on GNUstep, run it in `ois-dev` under `Xvfb` and drive it with
  `xdotool`; never take screenshots of the host's screen. On GNUstep the
  command key is Alt, so select-all is `alt+a`.
- gnustep-gui differs from AppKit in ways the app already allows for:
  - it ends a window's sheet only through `-[NSApp endSheet:]`;
  - it has no `NSAlert` accessory view;
  - it shows a stopped progress indicator;
  - it does not select an array controller's first row;
  - it quits the app the moment the last window closes, even between
    one window and the next.

`Apps/WorkflowDesigner` is the BPMN designer (see its README): a document
app whose document is the BPMN XML, edited in place through `WKDEditor`,
with the engine's `WFBpmnReader` saying after each change whether it runs.
It links the engine, and deploys to and opens from a `wf-serve` through
the connection WorkflowDesk has: `Apps/Shared` holds what both apps
compile -- the session, sign-in and connect window, and the BPMN document
model, editor, layout and renderer (`WKD*`), with which WorkflowDesk's
operations window draws a process and where its instances are -- so the
designer builds with `ODATAKIT=...` too. Its forms open in a window of its own through
XFormsKit's XFormsDesignKit, the XForms Designer's editor as a framework
(`XFDDocument`, its second document type), so it builds with
`XFORMSKIT=...` as well, after `make designkit` in that checkout; its tab
bars are the DMTabBar that framework carries. Its document model and editor are Foundation only, and
its tests (`make check`) need no display. A diagram's shapes link to one
another weakly, so keep the diagram they came from while using them: Apple
frees it at once, GNUstep later.

XFormsKit's frameworks carry no headers on either platform, so their users
include them from `../XFormsKit/Sources` (and `Sources/XFormsDesignKit`). On GNUstep it needs libs-corebase
and libs-opal in the stack.

## macOS

`WorkflowKit.xcworkspace` holds `WorkflowKit.xcodeproj`: the `WorkflowKit`
framework, the `WorkflowKitOData` framework, the `WorkflowKitTests` bundle
(the OData API's tests included), the `PurchaseRequestDemo` and `wf-serve`
tools, and the `WorkflowDesk` and `WorkflowDesigner` apps with their tests, with shared settings in
`Xcode/Configs` (the same as ODataKit's). It also holds
`../ODataKit/ODataKit.xcodeproj` and `../XFormsKit/XFormsKit.xcodeproj`, the
checkouts beside this one, whose frameworks the OData API and the app link
and Xcode builds first. The project
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
- gnustep-base's `-[NSBundle loadAndReturnError:]` was a stub answering NO,
  so no plugin bundle loaded (`-loadPluginsInDirectory:error:`, wf-serve's
  `-Plugins`); gnustep-patches' `bundle-load-and-return-error` fixes it.
  The tests compile the example delegates in rather than load them.

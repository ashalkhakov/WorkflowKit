# Processes in an application's life cycle

An application's processes are part of its source, like its data model:
edited with it, built with it, tested with it, shipped in it and deployed
when it starts. Nothing is deployed from an editor. This is how a Core Data
model goes from its `.xcdatamodeld` through `momc` to the `.momd` an
application loads, and WorkflowKit follows it step by step.

| Step | Core Data | WorkflowKit |
|---|---|---|
| Source | `Model.xcdatamodeld` | a deployment's directory: its `.bpmn` files, the `.dmn` files and the forms (`.xhtml`) they use |
| Edit | Xcode, Model Builder, UDCode's Core Data extension | UDCode's BPMN and DMN extension ([UDCODE.md](UDCODE.md)) |
| Build | `momc` into `Model.momd` | `wf-build` into `<name>.wfdeployment` |
| Ship | in the application's resources | in the application's resources |
| Load | `NSManagedObjectModel` from the bundle | `-deployBuiltDeploymentsInBundle:error:` when the engine opens |
| Test | the model from the test bundle | `+testEngineWithDeploymentsInBundle:error:` |

## The source

A deployment is a directory in the application's repository, as
`Examples/Processes/loan-application` is:

```
Processes/loan-application/
  loan-application.bpmn      the process
  risk.dmn                   the decisions its business rule tasks evaluate
  underwrite.xhtml           the form its user task names
```

A form is the one a task names as
`camunda:formKey="embedded:deployment:underwrite.xhtml"`, and a decision the
one a business rule task names by key (`camunda:decisionRef`). The editor
makes both beside the process (Edit Form…, Edit Decision…), and its Issues
navigator says, as you edit, what the engine would refuse the deployment
for: what the next step would fail on.

## Building

`wf-build` checks a deployment's directory as deploying it would and, when
the engine would take it, writes it as a `.wfdeployment`:

```sh
wf-build [-name NAME] [-o OUTPUT.wfdeployment] DIRECTORY
```

The name is the directory's, without an extension, unless `-name` gives
another. When the engine would refuse it, nothing is written and every
problem is printed as compilers print theirs, so an editor or a CI log
links each one to its line:

```
loan-application.bpmn:42:7: error: underwrite: form underwrite.xhtml is not in the deployment
```

A `.wfdeployment` is a directory (`WFBuiltDeployment.h`): `Deployment.plist`,
which says what it is -- its name, its resources, the processes and
decisions in them, the WorkflowKit that built it -- and `Resources/`, the
files as they were checked.

`wf-build` and the make fragment below are installed with the library
(`make install`), as FreeCoreData installs `momc` and `coredata-model.make`.

**On GNUstep**, a target names its deployments in its GNUmakefile, and
`workflow-deployment.make` builds each into its resources:

```make
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = MyApp
MyApp_OBJC_FILES = ...
MyApp_WORKFLOW_DEPLOYMENTS = Processes/orders Processes/billing

include $(GNUSTEP_MAKEFILES)/workflow-deployment.make
include $(GNUSTEP_MAKEFILES)/application.make
```

A deployment the engine would refuse fails the build. `WF_BUILD` names
another `wf-build` than the one on the `PATH`.

**In Xcode**, a Run Script build phase does the same, after the target's
resources are copied, with `wf-build` from wherever it is built or
installed:

```sh
wf-build -o "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/orders.wfdeployment" \
  "$SRCROOT/Processes/orders" || exit 1
```

WorkflowKit's own test bundle builds the example deployments this way,
with the `wf-build` its project builds (`.tools/genxcodeproj.py`'s "Build
Deployments" phase). Let the phase run every time: a directory's date does
not change when a file in it does.

## Deploying when the application starts

The application deploys what it ships when it opens its engine:

```objc
WFProcessEngine *engine = ...;   // opened on its store
NSError *error = nil;
if ([engine.repositoryService deployBuiltDeploymentsInBundle:[NSBundle mainBundle] error:&error] == nil) {
	// a deployment was refused: error says which, and why
}
```

Every `.wfdeployment` in the bundle's resources is deployed, in name order,
unless the latest deployment of that name is the same byte for byte. So
the first launch deploys everything, a later launch of the same build
deploys nothing, and a launch of a build whose processes changed deploys
them again:

- every process and decision in a changed deployment gets the next version,
  even those whose own file did not change;
- new instances start on the latest version, and the old versions' timer
  and message starts are replaced by the new version's;
- running instances stay on the version they started on. Moving them is
  `-[WFRuntimeService migrateProcessInstances:plan:error:]`, which nothing
  runs at deploy;
- call activities and business rule tasks follow their binding: `latest`
  (the default), `deployment` or `version`.

What happens to a process no longer shipped, whether a launch deploys all
or nothing, and launches racing against one database are not decided yet:
[WorkflowKit#3](https://github.com/ashalkhakov/WorkflowKit/issues/3).

**wf-serve** deploys built deployments too: its `Deployments` setting
(`OData/WFODataServer.h`) names directories, each holding deployments'
directories or `.wfdeployment`s, or `.wfdeployment`s themselves, deployed
the same way when it starts. `make -C Server check` runs the purchase
request as `wf-build` built it.

## Testing

An application's tests run its processes as it ships them: the test
bundle builds the same deployments into its own resources
(`MyAppTests_WORKFLOW_DEPLOYMENTS`, or the Xcode phase), and each test opens
an engine on them:

```objc
WFProcessEngine *engine = [WFProcessEngine testEngineWithDeploymentsInBundle:[NSBundle bundleForClass:[self class]]
                                                                       error:&error];
```

It is on a store in memory, with full history, its job executor stopped (a
test runs jobs itself), and the bundle's deployments deployed.

## Checking in code

What `wf-build`, the editor and the repository check is one public class:
`+[WFDeploymentChecker problemsInResources:]` (`WFDeploymentChecker.h`)
returns what deploying the resources would be refused for, as `WFProblem`s
with the file, the element, and the line and column. The repository
refuses a deployment for the same reasons, from the same code.

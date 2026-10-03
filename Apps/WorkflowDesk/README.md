# WorkflowDesk

The desktop client of a WorkflowKit server (`wf-serve`), for macOS and
GNUstep. It reads and changes the engine's state through the OData API
only, and it has two windows:

- **Tasks** lists the tasks the server shows you: yours, and those offered
  to you. From there you can claim or give back a task, open a task's
  form, or start a process.
- **Operations** shows the deployed process definitions, each one's
  instances -- running ones, finished ones from the engine's history, or
  all, as the Show menu above them says -- and for the instance selected:
  - the process's diagram, its pools and lanes too, with where the
    instance is on it, as Camunda's
    Cockpit shows it: the activities it is in now outlined in blue (with
    how many tokens, when more than one), those it has finished and the
    flows between them shaded green, and incidents as red badges. **All
    running instances** shows, instead, how many of the definition's
    instances are at each activity. A click on an activity says what is
    there in the status line. A process deployed without a diagram is laid
    out as the designer lays one out;
  - its variables, the activities it has been through, its incidents and
    its jobs; for a finished instance its variables' last values and the
    incidents it had, from the history;
  - controls to suspend and resume a definition or a running instance,
    cancel a running instance, retry a failed job, retry what an open
    incident is about (a failed job or external task, given an attempt
    again, which resolves the incident), and deploy BPMN, DMN and form
    files.

Forms are the engine's XForms documents, rendered by XFormsKit. The
server holds the instance a form opens with; the app puts it into the
document, checks the required and invalid fields, and sends the instance
back as the form leaves it. Return in a field commits it, as it does in any
XForms form; the form is sent with its button, or ⌘Return.

| Where | What |
| --- | --- |
| `../Shared/WDSession` | Core Data over `ODataIncrementalStore`, with the engine's own model on its `API` configuration. Fetches and operations run on a private-queue context; the windows bind to the main queue's context. |
| `../Shared/WDSignIn` | OpenID Connect sign-in: the authorization code flow with PKCE, in the system browser, back to a loopback redirect. It is the store's credential provider. |
| `../Shared/WDConnectWindowController` | The connect window, which WorkflowDesigner opens too. |
| `WDFormDocument` | Puts the task's instance into its form. |
| `WDDiagramView` | The diagram with where instances are, drawn by the designer's renderer (`../Shared/WKDRenderer`) from its document model (`../Shared/WKDDiagram`). |
| `Resources/*.xib` | The windows. Each list is an `NSArrayController` with Cocoa Bindings. |

## Running it

Start a server, for example `make -C Server run` at the top of this
repository on GNUstep, or the `wf-serve` scheme in Xcode: either deploys
the purchase request and every example process (`Examples/Processes`),
with the example plugin they call. Then open the
app and connect to the service root the server prints, such as
`http://127.0.0.1:8080/api/`. To connect at launch, give the address on
the command line:

    WorkflowDesk -WDServiceAddress http://127.0.0.1:8080/api/

The example server runs with `-DevelopmentUser`, which signs every request
in as one user, so no sign-in is needed.

## Signing in

A server started with `-JWTIssuer` says so in its `$metadata`. The app then
signs you in with the issuer before it reads anything. To set this up:

1. Register WorkflowDesk at the identity provider as a public client: no
   secret, the authorization code grant, and PKCE.
2. Allow the redirect URI `http://127.0.0.1/callback`. The app listens on a
   port it picks for each sign-in, which RFC 8252 lets a provider accept for
   loopback redirects.
3. Enter the client ID in the connect window.

The app asks for `openid`, the scopes the server requires, and the scopes
in the `WDScopes` user default. That default covers the API's scopes and
`offline_access`, for a refresh token:

    defaults write WorkflowDesk WDScopes "profile offline_access Tasks.Work Operations.Read"

The access token goes to the server as `Authorization: Bearer`. When the
server answers 401, the app uses the refresh token, or signs you in again.

## Building

**On GNUstep**, the app needs gnustep-gui, FreeCoreData installed (with
`momc`), and built checkouts of ODataKit and XFormsKit. XFormsKit in turn
needs libs-corebase and libs-opal.

    make ODATAKIT=../../../ODataKit XFORMSKIT=../../../XFormsKit
    make ODATAKIT=... XFORMSKIT=... run
    make ODATAKIT=... check        # the tests: signing in, and forms

**On macOS**, use the `WorkflowDesk` scheme of `WorkflowKit.xcworkspace`.
The workspace builds ODataKit and XFormsKit from their own projects,
which must be checked out beside this repository.

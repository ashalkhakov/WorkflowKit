# WorkflowDesk

The desktop client of a WorkflowKit server (`wf-serve`), for macOS and
GNUstep. It reads and changes the engine's state through the OData API
only, and it has two windows:

- **Tasks** lists the tasks the server shows you: yours, and those offered
  to you. From there you can claim or give back a task, open a task's
  form, or start a process.
- **Operations** shows the deployed process definitions, each one's running
  instances, and for the instance selected:
  - its variables, the activities it has been through, its incidents and
    its jobs;
  - controls to suspend and resume a definition or an instance, cancel an
    instance, retry a failed job, and deploy BPMN, DMN and form files.

Forms are the engine's XForms documents, rendered by XFormsKit. The
server holds the instance a form opens with; the app puts it into the
document, checks the required and invalid fields, and sends the instance
back as the form leaves it.

| Where | What |
| --- | --- |
| `WDSession` | Core Data over `ODataIncrementalStore`, with the engine's own model on its `API` configuration. Fetches and operations run on a private-queue context; the windows bind to the main queue's context. |
| `WDSignIn` | OpenID Connect sign-in: the authorization code flow with PKCE, in the system browser, back to a loopback redirect. It is the store's credential provider. |
| `WDFormDocument` | Puts the task's instance into its form. |
| `Resources/*.xib` | The windows. Each list is an `NSArrayController` with Cocoa Bindings. |

## Running it

Start a server, for example `make -C Server run` at the top of this
repository on GNUstep, or the `wf-serve` scheme in Xcode. Then open the
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

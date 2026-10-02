# WorkflowDesigner

The BPMN process designer for WorkflowKit, for macOS and GNUstep. It opens,
draws, edits and saves `.bpmn` files: Camunda Modeler's files and the
engine's own.

The document is the BPMN XML itself. Edits change it in place, and saving
writes it back as it was apart from what you changed. Whatever the designer
doesn't draw is kept: documentation, `camunda:` extensions, form fields,
annotations, other processes.

After every change the engine's own BPMN reader reads the process. The
status line says either that the engine runs it, or why it doesn't: "service
tasks are external tasks (camunda:type="external" with a camunda:topic) or
run a delegate", for instance.

## The window

Three panes, as RDLKit's and XFormsKit's designers have them:

- **Left**, behind three tabs:
  - **Outline:** the process with its nodes, a subprocess's contents and an
    activity's boundary events beneath them, and each node's outgoing flows.
  - **Insert:** the palette.
  - **Problems:** what the engine says about the process.
- **Centre:** the canvas.
- **Right**, behind two tabs:
  - **Element:** the inspector for what is selected.
  - **Process:** the process's own settings.

The outline, the canvas and the inspector share one selection. View ▸
Outline, Insert, Problems, Element and Process (⌘1 to ⌘5) bring each tab
forward.

## The inspector

The inspector shows an element's properties in sections, according to what
the element is:

- **Every element:** General (id, name, documentation).
- **User task:** Assignment (assignee, candidate users and groups, due and
  follow-up dates, priority) and Form (form key, form handler).
- **Service or send task:** Implementation: an external task on a topic,
  or a delegate by class or expression.
- **Business rule task:** Decision (decision, binding, version, result
  variable, how the result maps).
- **Script task:** Action (`wf:action`).
- **Call activity:** Called Process (process key, binding, version).
- **Event:** its definition's details: a timer's kind and value; a message
  or signal by name; an error or escalation by its code; a condition. A
  boundary event can also be made non-interrupting.
- **Activity:** Multi-instance (parallel or sequential, collection, element
  variable, cardinality, completion condition).
- **Every node:** Continuation (asynchronous before and after, exclusive,
  and for activities the retry cycle).
- **Sequence flow:** its condition, and whether it is its source's default.
- **Process:** id, name, executable, starter groups and users, history
  days, task priority.

A field writes when you leave it or press Return. A check box or pop-up
writes when used. Each write is one undoable change.

### Expressions

Fields the engine reads as expressions are coloured as you type. These
are:

- **Expressions:** conditions, a loop's collection, cardinality and
  completion condition, and a conditional event's condition. They are
  FEEL, unless written as `${...}`, which is the Camunda 7 subset.
- **Attributes that may hold one:** assignee, candidates, dates, priority,
  a timer's value and a delegate expression. They are literal text, unless
  written as `${...}` or begun with `=`.

The engine's own lexer and parser do the work, so the colours and the
checks are the engine's. Names, keywords, functions, numbers, strings,
dates and durations, operators and comments each have a colour. Where the
engine would stop reading is underlined in red, and the status line says
what it expected there. The field's tool tip says the same.

- **Ids:** changing an id updates every reference to it.
- **References:** naming a message, signal, error or escalation makes its
  definition at the top of the file, or reuses the one already there.
- **Names:** values are written under the attribute and element names the
  engine reads.

The properties are declared once each in `WKDProperties`, which says where
each value lives in the XML. Their tests check the engine reads what they
write.

## Using it

- **Palette** (the Insert tab): click a tool, then click the canvas to place it. Events,
  tasks, a subprocess, gateways and boundary events are all there. A node
  placed inside a subprocess belongs to it. A boundary event placed near a
  task's or subprocess's edge attaches to it there.
- **Select:** click a shape or a flow. Shift-click adds to the selection,
  and dragging on empty canvas draws a band around shapes.
- **Move:** drag the selection. A subprocess moves with its contents, and
  an activity with its boundary events. A boundary event dragged alone
  slides along its activity's edge. Flows are routed again with right-angle
  bends.
- **Connect:** select a shape and drag from the blue handle at its top
  right onto another. On macOS, Option-dragging from a shape does the same.
  The designer refuses flows the engine would: out of an end event, into a
  start or boundary event, or across a subprocess's border.
- **Resize:** a selected subprocess has a handle at its bottom right.
- **Delete:** Backspace or Delete removes the selection. A node takes its
  flows, its contents and its boundary events with it, and references to it
  are cleaned up: `incoming`, `outgoing` and a gateway's `default`.
- **Diagram ▸ Arrange** lays the whole process out afresh, left to right.
  A file without a diagram, such as the engine's example deployment, is laid
  out like this when it opens.
- **Undo and Redo** cover every change. **View** zooms in and out.

## The server

The designer connects to a `wf-serve` as WorkflowDesk does, through the
same connect window and sign-in. **Server ▸ Connect…** chooses the server.
Deploying or opening from a server before connecting shows the connect
window first.

- **Server ▸ Deploy** (⇧⌘D) sends the process to the server. Forms the
  process names as `camunda:formKey="embedded:deployment:<name>"` go with
  it, read from beside the file. A missing form stops the deployment. The
  status line then gives the version the server holds. An unchanged
  process keeps the version it had.
- **File ▸ Open from Server…** (⇧⌘O) lists every deployed version of every
  process definition. Opening one reads its BPMN as it was deployed into a
  new, unsaved document named after its key and version, such as
  "purchase v2". Deploying it again keeps its resource name. A deployed
  file without a diagram is laid out as it opens.

## Building

**On GNUstep**, build the engine library at the top of the repository with
`make` first. The designer also needs FreeCoreData installed (with `momc`)
and a built ODataKit checkout, as WorkflowDesk does. Then, in this
directory:

    make ODATAKIT=...         # WorkflowDesigner.app
    make ODATAKIT=... run     # open it
    make ODATAKIT=... check   # the tests: the document model, edits, layout,
                              # deployments, and that the engine reads what
                              # the designer writes

**On macOS**, use the `WorkflowDesigner` scheme of `WorkflowKit.xcworkspace`.

## Inside

| Where | What |
| --- | --- |
| `WKDDiagram` | What the canvas draws, read from the XML: shapes with their bounds, subprocess and boundary host, and flows with their waypoints. It is read again after every change. |
| `WKDEditor` | Every change. It keeps elements, references and the BPMN diagram information consistent. Each change is one undo step that restores the document as it was. |
| `WKDLayout` | A layered (Sugiyama) layout, adapted from CoreWF's. |
| `WKDProperties` | The inspector's properties: where each value lives in the XML, how to read and write it, and which hold expressions. |
| `WKDExpressionField` | The expression field and the text storage that colours it, ported from the XForms Designer's XPath field, over the engine's `+[WFFeelExpression tokensOfText:place:]` and `+problemInText:place:`. |
| `WKDWindowController`, `WKDOutline`, `WKDInspectorView`, `WKDPane` | The three panes, ported from RDLKit's designer, with its DMTabBar (`ThirdParty/`). |
| `WKDDeployment` | What a deployment sends: the process and the forms it embeds. |
| `WKDAppDelegate`, `WKDServerProcessesController` | The server connection, shared by every window, and the Open from Server window. The connection itself is WorkflowDesk's (`../Shared`). |
| `WKDCanvasView`, `WKDPaletteView`, `WKDRenderer` | Drawing and editing, adapted from CoreWF's graph view. BPMN notation is drawn with `NSBezierPath`, with no images. |

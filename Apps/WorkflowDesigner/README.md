# WorkflowDesigner

The BPMN process designer for WorkflowKit, for macOS and GNUstep. It opens,
draws, edits and saves `.bpmn` files: Camunda Modeler's files and the
engine's own. It also edits the DMN decisions a process's business rule
tasks evaluate (`.dmn`), and its forms (`.xhtml`).

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

### Tables

What an element has a list of is a table, a row an entry:

- **Input/Output** (tasks, subprocesses, call activities): input and
  output parameters, a variable and its value. A value written as a
  `camunda:list` or `camunda:map` shows as the FEEL it means, and stays a
  list or map unless it is edited.
- **Listeners** (every node, flow and the process; task listeners on user
  tasks): when, and the delegate called, by class or by name. Under the
  table, the selected listener's fields.
- **Called Process:** the variables passed in (one by name, all, or the
  business key) and passed back.
- **Implementation** (service and send tasks): a delegate's fields, text or
  an expression.
- **Form** (user tasks and start events): the fields the engine makes a
  form of (`camunda:formData`) -- id, label, type, default, required and
  read-only -- and under it the selected field's other constraints, an
  enum's values, and its properties. A start form also names the field
  whose value is the business key.

### Forms

A form the process names as `camunda:formKey="embedded:deployment:<name>"`
is an XForms document kept beside the `.bpmn` file and deployed with it.
**Edit Form…** (the button in the Form section, or Diagram ▸ Edit Form…, ⌘E)
opens the selected task's or start event's form in a window of its own,
in this app: the XForms Designer's editor, which XFormsKit's
XFormsDesignKit framework is, with its outline, live preview and
inspector, and its Form menu beside Diagram. A form is a document like the
process, saved and undone on its own; `.xhtml` files open in it from
File ▸ Open too. When there is no such form yet, it is made first, from
the fields as the engine makes their form, written beside the process,
and named in the form key: one undoable change. The process must have
been saved, so that there is somewhere beside it.

Deploy sends a form that is open as it stands in its window, saved or not.

**+** adds a row and **−** removes the selected one. Double-click a cell to
edit it, and Return or leaving it writes it. Each of these is one undoable
change, and the rows not touched are written back as they were. A value
the engine reads as an expression is coloured, and checked as it is
typed, as an expression field is.

### Decisions

A business rule task names its decision by key (`camunda:decisionRef`).
The decision is defined in a DMN file kept beside the `.bpmn` file and
deployed with it. **Edit Decision…** (the button in the Decision section,
or Diagram ▸ Edit Decision…, ⇧⌘E) opens the DMN file beside the process
that defines the selected task's decision, with that decision shown. When
no file defines it, the designer makes one named after the decision, with
a table for it, and when the task names no decision yet, it names this
one: one undoable change. `.dmn` files open from File ▸ Open too.

A DMN file's window lists its decisions on the left. **+ Table** and
**+ Literal** add a decision, and **−** removes the selected one, together
with the requirements other decisions have on it. On the right are the
selected decision's name, its id (changing it updates the requirements and
the diagram that refer to it), and **Requires**, the decisions it needs
evaluated first. The designer refuses a requirement that would make a
cycle.

A **decision table** is a grid laid out as DMN draws one: a row per rule,
the inputs' columns, then the outputs' (marked →), then the rule's
annotation. The hit policy is chosen above the grid, and its letter
heads the rule numbers: U, F, A, R, C, and C+, C<, C>, C# for COLLECT's
aggregations. These are the policies the engine evaluates.

- Double-click a cell to type in it. Return or leaving the cell writes it.
  An input's entry is unary tests (`< 10`, `[1..5]`, `"a","b"`,
  `not(...)`, or `-` or empty for any value). An output's entry is a FEEL
  expression, and an empty one gives no value. Entries are coloured and
  checked as the engine reads them, while you type too, and where the
  engine would stop reading is underlined.
- **+ Rule** adds a rule after the selected one, **Duplicate** (⌘D)
  copies it, **− Rule** (or Backspace, or Edit ▸ Delete) removes the
  selected rules, and **↑ ↓** move a rule.
- Click a column's heading or one of its cells, and the panel under the
  grid edits the column. An input has a label, the expression whose value
  the entries test, a type and its input variable (`cellInput` unless
  set). An output has a label, a name and a type. **+ Input** and
  **+ Output** add a column after the current one of their kind,
  **− Column** removes it, and **← →** move it among its kind. A rule's
  entries move, come and go with their columns.

A **literal expression** has its variable's name and type and its FEEL
expression.

The Decision menu has all of these. Each change is one undoable step, and
saving writes the file back as it was apart from what changed, Camunda
extensions and input data included. Where the file has a DMN diagram, a
decision added gets a shape in it, and a requirement an edge. The status
line says whether the engine would deploy the file, or why it would not.
**Server ▸ Deploy** sends the file on its own. Deploying the process
sends the DMN files beside it that define its tasks' decisions. A file
open in the decision editor goes as it stands there, saved or not.

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
- **Select:** click a shape or a flow. Shift- or ⌘-click adds to the
  selection or takes out of it, and dragging on empty canvas draws a band
  around shapes. The first selected is the anchor the others are lined up
  with, marked with a square when there are several.
- **Arrange several:** Diagram ▸ Align lines the selected shapes up with
  the anchor, by their left edges, centres, right edges, tops, middles or
  bottoms; Diagram ▸ Distribute spreads three or more out evenly, across or
  down, the outermost two staying where they are. Both are on the right-
  click menu too. What a selected subprocess holds goes with it.
- **Nudge:** the arrow keys move the selection by one, or by ten with
  Shift; a burst of presses is one undo step.
- **Move:** drag the selection. The shape dragged snaps its centre to
  another's when it comes within a few pixels of it, and a dashed guide
  shows the line. A subprocess moves with its contents, and
  an activity with its boundary events. A boundary event dragged alone
  slides along its activity's edge. A flow whose ends both move goes with
  them; one with a single end moved keeps its bends, the bend next to that
  end sliding to keep its segment straight, and is routed again with
  right-angle bends only when it has none or they would land inside a
  shape. Names go with their nodes and flows.
- **Rename:** double-click a node or a flow, or select one and press Return
  (or Diagram ▸ Rename, ⌘R), and type its name over it. Return keeps it,
  Escape leaves it as it was.
- **Flows' ends and bends:** a selected flow shows its ends as squares and
  its bends as circles. Drag an end onto another node to reconnect it, by
  the rules a new flow keeps to; drag a bend where it should go. A bend
  lines up with its neighbours when it comes within a few pixels of
  straight.
- **Names:** an event's, a gateway's or a flow's name can be dragged on its
  own. Where it is goes into the diagram (`BPMNLabel`), as Camunda Modeler
  writes it, and the labels in a modeller's files are shown where it put
  them.
- **Change Type:** right-click a node: a task becomes another kind of task,
  a gateway another gateway, an event another event its flows allow, with
  each definition BPMN gives it. What only the old type had -- a user
  task's assignment and form, a service task's topic, a gateway's default
  where the new one has none -- goes; its name, parameters, listeners and
  flows stay.
- **Cut, Copy, Paste, Duplicate (⌘D):** copied nodes take what they hold,
  their boundary events, the flows between them and the messages, signals,
  errors and escalations they name. They go on the clipboard as a BPMN
  document, which other modellers and text editors read too, and are
  pasted under fresh ids, a step further down each time. BPMN copied from
  another file pastes in this one's namespace prefixes.
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
  out like this when it opens. Each node is placed level with what it
  follows where it can, so flows run straight, and a gateway sits between
  its branches. What a boundary event leads to, and a compensation handler,
  hangs below its activity. Event subprocesses go in a row beneath the
  rest. Flows bend at right angles, enter an activity straight across
  where the two face each other, and go round other shapes.
- **Associations**, such as a compensation boundary's link to its handler,
  are drawn dotted and listed in the outline with ⇢.
- **Undo and Redo** cover every change. **View** zooms in and out, and
  **Zoom to Fit** (⌘9) shows the whole diagram.

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
and a built ODataKit checkout, as WorkflowDesk does, and a built
XFormsKit checkout with its form editor (`make designkit` there). Then, in
this directory:

    make ODATAKIT=... XFORMSKIT=...         # WorkflowDesigner.app
    make ODATAKIT=... XFORMSKIT=... run     # open it
    make ODATAKIT=... XFORMSKIT=... check   # the tests: the document model,
                                            # edits, layout, decisions,
                                            # deployments, and that the engine
                                            # reads what the designer writes

`Tools/` has the designer without a window, for BPMN files kept in a
repository, such as `Examples/Processes`. They build on GNUstep with
`make -C Tools`:

    Tools/obj/wkd-arrange file.bpmn...         # Diagram ▸ Arrange, written back
    Tools/obj/wkd-render file.bpmn out.png [scale]
                                               # the diagram as a picture; it
                                               # needs a display, Xvfb will do

**On macOS**, use the `WorkflowDesigner` scheme of `WorkflowKit.xcworkspace`.

## Inside

| Where | What |
| --- | --- |
| `../Shared/WKDDiagram` | What the canvas draws, read from the XML: shapes with their bounds, subprocess and boundary host, and flows with their waypoints. It is read again after every change. |
| `../Shared/WKDEditor` | Every change. It keeps elements, references and the BPMN diagram information consistent. Each change is one undo step that restores the document as it was. Its categories hold what the canvas changes directly (`+Canvas`: names, reconnections, bends, labels, kept routes), the clipboard (`+Clipboard`), type changes (`+Types`) and arranging several shapes (`+Alignment`). |
| `../Shared/WKDLayout` | A layered (Sugiyama) layout, adapted from CoreWF's: layers by longest path, ordered to cross as little as they can, then placed by sweeps that move each layer as near its neighbours as its order and spacing allow (isotonic regression). Edges can leave a node's bottom. |
| `WKDProperties` | The inspector's properties: where each value lives in the XML, how to read and write it, and which hold expressions. |
| `WKDTableEditor` | A table property in the inspector, with its + and − and its detail table. |
| `WKDExpressionField` | The expression field and the text storage that colours it, ported from the XForms Designer's XPath field, over the engine's `+[WFFeelExpression tokensOfText:place:]` and `+problemInText:place:`. |
| `WKDWindowController`, `WKDOutline`, `WKDInspectorView`, `WKDPane` | The three panes, ported from RDLKit's designer, with the DMTabBar XFormsDesignKit carries. |
| `WKDDeployment` | What a deployment sends: the process, the forms it embeds and the DMN files defining its decisions, as their editors have those open. |
| `WKDDecisions` | A DMN file's decisions, read after every change, and every change to them (`WKDDmnEditor`), one undo step each, as `WKDEditor`'s are to a process. |
| `WKDDecisionDocument`, `WKDDecisionWindowController` | The DMN document and its window: the decisions, the table's grid and its column panel, and a literal expression's fields. The window is built in code, because the grid's columns are the table's. |
| `WKDAppDelegate`, `WKDServerProcessesController` | The server connection, shared by every window, and the Open from Server window. The connection itself is WorkflowDesk's (`../Shared`). |
| `WKDCanvasView`, `WKDPaletteView`, `../Shared/WKDRenderer` | Drawing and editing, adapted from CoreWF's graph view. BPMN notation is drawn with `NSBezierPath`, with no images. |

The document model, the editor, the layout and the renderer are in
`../Shared`, because WorkflowDesk draws diagrams with them too.

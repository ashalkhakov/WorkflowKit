# BPMN and DMN in UDCode

WorkflowKit ships a [UDCode](https://github.com/ashalkhakov/UDCodeKit)
extension, BPMN and DMN, for editing processes (`.bpmn`) and the decisions
they evaluate (`.dmn`) inside UDCode, as part of the application whose
processes they are. It is WorkflowKit's designer: the canvas, its outline,
the inspector, the palette and the decision tables, which were the
WorkflowDesigner app's and are now UDCode's. Its files follow the
application's life cycle -- built with it, tested with it, shipped and
deployed with it ([deployments.md](deployments.md)) -- so there is no
deploying from the editor.

## Installing it

Each WorkflowKit release attaches a package for each platform:

| UDCode on | Package |
|---|---|
| macOS, Apple silicon | `workflowkit-<version>-darwin-arm64.udcx` |
| macOS, Intel | `workflowkit-<version>-darwin-x64.udcx` |
| Linux (the AppImage), x86_64 | `workflowkit-<version>-linux-x64.udcx` |
| Linux, aarch64 | `workflowkit-<version>-linux-arm64.udcx` |
| Windows | `workflowkit-<version>-win32-x64.udcx` |

Install it with **UDCode > Extensions… > Install from Package…**, or from a
shell with `UDCode --install-extension workflowkit-<version>-<platform>.udcx`,
then start UDCode again. A package states which UDCode versions it works
with (`engines.udcode` in its `package.json`: 0.22.2 and later 0.22
releases), and UDCode refuses a package built for another version or
another platform. Once installed it keeps itself up to date from the
release's feed (`updates` in its `package.json`).

Each release also attaches **UDCode with the extension in it**
(`UDCode-WorkflowKit-…`: the AppImage, the macOS app, the Windows zip),
for those who want the designer alone. It installs the extension the first
time it starts.

## Using it

A `.bpmn` file opens in the process editor and a `.dmn` file in the
decision editor, each in a tab of its own, when its text is BPMN or DMN; a
file of either kind that is not opens as text, coloured as XML. The parts
spread over UDCode's window the way an Xcode editor's do:

| Part | Where it goes in UDCode |
|---|---|
| A process's outline: its nodes, a subprocess's contents and an activity's boundary events beneath them, each node's outgoing flows | The tab, on the left |
| The canvas | The tab |
| The inspector for what is selected | The inspector pane's first tab after **File** (E) |
| The process's own settings | The inspector pane's next tab (P) |
| The palette | The **Library** (View ▸ Show Library, ⇧⌘L) |
| What the engine would refuse | The **Issues** navigator, each issue at the line of the element it is about; choosing one selects the element |
| Whether the engine runs the process, and what the last command refused | The status line under the canvas |
| A DMN file's decisions; the one chosen, and its decision table or literal expression | The tab |
| The column chosen in a decision table | The inspector pane's tab after **File** (C) |
| Arrange, pools and lanes, Rename, Align, Distribute, Edit Form…, Edit Decision…, the zoom; Add Decision Table, Add Literal Expression, the rules and columns; Show as Text | The **Editor** menu |

The outline, the canvas and the inspector share one selection. Choosing an
element brings its inspector forward; choosing the process in the outline
brings the process's.

The file is the document's text, and each change you make in the editor is
written back to it. So the things UDCode does for text files work here
too:

- **Undo** and **Redo** are the document's own. Undoing restores the text
  and reads the process or the decisions again; the selection, and the
  decision and column chosen, stay where they still exist.
- **Saving** and the tab's unsaved dot are the document's.
- **Source control** shows what changed. Each change touches only the lines
  that differ. Whatever the editor doesn't draw is kept: documentation,
  `camunda:` extensions, form fields, annotations, other processes. The
  first change of a file not written by WorkflowKit may touch more lines
  than it changed: the file is written back as WorkflowKit lays XML out.
- **View > Open as Text** shows the XML in a normal editor tab, beside the
  editor. The two tabs are the same document: edits made in the text
  appear in the editor, and the editor's in the text.

After every change the engine's own readers read the file, with the forms
beside it, as deploying it would: the Issues navigator lists what they
refuse, and the status line says either that the engine runs the process,
or why it doesn't -- "service tasks are external tasks
(camunda:type="external" with a camunda:topic) or run a delegate", for
instance. When the text cannot be read at all, the tab says why and offers
it as text.

### The canvas

- **The Library** (View ▸ Show Library, ⇧⌘L): choose an element, then
  click the canvas to place it. Events, tasks, a subprocess, gateways and
  boundary events are all there. A node placed inside a subprocess belongs
  to it. A boundary event placed near a task's or subprocess's edge
  attaches to it there.
- **Select:** click a shape or a flow. Shift- or ⌘-click adds to the
  selection or takes out of it, and dragging on empty canvas draws a band
  around shapes. The first selected is the anchor the others are lined up
  with, marked with a square when there are several.
- **Arrange several:** Editor ▸ Align lines the selected shapes up with
  the anchor, by their left edges, centres, right edges, tops, middles or
  bottoms; Editor ▸ Distribute spreads three or more out evenly, across or
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
  (or Editor ▸ Rename), and type its name over it. Return keeps it,
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
- **Cut, Copy, Paste, Duplicate** (Edit, and the right-click menu): copied
  nodes take what they hold, their boundary events, the flows between them
  and the messages, signals, errors and escalations they name. They go on
  the clipboard as a BPMN document, which other modellers and text editors
  read too, and are pasted under fresh ids, a step further down each time.
  BPMN copied from another file pastes in this one's namespace prefixes.
- **Connect:** select a shape and drag from the blue handle at its top
  right onto another. On macOS, Option-dragging from a shape does the same.
  The designer refuses flows the engine would: out of an end event, into a
  start or boundary event, or across a subprocess's border.
- **Resize:** a selected subprocess has a handle at its bottom right.
- **Delete:** Backspace or Delete removes the selection. A node takes its
  flows, its contents and its boundary events with it, and references to it
  are cleaned up: `incoming`, `outgoing` and a gateway's `default`.
- **Editor ▸ Arrange** lays the whole process out afresh, left to right. A
  file without a diagram, such as the engine's example deployment, is laid
  out like this when it opens, as one change of its text. Each node is
  placed level with what it follows where it can, so flows run straight, and
  a gateway sits between its branches. What a boundary event leads to, and a
  compensation handler, hangs below its activity. Event subprocesses go in a
  row beneath the rest. Flows bend at right angles, enter an activity
  straight across where the two face each other, and go round other shapes.
- **Pools and lanes:** Editor ▸ **Add Pool** puts the process in a pool
  (a collaboration's participant, named for the process). **Add Lane**
  (Editor, or right-click a pool or lane) adds a lane after the lane
  selected, or at the bottom of the pool; a process without a pool is
  given one first, and a pool without lanes a lane holding everything in
  it. What is below a new lane moves down to make room. Click a pool's or
  lane's band (where its name is) to select it; double-click it to rename
  it; drag a pool's band to move it with everything in it; drag the handle
  at its bottom right to resize it -- a lane gets taller or shorter at its
  bottom, the lanes below moving with it, and a pool's width is its
  lanes'. Delete removes a lane, the lane before it (or after it) taking
  its room and its nodes, or a pool with its lanes; the nodes stay. As
  nodes are moved, added, pasted and renamed, each is listed by the lane
  it is in (`flowNodeRef`), and the pool grows round what is moved past
  its edge, moving the pools below it down. **Arrange** keeps each node in
  its lane, stacking the lanes round what they hold. Other participants'
  pools are drawn, not edited; message flows are not drawn yet. The
  engine runs the process and ignores its lanes.
- **Associations**, such as a compensation boundary's link to its handler,
  are drawn dotted and listed in the outline with ⇢.
- **Undo and Redo** are the text's: see below. Editor ▸ **Zoom In**,
  **Zoom Out**, **Actual Size** and **Zoom to Fit** zoom the canvas.

### The inspector

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
writes when used. Each write is one change of the text.

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

**+** adds a row and **−** removes the selected one. Double-click a cell to
edit it, and Return or leaving it writes it. Each of these is one change,
and the rows not touched are written back as they were. A value the engine
reads as an expression is coloured, and checked as it is typed, as an
expression field is.

### Forms

A form the process names as `camunda:formKey="embedded:deployment:<name>"`
is an XForms document kept beside the `.bpmn` file and deployed with it.
**Edit Form…** (the button in the Form section, or Editor ▸ Edit Form…)
opens the selected task's or start event's form in a tab of its own: in
XFormsKit's designer when UDCode has the XForms extension, as XML when it
has not. When there is no such form yet, it is made first, from the fields
as the engine makes their form, written beside the process, and named in
the form key: one change. The process must have been saved, so that there
is somewhere beside it.

### Decisions

A business rule task names its decision by key (`camunda:decisionRef`).
The decision is defined in a DMN file kept beside the `.bpmn` file and
deployed with it. **Edit Decision…** (the button in the Decision section,
or Editor ▸ Edit Decision…) opens the DMN file beside the process that
defines the selected task's decision, with that decision shown. When no
file defines it, one is made, named after the decision, with a table for
it, and when the task names no decision yet, it names this one.

A DMN file's tab lists its decisions on the left. **+ Table** and
**+ Literal** add a decision, and **−** removes the selected one, together
with the requirements other decisions have on it. On the right are the
selected decision's name, its id (changing it updates the requirements and
the diagram that refer to it), and **Requires**, the decisions it needs
evaluated first. A requirement that would make a cycle is refused.

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
- **+ Rule** adds a rule after the selected one, **Duplicate** copies it,
  **− Rule** (or Backspace, or Edit ▸ Delete) removes the selected rules,
  and **↑ ↓** move a rule.
- Click a column's heading or one of its cells, and the **Column**
  inspector edits it. An input has a label, the expression whose value the
  entries test, a type and its input variable (`cellInput` unless set). An
  output has a label, a name and a type. **+ Input** and **+ Output** add a
  column after the current one of their kind, **− Column** removes it, and
  the Editor menu moves it among its kind. A rule's entries move, come and
  go with their columns.

A **literal expression** has its variable's name and type and its FEEL
expression.

The Editor menu has all of these. Where the file has a DMN diagram, a
decision added gets a shape in it, and a requirement an edge.

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

## How it is built

`UDCodeExtension/` contains the extension:

- **`WKUExtension`**, its principal class. It declares two modes in
  `LanguageInfo.plist`, `bpmn` (`.bpmn` files) and `dmn` (`.dmn` files),
  both borrowing the XML mode's grammar. It gives a document of either mode
  its editor when the text is BPMN or DMN, and adds the Editor menu's items
  (`WKUEditorMenus.xib`).
- **`WKUProcessEditorViewController`** and
  **`WKUDecisionEditorViewController`**, the tabs (`WKUProcessEditor.xib`,
  `WKUDecisionEditor.xib`). Each is a `WKDProcessEditor` or
  `WKDDecisionEditor` over the document's text, with no undo manager of its
  own, and the designer's parts over that editor, as the app's windows had
  them. Each change the editor reports is written back as one edit of the
  text (`WKUTextEdits`, over UDPieceTable's line diff). A change of the text
  made some other way is read again (`-readData:error:`).
- **`Tests/`**, an XCTest bundle (WKUTests) against UDCode's own document
  and text model.

The designer's parts (`Apps/WorkflowDesigner`, listed once in
`designer.make`) are compiled into the bundle, their XIBs among its
resources. The engine's library goes inside the bundle -- on macOS
`WorkflowKit.framework` in its `Frameworks`, on GNUstep its library beside
the bundle's binary, with Core Data's -- as the LGPL has it. UDCode's own
libraries (UDCodeKit, DiagramKit, GNUstep's) are the running UDCode's.

It builds on UDCode's SDK, which `.github/pins.env` pins
(`UDCODEKIT_VERSION`). With the SDK installed, `make` builds the extension
and `make check` runs its tests; `make -f Makefile.apple` and its `check` do
the same on macOS, from `.deps/UDCodeKit.xcframework`. `Scripts/udcx.sh
<version> <directory>` packages it, and each release attaches the packages
and UDCode with the extension in it (`.github/release/udcode.conf`).

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

## Using it

- **Palette:** click a tool, then click the canvas to place it. Events,
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

Names and the other properties come with the inspector, the next milestone.

## Building

**On GNUstep**, build the engine library at the top of the repository with
`make` first. Then, in this directory:

    make              # WorkflowDesigner.app
    make run          # open it
    make check        # the tests: the document model, edits, layout, and
                      # that the engine reads what the designer writes

**On macOS**, use the `WorkflowDesigner` scheme of `WorkflowKit.xcworkspace`.

## Inside

| Where | What |
| --- | --- |
| `WKDDiagram` | What the canvas draws, read from the XML: shapes with their bounds, subprocess and boundary host, and flows with their waypoints. It is read again after every change. |
| `WKDEditor` | Every change. It keeps elements, references and the BPMN diagram information consistent. Each change is one undo step that restores the document as it was. |
| `WKDLayout` | A layered (Sugiyama) layout, adapted from CoreWF's. |
| `WKDCanvasView`, `WKDPaletteView`, `WKDRenderer` | Drawing and editing, adapted from CoreWF's graph view. BPMN notation is drawn with `NSBezierPath`, with no images. |

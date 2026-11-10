# The designer's parts

WorkflowKit's BPMN and DMN designer, as parts: models of a process and of
a DMN file, the session objects the parts share, and the parts themselves
-- the canvas, the outline, the palette, the inspector, the decision list,
detail, rule grid, column and literal expression -- each a view controller
with its XIB. UDCode's BPMN and DMN extension (`../../UDCodeExtension`)
puts them in its tabs and panes; [docs/UDCODE.md](../../docs/UDCODE.md)
says how to use them there.

The document is the BPMN or DMN XML itself. It is read once into a model
of objects (`WKDModel`, `WKDDmnModel`), and each change is made to the
model and written into the XML where it changed, so what the designer
doesn't draw is kept: documentation, `camunda:` extensions, form fields,
annotations, other processes. After every change the engine's own readers
check the text (`WFDeploymentChecker`), a moment later.

## Building and testing

`designer.make` lists the parts' sources and XIBs once, for the extension
and the tests, and what they build on: the engine library built at the top
of the repository, DiagramKit, Core Data.

**On GNUstep**, build the engine library at the top of the repository with
`make` first; then, in this directory:

    make            # the tools, below
    make check      # the tests: the models and their edits, undo, the
                    # layout, decisions, that the engine reads what the
                    # designer writes, the XIBs loaded and connected;
                    # under xvfb-run where there is no display

`Tools/` has the designer without a window, for BPMN files kept in a
repository, such as `Examples/Processes`:

    Tools/obj/wkd-arrange file.bpmn...         # Editor ▸ Arrange, written back
    Tools/obj/wkd-render file.bpmn out.png [scale]
                                               # the diagram as a picture; it
                                               # needs a display, Xvfb will do

**On macOS**, the `WorkflowDesignerTests` scheme of `WorkflowKit.xcworkspace`
runs the tests.

`Tests/WKDTimingTests.m` times the edits on a process of 1000 tasks and a
DMN file of 2000 rules when `WKD_TIMING` is set.

## Inside

| Where | What |
| --- | --- |
| `../Shared/WKDModel`, `WKDBpmnReader`, `WKDBpmnWriter` | A process as objects linked both ways -- nodes, flows, lanes, pools, with their diagram's bounds and waypoints -- read once from the XML, which they keep, and written into it only where they changed. |
| `../Shared/WKDEditor` | Every change, made to the model. It keeps elements, references and the BPMN diagram information consistent. Each change is one undo step. Its categories hold what the canvas changes directly (`+Canvas`: names, reconnections, bends, labels, kept routes), the clipboard (`+Clipboard`), type changes (`+Types`), arranging several shapes (`+Alignment`), and pools and lanes, kept round their nodes after every change (`+Lanes`). |
| `../Shared/WKDJournal` | Undo: the states of the elements a step touched and the XML it edited, played back, so undo puts the document back to the byte, at the cost of the change. In UDCode the text's undo is the undo: the editors have no undo manager there. |
| `../Shared/WKDNotation` | What a node's kind is drawn as, and where its label and band go. |
| DiagramKit's `DKLayeredLayout` | The layered (Sugiyama) layout `WKDEditor` arranges a process with: layers by longest path, ordered to cross as little as they can, then placed by sweeps that move each layer as near its neighbours as its order and spacing allow. Edges can leave a node's bottom. |
| `WKDProcessEditor`, `WKDSelection` | One process being edited: its text read into an editor (and read again, `-readData:error:`), its selection, the engine's problems; what the parts share. |
| `WKDCanvasViewController`, `WKDOutlineViewController`, `WKDPaletteViewController` | The canvas, the outline and the palette, each from its XIB, following the process editor. |
| `WKDProcessCommands` | The Editor menu's actions on a process, in the responder chain of whatever shows it; what they need of it is `WKDProcessCommandsHost`. |
| `WKDProperties` | The inspector's properties: where each value lives in the XML, how to read and write it, and which hold expressions. |
| `WKDElementModel`, `WKDTableModel` | A section's values, and a table property's rows, as what the inspector's rows bind to: set through the descriptors, refused with the reason (`-validateValue:forKey:error:`). |
| `WKDInspectorViewController`, `WKDInspectorRow`, `WKDTableRowController` | The inspector: a section's rows, each from the XIB of its kind (`WKDRow*.xib`), a table's under an array controller of its rows. |
| `WKDExpressionField` | The expression field and the text storage that colours it, ported from the XForms Designer's XPath field, over the engine's `+[WFFeelExpression tokensOfText:place:]` and `+problemInText:place:`. |
| `WKDDeployment` | What a process deploys with: the forms it embeds and the DMN files defining its decisions, what it is checked with; and a form made from a task's fields. |
| `WKDDecisions`, `WKDDmnModel` | A DMN file's decisions as a model, read once, and every change to them (`WKDDmnEditor`), one undo step each, as `WKDEditor`'s are to a process. |
| `WKDDecisionEditor` | One DMN file being edited: its text (read again, `-readData:error:`), the decision and column chosen, the engine's problems; what the decision parts share. |
| `WKDDecisionListViewController`, `WKDDecisionDetailViewController`, `WKDRuleGridViewController`, `WKDColumnViewController`, `WKDLiteralViewController` | The decisions, the one chosen, its table's grid (its columns made from the table's), the column chosen, a literal expression: each from its XIB. |
| `WKDPane` | Putting a part's view in its place, ported from RDLKit's `RDLPane`. |
| `WKDCanvasView`, `WKDPaletteView`, `../Shared/WKDRenderer` | Drawing and editing, adapted from CoreWF's graph view. BPMN notation is drawn with `NSBezierPath`, with no images. |

The process model, the editor, the layout and the renderer are in
`../Shared`, because WorkflowDesk draws diagrams with them too.

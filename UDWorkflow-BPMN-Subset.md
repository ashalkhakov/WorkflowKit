# UDWorkflow — BPMN 2.0 executable subset

Target: embeddable GNUstep / Objective-C engine (ARC, libdispatch, Core Data). Prefix **UD**. The engine follows Camunda 7's execution model — an execution tree, commands that commit at wait states — as `docs/execution-model.md` describes; this page is the construct list.

This is not Camunda coverage. V2 is the set of constructs the engine will load, persist, and fire. Everything else is ignored or rejected on import.

## 1. In scope

### Process graph

| Construct | BPMN element | Engine type |
|---|---|---|
| Executable process | `process` `isExecutable="true"` | `UDProcessDefinition` |
| Sequence flow | `sequenceFlow` | `UDSequenceFlow` |
| Conditional flow | `conditionExpression` | `UDComparisonCondition` |
| Default flow | `exclusiveGateway/@default` | `UDGateway.defaultFlowId` |
| Version | assigned on deployment | `definition.version`: 1 for a key's first deployment, the next for each changed one |

### Activities

| Construct | BPMN | Notes |
|---|---|---|
| User task | `userTask` | Wait state; a task in `taskService`, completed with `completeTask:`. `camunda:assignee`. |
| Service task | `serviceTask` | External task: `camunda:type="external"` with `camunda:topic`, for workers using `externalTaskService` (fetch and lock by topic, complete, failure with retries and timeout, BPMN error). The engine's in-process worker is one: it hands tasks to the service handler with the activity's retry cycle (default three attempts). No retries left raises an incident. |
| Script task | `scriptTask` | Same handler path as service, action key in `ud:action`. No script text. |
| Embedded subprocess | `subProcess` | A scope execution of its own; it sees its parents' variables, and new variables land on the process instance. |

### Transactions

| Construct | BPMN | Behaviour |
|---|---|---|
| Async before | `camunda:asyncBefore="true"` | The command stops before the node; a job enters it. On a boundary event, the interruption happens at once and the job passes the event. |
| Async after | `camunda:asyncAfter="true"` | The node finishes (a join fires) and one job takes its outgoing flows. Not on event-based gateways. |
| Exclusive | `camunda:exclusive="false"` | The node's jobs may run beside the instance's other work. |
| Task priority | `camunda:taskPriority` | On a service task, or the process as a default: fetch order for external tasks. Whole numbers. |
| Retry cycle | `camunda:failedJobRetryTimeCycle` | `R<n>/<duration>` or a list of durations. Default three attempts, retried at once. None left raises an incident; `managementService` gives attempts back. |

### Gateways

| Construct | BPMN | Semantics |
|---|---|---|
| Exclusive split/merge | `exclusiveGateway` | First true condition in document order, else default; no match fails the command. Merge is pass-through. |
| Parallel split/join | `parallelGateway` | Split makes concurrent executions. Join fires when as many executions wait at it as it has incoming flows. Conditions ignored. |
| Inclusive split/join | `inclusiveGateway` | All true conditions (else default). Join fires when no other execution in the scope can still reach it. |
| Event-based | `eventBasedGateway` | The execution waits at the gateway with a subscription or timer per following catch event; the first to fire wins, the rest are cancelled. |

### Events

| Construct | BPMN | Behaviour |
|---|---|---|
| None start / end | `startEvent` / `endEvent` | Start an instance / end a path; the last path ends the scope. |
| Message start | `startEvent` + `messageEventDefinition` | A start subscription per deployed latest version; correlating the message starts an instance. |
| Timer start | `startEvent` + `timerEventDefinition` | A job created on deployment starts an instance when due; a new version replaces it. |
| Message catch | `intermediateCatchEvent` + message | Wait state with an event subscription. |
| Timer catch | `intermediateCatchEvent` + timer | Wait state with a timer job at an absolute due date. |
| Message throw / message end | throw / end + message | `UDProcessEngineDelegate` `didThrowMessage`, after commit. |
| Boundary message | `boundaryEvent` `attachedToRef` | On a task or subprocess. Interrupting, or non-interrupting and repeatable. |
| Boundary timer | `boundaryEvent` + timer | On a task or subprocess, armed when it is entered; fires once. |
| Signal start | `startEvent` + `signalEventDefinition` | A start subscription per deployed latest version; a signal starts an instance of every definition subscribed. |
| Signal catch | `intermediateCatchEvent` + signal | Wait state with a signal subscription; also behind an event-based gateway. |
| Signal throw / signal end | throw / end + signal | Broadcast in the throwing transaction to every waiting catcher, in every instance, and every signal start. |
| Boundary signal | `boundaryEvent` + signal | On a task or subprocess; interrupting, or non-interrupting and repeatable. |
| Terminate end | `endEvent` + `terminateEventDefinition` | Ends its scope -- the instance, or the subprocess it is in -- with every path in it. |
| Boundary error | `boundaryEvent` + `errorEventDefinition` | Catches a BPMN error with its `errorCode`, or any without `errorRef`, on the task or on any subprocess around it, nearest first. An uncaught error ends its path. |

## 2. Event rules

Timers are jobs with an absolute due date; the job executor fires them, so a restart waits only for the time that is left, and even a zero-length timer is a wait state that commits.

Messages are correlated through `runtimeService`: by name, narrowed by business key and by process variables that must be equal, to exactly one recipient (`correlateMessage:`) or to all (`correlateMessageToAll:`). Payload variables are set on the receiving instance.

**Interrupting boundary:** the host activity's scope execution is removed with everything in it; the path continues from the boundary event.

**Non-interrupting:** the activity goes on; a new concurrent path leaves the boundary. A message boundary stays armed for the next message.

Service and script tasks are external tasks, created by the commit that reaches them and offered to the in-process worker after it; a restarted engine offers again what it had locked. At-least-once, with the external task id as the idempotency key.

## 3. Conditions

Conditions are FEEL, the expression language of DMN; the engine implements its comparison subset so far. No JavaScript, no XPath.

```
amount > 1000
approved = true
name != "x"
```

Operators: `=` `!=` `>` `>=` `<` `<=` (`==` is accepted). Values: integers, floats, `true`/`false`, double-quoted strings.

The reader also accepts Camunda 8's `=` prefix, and Camunda 7's `${...}` syntax with the same single comparison inside, so files from both run. See `docs/execution-model.md` for how the language is chosen.

## 4. Out of scope (V2 reject or ignore)

| Family | Examples |
|---|---|
| Collaboration | pool, lane, messageFlow, conversation, choreography |
| Gateways | complex |
| Activities | event subprocess, call activity, transaction, ad-hoc, multi-instance, loop, compensation |
| Tasks | manual, business rule, send, receive, receive-task as event stand-in |
| Events | escalation, cancel, compensate, link, conditional, multiple, parallel multiple |
| Event use | non-interrupting start in event subprocess |
| Data | data object, data store, data association, properties as BPMN itemAware |
| Execution extras | full BPMN DI edge waypoints |

## 5. XML shape

Standard BPMN 2.0 (`http://www.omg.org/spec/BPMN/20100524/MODEL`), as Camunda Modeler reads and writes it:

- `message` and `error` elements at the top, referenced by `messageRef` and `errorRef` (an error boundary matches the error's `errorCode`; no `errorRef` catches any error).
- Timers as `timeDuration` in ISO-8601: weeks, days, hours, minutes, seconds. `timeDate`, `timeCycle` and calendar lengths (years, months) are refused for now.
- Embedded subprocesses hold their own flow elements.
- Settings BPMN has no attribute for use Camunda's namespace (`http://camunda.org/schema/1.0/bpmn`, prefix `camunda`); `ud:` (`https://udworkflow.local/bpmn`) is used only for a script task's action.
- Layout is BPMN DI: a `BPMNShape` with `dc:Bounds` per node that has bounds, and a straight `BPMNEdge` per flow between two such nodes. The engine keeps no edge waypoints.

The reader fails on any out-of-scope element, naming it, rather than dropping it. Documentation, extension elements, lanes, annotations and data objects are ignored. Only processes with `isExecutable="true"` are read.

Round-trip path:

```
UDProcessDefinition → UDBpmnWriter → XML → UDBpmnReader → UDDefinitionBuilder → UDProcessDefinition
```

Deploying stores the XML, and the engine runs the definition read back from it, so what runs is always what is stored.

## 6. Runtime contract

| Piece | Rule |
|---|---|
| Execution | A path through an instance; executions form a tree under the process instance. |
| Command | One call: its own Core Data context, run until every path is at a wait state or has ended, one save. |
| Concurrency | A lost race fails with `UDWorkflowErrorConflict` and changes nothing; the engine retries its own commands. |
| Worker and jobs | The in-process worker and the job executor run one instance's exclusive work on one serial queue at a time. A job is acquired, run and, on failure, recorded in three transactions. |
| Public API | `UDProcessEngine` and its services; value objects out. Delegates and target-action. |
| History | Written in the command's transaction at `historyLevel`: NONE, ACTIVITY (process, activity and task instances), AUDIT (and latest variables; the default), FULL (and variable updates, incidents, the job log). The store keeps the level. `camunda:historyTimeToLive` (days) lets cleanup remove an ended instance's history. |
| Persistence | `UDStore`: Core Data (`Model/UDWorkflow.xcdatamodeld`) over in-memory, SQLite or a FreeCoreData SQL backend. |

Node layout for the designer is stored on each `UDFlowNode` as `boundsX/Y/Width/Height` and exported as BPMN DI.

Tests: `Tests/UDWorkflowTests.m` is an XCTest case (`#import <XCTest/XCTest.h>`). On GNUstep, `make test` builds the library and runs the bundle under tools-xctest; see `CLAUDE.md` for the patched stack it is built against.

V3 candidates: call activity, error start in event subprocess, signal events, multi-instance, full BPMN DI edge waypoints.

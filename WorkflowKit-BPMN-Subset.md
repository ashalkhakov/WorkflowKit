# WorkflowKit — BPMN 2.0 executable subset

Target: embeddable GNUstep / Objective-C engine (ARC, libdispatch, Core Data). Prefix **WF**. The engine follows Camunda 7's execution model — an execution tree, commands that commit at wait states — as `docs/execution-model.md` describes; this page is the construct list.

This is not Camunda coverage. V2 is the set of constructs the engine will load, persist, and fire. Everything else is ignored or rejected on import.

## 1. In scope

### Process graph

| Construct | BPMN element | Engine type |
|---|---|---|
| Executable process | `process` `isExecutable="true"` | `WFProcessDefinition` |
| Sequence flow | `sequenceFlow` | `WFSequenceFlow` |
| Conditional flow | `conditionExpression` | `WFFeelExpression` |
| Default flow | `exclusiveGateway/@default` | `WFGateway.defaultFlowId` |
| Version | assigned on deployment | `definition.version`: 1 for a key's first deployment, the next for each changed one |

### Activities

| Construct | BPMN | Notes |
|---|---|---|
| User task | `userTask` | Wait state; a task in `taskService`, completed with `completeTask:`. `camunda:assignee`, `candidateUsers`, `candidateGroups`, `dueDate`, `followUpDate` and `priority`, each literal (`ann`; `ann,bob`; an ISO date; a number) or an expression (`${reviewer}`, `=owner.manager`) evaluated when the task is created. Candidates find it with `tasksForCandidateUser:groups:` or `tasksForCandidateGroup:` until one claims it. |
| Input/output | `camunda:inputOutput` on a task, subprocess or call activity | Input parameters -- text, an expression, `camunda:list` or `camunda:map` -- are evaluated where the path arrives and become the activity's local variables; output parameters are evaluated in the activity as it completes and set where it is. An interrupted activity maps no outputs; `camunda:script` values are refused. |
| Service task | `serviceTask` | External task: `camunda:type="external"` with `camunda:topic`, for workers using `externalTaskService` (fetch and lock by topic, complete, failure with retries and timeout, BPMN error). The engine's in-process worker is one: it hands tasks to the service handler with the activity's retry cycle (default three attempts). No retries left raises an incident. |
| Script task | `scriptTask` | Same handler path as service, action key in `wf:action`. No script text. |
| Send task | `sendTask` | An external task, as a service task: `camunda:type="external"` with `camunda:topic`, or a delegate. |
| Delegate | `camunda:class` or `camunda:delegateExpression="${name}"` on a service, send or business rule task, with `camunda:field`s | Host code run in the command: a `WFActivityDelegate` -- a class, instantiated for each call and given its fields by key, found by a name registered with `registerDelegateClass:forName:` (a Camunda file's Java class name) or by its own; or an object registered with `registerDelegate:forName:`. Plugins (`WFEnginePlugin`) register them, compiled into the host (`addPlugin:`) or loaded as bundles (`loadPluginsInDirectory:error:`). An error carrying `WFErrorRefKey` is a BPMN error; any other fails the command, or in a job its attempt. `camunda:expression` (a method call) and scripts are refused. |
| Listeners | `camunda:executionListener` (start, end on a node or the process; take on a flow), `camunda:taskListener` (create, assignment, complete, delete) | Host code, resolved as a delegate is, called in the command: start after an activity's inputs are mapped, end when it completes or is canceled (canceled activities innermost first, after their tasks' delete listeners), take as a flow is taken. A listener that fails fails the command. Timeout task listeners and script listeners are refused. |
| Business rule task | `businessRuleTask` | Evaluates the decision `camunda:decisionRef` in its command -- `camunda:decisionRefBinding` `latest` (default), `deployment`, or `version` with `camunda:decisionRefVersion` -- and keeps the result in `camunda:resultVariable` as `camunda:mapDecisionResult` says: `resultList` (default), `singleResult`, `singleEntry` or `collectEntries`. A decision that cannot be evaluated, or a result the mapping cannot take, fails the command. Without a decision, an external task as a service task is. |
| Receive task | `receiveTask` `messageRef` | Waits for the message, correlated as a message catch event's is; also behind an event-based gateway, when it has no boundary events, loop, parameters or `asyncBefore`. `instantiate="true"` is refused. |
| Manual task / task | `manualTask`, `task` | Passed through. |
| Embedded subprocess | `subProcess` | A scope execution of its own; it sees its parents' variables, and new variables land on the process instance. |
| Event subprocess | `subProcess` `triggeredByEvent="true"` | Started by its message, timer, signal, error, escalation or conditional start event while the scope around it -- the process instance or a subprocess -- is active; no sequence flows. Interrupting (the default): everything else in the scope is canceled and the scope goes on in the event subprocess, ending with it. Non-interrupting (`isInterrupting="false"`, not for errors): runs beside the scope's paths, and a message or signal start stays armed for the next. An error event subprocess catches errors thrown in its scope before any error boundary on the activity around it; an error thrown inside one goes outward. |
| Multi-instance | `multiInstanceLoopCharacteristics` on a task, subprocess or call activity | Parallel, or sequential with `isSequential="true"`. `loopCardinality`, or `camunda:collection` with `camunda:elementVariable`; `completionCondition`. The instances run under a body holding `nrOfInstances`, `nrOfActiveInstances` and `nrOfCompletedInstances`; each has its own `loopCounter` and element variable. When the completion condition holds, the other instances are canceled. Boundary events are on the body; the activity's `asyncBefore`/`asyncAfter` are each instance's. History records the body as `<id>#multiInstanceBody`. |
| Call activity | `callActivity` `calledElement` | Starts an instance of the process with that key, in the same transaction, and waits for it to end. `camunda:calledElementBinding`: `latest` (default), `deployment`, or `version` with `camunda:calledElementVersion`. Variables pass only through `camunda:in` / `camunda:out`: `source` and `target`, or `variables="all"`; `camunda:in businessKey="#{execution.processBusinessKey}"` passes the business key. A missing source passes null. Outputs are set where the variable exists, else on the process instance. |

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
| Timer start | `startEvent` + `timerEventDefinition` | A job created on deployment starts an instance when due, and with a cycle again each period; a new version replaces it. The timer is evaluated at deployment, with no variables. |
| Message catch | `intermediateCatchEvent` + message | Wait state with an event subscription. |
| Timer catch | `intermediateCatchEvent` + timer | Wait state with a timer job at an absolute due date. Fires once. |
| Message throw / message end | throw / end + message | `WFProcessEngineDelegate` `didThrowMessage`, after commit. |
| Boundary message | `boundaryEvent` `attachedToRef` | On a task, subprocess or call activity. Interrupting, or non-interrupting and repeatable. |
| Boundary timer | `boundaryEvent` + timer | On a task, subprocess or call activity, armed when it is entered; fires once. |
| Signal start | `startEvent` + `signalEventDefinition` | A start subscription per deployed latest version; a signal starts an instance of every definition subscribed. |
| Signal catch | `intermediateCatchEvent` + signal | Wait state with a signal subscription; also behind an event-based gateway. |
| Signal throw / signal end | throw / end + signal | Broadcast in the throwing transaction to every waiting catcher, in every instance, and every signal start. |
| Boundary signal | `boundaryEvent` + signal | On a task, subprocess or call activity; interrupting, or non-interrupting and repeatable. |
| Terminate end | `endEvent` + `terminateEventDefinition` | Ends its scope -- the instance, or the subprocess it is in -- with every path in it. |
| Error end | `endEvent` + `errorEventDefinition` | Throws the error as a service task's is thrown; uncaught, its path ends. `camunda:errorCodeVariable` on a catch gets the code. |
| Escalation | throw, end, boundary, event subprocess start + `escalationEventDefinition` | Travels outward like an error -- through subprocesses, out of a called process to its call activity -- to the nearest boundary or event subprocess start with its `escalationCode` (or none: any). Catches may be interrupting or not. Not critical: uncaught, or caught without interrupting, an intermediate throw goes on and an end event ends its path. `camunda:escalationCodeVariable` on a catch gets the code. |
| Compensation | boundary + association to an `isForCompensation` handler; throw and end with `compensateEventDefinition` | A completed activity's handler waits on its scope (each instance of a multi-instance activity, each completion). A completed subprocess passes its inner handlers up to its scope, unless it has a handler of its own. A throw or end event runs the handlers of the scope -- `activityRef`'s only, or all -- one after another, newest first, and waits for them. |
| Link | `intermediateThrowEvent` / `intermediateCatchEvent` + `linkEventDefinition` | A jump: the throw goes on at the catch with the same `name` in its scope. A throw has no outgoing flow, a catch no incoming one; a catch name is unique in its scope. |
| Conditional | catch, boundary, event subprocess start, process start + `conditionalEventDefinition` | Fires when its `condition` holds over the variables visible where it waits: evaluated as it starts to wait, and again after each change to a variable it sees -- only `camunda:variableName`, and only `camunda:variableEvents` (`create`, `update`, `delete`), when given. A catch that holds already does not wait. Boundaries and event subprocess starts may be interrupting or not; a non-interrupting one fires on each change after which it holds. A process's conditional start event is armed on deployment for the latest version, and `evaluateStartConditions:` starts every process whose condition holds over the variables it is given. |
| Boundary error | `boundaryEvent` + `errorEventDefinition` | Catches a BPMN error with its `errorCode`, or any without `errorRef`, on the task or on any subprocess around it, nearest first, and then, out of a called instance, on the call activity and the scopes around it; the call activity's outputs are passed back first. An uncaught error ends its path. |

## 2. Event rules

Timers are jobs with an absolute due date; the job executor fires them, so a restart waits only for the time that is left, and even a zero-length timer is a wait state that commits. A timer is `timeDate`, `timeDuration` or `timeCycle`, given as ISO-8601 text (`2030-01-01T09:00:00Z`, `PT5M`, `P2W`, `R3/PT10M`, `R/PT1H`, `R3/2030-01-01T09:00:00Z/P1D`) or as an expression (`${deadline}`, `=now() + duration(wait)`, or plain FEEL) evaluated over the variables when the timer is armed. A cycle repeats on a timer start event, a non-interrupting boundary event and a non-interrupting event subprocess; elsewhere its first firing is its only one. Cron cycles are refused.

Messages are correlated through `runtimeService`: by name, narrowed by business key and by process variables that must be equal, to exactly one recipient (`correlateMessage:`) or to all (`correlateMessageToAll:`). Payload variables are set on the receiving instance.

**Interrupting boundary:** the host activity's scope execution is removed with everything in it; the path continues from the boundary event.

Interrupting a call activity, or terminating the scope it is in, cancels the instance it called: its history ends as `INTERNALLY_TERMINATED`.

**Non-interrupting:** the activity goes on; a new concurrent path leaves the boundary. A message boundary stays armed for the next message.

Service, send, business rule and script tasks are external tasks, created by the commit that reaches them and offered to the in-process worker after it; a restarted engine offers again what it had locked. At-least-once, with the external task id as the idempotency key.

## 3. Conditions

Conditions are FEEL, the expression language of DMN, parsed once into a tree (`WFFeelExpression`) and evaluated over the variables visible at the gateway. No JavaScript, no XPath.

```
amount > 1000 and approved = true
customer.tier in ["gold", "platinum"]
count(lines[amount > 100]) >= 2
```

Implemented: null, boolean, decimal number, string, list, context and range values; names, paths and filters (`lines[amount > 100].sku`, `list[1]`, `list[-1]`); `+ - * / **`; `= != < <= > >=`, `between`, `in` with unary tests (`x in [1..10]`, `x in (< 5, > 10)`); `and` and `or` with FEEL's three-valued logic; `if/then/else`, `for/return`, `some`/`every ... satisfies`; the built-in functions for conversion (`not`, `string`, `number`), strings (`string length`, `substring`, `upper case`, `contains`, `starts with`, ...), lists (`count`, `sum`, `min`, `mean`, `all`, `any`, `list contains`, `index of`, `distinct values`, `flatten`, ...), numbers (`decimal`, `floor`, `ceiling`, `abs`, `modulo`, `odd`, `even`) and `now()`. Errors are null, as FEEL has it; a flow whose condition is null is not taken, and a condition whose value is not a boolean fails the command.

Temporal values: dates and dates and times (`@"2024-02-29"`, `@"2024-02-29T10:00:00Z"`, `date(...)`, `date and time(...)`, `today()`, `now()`), and years-and-months and days-and-time durations (`@"P1Y2M"`, `@"PT90M"`, `duration(...)`, `years and months duration(...)`); their arithmetic (a date plus a duration, the difference of two, a duration times a number), comparison, properties (`.year`, `.weekday`, `.hours`, ...) and `day of week`, `day of year`, `week of year`, `month of year`. A date and time without an offset is UTC; the API gives a date and time back as an `NSDate`, a date as its midnight in UTC, a duration as its ISO-8601 text.

Not yet: times of day without a date, time zones by name, names with spaces, user-defined functions, `instance of`, named arguments.

The reader also accepts Camunda 8's `=` prefix, and Camunda 7's `${...}` (or `#{...}`) with a compatibility subset inside -- literals, names and paths, `+ - * /`, `== != < <= > >=` and `eq ne lt le gt ge`, `&& || !` and `and or not`, parentheses -- which becomes the same FEEL. See `docs/execution-model.md` for how the language is chosen.

## 4. Decisions

`.dmn` resources (DMN 1.1, 1.2 and 1.3, as Camunda Modeler writes them) deploy beside processes; each decision is versioned per key, and is evaluated by business rule tasks or by `decisionService`.

| Construct | DMN | Behaviour |
|---|---|---|
| Decision table | `decisionTable` | Inputs are FEEL expressions over the variables; input entries are unary tests of the input's value (`< 10`, `[1..10]`, `"a","b"`, `not(...)`, `-`), which also sees it as `cellInput` (or `camunda:inputVariable`), or a boolean FEEL expression over it. Output entries are FEEL; an empty one gives no value. |
| Hit policy | `hitPolicy` | `UNIQUE` (default: more than one match is an error), `FIRST`, `ANY` (the matches must agree), `RULE ORDER`, `COLLECT`, and `COLLECT` with `aggregation` `SUM`, `MIN`, `MAX` or `COUNT` over a single output. Only the rules the policy keeps have their outputs computed. |
| Types | `typeRef` | `string`, `boolean`, `integer`, `long`, `double`, `date` on inputs and outputs: a value is converted, and one that cannot be fails the evaluation. Other types pass values through. |
| Literal expression | `literalExpression` + `variable` | One result: the variable's name and the expression's value. |
| Required decisions | `informationRequirement` / `requiredDecision` | Evaluated first, over the same variables; their outputs become variables of the decision that requires them -- a list of values when there were several results. Within one file; cycles are refused. |
| History | | At history level full, each evaluation is recorded with its inputs and result: `historicDecisionInstancesForProcessInstance:`, `...ForDecisionKey:`. |

Refused: `PRIORITY` and `OUTPUT ORDER`, business knowledge models, decision services, knowledge requirements, boxed expressions other than tables and literal expressions, expression languages other than FEEL (and Camunda 7's `${...}` subset).

## 5. Out of scope (V2 reject or ignore)

| Family | Examples |
|---|---|
| Collaboration | pool, lane, messageFlow, conversation, choreography |
| Gateways | complex |
| Activities | transaction, ad-hoc, standard loop, compensation |
| Tasks | receive tasks that start a process; `camunda:decisionRefBinding="versionTag"`, expressions in `camunda:decisionRef` |
| Events | cancel, multiple, parallel multiple; compensation event subprocesses and `waitForCompletion="false"` |
| Data | data object, data store, data association, properties as BPMN itemAware |
| Multi-instance extras | `asyncBefore`/`asyncAfter` on the loop characteristics themselves, `loopDataInputRef`/`inputDataItem` and the output side, `complexBehaviorDefinition` |
| Call activity extras | expressions in `calledElement`, `versionTag` binding, `sourceExpression`, `local="true"`, variable mapping delegates, tenants, CMMN cases |
| Execution extras | full BPMN DI edge waypoints |

## 6. XML shape

Standard BPMN 2.0 (`http://www.omg.org/spec/BPMN/20100524/MODEL`), as Camunda Modeler reads and writes it:

- `message` and `error` elements at the top, referenced by `messageRef` and `errorRef` (an error boundary matches the error's `errorCode`; no `errorRef` catches any error).
- Timers as `timeDate`, `timeDuration` or `timeCycle`, as ISO-8601 text or an expression (see section 2).
- Embedded subprocesses hold their own flow elements.
- Settings BPMN has no attribute for use Camunda's namespace (`http://camunda.org/schema/1.0/bpmn`, prefix `camunda`); `wf:` (`https://workflowkit.local/bpmn`) is used only for a script task's action.
- Layout is BPMN DI: a `BPMNShape` with `dc:Bounds` per node that has bounds, and a straight `BPMNEdge` per flow between two such nodes. The engine keeps no edge waypoints.

The reader fails on any out-of-scope element, naming it, rather than dropping it. Documentation, extension elements, lanes, annotations and data objects are ignored. Only processes with `isExecutable="true"` are read.

Round-trip path:

```
WFProcessDefinition → WFBpmnWriter → XML → WFBpmnReader → WFDefinitionBuilder → WFProcessDefinition
```

Deploying stores the XML, and the engine runs the definition read back from it, so what runs is always what is stored.

## 7. Runtime contract

| Piece | Rule |
|---|---|
| Execution | A path through an instance; executions form a tree under the process instance. A called instance's root points back at the execution at its call activity. |
| Command | One call: its own Core Data context, run until every path is at a wait state or has ended, one save. |
| Concurrency | A lost race fails with `WFErrorConflict` and changes nothing; the engine retries its own commands. |
| Worker and jobs | The in-process worker and the job executor run one instance's exclusive work on one serial queue at a time. A job is acquired, run and, on failure, recorded in three transactions. |
| Public API | `WFProcessEngine` and its services; value objects out. Delegates and target-action. |
| Operations | `runtimeService` deletes an instance (with a reason, recorded as externally terminated; what it called goes with it) and suspends or activates it with the instances it called; `repositoryService` suspends or activates a definition, optionally with its instances. A suspended instance's tasks cannot be completed, its jobs and external tasks wait, and messages and signals pass it by; a suspended definition starts nothing. |
| Modification | `modifyProcessInstance:` runs instructions in order in one command: start before an activity (entered as a flow would enter it, `asyncBefore` included), after an activity with one outgoing flow, or on a sequence flow; cancel an activity instance, or every instance of an activity. A start opens the subprocesses around its activity that have no instance -- inputs mapped, boundary events and event subprocesses armed, start event skipped -- and needs the ancestor activity instance when one has several; it cannot start inside a multi-instance or event subprocess, nor at a boundary event. A canceled activity instance takes everything in it, and a scope it leaves empty is canceled in turn; an instance left with nothing once every instruction has run ends, externally terminated. A suspended instance cannot be modified. `activityInstanceTreeOfProcessInstance:` gives the activity instances to address. |
| Migration | `migrateProcessInstances:plan:` moves instances onto another definition in one command. A `WFMigrationPlan` maps activities to activities of the same kind in corresponding scopes (`mapEqualActivities` for same id, kind and scope); every activity an instance is in must be mapped, and be a scope in both definitions or in neither. Tasks, jobs, external tasks, incidents, variables and history move with their activities; waits for events that are not mapped go, and boundary events and event subprocesses the target adds are armed. A mapped event keeps its trigger unless the mapping updates it. |
| History | Written in the command's transaction at `historyLevel`: NONE, ACTIVITY (process, activity and task instances), AUDIT (and latest variables; the default), FULL (and variable updates, incidents, the job log, decision evaluations). The store keeps the level. `camunda:historyTimeToLive` (days) lets cleanup remove an ended instance's history. |
| Persistence | `WFStore`: Core Data (`Model/WorkflowKit.xcdatamodeld`) over in-memory, SQLite or a FreeCoreData SQL backend. |

Node layout for the designer is stored on each `WFFlowNode` as `boundsX/Y/Width/Height` and exported as BPMN DI.

Tests: `Tests/` holds each area's tests in a `WF*Tests.inc`, run on every store -- in memory, SQLite, and FreeCoreData's PostgreSQL and MySQL stores when their servers are given -- by a class per area and backend on a shared `WFTestCase`; FEEL and DMN, which need no store, are plain classes. On GNUstep, `make test` builds the library and runs the bundle under tools-xctest; see `CLAUDE.md` for the patched stack it is built against and how to name the servers.

V3 candidates: full BPMN DI edge waypoints.

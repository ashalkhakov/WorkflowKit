# Execution model

Status: adopted and implemented, steps 1 to 5; what each step left out is noted under Implementation order. Replaces the token-marking model of
`persistence-design.md`, which describes the code as it stands today.

## Reference, and the clean-room rule

UDWorkflow follows the design of **Camunda 7**: an execution tree persisted
as ordinary rows, commits at wait states, asynchronous continuations, a job
executor with retries and incidents, external tasks, and history levels. When
a construct's behaviour is in question, Camunda 7's documented behaviour
settles it, and the BPMN 2.0 specification settles what Camunda leaves open.
Deviations are listed at the end, each with its reason; there should be few.

**Clean room.** UDWorkflow is to be licensed under the LGPL (2.1 or similar).
Camunda 7 is Apache-2.0, which is incompatible with GPLv2-family licences, so
nothing is taken from its source. We work from its public documentation, its
observable behaviour, and the specification. No code, SQL, or documentation
text is copied, and entity and class names are our own. Where this document
names Camunda concepts (execution, activity instance, wait state, async
continuation, job, external task, incident), those are the domain's terms,
not its code.

## Services

The engine is used through one object and six services, split the way the
reference splits them:

| Service | Covers |
|---|---|
| `repositoryService` | Deployments, process definitions, versions, BPMN resources |
| `runtimeService` | Starting instances, correlating messages, signalling, variables, suspension |
| `taskService` | User tasks: query, claim, assign, complete, task variables |
| `externalTaskService` | Fetch-and-lock by topic, complete, fail (with retries), BPMN error, extend lock |
| `managementService` | Jobs, retries, incidents, the job executor |
| `historyService` | Finished and running history, by level |

`UDProcessEngine` is built with a Core Data store description and owns the
job executor.

## Repository

A **deployment** is a named set of resources: the BPMN XML files. Deploying
parses each process into an immutable `UDProcessDefinition` graph. The engine
**assigns versions**: a process key's first deployment is version 1, and each
deployment whose content differs is the next version. Content that is
identical to the latest version is not deployed again (duplicate filtering).
New instances start on the latest version. Running instances stay on theirs.

A definition is loaded from its stored BPMN when it is first needed and then
cached, so an engine that restarts needs nothing re-deployed. This needs the
BPMN writer and reader to be lossless for everything we support (phase 2).

## The execution tree

An **execution** is a path of control through a process instance. Executions
form a tree whose root is the process instance itself.

- **Scope executions** carry variables, event subscriptions and jobs. They
  exist for:
  - the process instance;
  - an embedded subprocess;
  - an activity with boundary events;
  - a multi-instance body;
  - an activity with input and output mappings.
- **Concurrent executions** exist when a scope has more than one path
  running: after a parallel or inclusive split, or when an activity with a
  boundary event runs beside its siblings. The scope's own execution then
  goes inactive and parents one concurrent child per path.
- **Compaction.** When a scope is back to one path, its tree is compacted:
  the last concurrent child is folded back into the scope execution. Which
  execution carries on is therefore an implementation detail. This is the
  reference's documented behaviour, and callers must not rely on execution
  ids staying the same across a join.
- **Activity instances** give the state-oriented view: one per running
  activity, nested by BPMN scope. They are what the API reports, and what
  history records. Their relation to executions is many-to-one.

Parallel joins wait by making each arriving execution inactive at the join.
The join fires when every incoming flow has an inactive execution in the same
scope. The inclusive join fires when no execution in the scope can still
reach it, per the specification's OR-join, which the reference approximates
the same way.

## How the engine advances

Behaviour lives in one class per element type (`UDActivityBehavior`):

- `-execute:` enters the activity.
- `-signal:` resumes a wait state.
- An activity is left by taking outgoing transitions.

The engine never recurses through the graph. It keeps an **agenda** of small
operations (start activity, take transition, end activity, create scope,
destroy scope, notify listeners) and runs them in a loop until the agenda is
empty. At that point every execution is at a wait state or has ended.

A **command** is one call into the engine:
- start an instance;
- complete a task;
- correlate a message;
- execute a job;
- complete an external task.

Each command runs in its own Core Data context. It runs the agenda to
completion and saves once. That save is the transaction.

- **Wait states** (commits) by default:
  - user task and receive task;
  - message, timer and signal catch events;
  - the event-based gateway;
  - an external service task.
- **Asynchronous continuations.** `asyncBefore` and `asyncAfter` on any
  activity add a commit boundary: the command stops there and leaves a job
  that continues from that point.
- **Failure rolls everything back.** An unhandled failure discards the
  context, which leaves the instance at its last commit. Side effects outside
  the database are not undone, which is why I/O belongs in external tasks or
  behind an async continuation.
- **Optimistic locking.** Every row carries a version (Core Data's `Z_OPT`),
  and a save that loses a race fails with a conflict and changes nothing. The
  job executor retries a conflicted job without spending a retry. An API
  caller gets the error and decides whether to retry.

There is no per-instance queue. Commands on one instance may run
concurrently; conflicts are what optimistic locking is for. Exclusive jobs
keep the common case free of them.

## Service tasks

A service task is either of two kinds, as in the reference:

- **Delegate.** An in-process `UDServiceDelegate` runs *inside* the command,
  synchronously, and its failure rolls the command back. It is meant for
  quick, local work. Combined with `asyncBefore`, it runs from a job with
  retries.
- **External task.** The task waits under a **topic**. Workers fetch and lock
  tasks for a topic, with a worker id and a lock duration. A worker then does
  one of:
  - completes the task, with variables;
  - reports a failure, with the retries left and a retry delay; when retries
    reach zero, an incident is raised;
  - reports a BPMN error, which the task's error boundary events can catch;
  - extends its lock.

  Tasks have priorities.

The asynchronous `UDServiceTaskHandler` of today becomes an **in-process
external-task worker**: the engine fetches and locks for the handler's
topics and calls it on the worker queue. So the handler API survives, and a
worker in another process works the same way, through the same service.

## Jobs and the job executor

A job is one of:
- a **timer**, for a timer event;
- an **async continuation**, before or after an activity;
- **asynchronous event handling**, added later.

Each job has:
- a due date and a priority;
- **retries**: three attempts by default, or as a retry cycle such as
  `R5/PT5M`;
- a lock owner and a lock expiry;
- an exclusive flag, on by default;
- the last failure's message and details.

The job executor:

1. **Acquires** jobs that are due, unlocked (or whose lock has expired), have
   retries left and whose instance is not suspended. It locks them with its
   owner id and an expiry, ordering by priority when that is configured.
2. **Executes** each job as its own command. Exclusive jobs of the same
   process instance run one after another, never side by side.
3. **On failure,** it rolls back the job's command, and in a separate
   transaction decrements retries, records the failure and unlocks the job,
   due again after the retry cycle's delay. When retries reach zero it
   raises an **incident**. Setting retries again resolves it.

On a single node the owner is the process. Several nodes share the job table
the same way, with no further design needed.

## Variables

Variables live on scope executions and, for task-local values, on tasks.
- **Reading** walks up the scope chain.
- **`setVariable`** updates the variable in the nearest scope that has it,
  and otherwise creates it on the process instance.
- **`setVariableLocal`** always writes to the current scope.
- **Input and output mappings** copy values between an activity's scope and
  its parent.

A variable row stores:
- a type tag: string, boolean, integer, double, date, bytes, null, or JSON
  for arrays and dictionaries;
- the value in typed fields (text, integer, double, bytes).

So variables can be queried, and read by a worker in any language.

## Events and correlation

Waiting catch events are **event subscriptions**: type (message, signal,
and later compensation and conditional), event name, execution, activity.

A message is correlated by:
- its name;
- the process instance's **business key**;
- equality on process variables.

It can also start an instance through a message start event. Business key
plus variables replaces today's separate correlation table.

Timers are jobs. Boundary events subscribe on the host activity's scope
execution, and interrupting ones cancel that scope.

## User tasks

A task row holds:
- name, definition key, assignee;
- candidate users and groups (identity links);
- due date, follow-up date, priority, creation time;
- its execution and process instance.

Completing a task signals its execution. Identity management itself (users,
groups, passwords) is out of scope. Assignees and groups are plain strings,
resolved by the application.

## History

History is written in the same transaction as the runtime change, at the
configured level:

| Level | Records |
|---|---|
| NONE | nothing |
| ACTIVITY | process instances, activity instances, task instances |
| AUDIT (default) | the above, and the latest value of each variable |
| FULL | the above, every variable update, incidents, and a job log |

Runtime rows are deleted when their instance ends, so runtime tables stay
small. History is kept until a history time-to-live removes it.

## Core Data model

A new `Model/UDWorkflow.xcdatamodeld`. Relationships are Core Data
relationships, so a command faults in only the executions it touches.

| Group | Entities |
|---|---|
| Repository | `UDDeployment`, `UDResource` (BPMN bytes), `UDDefinitionRecord` (key, version, deployment, resource, suspended) |
| Runtime | `UDExecution` (parent/children, process instance, activity id, activity instance id, active, concurrent, scope, business key, suspended), `UDVariable`, `UDTask`, `UDIdentityLink`, `UDEventSubscription`, `UDJob`, `UDExternalTask`, `UDIncident` |
| History | `UDHistoricProcessInstance`, `UDHistoricActivityInstance`, `UDHistoricTaskInstance`, `UDHistoricVariable`, `UDHistoricVariableUpdate`, `UDHistoricIncident`, `UDHistoricJobLog` |

## BPMN extensions and expressions

**Extensions.** Settings BPMN has no attribute for are read and written in
Camunda's `camunda:` namespace:
- `asyncBefore`, `asyncAfter`, `exclusive`;
- `type="external"` with `topic`;
- `assignee`, `candidateUsers`, `candidateGroups`, `dueDate`;
- `failedJobRetryTimeCycle`;
- input and output mappings.

Files from Camunda Modeler therefore run unchanged. A `ud:` attribute is
added only where the reference has nothing equivalent, and there should be
very few.

**Expressions are FEEL**, the expression language standardised with DMN.
Where an expression appears, the file says which language it is in:
- the definitions' `expressionLanguage`;
- an expression's own `language` attribute;
- or the `=` prefix Camunda 8 files use.

The engine implements a FEEL subset, grown as constructs need it:
- literals, paths and comparisons;
- `and`, `or`, `not()`;
- ranges and `in`;
- simple arithmetic and string functions.

For Camunda 7 files there is also a **compatibility subset of the `${...}`
syntax**: comparisons, `&&`, `||`, `!` and property paths, with no method
calls or bean lookups. It exists only so those files run, and it is not
extended beyond that.

**XPath is an option** as a second language. It is the specification's
default, and XFormsKit (`../XFormsKit`) already has a solid XPath
interpreter that could evaluate it over the variables. It is not planned;
it is noted because it would cost little.

The BPMN 2.0 specification's own default expression language is XPath,
which executable engines have almost never implemented. Camunda 7 inherited
`${...}` (the Java EE Unified Expression Language) from Activiti, which
predates FEEL; Camunda 8 moved to FEEL.

## Deviations from the reference

- **No Java.** Delegates, listeners and scripts are Objective-C objects found
  by key. No JavaScript.
- **No identity service**, no CMMN, no DMN, no forms engine.
- **One node first.** The job executor is written for many, but only one is
  tested.
- **`asyncAfter` with several outgoing flows**, which the reference's
  documentation leaves open: the node finishes in the current transaction
  -- a join fires, a task completes -- and one job takes its outgoing flows,
  evaluating their conditions when it runs. Refused on an event-based
  gateway, which waits for its events.
- **Priorities are whole numbers.** `camunda:taskPriority` as an
  expression is refused on deployment.
- **History cleanup** runs on demand (`cleanUpHistory:`) or every
  `historyCleanupInterval` seconds, not in a daily batch window, and only
  by end time. A definition without `camunda:historyTimeToLive` keeps its
  history; the reference requires one on every deployment.

## Implementation order

Each step lands with the existing scenarios passing again on GNUstep and
macOS:

1. ~~**Repository.** The new model's repository entities, deployment with
   engine-assigned versions and duplicate filtering, and definitions loaded
   back from stored BPMN.~~ Done, with standard BPMN reading and writing for
   the current subset.
2. ~~**Core.** Executions, the agenda and behaviours for today's subset,
   commands with one context and one save, optimistic locking, scoped
   variables, tasks, event subscriptions, business-key and variable
   correlation.~~ Done. So that nothing the token engine did was lost, it
   also brought forward what the existing scenarios needed from later
   steps: timer jobs with a basic executor (acquire, then execute), external
   tasks with the in-process worker and three attempts, message start
   events, and history of process instances and latest variable values.
   Still to come in those steps: retry cycles and incidents, async
   continuations, the external task service, timer start events, and the
   rest of history.
3. ~~**Jobs.** Timers, async continuations, exclusive execution, retries,
   retry cycles and incidents.~~ Done, with timer start events and
   `managementService` (jobs, incidents, running a job, giving retries
   back), and `jobExecutorActive` for stepping through jobs in tests.
   Later completed: `asyncAfter` on gateways and async continuations on
   boundary events (see Deviations for how `asyncAfter` behaves).
4. ~~**External tasks.** Fetch-and-lock, the in-process worker behind
   `UDServiceTaskHandler`, and BPMN errors from workers.~~ Done:
   `externalTaskService` fetches and locks by topic (priority, then age),
   completes, reports failures with a retry timeout and BPMN errors,
   extends and releases locks, and gives retries back, resolving the
   incident. The in-process worker is a client of it. Later completed:
   `camunda:taskPriority` on tasks and processes (whole numbers), and the
   variables a fetch returns, per topic.
5. ~~**History**, by level.~~ Done: process, activity and task instances
   (canceled ones marked), latest variable values, and at FULL every
   variable update, incidents from open to resolved or deleted, and the
   job log. Later completed: `camunda:historyTimeToLive` with cleanup of
   what outlived it, and the level recorded in the store, which refuses an
   engine configured otherwise.

The token engine is removed at step 2. After that come standard BPMN
reading (phase 2) and the remaining constructs (phase 5), each one following
the reference's documented behaviour.

# Durable execution on Core Data — design

> **Superseded** by [execution-model.md](execution-model.md): UDWorkflow now
> follows Camunda 7's execution model, and the token-marking engine this page
> describes was removed with step 2 of that design. Kept for the record.

Status: steps 1–3 implemented (see "Build order"); retries and incidents are
next. Scope: phase 1 of the roadmap, an embeddable single-node engine whose
state lives in FreeCoreData (Apple's Core Data on macOS), and nothing that
rules out several engines sharing one database later.

## Goals

- **Durable.** A crash loses nothing that was committed, and nothing reaches
  the outside world (service calls, work items, thrown messages) until the
  state that caused it is committed.
- **Frugal.** A waiting instance costs one row, not an object graph, a
  dispatch queue and a timer source. Idle memory does not grow with the
  number of instances.
- **One code path.** The in-memory store used by tests and the SQLite /
  PostgreSQL / MySQL stores used in production go through the same
  Core Data code, so what the tests exercise is what ships.

## The store is a Core Data stack

`UDStore` owns a coordinator and one private-queue context, and runs every
call on it; after each save it resets the context, so no rows stay resident
between units of work. It is opened with a store type and URL, so the backend
is a configuration choice:

| Use | Store type |
|---|---|
| Tests | `NSInMemoryStoreType` (`+inMemoryStore:`) |
| Embedded | `NSSQLiteStoreType` (`+SQLiteStoreAtURL:error:`) |
| Server, later | `CDPostgreSQLStoreType`, `CDMySQLStoreType` (link the backend) |

The model is compiled from an `.xcdatamodeld`, so the library has a momc build step and the same model runs on Apple's Core Data and FreeCoreData.

`UDStore` is a class, not a protocol: there is one implementation, and the
backends vary underneath it through Core Data.

### Entities

`Model/UDWorkflow.xcdatamodeld`:

| Entity | Attributes | Notes |
|---|---|---|
| `UDDeployment` | processId, version, bpmn, deployedAt | Unique (processId, version). Redeploying different BPMN under the same version is an error. |
| `UDInstance` | instanceId, processId, version, status, state, error fields, createdAt, updatedAt | `state` is a binary plist of tokens, variables, fork counters, token serial and embedded subprocess children. Core Data's `Z_OPT` is the optimistic version. |
| `UDJob` | jobId, instanceId, tokenId, kind, actionKey, dueAt, attempts, owner, lockedUntil, lastError | kind = service or timer. |
| `UDCorrelation` | instanceId, key, value | Values are tagged text (`s:SO-9`, `n:7`), so a string and a number never match. |

`status` is active / completed / failed, so listing and cleanup queries never
unpack `state`.

The model declares fetch indexes (instance id, job due time, correlation
key/value) the way Xcode writes them. Apple's Core Data creates them;
**FreeCoreData does not yet** — neither its momc nor its SQL stores know
`NSFetchIndexDescription` — so on GNUstep those lookups scan their table.
That is a FreeCoreData feature to add, measured first.

Tokens stay a blob rather than rows: an instance is always loaded and saved
whole, and one row update per step is cheaper than a row per token. Completed
tokens are pruned before the save.

Variables must be property-list values (strings, numbers, dates, data,
arrays, dictionaries). The API checks this on the way in and fails early,
rather than failing at commit time; a service result that is not one fails
the task.

## A unit of work

Everything that happens to an instance is one unit of work. Units run on a
fixed set of serial queues, the instance id picking the queue, so they are
serial per instance and bounded in number however many instances exist:

1. **Load** the instance from its row. There is no cache: the object lives
   for one unit and is dropped.
2. **Apply the input:** start, complete user task, message, service result,
   timer due, thrown error. An input can reject (no such user task, no
   catch for the message), and then nothing is committed.
3. **Run** until no token is ready, in the instance and its subprocesses.
   Callbacks are *collected* into the unit, not made.
4. **Commit** once: the instance row, its jobs and its correlation rows, in
   one context save (one database transaction).
5. **After the commit,** send new service jobs to the worker queue, re-arm
   the scheduler, and deliver the collected callbacks on the engine's
   callback queue — never on an instance queue, so a callback can call back
   into the engine.

Jobs are not bookkept step by step: they are *derived* from the marking at
commit time. A token waiting on a service or script task needs a service
job; a token waiting on a timer event needs a timer job at its `dueAt`. The
store matches that set against the stored jobs by (kind, token), inserts
what is missing and deletes what is no longer needed — a cancelled timer, a
task an interrupting boundary took away, every job of a finished instance.

If the commit fails, the instance is dropped, traces still go out, and the
delegate gets `didFailToCommit:`. The database still holds the last committed
state, whose jobs drive the instance forward again. Nothing from the failed
unit has leaked.

Token ids are unique in the whole instance tree (children draw from the
root's serial), so `(instanceId, tokenId)` names any token, including one in
an embedded subprocess.

## Jobs

A **service task** parks its token; the commit writes a service job. The job
is sent to the handler only after that commit. The result arrives as a new
unit of work, whose commit deletes the job; a result for a token that has
moved on is stale and only drops the job. `-openWithError:` sends every
service job in the store again, so delivery is at-least-once, and
`UDServiceInvocation.jobId` — the same across repeats — is the idempotency
key handlers use to spot a repeat.

A **timer** puts an absolute `dueAt` on its token; the commit writes a timer
job. The engine keeps one dispatch timer source aimed at the earliest job
(one fetch, sorted, limit 1), not a source per timer, and runs due jobs in
batches. A restart re-arms at the time that is left. Timers that are already
due fire in the step that reaches them. A timer unit that cannot commit
backs the scheduler off for a second rather than spinning.

**Failures** (next, step 4): a failed service job is retried with backoff
(`ud:retries`, default 3). When retries run out, it becomes an incident: the
token and the instance are marked incident, and nothing else in the instance
is failed. `retryIncident:` resets the job. An error boundary still takes
precedence over retrying. Today a failed service call without an error
boundary fails the instance.

## Definitions

`-deployDefinition:error:` makes a definition runnable in the engine and
records its BPMN in `UDDeployment`. Instances run on the definitions deployed
into the engine, so an application deploys every version that may still have
instances before `-openWithError:`. The stored BPMN is not yet enough to
rebuild every definition (the writer emits a subprocess as a reference, and
target-action conditions not at all); once phase 2 makes the BPMN complete,
the engine can load a definition it was not handed from the store.

## API

```objc
UDEngine *engine = [[UDEngine alloc] initWithStore:[UDStore SQLiteStoreAtURL:url error:&error]];
engine.serviceHandler = handler;
[engine deployDefinition:definition error:&error];
[engine openWithError:&error];            /* resend service jobs, arm timers */

NSString *instanceId = [engine startProcess:@"purchase" variables:vars error:&error];
[engine completeUserTask:tokenId instanceId:instanceId variables:vars error:&error];
[engine deliverMessage:@"paid" payload:vars instanceId:instanceId error:&error];
[engine deliverMessage:@"paid" payload:vars correlationKey:@"orderId" value:@"SO-9" error:&error];
UDProcessInstance *snapshot = [engine instanceWithId:instanceId error:&error];
[engine waitUntilSettled:instanceId timeout:10];   /* service calls in flight */
```

Each call returns once its own unit is committed. `waitUntilSettled:` waits
for the service calls the instance has in flight; timers and user tasks are
waits, not work. Delegates and the user-task port receive a
`UDProcessInstance` snapshot.

## Left open for later, on purpose

- **Several engines on one database.** `Z_OPT` already turns a concurrent
  write into a merge conflict. Job rows carry `owner` and `lockedUntil`
  columns now, unused, so that claiming jobs is an addition, not a
  migration.
- **History / audit trail**: a history row per step.
- **Definition migration** of running instances to a new version.

## Build order

Each step lands with its tests green on GNUstep and macOS:

1. ~~`UDStore` over the model; `UDMemoryStore` replaced by its in-memory
   configuration; commit per unit of work.~~
2. ~~Service jobs with the outbox and recovery; absolute timers and the
   single scheduler.~~
3. ~~Id-based API, no resident instances, correlation index.~~
4. Retries and incidents.

The library links CoreData: FreeCoreData on GNUstep, pinned in CI the way
ODataStore pins it; `CoreData.framework` in the Xcode project.

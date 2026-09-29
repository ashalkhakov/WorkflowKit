# Durable execution on Core Data — design

Status: proposed. Scope: phase 1 of the roadmap, an embeddable single-node
engine whose state lives in FreeCoreData (Apple's Core Data on macOS), and
nothing that rules out several engines sharing one database later.

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

`UDCoreDataStore` owns a coordinator and one private-queue context. It is
opened with a store type and URL, so the backend is a configuration choice:

| Use | Store type |
|---|---|
| Tests, demos | `NSInMemoryStoreType` (replaces today's `UDMemoryStore`) |
| Embedded | `NSSQLiteStoreType` (in the framework) |
| Server, later | `CDPostgreSQLStoreType`, `CDMySQLStoreType` (link the backend) |

The model is built in code (`UDStoreModel`), not compiled from an
`.xcdatamodeld`, so the library has no momc build step and the same model
runs on Apple's Core Data and FreeCoreData.

### Entities

| Entity | Attributes | Notes |
|---|---|---|
| `UDDeployment` | processId, version, bpmn (binary XML), sha256, deployedAt | Unique (processId, version). Redeploying different XML under the same version is an error. |
| `UDInstanceRow` | instanceId, processId, version, status, state (binary), error fields, createdAt, updatedAt | `state` is a binary plist of tokens, variables, fork counters, token serial and embedded subprocess children. Core Data's `Z_OPT` is the optimistic version. |
| `UDJobRow` | jobId, instance, tokenId, kind, actionKey, dueAt, attempts, lastError | kind = service or timer. Index on dueAt. |
| `UDCorrelationRow` | instance, key, value | Compound index (key, value). Replaces the full scan. |

`status` is running / waiting / completed / failed / incident, so listing and
cleanup queries never unpack `state`.

Tokens stay a blob rather than rows: an instance is always loaded and saved
whole, and one row update per step is cheaper than a row per token. Completed
tokens are pruned before the save.

Variables must be property-list values (strings, numbers, dates, data,
arrays, dictionaries). The API checks this on the way in and fails early,
rather than failing at commit time.

## A unit of work

Everything that happens to an instance is one unit of work, on that
instance's serial queue:

1. **Load** the instance from the cache, or from its row.
2. **Apply the input:** start, complete user task, message, service result,
   timer due.
3. **Drain** until no token is ready. Side effects are *collected* into the
   unit of work, not performed: new and cancelled jobs, work items to
   publish, messages thrown, delegate notifications.
4. **Commit** once: the instance row, job inserts and deletes, correlation
   rows, in one context save (one database transaction).
5. **After the commit,** send service jobs to the worker queue, re-arm the
   scheduler, publish work items and notify the delegate.

If the commit fails, the in-memory instance is dropped and the delegate gets
the error. The database still holds the last committed state, whose jobs
drive the instance forward again. Nothing from the failed unit has leaked.

Today's engine saves after every token fire and ignores the result. This
replaces both: one save per unit of work, and a failed save is an error.

## Jobs

A **service task** writes a service job in the commit that parks its token.
The job is sent to the handler only after that commit. The result arrives as
a new unit of work, which deletes the job. After a crash, recovery sends every
service job again, so delivery is at-least-once. `UDServiceInvocation` gains
`jobId` and `attempt`, and `jobId` is the idempotency key handlers use to
spot a repeat.

A **timer** writes a timer job with an absolute `dueAt`. The engine keeps
one dispatch timer source aimed at the earliest `dueAt` (one fetch, sorted,
limit 1), not a source per timer. A restart re-arms at the time that is
left, not the full duration. Timers that are already due fire in the step
that reaches them (already the case for catch events).

**Failures:** a failed service job is retried with backoff
(`ud:retries`, default 3). When retries run out, it becomes an incident: the
token and the instance are marked incident, and nothing else in the instance
is failed. `retryIncident:` resets the job. An error boundary still takes
precedence over retrying.

## Memory

Hydrated instances live in a small bounded cache. An instance leaves the
cache once its unit of work commits with nothing in flight. So a thousand
instances waiting on people are a thousand rows, and the only resident
objects are those actually running a step.

## API changes

Instances are addressed by id, because the object a caller got from
`startProcess:` may have been evicted by the time the caller acts again:

```objc
- (NSString *)startProcess:(NSString *)processId variables:... error:...;
- (BOOL)completeUserTask:(NSString *)tokenId instanceId:(NSString *)instanceId
               variables:(NSDictionary *)variables error:(NSError **)error;
- (BOOL)deliverMessage:... instanceId:... error:...;
- (UDProcessInstance *)instanceWithId:(NSString *)instanceId error:...; /* a snapshot, for inspection */
- (BOOL)deployDefinition:(UDProcessDefinition *)definition error:...;
- (BOOL)openWithError:(NSError **)error;   /* recovery: resend service jobs, arm the scheduler */
```

Delegates keep receiving a `UDProcessInstance`, valid for the duration of the
callback. The synchronous "run until settled" calls stay, as test and demo
conveniences built on the async ones.

`UDInstanceStore` becomes the unit-of-work protocol (commit, load, next
due job, correlation lookup, deployments). `UDCoreDataStore` is the one
implementation. Keeping it a protocol keeps other stores possible without
promising any.

## Left open for later, on purpose

- **Several engines on one database.** `Z_OPT` already turns a concurrent
  write into a merge conflict. Job rows get `owner` and `lockedUntil`
  columns now, unused, so that claiming jobs is an addition, not a
  migration.
- **History / audit trail**: a `UDHistoryRow` per step, after the core
  works.
- **Definition migration** of running instances to a new version.

## Build order

Each step lands with its tests green on GNUstep and macOS:

1. `UDCoreDataStore` + `UDStoreModel`; `UDMemoryStore` becomes the
   in-memory configuration of it; commit per unit of work. The tests run
   against both in-memory and SQLite.
2. Service jobs with the outbox and recovery; absolute timers and the single
   scheduler.
3. Id-based API, eviction, correlation index.
4. Retries and incidents.

The library links CoreData from here on: FreeCoreData on GNUstep, pinned in
CI the way ODataStore pins it; `CoreData.framework` in the Xcode project.

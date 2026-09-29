# UDWorkflow — BPMN 2.0 executable subset

Target: embeddable GNUstep / Objective-C engine (ARC, libdispatch). Prefix **UD**. The diagram is the program. Tokens are the marking. A step is one graph rewrite.

This is not Camunda coverage. V2 is the set of constructs the engine will load, persist, and fire. Everything else is ignored or rejected on import.

## 1. In scope

### Process graph

| Construct | BPMN element | Engine type |
|---|---|---|
| Executable process | `process` `isExecutable="true"` | `UDProcessDefinition` |
| Sequence flow | `sequenceFlow` | `UDSequenceFlow` |
| Conditional flow | `conditionExpression` | `UDComparisonCondition` |
| Default flow | `exclusiveGateway/@default` | `UDGateway.defaultFlowId` |
| Version | `ud:version` | `definition.version` |

### Activities

| Construct | BPMN | Notes |
|---|---|---|
| User task | `userTask` | Waiting token + `UDUserTaskPort`. `ud:assignee`. |
| Service task | `serviceTask` | Worker queue. `implementation` / `ud:action`. |
| Script task | `scriptTask` | Same handler path as service. ObjC action key only. |
| Embedded subprocess | `subProcess` | Child `UDProcessDefinition`. Host token waits; variables merge on complete. |

### Gateways

| Construct | BPMN | Semantics |
|---|---|---|
| Exclusive split/merge | `exclusiveGateway` | First true condition, else default. Merge is pass-through. |
| Parallel split/join | `parallelGateway` | Split stamps `forkId`. Join waits on that cohort. |
| Inclusive split/join | `inclusiveGateway` | All true conditions (else default). Join waits for `joinExpected` of that `or-*` fork. |
| Event-based | `eventBasedGateway` | First catch (message/timer) wins; sibling catches with `egw-*` fork are cancelled. |

### Events

| Construct | BPMN | Behaviour |
|---|---|---|
| None start / end | `startEvent` / `endEvent` | Create marking / complete token. |
| Message start | `startEvent` + `messageEventDefinition` | Token waits until `deliverMessage:`. |
| Timer start | `startEvent` + `timerEventDefinition` | dispatch timer, then leave. |
| Message catch | `intermediateCatchEvent` + message | Wait for matching name on this instance. |
| Timer catch | `intermediateCatchEvent` + timer | `timeDuration` as seconds (`PTnS`). |
| Message throw / message end | throw / end + message | `UDEngineDelegate` `didThrowMessage`. |
| Boundary message | `boundaryEvent` `attachedToRef` | `cancelActivity` interrupting or not. |
| Boundary timer | `boundaryEvent` + timer | Armed when the host task is entered. |
| Boundary error | `boundaryEvent` + `errorEventDefinition` | Service failure or `throwError:` with matching `errorRef` (`*` = any). |

## 2. Event rules

Timers use libdispatch sources on the instance serial queue. Duration is `NSTimeInterval`. ISO-8601 export is `PTnS`. On resume from `UDMemoryStore` a waiting timer is re-armed for the **full** duration (remaining time is not persisted in V1).

Messages are delivered explicitly: `deliverMessage:payload:instance:` or `deliverMessage:payload:correlationKey:value:` against a `UDMemoryStore` index on `instance.correlationKeys`.

**Interrupting boundary:** host activity token is completed, other boundaries on that host are disarmed, flow leaves the boundary.

**Non-interrupting:** host keeps waiting; boundary leaves on its own outgoing flow. V1 fires a non-interrupting boundary once.

Service and script waits that are snapshotted come back `Ready` (at-least-once). User-task and message waits stay `Waiting`.

## 3. Conditions

No JavaScript. Sequence-flow conditions are `UDComparisonCondition` objects:

```
amount > 1000
approved == YES
name != "x"
```

Operators: `==` `!=` `>` `>=` `<` `<=`.

Values: integers, floats, `YES`/`NO`/`true`/`false`, quoted strings.

`UDActionCondition` exists for in-process target-action checks and does **not** round-trip through BPMN XML.

## 4. Out of scope (V2 reject or ignore)

| Family | Examples |
|---|---|
| Collaboration | pool, lane, messageFlow, conversation, choreography |
| Gateways | complex |
| Activities | event subprocess, call activity, transaction, ad-hoc, multi-instance, loop, compensation |
| Tasks | manual, business rule, send, receive, receive-task as event stand-in |
| Events | escalation, cancel, compensate, signal, link, terminate, conditional, multiple, parallel multiple |
| Event use | non-interrupting start in event subprocess |
| Data | data object, data store, data association, properties as BPMN itemAware |
| Execution extras | general unstructured OR-join, tokens on sequence flows as first-class marking, full BPMN DI edge waypoints |

## 5. XML shape

Namespace `http://www.omg.org/spec/BPMN/20100524/MODEL` with extensions in `https://udworkflow.local/bpmn` (prefix `ud`). Writer emits both standard child event definitions and `ud:*` attributes so the reader can stay attribute-driven.

Round-trip path:

```
UDProcessDefinition → UDBpmnWriter → XML → UDBpmnReader → UDDefinitionBuilder → UDProcessDefinition
```

Import of unknown elements is ignored; missing required V1 structure fails `build:`.

## 6. Runtime contract

| Piece | Rule |
|---|---|
| Token | Sits on a node. Fire consumes it and produces successors. |
| Instance queue | Serial dispatch queue. All marking changes happen here. |
| Worker queue | Concurrent. Service I/O only. Completion hops back. |
| Public API | Delegates and target-action. Blocks are not part of the model. |
| Persistence | `UDInstanceStore` snapshot of tokens + variables + definition id. |

Node layout for the designer is stored on each `UDFlowNode` as `boundsX/Y/Width/Height` and exported as `ud:x` `ud:y` `ud:w` `ud:h`.

Tests: `Tests/UDWorkflowTests.m` is an XCTest case (`#import <XCTest/XCTest.h>`). On GNUstep, `make test` builds the library and runs the bundle under tools-xctest; see `CLAUDE.md` for the patched stack it is built against.

V3 candidates: call activity, error start in event subprocess, signal events, multi-instance, full BPMN DI edge waypoints.

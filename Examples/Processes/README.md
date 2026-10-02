# Example processes

Each directory is one deployment: its BPMN files, with the decisions
(`.dmn`) they use. Together they cover the subset the engine runs
(`WorkflowKit-BPMN-Subset.md`). They are runnable as they are:

- `Tests/WFExamplesTests.inc` deploys each directory and runs it through
  the scenario its documentation describes, on every store.
- `wf-serve -Deployments Examples/Processes -Plugins Examples/Plugins/obj`
  deploys all of them, to try in WorkflowDesk or open in WorkflowDesigner
  (File ▸ Open from Server), after `make -C Examples/Plugins`.

Service, send and script tasks are external tasks; the topic each one
names is what a worker answers. The delegates and listeners the processes
call by name are in `Examples/Plugins` (`WFExampleDelegates.h`), as an
application's would be: `${audit}` keeps an audit trail, `${mailer}` puts a
message together from its fields, and `${workload}` routes a task and
sets its due date from its fields.

The diagrams are laid out by the designer's own Arrange, and the pictures
are drawn by its renderer: after changing a file, run
`Apps/WorkflowDesigner/Tools/obj/wkd-arrange` on it, and
`wkd-render file.bpmn docs/examples/name.png` for its picture (see
`Apps/WorkflowDesigner/Tools`).

## Order fulfilment

`order-fulfilment/` — an order from a web shop.

![Order fulfilment](../../docs/examples/order-fulfilment.png)

- A start form (`camunda:formData`) whose `orderNumber` field is the
  business key.
- Exclusive gateways splitting by FEEL conditions (`inStock`,
  `express = true`), with default flows, and one merging.
- A parallel split and join: the card is charged while the order is
  packed.
- User tasks for a candidate group, with a priority computed from the
  order (`=if express then 80 else 50`).
- Service tasks on topics, and a script task (`wf:action`).
- Execution listeners on the process's start and end, one with a field.
- A task listener on create with fields, one of them an expression
  (`=if express then "PT2H" else "P1D"`).
- Input parameters written as a `camunda:list` and a `camunda:map`, and an
  output parameter that builds a FEEL context from them
  (`={customer: packing.customer, items: packing.items, tape: checklist[3]}`).
- A delegate called by name (`${mailer}`) with text and expression fields.

## Loan application

`loan-application/` — scored by a decision table (`risk.dmn`).

![Loan application](../../docs/examples/loan-application.png)

- Three decisions in one file: `applicant-score`, a `COLLECT SUM` table
  whose inputs are FEEL expressions --
  `years and months duration(date(employedSince), today()).years`,
  `debts / income` -- with ranges like `[2..5)`; `loan-risk`, which
  requires it (`informationRequirement`) and reads its score; and
  `loan-limit`, a literal expression.
- Two business rule tasks, each result mapped to one value (`singleEntry`),
  and a condition using both (`risk = "low" and amount <= maxLoan`).
- Conditions in FEEL and in Camunda 7's `${...}`, side by side.
- An underwriter's task with a due date two days ahead
  (`=now() + duration("P2D")`) and a generated form with read-only and
  required fields.
- Candidate starters on the process (`branch-staff`).
- A task listener routing large loans to a senior underwriter
  (`=if amount > 50000 then "senior-underwriter" else null`), and a
  `camunda:map` summary for the underwriter.
- An end listener with an expression field, and a send task that is a
  delegate with fields.

## Travel booking

`travel-booking/` — book, and undo the bookings when payment fails.

![Travel booking](../../docs/examples/travel-booking.png)

- Compensation: a boundary event on each booking, associated with its
  handler (`isForCompensation`), and an intermediate compensation throw
  that runs them, newest first.
- An error boundary catching the BPMN error `card-declined` that a worker
  answers with.

## Customer onboarding

`customer-onboarding/` — wait for documents, then check what the customer
needs.

![Customer onboarding](../../docs/examples/customer-onboarding.png)

- An event-based gateway between a message (`documents-received`) and a
  timer (`P7D`), in a loop: the customer is reminded every week.
- An inclusive split and join: only the checks whose conditions hold run
  (`expectedVolume > 100000`, `not(country in ["DE", "FR", "NL"])`).
- A non-interrupting timer boundary (`P2D`) that chases someone while the
  task goes on.

## Expense review

`expense-review/` — several reviewers, two approvals enough.

![Expense review](../../docs/examples/expense-review.png)

- A condition over a list of contexts:
  `some line in lines satisfies line.amount > 500`.
- A parallel multi-instance user task over a collection (`reviewers`),
  each instance assigned to its element variable (`${reviewer}`), with
  inputs computed from the lines (`=sum(lines.amount)`,
  `=max(lines.amount)`).
- An output mapping counting approvals, and a completion condition
  (`approvals >= 2`) that withdraws the reviews still open.
- A sequential multi-instance send task, a delegate whose fields read
  each instance's element variable.

## Support ticket

`support-ticket/` — resolve within eight hours.

![Support ticket](../../docs/examples/support-ticket.png)

- An embedded subprocess with an interrupting timer boundary (`PT8H`).
- An escalation thrown inside it and caught, without interrupting, on its
  boundary.
- A task listener whose due date depends on the ticket
  (`=if priority = "urgent" then "PT1H" else "PT4H"`), and start and end
  listeners on the subprocess.
- Event subprocesses: a non-interrupting message start
  (`customer-replied`), and an interrupting one (`ticket-withdrawn`) that
  ends everything with a terminate end event.

## Shipping

`shipping/` — two processes, one calling the other.

![Shipment](../../docs/examples/shipment.png)

![Pack and ship](../../docs/examples/pack-and-ship.png)

- A call activity passing variables in and out (`camunda:in`,
  `camunda:out`) and the business key.
- Input and output parameters on a task (`=count(items)`).
- An asynchronous continuation (`camunda:asyncBefore`) with a retry cycle
  (`R3/PT5M`), and a manual task.

## Inventory

`inventory/` — three processes.

![Restock](../../docs/examples/restock.png)

![Weekly stock count](../../docs/examples/stock-count.png) ![Stock report](../../docs/examples/stock-report.png)

- A conditional catch event that waits until `stock < reorderLevel`,
  looking again when `stock` changes.
- Link events carrying the flow from one half of the diagram to the
  other.
- A timer start event with a cycle (`R/P7D`), a signal end event, and a
  signal start event in another process that the signal starts.

#!/bin/sh
# A purchase request over HTTP: wf-serve on the example deployment, started
# through its form, approved through the task's, and found in the history;
# an external task worked by a worker over HTTP, its failure an incident
# that a retry resolves; then what HTTPServerKit adds: health, readiness,
# and the requests counted.
#
#   ./check.sh path/to/wf-serve
set -eu
serve=$1
port=${WF_CHECK_PORT:-18089}
root="http://127.0.0.1:$port/api"
log=$(mktemp)
"$serve" -StoreType InMemory -Deployments Examples/deployments -Port "$port" -DevelopmentUser checker 2>"$log" &
pid=$!
trap 'kill $pid 2>/dev/null || true; rm -f "$log"' EXIT

fail() { echo "check: $*" >&2; cat "$log" >&2; exit 1; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
post() { curl -sS -X POST -H 'Content-Type: application/json' -d "$2" -w '\n%{http_code}' "$root/$1"; }

for i in $(seq 1 100); do
  curl -sf "$root/\$metadata" >/dev/null 2>&1 && break
  kill -0 $pid 2>/dev/null || fail "wf-serve stopped"
  sleep 0.1
done
curl -sf "$root/\$metadata" >/dev/null || fail "wf-serve does not answer"

started=$(post SubmitStartForm '{"Key":"purchase","Instance":"<data><reference>PO-1</reference><item>Chairs</item><amount>12</amount></data>"}')
[ "$(echo "$started" | tail -n 1)" = 200 ] || fail "start: $started"
key=$(echo "$started" | head -n 1 | json "d['BusinessKey']")
[ "$key" = PO-1 ] || fail "business key $key"
instance=$(echo "$started" | head -n 1 | json "d['ProcessInstanceId']")

task=$(curl -sS "$root/Tasks" | json "d['value'][0]['TaskId']")
form=$(curl -sS "$root/Tasks('$task')/WorkflowKit.FormInstance()" | json "d['value']")
echo "$form" | grep -q '<amount>12</amount>' || fail "the task's form: $form"
refused=$(post "Tasks('$task')/WorkflowKit.SubmitForm" '{"Instance":"<data/>"}')
[ "$(echo "$refused" | tail -n 1)" = 400 ] || fail "an unapproved form was taken: $refused"
[ "$(post "Tasks('$task')/WorkflowKit.Claim" '{"UserId":"ann"}' | tail -n 1)" = 204 ] || fail "claim"
done=$(post "Tasks('$task')/WorkflowKit.SubmitForm" '{"Instance":"<data><approved>true</approved></data>"}')
[ "$(echo "$done" | tail -n 1)" = 204 ] || fail "approve: $done"

state=$(curl -sS "$root/HistoricProcessInstances('$instance')" | json "d['State']")
[ "$state" = COMPLETED ] || fail "the instance is $state"
ended=$(curl -sS "$root/Tasks/\$count")
[ "$ended" = 0 ] || fail "$ended tasks left"

# A worker: a process deployed over HTTP, its external task fetched, failed
# for good -- an incident -- given an attempt again, fetched and completed.
bpmn='<definitions xmlns="http://www.omg.org/spec/BPMN/20100524/MODEL" xmlns:camunda="http://camunda.org/schema/1.0/bpmn" targetNamespace="urn:check"><process id="charge" isExecutable="true"><startEvent id="s"/><sequenceFlow id="f1" sourceRef="s" targetRef="charge"/><serviceTask id="charge" camunda:type="external" camunda:topic="charge"/><sequenceFlow id="f2" sourceRef="charge" targetRef="e"/><endEvent id="e"/></process></definitions>'
deploy=$(python3 -c 'import json,sys; print(json.dumps({"Name": "charge", "Resources": {"charge.bpmn": sys.argv[1]}}))' "$bpmn")
[ "$(post Deploy "$deploy" | tail -n 1)" = 200 ] || fail "deploy the worker's process"
started=$(post StartProcessInstance '{"Key":"charge","Variables":{"amount":25}}')
[ "$(echo "$started" | tail -n 1)" = 200 ] || fail "start charge: $started"
charge=$(echo "$started" | head -n 1 | json "d['ProcessInstanceId']")
fetch='{"WorkerId":"w1","MaxTasks":1,"Topics":{"charge":60}}'
fetched=$(post FetchAndLock "$fetch")
[ "$(echo "$fetched" | tail -n 1)" = 200 ] || fail "fetch: $fetched"
[ "$(echo "$fetched" | head -n 1 | json "d['value'][0]['Variables']['amount']")" = 25 ] || fail "the task's variables: $fetched"
xtask=$(echo "$fetched" | head -n 1 | json "d['value'][0]['ExternalTaskId']")
failed=$(post "ExternalTasks('$xtask')/WorkflowKit.HandleFailure" '{"WorkerId":"w1","ErrorMessage":"card service down","Retries":0,"RetryTimeout":0}')
[ "$(echo "$failed" | tail -n 1)" = 204 ] || fail "failure: $failed"
incident=$(curl -sS "$root/Incidents?\$filter=ProcessInstanceId%20eq%20'$charge'" | json "d['value'][0]['IncidentType']")
[ "$incident" = failedExternalTask ] || fail "no incident: $incident"
[ "$(post "ExternalTasks('$xtask')/WorkflowKit.SetRetries" '{"Retries":1}' | tail -n 1)" = 204 ] || fail "retry"
[ "$(curl -sS "$root/Incidents/\$count")" = 0 ] || fail "the incident is still open"
[ "$(post FetchAndLock "$fetch" | head -n 1 | json "d['value'][0]['ExternalTaskId']")" = "$xtask" ] || fail "not fetched again"
[ "$(post "ExternalTasks('$xtask')/WorkflowKit.Complete" '{"WorkerId":"w1","Variables":{"charged":true}}' | tail -n 1)" = 204 ] \
  || fail "complete"
state=$(curl -sS "$root/HistoricProcessInstances('$charge')" | json "d['State']")
[ "$state" = COMPLETED ] || fail "the charge is $state"

base="http://127.0.0.1:$port"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$base/health")" = 200 ] || fail "health"
ready=$(curl -sS "$base/ready")
[ "$(echo "$ready" | json "d['checks']['store']")" = ok ] || fail "readiness: $ready"
curl -sS "$base/metrics" | grep -q '^http_requests_total{method="POST",route="/api/\*",status="204"}' \
  || fail "the requests are not counted"
echo "check: a purchase request, started, approved and completed over HTTP; an external task failed, retried and completed by a worker; health, readiness, metrics"

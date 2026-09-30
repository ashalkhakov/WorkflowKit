#import <ODataService/ODataService.h>

@class WFProcessEngine;

/*
 * An engine's state as an OData service (ODataKit's ODataService), under
 * the model's API configuration, in the WorkflowKit namespace:
 *
 *   Tasks                     open user tasks
 *   ProcessInstances          running process instances
 *   Variables                 their variables
 *   ProcessDefinitions        deployed definitions, every version
 *   Forms, FormFields         their user tasks' and start events' forms
 *   HistoricProcessInstances  and HistoricTaskInstances, as history keeps them
 *
 * What the engine keeps for itself -- the execution tree, locks, jobs,
 * subscriptions -- is not served (OData.served NO in the model).
 *
 * A variable is a process instance's own (ProcessInstances(id)/Variables),
 * its value in the property of its type: Text, Number, Boolean, Date,
 * Json or Bytes, the others null. Tasks are filtered by them as by any
 * navigation:
 *
 *   Tasks?$filter=ProcessInstance/Variables/any(v: v/Name eq 'amount' and v/Number gt 1000)
 *
 * A task's form is Tasks(id)/Form, its fields in order
 * (Form?$expand=Fields($orderby=Position)); a definition's are
 * ProcessDefinitions(id)/Forms, the start event's IsStartForm. The values
 * a form shows -- each field's variable, else its default -- come from
 * Tasks(id)/WorkflowKit.FormValues() and StartFormValues(Key), a JSON
 * object by field (dates as ISO-8601 text).
 *
 * The service reads the store and never writes it: every change is an
 * action that calls the engine.
 *
 *   StartProcessInstance(Key, BusinessKey, Variables)
 *   CorrelateMessage(Name, BusinessKey, ProcessInstanceId, Variables)
 *   Tasks(id)/WorkflowKit.Complete(Variables), .Claim(UserId),
 *       .Unclaim, .Assign(UserId)
 *   ProcessInstances(id)/WorkflowKit.Suspend, .Activate, .Cancel(Reason),
 *       .SetVariables(Variables), .RemoveVariables(Names)
 *   Tasks(id)/WorkflowKit.SubmitForm(Values)
 *   SubmitStartForm(Key, BusinessKey, Values)
 *
 * A form's submission is checked against its fields before it completes
 * the task or starts the process; values it does not take answer 400.
 *
 * Variables given are a JSON object (Edm.Untyped). An engine error answers
 * with its status: 404 for what is not there, 409 for what its state does
 * not allow, 400 for the rest of what the caller got wrong.
 *
 * Who may call is the application's: give the service an authenticator
 * (ODataAuthentication.h) before it serves requests.
 */
@interface WFODataService : NSObject

/* A service over the engine's store, answering under the root; it keeps
 * the engine. Set anything else on it before its first request. */
+ (ODataService *)serviceForEngine:(WFProcessEngine *)engine serviceRoot:(NSURL *)serviceRoot;

@end

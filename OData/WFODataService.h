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
 *   Forms                     their user tasks' and start events' forms
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
 * A form is an XForms document: a task's is Tasks(id)/Form, its Document
 * the XHTML+XForms text (none for a form key the application resolves);
 * a definition's are ProcessDefinitions(id)/Forms, the start event's
 * IsStartForm. The instance a form opens with, as its handler gives it,
 * is Tasks(id)/WorkflowKit.FormInstance() or StartFormInstance(Key), XML
 * text; submitting one hands it to the handler (WFFormHandler), whose
 * variables complete the task or start the process.
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
 *   Tasks(id)/WorkflowKit.SubmitForm(Instance)
 *   SubmitStartForm(Key, BusinessKey, Instance)
 *
 * An instance that is not XML, or that the handler refuses, answers 400;
 * a form without a handler, 500.
 *
 * Variables given are a JSON object (Edm.Untyped). An engine error answers
 * with its status: 404 for what is not there, 409 for what its state does
 * not allow, 400 for the rest of what the caller got wrong.
 *
 * Who is asking is the service's authenticator's (ODataAuthentication.h):
 * the principal's subject is the user, the groups claim their groups, and
 * every claim theirs to match (WFIdentity.h). With a principal, what a
 * caller sees and does follows the processes:
 *
 *   Tasks               theirs, or unclaimed and offered to them -- by
 *                       candidate user, group, or a claim a candidate
 *                       group name:value names
 *   ProcessDefinitions  those they may start (candidate starters); all,
 *                       for a process that names none
 *   Claim, Unclaim      for themselves; Assign, to themselves
 *   StartProcessInstance, SubmitStartForm   what they may start
 *
 * and a scope of the principal's lifts each limit, for whoever operates
 * the engine: WFODataScopeReadAllTasks, WFODataScopeAssignTasks,
 * WFODataScopeReadAllDefinitions, WFODataScopeStartAny. Without an
 * authenticator, or a principal, nothing is limited.
 */
FOUNDATION_EXPORT NSString * const WFODataScopeReadAllTasks;        /* Tasks.ReadAll */
FOUNDATION_EXPORT NSString * const WFODataScopeAssignTasks;         /* Tasks.Assign */
FOUNDATION_EXPORT NSString * const WFODataScopeReadAllDefinitions;  /* ProcessDefinitions.ReadAll */
FOUNDATION_EXPORT NSString * const WFODataScopeStartAny;            /* ProcessInstances.StartAny */

@interface WFODataService : NSObject

/* A service over the engine's store, answering under the root; it keeps
 * the engine. Set anything else on it before its first request. A
 * principal's groups are its "groups" claim. */
+ (ODataService *)serviceForEngine:(WFProcessEngine *)engine serviceRoot:(NSURL *)serviceRoot;
/* The same, the groups in the claim of this name. */
+ (ODataService *)serviceForEngine:(WFProcessEngine *)engine
                       serviceRoot:(NSURL *)serviceRoot
                       groupsClaim:(NSString *)groupsClaim;

@end

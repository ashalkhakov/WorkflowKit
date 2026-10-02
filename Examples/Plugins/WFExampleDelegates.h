#import "WorkflowKit.h"

/*
 * The host code the example processes (Examples/Processes) call by name,
 * as a real application's would be: compiled into the tests, which run
 * the examples, and built as a plugin bundle for wf-serve
 * (make -C Examples/Plugins; wf-serve -Plugins Examples/Plugins/obj).
 *
 *   ${audit}     an execution listener: each event it hears appended to
 *                the auditTrail variable, as "event activity", with its
 *                note field when given
 *   ${mailer}    a delegate: a message, from its fields to, template and
 *                subject, appended to the outbox variable -- what a mail
 *                service would be handed
 *   ${workload}  a task listener: the task routed as its fields say --
 *                assignTo its assignee, dueIn (a duration, PT4H) from now
 *                its due date -- and the task's queue recorded
 */

@interface WFExampleAudit : NSObject <WFExecutionListener>
@end

@interface WFExampleMailer : NSObject <WFActivityDelegate>
@end

@interface WFExampleWorkload : NSObject <WFTaskListener>
@end

/* Registers the three under their names. The plugin bundle's principal
 * class. */
@interface WFExamplePlugin : NSObject <WFEnginePlugin>
@end

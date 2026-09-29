#import "WorkflowKit.h"

@interface WFDemoServices : NSObject <WFServiceTaskHandler>
@end

@implementation WFDemoServices
- (void)performInvocation:(WFServiceInvocation *)invocation
{
	NSLog(@"service %@", invocation.topic);
	if ([invocation.topic isEqualToString:@"erp.purchase-order"]) {
		[invocation finishWithVariables:@{ @"poCreated": @YES } error:nil];
		return;
	}
	if ([invocation.topic isEqualToString:@"notify.rejected"]) {
		[invocation finishWithVariables:@{ @"rejectedNotice": @YES } error:nil];
		return;
	}
	if ([invocation.topic isEqualToString:@"warehouse.pick"]) {
		[invocation finishWithVariables:@{ @"picked": @YES } error:nil];
		return;
	}
	if ([invocation.topic isEqualToString:@"payments.charge"]) {
		[invocation finishWithVariables:@{ @"charged": @YES } error:nil];
		return;
	}
	if ([invocation.topic isEqualToString:@"warehouse.ship"]) {
		[invocation finishWithVariables:@{ @"shipped": @YES } error:nil];
		return;
	}
	[invocation finishWithVariables:nil error:nil];
}
@end

@interface WFDemoDelegate : NSObject <WFProcessEngineDelegate>
@end

@implementation WFDemoDelegate
- (void)processEngine:(WFProcessEngine *)engine taskCreated:(WFWorkItem *)task
{
	(void)engine;
	NSLog(@"[%@] task %@ for %@", task.processInstanceId, task.taskDefinitionKey, task.assignee);
}
- (void)processEngine:(WFProcessEngine *)engine processInstanceEnded:(WFProcessInstance *)instance
{
	(void)engine;
	NSLog(@"[%@] ended", instance.processInstanceId);
}
@end

static WFProcessDefinition *
WFPurchaseRequestDefinition(NSError **error)
{
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"purchase-request"
	                                                 name:@"Purchase Request"];
	[[[[b addStart:@"start"]
		addUserTask:@"fill" name:@"Submit request" assignee:@"requester"]
		addExclusive:@"byAmount" defaultFlow:@"flow_auto"]
		addUserTask:@"approve" name:@"Manager approve" assignee:@"manager"];
	[[[b addExclusive:@"byDecision" defaultFlow:@"flow_reject"]
		addServiceTask:@"procure" action:@"erp.purchase-order"]
		addServiceTask:@"reject" action:@"notify.rejected"];
	[b addEnd:@"end"];
	[[b connect:@"start" to:@"fill"] connect:@"fill" to:@"byAmount"];
	[b connect:@"byAmount" to:@"approve" when:@"amount > 1000"];
	[b connect:@"byAmount" to:@"procure" flowId:@"flow_auto"];
	[b connect:@"approve" to:@"byDecision"];
	[b connect:@"byDecision" to:@"procure" when:@"approved = true"];
	[b connect:@"byDecision" to:@"reject" flowId:@"flow_reject"];
	[[b connect:@"procure" to:@"end"] connect:@"reject" to:@"end"];
	return [b build:error];
}

static WFProcessDefinition *
WFFulfillmentDefinition(NSError **error)
{
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"order-fulfillment"
	                                                 name:@"Order Fulfillment"];
	[[[[b addStart:@"start"]
		addParallel:@"fork"]
		addServiceTask:@"pick" action:@"warehouse.pick"]
		addServiceTask:@"charge" action:@"payments.charge"];
	[[[b addParallel:@"join"]
		addServiceTask:@"ship" action:@"warehouse.ship"]
		addEnd:@"end"];
	[b connect:@"start" to:@"fork"];
	[[b connect:@"fork" to:@"pick"] connect:@"fork" to:@"charge"];
	[[b connect:@"pick" to:@"join"] connect:@"charge" to:@"join"];
	[[b connect:@"join" to:@"ship"] connect:@"ship" to:@"end"];
	return [b build:error];
}

static WFProcessDefinition *
WFTimerWaitDefinition(NSError **error)
{
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"timer-wait"
	                                                 name:@"Timer Wait"];
	[[[b addStart:@"start"] addTimerCatch:@"wait" duration:0] addEnd:@"end"];
	[[b connect:@"start" to:@"wait"] connect:@"wait" to:@"end"];
	return [b build:error];
}

static WFProcessDefinition *
WFMessageWaitDefinition(NSError **error)
{
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"message-wait"
	                                                 name:@"Message Wait"];
	[[[b addStart:@"start"] addMessageCatch:@"go" message:@"go"] addEnd:@"end"];
	[[b connect:@"start" to:@"go"] connect:@"go" to:@"end"];
	return [b build:error];
}

static WFWorkItem *
WFOpenTask(WFProcessEngine *engine, NSString *processInstanceId)
{
	return [[engine.taskService tasksForProcessInstance:processInstanceId] firstObject];
}

static NSDictionary *
WFVariables(WFProcessEngine *engine, NSString *processInstanceId)
{
	return [engine.historyService historicVariablesForProcessInstance:processInstanceId];
}

static BOOL
WFEnded(WFProcessEngine *engine, NSString *processInstanceId)
{
	return [[engine.historyService historicProcessInstanceWithId:processInstanceId] endTime] != nil;
}

/* Works the purchase request's user tasks until the instance ends. */
static BOOL
WFDrivePurchase(WFProcessEngine *engine,
	NSDictionary *startVars,
	NSDictionary *approvalVars,
	NSError **error)
{
	NSString *processInstanceId =
		[engine.runtimeService startProcessInstanceByKey:@"purchase-request"
		                                       variables:startVars
		                                           error:error].processInstanceId;
	if (processInstanceId == nil) {
		return NO;
	}
	[engine waitUntilSettled:processInstanceId timeout:10.0];
	WFWorkItem *task = nil;
	while ((task = WFOpenTask(engine, processInstanceId)) != nil) {
		NSDictionary *vars = [task.taskDefinitionKey isEqualToString:@"approve"]
			? approvalVars : @{};
		NSLog(@"complete %@", task.taskDefinitionKey);
		if (![engine.taskService completeTask:task.taskId variables:vars error:error]) {
			return NO;
		}
		[engine waitUntilSettled:processInstanceId timeout:10.0];
	}
	NSLog(@"done ended=%d vars=%@", WFEnded(engine, processInstanceId),
		WFVariables(engine, processInstanceId));
	return WFEnded(engine, processInstanceId);
}

/* An engine over the SQLite file at url. Deploying at every start is
 * cheap: unchanged definitions are recognised and not versioned again. */
static WFProcessEngine *
WFMakeEngine(NSURL *url, id<WFProcessEngineDelegate> delegate, NSError **error)
{
	WFStore *store = [WFStore SQLiteStoreAtURL:url error:error];
	if (store == nil) {
		return nil;
	}
	WFProcessEngine *engine = [[WFProcessEngine alloc] initWithStore:store];
	engine.delegate = delegate;
	engine.serviceHandler = [[WFDemoServices alloc] init];
	NSArray *definitions = @[
		WFPurchaseRequestDefinition(error),
		WFFulfillmentDefinition(error),
		WFTimerWaitDefinition(error),
		WFMessageWaitDefinition(error)
	];
	for (WFProcessDefinition *definition in definitions) {
		if ([engine.repositoryService deployDefinition:definition error:error] == nil) {
			return nil;
		}
	}
	if (![engine openWithError:error]) {
		return nil;
	}
	return engine;
}

static int
WFFail(NSString *what, NSError *error)
{
	NSLog(@"%@: %@", what, error);
	return 1;
}

int
main(int argc, const char *argv[])
{
	(void)argc;
	(void)argv;

	@autoreleasepool {
		NSError *error = nil;
		NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"purchase-demo-%@.sqlite",
				[[NSUUID UUID] UUIDString]]];
		NSURL *url = [NSURL fileURLWithPath:path];
		WFDemoDelegate *delegate = [[WFDemoDelegate alloc] init];
		NSLog(@"store %@", path);

		WFProcessEngine *engine = WFMakeEngine(url, delegate, &error);
		if (engine == nil) {
			return WFFail(@"engine", error);
		}

		NSLog(@"--- amount 2500, approved ---");
		if (!WFDrivePurchase(engine, @{ @"amount": @2500 }, @{ @"approved": @YES }, &error)) {
			return WFFail(@"run failed", error);
		}
		NSLog(@"--- amount 2500, rejected ---");
		if (!WFDrivePurchase(engine, @{ @"amount": @2500 }, @{ @"approved": @NO }, &error)) {
			return WFFail(@"run failed", error);
		}
		NSLog(@"--- amount 400, auto ---");
		if (!WFDrivePurchase(engine, @{ @"amount": @400 }, @{ @"approved": @YES }, &error)) {
			return WFFail(@"run failed", error);
		}

		NSLog(@"--- restart after the first user task ---");
		NSString *liveId = [engine.runtimeService startProcessInstanceByKey:@"purchase-request"
		                                                          variables:@{ @"amount": @2500 }
		                                                              error:&error].processInstanceId;
		if (liveId == nil) {
			return WFFail(@"start failed", error);
		}
		[engine close];
		engine = nil;
		engine = WFMakeEngine(url, delegate, &error);
		if (engine == nil) {
			return WFFail(@"reopen", error);
		}
		WFWorkItem *task = nil;
		while ((task = WFOpenTask(engine, liveId)) != nil) {
			NSDictionary *vars = [task.taskDefinitionKey isEqualToString:@"approve"]
				? @{ @"approved": @YES } : @{};
			if (![engine.taskService completeTask:task.taskId variables:vars error:&error]) {
				return WFFail(@"resume failed", error);
			}
			[engine waitUntilSettled:liveId timeout:10.0];
		}
		NSLog(@"restored ended=%d vars=%@", WFEnded(engine, liveId), WFVariables(engine, liveId));
		if (!WFEnded(engine, liveId)) {
			return 1;
		}

		NSLog(@"--- parallel pick || charge ---");
		NSString *order = [engine.runtimeService startProcessInstanceByKey:@"order-fulfillment"
		                                                        variables:@{ @"orderId": @"SO-1" }
		                                                            error:&error].processInstanceId;
		[engine waitUntilSettled:order timeout:10.0];
		NSDictionary *orderVars = WFVariables(engine, order);
		if (!WFEnded(engine, order)
		    || ![[orderVars objectForKey:@"picked"] boolValue]
		    || ![[orderVars objectForKey:@"charged"] boolValue]
		    || ![[orderVars objectForKey:@"shipped"] boolValue]) {
			return WFFail(@"fulfillment failed", error);
		}
		NSLog(@"fulfillment ok vars=%@", orderVars);

		NSLog(@"--- timer catch 0s ---");
		NSString *timed = [engine.runtimeService startProcessInstanceByKey:@"timer-wait"
		                                                        variables:nil
		                                                            error:&error].processInstanceId;
		[engine waitUntilSettled:timed timeout:10.0];
		if (!WFEnded(engine, timed)) {
			return WFFail(@"timer run failed", error);
		}

		NSLog(@"--- message catch ---");
		if ([engine.runtimeService startProcessInstanceByKey:@"message-wait"
		                                         businessKey:@"M-1"
		                                           variables:nil
		                                               error:&error] == nil) {
			return WFFail(@"message start failed", error);
		}
		if (![engine.runtimeService correlateMessage:@"go"
		                                 businessKey:@"M-1"
		                             correlationKeys:nil
		                                   variables:@{ @"acked": @YES }
		                                       error:&error]) {
			return WFFail(@"correlate failed", error);
		}

		NSLog(@"--- BPMN 2.0 round-trip ---");
		WFProcessDefinition *definition = WFPurchaseRequestDefinition(&error);
		NSString *purchaseXML = [WFBpmnWriter XMLStringFromDefinition:definition error:&error];
		if (purchaseXML == nil) {
			return WFFail(@"export purchase failed", error);
		}
		NSLog(@"%@", purchaseXML);
		WFProcessDefinition *importedPurchase =
			[WFBpmnReader definitionFromXMLString:purchaseXML error:&error];
		if (importedPurchase == nil) {
			return WFFail(@"import purchase failed", error);
		}
		/* The imported copy writes back to the same BPMN, so deploying it
		 * is a duplicate: still version 1. */
		WFDeployment *redeployed =
			[engine.repositoryService deployDefinition:importedPurchase error:&error];
		if ([[redeployed.definitions lastObject] version] != 1) {
			return WFFail(@"round-tripped definition was versioned again", error);
		}
		if (!WFDrivePurchase(engine, @{ @"amount": @400 }, @{ @"approved": @YES }, &error)) {
			return WFFail(@"imported purchase run failed", error);
		}
		[engine close];
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}
	return 0;
}

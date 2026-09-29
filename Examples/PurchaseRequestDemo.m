#import "UDWorkflow.h"

@interface UDDemoServices : NSObject <UDServiceTaskHandler>
@end

@implementation UDDemoServices
- (void)performInvocation:(UDServiceInvocation *)invocation
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

@interface UDDemoDelegate : NSObject <UDProcessEngineDelegate>
@end

@implementation UDDemoDelegate
- (void)processEngine:(UDProcessEngine *)engine taskCreated:(UDWorkItem *)task
{
	(void)engine;
	NSLog(@"[%@] task %@ for %@", task.processInstanceId, task.taskDefinitionKey, task.assignee);
}
- (void)processEngine:(UDProcessEngine *)engine processInstanceEnded:(UDProcessInstance *)instance
{
	(void)engine;
	NSLog(@"[%@] ended", instance.processInstanceId);
}
@end

static UDProcessDefinition *
UDPurchaseRequestDefinition(NSError **error)
{
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"purchase-request"
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
	[b connect:@"byAmount"
	        to:@"approve"
	       key:@"amount"
	        op:UDComparisonOpGreater
	     value:@1000];
	[b connect:@"byAmount" to:@"procure" flowId:@"flow_auto"];
	[b connect:@"approve" to:@"byDecision"];
	[b connect:@"byDecision"
	        to:@"procure"
	       key:@"approved"
	        op:UDComparisonOpEqual
	     value:@YES];
	[b connect:@"byDecision" to:@"reject" flowId:@"flow_reject"];
	[[b connect:@"procure" to:@"end"] connect:@"reject" to:@"end"];
	return [b build:error];
}

static UDProcessDefinition *
UDFulfillmentDefinition(NSError **error)
{
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"order-fulfillment"
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

static UDProcessDefinition *
UDTimerWaitDefinition(NSError **error)
{
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"timer-wait"
	                                                 name:@"Timer Wait"];
	[[[b addStart:@"start"] addTimerCatch:@"wait" duration:0] addEnd:@"end"];
	[[b connect:@"start" to:@"wait"] connect:@"wait" to:@"end"];
	return [b build:error];
}

static UDProcessDefinition *
UDMessageWaitDefinition(NSError **error)
{
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"message-wait"
	                                                 name:@"Message Wait"];
	[[[b addStart:@"start"] addMessageCatch:@"go" message:@"go"] addEnd:@"end"];
	[[b connect:@"start" to:@"go"] connect:@"go" to:@"end"];
	return [b build:error];
}

static UDWorkItem *
UDOpenTask(UDProcessEngine *engine, NSString *processInstanceId)
{
	return [[engine.taskService tasksForProcessInstance:processInstanceId] firstObject];
}

static NSDictionary *
UDVariables(UDProcessEngine *engine, NSString *processInstanceId)
{
	return [engine.historyService historicVariablesForProcessInstance:processInstanceId];
}

static BOOL
UDEnded(UDProcessEngine *engine, NSString *processInstanceId)
{
	return [[engine.historyService historicProcessInstanceWithId:processInstanceId] endTime] != nil;
}

/* Works the purchase request's user tasks until the instance ends. */
static BOOL
UDDrivePurchase(UDProcessEngine *engine,
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
	UDWorkItem *task = nil;
	while ((task = UDOpenTask(engine, processInstanceId)) != nil) {
		NSDictionary *vars = [task.taskDefinitionKey isEqualToString:@"approve"]
			? approvalVars : @{};
		NSLog(@"complete %@", task.taskDefinitionKey);
		if (![engine.taskService completeTask:task.taskId variables:vars error:error]) {
			return NO;
		}
		[engine waitUntilSettled:processInstanceId timeout:10.0];
	}
	NSLog(@"done ended=%d vars=%@", UDEnded(engine, processInstanceId),
		UDVariables(engine, processInstanceId));
	return UDEnded(engine, processInstanceId);
}

/* An engine over the SQLite file at url. Deploying at every start is
 * cheap: unchanged definitions are recognised and not versioned again. */
static UDProcessEngine *
UDMakeEngine(NSURL *url, id<UDProcessEngineDelegate> delegate, NSError **error)
{
	UDStore *store = [UDStore SQLiteStoreAtURL:url error:error];
	if (store == nil) {
		return nil;
	}
	UDProcessEngine *engine = [[UDProcessEngine alloc] initWithStore:store];
	engine.delegate = delegate;
	engine.serviceHandler = [[UDDemoServices alloc] init];
	NSArray *definitions = @[
		UDPurchaseRequestDefinition(error),
		UDFulfillmentDefinition(error),
		UDTimerWaitDefinition(error),
		UDMessageWaitDefinition(error)
	];
	for (UDProcessDefinition *definition in definitions) {
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
UDFail(NSString *what, NSError *error)
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
		UDDemoDelegate *delegate = [[UDDemoDelegate alloc] init];
		NSLog(@"store %@", path);

		UDProcessEngine *engine = UDMakeEngine(url, delegate, &error);
		if (engine == nil) {
			return UDFail(@"engine", error);
		}

		NSLog(@"--- amount 2500, approved ---");
		if (!UDDrivePurchase(engine, @{ @"amount": @2500 }, @{ @"approved": @YES }, &error)) {
			return UDFail(@"run failed", error);
		}
		NSLog(@"--- amount 2500, rejected ---");
		if (!UDDrivePurchase(engine, @{ @"amount": @2500 }, @{ @"approved": @NO }, &error)) {
			return UDFail(@"run failed", error);
		}
		NSLog(@"--- amount 400, auto ---");
		if (!UDDrivePurchase(engine, @{ @"amount": @400 }, @{ @"approved": @YES }, &error)) {
			return UDFail(@"run failed", error);
		}

		NSLog(@"--- restart after the first user task ---");
		NSString *liveId = [engine.runtimeService startProcessInstanceByKey:@"purchase-request"
		                                                          variables:@{ @"amount": @2500 }
		                                                              error:&error].processInstanceId;
		if (liveId == nil) {
			return UDFail(@"start failed", error);
		}
		[engine close];
		engine = nil;
		engine = UDMakeEngine(url, delegate, &error);
		if (engine == nil) {
			return UDFail(@"reopen", error);
		}
		UDWorkItem *task = nil;
		while ((task = UDOpenTask(engine, liveId)) != nil) {
			NSDictionary *vars = [task.taskDefinitionKey isEqualToString:@"approve"]
				? @{ @"approved": @YES } : @{};
			if (![engine.taskService completeTask:task.taskId variables:vars error:&error]) {
				return UDFail(@"resume failed", error);
			}
			[engine waitUntilSettled:liveId timeout:10.0];
		}
		NSLog(@"restored ended=%d vars=%@", UDEnded(engine, liveId), UDVariables(engine, liveId));
		if (!UDEnded(engine, liveId)) {
			return 1;
		}

		NSLog(@"--- parallel pick || charge ---");
		NSString *order = [engine.runtimeService startProcessInstanceByKey:@"order-fulfillment"
		                                                        variables:@{ @"orderId": @"SO-1" }
		                                                            error:&error].processInstanceId;
		[engine waitUntilSettled:order timeout:10.0];
		NSDictionary *orderVars = UDVariables(engine, order);
		if (!UDEnded(engine, order)
		    || ![[orderVars objectForKey:@"picked"] boolValue]
		    || ![[orderVars objectForKey:@"charged"] boolValue]
		    || ![[orderVars objectForKey:@"shipped"] boolValue]) {
			return UDFail(@"fulfillment failed", error);
		}
		NSLog(@"fulfillment ok vars=%@", orderVars);

		NSLog(@"--- timer catch 0s ---");
		NSString *timed = [engine.runtimeService startProcessInstanceByKey:@"timer-wait"
		                                                        variables:nil
		                                                            error:&error].processInstanceId;
		[engine waitUntilSettled:timed timeout:10.0];
		if (!UDEnded(engine, timed)) {
			return UDFail(@"timer run failed", error);
		}

		NSLog(@"--- message catch ---");
		if ([engine.runtimeService startProcessInstanceByKey:@"message-wait"
		                                         businessKey:@"M-1"
		                                           variables:nil
		                                               error:&error] == nil) {
			return UDFail(@"message start failed", error);
		}
		if (![engine.runtimeService correlateMessage:@"go"
		                                 businessKey:@"M-1"
		                             correlationKeys:nil
		                                   variables:@{ @"acked": @YES }
		                                       error:&error]) {
			return UDFail(@"correlate failed", error);
		}

		NSLog(@"--- BPMN 2.0 round-trip ---");
		UDProcessDefinition *definition = UDPurchaseRequestDefinition(&error);
		NSString *purchaseXML = [UDBpmnWriter XMLStringFromDefinition:definition error:&error];
		if (purchaseXML == nil) {
			return UDFail(@"export purchase failed", error);
		}
		NSLog(@"%@", purchaseXML);
		UDProcessDefinition *importedPurchase =
			[UDBpmnReader definitionFromXMLString:purchaseXML error:&error];
		if (importedPurchase == nil) {
			return UDFail(@"import purchase failed", error);
		}
		/* The imported copy writes back to the same BPMN, so deploying it
		 * is a duplicate: still version 1. */
		UDDeployment *redeployed =
			[engine.repositoryService deployDefinition:importedPurchase error:&error];
		if ([[redeployed.definitions lastObject] version] != 1) {
			return UDFail(@"round-tripped definition was versioned again", error);
		}
		if (!UDDrivePurchase(engine, @{ @"amount": @400 }, @{ @"approved": @YES }, &error)) {
			return UDFail(@"imported purchase run failed", error);
		}
		[engine close];
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}
	return 0;
}

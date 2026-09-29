#import "UDWorkflow.h"

@interface UDDemoServices : NSObject <UDServiceTaskHandler>
@end

@implementation UDDemoServices
- (void)performInvocation:(UDServiceInvocation *)invocation
{
	NSLog(@"service %@", invocation.actionKey);
	if ([invocation.actionKey isEqualToString:@"erp.purchase-order"]) {
		[invocation finishWithVariables:@{ @"poCreated": @YES } error:nil];
		return;
	}
	if ([invocation.actionKey isEqualToString:@"notify.rejected"]) {
		[invocation finishWithVariables:@{ @"rejectedNotice": @YES } error:nil];
		return;
	}
	if ([invocation.actionKey isEqualToString:@"warehouse.pick"]) {
		[invocation finishWithVariables:@{ @"picked": @YES } error:nil];
		return;
	}
	if ([invocation.actionKey isEqualToString:@"payments.charge"]) {
		[invocation finishWithVariables:@{ @"charged": @YES } error:nil];
		return;
	}
	if ([invocation.actionKey isEqualToString:@"warehouse.ship"]) {
		[invocation finishWithVariables:@{ @"shipped": @YES } error:nil];
		return;
	}
	[invocation finishWithVariables:nil error:nil];
}
@end

@interface UDDemoDelegate : NSObject <UDEngineDelegate>
@end

@implementation UDDemoDelegate
- (void)engine:(UDEngine *)engine
       instance:(UDProcessInstance *)instance
      didTrace:(NSString *)message
{
	NSLog(@"[%@] %@", instance.instanceId, message);
}
@end

static UDToken *
UDWaitingUserToken(UDProcessInstance *instance)
{
	for (UDToken *token in instance.tokens) {
		if (token.state != UDTokenStateWaiting) {
			continue;
		}
		UDFlowNode *node = [instance.definition nodeWithId:token.nodeId];
		if ([node isKindOfClass:[UDTask class]]
		    && [(UDTask *)node kind] == UDTaskKindUser) {
			return token;
		}
	}
	return nil;
}

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

/* Waits for the instance's service calls, then answers it as committed. */
static UDProcessInstance *
UDSettled(UDEngine *engine, NSString *instanceId, NSError **error)
{
	if (instanceId == nil) {
		return nil;
	}
	[engine waitUntilSettled:instanceId timeout:10.0];
	return [engine instanceWithId:instanceId error:error];
}

static BOOL
UDDrivePurchase(UDEngine *engine,
	NSDictionary *startVars,
	NSDictionary *approvalVars,
	NSError **error)
{
	NSString *instanceId = [engine startProcess:@"purchase-request"
	                                  variables:startVars
	                                      error:error];
	UDProcessInstance *instance = UDSettled(engine, instanceId, error);
	if (instance == nil) {
		return NO;
	}

	while (!instance.isCompleted && !instance.isFailed) {
		UDToken *waiting = UDWaitingUserToken(instance);
		if (waiting == nil) {
			break;
		}
		NSDictionary *vars = nil;
		if ([waiting.nodeId isEqualToString:@"fill"]) {
			vars = @{};
		} else if ([waiting.nodeId isEqualToString:@"approve"]) {
			vars = approvalVars;
		}
		NSLog(@"complete user task %@", waiting.nodeId);
		if (![engine completeUserTask:waiting.tokenId
		                   instanceId:instanceId
		                    variables:vars
		                        error:error]) {
			return NO;
		}
		instance = UDSettled(engine, instanceId, error);
		if (instance == nil) {
			return NO;
		}
	}

	NSLog(@"done completed=%d failed=%d vars=%@",
		instance.isCompleted, instance.isFailed, instance.variables);
	if (instance.isFailed) {
		if (error != NULL) {
			*error = instance.error;
		}
		return NO;
	}
	return instance.isCompleted;
}

/* An engine over the SQLite file at url, with every definition deployed. */
static UDEngine *
UDMakeEngine(NSURL *url, id<UDEngineDelegate> delegate, NSError **error)
{
	UDStore *store = [UDStore SQLiteStoreAtURL:url error:error];
	if (store == nil) {
		return nil;
	}
	UDEngine *engine = [[UDEngine alloc] initWithStore:store];
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

		UDEngine *engine = UDMakeEngine(url, delegate, &error);
		if (engine == nil) {
			return UDFail(@"engine", error);
		}

		NSLog(@"--- amount 2500, approved ---");
		if (!UDDrivePurchase(engine, @{ @"amount": @2500 },
			@{ @"approved": @YES }, &error)) {
			return UDFail(@"run failed", error);
		}

		NSLog(@"--- amount 2500, rejected ---");
		if (!UDDrivePurchase(engine, @{ @"amount": @2500 },
			@{ @"approved": @NO }, &error)) {
			return UDFail(@"run failed", error);
		}

		NSLog(@"--- amount 400, auto ---");
		if (!UDDrivePurchase(engine, @{ @"amount": @400 },
			@{ @"approved": @YES }, &error)) {
			return UDFail(@"run failed", error);
		}

		NSLog(@"--- restart after the first user wait ---");
		NSString *liveId = [engine startProcess:@"purchase-request"
		                              variables:@{ @"amount": @2500 }
		                                  error:&error];
		if (liveId == nil) {
			return UDFail(@"start failed", error);
		}
		[engine close];
		engine = nil;
		engine = UDMakeEngine(url, delegate, &error);
		if (engine == nil) {
			return UDFail(@"reopen", error);
		}
		UDProcessInstance *restored = [engine instanceWithId:liveId error:&error];
		UDToken *fill = UDWaitingUserToken(restored);
		if (fill == nil || ![fill.nodeId isEqualToString:@"fill"]) {
			NSLog(@"expected fill waiting on restored instance");
			return 1;
		}
		if (![engine completeUserTask:fill.tokenId instanceId:liveId
		                    variables:@{} error:&error]) {
			return UDFail(@"resume fill failed", error);
		}
		UDToken *approve = UDWaitingUserToken(UDSettled(engine, liveId, &error));
		if (approve == nil) {
			NSLog(@"expected approve waiting after restore");
			return 1;
		}
		if (![engine completeUserTask:approve.tokenId instanceId:liveId
		                    variables:@{ @"approved": @YES } error:&error]) {
			return UDFail(@"resume approve failed", error);
		}
		restored = UDSettled(engine, liveId, &error);
		NSLog(@"restored completed=%d vars=%@",
			restored.isCompleted, restored.variables);
		if (!restored.isCompleted) {
			return 1;
		}

		NSLog(@"--- parallel pick || charge ---");
		UDProcessInstance *order = UDSettled(engine,
			[engine startProcess:@"order-fulfillment"
			           variables:@{ @"orderId": @"SO-1" }
			               error:&error], &error);
		if (order == nil || !order.isCompleted
		    || ![[order.variables objectForKey:@"picked"] boolValue]
		    || ![[order.variables objectForKey:@"charged"] boolValue]
		    || ![[order.variables objectForKey:@"shipped"] boolValue]) {
			return UDFail(@"fulfillment failed", error);
		}
		NSLog(@"fulfillment ok vars=%@", order.variables);

		NSLog(@"--- timer catch 0s ---");
		UDProcessInstance *timed = UDSettled(engine,
			[engine startProcess:@"timer-wait" variables:nil error:&error], &error);
		if (timed == nil || !timed.isCompleted) {
			return UDFail(@"timer run failed", error);
		}

		NSLog(@"--- message catch ---");
		NSString *waitingId = [engine startProcess:@"message-wait"
		                                 variables:nil
		                                     error:&error];
		if (waitingId == nil) {
			return UDFail(@"message start failed", error);
		}
		if (![engine deliverMessage:@"go"
		                    payload:@{ @"acked": @YES }
		                 instanceId:waitingId
		                      error:&error]) {
			return UDFail(@"deliver failed", error);
		}
		UDProcessInstance *acked = UDSettled(engine, waitingId, &error);
		if (!acked.isCompleted) {
			NSLog(@"message instance did not complete");
			return 1;
		}
		NSLog(@"message ok vars=%@", acked.variables);

		NSLog(@"--- BPMN 2.0 round-trip ---");
		UDProcessDefinition *definition = UDPurchaseRequestDefinition(&error);
		NSString *purchaseXML =
			[UDBpmnWriter XMLStringFromDefinition:definition error:&error];
		if (purchaseXML == nil) {
			return UDFail(@"export purchase failed", error);
		}
		NSLog(@"%@", purchaseXML);
		UDProcessDefinition *importedPurchase =
			[UDBpmnReader definitionFromXMLString:purchaseXML error:&error];
		if (importedPurchase == nil) {
			return UDFail(@"import purchase failed", error);
		}
		if ([importedPurchase.nodes count] != [definition.nodes count]
		    || [importedPurchase.flows count] != [definition.flows count]) {
			NSLog(@"purchase round-trip size mismatch nodes %lu/%lu flows %lu/%lu",
				(unsigned long)[importedPurchase.nodes count],
				(unsigned long)[definition.nodes count],
				(unsigned long)[importedPurchase.flows count],
				(unsigned long)[definition.flows count]);
			return 1;
		}
		/* The imported copy writes back to the same BPMN, so deploying it
		 * is a duplicate: still version 1. */
		UDDeployment *redeployed =
			[engine.repositoryService deployDefinition:importedPurchase error:&error];
		if ([[redeployed.definitions lastObject] version] != 1) {
			return UDFail(@"deploy imported purchase failed", error);
		}
		if (!UDDrivePurchase(engine, @{ @"amount": @400 },
			@{ @"approved": @YES }, &error)) {
			return UDFail(@"imported purchase run failed", error);
		}
		[engine close];
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}
	return 0;
}

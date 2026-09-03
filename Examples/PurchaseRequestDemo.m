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
	                                                 name:@"Purchase Request"
	                                              version:1];
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
	                                                 name:@"Order Fulfillment"
	                                              version:1];
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
	                                                 name:@"Timer Wait"
	                                              version:1];
	[[[b addStart:@"start"] addTimerCatch:@"wait" duration:0] addEnd:@"end"];
	[[b connect:@"start" to:@"wait"] connect:@"wait" to:@"end"];
	return [b build:error];
}

static UDProcessDefinition *
UDMessageWaitDefinition(NSError **error)
{
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"message-wait"
	                                                 name:@"Message Wait"
	                                              version:1];
	[[[b addStart:@"start"] addMessageCatch:@"go" message:@"go"] addEnd:@"end"];
	[[b connect:@"start" to:@"go"] connect:@"go" to:@"end"];
	return [b build:error];
}

static BOOL
UDDrivePurchase(UDEngine *engine,
	UDProcessDefinition *definition,
	NSDictionary *startVars,
	NSDictionary *approvalVars,
	NSError **error)
{
	UDProcessInstance *instance = [engine startProcess:definition
	                                         variables:startVars
	                                             error:error];
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
		                     instance:instance
		                    variables:vars
		                        error:error]) {
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

int
main(int argc, const char *argv[])
{
	(void)argc;
	(void)argv;

	@autoreleasepool {
		NSError *error = nil;
		UDProcessDefinition *definition = UDPurchaseRequestDefinition(&error);
		if (definition == nil) {
			NSLog(@"bad definition: %@", error);
			return 1;
		}

		UDMemoryStore *store = [[UDMemoryStore alloc] init];
		[store registerDefinition:definition];

		UDEngine *engine = [[UDEngine alloc] init];
		UDDemoDelegate *delegate = [[UDDemoDelegate alloc] init];
		engine.delegate = delegate;
		engine.serviceHandler = [[UDDemoServices alloc] init];
		engine.store = store;

		NSLog(@"--- amount 2500, approved ---");
		if (!UDDrivePurchase(engine, definition,
			@{ @"amount": @2500 },
			@{ @"approved": @YES },
			&error)) {
			NSLog(@"run failed: %@", error);
			return 1;
		}

		NSLog(@"--- amount 2500, rejected ---");
		if (!UDDrivePurchase(engine, definition,
			@{ @"amount": @2500 },
			@{ @"approved": @NO },
			&error)) {
			NSLog(@"run failed: %@", error);
			return 1;
		}

		NSLog(@"--- amount 400, auto ---");
		if (!UDDrivePurchase(engine, definition,
			@{ @"amount": @400 },
			@{ @"approved": @YES },
			&error)) {
			NSLog(@"run failed: %@", error);
			return 1;
		}

		NSLog(@"--- resume from store after first user wait ---");
		UDProcessInstance *live = [engine startProcess:definition
		                                     variables:@{ @"amount": @2500 }
		                                         error:&error];
		if (live == nil) {
			NSLog(@"start failed: %@", error);
			return 1;
		}
		UDProcessInstance *restored = [store loadInstance:live.instanceId
		                                            error:&error];
		if (restored == nil) {
			NSLog(@"load failed: %@", error);
			return 1;
		}
		UDToken *fill = UDWaitingUserToken(restored);
		if (fill == nil || ![fill.nodeId isEqualToString:@"fill"]) {
			NSLog(@"expected fill waiting on restored instance");
			return 1;
		}
		if (![engine completeUserTask:fill.tokenId
		                     instance:restored
		                    variables:@{}
		                        error:&error]) {
			NSLog(@"resume fill failed: %@", error);
			return 1;
		}
		UDToken *approve = UDWaitingUserToken(restored);
		if (approve == nil) {
			NSLog(@"expected approve waiting after restore");
			return 1;
		}
		if (![engine completeUserTask:approve.tokenId
		                     instance:restored
		                    variables:@{ @"approved": @YES }
		                        error:&error]) {
			NSLog(@"resume approve failed: %@", error);
			return 1;
		}
		NSLog(@"restored completed=%d vars=%@",
			restored.isCompleted, restored.variables);

		NSLog(@"--- parallel pick || charge ---");
		UDProcessDefinition *fulfillment = UDFulfillmentDefinition(&error);
		if (fulfillment == nil) {
			NSLog(@"bad fulfillment: %@", error);
			return 1;
		}
		[store registerDefinition:fulfillment];
		UDProcessInstance *order = [engine startProcess:fulfillment
		                                      variables:@{ @"orderId": @"SO-1" }
		                                          error:&error];
		if (order == nil || !order.isCompleted) {
			NSLog(@"fulfillment failed: %@", error);
			return 1;
		}
		if (![[order.variables objectForKey:@"picked"] boolValue]
		    || ![[order.variables objectForKey:@"charged"] boolValue]
		    || ![[order.variables objectForKey:@"shipped"] boolValue]) {
			NSLog(@"fulfillment vars incomplete: %@", order.variables);
			return 1;
		}
		NSLog(@"fulfillment ok vars=%@", order.variables);

		NSLog(@"--- timer catch 0s ---");
		UDProcessDefinition *timerDef = UDTimerWaitDefinition(&error);
		if (timerDef == nil) {
			NSLog(@"timer def: %@", error);
			return 1;
		}
		UDProcessInstance *timed = [engine startProcess:timerDef
		                                        variables:nil
		                                            error:&error];
		if (timed == nil || !timed.isCompleted) {
			NSLog(@"timer run failed: %@", error);
			return 1;
		}

		NSLog(@"--- message catch ---");
		UDProcessDefinition *msgDef = UDMessageWaitDefinition(&error);
		if (msgDef == nil) {
			NSLog(@"message def: %@", error);
			return 1;
		}
		UDProcessInstance *waiting = [engine startProcess:msgDef
		                                          variables:nil
		                                              error:&error];
		if (waiting == nil) {
			NSLog(@"message start failed: %@", error);
			return 1;
		}
		if (![engine deliverMessage:@"go"
		                     payload:@{ @"acked": @YES }
		                    instance:waiting
		                       error:&error]) {
			NSLog(@"deliver failed: %@", error);
			return 1;
		}
		if (!waiting.isCompleted) {
			NSLog(@"message instance did not complete");
			return 1;
		}
		NSLog(@"message ok vars=%@", waiting.variables);

		NSLog(@"--- BPMN 2.0 round-trip ---");
		NSString *purchaseXML =
			[UDBpmnWriter XMLStringFromDefinition:definition error:&error];
		if (purchaseXML == nil) {
			NSLog(@"export purchase failed: %@", error);
			return 1;
		}
		NSLog(@"%@", purchaseXML);
		UDProcessDefinition *importedPurchase =
			[UDBpmnReader definitionFromXMLString:purchaseXML error:&error];
		if (importedPurchase == nil) {
			NSLog(@"import purchase failed: %@", error);
			return 1;
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
		if (!UDDrivePurchase(engine, importedPurchase,
			@{ @"amount": @400 },
			@{ @"approved": @YES },
			&error)) {
			NSLog(@"imported purchase run failed: %@", error);
			return 1;
		}

		NSString *fulfillXML =
			[UDBpmnWriter XMLStringFromDefinition:fulfillment error:&error];
		if (fulfillXML == nil) {
			NSLog(@"export fulfillment failed: %@", error);
			return 1;
		}
		UDProcessDefinition *importedFulfill =
			[UDBpmnReader definitionFromXMLString:fulfillXML error:&error];
		if (importedFulfill == nil) {
			NSLog(@"import fulfillment failed: %@", error);
			return 1;
		}
		UDProcessInstance *importedOrder =
			[engine startProcess:importedFulfill
			           variables:@{ @"orderId": @"SO-2" }
			               error:&error];
		if (importedOrder == nil || !importedOrder.isCompleted) {
			NSLog(@"imported fulfillment failed: %@", error);
			return 1;
		}
		NSLog(@"imported fulfillment ok vars=%@", importedOrder.variables);
	}
	return 0;
}

/* Included into a class of each backend's suite: see WFTestCase.h. Built
 * where WorkflowKitOData is (make test ODATAKIT=...). */

#pragma mark - External tasks through the OData API

#include "WFODataSupport.inc"

/* start -> charge (an external task on the topic charge) -> end; with
 * boundary, a CARD_DECLINED error on charge leads to a user task. */
- (WFProcessDefinition *)charging:(BOOL)boundary
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:boundary ? @"charge-or-ask" : @"charge"];
	[[[b addStart:@"start"] addServiceTask:@"charge" action:@"charge"] addEnd:@"end"];
	[[b connect:@"start" to:@"charge"] connect:@"charge" to:@"end"];
	if (boundary) {
		[[b addBoundaryError:@"declined" onTask:@"charge" errorRef:@"CARD_DECLINED" interrupting:YES]
			addUserTask:@"ask" name:@"Ask for another card" assignee:@"clerk"];
		[b addEnd:@"asked"];
		[[b connect:@"declined" to:@"ask"] connect:@"ask" to:@"asked"];
	}
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

/* A worker: signed in with the worker's scope alone. */
static NSDictionary *
WFWorker(NSString *name)
{
	return @{ @"X-User": name, @"X-Scopes": @"ExternalTasks.Work" };
}

/* The tasks a fetch locked, or nil when it was refused. */
- (NSArray *)fetch:(NSDictionary *)topics as:(NSString *)worker service:(ODataService *)service
{
	NSDictionary *response = [self send:@"POST" path:@"FetchAndLock"
	                               body:@{ @"WorkerId": worker, @"MaxTasks": @5, @"Topics": topics }
	                            headers:WFWorker(worker) service:service];
	XCTAssertEqual([self statusOf:response], (NSInteger)200, @"%@", [response objectForKey:@"text"]);
	return [[self jsonOf:response] isKindOfClass:[NSDictionary class]] ? [[self jsonOf:response] objectForKey:@"value"] : nil;
}

- (NSInteger)post:(NSString *)action task:(NSString *)taskId body:(NSDictionary *)body
          headers:(NSDictionary *)headers service:(ODataService *)service
{
	NSString *path = [NSString stringWithFormat:@"ExternalTasks('%@')/WorkflowKit.%@", taskId, action];
	NSDictionary *response = [self send:@"POST" path:path body:body headers:headers service:service];
	return [self statusOf:response];
}

- (void)testODataWorkersFetchAndCompleteExternalTasks
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	[self deploy:[self charging:NO] engine:engine];
	NSDate *due = [NSDate dateWithTimeIntervalSince1970:1767225600];  /* 2026-01-01 */
	WFProcessInstance *instance = [engine.runtimeService startProcessInstanceByKey:@"charge" businessKey:@"order-7"
	                                                                     variables:@{ @"amount": @25, @"due": due }
	                                                                         error:&error];
	XCTAssertNotNil(instance, @"%@", error);

	/* What a fetch must say, and who may fetch. */
	NSDictionary *bad = [self send:@"POST" path:@"FetchAndLock"
	                          body:@{ @"WorkerId": @"w1", @"MaxTasks": @5, @"Topics": @{ @"charge": @"soon" } }
	                       headers:WFWorker(@"w1") service:service];
	XCTAssertEqual([self statusOf:bad], (NSInteger)400, @"%@", [bad objectForKey:@"text"]);
	NSDictionary *clerk = @{ @"X-User": @"clerk", @"X-Scopes": @"Tasks.Work" };
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"FetchAndLock"
	                                     body:@{ @"WorkerId": @"w1", @"MaxTasks": @5, @"Topics": @{ @"charge": @60 } }
	                                  headers:clerk service:service]]), (NSInteger)403, @"not a worker");

	NSArray *locked = [self fetch:@{ @"charge": @60, @"ship": @60 } as:@"w1" service:service];
	XCTAssertEqual([locked count], (NSUInteger)1);
	NSDictionary *task = [locked firstObject];
	NSString *taskId = [task objectForKey:@"ExternalTaskId"];
	XCTAssertEqualObjects([task objectForKey:@"Topic"], @"charge");
	XCTAssertEqualObjects([task objectForKey:@"ProcessInstanceId"], instance.processInstanceId);
	XCTAssertEqualObjects([task objectForKey:@"BusinessKey"], @"order-7");
	XCTAssertEqualObjects([task objectForKey:@"ActivityId"], @"charge");
	XCTAssertEqualObjects([[task objectForKey:@"Variables"] objectForKey:@"amount"], @25);
	XCTAssertTrue([[[task objectForKey:@"Variables"] objectForKey:@"due"] hasPrefix:@"2026-01-01T00:00:00"],
	              @"a date as ISO 8601: %@", task);
	XCTAssertEqual([[self fetch:@{ @"charge": @60 } as:@"w2" service:service] count], (NSUInteger)0, @"locked");

	/* Seen as the worker sees it, and only the worker holding the lock
	 * finishes it. */
	NSDictionary *read = [self send:@"GET" path:[NSString stringWithFormat:@"ExternalTasks('%@')", taskId] body:nil
	                        headers:WFWorker(@"w1") service:service];
	XCTAssertEqual([self statusOf:read], (NSInteger)200, @"%@", [read objectForKey:@"text"]);
	XCTAssertEqualObjects([[self jsonOf:read] objectForKey:@"WorkerId"], @"w1");
	XCTAssertEqual(([self post:@"Complete" task:taskId body:@{ @"WorkerId": @"w2", @"Variables": @{} }
	                   headers:WFWorker(@"w2") service:service]), (NSInteger)409);
	XCTAssertEqual(([self post:@"ExtendLock" task:taskId body:@{ @"WorkerId": @"w1", @"Duration": @120 }
	                   headers:WFWorker(@"w1") service:service]), (NSInteger)204);
	XCTAssertEqual(([self post:@"Complete" task:taskId body:@{ @"WorkerId": @"w1", @"Variables": @{ @"charged": @YES } }
	                   headers:WFWorker(@"w1") service:service]), (NSInteger)204);
	XCTAssertTrue([self ended:instance.processInstanceId engine:engine]);
	XCTAssertEqual(([self post:@"Complete" task:taskId body:@{ @"WorkerId": @"w1", @"Variables": @{} }
	                   headers:WFWorker(@"w1") service:service]), (NSInteger)404, @"done with");
}

- (void)testODataFailuresRaiseAnIncidentThatRetriesResolve
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	[self deploy:[self charging:NO] engine:engine];
	NSString *pid = [engine.runtimeService startProcessInstanceByKey:@"charge" businessKey:nil variables:nil
	                                                            error:&error].processInstanceId;
	XCTAssertNotNil(pid, @"%@", error);
	NSString *taskId = [[[self fetch:@{ @"charge": @60 } as:@"w1" service:service] firstObject]
		objectForKey:@"ExternalTaskId"];

	/* A failure with an attempt left: fetched again once the timeout is
	 * over, with what went wrong. */
	XCTAssertEqual(([self post:@"HandleFailure" task:taskId
	                      body:@{ @"WorkerId": @"w1", @"ErrorMessage": @"gateway timeout", @"Retries": @1,
	                              @"RetryTimeout": @0 }
	                   headers:WFWorker(@"w1") service:service]), (NSInteger)204);
	NSDictionary *again = [[self fetch:@{ @"charge": @60 } as:@"w2" service:service] firstObject];
	XCTAssertEqualObjects([again objectForKey:@"ExternalTaskId"], taskId);
	XCTAssertEqualObjects([again objectForKey:@"Retries"], @1);
	XCTAssertEqualObjects([again objectForKey:@"ErrorMessage"], @"gateway timeout");

	/* None left: an incident, and nothing to fetch. */
	XCTAssertEqual(([self post:@"HandleFailure" task:taskId
	                      body:@{ @"WorkerId": @"w2", @"ErrorMessage": @"card service down", @"Retries": @0,
	                              @"RetryTimeout": @0 }
	                   headers:WFWorker(@"w2") service:service]), (NSInteger)204);
	XCTAssertEqual([[self fetch:@{ @"charge": @60 } as:@"w1" service:service] count], (NSUInteger)0);
	NSString *incidents = [NSString stringWithFormat:@"Incidents?$filter=ProcessInstanceId eq '%@'", pid];
	NSArray *open = [[self jsonOf:[self get:incidents service:service]] objectForKey:@"value"];
	XCTAssertEqual([open count], (NSUInteger)1);
	XCTAssertEqualObjects([[open firstObject] objectForKey:@"IncidentType"], @"failedExternalTask");
	XCTAssertEqualObjects([[open firstObject] objectForKey:@"Configuration"], taskId);
	XCTAssertEqualObjects([[open firstObject] objectForKey:@"Message"], @"card service down");
	XCTAssertEqualObjects([[open firstObject] objectForKey:@"ActivityId"], @"charge");

	/* An operator's to retry, not a worker's: then it is fetched again. */
	XCTAssertEqual(([self post:@"SetRetries" task:taskId body:@{ @"Retries": @2 } headers:WFWorker(@"w1")
	                   service:service]), (NSInteger)403);
	XCTAssertEqual(([self post:@"SetRetries" task:taskId body:@{ @"Retries": @2 } headers:nil service:service]),
	               (NSInteger)204);
	XCTAssertEqual([[[self jsonOf:[self get:incidents service:service]] objectForKey:@"value"] count], (NSUInteger)0);
	XCTAssertEqual([[self fetch:@{ @"charge": @60 } as:@"w1" service:service] count], (NSUInteger)1);

	/* A lock released by an operator is anyone's. */
	XCTAssertEqual(([self post:@"Unlock" task:taskId body:nil headers:WFWorker(@"w1") service:service]),
	               (NSInteger)403);
	XCTAssertEqual(([self post:@"Unlock" task:taskId body:nil headers:nil service:service]), (NSInteger)204);
	XCTAssertEqual([[self fetch:@{ @"charge": @60 } as:@"w3" service:service] count], (NSUInteger)1);
}

- (void)testODataBpmnErrorsTakeTheBoundary
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	[self deploy:[self charging:YES] engine:engine];
	NSString *pid = [engine.runtimeService startProcessInstanceByKey:@"charge-or-ask" businessKey:nil variables:nil
	                                                            error:&error].processInstanceId;
	XCTAssertNotNil(pid, @"%@", error);
	NSString *taskId = [[[self fetch:@{ @"charge": @60 } as:@"w1" service:service] firstObject]
		objectForKey:@"ExternalTaskId"];
	XCTAssertEqual(([self post:@"HandleBpmnError" task:taskId
	                      body:@{ @"WorkerId": @"w1", @"ErrorCode": @"CARD_DECLINED",
	                              @"Variables": @{ @"reason": @"expired" } }
	                   headers:WFWorker(@"w1") service:service]), (NSInteger)204);
	XCTAssertEqualObjects([self active:pid engine:engine], @[ @"ask" ]);
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:pid error:NULL] objectForKey:@"reason"],
	                      @"expired");
}

/* Included into a class of each backend's suite: see WFTestCase.h. Built
 * where WorkflowKitOData is (make test ODATAKIT=...). */

#pragma mark - The OData API

/* start -> approve (a user task for the sales group) -> end */
- (WFProcessDefinition *)order
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"order"];
	[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve order" assignee:nil] addEnd:@"end"];
	[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"end"];
	[b setAssignment:@{ @"candidateGroups": @"sales" } forElement:@"approve"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

/* The status and the JSON of a request to the service. */
- (NSDictionary *)send:(NSString *)method
                  path:(NSString *)path
                  body:(id)body
               service:(ODataService *)service
{
	NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:
		[NSCharacterSet URLQueryAllowedCharacterSet]];
	NSURL *url = [NSURL URLWithString:[@"http://example.test/api/" stringByAppendingString:encoded]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setHTTPMethod:method];
	if (body != nil) {
		[request setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL]];
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	}
	ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:request target:nil action:NULL];
	[service startExchange:exchange];
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
	while (![exchange isFinished] && [deadline timeIntervalSinceNow] > 0) {
		[NSThread sleepForTimeInterval:0.005];
	}
	XCTAssertTrue([exchange isFinished], @"%@ %@ did not finish", method, path);
	NSInteger status = [(NSHTTPURLResponse *)exchange.URLResponse statusCode];
	id json = [exchange.data length] > 0
		? [NSJSONSerialization JSONObjectWithData:exchange.data options:NSJSONReadingAllowFragments error:NULL]
		: nil;
	return @{ @"status": [NSNumber numberWithInteger:status], @"json": json ?: [NSNull null],
	          @"text": [[NSString alloc] initWithData:exchange.data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"" };
}

- (NSDictionary *)get:(NSString *)path service:(ODataService *)service
{
	return [self send:@"GET" path:path body:nil service:service];
}

- (NSInteger)statusOf:(NSDictionary *)response
{
	return [[response objectForKey:@"status"] integerValue];
}

- (id)jsonOf:(NSDictionary *)response
{
	return [response objectForKey:@"json"];
}

- (ODataService *)serviceFor:(WFProcessEngine *)engine
{
	return [WFODataService serviceForEngine:engine serviceRoot:[NSURL URLWithString:@"http://example.test/api/"]];
}

/* Two orders: a for Acme over 1000, b for Beta. */
- (NSDictionary *)startOrders:(WFProcessEngine *)engine
{
	[self deploy:[self order] engine:engine];
	NSMutableDictionary *ids = [NSMutableDictionary dictionary];
	NSDictionary *variables = @{ @"a": @{ @"amount": @2500, @"customer": @"Acme", @"rush": @YES },
	                             @"b": @{ @"amount": @80.5, @"customer": @"Beta" } };
	for (NSString *key in @[ @"a", @"b" ]) {
		NSError *error = nil;
		WFProcessInstance *instance = [engine.runtimeService startProcessInstanceByKey:@"order" businessKey:key
		                                                                      variables:[variables objectForKey:key]
		                                                                          error:&error];
		XCTAssertNotNil(instance, @"%@", error);
		[ids setObject:instance.processInstanceId forKey:key];
	}
	return ids;
}

- (void)testODataServesTheAPI
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	NSDictionary *metadata = [self get:@"$metadata" service:service];
	XCTAssertEqual([self statusOf:metadata], (NSInteger)200);
	NSString *xml = [metadata objectForKey:@"text"];
	XCTAssertTrue([xml rangeOfString:@"<EntityType Name=\"Task\">"].location != NSNotFound, @"%@", xml);
	XCTAssertTrue([xml rangeOfString:@"<EntityType Name=\"Variable\">"].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"Namespace=\"WorkflowKit\""].location != NSNotFound);
	XCTAssertTrue([xml rangeOfString:@"OpenType"].location == NSNotFound);
	for (NSString *served in @[ @"Name=\"Text\"", @"Name=\"Number\" Type=\"Edm.Double\"", @"Name=\"Boolean\"",
	                            @"Name=\"Date\"", @"Name=\"Json\"", @"NavigationProperty Name=\"Variables\"" ]) {
		XCTAssertTrue([xml rangeOfString:served].location != NSNotFound, @"%@ is not served", served);
	}
	for (NSString *internal in @[ @"LockRevision", @"IsScope", @"IsConcurrent", @"ActivityInstanceId", @"Children",
	                              @"WholeNumber", @"IdentityLinks", @"EventSubscriptions" ]) {
		XCTAssertTrue([xml rangeOfString:internal].location == NSNotFound, @"%@ is served", internal);
	}
	NSRange variable = [xml rangeOfString:@"<EntityType Name=\"Variable\">"];
	NSString *variableType = [xml substringWithRange:NSMakeRange(variable.location,
		[xml rangeOfString:@"</EntityType>" options:0
		             range:NSMakeRange(variable.location, [xml length] - variable.location)].location - variable.location)];
	XCTAssertTrue([variableType rangeOfString:@"Name=\"Type\""].location == NSNotFound, @"%@", variableType);
	XCTAssertEqualObjects([service.entitySets sortedArrayUsingSelector:@selector(compare:)],
		(@[ @"FormFields", @"Forms", @"HistoricProcessInstances", @"HistoricTaskInstances", @"ProcessDefinitions",
		    @"ProcessInstances", @"Tasks", @"Variables" ]));
	XCTAssertEqualObjects(service.metadataProblems, @[]);
	XCTAssertEqualObjects(service.operationProblems, @[]);
	for (NSString *action in @[ @"StartProcessInstance", @"CorrelateMessage", @"Complete", @"Claim", @"Unclaim",
	                            @"Assign", @"Suspend", @"Activate", @"Cancel", @"SetVariables", @"RemoveVariables",
	                            @"SubmitForm", @"SubmitStartForm" ]) {
		NSString *declared = [NSString stringWithFormat:@"<Action Name=\"%@\"", action];
		XCTAssertTrue([xml rangeOfString:declared].location != NSNotFound, @"%@", action);
	}
	for (NSString *function in @[ @"FormValues", @"StartFormValues" ]) {
		NSString *declared = [NSString stringWithFormat:@"<Function Name=\"%@\"", function];
		XCTAssertTrue([xml rangeOfString:declared].location != NSNotFound, @"%@", function);
	}
}

/* The customers of the rows a query answers, sorted. */
- (NSArray *)customersOf:(NSString *)query service:(ODataService *)service
{
	NSDictionary *response = [self get:query service:service];
	XCTAssertEqual([self statusOf:response], (NSInteger)200, @"%@: %@", query, [response objectForKey:@"text"]);
	NSMutableArray *found = [NSMutableArray array];
	for (NSDictionary *row in [[self jsonOf:response] objectForKey:@"value"]) {
		NSDictionary *instance = [row objectForKey:@"ProcessInstance"] ?: row;
		[found addObject:[instance objectForKey:@"BusinessKey"] ?: [NSNull null]];
	}
	return [found sortedArrayUsingSelector:@selector(compare:)];
}

- (void)testODataReadsAndFiltersByVariables
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	NSDictionary *ids = [self startOrders:engine];
	NSString *a = [ids objectForKey:@"a"];

	/* Each value in the property of its type. */
	NSString *path = [NSString stringWithFormat:@"ProcessInstances('%@')/Variables?$orderby=Name", a];
	NSArray *variables = [[self jsonOf:[self get:path service:service]] objectForKey:@"value"];
	XCTAssertEqualObjects([variables valueForKey:@"Name"], (@[ @"amount", @"customer", @"rush" ]));
	XCTAssertEqualObjects([[variables objectAtIndex:0] objectForKey:@"Number"], @2500);
	XCTAssertEqualObjects([[variables objectAtIndex:0] objectForKey:@"Text"], [NSNull null]);
	XCTAssertEqualObjects([[variables objectAtIndex:1] objectForKey:@"Text"], @"Acme");
	XCTAssertEqualObjects([[variables objectAtIndex:2] objectForKey:@"Boolean"], @YES);

	NSString *(^tasks)(NSString *) = ^NSString *(NSString *condition) {
		return [NSString stringWithFormat:@"Tasks?$expand=ProcessInstance&$filter=ProcessInstance/Variables/any(v: %@)",
			condition];
	};
	XCTAssertEqualObjects(([self customersOf:tasks(@"v/Name eq 'amount' and v/Number gt 1000") service:service]),
		@[ @"a" ]);
	XCTAssertEqualObjects(([self customersOf:tasks(@"v/Name eq 'amount' and v/Number lt 100.5") service:service]),
		@[ @"b" ]);
	XCTAssertEqualObjects(([self customersOf:tasks(@"v/Name eq 'rush' and v/Boolean") service:service]), @[ @"a" ]);
	XCTAssertEqualObjects(([self customersOf:tasks(@"v/Name eq 'customer' and v/Text in ('Beta','Gamma')")
	                                  service:service]), @[ @"b" ]);
	XCTAssertEqualObjects(([self customersOf:@"ProcessInstances?$filter=Variables/any(v: v/Name eq 'amount' and v/Number ge 80.5)"
	                                  service:service]), (@[ @"a", @"b" ]));
	XCTAssertEqualObjects(([self customersOf:@"ProcessInstances?$filter=Variables/any(v: v/Name eq 'missing')"
	                                  service:service]), @[]);
	XCTAssertEqual([self statusOf:[self get:@"Variables?$filter=WholeNumber eq 1" service:service]], (NSInteger)400);
	XCTAssertEqual([self statusOf:[self get:@"ProcessInstances?$filter=LockRevision eq 0" service:service]],
		(NSInteger)400);

	/* Navigation, both ways, and only process instances. */
	NSString *instancePath = [NSString stringWithFormat:@"ProcessInstances('%@')", a];
	NSDictionary *instance = [self jsonOf:[self get:[instancePath stringByAppendingString:@"?$expand=Tasks"]
	                                         service:service]];
	XCTAssertEqualObjects([instance objectForKey:@"ProcessInstanceId"], a, @"%@", instance);
	XCTAssertEqualObjects([instance objectForKey:@"BusinessKey"], @"a");
	XCTAssertEqual([[instance objectForKey:@"Tasks"] count], (NSUInteger)1);
	NSString *taskId = [[[instance objectForKey:@"Tasks"] firstObject] objectForKey:@"TaskId"];
	NSDictionary *owner = [self jsonOf:[self get:[NSString stringWithFormat:@"Tasks('%@')/ProcessInstance", taskId]
	                                      service:service]];
	XCTAssertEqualObjects([owner objectForKey:@"ProcessInstanceId"], a);
	XCTAssertEqual([[[self jsonOf:[self get:@"ProcessInstances" service:service]] objectForKey:@"value"] count],
		(NSUInteger)2);
	XCTAssertEqual([[[self jsonOf:[self get:@"Variables" service:service]] objectForKey:@"value"] count],
		(NSUInteger)5);
	XCTAssertEqual([[[self jsonOf:[self get:@"ProcessDefinitions" service:service]] objectForKey:@"value"] count],
		(NSUInteger)1);
}

/* Only a process instance's own variables: not a scope's inside it. */
- (void)testODataServesTheInstancesOwnVariables
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	WFDefinitionBuilder *inner = [WFDefinitionBuilder process:@"inner"];
	[[[inner addStart:@"s"] addUserTask:@"work" name:@"Work" assignee:@"ann"] addEnd:@"e"];
	[[inner connect:@"s" to:@"work"] connect:@"work" to:@"e"];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"scoped"];
	[[[b addStart:@"start"] addSubProcess:@"stage" name:@"Stage" inner:[inner build:&error]] addEnd:@"end"];
	[[b connect:@"start" to:@"stage"] connect:@"stage" to:@"end"];
	[b addInputParameter:@"level" value:@"=2" forElement:@"stage"];
	NSString *pid = [self run:[b build:&error] engine:engine variables:@{ @"owner": @"ann" }];
	NSArray *variables = [[self jsonOf:[self get:@"Variables" service:service]] objectForKey:@"value"];
	XCTAssertEqualObjects([variables valueForKey:@"Name"], @[ @"owner" ]);
	XCTAssertEqualObjects([[variables firstObject] objectForKey:@"ProcessInstanceId"], pid);
	XCTAssertEqual([[[self jsonOf:[self get:@"ProcessInstances" service:service]] objectForKey:@"value"] count],
		(NSUInteger)1, @"not the subprocess's execution");
}

- (void)testODataActions
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	[self deploy:[self order] engine:engine];

	NSDictionary *started = [self send:@"POST" path:@"StartProcessInstance"
	                              body:@{ @"Key": @"order", @"BusinessKey": @"c", @"Variables": @{ @"amount": @5 } }
	                           service:service];
	XCTAssertEqual([self statusOf:started], (NSInteger)200, @"%@", [started objectForKey:@"text"]);
	NSString *pid = [[self jsonOf:started] objectForKey:@"ProcessInstanceId"];
	XCTAssertNotNil(pid);
	XCTAssertEqualObjects([[self jsonOf:started] objectForKey:@"BusinessKey"], @"c");
	XCTAssertEqualObjects([[engine.runtimeService variablesForProcessInstance:pid error:NULL] objectForKey:@"amount"],
		@5);
	/* A key nothing is deployed under is the caller's mistake. */
	XCTAssertEqual([self statusOf:[self send:@"POST" path:@"StartProcessInstance" body:@{ @"Key": @"none" }
	                                   service:service]], (NSInteger)400);

	NSString *taskId = [self task:@"approve" of:pid engine:engine].taskId;
	NSString *task = [NSString stringWithFormat:@"Tasks('%@')/WorkflowKit.", taskId];
	XCTAssertEqual([self statusOf:[self send:@"POST" path:[task stringByAppendingString:@"Claim"]
	                                     body:@{ @"UserId": @"ann" } service:service]], (NSInteger)204);
	XCTAssertEqualObjects([self task:@"approve" of:pid engine:engine].assignee, @"ann");
	XCTAssertEqual([self statusOf:[self send:@"POST" path:[task stringByAppendingString:@"Claim"]
	                                     body:@{ @"UserId": @"bob" } service:service]], (NSInteger)409);
	XCTAssertEqual([self statusOf:[self send:@"POST" path:[task stringByAppendingString:@"Unclaim"] body:nil
	                                  service:service]], (NSInteger)204);
	XCTAssertEqual([self statusOf:[self send:@"POST" path:[task stringByAppendingString:@"Assign"]
	                                     body:@{ @"UserId": @"cy" } service:service]], (NSInteger)204);
	XCTAssertEqualObjects([self task:@"approve" of:pid engine:engine].assignee, @"cy");

	/* Suspended, it cannot be completed; activated, it can. */
	NSString *instance = [NSString stringWithFormat:@"ProcessInstances('%@')/WorkflowKit.", pid];
	XCTAssertEqual([self statusOf:[self send:@"POST" path:[instance stringByAppendingString:@"Suspend"] body:nil
	                                  service:service]], (NSInteger)204);
	XCTAssertEqualObjects(([[self jsonOf:[self get:[NSString stringWithFormat:@"Tasks('%@')/Suspended", taskId]
	                                      service:service]] objectForKey:@"value"]), @YES);
	XCTAssertEqual([self statusOf:[self send:@"POST" path:[task stringByAppendingString:@"Complete"] body:@{}
	                                  service:service]], (NSInteger)409);
	XCTAssertEqual([self statusOf:[self send:@"POST" path:[instance stringByAppendingString:@"Activate"] body:nil
	                                  service:service]], (NSInteger)204);
	NSDictionary *completed = [self send:@"POST" path:[task stringByAppendingString:@"Complete"]
	                                body:@{ @"Variables": @{ @"approved": @YES } } service:service];
	XCTAssertEqual([self statusOf:completed], (NSInteger)204, @"%@", [completed objectForKey:@"text"]);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqual(([self statusOf:[self get:[NSString stringWithFormat:@"ProcessInstances('%@')", pid]
	                                service:service]]), (NSInteger)404);
	NSDictionary *history = [self jsonOf:[self get:[NSString stringWithFormat:@"HistoricProcessInstances('%@')", pid]
	                                        service:service]];
	XCTAssertEqualObjects([history objectForKey:@"BusinessKey"], @"c", @"%@", history);
	XCTAssertNotNil([history objectForKey:@"EndTime"]);

	/* Canceled, with a reason. */
	NSString *other = [self run:[self order] engine:engine variables:nil];
	XCTAssertEqual(([self statusOf:[self send:@"POST"
	                                    path:[NSString stringWithFormat:@"ProcessInstances('%@')/WorkflowKit.Cancel", other]
	                                    body:@{ @"Reason": @"withdrawn" } service:service]]), (NSInteger)204);
	XCTAssertTrue([self ended:other engine:engine]);
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:other] deleteReason], @"withdrawn");
}

- (void)testODataChangesVariablesThroughActions
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	NSDictionary *ids = [self startOrders:engine];
	NSString *a = [ids objectForKey:@"a"];
	NSString *path = [NSString stringWithFormat:@"ProcessInstances('%@')", a];

	NSDictionary *set = [self send:@"POST" path:[path stringByAppendingString:@"/WorkflowKit.SetVariables"]
	                          body:@{ @"Variables": @{ @"amount": @3000, @"notes": @{ @"by": @"ann" } } }
	                       service:service];
	XCTAssertEqual([self statusOf:set], (NSInteger)204, @"%@", [set objectForKey:@"text"]);
	NSDictionary *removed = [self send:@"POST" path:[path stringByAppendingString:@"/WorkflowKit.RemoveVariables"]
	                              body:@{ @"Names": @[ @"rush", @"never" ] } service:service];
	XCTAssertEqual([self statusOf:removed], (NSInteger)204, @"%@", [removed objectForKey:@"text"]);
	XCTAssertEqualObjects([engine.runtimeService variablesForProcessInstance:a error:&error],
		(@{ @"amount": @3000, @"customer": @"Acme", @"notes": @{ @"by": @"ann" } }));
	NSString *notes = [path stringByAppendingString:@"/Variables?$filter=Name eq 'notes'"];
	XCTAssertEqualObjects(([[[[self jsonOf:[self get:notes service:service]] objectForKey:@"value"] firstObject]
		objectForKey:@"Json"]), (@{ @"by": @"ann" }));

	/* Nothing is written but through the actions. */
	NSString *taskPath = [NSString stringWithFormat:@"Tasks('%@')", [self task:@"approve" of:a engine:engine].taskId];
	XCTAssertEqual([self statusOf:[self send:@"PATCH" path:path body:@{ @"BusinessKey": @"z" } service:service]],
		(NSInteger)405);
	XCTAssertEqual([self statusOf:[self send:@"PATCH" path:taskPath body:@{ @"Assignee": @"ann" } service:service]],
		(NSInteger)405);
	XCTAssertEqual([self statusOf:[self send:@"DELETE" path:taskPath body:nil service:service]], (NSInteger)405);
	XCTAssertEqual([self statusOf:[self send:@"POST" path:@"Variables" body:@{ @"Name": @"x" } service:service]],
		(NSInteger)405);
	XCTAssertEqual([self statusOf:[self send:@"POST" path:@"ProcessInstances" body:@{ @"BusinessKey": @"x" }
	                                  service:service]], (NSInteger)405);
	XCTAssertNil([self task:@"approve" of:a engine:engine].assignee);
}

/* start (a form taking the order's id as the business key) -> check (a
 * user task with a form) -> end */
- (WFProcessDefinition *)formOrder
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"formOrder"];
	[[[b addStart:@"start"] addUserTask:@"check" name:@"Check" assignee:@"ann"] addEnd:@"end"];
	[[b connect:@"start" to:@"check"] connect:@"check" to:@"end"];
	WFFormConstraint *required = [WFFormConstraint constraint:@"required" configuration:nil];
	[b setForm:[WFFormDefinition formWithKey:nil
	                                  fields:@[ [WFFormField fieldWithId:@"orderId" label:@"Order" type:WFFormFieldTypeString
	                                                        defaultValue:nil values:nil constraints:@[ required ]
	                                                          properties:nil] ]
	                      businessKeyFieldId:@"orderId"]
	forElement:@"start"];
	NSArray *fields = @[
		[WFFormField fieldWithId:@"amount" label:@"Amount" type:WFFormFieldTypeLong defaultValue:nil values:nil
		             constraints:(@[ required, [WFFormConstraint constraint:@"max" configuration:@"100"] ]) properties:nil],
		[WFFormField fieldWithId:@"size" label:@"Size" type:WFFormFieldTypeEnum
		            defaultValue:[WFFeelExpression expressionWithString:@"\"m\"" error:NULL]
		                  values:(@[ [WFFormFieldValue valueWithId:@"s" name:@"Small"],
		                             [WFFormFieldValue valueWithId:@"m" name:@"Medium"] ])
		             constraints:nil properties:@{ @"widget": @"radio" }],
		[WFFormField fieldWithId:@"due" label:@"Due" type:WFFormFieldTypeDate
		            defaultValue:[WFFeelExpression expressionWithString:@"date and time(\"2030-01-02T00:00:00Z\")" error:NULL]
		                  values:nil constraints:nil properties:nil],
	];
	[b setForm:[WFFormDefinition formWithKey:@"app:check" fields:fields businessKeyFieldId:nil] forElement:@"check"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (void)testODataServesForms
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	[self deploy:[self formOrder] engine:engine];

	/* The start form, from the definition. */
	NSString *definitionId = [[[[self jsonOf:[self get:@"ProcessDefinitions" service:service]] objectForKey:@"value"]
		firstObject] objectForKey:@"ProcessDefinitionId"];
	NSArray *forms = [[self jsonOf:[self get:[NSString stringWithFormat:@"ProcessDefinitions('%@')/Forms?$orderby=ActivityId",
	                                          definitionId] service:service]] objectForKey:@"value"];
	XCTAssertEqualObjects([forms valueForKey:@"ActivityId"], (@[ @"check", @"start" ]), @"%@", forms);
	XCTAssertEqualObjects([forms valueForKey:@"IsStartForm"], (@[ @NO, @YES ]));
	XCTAssertEqualObjects([[forms lastObject] objectForKey:@"BusinessKeyField"], @"orderId");
	NSDictionary *startValues = [self jsonOf:[self get:@"StartFormValues(Key='formOrder')" service:service]];
	XCTAssertEqualObjects([startValues objectForKey:@"value"], (@{ @"orderId": [NSNull null] }), @"%@", startValues);

	/* Started through its form: the business key is the field's. */
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"SubmitStartForm"
	                                      body:@{ @"Key": @"formOrder", @"Values": @{} } service:service]]), (NSInteger)400);
	NSDictionary *started = [self send:@"POST" path:@"SubmitStartForm"
	                              body:@{ @"Key": @"formOrder", @"Values": @{ @"orderId": @"o-7", @"amount": @40 } }
	                           service:service];
	XCTAssertEqual([self statusOf:started], (NSInteger)200, @"%@", [started objectForKey:@"text"]);
	XCTAssertEqualObjects([[self jsonOf:started] objectForKey:@"BusinessKey"], @"o-7");
	NSString *pid = [[self jsonOf:started] objectForKey:@"ProcessInstanceId"];

	/* The task's form, its fields in order, and its values. */
	NSString *taskId = [self task:@"check" of:pid engine:engine].taskId;
	NSString *task = [NSString stringWithFormat:@"Tasks('%@')", taskId];
	NSDictionary *form = [self jsonOf:[self get:[task stringByAppendingString:@"/Form?$expand=Fields($orderby=Position)"]
	                                     service:service]];
	XCTAssertEqualObjects([form objectForKey:@"FormKey"], @"app:check", @"%@", form);
	NSArray *fields = [form objectForKey:@"Fields"];
	XCTAssertEqualObjects([fields valueForKey:@"FieldId"], (@[ @"amount", @"size", @"due" ]));
	XCTAssertEqualObjects([fields valueForKey:@"Type"], (@[ @"long", @"enum", @"date" ]));
	XCTAssertEqualObjects([[fields objectAtIndex:0] objectForKey:@"Required"], @YES);
	XCTAssertEqualObjects([[fields objectAtIndex:0] objectForKey:@"Max"], @"100");
	XCTAssertEqualObjects([[fields objectAtIndex:1] objectForKey:@"Values"],
		(@[ @{ @"Id": @"s", @"Name": @"Small" }, @{ @"Id": @"m", @"Name": @"Medium" } ]));
	XCTAssertEqualObjects([[fields objectAtIndex:1] objectForKey:@"Properties"], @{ @"widget": @"radio" });
	NSDictionary *values = [[self jsonOf:[self get:[task stringByAppendingString:@"/WorkflowKit.FormValues()"]
	                                         service:service]] objectForKey:@"value"];
	XCTAssertEqualObjects(values, (@{ @"amount": @40, @"size": @"m", @"due": @"2030-01-02T00:00:00Z" }));
	XCTAssertEqual([[[self jsonOf:[self get:@"FormFields" service:service]] objectForKey:@"value"] count], (NSUInteger)4);

	/* Submitted: checked, then the task completes. */
	NSString *submit = [task stringByAppendingString:@"/WorkflowKit.SubmitForm"];
	NSDictionary *refused = [self send:@"POST" path:submit body:@{ @"Values": @{ @"amount": @500 } } service:service];
	XCTAssertEqual([self statusOf:refused], (NSInteger)400);
	XCTAssertTrue([[refused objectForKey:@"text"] rangeOfString:@"more than 100"].location != NSNotFound,
		@"%@", [refused objectForKey:@"text"]);
	XCTAssertNotNil([self task:@"check" of:pid engine:engine]);
	NSDictionary *submitted = [self send:@"POST" path:submit
	                                body:@{ @"Values": @{ @"amount": @"60", @"size": @"s" } } service:service];
	XCTAssertEqual([self statusOf:submitted], (NSInteger)204, @"%@", [submitted objectForKey:@"text"]);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"amount"], @60);
}

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
	return [self send:method path:path body:body headers:nil service:service];
}

- (NSDictionary *)send:(NSString *)method
                  path:(NSString *)path
                  body:(id)body
               headers:(NSDictionary *)headers
               service:(ODataService *)service
{
	NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:
		[NSCharacterSet URLQueryAllowedCharacterSet]];
	NSURL *url = [NSURL URLWithString:[@"http://example.test/api/" stringByAppendingString:encoded]];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setHTTPMethod:method];
	for (NSString *name in headers) {
		[request setValue:[headers objectForKey:name] forHTTPHeaderField:name];
	}
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
	for (NSString *internal in @[ @"LockRevision", @"IsScope", @"IsConcurrent", @"Children",
	                              @"WholeNumber", @"IdentityLinks", @"EventSubscriptions" ]) {
		XCTAssertTrue([xml rangeOfString:internal].location == NSNotFound, @"%@ is served", internal);
	}
	NSString *(^type)(NSString *) = ^NSString *(NSString *name) {
		NSRange start = [xml rangeOfString:[NSString stringWithFormat:@"<EntityType Name=\"%@\">", name]];
		NSRange end = [xml rangeOfString:@"</EntityType>" options:0
		                           range:NSMakeRange(start.location, [xml length] - start.location)];
		return [xml substringWithRange:NSMakeRange(start.location, end.location - start.location)];
	};
	XCTAssertTrue([type(@"Variable") rangeOfString:@"Name=\"Type\""].location == NSNotFound, @"%@", type(@"Variable"));
	XCTAssertTrue([type(@"Task") rangeOfString:@"ActivityInstanceId"].location == NSNotFound, @"%@", type(@"Task"));
	XCTAssertEqualObjects([service.entitySets sortedArrayUsingSelector:@selector(compare:)],
		(@[ @"DecisionDefinitions", @"Deployments", @"ExternalTasks", @"Forms", @"HistoricActivityInstances",
		    @"HistoricDecisionInstances", @"HistoricIncidents", @"HistoricJobLogs", @"HistoricProcessInstances",
		    @"HistoricTaskInstances", @"HistoricVariableUpdates", @"Incidents", @"Jobs", @"ProcessDefinitions",
		    @"ProcessInstances", @"Resources", @"Tasks", @"Variables" ]));
	XCTAssertEqualObjects(service.metadataProblems, @[]);
	XCTAssertEqualObjects(service.operationProblems, @[]);
	for (NSString *action in @[ @"StartProcessInstance", @"CorrelateMessage", @"Complete", @"Claim", @"Unclaim",
	                            @"Assign", @"Suspend", @"Activate", @"Cancel", @"SetVariables", @"RemoveVariables",
	                            @"SubmitForm", @"SubmitStartForm", @"Deploy", @"Execute", @"SetRetries" ]) {
		NSString *declared = [NSString stringWithFormat:@"<Action Name=\"%@\"", action];
		XCTAssertTrue([xml rangeOfString:declared].location != NSNotFound, @"%@", action);
	}
	for (NSString *function in @[ @"FormInstance", @"StartFormInstance", @"ActiveActivities", @"Bpmn" ]) {
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
	                                  fields:(@[ [WFFormField fieldWithId:@"orderId" label:@"Order" type:WFFormFieldTypeString
	                                                         defaultValue:nil values:nil constraints:@[ required ]
	                                                           properties:nil],
	                                             [WFFormField fieldWithId:@"amount" label:@"Amount" type:WFFormFieldTypeLong
	                                                         defaultValue:nil values:nil constraints:nil properties:nil] ])
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

/* An instance's elements' text, by name. */
- (NSDictionary *)textsOf:(NSString *)xml
{
	NSXMLDocument *instance = [[NSXMLDocument alloc] initWithXMLString:xml ?: @"" options:0 error:NULL];
	NSMutableDictionary *texts = [NSMutableDictionary dictionary];
	for (NSXMLNode *node in [[instance rootElement] children]) {
		[texts setObject:[node stringValue] ?: @"" forKey:[node name]];
	}
	return texts;
}

- (void)testODataServesForms
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	[self deploy:[self formOrder] engine:engine];

	/* The definition's forms, each an XForms document. */
	NSString *definitionId = [[[[self jsonOf:[self get:@"ProcessDefinitions" service:service]] objectForKey:@"value"]
		firstObject] objectForKey:@"ProcessDefinitionId"];
	NSArray *forms = [[self jsonOf:[self get:[NSString stringWithFormat:@"ProcessDefinitions('%@')/Forms?$orderby=ActivityId",
	                                          definitionId] service:service]] objectForKey:@"value"];
	XCTAssertEqualObjects([forms valueForKey:@"ActivityId"], (@[ @"check", @"start" ]), @"%@", forms);
	XCTAssertEqualObjects([forms valueForKey:@"IsStartForm"], (@[ @NO, @YES ]));
	XCTAssertTrue([[[forms lastObject] objectForKey:@"Document"] rangeOfString:@"ref=\"orderId\""].location != NSNotFound);
	NSDictionary *start = [self jsonOf:[self get:@"StartFormInstance(Key='formOrder')" service:service]];
	XCTAssertEqualObjects([self textsOf:[start objectForKey:@"value"]], (@{ @"orderId": @"", @"amount": @"" }),
		@"%@", start);

	/* Started through its form: the business key is the field's. */
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"SubmitStartForm"
	                                      body:@{ @"Key": @"formOrder", @"Instance": @"<data/>" } service:service]]),
		(NSInteger)400);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"SubmitStartForm"
	                                      body:@{ @"Key": @"formOrder", @"Instance": @"not <xml" } service:service]]),
		(NSInteger)400);
	NSDictionary *started = [self send:@"POST" path:@"SubmitStartForm"
	                              body:@{ @"Key": @"formOrder",
	                                      @"Instance": @"<data><orderId>o-7</orderId><amount>40</amount></data>" }
	                           service:service];
	XCTAssertEqual([self statusOf:started], (NSInteger)200, @"%@", [started objectForKey:@"text"]);
	XCTAssertEqualObjects([[self jsonOf:started] objectForKey:@"BusinessKey"], @"o-7");
	NSString *pid = [[self jsonOf:started] objectForKey:@"ProcessInstanceId"];

	/* The task's form, and the instance it opens with. */
	NSString *taskId = [self task:@"check" of:pid engine:engine].taskId;
	NSString *task = [NSString stringWithFormat:@"Tasks('%@')", taskId];
	NSDictionary *form = [self jsonOf:[self get:[task stringByAppendingString:@"/Form"] service:service]];
	XCTAssertEqualObjects([form objectForKey:@"FormKey"], @"app:check", @"%@", form);
	XCTAssertTrue([[form objectForKey:@"Document"] rangeOfString:@"xf:select1"].location != NSNotFound);
	NSString *instance = [[self jsonOf:[self get:[task stringByAppendingString:@"/WorkflowKit.FormInstance()"]
	                                        service:service]] objectForKey:@"value"];
	XCTAssertEqualObjects([self textsOf:instance], (@{ @"amount": @"40", @"size": @"m", @"due": @"2030-01-02T00:00:00Z" }));

	/* Submitted: the handler checks it, then the task completes. */
	NSString *submit = [task stringByAppendingString:@"/WorkflowKit.SubmitForm"];
	NSDictionary *refused = [self send:@"POST" path:submit
	                              body:@{ @"Instance": @"<data><amount>500</amount></data>" } service:service];
	XCTAssertEqual([self statusOf:refused], (NSInteger)400);
	XCTAssertTrue([[refused objectForKey:@"text"] rangeOfString:@"more than 100"].location != NSNotFound,
		@"%@", [refused objectForKey:@"text"]);
	XCTAssertNotNil([self task:@"check" of:pid engine:engine]);
	NSDictionary *submitted = [self send:@"POST" path:submit
	                                body:@{ @"Instance": @"<data><amount>60</amount><size>s</size></data>" }
	                             service:service];
	XCTAssertEqual([self statusOf:submitted], (NSInteger)204, @"%@", [submitted objectForKey:@"text"]);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"amount"], @60);
}

/* What an operator sees: deployments and what they hold, where instances
 * wait, failed jobs and their incidents, and the history of it all. */
- (void)testODataServesTheOperationalState
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	engine.historyLevel = WFHistoryLevelFull;
	ODataService *service = [self serviceFor:engine];

	/* Deployed through the API, and read back. */
	NSString *bpmn = [WFBpmnWriter XMLStringFromDefinition:[self fragileDefinition:nil] error:&error];
	NSDictionary *deployed = [self send:@"POST" path:@"Deploy"
	                               body:@{ @"Name": @"fragile", @"Resources": @{ @"fragile.bpmn": bpmn } } service:service];
	XCTAssertEqual([self statusOf:deployed], (NSInteger)200, @"%@", [deployed objectForKey:@"text"]);
	NSString *deploymentId = [[self jsonOf:deployed] objectForKey:@"value"];
	NSString *deployment = [NSString stringWithFormat:@"Deployments('%@')", deploymentId];
	XCTAssertEqualObjects([[self jsonOf:[self get:deployment service:service]] objectForKey:@"Name"], @"fragile");
	NSArray *resources = [[self jsonOf:[self get:[deployment stringByAppendingString:@"/Resources"] service:service]]
		objectForKey:@"value"];
	XCTAssertEqualObjects([resources valueForKey:@"Name"], @[ @"fragile.bpmn" ]);
	NSArray *definitions = [[self jsonOf:[self get:[deployment stringByAppendingString:@"/ProcessDefinitions"]
	                                        service:service]] objectForKey:@"value"];
	XCTAssertEqualObjects([definitions valueForKey:@"Key"], @[ @"fragile" ]);
	NSString *definition = [NSString stringWithFormat:@"ProcessDefinitions('%@')",
		[[definitions firstObject] objectForKey:@"ProcessDefinitionId"]];
	NSString *xml = [[self jsonOf:[self get:[definition stringByAppendingString:@"/WorkflowKit.Bpmn()"]
	                                 service:service]] objectForKey:@"value"];
	XCTAssertTrue([xml rangeOfString:@"id=\"fragile\""].location != NSNotFound, @"%@", xml);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"Deploy"
	                                      body:@{ @"Name": @"broken", @"Resources": @{ @"broken.bpmn": @"<nope" } }
	                                   service:service]]), (NSInteger)400);

	/* Where it waits: the gateway's job. */
	NSDictionary *started = [self send:@"POST" path:@"StartProcessInstance" body:@{ @"Key": @"fragile" } service:service];
	NSString *pid = [[self jsonOf:started] objectForKey:@"ProcessInstanceId"];
	NSString *instance = [NSString stringWithFormat:@"ProcessInstances('%@')", pid];
	XCTAssertEqualObjects(([[self jsonOf:[self get:[instance stringByAppendingString:@"/WorkflowKit.ActiveActivities()"]
	                                        service:service]] objectForKey:@"value"]), @[ @"route" ]);
	NSString *filter = [NSString stringWithFormat:@"Jobs?$filter=ProcessInstanceId eq '%@'", pid];
	NSArray *jobs = [[self jsonOf:[self get:filter service:service]] objectForKey:@"value"];
	XCTAssertEqual([jobs count], (NSUInteger)1);
	XCTAssertEqualObjects([[jobs firstObject] objectForKey:@"Retries"], @3);
	NSString *job = [NSString stringWithFormat:@"Jobs('%@')", [[jobs firstObject] objectForKey:@"JobId"]];

	/* It fails every attempt: an incident. */
	for (int attempt = 0; attempt < 3; attempt++) {
		XCTAssertEqual([self statusOf:[self send:@"POST" path:[job stringByAppendingString:@"/WorkflowKit.Execute"]
		                                     body:nil service:service]], (NSInteger)400);
	}
	NSDictionary *failed = [self jsonOf:[self get:job service:service]];
	XCTAssertEqualObjects([failed objectForKey:@"Retries"], @0);
	XCTAssertNotEqualObjects([failed objectForKey:@"ExceptionMessage"], [NSNull null]);
	NSString *incidents = [NSString stringWithFormat:@"Incidents?$filter=ProcessInstanceId eq '%@'", pid];
	NSArray *open = [[self jsonOf:[self get:incidents service:service]] objectForKey:@"value"];
	XCTAssertEqual([open count], (NSUInteger)1);
	XCTAssertEqualObjects([[open firstObject] objectForKey:@"Configuration"], [[jobs firstObject] objectForKey:@"JobId"]);
	XCTAssertEqualObjects([[open firstObject] objectForKey:@"ActivityId"], @"route");

	/* Fixed, and given an attempt: the incident is resolved and it runs. */
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:[instance stringByAppendingString:@"/WorkflowKit.SetVariables"]
	                                     body:@{ @"Variables": @{ @"amount": @500 } } service:service]]), (NSInteger)204);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:[job stringByAppendingString:@"/WorkflowKit.SetRetries"]
	                                     body:@{ @"Retries": @1 } service:service]]), (NSInteger)204);
	XCTAssertEqual([[[self jsonOf:[self get:incidents service:service]] objectForKey:@"value"] count], (NSUInteger)0);
	XCTAssertEqual([self statusOf:[self send:@"POST" path:[job stringByAppendingString:@"/WorkflowKit.Execute"]
	                                     body:nil service:service]], (NSInteger)204);
	XCTAssertTrue([self ended:pid engine:engine]);

	/* And its history. */
	NSString *of = [NSString stringWithFormat:@"?$filter=ProcessInstanceId eq '%@'", pid];
	NSArray *activities = [[self jsonOf:[self get:[@"HistoricActivityInstances" stringByAppendingString:of]
	                                       service:service]] objectForKey:@"value"];
	XCTAssertTrue([[activities valueForKey:@"ActivityId"] containsObject:@"big"], @"%@", activities);
	NSArray *past = [[self jsonOf:[self get:[@"HistoricIncidents" stringByAppendingString:of] service:service]]
		objectForKey:@"value"];
	XCTAssertEqual([past count], (NSUInteger)1);
	NSArray *log = [[self jsonOf:[self get:[@"HistoricJobLogs" stringByAppendingString:of] service:service]]
		objectForKey:@"value"];
	XCTAssertTrue([[log valueForKey:@"State"] count] >= 4, @"%@", log);
	NSArray *updates = [[self jsonOf:[self get:[@"HistoricVariableUpdates" stringByAppendingString:of] service:service]]
		objectForKey:@"value"];
	XCTAssertEqualObjects([updates valueForKey:@"Number"], @[ @500 ]);

	/* A definition suspended starts nothing. */
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:[definition stringByAppendingString:@"/WorkflowKit.Suspend"]
	                                     body:@{ @"IncludeInstances": @NO } service:service]]), (NSInteger)204);
	XCTAssertEqualObjects([[self jsonOf:[self get:definition service:service]] objectForKey:@"Suspended"], @YES);
	XCTAssertEqual([self statusOf:[self send:@"POST" path:@"StartProcessInstance" body:@{ @"Key": @"fragile" }
	                                  service:service]], (NSInteger)409);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:[definition stringByAppendingString:@"/WorkflowKit.Activate"]
	                                     body:@{ @"IncludeInstances": @NO } service:service]]), (NSInteger)204);
}

/* Who may see and do what: the processes say it, by user, group or claim,
 * and an operator's scopes lift it. */
- (void)testODataLimitsWhatEachCallerSeesAndDoes
{
	WFProcessEngine *engine = [self engineWithHandler:nil];
	ODataService *service = [self serviceFor:engine];
	service.authenticator = [[WFHeaderAuthenticator alloc] init];
	NSString *a = [self run:[self claimedPurchase] engine:engine variables:nil];
	[self run:[self claimedPurchase] engine:engine variables:nil];
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"open"];
	[[[b addStart:@"start"] addUserTask:@"chore" name:@"Chore" assignee:@"dan"] addEnd:@"end"];
	[[b connect:@"start" to:@"chore"] connect:@"chore" to:@"end"];
	NSError *error = nil;
	[self run:[b build:&error] engine:engine variables:nil];

	NSDictionary *ann = @{ @"X-User": @"ann", @"X-Groups": @"sales" };
	NSDictionary *bob = @{ @"X-User": @"bob", @"X-Department": @"purchasing" };
	NSDictionary *eve = @{ @"X-User": @"eve", @"X-Groups": @"staff" };
	NSDictionary *operator = @{ @"X-User": @"oz", @"X-Scopes": @"Tasks.ReadAll Tasks.Assign ProcessDefinitions.ReadAll ProcessInstances.StartAny" };
	NSUInteger (^count)(NSString *, NSDictionary *) = ^NSUInteger(NSString *path, NSDictionary *who) {
		NSDictionary *response = [self send:@"GET" path:path body:nil headers:who service:service];
		XCTAssertEqual([self statusOf:response], (NSInteger)200, @"%@: %@", path, [response objectForKey:@"text"]);
		return [[[self jsonOf:response] objectForKey:@"value"] count];
	};
	XCTAssertEqual([self statusOf:[self send:@"GET" path:@"Tasks" body:nil service:service]], (NSInteger)401);
	XCTAssertEqual(count(@"Tasks", ann), (NSUInteger)2, @"offered to sales");
	XCTAssertEqual(count(@"Tasks", bob), (NSUInteger)2, @"offered to purchasing, a claim");
	XCTAssertEqual(count(@"Tasks", @{ @"X-User": @"dan" }), (NSUInteger)1, @"his own");
	XCTAssertEqual(count(@"Tasks", eve), (NSUInteger)0);
	XCTAssertEqual(count(@"Tasks", operator), (NSUInteger)3);

	/* Claiming: for oneself; then the task is hers alone. */
	NSString *taskId = [self task:@"review" of:a engine:engine].taskId;
	NSString *claim = [NSString stringWithFormat:@"Tasks('%@')/WorkflowKit.Claim", taskId];
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:claim body:@{ @"UserId": @"bob" } headers:ann service:service]]),
		(NSInteger)403);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:claim body:@{} headers:ann service:service]]), (NSInteger)204);
	XCTAssertEqualObjects([self task:@"review" of:a engine:engine].assignee, @"ann");
	XCTAssertEqual(count(@"Tasks", bob), (NSUInteger)1);
	XCTAssertEqual(count(@"Tasks", ann), (NSUInteger)2);
	NSString *unclaim = [NSString stringWithFormat:@"Tasks('%@')/WorkflowKit.Unclaim", taskId];
	XCTAssertEqual([self statusOf:[self send:@"POST" path:unclaim body:nil headers:bob service:service]], (NSInteger)404,
		@"not his to see");
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:[NSString stringWithFormat:@"Tasks('%@')/WorkflowKit.Assign", taskId]
	                                     body:@{ @"UserId": @"bob" } headers:operator service:service]]), (NSInteger)204);
	XCTAssertEqualObjects([self task:@"review" of:a engine:engine].assignee, @"bob");
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:[NSString stringWithFormat:@"Tasks('%@')/WorkflowKit.Complete", taskId]
	                                     body:@{} headers:eve service:service]]), (NSInteger)404);

	/* Starting: what each may start. */
	XCTAssertEqual(count(@"ProcessDefinitions", eve), (NSUInteger)1, @"the one that names no starters");
	XCTAssertEqual(count(@"ProcessDefinitions", bob), (NSUInteger)2);
	XCTAssertEqual(count(@"ProcessDefinitions", operator), (NSUInteger)2);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"StartProcessInstance" body:@{ @"Key": @"claimed" }
	                                  headers:eve service:service]]), (NSInteger)403);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"StartProcessInstance" body:@{ @"Key": @"open" }
	                                  headers:eve service:service]]), (NSInteger)200);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"StartProcessInstance" body:@{ @"Key": @"claimed" }
	                                  headers:bob service:service]]), (NSInteger)200);
	XCTAssertEqual(([self statusOf:[self send:@"POST" path:@"StartProcessInstance" body:@{ @"Key": @"claimed" }
	                                  headers:operator service:service]]), (NSInteger)200);
}

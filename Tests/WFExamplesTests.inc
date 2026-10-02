/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - The example processes

/*
 * Each example in Examples/Processes, deployed as it is -- a directory a
 * deployment, as wf-serve -Deployments takes them -- and run through as
 * its documentation tells it: the examples are what the engine does.
 */

- (NSString *)examplesDirectory
{
	NSString *given = [[[NSProcessInfo processInfo] environment] objectForKey:@"WORKFLOWKIT_EXAMPLES"];
	if (given != nil) {
		return given;
	}
	NSString *tests = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
	if (![tests isAbsolutePath]) {
		tests = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:tests];
	}
	return [[tests stringByAppendingPathComponent:@"../Examples/Processes"] stringByStandardizingPath];
}

/* The example's directory, deployed under its name, with the delegates
 * and listeners the examples call (Examples/Plugins). */
- (void)deployExample:(NSString *)name engine:(WFProcessEngine *)engine
{
	[engine addPlugin:[[WFExamplePlugin alloc] init]];
	NSString *directory = [[self examplesDirectory] stringByAppendingPathComponent:name];
	NSMutableDictionary *resources = [NSMutableDictionary dictionary];
	for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL]) {
		if (![file hasPrefix:@"."]) {
			[resources setObject:[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:file]]
			              forKey:file];
		}
	}
	XCTAssertTrue([resources count] > 0, @"no example at %@", directory);
	NSError *error = nil;
	XCTAssertNotNil([engine.repositoryService deployResources:resources name:name filterDuplicates:NO error:&error],
	                @"%@: %@", name, error);
}

- (NSString *)startExample:(NSString *)key businessKey:(NSString *)businessKey variables:(NSDictionary *)variables
                    engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	WFProcessInstance *instance = [engine.runtimeService startProcessInstanceByKey:key businessKey:businessKey
	                                                                     variables:variables error:&error];
	XCTAssertNotNil(instance, @"%@: %@", key, error);
	XCTAssertTrue([engine waitUntilSettled:instance.processInstanceId timeout:10.0]);
	return instance.processInstanceId;
}

/* The activities the instance went through, and did not leave canceled. */
- (NSArray<NSString *> *)passed:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	NSMutableArray *ids = [NSMutableArray array];
	for (WFHistoricActivityInstance *activity in [engine.historyService historicActivityInstancesForProcessInstance:processInstanceId]) {
		if (!activity.canceled) {
			[ids addObject:activity.activityId];
		}
	}
	return ids;
}

/* Runs the instance's jobs that are due by then, as the job executor would. */
- (void)runJobsOf:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	for (WFJob *job in [engine.managementService jobsForProcessInstance:processInstanceId]) {
		XCTAssertTrue([engine.managementService executeJob:job.jobId error:&error], @"%@: %@", job.activityId, error);
	}
	XCTAssertTrue([engine waitUntilSettled:processInstanceId timeout:10.0]);
}

- (WFJob *)job:(NSString *)activityId of:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	for (WFJob *job in [engine.managementService jobsForProcessInstance:processInstanceId]) {
		if ([job.activityId isEqualToString:activityId]) {
			return job;
		}
	}
	XCTFail(@"no job at %@", activityId);
	return nil;
}

- (void)fire:(NSString *)activityId of:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	WFJob *job = [self job:activityId of:processInstanceId engine:engine];
	XCTAssertTrue(job == nil || [engine.managementService executeJob:job.jobId error:&error], @"%@: %@", activityId, error);
	XCTAssertTrue([engine waitUntilSettled:processInstanceId timeout:10.0]);
}

/* A child of the instance's root: its text, and a new one set. */
- (NSString *)field:(NSString *)name of:(NSXMLDocument *)instance
{
	return [[[[instance rootElement] elementsForName:name] firstObject] stringValue];
}

- (void)setField:(NSString *)name of:(NSXMLDocument *)instance to:(NSString *)text
{
	[(NSXMLElement *)[[[instance rootElement] elementsForName:name] firstObject] setStringValue:text];
}

- (NSXMLDocument *)XML:(NSString *)text
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error];
	XCTAssertNotNil(document, @"%@", error);
	return document;
}

/* A task's form: deployed with the process, the handler's instance in it. */
- (WFFormData *)form:(NSString *)taskId deployedAs:(NSString *)marker engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	WFFormData *form = [engine.formService formDataForTask:taskId error:&error];
	XCTAssertNotNil(form, @"%@", error);
	XCTAssertTrue([[form.document XMLString] rangeOfString:marker].location != NSNotFound,
	              @"the form deployed with the process: %@", [form.document XMLString]);
	XCTAssertNotNil(form.instance);
	return form;
}

/* Entered on the order form, in stock and express: charged and packed at
 * once, by courier; not in stock: back-ordered. */
- (void)testOrderFulfilment
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	[handler.results setObject:@{ @"inStock": @YES } forKey:@"check-stock"];
	[handler.results setObject:@{ @"shippingCost": @5 } forKey:@"shipping-cost"];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	[self deployExample:@"order-fulfilment" engine:engine];

	/* The order form opens blank, with a line to fill in. */
	NSError *error = nil;
	WFFormData *form = [engine.formService startFormDataForKey:@"order-fulfilment" error:&error];
	XCTAssertNotNil(form, @"%@", error);
	XCTAssertTrue([[form.document XMLString] rangeOfString:@"Add line"].location != NSNotFound, @"order.xhtml");
	XCTAssertTrue([[form.document XMLString] rangeOfString:@"<orderNumber"].location != NSNotFound,
	              @"its names as they are, not lower case as HTML's");
	XCTAssertEqual([[[[[form.instance rootElement] elementsForName:@"lines"] firstObject] elementsForName:@"line"] count],
	               (NSUInteger)1);
	XCTAssertEqualObjects([self field:@"express" of:form.instance], @"false");

	/* The handler checks the order again, whatever the form let through. */
	NSString *lines = @"<lines><line><item>lamp</item><quantity>2</quantity><price>40</price><amount>80</amount></line>"
		@"<line><item>desk</item><quantity>1</quantity><price>40.00</price><amount>40</amount></line></lines>";
	NSDictionary *refusals = @{
		@"<order><orderNumber>SO-1</orderNumber><customer>Ann</customer><lines/></order>": @"an order needs a line",
		@"<order><orderNumber>SO-1</orderNumber><customer/><lines/></order>": @"an order needs its customer",
		@"<order><orderNumber>SO-1</orderNumber><customer>Ann</customer><lines><line><item>lamp</item>"
			@"<quantity>0</quantity><price>40</price></line></lines></order>":
			@"line 1: the quantity is a whole number, at least 1",
		@"<order><orderNumber>SO-1</orderNumber><customer>Ann</customer><lines><line><item>lamp</item>"
			@"<quantity>1</quantity><price>cheap</price></line></lines></order>":
			@"line 1: the price is a number, not below 0" };
	for (NSString *refused in refusals) {
		XCTAssertNil([engine.formService submitStartFormForKey:@"order-fulfilment" businessKey:nil
		                                              instance:[self XML:refused] error:&error]);
		XCTAssertEqualObjects([error localizedDescription], [refusals objectForKey:refused]);
	}
	NSString *entered = [NSString stringWithFormat:@"<order><orderNumber>SO-1</orderNumber><customer>Ann</customer>"
		@"<express>true</express>%@<total>999</total></order>", lines];
	WFProcessInstance *started = [engine.formService submitStartFormForKey:@"order-fulfilment" businessKey:nil
	                                                              instance:[self XML:entered] error:&error];
	XCTAssertNotNil(started, @"%@", error);
	XCTAssertEqualObjects(started.businessKey, @"SO-1", @"the order number");
	NSString *express = started.processInstanceId;
	XCTAssertTrue([engine waitUntilSettled:express timeout:10.0]);
	NSDictionary *begun = [self variables:express engine:engine];
	XCTAssertEqual([[begun objectForKey:@"total"] doubleValue], 120.0, @"worked out again, not the form's");
	XCTAssertEqualObjects([[begun objectForKey:@"lines"] valueForKey:@"item"], (@[ @"lamp", @"desk" ]));
	XCTAssertEqualObjects([begun objectForKey:@"express"], @YES);

	WFWorkItem *pack = [self task:@"pack" of:express engine:engine];
	XCTAssertEqual(pack.priority, (NSInteger)80, @"express orders first");
	XCTAssertEqualObjects(pack.candidateGroups, @[ @"warehouse" ]);
	NSTimeInterval due = [pack.dueDate timeIntervalSinceNow];
	XCTAssertTrue(due > 3500 && due <= 7200, @"due in two hours, as the workload listener's field says: %f", due);
	XCTAssertTrue([[handler topicsFor:express] containsObject:@"payment"], @"charged while it is packed");
	[self complete:@"pack" of:express engine:engine variables:nil];
	XCTAssertTrue([self ended:express engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:express], (@[ @"check-stock", @"payment", @"shipping-cost", @"courier" ]));
	NSDictionary *done = [self variables:express engine:engine];
	XCTAssertEqualObjects([done objectForKey:@"outbox"], (@[ @{ @"to": @"Ann", @"template": @"order-shipped",
	                                                           @"subject": @"Order SO-1 is on its way" } ]));
	XCTAssertEqualObjects([done objectForKey:@"auditTrail"], (@[ @"start process", @"end process: order closed" ]));
	/* The packing task's list and map inputs, read back through its output. */
	XCTAssertEqualObjects([done objectForKey:@"packingSlip"], (@{ @"customer": @"Ann", @"items": @3, @"tape": @"red tape" }));

	NSString *standard = [self startExample:@"order-fulfilment" businessKey:@"SO-2"
	                              variables:@{ @"orderNumber": @"SO-2", @"customer": @"Bob", @"total": @30,
	                                           @"express": @NO,
	                                           @"lines": @[ @{ @"item": @"rug", @"quantity": @1, @"price": @30 } ] }
	                                 engine:engine];
	WFWorkItem *slow = [self task:@"pack" of:standard engine:engine];
	XCTAssertEqual(slow.priority, (NSInteger)50);
	XCTAssertTrue([slow.dueDate timeIntervalSinceNow] > 23 * 3600, @"due in a day");
	[self complete:@"pack" of:standard engine:engine variables:nil];
	XCTAssertEqualObjects([[handler topicsFor:standard] lastObject], @"post");

	[handler.results setObject:@{ @"inStock": @NO } forKey:@"check-stock"];
	NSString *missing = [self startExample:@"order-fulfilment" businessKey:@"SO-3"
	                             variables:@{ @"orderNumber": @"SO-3", @"customer": @"Cy", @"total": @45,
	                                          @"express": @NO } engine:engine];
	XCTAssertNotNil([self task:@"backOrder" of:missing engine:engine]);
	XCTAssertNil([self task:@"pack" of:missing engine:engine]);
	[self complete:@"backOrder" of:missing engine:engine variables:nil];
	XCTAssertTrue([[self passed:missing engine:engine] containsObject:@"backOrdered"]);
}

/* The score is added up from what is known of the applicant, the risk
 * follows from it and the share of income asked for, and the limit from
 * income and debts: a low risk within it is paid, a medium one
 * underwritten (by a senior underwriter when it is large), the rest
 * declined by mail. */
- (void)testLoanApplication
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	[self deployExample:@"loan-application" engine:engine];
	NSDictionary *(^applying)(NSNumber *, NSNumber *, NSNumber *, NSString *, NSNumber *) =
		^NSDictionary *(NSNumber *amount, NSNumber *income, NSNumber *debts, NSString *since, NSNumber *defaulted) {
			return @{ @"applicationId": @"A-1", @"applicant": @"Dee", @"amount": amount, @"income": income,
			          @"debts": debts, @"employedSince": since, @"hasDefaulted": defaulted };
		};

	/* Long employed, no debts: 30 + 40 + 20 points; the limit 40% of income. */
	NSString *low = [self startExample:@"loan-application" businessKey:@"L-1"
	                         variables:applying(@4000, @60000, @0, @"2015-03-01", @NO) engine:engine];
	NSDictionary *variables = [self variables:low engine:engine];
	XCTAssertEqualObjects([variables objectForKey:@"risk"], @"low");
	XCTAssertEqual([[variables objectForKey:@"maxLoan"] doubleValue], 24000.0);
	XCTAssertTrue([self ended:low engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:low], @[ @"pay-out" ]);
	XCTAssertEqualObjects([variables objectForKey:@"auditTrail"], @[ @"end payOut: paid 4000" ]);

	/* As safe, but over the limit: declined. */
	NSString *over = [self startExample:@"loan-application" businessKey:@"L-2"
	                          variables:applying(@30000, @60000, @0, @"2015-03-01", @NO) engine:engine];
	XCTAssertEqualObjects([[self variables:over engine:engine] objectForKey:@"outbox"],
	                      (@[ @{ @"to": @"Dee", @"template": @"loan-declined", @"subject": @"Your application A-1" } ]));
	XCTAssertEqualObjects([handler topicsFor:over], @[]);

	/* A few years employed, some debts: 15 + 20 + 20, medium. */
	NSString *medium = [self startExample:@"loan-application" businessKey:@"L-3"
	                            variables:applying(@20000, @60000, @15000, @"2023-06-01", @NO) engine:engine];
	WFWorkItem *underwrite = [self task:@"underwrite" of:medium engine:engine];
	XCTAssertNotNil(underwrite);
	XCTAssertNil(underwrite.assignee, @"left to the underwriters");
	XCTAssertTrue([underwrite.dueDate timeIntervalSinceNow] > 47 * 3600, @"due in two days");
	/* On the underwriter's form: the task's fields in it, the decision taken
	 * back, what is read-only left as it was. */
	WFFormData *form = [self form:underwrite.taskId deployedAs:@"Share of income" engine:engine];
	XCTAssertEqualObjects([self field:@"applicant" of:form.instance], @"Dee");
	XCTAssertEqualObjects([self field:@"debts" of:form.instance], @"15000");
	XCTAssertEqualObjects([self field:@"risk" of:form.instance], @"medium");
	XCTAssertEqualObjects([self field:@"employedSince" of:form.instance], @"2023-06-01T00:00:00Z");
	NSError *error = nil;
	NSXMLDocument *answer = [form.instance copy];
	[self setField:@"approved" of:answer to:@"true"];
	[self setField:@"amount" of:answer to:@"1"];
	XCTAssertTrue([engine.formService submitTaskForm:underwrite.taskId instance:answer error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:medium timeout:10.0]);
	XCTAssertEqualObjects([handler topicsFor:medium], @[ @"pay-out" ]);
	XCTAssertEqualObjects([[self variables:medium engine:engine] objectForKey:@"amount"], @20000, @"read-only");

	NSString *large = [self startExample:@"loan-application" businessKey:@"L-4"
	                           variables:applying(@60000, @100000, @30000, @"2023-06-01", @NO) engine:engine];
	WFWorkItem *senior = [self task:@"underwrite" of:large engine:engine];
	XCTAssertEqualObjects(senior.assignee, @"senior-underwriter");
	/* Declined, with the reason the form asks for. */
	NSXMLDocument *declined = [[self form:senior.taskId deployedAs:@"Share of income" engine:engine].instance copy];
	[self setField:@"approved" of:declined to:@"false"];
	[self setField:@"comment" of:declined to:@"debts too high for now"];
	XCTAssertTrue([engine.formService submitTaskForm:senior.taskId instance:declined error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:large timeout:10.0]);
	XCTAssertTrue([[self passed:large engine:engine] containsObject:@"declined"]);
	XCTAssertEqualObjects([[self variables:large engine:engine] objectForKey:@"comment"], @"debts too high for now");

	/* A default outweighs everything. */
	NSString *defaulted = [self startExample:@"loan-application" businessKey:@"L-5"
	                               variables:applying(@1000, @90000, @0, @"2010-01-01", @YES) engine:engine];
	XCTAssertEqualObjects([[self variables:defaulted engine:engine] objectForKey:@"risk"], @"high");
	XCTAssertTrue([[self passed:defaulted engine:engine] containsObject:@"declined"]);
	XCTAssertEqual([[[self variables:defaulted engine:engine] objectForKey:@"outbox"] count], (NSUInteger)1);
}

/* Paid: booked. Declined: the hotel and the flight are cancelled again,
 * newest first. */
- (void)testTravelBooking
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	[self deployExample:@"travel-booking" engine:engine];

	NSString *paid = [self startExample:@"travel-booking" businessKey:@"T-1" variables:nil engine:engine];
	XCTAssertTrue([self ended:paid engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:paid], (@[ @"book-flight", @"book-hotel", @"charge-card" ]));

	[handler.bpmnErrors setObject:@"card-declined" forKey:@"charge-card"];
	NSString *declined = [self startExample:@"travel-booking" businessKey:@"T-2" variables:nil engine:engine];
	XCTAssertTrue([self ended:declined engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:declined],
	                      (@[ @"book-flight", @"book-hotel", @"charge-card", @"cancel-hotel", @"cancel-flight" ]));
	XCTAssertTrue([[self passed:declined engine:engine] containsObject:@"failed"]);
}

/* Reminded after a week, documents in: the checks a large customer abroad
 * needs run together, and the account manager is chased after two days. */
- (void)testCustomerOnboarding
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	engine.jobExecutorActive = NO;
	[self deployExample:@"customer-onboarding" engine:engine];
	NSString *pid = [self startExample:@"customer-onboarding" businessKey:@"C-1"
	                         variables:@{ @"expectedVolume": @250000, @"country": @"US" } engine:engine];
	XCTAssertEqualObjects([handler topicsFor:pid], @[ @"mail" ]);
	[self fire:@"aWeek" of:pid engine:engine];
	XCTAssertEqualObjects([handler topicsFor:pid], (@[ @"mail", @"mail" ]), @"reminded");
	XCTAssertNotNil([self job:@"aWeek" of:pid engine:engine], @"and waiting again");

	NSError *error = nil;
	XCTAssertTrue([engine.runtimeService correlateMessage:@"documents-received" businessKey:@"C-1"
	                                      correlationKeys:nil variables:nil error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:pid timeout:10.0]);
	NSArray *topics = [handler topicsFor:pid];
	XCTAssertTrue([topics containsObject:@"credit-check"] && [topics containsObject:@"sanctions"], @"%@", topics);
	XCTAssertNotNil([self task:@"verify" of:pid engine:engine]);
	[self fire:@"slow" of:pid engine:engine];
	XCTAssertEqualObjects([[handler topicsFor:pid] lastObject], @"mail", @"chased");
	XCTAssertNotNil([self task:@"verify" of:pid engine:engine], @"and still to verify");
	[self complete:@"verify" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

/* A claim with a line over 500 has its receipts checked first; two
 * approvals of three are enough -- the third review is withdrawn -- and
 * each reviewer is mailed the outcome in turn. */
- (void)testExpenseReview
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	[self deployExample:@"expense-review" engine:engine];
	NSArray *lines = @[ @{ @"item": @"taxi", @"amount": @40 }, @{ @"item": @"hotel", @"amount": @620 } ];
	NSString *pid = [self startExample:@"expense-review" businessKey:@"E-1"
	                         variables:@{ @"reviewers": @[ @"ann", @"bob", @"cy" ], @"approvals": @0, @"lines": lines }
	                            engine:engine];
	XCTAssertEqualObjects([[self task:@"checkReceipts" of:pid engine:engine] candidateGroups], @[ @"finance" ]);
	[self complete:@"checkReceipts" of:pid engine:engine variables:nil];
	NSArray *reviews = [engine.taskService tasksForProcessInstance:pid];
	XCTAssertEqualObjects([[reviews valueForKey:@"assignee"] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @"ann", @"bob", @"cy" ]));
	/* On the review form: the claim's lines, the total and the largest. */
	WFWorkItem *annsReview = [[engine.taskService tasksForAssignee:@"ann"] firstObject];
	WFFormData *form = [self form:annsReview.taskId deployedAs:@"Your review" engine:engine];
	NSArray *shown = [[[[form.instance rootElement] elementsForName:@"lines"] firstObject] elementsForName:@"line"];
	XCTAssertEqualObjects([shown valueForKey:@"stringValue"], (@[ @"taxi40", @"hotel620" ]));
	XCTAssertEqualObjects([self field:@"total" of:form.instance], @"660");
	XCTAssertEqualObjects([self field:@"largest" of:form.instance], @"620");
	XCTAssertEqualObjects([self field:@"reviewer" of:form.instance], @"ann");
	NSError *error = nil;
	NSXMLDocument *answer = [form.instance copy];
	XCTAssertFalse([engine.formService submitTaskForm:annsReview.taskId instance:answer error:&error]);
	XCTAssertEqualObjects([error localizedDescription], @"approve or reject the claim");
	[self setField:@"decision" of:answer to:@"reject"];
	XCTAssertFalse([engine.formService submitTaskForm:annsReview.taskId instance:answer error:&error]);
	XCTAssertEqualObjects([error localizedDescription], @"a rejection needs a reason");
	[self setField:@"decision" of:answer to:@"approve"];
	[self setField:@"reason" of:answer to:@"hotel receipt seen"];
	XCTAssertTrue([engine.formService submitTaskForm:annsReview.taskId instance:answer error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:pid timeout:10.0]);
	WFWorkItem *bobsReview = [[engine.taskService tasksForAssignee:@"bob"] firstObject];
	NSXMLDocument *bobs = [[self form:bobsReview.taskId deployedAs:@"Your review" engine:engine].instance copy];
	[self setField:@"decision" of:bobs to:@"approve"];
	XCTAssertTrue([engine.formService submitTaskForm:bobsReview.taskId instance:bobs error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:pid timeout:10.0]);
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:pid] count], (NSUInteger)0, @"cy's review withdrawn");
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:pid], @[ @"reimburse" ]);
	XCTAssertEqualObjects([[[self variables:pid engine:engine] objectForKey:@"outbox"] valueForKey:@"to"],
	                      (@[ @"ann", @"bob", @"cy" ]), @"mailed one after another");
	XCTAssertEqualObjects([[[[self variables:pid engine:engine] objectForKey:@"outbox"] firstObject] objectForKey:@"subject"],
	                      @"Claim approved");
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"notes"], @[ @"ann: hotel receipt seen" ]);

	/* Every line small: straight to the reviewers. */
	NSString *small = [self startExample:@"expense-review" businessKey:@"E-2"
	                           variables:@{ @"reviewers": @[ @"dan" ], @"approvals": @0,
	                                        @"lines": @[ @{ @"item": @"lunch", @"amount": @25 } ] } engine:engine];
	XCTAssertNil([self task:@"checkReceipts" of:small engine:engine]);
	XCTAssertEqualObjects([[[engine.taskService tasksForProcessInstance:small] firstObject] assignee], @"dan");

	/* Claimed on its start form: the lines and the reviewers, as lists. */
	WFFormData *claimForm = [engine.formService startFormDataForKey:@"expense-review" error:&error];
	XCTAssertNotNil(claimForm, @"%@", error);
	XCTAssertTrue([[claimForm.document XMLString] rangeOfString:@"Add reviewer"].location != NSNotFound, @"claim.xhtml");
	NSString *noReviewer = @"<claim><reference>E-3</reference><lines><line><item>taxi</item><amount>30</amount></line>"
		@"</lines><reviewers><reviewer/></reviewers></claim>";
	XCTAssertNil([engine.formService submitStartFormForKey:@"expense-review" businessKey:nil
	                                              instance:[self XML:noReviewer] error:&error]);
	XCTAssertEqualObjects([error localizedDescription], @"a claim needs a reviewer");
	NSString *claim = @"<claim><reference>E-3</reference><lines><line><item>taxi</item><amount>30</amount></line>"
		@"<line><item>train</item><amount>45.50</amount></line></lines>"
		@"<reviewers><reviewer>eve</reviewer><reviewer> fay </reviewer><reviewer>eve</reviewer></reviewers></claim>";
	WFProcessInstance *claimed = [engine.formService submitStartFormForKey:@"expense-review" businessKey:nil
	                                                              instance:[self XML:claim] error:&error];
	XCTAssertNotNil(claimed, @"%@", error);
	XCTAssertEqualObjects(claimed.businessKey, @"E-3", @"the reference");
	NSArray *reviewers = [[engine.taskService tasksForProcessInstance:claimed.processInstanceId] valueForKey:@"assignee"];
	XCTAssertEqualObjects([reviewers sortedArrayUsingSelector:@selector(compare:)], (@[ @"eve", @"fay" ]),
	                      @"each reviewer once");
}

/* A ticket the customer writes about, which needs a product fix: the bug
 * is filed while support works around it. One left for eight hours goes
 * to a supervisor; one withdrawn ends there. */
- (void)testSupportTicket
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	engine.jobExecutorActive = NO;
	[self deployExample:@"support-ticket" engine:engine];
	NSError *error = nil;

	NSString *bug = [self startExample:@"support-ticket" businessKey:@"T-1" variables:@{ @"priority": @"urgent" }
	                            engine:engine];
	NSTimeInterval due = [[self task:@"diagnose" of:bug engine:engine].dueDate timeIntervalSinceNow];
	XCTAssertTrue(due > 3000 && due <= 3600, @"an urgent ticket diagnosed within the hour: %f", due);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"customer-replied" businessKey:@"T-1"
	                                      correlationKeys:nil variables:nil error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:bug timeout:10.0]);
	XCTAssertNotNil([self task:@"readReply" of:bug engine:engine]);
	[self complete:@"diagnose" of:bug engine:engine variables:@{ @"bug": @YES }];
	XCTAssertEqualObjects([handler topicsFor:bug], @[ @"file-bug" ]);
	[self complete:@"workaround" of:bug engine:engine variables:nil];
	XCTAssertFalse([self ended:bug engine:engine], @"the reply is still to read");
	[self complete:@"readReply" of:bug engine:engine variables:nil];
	XCTAssertTrue([self ended:bug engine:engine]);
	XCTAssertEqualObjects([[self variables:bug engine:engine] objectForKey:@"auditTrail"],
	                      (@[ @"start resolve", @"end resolve" ]));

	NSString *late = [self startExample:@"support-ticket" businessKey:@"T-2" variables:nil engine:engine];
	[self fire:@"sla" of:late engine:engine];
	XCTAssertNil([self task:@"diagnose" of:late engine:engine]);
	[self complete:@"takeOver" of:late engine:engine variables:nil];
	XCTAssertTrue([self ended:late engine:engine]);

	NSString *withdrawn = [self startExample:@"support-ticket" businessKey:@"T-3" variables:nil engine:engine];
	XCTAssertTrue([engine.runtimeService correlateMessage:@"ticket-withdrawn" businessKey:@"T-3"
	                                      correlationKeys:nil variables:nil error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:withdrawn timeout:10.0]);
	XCTAssertTrue([self ended:withdrawn engine:engine]);
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:withdrawn] count], (NSUInteger)0);
}

/* The shipment calls Pack and ship with its items and business key, and
 * has the tracking number back; printing the label waits for its job. */
- (void)testShipping
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	[handler.results setObject:@{ @"trackingNumber": @"TRK-1" } forKey:@"carrier-label"];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	engine.jobExecutorActive = NO;
	[self deployExample:@"shipping" engine:engine];
	NSString *pid = [self startExample:@"shipment" businessKey:@"SO-9"
	                         variables:@{ @"items": @[ @"lamp", @"desk", @"chair" ] } engine:engine];
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"parcels"], @3);
	WFProcessInstance *called = [[engine.runtimeService subProcessInstancesOf:pid error:NULL] firstObject];
	XCTAssertNotNil(called);
	XCTAssertEqualObjects(called.businessKey, @"SO-9");
	[self complete:@"pack" of:called.processInstanceId engine:engine variables:nil];
	XCTAssertEqualObjects([handler topicsFor:called.processInstanceId], @[], @"the label waits for its job");
	[self runJobsOf:called.processInstanceId engine:engine];
	XCTAssertTrue([engine waitUntilSettled:pid timeout:10.0]);
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([[self variables:pid engine:engine] objectForKey:@"tracking"], @"TRK-1");
	XCTAssertEqualObjects([handler topicsFor:pid], @[ @"mail" ]);
}

/* Stock falls below the reorder level: reordered, and booked in when the
 * delivery comes. The weekly count's signal starts the report. */
- (void)testInventory
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	engine.jobExecutorActive = NO;
	[self deployExample:@"inventory" engine:engine];
	NSError *error = nil;

	NSString *restock = [self startExample:@"restock" businessKey:@"SKU-7"
	                             variables:@{ @"stock": @12, @"reorderLevel": @5 } engine:engine];
	XCTAssertEqualObjects([self active:restock engine:engine], @[ @"low" ]);
	XCTAssertTrue([engine.runtimeService setVariables:@{ @"stock": @3 } processInstanceId:restock error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:restock timeout:10.0]);
	XCTAssertEqualObjects([handler topicsFor:restock], @[ @"reorder" ]);
	XCTAssertEqualObjects([self active:restock engine:engine], @[ @"delivered" ], @"across the link");
	XCTAssertTrue([engine.runtimeService correlateMessage:@"delivery-arrived" processInstanceId:restock
	                                            variables:nil error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:restock timeout:10.0]);
	XCTAssertTrue([self ended:restock engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:restock], (@[ @"reorder", @"book-in" ]));

	WFProcessDefinition *count = [engine.repositoryService latestDefinitionForKey:@"stock-count" error:&error];
	WFJob *weekly = [[engine.managementService jobsForDefinition:count.definitionId] firstObject];
	XCTAssertNotNil(weekly, @"the weekly timer is armed on deployment");
	XCTAssertTrue([engine.managementService executeJob:weekly.jobId error:&error], @"%@", error);
	WFWorkItem *counting = [[engine.taskService tasksForCandidateGroup:@"warehouse"] firstObject];
	XCTAssertNotNil(counting);
	XCTAssertTrue([engine.taskService completeTask:counting.taskId variables:nil error:&error], @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:counting.processInstanceId timeout:10.0]);
	XCTAssertTrue([self waitForTopic:@"stock-report" handler:handler]);
}

- (BOOL)waitForTopic:(NSString *)topic handler:(WFMapHandler *)handler
{
	for (int i = 0; i < 100; i++) {
		if ([[handler topicsFor:nil] containsObject:topic]) {
			return YES;
		}
		[NSThread sleepForTimeInterval:0.05];
	}
	return NO;
}

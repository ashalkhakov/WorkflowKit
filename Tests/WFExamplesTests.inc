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

/* The example's directory, deployed under its name. */
- (void)deployExample:(NSString *)name engine:(WFProcessEngine *)engine
{
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

/* In stock and express: charged and packed at once, by courier; not in
 * stock: back-ordered. */
- (void)testOrderFulfilment
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	[handler.results setObject:@{ @"inStock": @YES } forKey:@"check-stock"];
	[handler.results setObject:@{ @"shippingCost": @5 } forKey:@"shipping-cost"];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	[self deployExample:@"order-fulfilment" engine:engine];

	NSString *express = [self startExample:@"order-fulfilment" businessKey:@"SO-1"
	                             variables:@{ @"customer": @"Ann", @"total": @120, @"express": @YES } engine:engine];
	WFWorkItem *pack = [self task:@"pack" of:express engine:engine];
	XCTAssertEqual(pack.priority, (NSInteger)80, @"express orders first");
	XCTAssertEqualObjects(pack.candidateGroups, @[ @"warehouse" ]);
	XCTAssertTrue([[handler topicsFor:express] containsObject:@"payment"], @"charged while it is packed");
	[self complete:@"pack" of:express engine:engine variables:nil];
	XCTAssertTrue([self ended:express engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:express], (@[ @"check-stock", @"payment", @"shipping-cost", @"courier" ]));

	NSString *standard = [self startExample:@"order-fulfilment" businessKey:@"SO-2"
	                              variables:@{ @"customer": @"Bob", @"total": @30, @"express": @NO } engine:engine];
	XCTAssertEqual([self task:@"pack" of:standard engine:engine].priority, (NSInteger)50);
	[self complete:@"pack" of:standard engine:engine variables:nil];
	XCTAssertEqualObjects([[handler topicsFor:standard] lastObject], @"post");

	[handler.results setObject:@{ @"inStock": @NO } forKey:@"check-stock"];
	NSString *missing = [self startExample:@"order-fulfilment" businessKey:@"SO-3"
	                             variables:@{ @"customer": @"Cy", @"total": @45, @"express": @NO } engine:engine];
	XCTAssertNotNil([self task:@"backOrder" of:missing engine:engine]);
	XCTAssertNil([self task:@"pack" of:missing engine:engine]);
	[self complete:@"backOrder" of:missing engine:engine variables:nil];
	XCTAssertTrue([[self passed:missing engine:engine] containsObject:@"backOrdered"]);
}

/* The decision table scores each application: low is paid, medium is
 * underwritten, high -- or anyone who defaulted -- declined. */
- (void)testLoanApplication
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	[self deployExample:@"loan-application" engine:engine];
	NSDictionary *(^applying)(NSNumber *, NSNumber *, NSNumber *) = ^NSDictionary *(NSNumber *amount, NSNumber *income,
	                                                                                 NSNumber *defaulted) {
		return @{ @"applicant": @"Dee", @"amount": amount, @"income": income, @"hasDefaulted": defaulted };
	};

	NSString *low = [self startExample:@"loan-application" businessKey:@"L-1"
	                         variables:applying(@4000, @60000, @NO) engine:engine];
	XCTAssertEqualObjects([[self variables:low engine:engine] objectForKey:@"risk"], @"low");
	XCTAssertTrue([self ended:low engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:low], @[ @"pay-out" ]);

	NSString *medium = [self startExample:@"loan-application" businessKey:@"L-2"
	                            variables:applying(@20000, @60000, @NO) engine:engine];
	WFWorkItem *underwrite = [self task:@"underwrite" of:medium engine:engine];
	XCTAssertNotNil(underwrite);
	XCTAssertTrue([underwrite.dueDate timeIntervalSinceNow] > 47 * 3600, @"due in two days");
	[self complete:@"underwrite" of:medium engine:engine variables:@{ @"approved": @YES }];
	XCTAssertEqualObjects([handler topicsFor:medium], @[ @"pay-out" ]);

	NSString *defaulted = [self startExample:@"loan-application" businessKey:@"L-3"
	                               variables:applying(@1000, @90000, @YES) engine:engine];
	XCTAssertEqualObjects([[self variables:defaulted engine:engine] objectForKey:@"risk"], @"high");
	XCTAssertEqualObjects([handler topicsFor:defaulted], @[ @"letters" ]);
	XCTAssertTrue([[self passed:defaulted engine:engine] containsObject:@"declined"]);
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

/* Two approvals of three are enough: the third review is withdrawn, the
 * claim reimbursed, and each reviewer told in turn. */
- (void)testExpenseReview
{
	WFMapHandler *handler = [[WFMapHandler alloc] init];
	WFProcessEngine *engine = [self engineWithHandler:handler];
	[self deployExample:@"expense-review" engine:engine];
	NSString *pid = [self startExample:@"expense-review" businessKey:@"E-1"
	                         variables:@{ @"reviewers": @[ @"ann", @"bob", @"cy" ], @"approvals": @0 } engine:engine];
	NSArray *reviews = [engine.taskService tasksForProcessInstance:pid];
	XCTAssertEqualObjects([[reviews valueForKey:@"assignee"] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @"ann", @"bob", @"cy" ]));
	NSError *error = nil;
	for (NSString *reviewer in @[ @"ann", @"bob" ]) {
		WFWorkItem *review = [[engine.taskService tasksForAssignee:reviewer] firstObject];
		XCTAssertTrue([engine.taskService completeTask:review.taskId variables:@{ @"approved": @YES } error:&error],
		              @"%@", error);
		XCTAssertTrue([engine waitUntilSettled:pid timeout:10.0]);
	}
	XCTAssertEqual([[engine.taskService tasksForProcessInstance:pid] count], (NSUInteger)0, @"cy's review withdrawn");
	XCTAssertTrue([self ended:pid engine:engine]);
	XCTAssertEqualObjects([handler topicsFor:pid], (@[ @"reimburse", @"notify", @"notify", @"notify" ]));
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

	NSString *bug = [self startExample:@"support-ticket" businessKey:@"T-1" variables:nil engine:engine];
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

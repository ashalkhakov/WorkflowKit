/* Included into a class of each backend's suite: see WFTestCase.h. */

#pragma mark - Migration

/* Version 1 of "claims": start -> assess (a user task with a boundary
 * message "withdraw") -> end; the boundary -> withdrawn. */
- (WFProcessDefinition *)claimsVersion1
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"claims"];
	[[[[b addStart:@"start"] addUserTask:@"assess" name:@"Assess" assignee:@"ann"] addEnd:@"end"]
		addBoundaryMessage:@"withdraw" onTask:@"assess" message:@"withdraw" interrupting:YES];
	[[b addEnd:@"withdrawn"] connect:@"start" to:@"assess"];
	[[b connect:@"assess" to:@"end"] connect:@"withdraw" to:@"withdrawn"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

/* Version 2: assess is now "review", followed by a new task "pay"; the
 * withdraw message is gone, and a boundary timer "late" is new. */
- (WFProcessDefinition *)claimsVersion2
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"claims"];
	[[[[[b addStart:@"start"] addUserTask:@"review" name:@"Review" assignee:@"ann"]
		addUserTask:@"pay" name:@"Pay" assignee:@"bob"] addEnd:@"end"]
		addBoundaryTimer:@"late" onTask:@"review" duration:3600 interrupting:NO];
	[[b addUserTask:@"chase" name:@"Chase" assignee:@"ann"] addEnd:@"chased"];
	[[[b connect:@"start" to:@"review"] connect:@"review" to:@"pay"] connect:@"pay" to:@"end"];
	[[b connect:@"late" to:@"chase"] connect:@"chase" to:@"chased"];
	WFProcessDefinition *definition = [b build:&error];
	XCTAssertNotNil(definition, @"%@", error);
	return definition;
}

- (NSString *)definitionIdOf:(NSString *)key engine:(WFProcessEngine *)engine
{
	return [[engine.repositoryService latestDefinitionForKey:key error:NULL] definitionId];
}

- (void)testMigratesAnInstanceToAnotherVersion
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	engine.jobExecutorActive = NO;
	NSString *first = [self run:[self claimsVersion1] engine:engine variables:@{ @"amount": @10 }];
	NSString *second = [self run:[self claimsVersion1] engine:engine variables:nil];
	NSString *v1 = [self definitionIdOf:@"claims" engine:engine];
	[self deploy:[self claimsVersion2] engine:engine];
	NSString *v2 = [self definitionIdOf:@"claims" engine:engine];
	XCTAssertNotEqualObjects(v1, v2);

	WFMigrationPlan *plan = [[WFMigrationPlan planFromDefinition:v1 toDefinition:v2]
		mapActivity:@"assess" toActivity:@"review"];
	XCTAssertTrue([engine.runtimeService validateMigrationPlan:plan error:&error], @"%@", error);
	XCTAssertTrue([engine.runtimeService migrateProcessInstances:(@[ first, second ]) plan:plan error:&error], @"%@", error);

	WFProcessInstance *instance = [engine.runtimeService processInstanceWithId:first error:NULL];
	XCTAssertEqualObjects(instance.definitionId, v2);
	XCTAssertEqualObjects([self active:first engine:engine], @[ @"review" ]);
	XCTAssertEqualObjects([self task:@"review" of:first engine:engine].taskDefinitionKey, @"review");
	XCTAssertEqualObjects([[self variables:first engine:engine] objectForKey:@"amount"], @10);
	/* The withdraw message was not mapped: it is no longer waited for. The
	 * new timer is. */
	XCTAssertFalse([engine.runtimeService correlateMessage:@"withdraw" processInstanceId:first
	                                             variables:nil error:&error]);
	WFJob *late = [[engine.managementService jobsForProcessInstance:first] lastObject];
	XCTAssertEqualObjects(late.activityId, @"late");
	XCTAssertEqualObjects([[engine.historyService historicProcessInstanceWithId:first] definitionId], v2);

	/* It runs on version 2 from here. */
	[self complete:@"review" of:first engine:engine variables:nil];
	XCTAssertEqualObjects([self active:first engine:engine], @[ @"pay" ]);
	XCTAssertEqualObjects([self active:second engine:engine], @[ @"review" ]);
}

- (void)testMapEqualActivities
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self claimsVersion1] engine:engine variables:nil];
	NSString *v1 = [self definitionIdOf:@"claims" engine:engine];
	/* Version 3: assess keeps its id and boundary, and pay follows it. */
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"claims"];
	[[[[[b addStart:@"start"] addUserTask:@"assess" name:@"Assess" assignee:@"ann"]
		addUserTask:@"pay" name:@"Pay" assignee:@"bob"] addEnd:@"end"]
		addBoundaryMessage:@"withdraw" onTask:@"assess" message:@"retract" interrupting:YES];
	[[b addEnd:@"withdrawn"] connect:@"start" to:@"assess"];
	[[[b connect:@"assess" to:@"pay"] connect:@"pay" to:@"end"] connect:@"withdraw" to:@"withdrawn"];
	[self deploy:[b build:&error] engine:engine];
	NSString *v3 = [self definitionIdOf:@"claims" engine:engine];
	WFMigrationPlan *plan = [[WFMigrationPlan planFromDefinition:v1 toDefinition:v3] mapEqualActivities];
	XCTAssertTrue([engine.runtimeService migrateProcessInstances:@[ pid ] plan:plan error:&error], @"%@", error);
	/* The boundary keeps its trigger, the old message. */
	XCTAssertFalse([engine.runtimeService correlateMessage:@"retract" processInstanceId:pid variables:nil error:&error]);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"withdraw" processInstanceId:pid variables:nil error:&error],
		@"%@", error);
	XCTAssertTrue([self ended:pid engine:engine]);

	/* Updating the trigger makes it wait for the new one: an instance of
	 * version 1 again (deployed anew as version 4) onto version 3. */
	NSString *again = [self run:[self claimsVersion1] engine:engine variables:nil];
	NSString *v4 = [self definitionIdOf:@"claims" engine:engine];
	WFMigrationPlan *updating = [[[WFMigrationPlan planFromDefinition:v4 toDefinition:v3] mapEqualActivities]
		mapActivity:@"withdraw" toActivity:@"withdraw" updateEventTrigger:YES];
	XCTAssertTrue([engine.runtimeService migrateProcessInstances:@[ again ] plan:updating error:&error], @"%@", error);
	XCTAssertFalse([engine.runtimeService correlateMessage:@"withdraw" processInstanceId:again variables:nil error:&error]);
	XCTAssertTrue([engine.runtimeService correlateMessage:@"retract" processInstanceId:again variables:nil error:&error],
		@"%@", error);
}

- (void)testPlansAndInstancesThatCannotBeMigrated
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	NSString *pid = [self run:[self claimsVersion1] engine:engine variables:nil];
	NSString *v1 = [self definitionIdOf:@"claims" engine:engine];
	[self deploy:[self claimsVersion2] engine:engine];
	NSString *v2 = [self definitionIdOf:@"claims" engine:engine];

	NSDictionary *plans = @{
		@"not the same kind": [[WFMigrationPlan planFromDefinition:v1 toDefinition:v2]
			mapActivity:@"assess" toActivity:@"end"],
		@"not in the target": [[WFMigrationPlan planFromDefinition:v1 toDefinition:v2]
			mapActivity:@"assess" toActivity:@"nothing"],
	};
	for (NSString *reason in plans) {
		XCTAssertFalse([engine.runtimeService validateMigrationPlan:[plans objectForKey:reason] error:&error]);
		XCTAssertTrue([[error localizedDescription] rangeOfString:reason].location != NSNotFound,
			@"%@: %@", reason, error);
	}
	/* assess is not mapped at all. */
	WFMigrationPlan *partial = [[WFMigrationPlan planFromDefinition:v1 toDefinition:v2] mapActivity:@"start"
		toActivity:@"start"];
	XCTAssertFalse([engine.runtimeService migrateProcessInstances:@[ pid ] plan:partial error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"assess is not mapped"].location != NSNotFound,
		@"%@", error);
	/* Mapped to a task that is a scope of its own in one and not the other. */
	WFMigrationPlan *toPay = [[WFMigrationPlan planFromDefinition:v1 toDefinition:v2] mapActivity:@"assess"
		toActivity:@"pay"];
	XCTAssertFalse([engine.runtimeService migrateProcessInstances:@[ pid ] plan:toPay error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"boundary events"].location != NSNotFound, @"%@", error);
	XCTAssertEqualObjects([[engine.runtimeService processInstanceWithId:pid error:NULL] definitionId], v1);
}

- (void)testMigratesInsideASubprocess
{
	NSError *error = nil;
	WFProcessEngine *engine = [self engineWithHandler:nil];
	WFProcessDefinition *(^version)(NSString *, NSString *) = ^WFProcessDefinition *(NSString *outer, NSString *task) {
		NSError *buildError = nil;
		WFDefinitionBuilder *inner = [WFDefinitionBuilder process:@"inner"];
		[[[inner addStart:@"s"] addUserTask:task name:task assignee:@"ann"] addEnd:@"e"];
		[[inner connect:@"s" to:task] connect:task to:@"e"];
		WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"nested"];
		[[[b addStart:@"start"] addSubProcess:outer name:outer inner:[inner build:&buildError]] addEnd:@"end"];
		[[b connect:@"start" to:outer] connect:outer to:@"end"];
		return [b build:&buildError];
	};
	NSString *pid = [self run:version(@"stage", @"work") engine:engine variables:nil];
	NSString *v1 = [self definitionIdOf:@"nested" engine:engine];
	[self deploy:version(@"phase", @"job") engine:engine];
	NSString *v2 = [self definitionIdOf:@"nested" engine:engine];
	WFMigrationPlan *wrong = [[WFMigrationPlan planFromDefinition:v1 toDefinition:v2] mapActivity:@"work"
		toActivity:@"job"];
	XCTAssertFalse([engine.runtimeService validateMigrationPlan:wrong error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"subprocess around"].location != NSNotFound, @"%@", error);
	WFMigrationPlan *plan = [[[WFMigrationPlan planFromDefinition:v1 toDefinition:v2]
		mapActivity:@"stage" toActivity:@"phase"] mapActivity:@"work" toActivity:@"job"];
	XCTAssertTrue([engine.runtimeService migrateProcessInstances:@[ pid ] plan:plan error:&error], @"%@", error);
	WFActivityInstance *tree = [engine.runtimeService activityInstanceTreeOfProcessInstance:pid error:NULL];
	XCTAssertEqualObjects([[[[tree activityInstancesForActivity:@"phase"] firstObject] childActivityInstances]
		valueForKey:@"activityId"], @[ @"job" ]);
	[self complete:@"job" of:pid engine:engine variables:nil];
	XCTAssertTrue([self ended:pid engine:engine]);
}

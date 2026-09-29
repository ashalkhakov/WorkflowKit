#import "UDWorkflowTestCase.h"

@implementation UDMapHandler
- (instancetype)init
{
	self = [super init];
	if (self) {
		_results = [NSMutableDictionary dictionary];
		_bpmnErrors = [NSMutableDictionary dictionary];
		_failures = [NSMutableDictionary dictionary];
		_taskIds = [NSMutableArray array];
	}
	return self;
}
- (void)performInvocation:(UDServiceInvocation *)invocation
{
	NSInteger failuresLeft = 0;
	@synchronized (self) {
		[self.taskIds addObject:invocation.externalTaskId];
		failuresLeft = [[self.failures objectForKey:invocation.topic] integerValue];
		if (failuresLeft > 0) {
			[self.failures setObject:[NSNumber numberWithInteger:failuresLeft - 1]
			                  forKey:invocation.topic];
		}
	}
	if (self.drops) {
		return;
	}
	NSString *code = [self.bpmnErrors objectForKey:invocation.topic];
	if (code != nil) {
		[invocation finishWithVariables:nil
		                          error:[NSError errorWithDomain:UDWorkflowErrorDomain
		                                                    code:UDWorkflowErrorHandler
		                                                userInfo:@{ UDWorkflowErrorRefKey: code }]];
		return;
	}
	if (failuresLeft != 0) {
		[invocation finishWithVariables:nil
		                          error:[NSError errorWithDomain:@"test"
		                                                    code:1
		                                                userInfo:@{ NSLocalizedDescriptionKey: @"down" }]];
		return;
	}
	[invocation finishWithVariables:[self.results objectForKey:invocation.topic] error:nil];
}
- (NSUInteger)calls
{
	@synchronized (self) {
		return [self.taskIds count];
	}
}
@end

@implementation UDCompletingDelegate
- (instancetype)init
{
	self = [super init];
	if (self) {
		_ended = [NSMutableArray array];
	}
	return self;
}
/* Completes every task from inside the callback. */
- (void)processEngine:(UDProcessEngine *)engine taskCreated:(UDWorkItem *)task
{
	[engine.taskService completeTask:task.taskId variables:@{ @"byDelegate": @YES } error:NULL];
}
- (void)processEngine:(UDProcessEngine *)engine processInstanceEnded:(UDProcessInstance *)instance
{
	(void)engine;
	@synchronized (self) {
		[self.ended addObject:instance.processInstanceId];
	}
}
@end

@implementation UDWorkflowTestCase

- (UDProcessEngine *)engineWithHandler:(UDMapHandler *)handler
{
	NSError *error = nil;
	UDStore *store = [UDStore inMemoryStore:&error];
	XCTAssertNotNil(store, @"%@", error);
	UDProcessEngine *engine = [[UDProcessEngine alloc] initWithStore:store];
	engine.serviceHandler = handler;
	return engine;
}

- (NSURL *)temporarySQLiteURL
{
	NSString *name = [NSString stringWithFormat:@"udworkflow-%@.sqlite",
		[[NSUUID UUID] UUIDString]];
	return [NSURL fileURLWithPath:
		[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (UDProcessEngine *)SQLiteEngineAtURL:(NSURL *)url handler:(UDMapHandler *)handler
{
	NSError *error = nil;
	UDStore *store = [UDStore SQLiteStoreAtURL:url error:&error];
	XCTAssertNotNil(store, @"%@", error);
	UDProcessEngine *engine = [[UDProcessEngine alloc] initWithStore:store];
	engine.serviceHandler = handler;
	return engine;
}

- (void)deploy:(UDProcessDefinition *)definition engine:(UDProcessEngine *)engine
{
	NSError *error = nil;
	XCTAssertNotNil(definition);
	XCTAssertNotNil([engine.repositoryService deployDefinition:definition error:&error],
		@"%@", error);
}

/* Deploys, starts, and waits for the engine's own work on the instance. */
- (NSString *)run:(UDProcessDefinition *)definition
           engine:(UDProcessEngine *)engine
        variables:(NSDictionary *)variables
{
	NSError *error = nil;
	[self deploy:definition engine:engine];
	UDProcessInstance *instance =
		[engine.runtimeService startProcessInstanceByKey:definition.processId
		                                       variables:variables
		                                           error:&error];
	XCTAssertNotNil(instance, @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:instance.processInstanceId timeout:10.0]);
	return instance.processInstanceId;
}

- (BOOL)ended:(NSString *)processInstanceId engine:(UDProcessEngine *)engine
{
	return [[engine.historyService historicProcessInstanceWithId:processInstanceId] endTime] != nil;
}

- (NSDictionary *)variables:(NSString *)processInstanceId engine:(UDProcessEngine *)engine
{
	return [engine.historyService historicVariablesForProcessInstance:processInstanceId];
}

- (NSArray *)active:(NSString *)processInstanceId engine:(UDProcessEngine *)engine
{
	return [engine.runtimeService activeActivityIdsForProcessInstance:processInstanceId error:NULL];
}

- (UDWorkItem *)task:(NSString *)key of:(NSString *)processInstanceId engine:(UDProcessEngine *)engine
{
	for (UDWorkItem *task in [engine.taskService tasksForProcessInstance:processInstanceId]) {
		if ([task.taskDefinitionKey isEqualToString:key]) {
			return task;
		}
	}
	return nil;
}

- (void)complete:(NSString *)key
              of:(NSString *)processInstanceId
          engine:(UDProcessEngine *)engine
       variables:(NSDictionary *)variables
{
	NSError *error = nil;
	UDWorkItem *task = [self task:key of:processInstanceId engine:engine];
	XCTAssertNotNil(task, @"no task %@", key);
	XCTAssertTrue([engine.taskService completeTask:task.taskId variables:variables error:&error],
		@"%@", error);
	XCTAssertTrue([engine waitUntilSettled:processInstanceId timeout:10.0]);
}

/* Timers are waits, not work: poll history until the instance ends. */
- (BOOL)waitForEnd:(NSString *)processInstanceId
            engine:(UDProcessEngine *)engine
           seconds:(NSTimeInterval)seconds
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
	while ([deadline timeIntervalSinceNow] > 0) {
		[engine waitUntilSettled:processInstanceId timeout:1.0];
		if ([self ended:processInstanceId engine:engine]) {
			return YES;
		}
		[NSThread sleepForTimeInterval:0.02];
	}
	return NO;
}

- (NSArray *)rows:(NSString *)entity engine:(UDProcessEngine *)engine
{
	__block NSArray *rows = nil;
	NSManagedObjectContext *context = [engine.store newCommandContext];
	[context performBlockAndWait:^{
		NSArray *objects = [context executeFetchRequest:
			[NSFetchRequest fetchRequestWithEntityName:entity] error:NULL];
		NSMutableArray *values = [NSMutableArray array];
		for (NSManagedObject *object in objects) {
			[values addObject:[object dictionaryWithValuesForKeys:
				[[[object entity] attributesByName] allKeys]]];
		}
		rows = values;
	}];
	return rows;
}

- (UDProcessDefinition *)approvalDefinition
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"approval"];
	[[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"]
		addServiceTask:@"book" action:@"book"] addEnd:@"end"];
	[[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"book"]
		connect:@"book" to:@"end"];
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

/* An exclusive gateway behind an async continuation, with no default: it
 * fails until "amount" is set. */
- (UDProcessDefinition *)fragileDefinition:(NSString *)cycle
{
	NSError *error = nil;
	UDDefinitionBuilder *b = [UDDefinitionBuilder process:@"fragile"];
	[[[[b addStart:@"start"] addExclusive:@"route" defaultFlow:nil] addEnd:@"big"] addEnd:@"small"];
	[b connect:@"start" to:@"route"];
	[b connect:@"route" to:@"big" key:@"amount" op:UDComparisonOpGreater value:@100];
	[b connect:@"route" to:@"small" key:@"amount" op:UDComparisonOpLessOrEqual value:@100];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"route"];
	if (cycle != nil) {
		[b setRetryTimeCycle:cycle forElement:@"route"];
	}
	UDProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

- (void)assertNode:(UDFlowNode *)a matches:(UDFlowNode *)b
{
	XCTAssertEqualObjects(NSStringFromClass([a class]), NSStringFromClass([b class]), @"%@", a.elementId);
	XCTAssertEqualObjects(a.name, b.name, @"%@", a.elementId);
	XCTAssertEqualObjects([NSSet setWithArray:a.incomingFlowIds],
		[NSSet setWithArray:b.incomingFlowIds], @"%@", a.elementId);
	XCTAssertEqualObjects([NSSet setWithArray:a.outgoingFlowIds],
		[NSSet setWithArray:b.outgoingFlowIds], @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsX, b.boundsX, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsY, b.boundsY, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsWidth, b.boundsWidth, 0.001, @"%@", a.elementId);
	XCTAssertEqualWithAccuracy(a.boundsHeight, b.boundsHeight, 0.001, @"%@", a.elementId);
	XCTAssertEqual(a.isAsyncBefore, b.isAsyncBefore, @"%@", a.elementId);
	XCTAssertEqual(a.isAsyncAfter, b.isAsyncAfter, @"%@", a.elementId);
	XCTAssertEqual(a.isExclusive, b.isExclusive, @"%@", a.elementId);
	XCTAssertEqualObjects(a.retryTimeCycle, b.retryTimeCycle, @"%@", a.elementId);
	XCTAssertEqualObjects(a.taskPriority, b.taskPriority, @"%@", a.elementId);
	if ([a isKindOfClass:[UDEvent class]]) {
		UDEvent *x = (UDEvent *)a, *y = (UDEvent *)b;
		XCTAssertEqual(x.kind, y.kind, @"%@", a.elementId);
		XCTAssertEqual(x.trigger, y.trigger, @"%@", a.elementId);
		if (x.trigger == UDEventTriggerMessage) {
			XCTAssertEqualObjects(x.messageName, y.messageName, @"%@", a.elementId);
		}
		if (x.trigger == UDEventTriggerError) {
			XCTAssertEqualObjects(x.errorRef, y.errorRef, @"%@", a.elementId);
		}
		XCTAssertEqualWithAccuracy(x.timerDuration, y.timerDuration, 0.001, @"%@", a.elementId);
		XCTAssertEqualObjects(x.attachedToId, y.attachedToId, @"%@", a.elementId);
		if (x.kind == UDEventKindBoundary) {
			XCTAssertEqual(x.isInterrupting, y.isInterrupting, @"%@", a.elementId);
		}
	} else if ([a isKindOfClass:[UDTask class]]) {
		UDTask *x = (UDTask *)a, *y = (UDTask *)b;
		XCTAssertEqual(x.kind, y.kind, @"%@", a.elementId);
		XCTAssertEqualObjects(x.assignee, y.assignee, @"%@", a.elementId);
		if (x.kind != UDTaskKindUser) {
			XCTAssertEqualObjects(x.actionKey, y.actionKey, @"%@", a.elementId);
		}
	} else if ([a isKindOfClass:[UDGateway class]]) {
		XCTAssertEqual([(UDGateway *)a kind], [(UDGateway *)b kind], @"%@", a.elementId);
		XCTAssertEqualObjects([(UDGateway *)a defaultFlowId], [(UDGateway *)b defaultFlowId],
			@"%@", a.elementId);
	} else if ([a isKindOfClass:[UDSubProcess class]]) {
		[self assertDefinition:[(UDSubProcess *)a innerDefinition]
		               matches:[(UDSubProcess *)b innerDefinition]];
	}
}

- (void)assertDefinition:(UDProcessDefinition *)a matches:(UDProcessDefinition *)b
{
	XCTAssertEqualObjects(a.processId, b.processId);
	XCTAssertEqualObjects(a.name, b.name);
	XCTAssertEqualObjects(a.defaultTaskPriority, b.defaultTaskPriority);
	XCTAssertEqualObjects(a.historyTimeToLive, b.historyTimeToLive);
	XCTAssertEqualObjects([NSSet setWithArray:[a.nodes allKeys]],
		[NSSet setWithArray:[b.nodes allKeys]]);
	XCTAssertEqualObjects([NSSet setWithArray:[a.flows allKeys]],
		[NSSet setWithArray:[b.flows allKeys]]);
	for (NSString *nodeId in a.nodes) {
		UDFlowNode *other = [b nodeWithId:nodeId];
		if (other != nil) {
			[self assertNode:[a nodeWithId:nodeId] matches:other];
		}
	}
	for (NSString *flowId in a.flows) {
		UDSequenceFlow *x = [a flowWithId:flowId];
		UDSequenceFlow *y = [b flowWithId:flowId];
		XCTAssertEqualObjects(x.sourceId, y.sourceId, @"%@", flowId);
		XCTAssertEqualObjects(x.targetId, y.targetId, @"%@", flowId);
		XCTAssertEqualObjects(x.name, y.name, @"%@", flowId);
		XCTAssertEqualObjects([x.condition expressionString], [y.condition expressionString],
			@"%@", flowId);
	}
}

@end

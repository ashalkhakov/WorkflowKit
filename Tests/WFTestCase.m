#import "WFTestCase.h"

@implementation WFMapHandler
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
- (void)performInvocation:(WFServiceInvocation *)invocation
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
		                          error:[NSError errorWithDomain:WFErrorDomain
		                                                    code:WFErrorHandler
		                                                userInfo:@{ WFErrorRefKey: code }]];
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

@implementation WFCompletingDelegate
- (instancetype)init
{
	self = [super init];
	if (self) {
		_ended = [NSMutableArray array];
	}
	return self;
}
/* Completes every task from inside the callback. */
- (void)processEngine:(WFProcessEngine *)engine taskCreated:(WFWorkItem *)task
{
	[engine.taskService completeTask:task.taskId variables:@{ @"byDelegate": @YES } error:NULL];
}
- (void)processEngine:(WFProcessEngine *)engine processInstanceEnded:(WFProcessInstance *)instance
{
	(void)engine;
	@synchronized (self) {
		[self.ended addObject:instance.processInstanceId];
	}
}
@end

@implementation WFTestCase

- (WFProcessEngine *)engineWithHandler:(WFMapHandler *)handler
{
	NSError *error = nil;
	WFStore *store = [WFStore inMemoryStore:&error];
	XCTAssertNotNil(store, @"%@", error);
	WFProcessEngine *engine = [[WFProcessEngine alloc] initWithStore:store];
	engine.serviceHandler = handler;
	return engine;
}

- (NSURL *)temporarySQLiteURL
{
	NSString *name = [NSString stringWithFormat:@"workflowkit-%@.sqlite",
		[[NSUUID UUID] UUIDString]];
	return [NSURL fileURLWithPath:
		[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (WFProcessEngine *)SQLiteEngineAtURL:(NSURL *)url handler:(WFMapHandler *)handler
{
	NSError *error = nil;
	WFStore *store = [WFStore SQLiteStoreAtURL:url error:&error];
	XCTAssertNotNil(store, @"%@", error);
	WFProcessEngine *engine = [[WFProcessEngine alloc] initWithStore:store];
	engine.serviceHandler = handler;
	return engine;
}

- (void)deploy:(WFProcessDefinition *)definition engine:(WFProcessEngine *)engine
{
	NSError *error = nil;
	XCTAssertNotNil(definition);
	XCTAssertNotNil([engine.repositoryService deployDefinition:definition error:&error],
		@"%@", error);
}

/* Deploys, starts, and waits for the engine's own work on the instance. */
- (NSString *)run:(WFProcessDefinition *)definition
           engine:(WFProcessEngine *)engine
        variables:(NSDictionary *)variables
{
	NSError *error = nil;
	[self deploy:definition engine:engine];
	WFProcessInstance *instance =
		[engine.runtimeService startProcessInstanceByKey:definition.processId
		                                       variables:variables
		                                           error:&error];
	XCTAssertNotNil(instance, @"%@", error);
	XCTAssertTrue([engine waitUntilSettled:instance.processInstanceId timeout:10.0]);
	return instance.processInstanceId;
}

- (BOOL)ended:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	return [[engine.historyService historicProcessInstanceWithId:processInstanceId] endTime] != nil;
}

- (NSDictionary *)variables:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	return [engine.historyService historicVariablesForProcessInstance:processInstanceId];
}

- (NSArray *)active:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	return [engine.runtimeService activeActivityIdsForProcessInstance:processInstanceId error:NULL];
}

- (WFWorkItem *)task:(NSString *)key of:(NSString *)processInstanceId engine:(WFProcessEngine *)engine
{
	for (WFWorkItem *task in [engine.taskService tasksForProcessInstance:processInstanceId]) {
		if ([task.taskDefinitionKey isEqualToString:key]) {
			return task;
		}
	}
	return nil;
}

- (void)complete:(NSString *)key
              of:(NSString *)processInstanceId
          engine:(WFProcessEngine *)engine
       variables:(NSDictionary *)variables
{
	NSError *error = nil;
	WFWorkItem *task = [self task:key of:processInstanceId engine:engine];
	XCTAssertNotNil(task, @"no task %@", key);
	XCTAssertTrue([engine.taskService completeTask:task.taskId variables:variables error:&error],
		@"%@", error);
	XCTAssertTrue([engine waitUntilSettled:processInstanceId timeout:10.0]);
}

/* Timers are waits, not work: poll history until the instance ends. */
- (BOOL)waitForEnd:(NSString *)processInstanceId
            engine:(WFProcessEngine *)engine
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

- (BOOL)waitForActive:(NSString *)activityId
                   in:(NSString *)processInstanceId
               engine:(WFProcessEngine *)engine
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
	while ([deadline timeIntervalSinceNow] > 0) {
		if ([[self active:processInstanceId engine:engine] containsObject:activityId]) {
			return YES;
		}
		[NSThread sleepForTimeInterval:0.02];
	}
	return NO;
}

- (NSArray *)rows:(NSString *)entity engine:(WFProcessEngine *)engine
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

- (WFProcessDefinition *)approvalDefinition
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"approval"];
	[[[[b addStart:@"start"] addUserTask:@"approve" name:@"Approve" assignee:@"boss"]
		addServiceTask:@"book" action:@"book"] addEnd:@"end"];
	[[[b connect:@"start" to:@"approve"] connect:@"approve" to:@"book"]
		connect:@"book" to:@"end"];
	WFProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

/* An exclusive gateway behind an async continuation, with no default: it
 * fails until "amount" is set. */
- (WFProcessDefinition *)fragileDefinition:(NSString *)cycle
{
	NSError *error = nil;
	WFDefinitionBuilder *b = [WFDefinitionBuilder process:@"fragile"];
	[[[[b addStart:@"start"] addExclusive:@"route" defaultFlow:nil] addEnd:@"big"] addEnd:@"small"];
	[b connect:@"start" to:@"route"];
	[b connect:@"route" to:@"big" when:@"amount > 100"];
	[b connect:@"route" to:@"small" when:@"amount <= 100"];
	[b setAsyncBefore:YES asyncAfter:NO exclusive:YES forElement:@"route"];
	if (cycle != nil) {
		[b setRetryTimeCycle:cycle forElement:@"route"];
	}
	WFProcessDefinition *def = [b build:&error];
	XCTAssertNotNil(def, @"%@", error);
	return def;
}

static NSArray *
WFMappingStrings(NSArray<WFVariableMapping *> *mappings)
{
	NSMutableArray *strings = [NSMutableArray array];
	for (WFVariableMapping *mapping in mappings) {
		[strings addObject:mapping.isAllVariables ? @"all"
			: mapping.isBusinessKey ? @"businessKey"
			: [NSString stringWithFormat:@"%@->%@", mapping.source, mapping.target]];
	}
	return strings;
}

- (void)assertNode:(WFFlowNode *)a matches:(WFFlowNode *)b
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
	XCTAssertEqual(a.isForCompensation, b.isForCompensation, @"%@", a.elementId);
	XCTAssertEqual(a.multiInstance == nil, b.multiInstance == nil, @"%@", a.elementId);
	if (a.multiInstance != nil) {
		WFMultiInstance *x = a.multiInstance, *y = b.multiInstance;
		XCTAssertEqual(x.isSequential, y.isSequential, @"%@", a.elementId);
		XCTAssertEqualObjects([x.loopCardinality expressionString], [y.loopCardinality expressionString],
			@"%@", a.elementId);
		XCTAssertEqualObjects([x.collection expressionString], [y.collection expressionString],
			@"%@", a.elementId);
		XCTAssertEqualObjects(x.elementVariable, y.elementVariable, @"%@", a.elementId);
		XCTAssertEqualObjects([x.completionCondition expressionString],
			[y.completionCondition expressionString], @"%@", a.elementId);
	}
	if ([a isKindOfClass:[WFEvent class]]) {
		WFEvent *x = (WFEvent *)a, *y = (WFEvent *)b;
		XCTAssertEqual(x.kind, y.kind, @"%@", a.elementId);
		XCTAssertEqual(x.trigger, y.trigger, @"%@", a.elementId);
		if (x.trigger == WFEventTriggerMessage) {
			XCTAssertEqualObjects(x.messageName, y.messageName, @"%@", a.elementId);
		}
		if (x.trigger == WFEventTriggerError) {
			XCTAssertEqualObjects(x.errorRef, y.errorRef, @"%@", a.elementId);
		}
		XCTAssertEqual(x.timer.kind, y.timer.kind, @"%@", a.elementId);
		XCTAssertEqualObjects(x.escalationCode, y.escalationCode, @"%@", a.elementId);
		XCTAssertEqualObjects(x.activityRef, y.activityRef, @"%@", a.elementId);
		XCTAssertEqualObjects(x.compensationHandlerId, y.compensationHandlerId, @"%@", a.elementId);
		XCTAssertEqualObjects(x.codeVariable, y.codeVariable, @"%@", a.elementId);
		XCTAssertEqualObjects([x.timer.expression expressionString], [y.timer.expression expressionString],
			@"%@", a.elementId);
		XCTAssertEqualObjects(x.attachedToId, y.attachedToId, @"%@", a.elementId);
		if (x.kind == WFEventKindBoundary || x.kind == WFEventKindStart) {
			XCTAssertEqual(x.isInterrupting, y.isInterrupting, @"%@", a.elementId);
		}
	} else if ([a isKindOfClass:[WFTask class]]) {
		WFTask *x = (WFTask *)a, *y = (WFTask *)b;
		XCTAssertEqual(x.kind, y.kind, @"%@", a.elementId);
		XCTAssertEqualObjects(x.assignee, y.assignee, @"%@", a.elementId);
		if (x.kind != WFTaskKindUser) {
			XCTAssertEqualObjects(x.actionKey, y.actionKey, @"%@", a.elementId);
		}
	} else if ([a isKindOfClass:[WFCallActivity class]]) {
		WFCallActivity *x = (WFCallActivity *)a, *y = (WFCallActivity *)b;
		XCTAssertEqualObjects(x.calledElement, y.calledElement, @"%@", a.elementId);
		XCTAssertEqual(x.binding, y.binding, @"%@", a.elementId);
		XCTAssertEqual(x.calledElementVersion, y.calledElementVersion, @"%@", a.elementId);
		XCTAssertEqualObjects(WFMappingStrings(x.inputs), WFMappingStrings(y.inputs), @"%@", a.elementId);
		XCTAssertEqualObjects(WFMappingStrings(x.outputs), WFMappingStrings(y.outputs), @"%@", a.elementId);
	} else if ([a isKindOfClass:[WFGateway class]]) {
		XCTAssertEqual([(WFGateway *)a kind], [(WFGateway *)b kind], @"%@", a.elementId);
		XCTAssertEqualObjects([(WFGateway *)a defaultFlowId], [(WFGateway *)b defaultFlowId],
			@"%@", a.elementId);
	} else if ([a isKindOfClass:[WFSubProcess class]]) {
		XCTAssertEqual([(WFSubProcess *)a isTriggeredByEvent], [(WFSubProcess *)b isTriggeredByEvent],
			@"%@", a.elementId);
		[self assertDefinition:[(WFSubProcess *)a innerDefinition]
		               matches:[(WFSubProcess *)b innerDefinition]];
	}
}

- (void)assertDefinition:(WFProcessDefinition *)a matches:(WFProcessDefinition *)b
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
		WFFlowNode *other = [b nodeWithId:nodeId];
		if (other != nil) {
			[self assertNode:[a nodeWithId:nodeId] matches:other];
		}
	}
	for (NSString *flowId in a.flows) {
		WFSequenceFlow *x = [a flowWithId:flowId];
		WFSequenceFlow *y = [b flowWithId:flowId];
		XCTAssertEqualObjects(x.sourceId, y.sourceId, @"%@", flowId);
		XCTAssertEqualObjects(x.targetId, y.targetId, @"%@", flowId);
		XCTAssertEqualObjects(x.name, y.name, @"%@", flowId);
		XCTAssertEqualObjects([x.condition expressionString], [y.condition expressionString],
			@"%@", flowId);
	}
}

@end

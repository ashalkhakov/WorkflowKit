#import "WFStore.h"
#import "WFEntities.h"
#import "WFForm.h"
#import <CoreData/CoreData.h>

static NSString * const WFDeploymentEntity = @"WFDeployment";
static NSString * const WFResourceEntity = @"WFResource";
static NSString * const WFDefinitionEntity = @"WFDefinitionRecord";
static NSString * const WFDecisionEntity = @"WFDecisionRecord";
static NSString * const WFSubscriptionEntity = @"WFEventSubscription";
static NSString * const WFJobEntityName = @"WFJob";

@implementation WFDeploymentRecord
@end

@implementation WFDefinitionRecord
@end

@implementation WFDecisionRecord
@end


@implementation WFStore
{
	NSPersistentStoreCoordinator *_coordinator;
	NSManagedObjectContext *_context;
}

+ (NSManagedObjectModel *)model
{
	static NSManagedObjectModel *model = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		/* For running from a build tree, where nothing is installed yet. */
		NSString *override = [[[NSProcessInfo processInfo] environment]
			objectForKey:@"WORKFLOWKIT_MODEL"];
		if ([override length] > 0) {
			model = [[NSManagedObjectModel alloc]
				initWithContentsOfURL:[NSURL fileURLWithPath:override]];
			return;
		}
		NSMutableArray *bundles = [NSMutableArray array];
		NSBundle *own = [NSBundle bundleForClass:[WFStore class]];
		if (own != nil) {
			[bundles addObject:own];
		}
		[bundles addObject:[NSBundle mainBundle]];
		[bundles addObjectsFromArray:[NSBundle allBundles]];
		for (NSBundle *bundle in bundles) {
			NSURL *url = [bundle URLForResource:@"WorkflowKit" withExtension:@"momd"];
			if (url != nil) {
				model = [[NSManagedObjectModel alloc] initWithContentsOfURL:url];
				break;
			}
		}
	});
	return model;
}

+ (instancetype)inMemoryStore:(NSError **)error
{
	return [[self alloc] initWithStoreType:NSInMemoryStoreType
	                                   URL:nil
	                               options:nil
	                                 error:error];
}

+ (instancetype)SQLiteStoreAtURL:(NSURL *)url error:(NSError **)error
{
	return [[self alloc] initWithStoreType:NSSQLiteStoreType
	                                   URL:url
	                               options:nil
	                                 error:error];
}

- (instancetype)initWithStoreType:(NSString *)storeType
                              URL:(NSURL *)url
                          options:(NSDictionary *)options
                            error:(NSError **)error
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	NSManagedObjectModel *model = [[self class] model];
	if (model == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:WFErrorDomain
			                             code:WFErrorInvalidState
			                         userInfo:@{ NSLocalizedDescriptionKey:
				@"WorkflowKit.momd not found beside the library or in the main bundle; set WORKFLOWKIT_MODEL to run uninstalled" }];
		}
		return nil;
	}
	_coordinator = [[NSPersistentStoreCoordinator alloc]
		initWithManagedObjectModel:model];
	if ([_coordinator addPersistentStoreWithType:storeType
	                               configuration:nil
	                                         URL:url
	                                     options:options
	                                       error:error] == nil) {
		return nil;
	}
	_context = [[NSManagedObjectContext alloc]
		initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	[_context setPersistentStoreCoordinator:_coordinator];
	[_context setUndoManager:nil];
	return self;
}

- (NSManagedObjectContext *)newCommandContext
{
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc]
		initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	[context setPersistentStoreCoordinator:_coordinator];
	[context setUndoManager:nil];
	return context;
}

/* Runs on the context's queue. A fetch that fails answers an empty array:
 * for the lookups here "nothing found" is the only useful reading. */
- (NSArray *)fetch:(NSString *)entity
         predicate:(NSPredicate *)predicate
              sort:(NSArray *)sort
             limit:(NSUInteger)limit
{
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entity];
	[request setPredicate:predicate];
	[request setSortDescriptors:sort];
	if (limit > 0) {
		[request setFetchLimit:limit];
	}
	NSArray *rows = [_context executeFetchRequest:request error:NULL];
	return rows ?: @[];
}

/* Saves and then forgets every row, so the context holds nothing between
 * units of work. A failed save is rolled back. */
- (BOOL)saveAndReset:(NSError **)error
{
	BOOL ok = YES;
	if ([_context hasChanges]) {
		ok = [_context save:error];
	}
	if (!ok) {
		[_context rollback];
	}
	[_context reset];
	return ok;
}

- (WFDeploymentRecord *)deploymentRecordFromRow:(NSManagedObject *)row
{
	if (row == nil) {
		return nil;
	}
	WFDeploymentRecord *record = [[WFDeploymentRecord alloc] init];
	record.deploymentId = [row valueForKey:@"deploymentId"];
	record.name = [row valueForKey:@"name"];
	record.deployedAt = [row valueForKey:@"deployedAt"];
	NSMutableDictionary *resources = [NSMutableDictionary dictionary];
	for (NSManagedObject *resource in [row valueForKey:@"resources"]) {
		[resources setObject:[resource valueForKey:@"bytes"]
		              forKey:[resource valueForKey:@"name"]];
	}
	record.resources = resources;
	return record;
}

- (WFDefinitionRecord *)definitionRecordFromRow:(NSManagedObject *)row
{
	if (row == nil) {
		return nil;
	}
	WFDefinitionRecord *record = [[WFDefinitionRecord alloc] init];
	record.definitionId = [row valueForKey:@"definitionId"];
	record.key = [row valueForKey:@"key"];
	record.name = [row valueForKey:@"name"];
	record.version = [[row valueForKey:@"version"] integerValue];
	record.deploymentId = [[row valueForKey:@"deployment"] valueForKey:@"deploymentId"];
	record.resourceName = [row valueForKey:@"resourceName"];
	record.suspended = [[row valueForKey:@"suspended"] boolValue];
	record.historyTimeToLive = [row valueForKey:@"historyTimeToLive"];
	return record;
}

- (WFDecisionRecord *)decisionRecordFromRow:(NSManagedObject *)row
{
	if (row == nil) {
		return nil;
	}
	WFDecisionRecord *record = [[WFDecisionRecord alloc] init];
	record.definitionId = [row valueForKey:@"definitionId"];
	record.key = [row valueForKey:@"key"];
	record.name = [row valueForKey:@"name"];
	record.version = [[row valueForKey:@"version"] integerValue];
	record.versionTag = [row valueForKey:@"versionTag"];
	record.deploymentId = [[row valueForKey:@"deployment"] valueForKey:@"deploymentId"];
	record.resourceName = [row valueForKey:@"resourceName"];
	return record;
}

/* A form as a row beside its definition's, with its XForms document. */
- (void)insertForm:(WFFormDefinition *)form
                of:(NSString *)activityId
          document:(NSString *)document
        definition:(NSManagedObject *)definitionRow
             start:(BOOL)start
{
	NSString *definitionId = [definitionRow valueForKey:@"definitionId"];
	NSManagedObject *formRow = [NSEntityDescription insertNewObjectForEntityForName:@"WFFormRecord"
	                                                         inManagedObjectContext:_context];
	[formRow setValue:[NSString stringWithFormat:@"%@:%@", definitionId, activityId] forKey:@"formId"];
	[formRow setValue:definitionId forKey:@"definitionId"];
	[formRow setValue:activityId forKey:@"activityId"];
	[formRow setValue:form.formKey forKey:@"formKey"];
	[formRow setValue:document forKey:@"document"];
	[formRow setValue:[NSNumber numberWithBool:start] forKey:@"startForm"];
	[formRow setValue:definitionRow forKey:@"definition"];
}

- (NSArray<WFDefinitionRecord *> *)insertDeployment:(WFDeploymentRecord *)deployment
                                        definitions:(NSArray<WFDefinitionRecord *> *)definitions
                                          decisions:(NSArray<WFDecisionRecord *> *)decisions
                                              error:(NSError **)error
{
	__block BOOL ok = NO;
	__block NSError *localError = nil;
	NSMutableArray *stored = [NSMutableArray array];
	[_context performBlockAndWait:^{
		NSManagedObject *row = [NSEntityDescription
			insertNewObjectForEntityForName:WFDeploymentEntity
			         inManagedObjectContext:self->_context];
		[row setValue:deployment.deploymentId forKey:@"deploymentId"];
		[row setValue:deployment.name forKey:@"name"];
		[row setValue:deployment.deployedAt forKey:@"deployedAt"];
		for (NSString *name in deployment.resources) {
			NSManagedObject *resource = [NSEntityDescription
				insertNewObjectForEntityForName:WFResourceEntity
				         inManagedObjectContext:self->_context];
			[resource setValue:name forKey:@"name"];
			[resource setValue:[NSString stringWithFormat:@"%@:%@", deployment.deploymentId, name] forKey:@"resourceId"];
			[resource setValue:[deployment.resources objectForKey:name] forKey:@"bytes"];
			[resource setValue:row forKey:@"deployment"];
		}
		/* Two definitions of one key in one deployment count on from each
		 * other, not both from the stored latest. */
		NSMutableDictionary *next = [NSMutableDictionary dictionary];
		for (WFDefinitionRecord *definition in definitions) {
			if (definition.messageStartName != nil) {
				for (WFEventSubscriptionEntity *start in [self fetch:WFSubscriptionEntity
				         predicate:[NSPredicate predicateWithFormat:
				             @"execution == nil AND eventType == %@ AND eventName == %@",
				             WFEventTypeMessage, definition.messageStartName]
				              sort:nil
				             limit:0]) {
					if (![start.activityId isEqualToString:definition.key]
					    && localError == nil) {
						localError = [NSError errorWithDomain:WFErrorDomain
						                                 code:WFErrorInvalidDefinition
						                             userInfo:@{ NSLocalizedDescriptionKey:
							[NSString stringWithFormat:
								@"message %@ already starts process %@",
								definition.messageStartName, start.activityId] }];
					}
				}
			}
			NSNumber *version = [next objectForKey:definition.key];
			if (version == nil) {
				NSManagedObject *latest = [[self fetch:WFDefinitionEntity
				                             predicate:[NSPredicate predicateWithFormat:
				                                 @"key == %@", definition.key]
				                                  sort:@[ [NSSortDescriptor
				                                      sortDescriptorWithKey:@"version"
				                                                  ascending:NO] ]
				                                 limit:1] lastObject];
				version = [NSNumber numberWithInteger:
					[[latest valueForKey:@"version"] integerValue] + 1];
			}
			[next setObject:[NSNumber numberWithInteger:[version integerValue] + 1]
			         forKey:definition.key];
			WFDefinitionRecord *record = [[WFDefinitionRecord alloc] init];
			record.definitionId = [[NSUUID UUID] UUIDString];
			record.key = definition.key;
			record.name = definition.name;
			record.version = [version integerValue];
			record.deploymentId = deployment.deploymentId;
			record.resourceName = definition.resourceName;
			NSManagedObject *definitionRow = [NSEntityDescription
				insertNewObjectForEntityForName:WFDefinitionEntity
				         inManagedObjectContext:self->_context];
			[definitionRow setValue:record.definitionId forKey:@"definitionId"];
			[definitionRow setValue:record.key forKey:@"key"];
			[definitionRow setValue:record.name forKey:@"name"];
			[definitionRow setValue:version forKey:@"version"];
			[definitionRow setValue:record.resourceName forKey:@"resourceName"];
			[definitionRow setValue:definition.historyTimeToLive forKey:@"historyTimeToLive"];
			[definitionRow setValue:row forKey:@"deployment"];
			for (NSString *activityId in definition.forms) {
				[self insertForm:[definition.forms objectForKey:activityId] of:activityId
				        document:[definition.formDocuments objectForKey:activityId]
				      definition:definitionRow start:[activityId isEqualToString:definition.startEventId]];
			}
			[stored addObject:record];
			/* The latest version starts on the message; earlier ones stop. */
			for (WFEventSubscriptionEntity *old in [self fetch:WFSubscriptionEntity
			         predicate:[NSPredicate predicateWithFormat:
			             @"execution == nil AND activityId == %@", definition.key]
			              sort:nil
			             limit:0]) {
				[self->_context deleteObject:old];
			}
			NSArray *versions = [[self fetch:WFDefinitionEntity
			                      predicate:[NSPredicate predicateWithFormat:@"key == %@",
			                          definition.key]
			                           sort:nil
			                          limit:0] valueForKey:@"definitionId"];
			if ([versions count] > 0) {
				for (WFJobEntity *old in [self fetch:WFJobEntityName
				         predicate:[NSPredicate predicateWithFormat:
				             @"jobType == %@ AND definitionId IN %@",
				             WFJobTypeTimerStart, versions]
				              sort:nil
				             limit:0]) {
					[self->_context deleteObject:old];
				}
			}
			if (definition.timerStartActivityId != nil) {
				WFJobEntity *job = [NSEntityDescription
					insertNewObjectForEntityForName:WFJobEntityName
					         inManagedObjectContext:self->_context];
				job.jobId = [[NSUUID UUID] UUIDString];
				job.jobType = WFJobTypeTimerStart;
				job.activityId = definition.timerStartActivityId;
				job.definitionId = record.definitionId;
				job.createdAt = deployment.deployedAt;
				job.dueDate = definition.timerStartDue;
				job.repeat = definition.timerStartRepeat;
				job.retries = (int32_t)definition.timerStartAttempts;
				job.exclusive = YES;
			}
			if (definition.signalStartName != nil) {
				WFEventSubscriptionEntity *start = [NSEntityDescription
					insertNewObjectForEntityForName:WFSubscriptionEntity
					         inManagedObjectContext:self->_context];
				start.subscriptionId = [[NSUUID UUID] UUIDString];
				start.eventType = WFEventTypeSignal;
				start.eventName = definition.signalStartName;
				start.activityId = definition.key;
				start.definitionId = record.definitionId;
				start.createdAt = deployment.deployedAt;
			}
			if (definition.conditionalStart) {
				WFEventSubscriptionEntity *start = [NSEntityDescription
					insertNewObjectForEntityForName:WFSubscriptionEntity
					         inManagedObjectContext:self->_context];
				start.subscriptionId = [[NSUUID UUID] UUIDString];
				start.eventType = WFEventTypeConditional;
				start.eventName = definition.key;
				start.activityId = definition.key;
				start.definitionId = record.definitionId;
				start.createdAt = deployment.deployedAt;
			}
			if (definition.messageStartName != nil) {
				WFEventSubscriptionEntity *start = [NSEntityDescription
					insertNewObjectForEntityForName:WFSubscriptionEntity
					         inManagedObjectContext:self->_context];
				start.subscriptionId = [[NSUUID UUID] UUIDString];
				start.eventType = WFEventTypeMessage;
				start.eventName = definition.messageStartName;
				/* A start subscription names the process key it starts. */
				start.activityId = definition.key;
				start.definitionId = record.definitionId;
				start.createdAt = deployment.deployedAt;
			}
		}
		NSMutableDictionary *nextDecision = [NSMutableDictionary dictionary];
		for (WFDecisionRecord *decision in decisions) {
			NSNumber *version = [nextDecision objectForKey:decision.key];
			if (version == nil) {
				NSManagedObject *latest = [[self fetch:WFDecisionEntity
				                             predicate:[NSPredicate predicateWithFormat:@"key == %@", decision.key]
				                                  sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"version"
				                                                                        ascending:NO] ]
				                                 limit:1] lastObject];
				version = [NSNumber numberWithInteger:[[latest valueForKey:@"version"] integerValue] + 1];
			}
			[nextDecision setObject:[NSNumber numberWithInteger:[version integerValue] + 1] forKey:decision.key];
			decision.definitionId = [[NSUUID UUID] UUIDString];
			decision.version = [version integerValue];
			decision.deploymentId = deployment.deploymentId;
			NSManagedObject *decisionRow = [NSEntityDescription
				insertNewObjectForEntityForName:WFDecisionEntity
				         inManagedObjectContext:self->_context];
			[decisionRow setValue:decision.definitionId forKey:@"definitionId"];
			[decisionRow setValue:decision.key forKey:@"key"];
			[decisionRow setValue:decision.name forKey:@"name"];
			[decisionRow setValue:version forKey:@"version"];
			[decisionRow setValue:decision.versionTag forKey:@"versionTag"];
			[decisionRow setValue:decision.resourceName forKey:@"resourceName"];
			[decisionRow setValue:row forKey:@"deployment"];
		}
		if (localError != nil) {
			[self->_context rollback];
			[self->_context reset];
			return;
		}
		ok = [self saveAndReset:&localError];
	}];
	if (!ok) {
		if (error != NULL) {
			*error = localError;
		}
		return nil;
	}
	return stored;
}

- (WFDeploymentRecord *)latestDeploymentNamed:(NSString *)name
{
	__block WFDeploymentRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:WFDeploymentEntity
		                  predicate:[NSPredicate predicateWithFormat:@"name == %@", name]
		                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"deployedAt"
		                                                             ascending:NO] ]
		                      limit:1];
		record = [self deploymentRecordFromRow:[rows lastObject]];
		[self->_context reset];
	}];
	return record;
}

- (WFDeploymentRecord *)deploymentWithId:(NSString *)deploymentId
{
	__block WFDeploymentRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:WFDeploymentEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"deploymentId == %@", deploymentId]
		                       sort:nil
		                      limit:1];
		record = [self deploymentRecordFromRow:[rows lastObject]];
		[self->_context reset];
	}];
	return record;
}

- (NSArray<WFDefinitionRecord *> *)definitionRecordsInDeployment:(NSString *)deploymentId
{
	NSMutableArray *records = [NSMutableArray array];
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:WFDefinitionEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"deployment.deploymentId == %@", deploymentId]
		                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"key"
		                                                             ascending:YES] ]
		                      limit:0];
		for (NSManagedObject *row in rows) {
			[records addObject:[self definitionRecordFromRow:row]];
		}
		[self->_context reset];
	}];
	return records;
}

- (WFDefinitionRecord *)definitionRecordForKey:(NSString *)key version:(NSInteger)version
{
	NSPredicate *predicate = version > 0
		? [NSPredicate predicateWithFormat:@"key == %@ AND version == %@",
			key, [NSNumber numberWithInteger:version]]
		: [NSPredicate predicateWithFormat:@"key == %@", key];
	__block WFDefinitionRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:WFDefinitionEntity
		                  predicate:predicate
		                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"version"
		                                                             ascending:NO] ]
		                      limit:1];
		record = [self definitionRecordFromRow:[rows lastObject]];
		[self->_context reset];
	}];
	return record;
}

- (WFDefinitionRecord *)definitionRecordWithId:(NSString *)definitionId
{
	__block WFDefinitionRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:WFDefinitionEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"definitionId == %@", definitionId]
		                       sort:nil
		                      limit:1];
		record = [self definitionRecordFromRow:[rows lastObject]];
		[self->_context reset];
	}];
	return record;
}

- (NSArray<WFDecisionRecord *> *)decisionRecords:(NSPredicate *)predicate limit:(NSUInteger)limit
{
	NSMutableArray *records = [NSMutableArray array];
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:WFDecisionEntity
		                  predicate:predicate
		                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"key" ascending:YES],
		                               [NSSortDescriptor sortDescriptorWithKey:@"version" ascending:NO] ]
		                      limit:limit];
		for (NSManagedObject *row in rows) {
			[records addObject:[self decisionRecordFromRow:row]];
		}
		[self->_context reset];
	}];
	return records;
}

- (NSArray<WFDecisionRecord *> *)decisionRecordsInDeployment:(NSString *)deploymentId
{
	return [self decisionRecords:[NSPredicate predicateWithFormat:@"deployment.deploymentId == %@", deploymentId]
	                       limit:0];
}

- (WFDecisionRecord *)decisionRecordForKey:(NSString *)key version:(NSInteger)version
{
	if (key == nil) {
		return nil;
	}
	NSPredicate *predicate = version > 0
		? [NSPredicate predicateWithFormat:@"key == %@ AND version == %@", key, [NSNumber numberWithInteger:version]]
		: [NSPredicate predicateWithFormat:@"key == %@", key];
	return [[self decisionRecords:predicate limit:1] firstObject];
}

- (WFDecisionRecord *)decisionRecordWithId:(NSString *)definitionId
{
	if (definitionId == nil) {
		return nil;
	}
	return [[self decisionRecords:[NSPredicate predicateWithFormat:@"definitionId == %@", definitionId] limit:1]
		firstObject];
}

@end

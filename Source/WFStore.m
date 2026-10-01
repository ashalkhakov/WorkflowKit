#import "WFStore.h"
#import "WFEntities.h"
#import "WFForm.h"
#import "WFIdentity+Internal.h"
#import <CoreData/CoreData.h>

static NSString * const WFDeploymentEntityName = @"WFDeployment";
static NSString * const WFResourceEntityName = @"WFResource";
static NSString * const WFDefinitionEntityName = @"WFDefinitionRecord";
static NSString * const WFDecisionEntityName = @"WFDecisionRecord";
static NSString * const WFSubscriptionEntityName = @"WFEventSubscription";
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

- (WFDeploymentRecord *)deploymentRecordFromRow:(WFDeploymentEntity *)row
{
	if (row == nil) {
		return nil;
	}
	WFDeploymentRecord *record = [[WFDeploymentRecord alloc] init];
	record.deploymentId = row.deploymentId;
	record.name = row.name;
	record.deployedAt = row.deployedAt;
	NSMutableDictionary *resources = [NSMutableDictionary dictionary];
	for (WFResourceEntity *resource in row.resources) {
		[resources setObject:resource.bytes forKey:resource.name];
	}
	record.resources = resources;
	return record;
}

- (WFDefinitionRecord *)definitionRecordFromRow:(WFDefinitionRecordEntity *)row
{
	if (row == nil) {
		return nil;
	}
	WFDefinitionRecord *record = [[WFDefinitionRecord alloc] init];
	record.definitionId = row.definitionId;
	record.key = row.key;
	record.name = row.name;
	record.version = (NSInteger)row.version;
	record.deploymentId = row.deployment.deploymentId;
	record.resourceName = row.resourceName;
	record.suspended = row.suspended;
	record.historyTimeToLive = row.historyTimeToLive;
	return record;
}

- (WFDecisionRecord *)decisionRecordFromRow:(WFDecisionRecordEntity *)row
{
	if (row == nil) {
		return nil;
	}
	WFDecisionRecord *record = [[WFDecisionRecord alloc] init];
	record.definitionId = row.definitionId;
	record.key = row.key;
	record.name = row.name;
	record.version = (NSInteger)row.version;
	record.versionTag = row.versionTag;
	record.deploymentId = row.deployment.deploymentId;
	record.resourceName = row.resourceName;
	return record;
}

/* A form as a row beside its definition's, with its XForms document. */
- (void)insertForm:(WFFormDefinition *)form
                of:(NSString *)activityId
          document:(NSString *)document
        definition:(WFDefinitionRecordEntity *)definitionRow
             start:(BOOL)start
{
	WFFormRecordEntity *formRow = [NSEntityDescription insertNewObjectForEntityForName:@"WFFormRecord"
	                                                            inManagedObjectContext:_context];
	formRow.formId = [NSString stringWithFormat:@"%@:%@", definitionRow.definitionId, activityId];
	formRow.definitionId = definitionRow.definitionId;
	formRow.activityId = activityId;
	formRow.formKey = form.formKey;
	formRow.document = document;
	formRow.startForm = start;
	formRow.definition = definitionRow;
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
		WFDeploymentEntity *row = [NSEntityDescription
			insertNewObjectForEntityForName:WFDeploymentEntityName
			         inManagedObjectContext:self->_context];
		row.deploymentId = deployment.deploymentId;
		row.name = deployment.name;
		row.deployedAt = deployment.deployedAt;
		for (NSString *name in deployment.resources) {
			WFResourceEntity *resource = [NSEntityDescription
				insertNewObjectForEntityForName:WFResourceEntityName
				         inManagedObjectContext:self->_context];
			resource.name = name;
			resource.resourceId = [NSString stringWithFormat:@"%@:%@", deployment.deploymentId, name];
			resource.bytes = [deployment.resources objectForKey:name];
			resource.deployment = row;
		}
		/* Two definitions of one key in one deployment count on from each
		 * other, not both from the stored latest. */
		NSMutableDictionary *next = [NSMutableDictionary dictionary];
		for (WFDefinitionRecord *definition in definitions) {
			if (definition.messageStartName != nil) {
				for (WFEventSubscriptionEntity *start in [self fetch:WFSubscriptionEntityName
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
				WFDefinitionRecordEntity *latest = [[self fetch:WFDefinitionEntityName
				                             predicate:[NSPredicate predicateWithFormat:
				                                 @"key == %@", definition.key]
				                                  sort:@[ [NSSortDescriptor
				                                      sortDescriptorWithKey:@"version"
				                                                  ascending:NO] ]
				                                 limit:1] lastObject];
				version = [NSNumber numberWithLongLong:latest.version + 1];
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
			WFDefinitionRecordEntity *definitionRow = [NSEntityDescription
				insertNewObjectForEntityForName:WFDefinitionEntityName
				         inManagedObjectContext:self->_context];
			definitionRow.definitionId = record.definitionId;
			definitionRow.key = record.key;
			definitionRow.name = record.name;
			definitionRow.version = [version longLongValue];
			definitionRow.resourceName = record.resourceName;
			definitionRow.historyTimeToLive = definition.historyTimeToLive;
			definitionRow.deployment = row;
			for (NSString *user in definition.candidateStarterUsers) {
				WFIdentityLinkEntity *link = [NSEntityDescription insertNewObjectForEntityForName:@"WFIdentityLink"
				                                                           inManagedObjectContext:self->_context];
				link.type = WFIdentityLinkStarter;
				link.userId = user;
				link.definition = definitionRow;
			}
			for (NSString *entry in definition.candidateStarterGroups) {
				WFIdentityLinkEntity *link = [NSEntityDescription insertNewObjectForEntityForName:@"WFIdentityLink"
				                                                           inManagedObjectContext:self->_context];
				NSString *groupId = nil, *claimName = nil, *claimValue = nil;
				WFSplitCandidate(entry, &groupId, &claimName, &claimValue);
				link.type = WFIdentityLinkStarter;
				link.groupId = groupId;
				link.claimName = claimName;
				link.claimValue = claimValue;
				link.definition = definitionRow;
			}
			for (NSString *activityId in definition.forms) {
				[self insertForm:[definition.forms objectForKey:activityId] of:activityId
				        document:[definition.formDocuments objectForKey:activityId]
				      definition:definitionRow start:[activityId isEqualToString:definition.startEventId]];
			}
			[stored addObject:record];
			/* The latest version starts on the message; earlier ones stop. */
			for (WFEventSubscriptionEntity *old in [self fetch:WFSubscriptionEntityName
			         predicate:[NSPredicate predicateWithFormat:
			             @"execution == nil AND activityId == %@", definition.key]
			              sort:nil
			             limit:0]) {
				[self->_context deleteObject:old];
			}
			NSArray *versions = [[self fetch:WFDefinitionEntityName
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
					insertNewObjectForEntityForName:WFSubscriptionEntityName
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
					insertNewObjectForEntityForName:WFSubscriptionEntityName
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
					insertNewObjectForEntityForName:WFSubscriptionEntityName
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
				WFDecisionRecordEntity *latest = [[self fetch:WFDecisionEntityName
				                             predicate:[NSPredicate predicateWithFormat:@"key == %@", decision.key]
				                                  sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"version"
				                                                                        ascending:NO] ]
				                                 limit:1] lastObject];
				version = [NSNumber numberWithLongLong:latest.version + 1];
			}
			[nextDecision setObject:[NSNumber numberWithInteger:[version integerValue] + 1] forKey:decision.key];
			decision.definitionId = [[NSUUID UUID] UUIDString];
			decision.version = [version integerValue];
			decision.deploymentId = deployment.deploymentId;
			WFDecisionRecordEntity *decisionRow = [NSEntityDescription
				insertNewObjectForEntityForName:WFDecisionEntityName
				         inManagedObjectContext:self->_context];
			decisionRow.definitionId = decision.definitionId;
			decisionRow.key = decision.key;
			decisionRow.name = decision.name;
			decisionRow.version = [version longLongValue];
			decisionRow.versionTag = decision.versionTag;
			decisionRow.resourceName = decision.resourceName;
			decisionRow.deployment = row;
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
		NSArray *rows = [self fetch:WFDeploymentEntityName
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
		NSArray *rows = [self fetch:WFDeploymentEntityName
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
		NSArray *rows = [self fetch:WFDefinitionEntityName
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
		NSArray *rows = [self fetch:WFDefinitionEntityName
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
		NSArray *rows = [self fetch:WFDefinitionEntityName
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
		NSArray *rows = [self fetch:WFDecisionEntityName
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

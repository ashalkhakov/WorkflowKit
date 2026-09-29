#import "UDStore.h"
#import "UDEntities.h"
#import <CoreData/CoreData.h>

static NSString * const UDDeploymentEntity = @"UDDeployment";
static NSString * const UDResourceEntity = @"UDResource";
static NSString * const UDDefinitionEntity = @"UDDefinitionRecord";
static NSString * const UDSubscriptionEntity = @"UDEventSubscription";

@implementation UDDeploymentRecord
@end

@implementation UDDefinitionRecord
@end


@implementation UDStore
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
			objectForKey:@"UDWORKFLOW_MODEL"];
		if ([override length] > 0) {
			model = [[NSManagedObjectModel alloc]
				initWithContentsOfURL:[NSURL fileURLWithPath:override]];
			return;
		}
		NSMutableArray *bundles = [NSMutableArray array];
		NSBundle *own = [NSBundle bundleForClass:[UDStore class]];
		if (own != nil) {
			[bundles addObject:own];
		}
		[bundles addObject:[NSBundle mainBundle]];
		[bundles addObjectsFromArray:[NSBundle allBundles]];
		for (NSBundle *bundle in bundles) {
			NSURL *url = [bundle URLForResource:@"UDWorkflow" withExtension:@"momd"];
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
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidState
			                         userInfo:@{ NSLocalizedDescriptionKey:
				@"UDWorkflow.momd not found beside the library or in the main bundle; set UDWORKFLOW_MODEL to run uninstalled" }];
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

- (UDDeploymentRecord *)deploymentRecordFromRow:(NSManagedObject *)row
{
	if (row == nil) {
		return nil;
	}
	UDDeploymentRecord *record = [[UDDeploymentRecord alloc] init];
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

- (UDDefinitionRecord *)definitionRecordFromRow:(NSManagedObject *)row
{
	if (row == nil) {
		return nil;
	}
	UDDefinitionRecord *record = [[UDDefinitionRecord alloc] init];
	record.definitionId = [row valueForKey:@"definitionId"];
	record.key = [row valueForKey:@"key"];
	record.name = [row valueForKey:@"name"];
	record.version = [[row valueForKey:@"version"] integerValue];
	record.deploymentId = [[row valueForKey:@"deployment"] valueForKey:@"deploymentId"];
	record.resourceName = [row valueForKey:@"resourceName"];
	record.suspended = [[row valueForKey:@"suspended"] boolValue];
	return record;
}

- (NSArray<UDDefinitionRecord *> *)insertDeployment:(UDDeploymentRecord *)deployment
                                        definitions:(NSArray<UDDefinitionRecord *> *)definitions
                                              error:(NSError **)error
{
	__block BOOL ok = NO;
	__block NSError *localError = nil;
	NSMutableArray *stored = [NSMutableArray array];
	[_context performBlockAndWait:^{
		NSManagedObject *row = [NSEntityDescription
			insertNewObjectForEntityForName:UDDeploymentEntity
			         inManagedObjectContext:self->_context];
		[row setValue:deployment.deploymentId forKey:@"deploymentId"];
		[row setValue:deployment.name forKey:@"name"];
		[row setValue:deployment.deployedAt forKey:@"deployedAt"];
		for (NSString *name in deployment.resources) {
			NSManagedObject *resource = [NSEntityDescription
				insertNewObjectForEntityForName:UDResourceEntity
				         inManagedObjectContext:self->_context];
			[resource setValue:name forKey:@"name"];
			[resource setValue:[deployment.resources objectForKey:name] forKey:@"bytes"];
			[resource setValue:row forKey:@"deployment"];
		}
		/* Two definitions of one key in one deployment count on from each
		 * other, not both from the stored latest. */
		NSMutableDictionary *next = [NSMutableDictionary dictionary];
		for (UDDefinitionRecord *definition in definitions) {
			if (definition.messageStartName != nil) {
				for (UDEventSubscriptionEntity *start in [self fetch:UDSubscriptionEntity
				         predicate:[NSPredicate predicateWithFormat:
				             @"execution == nil AND eventType == %@ AND eventName == %@",
				             UDEventTypeMessage, definition.messageStartName]
				              sort:nil
				             limit:0]) {
					if (![start.activityId isEqualToString:definition.key]
					    && localError == nil) {
						localError = [NSError errorWithDomain:UDWorkflowErrorDomain
						                                 code:UDWorkflowErrorInvalidDefinition
						                             userInfo:@{ NSLocalizedDescriptionKey:
							[NSString stringWithFormat:
								@"message %@ already starts process %@",
								definition.messageStartName, start.activityId] }];
					}
				}
			}
			NSNumber *version = [next objectForKey:definition.key];
			if (version == nil) {
				NSManagedObject *latest = [[self fetch:UDDefinitionEntity
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
			UDDefinitionRecord *record = [[UDDefinitionRecord alloc] init];
			record.definitionId = [[NSUUID UUID] UUIDString];
			record.key = definition.key;
			record.name = definition.name;
			record.version = [version integerValue];
			record.deploymentId = deployment.deploymentId;
			record.resourceName = definition.resourceName;
			NSManagedObject *definitionRow = [NSEntityDescription
				insertNewObjectForEntityForName:UDDefinitionEntity
				         inManagedObjectContext:self->_context];
			[definitionRow setValue:record.definitionId forKey:@"definitionId"];
			[definitionRow setValue:record.key forKey:@"key"];
			[definitionRow setValue:record.name forKey:@"name"];
			[definitionRow setValue:version forKey:@"version"];
			[definitionRow setValue:record.resourceName forKey:@"resourceName"];
			[definitionRow setValue:row forKey:@"deployment"];
			[stored addObject:record];
			/* The latest version starts on the message; earlier ones stop. */
			for (UDEventSubscriptionEntity *old in [self fetch:UDSubscriptionEntity
			         predicate:[NSPredicate predicateWithFormat:
			             @"execution == nil AND activityId == %@", definition.key]
			              sort:nil
			             limit:0]) {
				[self->_context deleteObject:old];
			}
			if (definition.messageStartName != nil) {
				UDEventSubscriptionEntity *start = [NSEntityDescription
					insertNewObjectForEntityForName:UDSubscriptionEntity
					         inManagedObjectContext:self->_context];
				start.subscriptionId = [[NSUUID UUID] UUIDString];
				start.eventType = UDEventTypeMessage;
				start.eventName = definition.messageStartName;
				/* A start subscription names the process key it starts. */
				start.activityId = definition.key;
				start.definitionId = record.definitionId;
				start.createdAt = deployment.deployedAt;
			}
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

- (UDDeploymentRecord *)latestDeploymentNamed:(NSString *)name
{
	__block UDDeploymentRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDDeploymentEntity
		                  predicate:[NSPredicate predicateWithFormat:@"name == %@", name]
		                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"deployedAt"
		                                                             ascending:NO] ]
		                      limit:1];
		record = [self deploymentRecordFromRow:[rows lastObject]];
		[self->_context reset];
	}];
	return record;
}

- (UDDeploymentRecord *)deploymentWithId:(NSString *)deploymentId
{
	__block UDDeploymentRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDDeploymentEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"deploymentId == %@", deploymentId]
		                       sort:nil
		                      limit:1];
		record = [self deploymentRecordFromRow:[rows lastObject]];
		[self->_context reset];
	}];
	return record;
}

- (NSArray<UDDefinitionRecord *> *)definitionRecordsInDeployment:(NSString *)deploymentId
{
	NSMutableArray *records = [NSMutableArray array];
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDDefinitionEntity
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

- (UDDefinitionRecord *)definitionRecordForKey:(NSString *)key version:(NSInteger)version
{
	NSPredicate *predicate = version > 0
		? [NSPredicate predicateWithFormat:@"key == %@ AND version == %@",
			key, [NSNumber numberWithInteger:version]]
		: [NSPredicate predicateWithFormat:@"key == %@", key];
	__block UDDefinitionRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDDefinitionEntity
		                  predicate:predicate
		                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"version"
		                                                             ascending:NO] ]
		                      limit:1];
		record = [self definitionRecordFromRow:[rows lastObject]];
		[self->_context reset];
	}];
	return record;
}

- (UDDefinitionRecord *)definitionRecordWithId:(NSString *)definitionId
{
	__block UDDefinitionRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDDefinitionEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"definitionId == %@", definitionId]
		                       sort:nil
		                      limit:1];
		record = [self definitionRecordFromRow:[rows lastObject]];
		[self->_context reset];
	}];
	return record;
}

@end

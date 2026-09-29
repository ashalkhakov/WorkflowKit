#import "UDStore.h"
#import <CoreData/CoreData.h>

static NSString * const UDDeploymentEntity = @"UDDeployment";
static NSString * const UDInstanceEntity = @"UDInstance";
static NSString * const UDJobEntity = @"UDJob";
static NSString * const UDCorrelationEntity = @"UDCorrelation";

@implementation UDInstanceRecord
@end

@implementation UDJobRecord
@end

/* Correlation values are stored as text, tagged with their type so that a
 * string and a number that print alike do not match. */
static NSString *
UDCorrelationText(id value)
{
	if ([value isKindOfClass:[NSString class]]) {
		return [@"s:" stringByAppendingString:value];
	}
	if ([value isKindOfClass:[NSNumber class]]) {
		return [@"n:" stringByAppendingString:[value stringValue]];
	}
	return nil;
}

static NSString *
UDJobMatchKey(NSInteger kind, NSString *tokenId)
{
	return [NSString stringWithFormat:@"%ld:%@", (long)kind, tokenId];
}

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

- (BOOL)recordDeploymentOfProcess:(NSString *)processId
                          version:(NSInteger)version
                             bpmn:(NSString *)bpmn
                            error:(NSError **)error
{
	__block BOOL ok = YES;
	__block NSError *localError = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDDeploymentEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"processId == %@ AND version == %@",
		                      processId, [NSNumber numberWithInteger:version]]
		                       sort:nil
		                      limit:1];
		if ([rows count] > 0) {
			NSManagedObject *row = [rows objectAtIndex:0];
			NSString *stored = [row valueForKey:@"bpmn"];
			if (stored != nil && bpmn != nil && ![stored isEqualToString:bpmn]) {
				localError = [NSError errorWithDomain:UDWorkflowErrorDomain
				                                 code:UDWorkflowErrorInvalidDefinition
				                             userInfo:@{ NSLocalizedDescriptionKey:
					[NSString stringWithFormat:
						@"%@ version %ld is already deployed with different content",
						processId, (long)version] }];
				ok = NO;
			} else if (stored == nil && bpmn != nil) {
				[row setValue:bpmn forKey:@"bpmn"];
			}
			if (ok) {
				ok = [self saveAndReset:&localError];
			} else {
				[self->_context reset];
			}
			return;
		}
		NSManagedObject *row = [NSEntityDescription
			insertNewObjectForEntityForName:UDDeploymentEntity
			         inManagedObjectContext:self->_context];
		[row setValue:processId forKey:@"processId"];
		[row setValue:[NSNumber numberWithInteger:version] forKey:@"version"];
		[row setValue:bpmn forKey:@"bpmn"];
		[row setValue:[NSDate date] forKey:@"deployedAt"];
		ok = [self saveAndReset:&localError];
	}];
	if (!ok && error != NULL) {
		*error = localError;
	}
	return ok;
}

- (NSString *)bpmnForProcess:(NSString *)processId version:(NSInteger)version
{
	__block NSString *bpmn = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDDeploymentEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"processId == %@ AND version == %@",
		                      processId, [NSNumber numberWithInteger:version]]
		                       sort:nil
		                      limit:1];
		bpmn = [[rows lastObject] valueForKey:@"bpmn"];
		[self->_context reset];
	}];
	return bpmn;
}

- (UDInstanceRecord *)instanceRecord:(NSString *)instanceId error:(NSError **)error
{
	__block UDInstanceRecord *record = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDInstanceEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"instanceId == %@", instanceId]
		                       sort:nil
		                      limit:1];
		NSManagedObject *row = [rows lastObject];
		if (row != nil) {
			record = [[UDInstanceRecord alloc] init];
			record.instanceId = [row valueForKey:@"instanceId"];
			record.processId = [row valueForKey:@"processId"];
			record.version = [[row valueForKey:@"version"] integerValue];
			record.status = [[row valueForKey:@"status"] integerValue];
			record.state = [row valueForKey:@"state"];
		}
		[self->_context reset];
	}];
	if (record == nil && error != NULL) {
		*error = [NSError errorWithDomain:UDWorkflowErrorDomain
		                             code:UDWorkflowErrorUnknownElement
		                         userInfo:@{ NSLocalizedDescriptionKey:
			[NSString stringWithFormat:@"no instance %@ in the store", instanceId] }];
	}
	return record;
}

- (NSArray<NSString *> *)instanceIdsWithStatus:(UDInstanceStatus)status
{
	__block NSArray *ids = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDInstanceEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"status == %@",
		                      [NSNumber numberWithInteger:status]]
		                       sort:nil
		                      limit:0];
		ids = [rows valueForKey:@"instanceId"];
		[self->_context reset];
	}];
	return ids;
}

- (NSArray<NSString *> *)instanceIdsForCorrelationKey:(NSString *)key
                                                value:(id)value
{
	NSString *text = UDCorrelationText(value);
	if (key == nil || text == nil) {
		return @[];
	}
	__block NSArray *ids = nil;
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDCorrelationEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"key == %@ AND value == %@", key, text]
		                       sort:nil
		                      limit:0];
		ids = [rows valueForKey:@"instanceId"];
		[self->_context reset];
	}];
	return ids;
}

- (void)reconcileJobs:(NSArray<UDJobRecord *> *)jobs
          forInstance:(NSString *)instanceId
             inserted:(NSMutableArray *)inserted
{
	NSArray *rows = [self fetch:UDJobEntity
	                  predicate:[NSPredicate predicateWithFormat:
	                      @"instanceId == %@", instanceId]
	                       sort:nil
	                      limit:0];
	NSMutableDictionary *stored = [NSMutableDictionary dictionary];
	for (NSManagedObject *row in rows) {
		NSString *key = UDJobMatchKey([[row valueForKey:@"kind"] integerValue],
			[row valueForKey:@"tokenId"]);
		[stored setObject:row forKey:key];
	}
	NSMutableSet *wanted = [NSMutableSet set];
	for (UDJobRecord *job in jobs) {
		NSString *key = UDJobMatchKey(job.kind, job.tokenId);
		[wanted addObject:key];
		NSManagedObject *row = [stored objectForKey:key];
		if (row != nil) {
			if (job.dueAt != nil && ![job.dueAt isEqual:[row valueForKey:@"dueAt"]]) {
				[row setValue:job.dueAt forKey:@"dueAt"];
			}
			continue;
		}
		row = [NSEntityDescription insertNewObjectForEntityForName:UDJobEntity
		                                    inManagedObjectContext:_context];
		UDJobRecord *fresh = [[UDJobRecord alloc] init];
		fresh.jobId = [[NSUUID UUID] UUIDString];
		fresh.instanceId = instanceId;
		fresh.tokenId = job.tokenId;
		fresh.kind = job.kind;
		fresh.actionKey = job.actionKey;
		fresh.dueAt = job.dueAt;
		[row setValue:fresh.jobId forKey:@"jobId"];
		[row setValue:instanceId forKey:@"instanceId"];
		[row setValue:fresh.tokenId forKey:@"tokenId"];
		[row setValue:[NSNumber numberWithInteger:fresh.kind] forKey:@"kind"];
		[row setValue:fresh.actionKey forKey:@"actionKey"];
		[row setValue:fresh.dueAt forKey:@"dueAt"];
		[inserted addObject:fresh];
	}
	for (NSString *key in stored) {
		if (![wanted containsObject:key]) {
			[_context deleteObject:[stored objectForKey:key]];
		}
	}
}

- (void)reconcileCorrelationKeys:(NSDictionary *)keys
                     forInstance:(NSString *)instanceId
{
	NSArray *rows = [self fetch:UDCorrelationEntity
	                  predicate:[NSPredicate predicateWithFormat:
	                      @"instanceId == %@", instanceId]
	                       sort:nil
	                      limit:0];
	NSMutableDictionary *wanted = [NSMutableDictionary dictionary];
	for (NSString *key in keys) {
		NSString *text = UDCorrelationText([keys objectForKey:key]);
		if (text != nil) {
			[wanted setObject:text forKey:key];
		}
	}
	for (NSManagedObject *row in rows) {
		NSString *key = [row valueForKey:@"key"];
		if ([[wanted objectForKey:key] isEqualToString:[row valueForKey:@"value"]]) {
			[wanted removeObjectForKey:key];
		} else {
			[_context deleteObject:row];
		}
	}
	for (NSString *key in wanted) {
		NSManagedObject *row = [NSEntityDescription
			insertNewObjectForEntityForName:UDCorrelationEntity
			         inManagedObjectContext:_context];
		[row setValue:instanceId forKey:@"instanceId"];
		[row setValue:key forKey:@"key"];
		[row setValue:[wanted objectForKey:key] forKey:@"value"];
	}
}

- (NSArray<UDJobRecord *> *)commitInstance:(UDInstanceRecord *)record
                                      jobs:(NSArray<UDJobRecord *> *)jobs
                           correlationKeys:(NSDictionary *)correlationKeys
                                     error:(NSError **)error
{
	__block BOOL ok = NO;
	__block NSError *localError = nil;
	NSMutableArray *inserted = [NSMutableArray array];
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDInstanceEntity
		                  predicate:[NSPredicate predicateWithFormat:
		                      @"instanceId == %@", record.instanceId]
		                       sort:nil
		                      limit:1];
		NSManagedObject *row = [rows lastObject];
		NSDate *now = [NSDate date];
		if (row == nil) {
			row = [NSEntityDescription insertNewObjectForEntityForName:UDInstanceEntity
			                                    inManagedObjectContext:self->_context];
			[row setValue:record.instanceId forKey:@"instanceId"];
			[row setValue:record.processId forKey:@"processId"];
			[row setValue:[NSNumber numberWithInteger:record.version] forKey:@"version"];
			[row setValue:now forKey:@"createdAt"];
		}
		[row setValue:[NSNumber numberWithInteger:record.status] forKey:@"status"];
		[row setValue:record.state forKey:@"state"];
		[row setValue:now forKey:@"updatedAt"];
		[self reconcileJobs:jobs forInstance:record.instanceId inserted:inserted];
		[self reconcileCorrelationKeys:correlationKeys forInstance:record.instanceId];
		ok = [self saveAndReset:&localError];
	}];
	if (!ok) {
		if (error != NULL) {
			*error = localError;
		}
		return nil;
	}
	return inserted;
}

- (UDJobRecord *)jobRecordFromRow:(NSManagedObject *)row
{
	UDJobRecord *job = [[UDJobRecord alloc] init];
	job.jobId = [row valueForKey:@"jobId"];
	job.instanceId = [row valueForKey:@"instanceId"];
	job.tokenId = [row valueForKey:@"tokenId"];
	job.kind = [[row valueForKey:@"kind"] integerValue];
	job.actionKey = [row valueForKey:@"actionKey"];
	job.dueAt = [row valueForKey:@"dueAt"];
	job.attempts = [[row valueForKey:@"attempts"] integerValue];
	return job;
}

- (NSArray<UDJobRecord *> *)jobsOfKind:(UDJobKind)kind
                             dueBefore:(NSDate *)date
                                 limit:(NSUInteger)limit
{
	/* %@ with an NSNumber, not %ld: gnustep-base's predicate parser
	 * takes only object arguments. */
	NSNumber *kindNumber = [NSNumber numberWithInteger:kind];
	NSPredicate *predicate = date == nil
		? [NSPredicate predicateWithFormat:@"kind == %@", kindNumber]
		: [NSPredicate predicateWithFormat:@"kind == %@ AND dueAt <= %@",
			kindNumber, date];
	NSMutableArray *jobs = [NSMutableArray array];
	[_context performBlockAndWait:^{
		NSArray *rows = [self fetch:UDJobEntity
		                  predicate:predicate
		                       sort:@[ [NSSortDescriptor sortDescriptorWithKey:@"dueAt"
		                                                             ascending:YES] ]
		                      limit:limit];
		for (NSManagedObject *row in rows) {
			[jobs addObject:[self jobRecordFromRow:row]];
		}
		[self->_context reset];
	}];
	return jobs;
}

- (NSDate *)earliestTimerDue
{
	return [[[self jobsOfKind:UDJobKindTimer dueBefore:nil limit:1] lastObject] dueAt];
}

- (BOOL)deleteJob:(NSString *)jobId error:(NSError **)error
{
	__block BOOL ok = YES;
	__block NSError *localError = nil;
	[_context performBlockAndWait:^{
		for (NSManagedObject *row in [self fetch:UDJobEntity
		                               predicate:[NSPredicate predicateWithFormat:
		                                   @"jobId == %@", jobId]
		                                    sort:nil
		                                   limit:0]) {
			[self->_context deleteObject:row];
		}
		ok = [self saveAndReset:&localError];
	}];
	if (!ok && error != NULL) {
		*error = localError;
	}
	return ok;
}

@end

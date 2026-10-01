#import "WDSession.h"
#import "WDEntities.h"
#if __has_include(<ODataIncrementalStore/ODataIncrementalStore.h>)
#import <ODataIncrementalStore/ODataIncrementalStore.h>
#else
#import "ODataIncrementalStore.h"
#endif

NSString * const WDSessionDidChangeNotification = @"WDSessionDidChangeNotification";

/* The engine's model, as momc compiled it into the app; or where
 * WORKFLOWKIT_MODEL says, as for the engine itself. */
static NSManagedObjectModel *
WDModel(void)
{
	static NSManagedObjectModel *model;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSString *path = [[[NSProcessInfo processInfo] environment] objectForKey:@"WORKFLOWKIT_MODEL"];
		NSURL *url = [path length] > 0 ? [NSURL fileURLWithPath:path]
		                               : [[NSBundle mainBundle] URLForResource:@"WorkflowKit" withExtension:@"momd"];
		/* A copy: Apple's loads a compiled model immutable. Its classes are
		 * the engine's, which the app does not have: rows are plain managed
		 * objects, except those it shows its own way. */
		NSManagedObjectModel *loaded = url != nil ? [[[NSManagedObjectModel alloc] initWithContentsOfURL:url] copy] : nil;
		NSDictionary *classes = WDEntityClasses();
		for (NSEntityDescription *entity in [loaded entities]) {
			[entity setManagedObjectClassName:[classes objectForKey:[entity name]] ?: @"NSManagedObject"];
		}
		model = loaded;
	});
	return model;
}

@implementation WDSession
{
	NSPersistentStoreCoordinator *_coordinator;
	NSManagedObjectContext *_worker;
}

- (instancetype)initWithServiceURL:(NSURL *)serviceURL credentials:(id<ODataCredentialProviding>)credentials
{
	if ((self = [super init])) {
		_serviceURL = [serviceURL copy];
		_credentials = credentials;
	}
	return self;
}

- (BOOL)open:(NSError **)error
{
	NSManagedObjectModel *model = WDModel();
	if (model == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:@{
				NSLocalizedDescriptionKey: @"The application has no WorkflowKit model." }];
		}
		return NO;
	}
	[ODataIncrementalStore registerStore];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	NSMutableDictionary *options = [NSMutableDictionary dictionary];
	if (_credentials != nil) {
		[options setObject:_credentials forKey:ODataIncrementalStoreCredentialProviderOption];
	}
	NSPersistentStore *store = [coordinator addPersistentStoreWithType:[ODataIncrementalStore storeType]
	                                                     configuration:@"API"
	                                                               URL:_serviceURL
	                                                           options:options
	                                                             error:error];
	if (store == nil) {
		return NO;
	}
	_store = (ODataIncrementalStore *)store;
	_coordinator = coordinator;
	_worker = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	[_worker setPersistentStoreCoordinator:coordinator];
	_viewContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	[_viewContext setPersistentStoreCoordinator:coordinator];
	return YES;
}

- (void)close
{
	_viewContext = nil;
	_worker = nil;
	_coordinator = nil;
	_store = nil;
}

- (void)perform:(id (^)(NSManagedObjectContext *context, NSError **error))work
     completion:(void (^)(id result, NSError *error))completion
{
	NSManagedObjectContext *worker = _worker;
	if (worker == nil) {
		completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
		return;
	}
	[worker performBlock:^{
		/* A pool of its own: GNUstep's libdispatch drains a worker's
		 * only when the thread goes idle. */
		@autoreleasepool {
			NSError *error = nil;
			id result = work(worker, &error);
			[worker reset];
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(result, result != nil ? nil : error);
			});
		}
	}];
}

/* Objects of the private context as the main queue's, read again. */
- (NSArray *)viewObjectsWithIDs:(NSArray *)objectIDs
{
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:[objectIDs count]];
	for (NSManagedObjectID *objectID in objectIDs) {
		NSManagedObject *object = [_viewContext objectWithID:objectID];
		[_viewContext refreshObject:object mergeChanges:NO];
		[objects addObject:object];
	}
	return objects;
}

- (void)fetch:(NSFetchRequest *)request completion:(void (^)(NSArray *objects, NSError *error))completion
{
	[self perform:^id(NSManagedObjectContext *context, NSError **error) {
		NSArray *objects = [context executeFetchRequest:request error:error];
		return [objects valueForKey:@"objectID"];
	} completion:^(id objectIDs, NSError *error) {
		completion(objectIDs != nil ? [self viewObjectsWithIDs:objectIDs] : nil, error);
	}];
}

- (void)invoke:(NSString *)operation
            on:(NSManagedObject *)object
    parameters:(NSDictionary *)parameters
    completion:(void (^)(id result, NSError *error))completion
{
	NSManagedObjectID *objectID = [object objectID];
	__block BOOL changes = NO;
	[self perform:^id(NSManagedObjectContext *context, NSError **error) {
		ODataOperationCall *call = objectID != nil
			? [ODataOperationCall callOfOperation:operation onObject:[context objectWithID:objectID]]
			: [ODataOperationCall callOfOperation:operation inContext:context];
		call.parameters = parameters;
		id result = [call invoke:error];
		changes = call.operation.isAction;
		/* What it returns, by ID: the context is reset. */
		if ([result isKindOfClass:[NSManagedObject class]]) {
			result = [result objectID];
		}
		return result;
	} completion:^(id result, NSError *error) {
		/* The bound object is left as it was, not refreshed: an action may
		 * have ended it (a task completed), and a window drawing it before
		 * it reads its list again would fault it from a server that no
		 * longer has it. The windows read again on the notification. */
		if ([result isKindOfClass:[NSManagedObjectID class]]) {
			result = [[self viewObjectsWithIDs:@[ result ]] firstObject];
		}
		completion(result, error);
		if (error == nil && changes) {
			[[NSNotificationCenter defaultCenter] postNotificationName:WDSessionDidChangeNotification object:self];
		}
	}];
}

@end

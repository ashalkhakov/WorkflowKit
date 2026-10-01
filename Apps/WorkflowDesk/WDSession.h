#import <CoreData/CoreData.h>

@class ODataIncrementalStore;
@protocol ODataCredentialProviding;

/*
 * One server's API, as Core Data has it: the engine's own model, opened
 * on its API configuration over ODataIncrementalStore.
 *
 * The store must not be used on the main queue, which would wait for the
 * network: fetches and operations run on a private-queue context, and
 * their objects reach the main queue's viewContext by ID, where they fault
 * from the rows the store has just kept. Completions run on the main
 * queue.
 */
@interface WDSession : NSObject

- (instancetype)initWithServiceURL:(NSURL *)serviceURL
                       credentials:(id<ODataCredentialProviding>)credentials;

@property (nonatomic, readonly, copy) NSURL *serviceURL;
@property (nonatomic, readonly, strong) id<ODataCredentialProviding> credentials;
@property (nonatomic, readonly, strong) NSManagedObjectContext *viewContext;
/* Once open. */
@property (nonatomic, readonly, strong) ODataIncrementalStore *store;

/* Reads $metadata; off the main queue. */
- (BOOL)open:(NSError **)error;

/* The request's objects, in viewContext, up to date. */
- (void)fetch:(NSFetchRequest *)request completion:(void (^)(NSArray *objects, NSError *error))completion;

/* Work on the private context; nil and an error is a failure. */
- (void)perform:(id (^)(NSManagedObjectContext *context, NSError **error))work
     completion:(void (^)(id result, NSError *error))completion;

/* An action or function bound to the object, or unbound with object nil.
 * An action posts WDSessionDidChangeNotification once it is done, and the
 * windows read what it changed then. */
- (void)invoke:(NSString *)operation
            on:(NSManagedObject *)object
    parameters:(NSDictionary *)parameters
    completion:(void (^)(id result, NSError *error))completion;

/* Before a new session for another server, or none. */
- (void)close;

@end

/* Posted on the main queue after an operation changed something. */
extern NSString * const WDSessionDidChangeNotification;

#import "UDTypes.h"

@class NSManagedObjectModel;
@class NSManagedObjectContext;

/* A deployment: a named set of BPMN resources. */
@interface UDDeploymentRecord : NSObject
@property (nonatomic, copy) NSString *deploymentId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSDate *deployedAt;
/* Resource name to bytes. */
@property (nonatomic, copy) NSDictionary<NSString *, NSData *> *resources;
@end

/* A process definition as deployed: one version of one process key. */
@interface UDDefinitionRecord : NSObject
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger version;
@property (nonatomic, copy) NSString *deploymentId;
@property (nonatomic, copy) NSString *resourceName;
@property (nonatomic) BOOL suspended;
/* The message a message start event starts this definition on, if any. */
@property (nonatomic, copy) NSString *messageStartName;
/* The signal a signal start event starts this definition on, if any. */
@property (nonatomic, copy) NSString *signalStartName;
/* A timer start event, if any: its id, its delay after deployment, and the
 * attempts its job gets. */
@property (nonatomic, strong) NSNumber *historyTimeToLive;
@property (nonatomic, copy) NSString *timerStartActivityId;
@property (nonatomic) NSTimeInterval timerStartDelay;
@property (nonatomic) NSInteger timerStartAttempts;
@end

/*
 * The engine's persistent state, in Core Data: the UDWorkflow model
 * (Model/UDWorkflow.xcdatamodeld) over whichever store type the caller
 * names -- in-memory for tests, SQLite embedded, or a FreeCoreData SQL
 * backend such as CDPostgreSQLStoreType once that backend is linked.
 *
 * The repository methods are synchronous and safe to call from any thread:
 * the store owns one private-queue context and runs each call on it. The
 * engine's commands each work in a context of their own.
 */
@interface UDStore : NSObject

/* The compiled UDWorkflow.momd: the file UDWORKFLOW_MODEL names if set
 * (for running from a build tree), else the one in the library's resource
 * bundle or the main bundle. */
+ (NSManagedObjectModel *)model;

+ (instancetype)inMemoryStore:(NSError **)error;
+ (instancetype)SQLiteStoreAtURL:(NSURL *)url error:(NSError **)error;
- (instancetype)initWithStoreType:(NSString *)storeType
                              URL:(NSURL *)url
                          options:(NSDictionary *)options
                            error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

/* A new private-queue context on the store, for one command. */
- (NSManagedObjectContext *)newCommandContext;

/* Stores a deployment, its resources and its definitions in one save.
 * Each definition gets the next version of its key and a fresh id; the
 * records answered carry them. A definition with a message start event
 * gets a start subscription for it, replacing the previous version's; a
 * message name another process key already starts on is an error. A timer
 * start event gets a job, replacing the previous version's. */
- (NSArray<UDDefinitionRecord *> *)insertDeployment:(UDDeploymentRecord *)deployment
                                        definitions:(NSArray<UDDefinitionRecord *> *)definitions
                                              error:(NSError **)error;
/* The most recent deployment of that name, resources included. */
- (UDDeploymentRecord *)latestDeploymentNamed:(NSString *)name;
- (UDDeploymentRecord *)deploymentWithId:(NSString *)deploymentId;
- (NSArray<UDDefinitionRecord *> *)definitionRecordsInDeployment:(NSString *)deploymentId;
/* version 0 means the latest. */
- (UDDefinitionRecord *)definitionRecordForKey:(NSString *)key version:(NSInteger)version;
- (UDDefinitionRecord *)definitionRecordWithId:(NSString *)definitionId;

@end

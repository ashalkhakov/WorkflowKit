#ifndef UDStore_h
#define UDStore_h

#import "UDTypes.h"

@class NSManagedObjectModel;

typedef NS_ENUM(NSInteger, UDInstanceStatus) {
	UDInstanceStatusActive = 0,
	UDInstanceStatusCompleted,
	UDInstanceStatusFailed
};

typedef NS_ENUM(NSInteger, UDJobKind) {
	UDJobKindService = 0,
	UDJobKindTimer
};

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
@end

/* An instance's row: what a unit of work loads and commits. */
@interface UDInstanceRecord : NSObject
@property (nonatomic, copy) NSString *instanceId;
@property (nonatomic, copy) NSString *processId;
@property (nonatomic) NSInteger version;
@property (nonatomic) UDInstanceStatus status;
/* The marking as a binary property list (-[UDProcessInstance stateDictionary]). */
@property (nonatomic, copy) NSData *state;
@end

/* Outstanding work for a token: a service call to make, or a timer due. */
@interface UDJobRecord : NSObject
@property (nonatomic, copy) NSString *jobId;
@property (nonatomic, copy) NSString *instanceId;
@property (nonatomic, copy) NSString *tokenId;
@property (nonatomic) UDJobKind kind;
@property (nonatomic, copy) NSString *actionKey;
@property (nonatomic, copy) NSDate *dueAt;
@property (nonatomic) NSInteger attempts;
@end

/*
 * The engine's persistent state, in Core Data: the UDWorkflow model
 * (Model/UDWorkflow.xcdatamodeld) over whichever store type the caller
 * names -- in-memory for tests, SQLite embedded, or a FreeCoreData SQL
 * backend such as CDPostgreSQLStoreType once that backend is linked.
 *
 * Every method is synchronous and safe to call from any thread: the store
 * owns one private-queue context and runs each call on it.
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

/* Stores a deployment, its resources and its definitions in one save.
 * Each definition gets the next version of its key and a fresh id; the
 * records answered carry them. */
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

- (UDInstanceRecord *)instanceRecord:(NSString *)instanceId error:(NSError **)error;
- (NSArray<NSString *> *)instanceIdsWithStatus:(UDInstanceStatus)status;
/* Values are strings or numbers; @"7" and @7 are different keys. */
- (NSArray<NSString *> *)instanceIdsForCorrelationKey:(NSString *)key
                                                value:(id)value;

/*
 * Commits one unit of work in one save: the instance row, its jobs and its
 * correlation keys. jobs is the complete set the instance needs now, matched
 * to the stored ones by token and kind: stored jobs not in it are deleted,
 * and those only in it are inserted with a fresh jobId. Answers the
 * inserted jobs, or nil if the save failed, in which case nothing changed.
 */
- (NSArray<UDJobRecord *> *)commitInstance:(UDInstanceRecord *)record
                                      jobs:(NSArray<UDJobRecord *> *)jobs
                           correlationKeys:(NSDictionary *)correlationKeys
                                     error:(NSError **)error;

/* dueBefore nil means any due time, which is what service jobs have. */
- (NSArray<UDJobRecord *> *)jobsOfKind:(UDJobKind)kind
                             dueBefore:(NSDate *)date
                                 limit:(NSUInteger)limit;
- (NSDate *)earliestTimerDue;
/* For a job whose instance is gone. */
- (BOOL)deleteJob:(NSString *)jobId error:(NSError **)error;

@end

#endif /* UDStore_h */

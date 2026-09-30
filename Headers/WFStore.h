#import "WFTypes.h"

@class NSManagedObjectModel;
@class NSManagedObjectContext;

/* A deployment: a named set of BPMN and DMN resources. */
@interface WFDeploymentRecord : NSObject
@property (nonatomic, copy) NSString *deploymentId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSDate *deployedAt;
/* Resource name to bytes. */
@property (nonatomic, copy) NSDictionary<NSString *, NSData *> *resources;
@end

/* A process definition as deployed: one version of one process key. */
@interface WFDefinitionRecord : NSObject
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
/* Whether a conditional start event starts this definition. */
@property (nonatomic) BOOL conditionalStart;
/* A timer start event, if any: its id, when it first fires, what of its
 * cycle repeats after that, and the attempts its job gets. */
@property (nonatomic, strong) NSNumber *historyTimeToLive;
@property (nonatomic, copy) NSString *timerStartActivityId;
@property (nonatomic, copy) NSDate *timerStartDue;
@property (nonatomic, copy) NSString *timerStartRepeat;
@property (nonatomic) NSInteger timerStartAttempts;
@end

/*
 * The engine's persistent state, in Core Data: the WorkflowKit model
 * (Model/WorkflowKit.xcdatamodeld) over whichever store type the caller
 * names -- in-memory for tests, SQLite embedded, or a FreeCoreData SQL
 * backend such as CDPostgreSQLStoreType once that backend is linked.
 *
 * The repository methods are synchronous and safe to call from any thread:
 * the store owns one private-queue context and runs each call on it. The
 * engine's commands each work in a context of their own.
 */
/* A decision as deployed: one version of one decision key. */
@interface WFDecisionRecord : NSObject
@property (nonatomic, copy) NSString *definitionId;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger version;
@property (nonatomic, copy) NSString *versionTag;
@property (nonatomic, copy) NSString *deploymentId;
@property (nonatomic, copy) NSString *resourceName;
@end

@interface WFStore : NSObject

/* The compiled WorkflowKit.momd: the file WORKFLOWKIT_MODEL names if set
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
 * start event gets a job, replacing the previous version's. Decisions
 * are versioned per decision key as definitions are; their records are
 * given their version and id in place. */
- (NSArray<WFDefinitionRecord *> *)insertDeployment:(WFDeploymentRecord *)deployment
                                        definitions:(NSArray<WFDefinitionRecord *> *)definitions
                                          decisions:(NSArray<WFDecisionRecord *> *)decisions
                                              error:(NSError **)error;
/* The most recent deployment of that name, resources included. */
- (WFDeploymentRecord *)latestDeploymentNamed:(NSString *)name;
- (WFDeploymentRecord *)deploymentWithId:(NSString *)deploymentId;
- (NSArray<WFDefinitionRecord *> *)definitionRecordsInDeployment:(NSString *)deploymentId;
/* version 0 means the latest. */
- (WFDefinitionRecord *)definitionRecordForKey:(NSString *)key version:(NSInteger)version;
- (WFDefinitionRecord *)definitionRecordWithId:(NSString *)definitionId;
- (NSArray<WFDecisionRecord *> *)decisionRecordsInDeployment:(NSString *)deploymentId;
/* version 0 means the latest. */
- (WFDecisionRecord *)decisionRecordForKey:(NSString *)key version:(NSInteger)version;
- (WFDecisionRecord *)decisionRecordWithId:(NSString *)definitionId;

@end

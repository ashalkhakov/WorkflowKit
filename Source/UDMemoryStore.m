#import "UDMemoryStore.h"
#import "UDRuntimeState.h"
#import "UDFlowElements.h"
#import <dispatch/dispatch.h>

@interface UDInstanceSnapshot : NSObject
@property (nonatomic, copy) NSString *instanceId;
@property (nonatomic, copy) NSString *processId;
@property (nonatomic) NSInteger version;
@property (nonatomic, copy) NSDictionary *variables;
@property (nonatomic, copy) NSDictionary *correlationKeys;
@property (nonatomic, copy) NSArray *tokens;
@property (nonatomic) BOOL completed;
@property (nonatomic) BOOL failed;
@property (nonatomic, strong) NSError *error;
@property (nonatomic) NSUInteger tokenSerial;
@end

@implementation UDInstanceSnapshot
@end

@implementation UDToken (UDSnapshot)

- (UDToken *)ud_snapshot
{
	UDToken *token = [[UDToken alloc] init];
	token.tokenId = self.tokenId;
	token.nodeId = self.nodeId;
	token.arrivedViaFlowId = self.arrivedViaFlowId;
	token.state = self.state;
	token.parentTokenId = self.parentTokenId;
	token.forkId = self.forkId;
	token.joinExpected = self.joinExpected;
	return token;
}

@end

@implementation UDMemoryStore
{
	dispatch_queue_t _queue;
	NSMutableDictionary *_definitions;
	NSMutableDictionary *_snapshots;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_queue = dispatch_queue_create("ud.workflow.memory-store",
			DISPATCH_QUEUE_SERIAL);
		_definitions = [NSMutableDictionary dictionary];
		_snapshots = [NSMutableDictionary dictionary];
	}
	return self;
}

- (NSString *)keyForProcess:(NSString *)processId version:(NSInteger)version
{
	return [NSString stringWithFormat:@"%@:%ld", processId, (long)version];
}

- (void)registerDefinition:(UDProcessDefinition *)definition
{
	if (definition == nil) {
		return;
	}
	NSString *key = [self keyForProcess:definition.processId
	                            version:definition.version];
	dispatch_sync(_queue, ^{
		[self->_definitions setObject:definition forKey:key];
	});
}

- (UDProcessDefinition *)definitionForProcess:(NSString *)processId
                                      version:(NSInteger)version
{
	__block UDProcessDefinition *definition = nil;
	NSString *key = [self keyForProcess:processId version:version];
	dispatch_sync(_queue, ^{
		definition = [self->_definitions objectForKey:key];
	});
	return definition;
}

- (NSArray<NSString *> *)instanceIds
{
	__block NSArray *ids = nil;
	dispatch_sync(_queue, ^{
		ids = [[self->_snapshots allKeys] copy];
	});
	return ids;
}

- (BOOL)saveInstance:(UDProcessInstance *)instance error:(NSError **)error
{
	if (instance.instanceId == nil || instance.definition == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidState
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"instance missing id or definition" }];
		}
		return NO;
	}

	[self registerDefinition:instance.definition];

	UDInstanceSnapshot *snap = [[UDInstanceSnapshot alloc] init];
	snap.instanceId = instance.instanceId;
	snap.processId = instance.definition.processId;
	snap.version = instance.definition.version;
	snap.variables = [instance.variables copy];
	snap.correlationKeys = [instance.correlationKeys copy];
	snap.completed = instance.isCompleted;
	snap.failed = instance.isFailed;
	snap.error = instance.error;
	snap.tokenSerial = instance.tokenSerial;

	NSMutableArray *tokens = [NSMutableArray array];
	for (UDToken *token in instance.tokens) {
		[tokens addObject:[token ud_snapshot]];
	}
	snap.tokens = tokens;

	dispatch_sync(_queue, ^{
		[self->_snapshots setObject:snap forKey:snap.instanceId];
	});
	return YES;
}

- (UDProcessInstance *)loadInstance:(NSString *)instanceId error:(NSError **)error
{
	__block UDInstanceSnapshot *snap = nil;
	dispatch_sync(_queue, ^{
		snap = [self->_snapshots objectForKey:instanceId];
	});
	if (snap == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorUnknownElement
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"instance not in store" }];
		}
		return nil;
	}

	UDProcessDefinition *definition =
		[self definitionForProcess:snap.processId version:snap.version];
	if (definition == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:UDWorkflowErrorDomain
			                             code:UDWorkflowErrorInvalidDefinition
			                         userInfo:@{ NSLocalizedDescriptionKey:
					@"definition not registered for snapshot" }];
		}
		return nil;
	}

	UDProcessInstance *instance = [[UDProcessInstance alloc] init];
	instance.instanceId = snap.instanceId;
	instance.definition = definition;
	if (snap.variables != nil) {
		[instance.variables addEntriesFromDictionary:snap.variables];
	}
	if (snap.correlationKeys != nil) {
		[instance.correlationKeys addEntriesFromDictionary:snap.correlationKeys];
	}
	instance.completed = snap.completed;
	instance.failed = snap.failed;
	instance.error = snap.error;
	instance.tokenSerial = snap.tokenSerial;
	instance.pendingServices = 0;
	instance.queue = dispatch_queue_create(
		[[NSString stringWithFormat:@"ud.workflow.%@", instance.instanceId]
			UTF8String],
		DISPATCH_QUEUE_SERIAL);

	for (UDToken *saved in snap.tokens) {
		UDToken *token = [saved ud_snapshot];
		UDFlowNode *node = [definition nodeWithId:token.nodeId];
		if (token.state == UDTokenStateWaiting
		    && [node isKindOfClass:[UDTask class]]) {
			UDTaskKind kind = [(UDTask *)node kind];
			if (kind == UDTaskKindService || kind == UDTaskKindScript) {
				token.state = UDTokenStateReady;
			}
		}
		[instance.tokens addObject:token];
	}
	return instance;
}

- (NSArray *)instancesWithCorrelationKey:(NSString *)key
                                   value:(id)value
                                   error:(NSError **)error
{
	NSMutableArray *matches = [NSMutableArray array];
	for (NSString *instanceId in [self instanceIds]) {
		NSError *loadError = nil;
		UDProcessInstance *instance = [self loadInstance:instanceId error:&loadError];
		if (instance == nil) {
			continue;
		}
		id stored = [instance.correlationKeys objectForKey:key];
		if (stored != nil && [stored isEqual:value]) {
			[matches addObject:instance];
		}
	}
	(void)error;
	return matches;
}

@end

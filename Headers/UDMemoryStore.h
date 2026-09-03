#ifndef UDMemoryStore_h
#define UDMemoryStore_h

#import "UDHandlers.h"
#import "UDProcessDefinition.h"

@interface UDMemoryStore : NSObject <UDInstanceStore>

- (void)registerDefinition:(UDProcessDefinition *)definition;
- (UDProcessDefinition *)definitionForProcess:(NSString *)processId
                                      version:(NSInteger)version;
- (NSArray<NSString *> *)instanceIds;
- (NSArray *)instancesWithCorrelationKey:(NSString *)key
                                   value:(id)value
                                   error:(NSError **)error;

@end

#endif /* UDMemoryStore_h */

#ifndef UDHistoryService_h
#define UDHistoryService_h

#import "UDTypes.h"

extern NSString * const UDProcessInstanceStateActive;
extern NSString * const UDProcessInstanceStateCompleted;

@interface UDHistoricProcessInstance : NSObject
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *businessKey;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSString *definitionKey;
@property (nonatomic, readonly, copy) NSDate *startTime;
/* nil while the instance runs. */
@property (nonatomic, readonly, copy) NSDate *endTime;
@property (nonatomic, readonly, copy) NSString *state;
@end

/*
 * What happened, kept after the runtime rows of an instance are gone.
 * Written in the same transaction as the runtime change it records. So far
 * process instances and the latest value of each variable (the AUDIT
 * level of docs/execution-model.md); activity and task history follow.
 */
@interface UDHistoryService : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (UDHistoricProcessInstance *)historicProcessInstanceWithId:(NSString *)processInstanceId;
/* Name to latest value. A process instance variable wins over a local
 * variable of the same name in a subprocess. */
- (NSDictionary *)historicVariablesForProcessInstance:(NSString *)processInstanceId;

@end

#endif /* UDHistoryService_h */

#import "WFTypes.h"

@class WFProcessEngine;

/* A running process instance, as last committed. */
@interface WFProcessInstance : NSObject
@property (nonatomic, readonly, copy) NSString *processInstanceId;
@property (nonatomic, readonly, copy) NSString *businessKey;
@property (nonatomic, readonly, copy) NSString *definitionId;
@property (nonatomic, readonly, copy) NSString *definitionKey;
/* The instance whose call activity started this one; nil otherwise. */
@property (nonatomic, readonly, copy) NSString *superProcessInstanceId;
/* YES once the instance has reached its end: it is then only in history. */
@property (nonatomic, readonly, getter=isEnded) BOOL ended;
@end

/*
 * Process instances, messages and variables.
 *
 * Every call is one command: it runs until each path of the instance is at
 * a wait state or has ended, and commits once. When a call returns, what it
 * did is durable. A call that loses a race with another command on the
 * same instance fails with WFErrorConflict, having changed nothing.
 *
 * Variables are strings, numbers, dates, data, NSNull, or arrays and
 * dictionaries of JSON values.
 */
@interface WFRuntimeService : NSObject

- (instancetype)init NS_UNAVAILABLE;

/* Starts the latest version of the process. */
- (WFProcessInstance *)startProcessInstanceByKey:(NSString *)key
                                       variables:(NSDictionary *)variables
                                           error:(NSError **)error;
- (WFProcessInstance *)startProcessInstanceByKey:(NSString *)key
                                     businessKey:(NSString *)businessKey
                                       variables:(NSDictionary *)variables
                                           error:(NSError **)error;

/* nil, with an error, for an instance that has ended or never existed. */
- (WFProcessInstance *)processInstanceWithId:(NSString *)processInstanceId
                                       error:(NSError **)error;
/* The running instances the instance's call activities started, in no
 * particular order. */
- (NSArray<WFProcessInstance *> *)subProcessInstancesOf:(NSString *)processInstanceId
                                                  error:(NSError **)error;
/* The activities the instance's paths are active in, sorted. A path
 * waiting at a join is not active. */
- (NSArray<NSString *> *)activeActivityIdsForProcessInstance:(NSString *)processInstanceId
                                                       error:(NSError **)error;
/* The process instance's own variables. */
- (NSDictionary *)variablesForProcessInstance:(NSString *)processInstanceId
                                        error:(NSError **)error;
- (BOOL)setVariables:(NSDictionary *)variables
   processInstanceId:(NSString *)processInstanceId
               error:(NSError **)error;

/*
 * Delivers a message to exactly one recipient: a path waiting on a catch
 * or boundary event for that message name, or, when neither the business
 * key's instance nor correlation keys narrow it to a running instance, a
 * process whose start event is that message. Recipients are narrowed by
 * business key and by correlationKeys, process instance variables that
 * must be equal. Zero or several matches are an error. The variables are
 * set on the receiving process instance.
 */
- (BOOL)correlateMessage:(NSString *)messageName
             businessKey:(NSString *)businessKey
         correlationKeys:(NSDictionary *)correlationKeys
               variables:(NSDictionary *)variables
                   error:(NSError **)error;
/* The same, to every match. Answers the process instances it reached. */
- (NSArray<NSString *> *)correlateMessageToAll:(NSString *)messageName
                                   businessKey:(NSString *)businessKey
                               correlationKeys:(NSDictionary *)correlationKeys
                                     variables:(NSDictionary *)variables
                                         error:(NSError **)error;
/*
 * Sends a signal: every path waiting for it, in every process instance,
 * receives it, and every process whose start event it is starts. Nobody
 * waiting is not an error. The variables are set on each receiver.
 */
- (BOOL)signal:(NSString *)signalName
     variables:(NSDictionary *)variables
         error:(NSError **)error;
/* To the paths of one instance waiting for it. */
- (BOOL)signal:(NSString *)signalName
processInstanceId:(NSString *)processInstanceId
     variables:(NSDictionary *)variables
         error:(NSError **)error;

/* To a waiting path of that instance. */
- (BOOL)correlateMessage:(NSString *)messageName
       processInstanceId:(NSString *)processInstanceId
               variables:(NSDictionary *)variables
                   error:(NSError **)error;

@end

#import <CoreData/CoreData.h>

/* The classes of the rows the app shows its own way, by entity name;
 * the rest are plain managed objects. */
NSDictionary *WDEntityClasses(void);

/* A process variable, or one of its historic values: one of a row's
 * columns holds it, as its type has it. */
@interface WDVariable : NSManagedObject
@property (nonatomic, readonly) id displayValue;
@end

/* A process definition or a running instance: Active or Suspended. */
@interface WDSuspendable : NSManagedObject
@property (nonatomic, readonly) NSString *state;
/* When it started and ended, which an execution does not say: nil, so that
 * a list of instances shows running and historic ones alike. */
@property (nonatomic, readonly) NSDate *startTime;
@property (nonatomic, readonly) NSDate *endTime;
@end

/* An instance as its history keeps it, running or finished, shown in the
 * rows a running instance is: its id as executionId, and its state in
 * words -- Active, Suspended, Completed, Canceled -- rather than the
 * engine's ACTIVE, EXTERNALLY_TERMINATED. */
@interface WDHistoricInstance : NSManagedObject
@property (nonatomic, readonly) NSString *executionId;
@property (nonatomic, readonly) NSString *state;
/* No end time yet. */
@property (nonatomic, readonly) BOOL isRunning;
@end

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
@end

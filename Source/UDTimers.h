#import <Foundation/Foundation.h>
#import "UDFlowElements.h"

/* A number of seconds as an ISO-8601 duration: PT1M30S, P7D. */
NSString *UDISODurationText(NSTimeInterval seconds);

/* ISO-8601 text of the kind as a FEEL literal -- @"PT5M", @"2024-01-01T09:00:00Z",
 * "R3/PT10M" -- or nil when it is not one. Durations may be in weeks. */
NSString *UDTimerLiteral(UDTimerKind kind, NSString *text);

/* The timer's ISO-8601 text when its expression is a literal; nil for
 * one that is computed. */
NSString *UDTimerText(UDTimer *timer);

/* When the timer armed now fires first, over the variables, and for a
 * cycle what repeats after that (R2/PT10M, R/PT1H; nil for nothing). NO,
 * with an error, for a value the timer cannot use. */
BOOL UDTimerSchedule(UDTimer *timer, NSDictionary *variables, NSDate *now,
                     NSDate **due, NSString **repeat, NSError **error);

/* The next firing of what repeats, after one due at last. NO when the
 * repetition cannot be read. */
BOOL UDTimerNextDue(NSString *repeat, NSDate *last, NSDate **due, NSString **remaining);

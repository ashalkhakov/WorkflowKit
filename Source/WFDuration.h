#import <Foundation/Foundation.h>

/* ISO-8601 durations in weeks, days, hours, minutes and seconds. Years and
 * months are calendar lengths, not durations, and are refused. Answers a
 * negative number for anything else. */
NSTimeInterval WFParseISODuration(NSString *text);

/* The attempts a job or external task gets with no retry cycle: the first
 * and two retries, as the reference has it. */
#define WF_DEFAULT_ATTEMPTS 3

/*
 * A retry time cycle, camunda:failedJobRetryTimeCycle: "R<n>/<duration>"
 * retries n times, each after the duration; a comma-separated list of
 * durations retries once per duration, each after its own. *attempts is the
 * first attempt plus the retries, *delays the wait before each retry. nil
 * cycle means the default: WF_DEFAULT_ATTEMPTS, retried at once. Answers NO
 * for a cycle it cannot read.
 */
BOOL WFParseRetryCycle(NSString *cycle, NSInteger *attempts, NSArray<NSNumber *> **delays);

/* The wait before the next attempt, given the attempts left before the one
 * that just failed. */
NSTimeInterval WFRetryDelay(NSString *cycle, NSInteger attemptsLeft);

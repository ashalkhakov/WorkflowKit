#import "WFExampleDelegates.h"

/* The list variable with one more at the end. */
static BOOL
WFAppend(WFDelegateExecution *execution, NSString *variable, id value, NSError **error)
{
	id list = [execution variableNamed:variable];
	NSMutableArray *items = [list isKindOfClass:[NSArray class]] ? [list mutableCopy] : [NSMutableArray array];
	[items addObject:value];
	return [execution setVariable:variable value:items error:error];
}

/* PT4H, P2D, PT30M: seconds; 0 for what it does not read. */
static NSTimeInterval
WFSeconds(NSString *duration)
{
	NSScanner *scanner = [NSScanner scannerWithString:[duration uppercaseString]];
	NSTimeInterval seconds = 0;
	BOOL time = NO;
	if (![scanner scanString:@"P" intoString:NULL]) {
		return 0;
	}
	while (![scanner isAtEnd]) {
		if ([scanner scanString:@"T" intoString:NULL]) {
			time = YES;
			continue;
		}
		double amount = 0;
		NSString *unit = nil;
		if (![scanner scanDouble:&amount]
		    || ![scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"DHMSW"]
		                            intoString:&unit]) {
			return 0;
		}
		if ([unit isEqualToString:@"W"]) {
			seconds += amount * 7 * 86400;
		} else if ([unit isEqualToString:@"D"]) {
			seconds += amount * 86400;
		} else if ([unit isEqualToString:@"H"]) {
			seconds += amount * 3600;
		} else if ([unit isEqualToString:@"M"]) {
			seconds += amount * (time ? 60 : 30 * 86400);
		} else {
			seconds += amount;
		}
	}
	return seconds;
}

@implementation WFExampleAudit

- (BOOL)notifyWithExecution:(WFDelegateExecution *)execution error:(NSError **)error
{
	NSString *entry = [NSString stringWithFormat:@"%@ %@", execution.eventName,
	                   execution.activityId ?: @"process"];
	NSString *note = [execution.fields objectForKey:@"note"];
	if ([note isKindOfClass:[NSString class]] && [note length] > 0) {
		entry = [entry stringByAppendingFormat:@": %@", note];
	}
	return WFAppend(execution, @"auditTrail", entry, error);
}

@end

@implementation WFExampleMailer

- (BOOL)executeWithExecution:(WFDelegateExecution *)execution error:(NSError **)error
{
	NSMutableDictionary *message = [NSMutableDictionary dictionary];
	for (NSString *field in @[ @"to", @"template", @"subject" ]) {
		id value = [execution.fields objectForKey:field];
		if (value != nil && value != [NSNull null]) {
			[message setObject:[value description] forKey:field];
		}
	}
	if ([message objectForKey:@"to"] == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:WFErrorDomain code:WFErrorHandler userInfo:@{
				NSLocalizedDescriptionKey: @"the mailer needs a to field" }];
		}
		return NO;
	}
	return WFAppend(execution, @"outbox", message, error);
}

@end

@implementation WFExampleWorkload

- (BOOL)notifyWithTask:(WFDelegateTask *)task error:(NSError **)error
{
	NSDictionary *fields = task.fields;
	id assignee = [fields objectForKey:@"assignTo"];
	if ([assignee isKindOfClass:[NSString class]] && [assignee length] > 0) {
		task.assignee = assignee;
	}
	NSTimeInterval due = WFSeconds([[fields objectForKey:@"dueIn"] description] ?: @"");
	if (due > 0) {
		task.dueDate = [NSDate dateWithTimeIntervalSinceNow:due];
	}
	NSString *queue = [[fields objectForKey:@"queue"] description];
	if ([queue length] > 0) {
		return [task setLocalVariable:@"queue" value:queue error:error];
	}
	return YES;
}

@end

@implementation WFExamplePlugin

- (void)registerWithEngine:(WFProcessEngine *)engine
{
	[engine registerDelegate:[[WFExampleAudit alloc] init] forName:@"audit"];
	[engine registerDelegate:[[WFExampleMailer alloc] init] forName:@"mailer"];
	[engine registerDelegate:[[WFExampleWorkload alloc] init] forName:@"workload"];
}

@end

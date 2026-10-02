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

/* A form handler's refusal: what the person has to change. */
static NSError *
WFFormRefusal(NSString *message)
{
	return [NSError errorWithDomain:WFErrorDomain code:WFErrorInvalidFormData
	                       userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSXMLElement *
WFChild(NSXMLElement *element, NSString *name)
{
	return [[element elementsForName:name] firstObject];
}

/* The child's text, trimmed. */
static NSString *
WFText(NSXMLElement *element, NSString *name)
{
	return [[WFChild(element, name) stringValue] ?: @""
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSXMLElement *
WFElement(NSString *name, id value)
{
	NSXMLElement *element = [[NSXMLElement alloc] initWithName:name];
	if (value != nil && value != [NSNull null]) {
		[element setStringValue:[value description]];
	}
	return element;
}

/* The whole text as a number; nil for text that is not one. */
static NSNumber *
WFNumber(NSString *text, BOOL whole)
{
	NSScanner *scanner = [NSScanner scannerWithString:text];
	long long integer = 0;
	double real = 0;
	if (whole ? ![scanner scanLongLong:&integer] : ![scanner scanDouble:&real]) {
		return nil;
	}
	if (![scanner isAtEnd]) {
		return nil;
	}
	return whole ? [NSNumber numberWithLongLong:integer] : [NSNumber numberWithDouble:real];
}

@implementation WFExampleOrderForm

- (NSXMLDocument *)instanceForForm:(WFFormContext *)context error:(NSError **)error
{
	NSXMLElement *order = [[NSXMLElement alloc] initWithName:@"order"];
	for (NSString *name in @[ @"orderNumber", @"customer" ]) {
		[order addChild:WFElement(name, nil)];
	}
	[order addChild:WFElement(@"express", @"false")];
	NSXMLElement *lines = [[NSXMLElement alloc] initWithName:@"lines"];
	NSXMLElement *line = [[NSXMLElement alloc] initWithName:@"line"];
	[line addChild:WFElement(@"item", nil)];
	[line addChild:WFElement(@"quantity", @"1")];
	[line addChild:WFElement(@"price", nil)];
	[line addChild:WFElement(@"amount", nil)];
	[lines addChild:line];
	[order addChild:lines];
	[order addChild:WFElement(@"total", nil)];
	return [[NSXMLDocument alloc] initWithRootElement:order];
}

- (NSDictionary *)variablesFromInstance:(NSXMLDocument *)instance
                                   form:(WFFormContext *)context
                                  error:(NSError **)error
{
	NSXMLElement *order = [instance rootElement];
	NSString *orderNumber = WFText(order, @"orderNumber");
	NSString *customer = WFText(order, @"customer");
	NSString *problem = [orderNumber length] == 0 ? @"an order needs its order number"
		: [customer length] == 0 ? @"an order needs its customer" : nil;
	NSMutableArray *lines = [NSMutableArray array];
	double total = 0;
	for (NSXMLElement *line in [WFChild(order, @"lines") elementsForName:@"line"]) {
		if (problem != nil) {
			break;
		}
		NSUInteger number = [lines count] + 1;
		NSString *item = WFText(line, @"item");
		NSNumber *quantity = WFNumber(WFText(line, @"quantity"), YES);
		NSNumber *price = WFNumber(WFText(line, @"price"), NO);
		if ([item length] == 0) {
			problem = [NSString stringWithFormat:@"line %lu needs its item", (unsigned long)number];
		} else if (quantity == nil || [quantity longLongValue] < 1) {
			problem = [NSString stringWithFormat:@"line %lu: the quantity is a whole number, at least 1",
				(unsigned long)number];
		} else if (price == nil || [price doubleValue] < 0) {
			problem = [NSString stringWithFormat:@"line %lu: the price is a number, not below 0",
				(unsigned long)number];
		} else {
			[lines addObject:@{ @"item": item, @"quantity": quantity, @"price": price }];
			total += [quantity longLongValue] * [price doubleValue];
		}
	}
	if (problem == nil && [lines count] == 0) {
		problem = @"an order needs a line";
	}
	if (problem != nil) {
		if (error != NULL) {
			*error = WFFormRefusal(problem);
		}
		return nil;
	}
	context.businessKey = context.businessKey ?: orderNumber;
	/* The total worked out again, not taken from the form. */
	return @{ @"orderNumber": orderNumber, @"customer": customer,
	          @"express": [NSNumber numberWithBool:[WFText(order, @"express") isEqualToString:@"true"]],
	          @"lines": lines, @"total": [NSNumber numberWithDouble:total] };
}

@end

@implementation WFExampleExpenseClaim

- (NSXMLDocument *)instanceForForm:(WFFormContext *)context error:(NSError **)error
{
	NSXMLElement *claim = [[NSXMLElement alloc] initWithName:@"claim"];
	[claim addChild:WFElement(@"reference", nil)];
	NSXMLElement *lines = [[NSXMLElement alloc] initWithName:@"lines"];
	NSXMLElement *line = [[NSXMLElement alloc] initWithName:@"line"];
	[line addChild:WFElement(@"item", nil)];
	[line addChild:WFElement(@"amount", nil)];
	[lines addChild:line];
	[claim addChild:lines];
	NSXMLElement *reviewers = [[NSXMLElement alloc] initWithName:@"reviewers"];
	[reviewers addChild:WFElement(@"reviewer", nil)];
	[claim addChild:reviewers];
	[claim addChild:WFElement(@"total", nil)];
	return [[NSXMLDocument alloc] initWithRootElement:claim];
}

- (NSDictionary *)variablesFromInstance:(NSXMLDocument *)instance
                                   form:(WFFormContext *)context
                                  error:(NSError **)error
{
	NSXMLElement *claim = [instance rootElement];
	NSString *reference = WFText(claim, @"reference");
	NSString *problem = [reference length] == 0 ? @"a claim needs its reference" : nil;
	NSMutableArray *lines = [NSMutableArray array];
	for (NSXMLElement *line in [WFChild(claim, @"lines") elementsForName:@"line"]) {
		if (problem != nil) {
			break;
		}
		NSUInteger number = [lines count] + 1;
		NSString *item = WFText(line, @"item");
		NSNumber *amount = WFNumber(WFText(line, @"amount"), NO);
		if ([item length] == 0) {
			problem = [NSString stringWithFormat:@"line %lu needs its item", (unsigned long)number];
		} else if (amount == nil || [amount doubleValue] <= 0) {
			problem = [NSString stringWithFormat:@"line %lu: the amount is a number above 0", (unsigned long)number];
		} else {
			[lines addObject:@{ @"item": item, @"amount": amount }];
		}
	}
	/* Each reviewer once, in the order named. */
	NSMutableArray *reviewers = [NSMutableArray array];
	for (NSXMLElement *reviewer in [WFChild(claim, @"reviewers") elementsForName:@"reviewer"]) {
		NSString *name = [[reviewer stringValue]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([name length] > 0 && ![reviewers containsObject:name]) {
			[reviewers addObject:name];
		}
	}
	if (problem == nil && [lines count] == 0) {
		problem = @"a claim needs a line";
	}
	if (problem == nil && [reviewers count] == 0) {
		problem = @"a claim needs a reviewer";
	}
	if (problem != nil) {
		if (error != NULL) {
			*error = WFFormRefusal(problem);
		}
		return nil;
	}
	context.businessKey = context.businessKey ?: reference;
	return @{ @"lines": lines, @"reviewers": reviewers, @"approvals": @0, @"notes": @[] };
}

@end

@implementation WFExampleExpenseReview

- (NSXMLDocument *)instanceForForm:(WFFormContext *)context error:(NSError **)error
{
	NSDictionary *variables = context.variables;
	NSXMLElement *review = [[NSXMLElement alloc] initWithName:@"review"];
	[review addChild:WFElement(@"reviewer", [variables objectForKey:@"reviewer"])];
	NSXMLElement *lines = [[NSXMLElement alloc] initWithName:@"lines"];
	id claimed = [variables objectForKey:@"lines"];
	for (NSDictionary *each in [claimed isKindOfClass:[NSArray class]] ? claimed : @[]) {
		if (![each isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		NSXMLElement *line = [[NSXMLElement alloc] initWithName:@"line"];
		[line addChild:WFElement(@"item", [each objectForKey:@"item"])];
		[line addChild:WFElement(@"amount", [each objectForKey:@"amount"])];
		[lines addChild:line];
	}
	[review addChild:lines];
	[review addChild:WFElement(@"total", [variables objectForKey:@"total"])];
	[review addChild:WFElement(@"largest", [variables objectForKey:@"largest"])];
	[review addChild:WFElement(@"decision", nil)];
	[review addChild:WFElement(@"reason", nil)];
	return [[NSXMLDocument alloc] initWithRootElement:review];
}

- (NSDictionary *)variablesFromInstance:(NSXMLDocument *)instance
                                   form:(WFFormContext *)context
                                  error:(NSError **)error
{
	NSString *decision = WFText([instance rootElement], @"decision");
	NSString *reason = WFText([instance rootElement], @"reason");
	NSString *problem = ![@[ @"approve", @"reject" ] containsObject:decision] ? @"approve or reject the claim"
		: [decision isEqualToString:@"reject"] && [reason length] == 0 ? @"a rejection needs a reason"
		: [reason length] > 500 ? @"the reason is longer than 500 characters" : nil;
	if (problem != nil) {
		if (error != NULL) {
			*error = WFFormRefusal(problem);
		}
		return nil;
	}
	id notes = [context.variables objectForKey:@"notes"];
	NSMutableArray *kept = [notes isKindOfClass:[NSArray class]] ? [notes mutableCopy] : [NSMutableArray array];
	if ([reason length] > 0) {
		[kept addObject:[NSString stringWithFormat:@"%@: %@",
			[[context.variables objectForKey:@"reviewer"] description] ?: @"a reviewer", reason]];
	}
	return @{ @"approved": [NSNumber numberWithBool:[decision isEqualToString:@"approve"]], @"notes": kept };
}

@end

@implementation WFExamplePlugin

- (void)registerWithEngine:(WFProcessEngine *)engine
{
	[engine registerDelegate:[[WFExampleAudit alloc] init] forName:@"audit"];
	[engine registerDelegate:[[WFExampleMailer alloc] init] forName:@"mailer"];
	[engine registerDelegate:[[WFExampleWorkload alloc] init] forName:@"workload"];
	[engine registerDelegateClass:[WFExampleOrderForm class] forName:@"orderForm"];
	[engine registerDelegateClass:[WFExampleExpenseClaim class] forName:@"expenseClaim"];
	[engine registerDelegateClass:[WFExampleExpenseReview class] forName:@"expenseReview"];
}

@end

#import "WDInterface.h"

void
WDAlert(NSWindow *window, NSString *message, NSError *error)
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:message];
	[alert setInformativeText:[error localizedDescription] ?: @""];
	[alert beginSheetModalForWindow:window completionHandler:nil];
}

void
WDFormatDateColumns(NSTableView *table)
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	/* GNUstep still defaults to the old behaviour, where a style is
	 * ignored. */
	[formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
	[formatter setDateStyle:NSDateFormatterShortStyle];
	[formatter setTimeStyle:NSDateFormatterShortStyle];
	for (NSTableColumn *column in [table tableColumns]) {
		NSString *key = [column identifier];
		if ([key hasSuffix:@"At"] || [key hasSuffix:@"Date"] || [key hasSuffix:@"Time"]) {
			[[column dataCell] setFormatter:formatter];
		}
	}
}

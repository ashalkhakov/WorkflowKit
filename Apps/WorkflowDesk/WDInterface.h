#import <AppKit/AppKit.h>

/* What the windows share. */

/* A failed request, told on the window as a sheet. */
void WDAlert(NSWindow *window, NSString *message, NSError *error);

/* The columns of dates -- those whose identifier, the key they show,
 * ends in At, Date or Time -- in the locale's short date and time. */
void WDFormatDateColumns(NSTableView *table);

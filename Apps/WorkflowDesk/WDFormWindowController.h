#import <AppKit/AppKit.h>

@class XFProcessor;

/*
 * A form in a window of its own: the XForms document, with the instance it
 * opens with, laid out by XFormsKit's form view. Submit takes the instance
 * as the form leaves it, once every relevant field is filled in and valid,
 * and hands it to the submitter, which sends it to the server; the window
 * closes when the server has taken it.
 */
@interface WDFormWindowController : NSWindowController <NSWindowDelegate>

typedef void (^WDFormSubmitter)(NSString *instance, void (^done)(NSError *error));

- (instancetype)initWithTitle:(NSString *)title
                     document:(NSString *)document
                      baseURL:(NSURL *)baseURL
                  submitTitle:(NSString *)submitTitle
                    submitter:(WDFormSubmitter)submitter;

@property (nonatomic, strong) IBOutlet NSScrollView *scrollView;
@property (nonatomic, strong) IBOutlet NSButton *submitButton;
@property (nonatomic, copy) NSString *status;
@property (nonatomic) BOOL idle;

/* Called once the window has closed, submitted or not. */
@property (nonatomic, copy) void (^closed)(WDFormWindowController *controller);

- (IBAction)submit:(id)sender;
- (IBAction)cancel:(id)sender;

@end

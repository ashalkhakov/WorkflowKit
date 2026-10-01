#import "WDFormWindowController.h"
#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFFormView.h>
#import <XFormsKit/XFInstance.h>
#import <XFormsKit/XFProcessor.h>

@implementation WDFormWindowController
{
	NSString *_title;
	NSString *_document;
	NSURL *_baseURL;
	NSString *_submitTitle;
	WDFormSubmitter _submitter;
	XFProcessor *_processor;
	XFFormView *_formView;
}

- (instancetype)initWithTitle:(NSString *)title
                     document:(NSString *)document
                      baseURL:(NSURL *)baseURL
                  submitTitle:(NSString *)submitTitle
                    submitter:(WDFormSubmitter)submitter
{
	if ((self = [super initWithWindowNibName:@"FormWindow"])) {
		_title = [title copy];
		_document = [document copy];
		_baseURL = [baseURL copy];
		_submitTitle = [submitTitle copy];
		_submitter = [submitter copy];
		_status = @"";
		_idle = YES;
	}
	return self;
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[[self window] setTitle:_title ?: @"Form"];
	[[self window] setDelegate:self];
	[self.submitButton setTitle:_submitTitle ?: @"Submit"];

	NSError *error = nil;
	_processor = [XFProcessor processorWithXMLString:_document baseURL:_baseURL error:&error];
	if (_processor == nil) {
		self.status = [NSString stringWithFormat:@"The form cannot be shown: %@", [error localizedDescription]];
		self.idle = NO;
		return;
	}
	__weak WDFormWindowController *weakSelf = self;
	_processor.messageHandler = ^(NSString *text, NSString *level) {
		[weakSelf showMessage:text];
	};
	_processor.confirmHandler = ^BOOL(NSString *text) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:text];
		[alert addButtonWithTitle:@"OK"];
		[alert addButtonWithTitle:@"Cancel"];
		return [alert runModal] == NSAlertFirstButtonReturn;
	};
	_processor.loadRequestHandler = ^BOOL(NSURL *url, NSString *show) {
		return url != nil ? [[NSWorkspace sharedWorkspace] openURL:url] : NO;
	};
	_formView = [[XFFormView alloc] initWithProcessor:_processor];
	_formView.instanceChangedHandler = ^{
		weakSelf.status = @"";
	};
	[self.scrollView setDocumentView:_formView];
}

- (void)showMessage:(NSString *)text
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:text ?: @""];
	[alert beginSheetModalForWindow:[self window] completionHandler:nil];
}

/* The labels of relevant fields that are invalid or required and empty. */
- (NSArray *)fieldsToFix
{
	[_processor refreshControls];
	NSMutableArray *labels = [NSMutableArray array];
	for (XFControl *control in _processor.controls) {
		if (control.boundNode == nil || !control.relevant || control.readonly) {
			continue;
		}
		if (!control.valid || (control.required && [control.stringValue length] == 0)) {
			[labels addObject:[control.label length] > 0 ? control.label : (control.identifier ?: @"a field")];
		}
	}
	return labels;
}

- (IBAction)submit:(id)sender
{
	if (_processor == nil || !self.idle) {
		return;
	}
	/* What the field being edited holds, committed first. */
	[[self window] makeFirstResponder:nil];
	NSArray *fix = [self fieldsToFix];
	if ([fix count] > 0) {
		self.status = [NSString stringWithFormat:@"Fill in or correct: %@.", [fix componentsJoinedByString:@", "]];
		NSBeep();
		return;
	}
	NSString *instance = [[[_processor defaultInstance] documentElement] XMLString];
	self.idle = NO;
	self.status = @"Sending…";
	_submitter(instance, ^(NSError *error) {
		self.idle = YES;
		if (error != nil) {
			self.status = @"";
			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:@"The server did not take the form."];
			[alert setInformativeText:[error localizedDescription] ?: @""];
			[alert beginSheetModalForWindow:[self window] completionHandler:nil];
			return;
		}
		[self close];
	});
}

- (IBAction)cancel:(id)sender
{
	[self close];
}

- (void)windowWillClose:(NSNotification *)notification
{
	[_processor close];
	/* Through the scroll view: GNUstep's clip view does not retain its
	 * document view. */
	[self.scrollView setDocumentView:nil];
	_formView = nil;
	if (self.closed != nil) {
		void (^closed)(WDFormWindowController *) = self.closed;
		self.closed = nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			closed(self);
		});
	}
}

@end

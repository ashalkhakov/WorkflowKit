#import "WDTasksWindowController.h"
#import "WDFormDocument.h"
#import "WDFormWindowController.h"
#import "WDInterface.h"
#import "WDSession.h"
#if __has_include(<ODataIncrementalStore/ODataIncrementalStore.h>)
#import <ODataIncrementalStore/ODataIncrementalStore.h>
#else
#import "ODataIncrementalStore.h"
#endif

/* The Show pop-up's items, by tag. */
enum { WDShowAll = 0, WDShowMine = 1, WDShowUnassigned = 2 };

@implementation WDTasksWindowController
{
	WDSession *_session;
	NSString *_userId;
	NSString *_userName;
	NSMutableArray *_forms;
	NSUInteger _loading;
}

- (instancetype)initWithSession:(WDSession *)session userId:(NSString *)userId userName:(NSString *)userName
{
	if ((self = [super initWithWindowNibName:@"TasksWindow"])) {
		_session = session;
		_userId = [userId copy];
		_userName = [userName copy];
		_forms = [NSMutableArray array];
		_status = @"";
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionDidChange:)
		                                             name:WDSessionDidChangeNotification object:session];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[[self window] setTitle:[NSString stringWithFormat:@"Tasks — %@", _userName ?: [[_session serviceURL] host]]];
	[self.tasks setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO] ]];
	[self.definitions setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
	                                                                        selector:@selector(caseInsensitiveCompare:)] ]];
	/* Mine needs to know who that is: the ID token says, where there was
	 * a sign-in. */
	[[self.showPopUp itemAtIndex:WDShowMine] setEnabled:_userId != nil];
	[self.showPopUp setAutoenablesItems:NO];
	/* GNUstep's search field does not send its action per keystroke. */
	[self.searchField setDelegate:(id)self];
	[self.tableView setDelegate:self];
	WDFormatDateColumns(self.tableView);
	[self refresh:self];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] == self.searchField) {
		[self filterChanged:self.searchField];
	}
}

- (void)sessionDidChange:(NSNotification *)notification
{
	[self refresh:self];
}

- (void)setLoading:(BOOL)loading
{
	_loading = loading ? _loading + 1 : _loading - 1;
	/* Hidden by hand: GNUstep shows a stopped indicator regardless. */
	[self.progress setHidden:_loading == 0];
	if (_loading > 0) {
		[self.progress startAnimation:self];
	} else {
		[self.progress stopAnimation:self];
	}
}

- (IBAction)refresh:(id)sender
{
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"WFTask"];
	[fetch setRelationshipKeyPathsForPrefetching:@[ @"processInstance" ]];
	[self setLoading:YES];
	[_session fetch:fetch completion:^(NSArray *objects, NSError *error) {
		[self setLoading:NO];
		if (objects == nil) {
			self.status = @"";
			WDAlert([self window], @"Could not read the tasks.", error);
			return;
		}
		[self.tasks setContent:objects];
		[self.tasks rearrangeObjects];
		[self selectionDidChange];
	}];
}

- (IBAction)filterChanged:(id)sender
{
	NSMutableArray *conditions = [NSMutableArray array];
	switch ([[self.showPopUp selectedItem] tag]) {
	case WDShowMine:
		if (_userId != nil) {
			[conditions addObject:[NSPredicate predicateWithFormat:@"assignee == %@", _userId]];
		}
		break;
	case WDShowUnassigned:
		[conditions addObject:[NSPredicate predicateWithFormat:@"assignee == nil"]];
		break;
	}
	NSString *needle = [[self.searchField stringValue]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if ([needle length] > 0) {
		[conditions addObject:[NSPredicate predicateWithFormat:
			@"name CONTAINS[cd] %@ OR processInstance.businessKey CONTAINS[cd] %@", needle, needle]];
	}
	[self.tasks setFilterPredicate:[conditions count] > 0
		? [NSCompoundPredicate andPredicateWithSubpredicates:conditions] : nil];
	/* A new filter rearranges by itself on macOS, not everywhere. */
	[self.tasks rearrangeObjects];
	[self selectionDidChange];
}

- (NSManagedObject *)selectedTask
{
	return [[self.tasks selectedObjects] firstObject];
}

- (void)selectionDidChange
{
	NSManagedObject *task = [self selectedTask];
	self.canOpen = task != nil;
	self.canClaim = task != nil && [task valueForKey:@"assignee"] == nil;
	self.canUnclaim = task != nil && [task valueForKey:@"assignee"] != nil;
	NSUInteger shown = [[self.tasks arrangedObjects] count], all = [[self.tasks content] count];
	self.status = shown == all ? [NSString stringWithFormat:@"%lu tasks", (unsigned long)all]
	                           : [NSString stringWithFormat:@"%lu of %lu tasks", (unsigned long)shown, (unsigned long)all];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	if ([notification object] == self.tableView) {
		[self selectionDidChange];
	}
}

- (void)invoke:(NSString *)operation on:(NSManagedObject *)object failure:(NSString *)failure
{
	if (object == nil) {
		return;
	}
	[self setLoading:YES];
	[_session invoke:operation on:object parameters:nil completion:^(id result, NSError *error) {
		[self setLoading:NO];
		if (error != nil) {
			WDAlert([self window], failure, error);
		}
	}];
}

- (IBAction)claim:(id)sender
{
	[self invoke:@"Claim" on:[self selectedTask] failure:@"Could not claim the task."];
}

- (IBAction)unclaim:(id)sender
{
	[self invoke:@"Unclaim" on:[self selectedTask] failure:@"Could not give the task back."];
}

#pragma mark Forms

- (void)showForm:(WDFormWindowController *)form
{
	[_forms addObject:form];
	form.closed = ^(WDFormWindowController *closed) {
		[self->_forms removeObject:closed];
	};
	[form showWindow:self];
}

/* The form's document and instance, read on the session's context:
 * {document, instance}, or an empty dictionary for none. */
static NSDictionary *
WDFormParts(NSString *document, id instance)
{
	if (document == nil) {
		return @{};
	}
	return @{ @"document": document, @"instance": [instance isKindOfClass:[NSString class]] ? instance : @"" };
}

- (IBAction)openTask:(id)sender
{
	NSManagedObject *task = [self selectedTask];
	if (task == nil) {
		return;
	}
	NSString *name = [task valueForKey:@"name"] ?: [task valueForKey:@"taskDefinitionKey"];
	NSManagedObjectID *taskID = [task objectID];
	[self setLoading:YES];
	[_session perform:^id(NSManagedObjectContext *context, NSError **error) {
		NSManagedObject *row = [context existingObjectWithID:taskID error:error];
		NSString *document = [[row valueForKey:@"form"] valueForKey:@"document"];
		if (row == nil) {
			return nil;
		}
		if (document == nil) {
			return @{};
		}
		id instance = [[ODataOperationCall callOfOperation:@"FormInstance" onObject:row] invoke:error];
		return instance != nil ? WDFormParts(document, instance) : nil;
	} completion:^(NSDictionary *parts, NSError *error) {
		[self setLoading:NO];
		if (parts == nil) {
			WDAlert([self window], @"Could not open the task.", error);
			return;
		}
		if ([parts count] == 0) {
			[self completeWithoutForm:task name:name];
			return;
		}
		[self openForm:parts title:name submitTitle:@"Complete" submitter:^(NSString *instance, void (^done)(NSError *)) {
			[self->_session invoke:@"SubmitForm" on:task parameters:@{ @"Instance": instance }
			            completion:^(id result, NSError *submitError) {
				done(submitError);
			}];
		}];
	}];
}

- (void)openForm:(NSDictionary *)parts title:(NSString *)title submitTitle:(NSString *)submitTitle
       submitter:(WDFormSubmitter)submitter
{
	NSError *error = nil;
	NSString *document = WDFormDocumentWithInstance([parts objectForKey:@"document"], [parts objectForKey:@"instance"], &error);
	if (document == nil) {
		WDAlert([self window], @"The form cannot be shown.", error);
		return;
	}
	[self showForm:[[WDFormWindowController alloc] initWithTitle:title document:document baseURL:[_session serviceURL]
	                                                submitTitle:submitTitle submitter:submitter]];
}

/* A task without a form is done when the user says so. */
- (void)completeWithoutForm:(NSManagedObject *)task name:(NSString *)name
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:[NSString stringWithFormat:@"Complete “%@”?", name ?: @"the task"]];
	[alert setInformativeText:@"The task has no form. Completing it lets the process go on."];
	[alert addButtonWithTitle:@"Complete"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
		if (response == NSAlertFirstButtonReturn) {
			[self invoke:@"Complete" on:task failure:@"Could not complete the task."];
		}
	}];
}

#pragma mark Starting a process

- (IBAction)startProcess:(id)sender
{
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"WFDefinitionRecord"];
	[self setLoading:YES];
	[_session fetch:fetch completion:^(NSArray *objects, NSError *error) {
		[self setLoading:NO];
		if (objects == nil) {
			WDAlert([self window], @"Could not read the processes.", error);
			return;
		}
		/* The latest version of each, which is what a key starts. */
		NSMutableDictionary *latest = [NSMutableDictionary dictionary];
		for (NSManagedObject *definition in objects) {
			NSString *key = [definition valueForKey:@"key"];
			NSManagedObject *seen = [latest objectForKey:key];
			if (seen == nil || [[seen valueForKey:@"version"] compare:[definition valueForKey:@"version"]] == NSOrderedAscending) {
				[latest setObject:definition forKey:key];
			}
		}
		[self.definitions setContent:[latest allValues]];
		[self.definitions rearrangeObjects];
		self.businessKey = @"";
		[[self window] beginSheet:self.startSheet completionHandler:nil];
	}];
}

/* NSApp's, not the window's: GNUstep runs a window's sheet modally, and
 * only NSApp ends it. */
- (void)endStartSheet
{
	[NSApp endSheet:self.startSheet];
	[self.startSheet orderOut:self];
}

- (IBAction)cancelStart:(id)sender
{
	[self endStartSheet];
}

- (IBAction)startSelectedDefinition:(id)sender
{
	NSManagedObject *definition = [[self.definitions selectedObjects] firstObject];
	if (definition == nil) {
		NSBeep();
		return;
	}
	[self.startSheet makeFirstResponder:nil];
	[self endStartSheet];
	NSString *key = [definition valueForKey:@"key"];
	NSString *definitionId = [definition valueForKey:@"definitionId"];
	NSString *title = [definition valueForKey:@"name"] ?: key;
	NSString *businessKey = [self.businessKey length] > 0 ? self.businessKey : nil;
	[self setLoading:YES];
	[_session perform:^id(NSManagedObjectContext *context, NSError **error) {
		NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"WFFormRecord"];
		[fetch setPredicate:[NSPredicate predicateWithFormat:@"definitionId == %@ AND startForm == %@",
			definitionId, @YES]];
		[fetch setFetchLimit:1];
		NSArray *forms = [context executeFetchRequest:fetch error:error];
		if (forms == nil) {
			return nil;
		}
		NSString *document = [[forms firstObject] valueForKey:@"document"];
		if (document == nil) {
			return @{};
		}
		ODataOperationCall *call = [ODataOperationCall callOfOperation:@"StartFormInstance" inContext:context];
		call.parameters = @{ @"Key": key };
		id instance = [call invoke:error];
		return instance != nil ? WDFormParts(document, instance) : nil;
	} completion:^(NSDictionary *parts, NSError *error) {
		[self setLoading:NO];
		if (parts == nil) {
			WDAlert([self window], @"Could not start the process.", error);
			return;
		}
		NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithObject:key forKey:@"Key"];
		if (businessKey != nil) {
			[parameters setObject:businessKey forKey:@"BusinessKey"];
		}
		if ([parts count] == 0) {
			[self->_session invoke:@"StartProcessInstance" on:nil parameters:parameters
			            completion:^(id result, NSError *startError) {
				if (startError != nil) {
					WDAlert([self window], @"Could not start the process.", startError);
				}
			}];
			return;
		}
		[self openForm:parts title:title submitTitle:@"Start" submitter:^(NSString *instance, void (^done)(NSError *)) {
			[parameters setObject:instance forKey:@"Instance"];
			[self->_session invoke:@"SubmitStartForm" on:nil parameters:parameters
			            completion:^(id result, NSError *submitError) {
				done(submitError);
			}];
		}];
	}];
}

@end

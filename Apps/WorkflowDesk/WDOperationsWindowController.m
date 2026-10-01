#import "WDOperationsWindowController.h"
#import "WDInterface.h"
#import "WDSession.h"

static NSSortDescriptor *
WDSort(NSString *key, BOOL ascending)
{
	return [NSSortDescriptor sortDescriptorWithKey:key ascending:ascending];
}

@implementation WDOperationsWindowController
{
	WDSession *_session;
	NSUInteger _loading;
	/* Which selection the lists below a table were read for: an answer
	 * for an older one is dropped. */
	NSUInteger _instancesRead;
	NSUInteger _detailsRead;
}

- (instancetype)initWithSession:(WDSession *)session
{
	if ((self = [super initWithWindowNibName:@"OperationsWindow"])) {
		_session = session;
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
	[[self window] setTitle:[NSString stringWithFormat:@"Operations — %@", [[_session serviceURL] host]]];
	[self.definitions setSortDescriptors:@[ WDSort(@"key", YES), WDSort(@"version", NO) ]];
	[self.instances setSortDescriptors:@[ WDSort(@"businessKey", YES), WDSort(@"executionId", YES) ]];
	[self.variables setSortDescriptors:@[ WDSort(@"name", YES) ]];
	[self.activities setSortDescriptors:@[ WDSort(@"startTime", YES) ]];
	[self.incidents setSortDescriptors:@[ WDSort(@"createdAt", NO) ]];
	[self.jobs setSortDescriptors:@[ WDSort(@"dueDate", YES) ]];
	for (NSTableView *table in @[ self.definitionsTable, self.instancesTable, self.jobsTable ]) {
		[table setDelegate:self];
	}
	/* Every table's, those in the tabs too. */
	NSMutableArray *views = [NSMutableArray arrayWithObject:[[self window] contentView]];
	while ([views count] > 0) {
		NSView *view = [views lastObject];
		[views removeLastObject];
		if ([view isKindOfClass:[NSTableView class]]) {
			WDFormatDateColumns((NSTableView *)view);
		} else if ([view isKindOfClass:[NSTabView class]]) {
			for (NSTabViewItem *item in [(NSTabView *)view tabViewItems]) {
				[views addObject:[item view]];
			}
		}
		[views addObjectsFromArray:[view subviews]];
	}
	[self refresh:self];
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

/* The rows of the entity, as the predicate picks them, into the controller. */
- (void)read:(NSString *)entity where:(NSPredicate *)predicate into:(NSArrayController *)controller
        then:(void (^)(void))then
{
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entity];
	[fetch setPredicate:predicate];
	[self setLoading:YES];
	[_session fetch:fetch completion:^(NSArray *objects, NSError *error) {
		[self setLoading:NO];
		if (objects == nil) {
			self.status = [NSString stringWithFormat:@"Could not read %@: %@", entity, [error localizedDescription]];
			objects = @[];
		}
		[controller setContent:objects];
		[controller rearrangeObjects];
		if (then != nil) {
			then();
		}
	}];
}

- (IBAction)refresh:(id)sender
{
	self.status = @"";
	[self read:@"WFDefinitionRecord" where:nil into:self.definitions then:^{
		[self selectFirstOf:self.definitions];
		[self definitionSelectionDidChange];
	}];
}

- (NSManagedObject *)selectedOf:(NSArrayController *)controller
{
	return [[controller selectedObjects] firstObject];
}

/* The first row, when none is: AppKit's controllers pick it themselves,
 * gnustep-gui's do not. */
- (void)selectFirstOf:(NSArrayController *)controller
{
	if ([[controller selectionIndexes] count] == 0 && [[controller arrangedObjects] count] > 0) {
		[controller setSelectionIndex:0];
	}
}

- (void)definitionSelectionDidChange
{
	NSManagedObject *definition = [self selectedOf:self.definitions];
	self.definitionSelected = definition != nil;
	NSUInteger read = ++_instancesRead;
	if (definition == nil) {
		[self.instances setContent:@[]];
		[self instanceSelectionDidChange];
		return;
	}
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"definitionId == %@",
		[definition valueForKey:@"definitionId"]];
	[self read:@"WFExecution" where:predicate into:self.instances then:^{
		if (read == self->_instancesRead) {
			[self selectFirstOf:self.instances];
			[self instanceSelectionDidChange];
		}
	}];
}

- (void)instanceSelectionDidChange
{
	NSManagedObject *instance = [self selectedOf:self.instances];
	self.instanceSelected = instance != nil;
	NSUInteger read = ++_detailsRead;
	NSArray *lists = @[ @[ @"WFVariable", self.variables ], @[ @"WFHistoricActivityInstance", self.activities ],
	                    @[ @"WFIncident", self.incidents ], @[ @"WFJob", self.jobs ] ];
	for (NSArray *list in lists) {
		NSArrayController *controller = [list lastObject];
		if (instance == nil) {
			[controller setContent:@[]];
			continue;
		}
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"processInstanceId == %@",
			[instance valueForKey:@"executionId"]];
		NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:[list firstObject]];
		[fetch setPredicate:predicate];
		[self setLoading:YES];
		[_session fetch:fetch completion:^(NSArray *objects, NSError *error) {
			[self setLoading:NO];
			if (read != self->_detailsRead) {
				return;
			}
			[controller setContent:objects ?: @[]];
			[controller rearrangeObjects];
			if (objects == nil) {
				self.status = [NSString stringWithFormat:@"Could not read the instance's %@.",
					[[list firstObject] substringFromIndex:2]];
			}
			[self jobSelectionDidChange];
		}];
	}
	[self jobSelectionDidChange];
}

- (void)jobSelectionDidChange
{
	self.jobSelected = [self selectedOf:self.jobs] != nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	id table = [notification object];
	if (table == self.definitionsTable) {
		[self definitionSelectionDidChange];
	} else if (table == self.instancesTable) {
		[self instanceSelectionDidChange];
	} else if (table == self.jobsTable) {
		[self jobSelectionDidChange];
	}
}

#pragma mark Actions

- (void)invoke:(NSString *)operation on:(NSManagedObject *)object parameters:(NSDictionary *)parameters
       failure:(NSString *)failure
{
	if (object == nil) {
		return;
	}
	[self setLoading:YES];
	[_session invoke:operation on:object parameters:parameters completion:^(id result, NSError *error) {
		[self setLoading:NO];
		if (error != nil) {
			WDAlert([self window], failure, error);
		}
	}];
}

- (IBAction)suspendDefinition:(id)sender
{
	[self invoke:@"Suspend" on:[self selectedOf:self.definitions] parameters:@{ @"IncludeInstances": @YES }
	     failure:@"Could not suspend the process definition."];
}

- (IBAction)activateDefinition:(id)sender
{
	[self invoke:@"Activate" on:[self selectedOf:self.definitions] parameters:@{ @"IncludeInstances": @YES }
	     failure:@"Could not resume the process definition."];
}

- (IBAction)suspendInstance:(id)sender
{
	[self invoke:@"Suspend" on:[self selectedOf:self.instances] parameters:nil
	     failure:@"Could not suspend the process instance."];
}

- (IBAction)activateInstance:(id)sender
{
	[self invoke:@"Activate" on:[self selectedOf:self.instances] parameters:nil
	     failure:@"Could not resume the process instance."];
}

- (IBAction)cancelInstance:(id)sender
{
	NSManagedObject *instance = [self selectedOf:self.instances];
	if (instance == nil) {
		return;
	}
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:[NSString stringWithFormat:@"Cancel the process instance %@?",
		[instance valueForKey:@"businessKey"] ?: [instance valueForKey:@"executionId"]]];
	[alert setInformativeText:@"It stops where it is, and its tasks and jobs go with it."];
	[alert addButtonWithTitle:@"Cancel Instance"];
	[alert addButtonWithTitle:@"Keep Running"];
	[alert beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
		if (response == NSAlertFirstButtonReturn) {
			[self invoke:@"Cancel" on:instance parameters:@{ @"Reason": @"Cancelled in WorkflowDesk" }
			     failure:@"Could not cancel the process instance."];
		}
	}];
}

- (IBAction)retryJob:(id)sender
{
	[self invoke:@"SetRetries" on:[self selectedOf:self.jobs] parameters:@{ @"Retries": @1 }
	     failure:@"Could not retry the job."];
}

- (IBAction)deploy:(id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:YES];
	[panel setCanChooseDirectories:NO];
	[panel setAllowedFileTypes:@[ @"bpmn", @"dmn", @"xhtml", @"xml", @"form" ]];
	[panel setMessage:@"Choose the BPMN, DMN and form files to deploy together."];
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	NSMutableDictionary *resources = [NSMutableDictionary dictionary];
	for (NSURL *url in [panel URLs]) {
		NSError *error = nil;
		NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
		if (text == nil) {
			WDAlert([self window], [NSString stringWithFormat:@"Could not read %@.", [url lastPathComponent]], error);
			return;
		}
		[resources setObject:text forKey:[url lastPathComponent]];
	}
	NSString *name = [[[[panel URLs] firstObject] lastPathComponent] stringByDeletingPathExtension];
	[self setLoading:YES];
	[_session invoke:@"Deploy" on:nil parameters:@{ @"Name": name ?: @"deployment", @"Resources": resources }
	      completion:^(id result, NSError *error) {
		[self setLoading:NO];
		if (error != nil) {
			WDAlert([self window], @"Could not deploy.", error);
			return;
		}
		self.status = [NSString stringWithFormat:@"Deployed %@.", result];
	}];
}

@end

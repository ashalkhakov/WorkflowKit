#import "WDOperationsWindowController.h"
#import "WDDiagramView.h"
#import "WDInterface.h"
#import "WDSession.h"
#import "WKDDiagram.h"
#import "WKDEditor.h"

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
	NSUInteger _marksRead;
	/* Each definition's diagram, by its id, once read; and the
	 * document each was read from, which its shapes need kept. */
	NSMutableDictionary<NSString *, WKDDiagram *> *_diagrams;
	NSMutableDictionary<NSString *, NSXMLDocument *> *_documents;
}

- (instancetype)initWithSession:(WDSession *)session
{
	if ((self = [super initWithWindowNibName:@"OperationsWindow"])) {
		_session = session;
		_status = @"";
		_diagrams = [NSMutableDictionary dictionary];
		_documents = [NSMutableDictionary dictionary];
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
	__weak WDOperationsWindowController *weakSelf = self;
	self.diagramView.clicked = ^(NSString *activityId) {
		[weakSelf describeActivity:activityId];
	};
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
	[_diagrams removeAllObjects];
	[_documents removeAllObjects];
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
	[self showDiagramOf:definition];
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
			if (controller == self.activities || controller == self.incidents) {
				[self markDiagram];
			}
		}];
	}
	[self jobSelectionDidChange];
	[self markDiagram];
}

#pragma mark The diagram

/* The definition's diagram: read once through its Bpmn operation, laid
 * out as the designer lays out a file without one. */
- (void)showDiagramOf:(NSManagedObject *)definition
{
	NSString *definitionId = [definition valueForKey:@"definitionId"];
	WKDDiagram *known = definitionId != nil ? [_diagrams objectForKey:definitionId] : nil;
	if (definition == nil || known != nil) {
		self.diagramView.placeholder = definition == nil ? @"No process selected." : nil;
		self.diagramView.diagram = known;
		[self markDiagram];
		return;
	}
	self.diagramView.diagram = nil;
	self.diagramView.placeholder = @"Reading the diagram…";
	[self setLoading:YES];
	[_session invoke:@"Bpmn" on:definition parameters:nil completion:^(id result, NSError *error) {
		[self setLoading:NO];
		NSXMLDocument *document = [result isKindOfClass:[NSString class]]
			? [[NSXMLDocument alloc] initWithXMLString:result options:0 error:NULL] : nil;
		if (document == nil) {
			self.diagramView.placeholder = [NSString stringWithFormat:@"Could not read the diagram: %@",
				[error localizedDescription] ?: @"the server sent no BPMN"];
			[self.diagramView setNeedsDisplay:YES];
			return;
		}
		WKDEditor *editor = [[WKDEditor alloc] initWithDocument:document undoManager:nil];
		[editor completeDiagram];
		[self->_documents setObject:editor.document forKey:definitionId];
		[self->_diagrams setObject:editor.diagram forKey:definitionId];
		if ([[[self selectedOf:self.definitions] valueForKey:@"definitionId"] isEqual:definitionId]) {
			self.diagramView.placeholder = nil;
			self.diagramView.diagram = editor.diagram;
			[self markDiagram];
		}
	}];
}

- (void)setShowsAllInstances:(BOOL)showsAllInstances
{
	_showsAllInstances = showsAllInstances;
	[self markDiagram];
}

/* Where the instance selected is on the diagram, from the activities and
 * incidents read for it; or, showing all, where every running instance of
 * the definition is, read for them. */
- (void)markDiagram
{
	NSUInteger read = ++_marksRead;
	if (!self.showsAllInstances) {
		NSCountedSet *active = [NSCountedSet set], *incidents = [NSCountedSet set];
		NSMutableSet *finished = [NSMutableSet set];
		for (NSManagedObject *activity in [self.activities arrangedObjects]) {
			NSString *activityId = [activity valueForKey:@"activityId"];
			if (activityId == nil) {
				continue;
			}
			if ([activity valueForKey:@"endTime"] == nil) {
				[active addObject:activityId];
			} else if (![[activity valueForKey:@"canceled"] boolValue]) {
				[finished addObject:activityId];
			}
		}
		for (NSManagedObject *incident in [self.incidents arrangedObjects]) {
			if ([incident valueForKey:@"activityId"] != nil) {
				[incidents addObject:[incident valueForKey:@"activityId"]];
			}
		}
		[self.diagramView setActive:active finished:finished incidents:incidents];
		return;
	}
	NSArray *ids = [[self.instances arrangedObjects] valueForKey:@"executionId"];
	if ([ids count] == 0) {
		[self.diagramView setActive:nil finished:nil incidents:nil];
		return;
	}
	NSFetchRequest *running = [NSFetchRequest fetchRequestWithEntityName:@"WFHistoricActivityInstance"];
	[running setPredicate:[NSPredicate predicateWithFormat:@"processInstanceId IN %@ AND endTime == nil", ids]];
	NSFetchRequest *failing = [NSFetchRequest fetchRequestWithEntityName:@"WFIncident"];
	[failing setPredicate:[NSPredicate predicateWithFormat:@"processInstanceId IN %@", ids]];
	[self setLoading:YES];
	[_session fetch:running completion:^(NSArray *activities, NSError *error) {
		[self->_session fetch:failing completion:^(NSArray *incidentRows, NSError *incidentError) {
			[self setLoading:NO];
			if (read != self->_marksRead) {
				return;
			}
			if (activities == nil || incidentRows == nil) {
				self.status = [NSString stringWithFormat:@"Could not read where the instances are: %@",
					[(error ?: incidentError) localizedDescription]];
			}
			NSCountedSet *active = [NSCountedSet set], *incidents = [NSCountedSet set];
			for (NSManagedObject *activity in activities ?: @[]) {
				if ([activity valueForKey:@"activityId"] != nil) {
					[active addObject:[activity valueForKey:@"activityId"]];
				}
			}
			for (NSManagedObject *incident in incidentRows ?: @[]) {
				if ([incident valueForKey:@"activityId"] != nil) {
					[incidents addObject:[incident valueForKey:@"activityId"]];
				}
			}
			[self.diagramView setActive:active finished:nil incidents:incidents];
		}];
	}];
}

/* What the diagram shows of the activity clicked, in the status line. */
- (void)describeActivity:(NSString *)activityId
{
	WKDShape *shape = [self.diagramView.diagram shapeWithId:activityId];
	if (shape == nil) {
		self.status = @"";
		return;
	}
	NSString *name = [shape.name length] > 0 ? shape.name : shape.elementId;
	NSMutableArray *parts = [NSMutableArray array];
	NSUInteger tokens = [self.diagramView.active countForObject:activityId];
	if (tokens > 0) {
		[parts addObject:self.showsAllInstances
			? [NSString stringWithFormat:@"%lu instance%@ here now", (unsigned long)tokens, tokens == 1 ? @"" : @"s"]
			: @"the instance is here now"];
	} else if ([self.diagramView.finished containsObject:activityId]) {
		[parts addObject:@"done"];
	}
	NSUInteger incidents = [self.diagramView.incidents countForObject:activityId];
	if (incidents > 0) {
		[parts addObject:[NSString stringWithFormat:@"%lu incident%@", (unsigned long)incidents, incidents == 1 ? @"" : @"s"]];
	}
	self.status = [parts count] > 0 ? [NSString stringWithFormat:@"%@: %@", name, [parts componentsJoinedByString:@", "]]
	                                : name;
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

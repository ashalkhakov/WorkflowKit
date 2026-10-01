#import "WKDServerProcessesController.h"
#import "WKDAppDelegate.h"
#import "WDSession.h"

@implementation WKDServerProcessesController
{
	WDSession *_session;
	NSInteger _loading;
}

- (instancetype)initWithSession:(WDSession *)session
{
	if ((self = [super initWithWindowNibName:@"ServerProcesses"])) {
		_session = session;
	}
	return self;
}

+ (NSSet *)keyPathsForValuesAffectingDefinitionSelected
{
	return [NSSet setWithObject:@"definitions.selectionIndexes"];
}

- (BOOL)definitionSelected
{
	return [[self.definitions selectedObjects] count] > 0;
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self.window setTitle:[NSString stringWithFormat:@"Open from %@", [_session.serviceURL host] ?: @"Server"]];
	[self.definitions setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"key" ascending:YES],
	                                        [NSSortDescriptor sortDescriptorWithKey:@"version" ascending:NO] ]];
	[self.table setTarget:self];
	[self.table setDoubleAction:@selector(open:)];
	[self.progress setHidden:YES];
}

- (void)setLoading:(BOOL)loading
{
	_loading += loading ? 1 : -1;
	/* gnustep-gui draws a stopped indicator: hidden, then. */
	[self.progress setHidden:_loading == 0];
	if (_loading > 0) {
		[self.progress startAnimation:self];
	} else {
		[self.progress stopAnimation:self];
	}
}

- (IBAction)refresh:(id)sender
{
	[self window];
	self.status = @"";
	[self setLoading:YES];
	[_session fetch:[NSFetchRequest fetchRequestWithEntityName:@"WFDefinitionRecord"]
	     completion:^(NSArray *objects, NSError *error) {
		[self setLoading:NO];
		if (objects == nil) {
			self.status = [NSString stringWithFormat:@"Could not read the definitions: %@", [error localizedDescription]];
			objects = @[];
		}
		[self.definitions setContent:objects];
		[self.definitions rearrangeObjects];
		/* AppKit's controllers select the first row themselves,
		 * gnustep-gui's do not. */
		if ([[self.definitions selectionIndexes] count] == 0 && [objects count] > 0) {
			[self.definitions setSelectionIndex:0];
		}
		if ([objects count] == 0 && error == nil) {
			self.status = @"Nothing is deployed.";
		}
	}];
}

- (IBAction)open:(id)sender
{
	NSManagedObject *definition = [[self.definitions selectedObjects] firstObject];
	if (definition == nil) {
		return;
	}
	NSString *title = [NSString stringWithFormat:@"%@ v%@", [definition valueForKey:@"key"],
	                   [definition valueForKey:@"version"]];
	self.status = [NSString stringWithFormat:@"Opening %@…", title];
	[self setLoading:YES];
	[_session invoke:@"Bpmn" on:definition parameters:nil completion:^(id result, NSError *error) {
		[self setLoading:NO];
		if (![result isKindOfClass:[NSString class]]) {
			self.status = [NSString stringWithFormat:@"Could not read %@: %@", title,
			               [error localizedDescription] ?: @"the server sent no BPMN"];
			return;
		}
		NSError *openError = nil;
		if ([[WKDAppDelegate shared] openDocumentWithXML:result title:title
		                                       resourceName:[definition valueForKey:@"resourceName"] error:&openError] == nil) {
			self.status = [NSString stringWithFormat:@"Could not open %@: %@", title, [openError localizedDescription]];
			return;
		}
		self.status = @"";
		[self close];
	}];
}

@end

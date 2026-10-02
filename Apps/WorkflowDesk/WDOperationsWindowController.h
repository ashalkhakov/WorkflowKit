#import <AppKit/AppKit.h>

@class WDSession, WDDiagramView;

/*
 * What the engine is doing: the deployed process definitions, the running
 * instances of the one selected, and of the instance selected its
 * variables, the activities it has been through, its incidents and its
 * jobs, and the definition's diagram with where the instance is on it --
 * or where all its running instances are. Each list is an
 * NSArrayController in OperationsWindow.xib; a
 * selection reads the lists below it again. The buttons suspend and
 * resume definitions and instances, cancel an instance, give a failed job
 * its retries back, and deploy files.
 */
@interface WDOperationsWindowController : NSWindowController <NSTableViewDelegate>

- (instancetype)initWithSession:(WDSession *)session;

@property (nonatomic, strong) IBOutlet NSArrayController *definitions;
@property (nonatomic, strong) IBOutlet NSArrayController *instances;
@property (nonatomic, strong) IBOutlet NSArrayController *variables;
@property (nonatomic, strong) IBOutlet NSArrayController *activities;
@property (nonatomic, strong) IBOutlet NSArrayController *incidents;
@property (nonatomic, strong) IBOutlet NSArrayController *jobs;
@property (nonatomic, strong) IBOutlet NSTableView *definitionsTable;
@property (nonatomic, strong) IBOutlet NSTableView *instancesTable;
@property (nonatomic, strong) IBOutlet NSTableView *jobsTable;
@property (nonatomic, strong) IBOutlet NSProgressIndicator *progress;
@property (nonatomic, strong) IBOutlet WDDiagramView *diagramView;
/* The diagram shows every running instance of the definition, rather than
 * the one selected. */
@property (nonatomic) BOOL showsAllInstances;

@property (nonatomic, copy) NSString *status;
@property (nonatomic) BOOL definitionSelected;
@property (nonatomic) BOOL instanceSelected;
@property (nonatomic) BOOL jobSelected;

- (IBAction)refresh:(id)sender;
- (IBAction)suspendDefinition:(id)sender;
- (IBAction)activateDefinition:(id)sender;
- (IBAction)suspendInstance:(id)sender;
- (IBAction)activateInstance:(id)sender;
- (IBAction)cancelInstance:(id)sender;
- (IBAction)retryJob:(id)sender;
- (IBAction)deploy:(id)sender;

@end

#import <AppKit/AppKit.h>
#import "WKDProcessEditor.h"

@class WKDProcessCommands;

/* What the commands need of where the editor is shown -- a window of the
 * designer, a tab of UDCode's -- and nothing else. */
@protocol WKDProcessCommandsHost <NSObject>
/* Why a command did nothing, until the next; nil: it did. */
- (void)commands:(WKDProcessCommands *)commands refused:(NSString *)reason;
- (void)commands:(WKDProcessCommands *)commands say:(NSString *)status;
- (void)commands:(WKDProcessCommands *)commands alert:(NSString *)message detail:(NSString *)detail;
/* The process's file; nil while it has none. */
- (NSURL *)documentURLForCommands:(WKDProcessCommands *)commands;
/* The files beside the process open in an editor, as they stand there, by
 * name: its forms and DMN files. */
- (NSDictionary<NSString *, NSString *> *)editedResourcesForCommands:(WKDProcessCommands *)commands;
/* A form beside the process opened in the form editor (decision nil), or
 * a DMN file in the decision editor with that decision shown, made when
 * the file does not define it. */
- (void)commands:(WKDProcessCommands *)commands open:(NSURL *)url decision:(NSString *)decision;
/* The element's name typed over it, where it is drawn. */
- (void)commands:(WKDProcessCommands *)commands rename:(NSString *)elementId;
/* The diagram laid out anew: shown from its start. */
- (void)commandsDidArrange:(WKDProcessCommands *)commands;
@end

/*
 * The Editor menu's actions on a process -- Arrange, Align and Distribute,
 * pools and lanes, Change Type, Rename, the clipboard, Edit Form and Edit
 * Decision -- on the process editor's selection, in the responder chain of
 * whoever shows it, and each one change.
 */
@interface WKDProcessCommands : NSResponder <NSUserInterfaceValidations>

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor;
@property (nonatomic, readonly, strong) WKDProcessEditor *processEditor;
@property (nonatomic, weak) id<WKDProcessCommandsHost> host;

- (IBAction)arrange:(id)sender;
- (IBAction)alignLeftEdges:(id)sender;
- (IBAction)alignCentres:(id)sender;
- (IBAction)alignRightEdges:(id)sender;
- (IBAction)alignTopEdges:(id)sender;
- (IBAction)alignMiddles:(id)sender;
- (IBAction)alignBottomEdges:(id)sender;
- (IBAction)distributeAcross:(id)sender;
- (IBAction)distributeDown:(id)sender;
/* The process in a pool of its own; a lane after the one selected, or at
 * the bottom of the pool. */
- (IBAction)addPool:(id)sender;
- (IBAction)addLane:(id)sender;
/* A Change Type item's type (its represented object), for the selected node. */
- (IBAction)changeType:(id)sender;
- (IBAction)rename:(id)sender;
/* The selection to the pasteboard as BPMN, and back as copies under ids
 * of their own, a step further down each time; Duplicate both at once. */
- (IBAction)copy:(id)sender;
- (IBAction)cut:(id)sender;
- (IBAction)paste:(id)sender;
- (IBAction)duplicate:(id)sender;
/* The selected task's or start event's embedded form, beside the process:
 * made from its fields first, and named in its form key, when there is
 * none. */
- (IBAction)editForm:(id)sender;
/* The selected business rule task's decision, from the DMN file beside the
 * process that defines it: a file of its own made for it, and named in the
 * task's decisionRef, when there is none. */
- (IBAction)editDecision:(id)sender;

/* The selected nodes, the first chosen first: what Align and Distribute
 * arrange. */
- (NSArray<NSString *> *)selectedShapes;

@end

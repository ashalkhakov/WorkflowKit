/*
 * UDCode's BPMN and DMN extension -- a process's tab
 * (WKUProcessEditor.xib): the designer's parts over a process editor of the
 * file's text, spread over the window's panes as an Xcode editor's are
 * (UDEditorPanes): the outline and the canvas in the tab; the inspectors,
 * the selected element's and the process's, tabs of the inspector pane;
 * the palette the Library; what the engine finds wrong the document's
 * issues, each at the line its element is written on.
 *
 * The text is the model. Each change made in the parts is written back as
 * one edit of the text (the lines it changed), so the text's undo undoes
 * it; saving and the tab's dot are the document's; a diff shows what
 * changed. The process editor records no undo of its own. When the text
 * changes some other way (undone, edited as text, reverted) it is read
 * again, the selection kept where it still is. A text that is no process
 * shows why, and offers it as text.
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>
#import <UDCodeKit/UDEditorPanes.h>
#import "WKDProcessCommands.h"

@class UDCodeDocument, WKDProcessEditor, WKDCanvasViewController, WKDOutlineViewController,
	WKDPaletteViewController, WKDInspectorViewController;

@interface WKUProcessEditorViewController : NSViewController <UDEditorPanes, WKDProcessCommandsHost, NSSplitViewDelegate>

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench;

@property (nonatomic, readonly, strong) UDCodeDocument *document;
/* The process editor, made for the first text that is a process; nil until then. */
@property (nonatomic, readonly, strong) WKDProcessEditor *processEditor;
/* Why the text is no process, while it is not; nil while it is. */
@property (nonatomic, readonly, copy) NSString *problem;

@property (nonatomic, readonly, strong) WKDCanvasViewController *canvasController;
@property (nonatomic, readonly, strong) WKDOutlineViewController *outlineController;
@property (nonatomic, readonly, strong) WKDPaletteViewController *paletteController;
/* The inspector pane's tabs: the selected element's, and the process's. */
@property (nonatomic, readonly, strong) WKDInspectorViewController *inspectorController;
@property (nonatomic, readonly, strong) WKDInspectorViewController *processInspectorController;
/* The Editor menu's commands, after this in the responder chain. */
@property (nonatomic, readonly, strong) WKDProcessCommands *commands;
/* What the last command refused or said, and whether the engine runs it. */
@property (nonatomic, readonly, copy) NSString *status;

/* The text written now, if a change is waiting (it is written as the event
 * that made it ends). */
- (void)write;

/* The canvas's zoom (the Editor menu's, WKUEditorMenus.xib). */
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)actualSize:(id)sender;
- (IBAction)zoomToFit:(id)sender;
/* The document's text's undo, which every change of the process is part of. */
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
/* The document in a tab of its own, as XML. */
- (IBAction)showAsText:(id)sender;

@end

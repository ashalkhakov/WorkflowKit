#import <Foundation/Foundation.h>
#import "WKDEditor.h"
#import "WKDSelection.h"

@class WFProblem;

/* Posted, by the process editor, after every change to the process, undo
 * and redo included, once the selection has followed it. */
extern NSString * const WKDProcessEditorDidChangeNotification;
/* Posted, by the process editor, when what the engine finds wrong changes. */
extern NSString * const WKDProcessEditorProblemsDidChangeNotification;

/*
 * One process being edited: its text read into an editor and written back,
 * one change at a time; what is selected in it; and what the engine finds
 * wrong with it, checked again a moment after each change. What the
 * designer's parts -- the canvas, the outline, the inspector, the problems
 * -- share, each knowing this and nothing of the others.
 */
@interface WKDProcessEditor : NSObject

/* The process the text holds, on the undo manager (nil: none); nil, with
 * why, for text that holds no BPMN process. One without a diagram is laid
 * out, a change to save (laidOut). */
- (instancetype)initWithData:(NSData *)data undoManager:(NSUndoManager *)undoManager error:(NSError **)error;
/* A new executable process with a start event. */
- (instancetype)initNewProcessWithUndoManager:(NSUndoManager *)undoManager;

@property (nonatomic, readonly, strong) WKDEditor *editor;
@property (nonatomic, readonly, strong) WKDSelection *selection;
/* The process was laid out as it was read: it has changed. */
@property (nonatomic, readonly) BOOL laidOut;

/* The text, as it is now. */
- (NSData *)data;

/* What the process is checked as: a deployment of the file under its
 * name (process.bpmn when nil) with what the block gives -- the forms and
 * decisions beside it -- as deploying it would be. */
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSDictionary<NSString *, NSData *> *(^resourcesBeside)(void);
/* What the engine finds wrong, in the file's order; empty when nothing. */
@property (nonatomic, readonly, copy) NSArray<WFProblem *> *problems;
/* The first problem's message, or nil: what a status line says. */
@property (nonatomic, readonly, copy) NSString *problem;
/* Checked now, rather than a moment after the last change. */
- (void)checkNow;

@end

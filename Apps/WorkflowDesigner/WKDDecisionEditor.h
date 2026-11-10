#import <Foundation/Foundation.h>
#import "WKDDecisions.h"

@class WFProblem;

/* Posted, by the decision editor, after every change to the decisions,
 * undo and redo included, once what is chosen has followed it. */
extern NSString * const WKDDecisionEditorDidChangeNotification;
/* Posted, by the decision editor, when another decision or column is
 * chosen. */
extern NSString * const WKDDecisionEditorChoiceDidChangeNotification;
/* Posted, by the decision editor, when what the engine finds wrong changes. */
extern NSString * const WKDDecisionEditorProblemsDidChangeNotification;

/*
 * One DMN file being edited: its text read into a WKDDmnEditor and written
 * back, one change at a time; the decision chosen and the column of its
 * table chosen; and what the engine finds wrong with it, checked again a
 * moment after each change. What the decision editor's parts -- the list,
 * the detail, the grid, the column, the literal expression -- share.
 */
@interface WKDDecisionEditor : NSObject

/* The decisions the text holds, on the undo manager (nil: none); nil, with
 * why, for text that is not DMN. */
- (instancetype)initWithData:(NSData *)data undoManager:(NSUndoManager *)undoManager error:(NSError **)error;
/* A new file with one decision table. */
- (instancetype)initNewWithUndoManager:(NSUndoManager *)undoManager;

@property (nonatomic, readonly, strong) WKDDmnEditor *editor;
- (NSData *)data;

/* The text read again, after it changed some other way -- undone in, or
 * typed into, a text it is the model of: the decisions anew, on the same
 * undo manager, what is chosen kept where it still is, and a change
 * posted. NO, with why, for text that is not DMN: nothing changes then. */
- (BOOL)readData:(NSData *)data error:(NSError **)error;

/* The decision chosen, kept to one the file has: after one goes, its
 * neighbour; after one is renamed, it under its new id. */
@property (nonatomic, copy) NSString *decisionId;
@property (nonatomic, readonly, strong) WKDDmnDecision *decision;
/* The column of its table chosen, among its columns; NSNotFound for none. */
@property (nonatomic) NSUInteger column;

/* What the file is checked as: a deployment of it under its name
 * (decisions.dmn when nil). */
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, readonly, copy) NSArray<WFProblem *> *problems;
/* The first problem's message, or nil. */
@property (nonatomic, readonly, copy) NSString *problem;
- (void)checkNow;

@end

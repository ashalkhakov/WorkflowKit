/*
 * UDCode's BPMN and DMN extension -- the edits that turn a document's text
 * into the text an editor wrote: one for each run of lines that differs
 * (UDPieceTable's line diff, VS Code's), made together, so they are one
 * step of the text's undo and a diff of the file shows the lines a change
 * touched. As FreeCoreData's extension makes them (MBUTextEdits).
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import <Foundation/Foundation.h>
#import <UDPieceTable/UDTextModel.h>

/* The edits that make `model`'s text `text`; none when it is that already. */
NSArray<UDTextModelEdit *> *WKUEditsToText(UDTextModel *model, NSString *text);

/* `model`'s text made `text`, as one edit of it; NO when it was that already. */
BOOL WKUWriteText(UDTextModel *model, NSString *text);

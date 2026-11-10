/*
 * UDCode's BPMN and DMN extension -- the text edits (see WKUTextEdits.h).
 *
 * Copyright (C) 2026 the WorkflowKit contributors. GNU LGPL 2.1.
 */
#import "WKUTextEdits.h"
#import <UDPieceTable/UDLinesDiffComputer.h>

/* Where each line of `lines` (a text cut at its line feeds) starts, as if
 * the text ended in a line feed too: then every line ends in one, and the
 * last's ends one past the text, where the next would start. */
static NSArray<NSNumber *> *
WKULineStarts(NSArray<NSString *> *lines)
{
	NSMutableArray *starts = [NSMutableArray arrayWithCapacity:[lines count] + 1];
	NSUInteger offset = 0;
	for (NSString *line in lines) {
		[starts addObject:@(offset)];
		offset += [line length] + 1;
	}
	[starts addObject:@(offset)];
	return starts;
}

/* The offset of a line number (1-based); one past the last line, past the
 * text and its imagined last line feed. */
static NSUInteger
WKUOffsetOfLine(NSArray<NSNumber *> *starts, NSInteger line)
{
	NSInteger index = MAX(0, MIN((NSInteger)[starts count] - 1, line - 1));
	return [starts[(NSUInteger)index] unsignedIntegerValue];
}

NSArray<UDTextModelEdit *> *
WKUEditsToText(UDTextModel *model, NSString *text)
{
	NSString *old = [model getValue] ?: @"";
	if ([old isEqualToString:text]) {
		return @[];
	}
	NSArray *oldLines = [old componentsSeparatedByString:@"\n"];
	NSArray *newLines = [text componentsSeparatedByString:@"\n"];
	UDLinesDiff *diff = [UDLinesDiffComputer diffOfOriginalLines:oldLines
	                                               modifiedLines:newLines
	                                        ignoreTrimWhitespace:NO
	                                          maxComputationTime:0];
	NSArray *oldStarts = WKULineStarts(oldLines), *newStarts = WKULineStarts(newLines);
	NSUInteger length = [old length];
	NSMutableArray *edits = [NSMutableArray array];
	for (UDDetailedLineRangeMapping *change in diff.changes) {
		NSUInteger from = WKUOffsetOfLine(oldStarts, change.original.startLineNumber);
		NSUInteger to = WKUOffsetOfLine(oldStarts, change.original.endLineNumberExclusive);
		NSUInteger newFrom = WKUOffsetOfLine(newStarts, change.modified.startLineNumber);
		NSUInteger newTo = WKUOffsetOfLine(newStarts, change.modified.endLineNumberExclusive);
		/* The lines as the texts would be with their imagined line feeds. */
		NSString *lines = [[text stringByAppendingString:@"\n"] substringWithRange:NSMakeRange(newFrom, newTo - newFrom)];
		if (to > length) {
			/* Lines that end the text, which ends with no line feed of its
			 * own: the new lines' last feed is the imagined one; with no new
			 * lines, the feed before the old ones goes with them. */
			if ([lines length] > 0) {
				lines = [lines substringToIndex:[lines length] - 1];
				if (from > length) {
					lines = [@"\n" stringByAppendingString:lines];
				}
			} else if (from > 0) {
				from -= 1;
			}
			from = MIN(from, length);
			to = length;
		}
		UDPosition start = [model getPositionAt:(NSInteger)from];
		UDPosition end = [model getPositionAt:(NSInteger)to];
		UDRange range = { start.line, start.column, end.line, end.column };
		[edits addObject:[[UDTextModelEdit alloc] initWithRange:range text:lines]];
	}
	return edits;
}

BOOL
WKUWriteText(UDTextModel *model, NSString *text)
{
	NSArray *edits = WKUEditsToText(model, text);
	if ([edits count] == 0) {
		return NO;
	}
	[model applyEdits:edits];
	return YES;
}

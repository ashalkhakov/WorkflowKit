#import "WKDInspectorViewController.h"
#import "WKDInspectorRow.h"
#import "WKDTableModel.h"
#import "WKDXML.h"

@implementation WKDInspectorStack

- (BOOL)isFlipped
{
	return YES;
}

@end

/* The sections' titles and labels: whether the rows still fit. */
static NSString *
WKDShapeOf(NSArray<WKDSection *> *sections)
{
	NSMutableArray *parts = [NSMutableArray array];
	for (WKDSection *section in sections) {
		[parts addObject:section.title];
		for (WKDProperty *property in section.properties) {
			[parts addObject:property.label];
		}
	}
	return [parts componentsJoinedByString:@"|"];
}

@implementation WKDInspectorViewController
{
	NSMutableArray<WKDInspectorRow *> *_rows;
	NSString *_shape;
}

- (instancetype)initWithProcessEditor:(WKDProcessEditor *)processEditor showingProcess:(BOOL)process
{
	if ((self = [super initWithNibName:@"WKDInspector" bundle:[NSBundle bundleForClass:[WKDInspectorViewController class]]])) {
		_processEditor = processEditor;
		_showingProcess = process;
		_rows = [NSMutableArray array];
		_models = @[];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self clear];
}

- (void)loadView
{
	[super loadView];
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(processDidChange:) name:WKDProcessEditorDidChangeNotification
	             object:_processEditor];
	if (!_showingProcess) {
		[center addObserver:self selector:@selector(selectionDidChange:) name:WKDSelectionDidChangeNotification
		             object:_processEditor.selection];
	}
	[self show];
}

- (WKDEditor *)editor
{
	return _processEditor.editor;
}

/* The element to show now. */
- (NSString *)wantedId
{
	if (_showingProcess) {
		return WKDAttribute([self editor].model.process, @"id");
	}
	NSArray *selected = _processEditor.selection.selectedIds;
	return [selected count] == 1 ? [selected firstObject] : nil;
}

#pragma mark Following the process

- (void)processDidChange:(NSNotification *)notification
{
	[self show];
}

- (void)selectionDidChange:(NSNotification *)notification
{
	[self show];
}

- (void)show
{
	NSString *elementId = [self wantedId];
	NSArray *sections = elementId != nil ? WKDSectionsFor([self editor], elementId) : @[];
	NSString *shape = WKDShapeOf(sections);
	if (![shape isEqualToString:_shape] || ![elementId isEqualToString:_elementId ?: @""]
	    || (elementId == nil) != (_elementId == nil)) {
		_shape = shape;
		_elementId = [elementId copy];
		[self build:sections];
		return;
	}
	for (WKDElementModel *model in _models) {
		[model reload];
	}
}

#pragma mark The rows

- (void)clear
{
	for (WKDInspectorRow *row in _rows) {
		[row unbind];
		[row.view removeFromSuperview];
	}
	[_rows removeAllObjects];
}

- (void)build:(NSArray<WKDSection *> *)sections
{
	[self clear];
	__weak WKDInspectorViewController *weakSelf = self;
	void (^refused)(NSString *) = ^(NSString *reason) {
		if (reason != nil) {
			NSBeep();
		}
		if (weakSelf.refused != nil) {
			weakSelf.refused(reason);
		}
	};
	void (^explained)(NSString *) = ^(NSString *problem) {
		if (weakSelf.explained != nil) {
			weakSelf.explained(problem);
		}
	};
	NSMutableArray *models = [NSMutableArray array];
	if ([sections count] == 0) {
		WKDInspectorRow *nothing = [WKDInspectorRow titleRow:_showingProcess ? @"No process" : @"Nothing selected"];
		[nothing.label setTextColor:[NSColor secondaryLabelColor]];
		[nothing.label setAlignment:NSTextAlignmentCenter];
		if (nothing != nil) {
			[_rows addObject:nothing];
		}
	}
	for (WKDSection *section in sections) {
		WKDElementModel *model = [[WKDElementModel alloc] initWithEditor:[self editor] elementId:_elementId section:section];
		model.refused = refused;
		for (NSString *key in model.keys) {
			[model tableModelForKey:key].refused = refused;
		}
		[models addObject:model];
		WKDInspectorRow *title = [WKDInspectorRow titleRow:section.title];
		if (title != nil) {
			[_rows addObject:title];
		}
		for (WKDProperty *property in section.properties) {
			WKDInspectorRow *row = [WKDInspectorRow rowForProperty:property model:model];
			row.explained = explained;
			if (row != nil) {
				[_rows addObject:row];
			}
		}
	}
	_models = models;
	[self layOut];
}

- (void)layOut
{
	double width = NSWidth([[[self.stack enclosingScrollView] contentView] bounds]);
	width = MAX(width, 220);
	double y = 4;
	for (WKDInspectorRow *row in _rows) {
		NSView *view = row.view;
		[view setFrame:NSMakeRect(0, y, width, NSHeight([view frame]))];
		[view setAutoresizingMask:NSViewWidthSizable];
		[self.stack addSubview:view];
		y += NSHeight([view frame]);
	}
	[self.stack setFrameSize:NSMakeSize(width, y + 10)];
	[self.stack setNeedsDisplay:YES];
}

@end

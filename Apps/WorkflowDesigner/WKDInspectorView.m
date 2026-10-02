#import "WKDInspectorView.h"
#import "WKDEditor.h"
#import "WKDExpressionField.h"
#import "WKDTableEditor.h"
#import "WKDProperties.h"

static const double WKDLabelWidth = 104;
static const double WKDGap = 6;

@interface WKDInspectorView () <NSTextViewDelegate>
@end

@implementation WKDInspectorView
{
	NSArray<WKDSection *> *_sections;
	/* What the rows were made for: the sections' titles and labels. */
	NSString *_shape;
	NSString *_shapeOf;
	NSMutableArray<WKDProperty *> *_properties;
	NSMutableArray *_controls;
}

- (BOOL)isFlipped
{
	return YES;
}

- (void)setElementId:(NSString *)elementId
{
	_elementId = [elementId copy];
	[self reload];
}

/* The sections' titles and labels, to know when the rows still fit. */
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

- (void)reload
{
	_sections = self.editor != nil && self.elementId != nil ? WKDSectionsFor(self.editor, self.elementId) : @[];
	NSString *shape = WKDShapeOf(_sections);
	if (![shape isEqualToString:_shape] || ![self.elementId isEqualToString:_shapeOf]) {
		_shape = shape;
		_shapeOf = self.elementId;
		[self build];
	}
	[self fill];
}

#pragma mark Rows

- (NSTextField *)label:(NSString *)text bold:(BOOL)bold frame:(NSRect)frame
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	[label setStringValue:text];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBordered:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setAlignment:bold ? NSTextAlignmentLeft : NSTextAlignmentRight];
	[label setFont:bold ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:11]];
	[label setTextColor:bold ? [NSColor textColor] : [NSColor secondaryLabelColor]];
	return label;
}

- (void)build
{
	for (NSView *view in [[self subviews] copy]) {
		[view removeFromSuperview];
	}
	_properties = [NSMutableArray array];
	_controls = [NSMutableArray array];
	double width = MAX(220, NSWidth([self frame]));
	double fieldX = 12 + WKDLabelWidth + WKDGap, fieldWidth = width - fieldX - 12;
	double y = 10;
	if ([_sections count] == 0) {
		NSTextField *nothing = [self label:@"Nothing selected" bold:NO frame:NSMakeRect(12, y, width - 24, 18)];
		[nothing setAlignment:NSTextAlignmentCenter];
		[nothing setAutoresizingMask:NSViewWidthSizable];
		[self addSubview:nothing];
		y += 30;
	}
	for (WKDSection *section in _sections) {
		NSTextField *title = [self label:section.title bold:YES frame:NSMakeRect(12, y, width - 24, 18)];
		[title setAutoresizingMask:NSViewWidthSizable];
		[self addSubview:title];
		y += 24;
		for (WKDProperty *property in section.properties) {
			NSView *control = nil;
			double height = 22;
			switch (property.kind) {
			case WKDPropertyTable: {
				/* The width of the pane, under its name. */
				NSTextField *title = [self label:property.label bold:NO frame:NSMakeRect(12, y, width - 24, 16)];
				[title setAlignment:NSTextAlignmentLeft];
				[title setAutoresizingMask:NSViewWidthSizable];
				[self addSubview:title];
				y += 18;
				height = [WKDTableEditor heightFor:property];
				WKDTableEditor *table = [[WKDTableEditor alloc] initWithFrame:NSMakeRect(12, y, width - 24, height)
				                                                     property:property];
				table.editor = self.editor;
				table.refused = self.refused;
				table.explained = self.explained;
				control = table;
				break;
			}
			case WKDPropertyCheck: {
				NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 18)];
				[box setButtonType:NSButtonTypeSwitch];
				[box setTitle:property.label];
				[box setFont:[NSFont systemFontOfSize:11]];
				[box setTarget:self];
				[box setAction:@selector(changed:)];
				control = box;
				height = 18;
				break;
			}
			case WKDPropertyChoice: {
				NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX - 2, y - 1, fieldWidth + 4, 24)
				                                                  pullsDown:NO];
				[popup addItemsWithTitles:property.titles];
				[popup setFont:[NSFont systemFontOfSize:11]];
				[popup setTarget:self];
				[popup setAction:@selector(changed:)];
				control = popup;
				break;
			}
			case WKDPropertyLongText: {
				height = 64;
				NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, height)];
				[scroll setBorderType:NSBezelBorder];
				[scroll setHasVerticalScroller:YES];
				NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, [scroll contentSize].width,
				                                                                 [scroll contentSize].height)];
				[text setFont:[NSFont systemFontOfSize:11]];
				[text setRichText:NO];
				[text setAutoresizingMask:NSViewWidthSizable];
				[text setDelegate:self];
				[scroll setDocumentView:text];
				[scroll setAutoresizingMask:NSViewWidthSizable];
				[self addSubview:scroll];
				control = text;
				break;
			}
			default: {
				if (property.holdsExpression) {
					/* Coloured, and checked as it is typed, as the engine
					 * reads it there. */
					WKDExpressionField *field = [[WKDExpressionField alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 22)];
					field.place = property.place;
					field.placeholderString = property.placeholder;
					field.delegate = self;
					field.target = self;
					field.action = @selector(changed:);
					control = field;
					break;
				}
				NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 22)];
				[field setFont:[NSFont systemFontOfSize:11]];
				[[field cell] setPlaceholderString:property.placeholder];
				[[field cell] setScrollable:YES];
				[[field cell] setSendsActionOnEndEditing:YES];
				[field setTarget:self];
				[field setAction:@selector(changed:)];
				control = field;
				break;
			}
			}
			if (property.kind != WKDPropertyCheck && property.kind != WKDPropertyTable) {
				[self addSubview:[self label:property.label bold:NO frame:NSMakeRect(12, y + 3, WKDLabelWidth, 16)]];
			}
			if (property.kind != WKDPropertyLongText) {
				[control setAutoresizingMask:NSViewWidthSizable];
				[self addSubview:control];
			}
			[_properties addObject:property];
			[_controls addObject:control];
			y += height + WKDGap;
		}
		y += 8;
	}
	[self setFrameSize:NSMakeSize(width, y + 10)];
	[self setNeedsDisplay:YES];
}

/* The control being typed in: a field's editor is the first responder. */
- (BOOL)isEditing:(id)control
{
	if ([control isKindOfClass:[WKDTableEditor class]]) {
		return [(WKDTableEditor *)control isEditing];
	}
	id responder = [[self window] firstResponder];
	if (responder == control) {
		return YES;
	}
	return [responder isKindOfClass:[NSText class]] && [(NSText *)responder delegate] == control;
}

- (void)fill
{
	for (NSUInteger i = 0; i < [_controls count]; i++) {
		id control = [_controls objectAtIndex:i];
		if ([self isEditing:control]) {
			continue;
		}
		WKDProperty *property = [_properties objectAtIndex:i];
		if (property.kind == WKDPropertyTable) {
			WKDTableEditor *table = control;
			table.editor = self.editor;
			table.elementId = self.elementId;
			[table reload];
			continue;
		}
		NSString *value = [property valueIn:self.editor of:self.elementId] ?: @"";
		switch (property.kind) {
		case WKDPropertyCheck:
			[(NSButton *)control setState:[value isEqualToString:@"true"] ? NSControlStateValueOn : NSControlStateValueOff];
			break;
		case WKDPropertyChoice: {
			NSUInteger index = [property.values indexOfObject:value];
			[(NSPopUpButton *)control selectItemAtIndex:index == NSNotFound ? 0 : (NSInteger)index];
			break;
		}
		case WKDPropertyLongText:
			[(NSTextView *)control setString:value];
			break;
		default:
			[(id)control setStringValue:value];
			break;
		}
	}
}

#pragma mark Writing

- (void)write:(id)control
{
	NSUInteger index = [_controls indexOfObjectIdenticalTo:control];
	if (index == NSNotFound || self.elementId == nil) {
		return;
	}
	WKDProperty *property = [_properties objectAtIndex:index];
	NSString *value;
	switch (property.kind) {
	case WKDPropertyCheck:
		value = [(NSButton *)control state] == NSControlStateValueOn ? @"true" : @"false";
		break;
	case WKDPropertyChoice:
		value = [property.values objectAtIndex:MAX(0, [(NSPopUpButton *)control indexOfSelectedItem])];
		break;
	case WKDPropertyLongText:
		value = [[(NSTextView *)control string] copy];
		break;
	default:
		value = [(id)control stringValue];
		break;
	}
	if ([control isKindOfClass:[WKDExpressionField class]] && self.explained != nil) {
		self.explained(nil);
	}
	NSString *elementId = self.elementId;
	/* A new id: the element is the same one under it, from the change on,
	 * which reloads this view while it is made. */
	BOOL renaming = [property.label isEqualToString:@"Id"] && ![value isEqualToString:elementId];
	if (renaming) {
		_elementId = [value copy];
		_shapeOf = _elementId;
	}
	NSString *reason = nil;
	if (![property setValue:value in:self.editor of:elementId error:&reason]) {
		if (renaming) {
			_elementId = [elementId copy];
			_shapeOf = _elementId;
		}
		if (self.refused != nil) {
			self.refused(reason);
		}
	}
	[self fill];
}

- (void)changed:(id)sender
{
	[self write:sender];
}

- (void)textDidEndEditing:(NSNotification *)notification
{
	[self write:[notification object]];
}

/* An expression being typed: what the engine says of it, while it does. */
- (void)controlTextDidChange:(NSNotification *)notification
{
	WKDExpressionField *field = [notification object];
	if (![field isKindOfClass:[WKDExpressionField class]] || self.explained == nil) {
		return;
	}
	NSUInteger index = [_controls indexOfObjectIdenticalTo:field];
	NSString *label = index != NSNotFound ? [[_properties objectAtIndex:index] label] : nil;
	self.explained(field.problem != nil ? [NSString stringWithFormat:@"%@: %@", label ?: @"Expression", field.problem] : nil);
}

@end

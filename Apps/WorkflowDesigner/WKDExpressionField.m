#import "WKDExpressionField.h"

/* A system colour on macOS, keeping its contrast in a dark appearance; a
 * fixed one on GNUstep. */
static NSColor *
WKDSystemColor(NSString *name, CGFloat r, CGFloat g, CGFloat b)
{
#if defined(__APPLE__)
	SEL selector = NSSelectorFromString(name);
	if ([NSColor respondsToSelector:selector]) {
		NSColor *(*colour)(id, SEL) = (NSColor *(*)(id, SEL))[NSColor methodForSelector:selector];
		NSColor *found = colour([NSColor class], selector);
		if (found != nil) {
			return found;
		}
	}
#endif
	/* gnustep-gui's system colours are pale on a white field, and it has
	 * no dark appearance to keep contrast in. */
	return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1];
}

NSColor *
WKDExpressionTokenColor(NSString *kind)
{
	if ([kind isEqualToString:WFExpressionTokenString]) {
		return WKDSystemColor(@"systemRedColor", 0.77, 0.10, 0.09);
	}
	if ([kind isEqualToString:WFExpressionTokenNumber]) {
		return WKDSystemColor(@"systemBlueColor", 0.11, 0.00, 0.81);
	}
	if ([kind isEqualToString:WFExpressionTokenTemporal]) {
		return WKDSystemColor(@"systemTealColor", 0.00, 0.46, 0.54);
	}
	if ([kind isEqualToString:WFExpressionTokenFunction]) {
		return WKDSystemColor(@"systemPurpleColor", 0.42, 0.13, 0.66);
	}
	if ([kind isEqualToString:WFExpressionTokenKeyword]) {
		return WKDSystemColor(@"systemPinkColor", 0.61, 0.14, 0.58);
	}
	if ([kind isEqualToString:WFExpressionTokenOperator]) {
		return WKDSystemColor(@"systemOrangeColor", 0.64, 0.35, 0.00);
	}
	if ([kind isEqualToString:WFExpressionTokenComment]) {
		return WKDSystemColor(@"systemGreenColor", 0.20, 0.50, 0.20);
	}
	if ([kind isEqualToString:WFExpressionTokenPunctuation] || [kind isEqualToString:WFExpressionTokenDelimiter]) {
		return [NSColor disabledControlTextColor];
	}
	if ([kind isEqualToString:WFExpressionTokenInvalid]) {
		return [NSColor redColor];
	}
	return [NSColor controlTextColor];
}

@implementation WKDExpressionTextStorage
{
	/* NSTextStorage is abstract: the text lives here, behind the four
	 * primitives. */
	NSMutableAttributedString *_backing;
	BOOL _colouring;
}

+ (instancetype)installedInTextView:(NSTextView *)view
{
	NSLayoutManager *layout = [view layoutManager];
	if (layout == nil) {
		return nil;
	}
	WKDExpressionTextStorage *storage = [[self alloc] init];
	[storage replaceCharactersInRange:NSMakeRange(0, 0) withString:[[view textStorage] string] ?: @""];
	[layout replaceTextStorage:storage];
	return [view textStorage] == storage ? storage : nil;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_backing = [[NSMutableAttributedString alloc] init];
		_problemRange = NSMakeRange(NSNotFound, 0);
		_baseAttributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:11],
		                     NSForegroundColorAttributeName: [NSColor controlTextColor] };
	}
	return self;
}

- (NSString *)string
{
	return [_backing string];
}

- (NSDictionary<NSString *, id> *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range
{
	return [_backing attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
	[_backing replaceCharactersInRange:range withString:string];
	[self edited:NSTextStorageEditedCharacters range:range
	  changeInLength:(NSInteger)[string length] - (NSInteger)range.length];
}

- (void)setAttributes:(NSDictionary<NSString *, id> *)attributes range:(NSRange)range
{
	[_backing setAttributes:attributes range:range];
	[self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

- (void)setBaseAttributes:(NSDictionary<NSString *, id> *)baseAttributes
{
	_baseAttributes = [baseAttributes copy];
	[self recolour];
}

- (void)setPlace:(WFExpressionPlace)place
{
	_place = place;
	[self recolour];
}

- (void)setProblemRange:(NSRange)problemRange
{
	_problemRange = problemRange;
	[self recolour];
}

/* The whole text each time: a quote or a bracket typed changes what all
 * the text after it is, and an expression is a line long. */
- (void)recolour
{
	NSUInteger length = [_backing length];
	if (_colouring || length == 0) {
		return;
	}
	_colouring = YES;
	[self beginEditing];
	[self setAttributes:_baseAttributes range:NSMakeRange(0, length)];
	for (NSDictionary *token in [WFFeelExpression tokensOfText:[_backing string] place:_place]) {
		NSRange range = [[token objectForKey:@"range"] rangeValue];
		if (NSMaxRange(range) <= length) {
			[self addAttribute:NSForegroundColorAttributeName
			             value:WKDExpressionTokenColor([token objectForKey:@"kind"]) range:range];
		}
	}
	if (_problemRange.location != NSNotFound) {
		/* At the end, nothing to underline: the last character, then. */
		NSRange range = _problemRange;
		if (NSMaxRange(range) > length) {
			range = NSMakeRange(length - 1, 1);
		}
		if (range.length == 0) {
			range = NSMakeRange(MIN(range.location, length - 1), 1);
		}
		[self addAttributes:@{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleThick),
		                       NSUnderlineColorAttributeName: [NSColor redColor],
		                       NSBackgroundColorAttributeName: [[NSColor redColor] colorWithAlphaComponent:0.15] }
		              range:range];
	}
	[self endEditing];
	_colouring = NO;
}

/* The mask before super clears it; the flag in -recolour because setting
 * attributes is itself an edit, which comes round again. */
- (void)processEditing
{
	NSUInteger mask = [self editedMask];
	[super processEditing];
	if ((mask & NSTextStorageEditedCharacters) != 0) {
		[self recolour];
	}
}

@end

@interface WKDExpressionField () <NSTextViewDelegate>
@end

NSAttributedString *
WKDColouredExpression(NSString *text, WFExpressionPlace place, NSFont *font)
{
	text = text ?: @"";
	NSMutableAttributedString *coloured = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
		NSFontAttributeName: font,
		NSForegroundColorAttributeName: [NSColor controlTextColor] }];
	for (NSDictionary *token in [WFFeelExpression tokensOfText:text place:place]) {
		NSRange range = [[token objectForKey:@"range"] rangeValue];
		if (NSMaxRange(range) <= [text length]) {
			[coloured addAttribute:NSForegroundColorAttributeName
			                 value:WKDExpressionTokenColor([token objectForKey:@"kind"]) range:range];
		}
	}
	NSError *problem = [WFFeelExpression problemInText:text place:place];
	if (problem != nil && [text length] > 0) {
		NSRange range = [[[problem userInfo] objectForKey:WFErrorRangeKey] rangeValue];
		range = NSIntersectionRange(range.length > 0 ? range : NSMakeRange(range.location, 1), NSMakeRange(0, [text length]));
		[coloured addAttributes:@{ NSUnderlineStyleAttributeName: @(NSUnderlineStyleThick),
		                           NSUnderlineColorAttributeName: [NSColor redColor] } range:range];
	}
	return coloured;
}

@implementation WKDExpressionField
{
	NSScrollView *_scroll;
	NSTextView *_textView;
	WKDExpressionTextStorage *_storage;
	NSFont *_font;
}

@dynamic stringValue;

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		[self build];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	if ((self = [super initWithCoder:coder])) {
		[self build];
	}
	return self;
}

- (void)build
{
	_font = [NSFont systemFontOfSize:11];
	_scroll = [[NSScrollView alloc] initWithFrame:[self bounds]];
	[_scroll setBorderType:NSBezelBorder];
	[_scroll setHasVerticalScroller:NO];
	[_scroll setHasHorizontalScroller:NO];
	[_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[_scroll setDrawsBackground:YES];
	NSRect inner = [[_scroll contentView] bounds];
	_textView = [[NSTextView alloc] initWithFrame:inner];
	/* A field's behaviour: Return and Tab leave it; no rich text pasted
	 * over the colours. */
	[_textView setFieldEditor:YES];
	[_textView setRichText:NO];
	[_textView setImportsGraphics:NO];
	[_textView setAllowsUndo:YES];
	[_textView setHorizontallyResizable:YES];
	[_textView setVerticallyResizable:NO];
	[[_textView textContainer] setWidthTracksTextView:NO];
	[[_textView textContainer] setContainerSize:NSMakeSize(1.0e7, inner.size.height)];
	[_textView setTextContainerInset:NSMakeSize(1, 3)];
	[_textView setDelegate:self];
	[_textView setFont:_font];
	[_scroll setDocumentView:_textView];
	[self addSubview:_scroll];
	_storage = [WKDExpressionTextStorage installedInTextView:_textView];
	[self applyBaseAttributes];
}

- (NSTextView *)textView
{
	return _textView;
}

- (void)applyBaseAttributes
{
	_storage.baseAttributes = @{ NSFontAttributeName: _font ?: [NSFont systemFontOfSize:11],
	                             NSForegroundColorAttributeName: [NSColor controlTextColor] };
}

- (NSString *)stringValue
{
	return [[_textView string] copy] ?: @"";
}

- (void)setStringValue:(NSString *)value
{
	NSString *text = value ?: @"";
	if (![[_textView string] isEqualToString:text]) {
		/* Through the storage, so it colours as typing would. */
		[_storage replaceCharactersInRange:NSMakeRange(0, [_storage length]) withString:text];
	}
	[self check];
	[self setNeedsDisplay:YES];
}

- (void)setPlace:(WFExpressionPlace)place
{
	_place = place;
	_storage.place = place;
	[self check];
}

/* What the engine says of the text now. */
- (void)check
{
	NSError *error = [WFFeelExpression problemInText:[_textView string] place:_place];
	_problem = [[error localizedDescription] copy];
	NSValue *range = [[error userInfo] objectForKey:WFErrorRangeKey];
	_storage.problemRange = error == nil ? NSMakeRange(NSNotFound, 0)
		: range != nil ? [range rangeValue] : NSMakeRange(0, [[_textView string] length]);
	[_textView setToolTip:_problem];
	[self setToolTip:_problem];
}

- (void)setFont:(NSFont *)font
{
	_font = font;
	[_textView setFont:font];
	[self applyBaseAttributes];
}

- (void)setEnabled:(BOOL)enabled
{
	[_textView setEditable:enabled];
	[_textView setSelectable:YES];
	[_scroll setBackgroundColor:enabled ? [NSColor textBackgroundColor] : [NSColor controlBackgroundColor]];
}

- (void)setPlaceholderString:(NSString *)placeholderString
{
	_placeholderString = [placeholderString copy];
	[self setNeedsDisplay:YES];
}

/* A text view has no placeholder of its own: drawn over it while empty. */
- (void)drawRect:(NSRect)dirty
{
	[super drawRect:dirty];
	if ([_placeholderString length] == 0 || [[_textView string] length] > 0) {
		return;
	}
	NSDictionary *attributes = @{ NSFontAttributeName: _font ?: [NSFont systemFontOfSize:11],
	                              NSForegroundColorAttributeName: [NSColor disabledControlTextColor] };
	NSSize size = [_placeholderString sizeWithAttributes:attributes];
	NSRect box = NSInsetRect([self bounds], 5, 0);
	box.origin.y = NSMidY([self bounds]) - size.height / 2;
	box.size.height = size.height;
	[_placeholderString drawInRect:box withAttributes:attributes];
}

- (BOOL)acceptsFirstResponder
{
	return [_textView isEditable];
}

- (BOOL)becomeFirstResponder
{
	return [[self window] makeFirstResponder:_textView];
}

- (void)textDidChange:(NSNotification *)notification
{
	[self check];
	[self setNeedsDisplay:YES];
	if ([self.delegate respondsToSelector:@selector(controlTextDidChange:)]) {
		[self.delegate controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification
		                                                                  object:self]];
	}
}

- (void)textDidEndEditing:(NSNotification *)notification
{
	[self setNeedsDisplay:YES];
	id target = self.target;
	SEL action = self.action;
	if (target != nil && action != NULL) {
		void (*send)(id, SEL, id) = (void (*)(id, SEL, id))[target methodForSelector:action];
		send(target, action, self);
	}
}

@end

#import <AppKit/AppKit.h>
#if __has_include(<WorkflowKit/WFFeel.h>)
#import <WorkflowKit/WFFeel.h>
#else
#import "WFFeel.h"
#endif

/*
 * Expressions as the engine reads them, coloured as they are typed: FEEL,
 * Camunda 7's ${...}, or literal text where an attribute takes one -- the
 * engine's own lexer says what each token is
 * (+[WFFeelExpression tokensOfText:place:]), and its parser where it stops
 * reading (+problemInText:place:), which is underlined.
 *
 * Ported from the XForms Designer's XFDXPathTextStorage and
 * XFDExpressionField: the storage colours, because it hears of every
 * change -- typing, a paste, an undo -- and the field is a text view
 * behind it that behaves as a one-line field does.
 */

/* The colour a kind of token is drawn in. */
NSColor *WKDExpressionTokenColor(NSString *kind);
/* The text in its tokens' colours, where the engine stops reading
 * underlined: what a table's cell shows when it is not typed in. */
NSAttributedString *WKDColouredExpression(NSString *text, WFExpressionPlace place, NSFont *font);

@interface WKDExpressionTextStorage : NSTextStorage
/* What the text starts from before the tokens' colours. */
@property (nonatomic, copy) NSDictionary<NSString *, id> *baseAttributes;
/* How the engine reads the text. */
@property (nonatomic) WFExpressionPlace place;
/* Where the engine stops reading: underlined. NSNotFound for nowhere. */
@property (nonatomic) NSRange problemRange;
+ (instancetype)installedInTextView:(NSTextView *)view;
@end

@interface WKDExpressionField : NSView

@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic) WFExpressionPlace place;
/* Why the engine would not read the text; nil when it would. Kept as the
 * text changes, and the field's tool tip. */
@property (nonatomic, readonly, copy) NSString *problem;
@property (nonatomic, copy) NSString *placeholderString;
/* Sent -controlTextDidChange: as the text changes, with the field as the
 * notification's object. */
@property (nonatomic, weak) id delegate;
/* Sent when the field is left, or Return is pressed. */
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;

- (void)setFont:(NSFont *)font;
- (void)setEnabled:(BOOL)enabled;
/* The text view that is typed in: what the window's first responder is
 * while it is. */
@property (nonatomic, readonly) NSTextView *textView;

@end

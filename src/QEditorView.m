//
//  QEditorView.m — one source view: gutter, text, scrollers.
//
//  TextKit 1 on purpose: the colouriser paints through the layout manager's
//  temporary attributes, which leaves the text storage itself untouched, so
//  two views of the same document can colour independently and Undo never
//  sees a colour change.
//

#import "Quincy.h"

@interface QEditorView (Private) <NSTextViewDelegate>
- (void)textDidChange;
- (void)toggleBreakpointAtLine:(NSUInteger)line;
- (void)highlightVisible;
- (void)scheduleHighlight;
@end

#pragma mark - Gutter

/// Line numbers, breakpoints and the debugger's current-line arrow.  The
/// original drew a hand for a breakpoint and a green arrow for the current
/// line; here they are the shapes a Mac programmer expects, in the same roles.
@interface QGutterView : NSRulerView
@property (nonatomic, weak) QEditorView *editor;
@end

@implementation QGutterView

- (instancetype)initWithScrollView:(NSScrollView *)scrollView {
    if (!(self = [super initWithScrollView:scrollView
                               orientation:NSVerticalRuler])) return nil;
    self.clientView = scrollView.documentView;
    self.ruleThickness = 42;
    self.clipsToBounds = YES;
    return self;
}

- (NSFont *)numberFont {
    CGFloat size = MAX(9.0, [QOptions shared].fontSize - 2.0);
    return [NSFont monospacedDigitSystemFontOfSize:size
                                            weight:NSFontWeightRegular];
}

/// Enough room for the widest line number, plus the breakpoint gutter.
- (void)sizeToFitLineCount:(NSUInteger)lines {
    NSUInteger digits = 1;
    for (NSUInteger n = MAX(lines, (NSUInteger)10); n >= 10; n /= 10) digits++;
    CGFloat width = ceil([@"0" sizeWithAttributes:
                          @{NSFontAttributeName: [self numberFont]}].width);
    CGFloat wanted = round(width * digits) + 22;
    if (fabs(wanted - self.ruleThickness) > 0.5) self.ruleThickness = wanted;
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    NSTextView *tv = (NSTextView *)self.clientView;
    if (![tv isKindOfClass:NSTextView.class]) return;
    QDocumentModel *doc = self.editor.document;

    rect = NSIntersectionRect(rect, self.bounds);
    [[QOptions shared].backgroundColour setFill];
    NSRectFill(rect);
    // A hairline against the text, so the gutter reads as its own column.
    [NSColor.separatorColor setFill];
    NSRectFill(NSMakeRect(NSWidth(self.bounds) - 1, NSMinY(rect),
                          1, NSHeight(rect)));

    NSLayoutManager *lm = tv.layoutManager;
    NSTextContainer *tc = tv.textContainer;
    NSString *text = tv.string;
    NSRect visible = self.scrollView.contentView.bounds;
    NSPoint origin = tv.textContainerOrigin;

    NSRange glyphs = [lm glyphRangeForBoundingRect:visible inTextContainer:tc];
    NSRange chars = [lm characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];

    // Which line the visible range starts on.
    NSUInteger line = 1;
    for (NSUInteger i = 0; i < chars.location; ) {
        NSRange r = [text lineRangeForRange:NSMakeRange(i, 0)];
        if (NSMaxRange(r) > chars.location || r.length == 0) break;
        i = NSMaxRange(r);
        line++;
    }

    NSDictionary *attrs = @{
        NSFontAttributeName: [self numberFont],
        NSForegroundColorAttributeName: NSColor.tertiaryLabelColor,
    };
    NSDictionary *hotAttrs = @{
        NSFontAttributeName: [self numberFont],
        NSForegroundColorAttributeName: NSColor.alternateSelectedControlTextColor,
    };
    NSDictionary *currentAttrs = @{
        NSFontAttributeName: [self numberFont],
        NSForegroundColorAttributeName: NSColor.labelColor,
    };

    NSUInteger index = [text lineRangeForRange:
                        NSMakeRange(MIN(chars.location, text.length), 0)].location;
    NSUInteger total = text.length;
    NSUInteger caretLine = [self.editor currentLine];

    while (index <= total) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(index, 0)];
        // The line's first fragment; the empty last line after a trailing
        // newline has no glyphs and lives in the extra line fragment.
        NSRect fragment;
        if (lineRange.length == 0) {
            fragment = lm.extraLineFragmentRect;
        } else {
            NSUInteger glyph = [lm glyphIndexForCharacterAtIndex:lineRange.location];
            fragment = [lm lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
        }
        CGFloat h = NSHeight(fragment);
        if (h <= 0) h = ceil([self numberFont].pointSize * 1.4);
        CGFloat y = NSMinY(fragment) + origin.y - NSMinY(visible);
        if (y > NSMaxY(rect)) break;

        if (y + h >= NSMinY(rect)) {
            BOOL hasBreak = [doc.breakpoints containsIndex:line - 1];
            BOOL isCurrent = doc.currentLine != NSNotFound &&
                             doc.currentLine == line - 1;

            if (isCurrent) {
                [[NSColor.systemGreenColor colorWithAlphaComponent:0.35] setFill];
                NSRectFill(NSMakeRect(0, y, NSWidth(self.bounds) - 1, h));
            }
            if (hasBreak) {
                // Xcode's pointed tag, so a breakpoint reads as one at a glance.
                NSRect box = NSInsetRect(NSMakeRect(2, y,
                                                    NSWidth(self.bounds) - 5, h), 0, 1);
                NSBezierPath *tag = [NSBezierPath bezierPath];
                CGFloat tip = 6, r = 3;
                [tag moveToPoint:NSMakePoint(NSMinX(box) + r, NSMinY(box))];
                [tag lineToPoint:NSMakePoint(NSMaxX(box) - tip, NSMinY(box))];
                [tag lineToPoint:NSMakePoint(NSMaxX(box), NSMidY(box))];
                [tag lineToPoint:NSMakePoint(NSMaxX(box) - tip, NSMaxY(box))];
                [tag lineToPoint:NSMakePoint(NSMinX(box) + r, NSMaxY(box))];
                [tag appendBezierPathWithArcFromPoint:NSMakePoint(NSMinX(box), NSMaxY(box))
                                              toPoint:NSMakePoint(NSMinX(box), NSMidY(box))
                                               radius:r];
                [tag appendBezierPathWithArcFromPoint:NSMakePoint(NSMinX(box), NSMinY(box))
                                              toPoint:NSMakePoint(NSMidX(box), NSMinY(box))
                                               radius:r];
                [tag closePath];
                [NSColor.controlAccentColor setFill];
                [tag fill];
            }

            if ([QOptions shared].showLineNumbers) {
                NSString *label = [NSString stringWithFormat:@"%lu",
                                   (unsigned long)line];
                NSDictionary *a = hasBreak ? hotAttrs
                                : ((NSInteger)line == caretLine ? currentAttrs : attrs);
                NSSize size = [label sizeWithAttributes:a];
                [label drawAtPoint:NSMakePoint(NSWidth(self.bounds) - size.width - 10,
                                               y + (h - size.height) / 2)
                        withAttributes:a];
            }
        }

        NSUInteger next = NSMaxRange(lineRange);
        if (next <= index) break;
        index = next;
        line++;
        if (index >= total &&
            (total == 0 || [text characterAtIndex:total - 1] != '\n')) break;
    }
}

/// A click in the gutter toggles a breakpoint, the way Xcode does it; the
/// original wanted a double-click, which still works because this fires first.
- (void)mouseDown:(NSEvent *)event {
    NSTextView *tv = (NSTextView *)self.clientView;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect visible = self.scrollView.contentView.bounds;
    NSPoint inText = NSMakePoint(4, p.y + NSMinY(visible) - tv.textContainerOrigin.y);
    NSUInteger index = [tv characterIndexForInsertionAtPoint:inText];
    NSUInteger line = 0;
    for (NSUInteger i = 0; i < index; ) {
        NSRange r = [tv.string lineRangeForRange:NSMakeRange(i, 0)];
        if (r.length == 0) break;
        i = NSMaxRange(r);
        if (i <= index) line++;
    }
    [self.editor toggleBreakpointAtLine:line];
}

@end

#pragma mark - Text view

@interface QSourceTextView : NSTextView
@property (nonatomic, weak) QEditorView *editor;
@end

@implementation QSourceTextView

/// Autoindent: a new line starts under the first non-blank of the old one.
- (void)insertNewline:(id)sender {
    [super insertNewline:sender];
    if (![QOptions shared].autoindent) return;
    NSString *text = self.string;
    NSUInteger caret = self.selectedRange.location;
    if (caret < 2) return;
    NSRange previous = [text lineRangeForRange:NSMakeRange(caret - 1, 0)];
    NSUInteger i = previous.location;
    while (i < NSMaxRange(previous)) {
        unichar c = [text characterAtIndex:i];
        if (c != ' ' && c != '\t') break;
        i++;
    }
    if (i > previous.location)
        [self insertText:[text substringWithRange:
                          NSMakeRange(previous.location, i - previous.location)]
        replacementRange:self.selectedRange];
}

/// Tab inserts spaces unless the user asked for real tab characters.
- (void)insertTab:(id)sender {
    QOptions *opt = [QOptions shared];
    if (opt.useTabCharacters) { [super insertTab:sender]; return; }
    NSUInteger caret = self.selectedRange.location;
    NSRange line = [self.string lineRangeForRange:NSMakeRange(caret, 0)];
    NSInteger column = (NSInteger)(caret - line.location);
    NSInteger width = MAX((NSInteger)1, opt.tabStops);
    NSInteger fill = width - (column % width);
    [self insertText:[@"" stringByPaddingToLength:fill withString:@" "
                                startingAtIndex:0]
    replacementRange:self.selectedRange];
}

/// Copy with nothing selected takes the whole line, as the original did.
- (void)copy:(id)sender {
    if (self.selectedRange.length == 0) {
        NSRange line = [self.string lineRangeForRange:self.selectedRange];
        NSPasteboard *pb = NSPasteboard.generalPasteboard;
        [pb clearContents];
        [pb setString:[self.string substringWithRange:line]
              forType:NSPasteboardTypeString];
        return;
    }
    [super copy:sender];
}

- (void)didChangeText {
    [super didChangeText];
    [self.editor textDidChange];
}

@end

#pragma mark - Editor

@implementation QEditorView {
    QSourceTextView *_textView;
    NSScrollView    *_scrollView;
    QGutterView     *_gutter;
    QSyntax         *_syntax;
    BOOL             _highlightScheduled;
}

- (instancetype)initWithDocument:(QDocumentModel *)doc {
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, 640, 480)])) return nil;
    _document = doc;
    _syntax = [[QSyntax alloc] initWithTextStorage:doc.textStorage];

    // One layout manager per view, sharing the document's storage: that is
    // what makes a second window on the same document possible.
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    [doc.textStorage addLayoutManager:lm];
    NSTextContainer *tc = [[NSTextContainer alloc]
        initWithContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    tc.widthTracksTextView = NO;
    [lm addTextContainer:tc];

    _textView = [[QSourceTextView alloc] initWithFrame:self.bounds
                                         textContainer:tc];
    _textView.editor = self;
    _textView.minSize = NSMakeSize(0, 0);
    _textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _textView.horizontallyResizable = YES;
    _textView.verticallyResizable = YES;
    _textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _textView.allowsUndo = YES;
    _textView.richText = NO;
    _textView.importsGraphics = NO;
    _textView.usesFindBar = YES;
    _textView.incrementalSearchingEnabled = YES;
    _textView.automaticQuoteSubstitutionEnabled = NO;
    _textView.automaticDashSubstitutionEnabled = NO;
    _textView.automaticTextReplacementEnabled = NO;
    _textView.automaticSpellingCorrectionEnabled = NO;
    _textView.continuousSpellCheckingEnabled = NO;
    _textView.smartInsertDeleteEnabled = NO;
    _textView.textContainerInset = NSMakeSize(4, 6);
    _textView.delegate = (id)self;

    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.documentView = _textView;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = YES;
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _gutter = [[QGutterView alloc] initWithScrollView:_scrollView];
    _gutter.editor = self;
    _scrollView.verticalRulerView = _gutter;
    _scrollView.hasVerticalRuler = YES;
    _scrollView.rulersVisible = YES;

    [self addSubview:_scrollView];

    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(viewScrolled:)
            name:NSViewBoundsDidChangeNotification
          object:_scrollView.contentView];
    _scrollView.contentView.postsBoundsChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(optionsChanged:)
            name:QOptionsDidChangeNotification object:nil];
    // Edits may come through another view on the same document.
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(storageEdited:)
            name:NSTextStorageDidProcessEditingNotification
          object:doc.textStorage];

    [self refreshAppearance];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_document.textStorage removeLayoutManager:_textView.layoutManager];
}

- (NSTextView *)textView { return _textView; }
- (NSScrollView *)scrollView { return _scrollView; }

#pragma mark - Appearance

- (void)refreshAppearance {
    QOptions *opt = [QOptions shared];
    NSFont *font = [opt editorFont];
    _textView.font = font;
    _textView.backgroundColor = [opt backgroundColour];
    _textView.textColor = [opt textColour];
    _textView.insertionPointColor = [opt textColour];
    _scrollView.backgroundColor = [opt backgroundColour];

    // Tab stops, so a tab character lands where the setting says it should.
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    CGFloat advance = [font advancementForGlyph:(NSGlyph)' '].width;
    if (advance <= 0) advance = font.pointSize * 0.6;
    ps.tabStops = @[];
    ps.defaultTabInterval = advance * MAX((NSInteger)1, opt.tabStops);
    ps.lineBreakMode = NSLineBreakByClipping;
    _textView.defaultParagraphStyle = ps;
    [_document.textStorage addAttribute:NSParagraphStyleAttributeName value:ps
                                  range:NSMakeRange(0, _document.textStorage.length)];
    [_document.textStorage addAttribute:NSFontAttributeName value:font
                                  range:NSMakeRange(0, _document.textStorage.length)];
    [_document.textStorage addAttribute:NSForegroundColorAttributeName
                                  value:[opt textColour]
                                  range:NSMakeRange(0, _document.textStorage.length)];
    [_syntax invalidateFromCharacterIndex:0];
    [self highlightVisible];
    [self refreshGutter];
}

- (void)optionsChanged:(NSNotification *)note { [self refreshAppearance]; }

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self refreshAppearance];
}

- (void)refreshGutter {
    [_gutter sizeToFitLineCount:
        [_document.textStorage.string componentsSeparatedByString:@"\n"].count];
    _gutter.needsDisplay = YES;
}

#pragma mark - Highlighting

- (void)viewScrolled:(NSNotification *)note {
    [self scheduleHighlight];
    _gutter.needsDisplay = YES;
}

- (void)textDidChange {
    _document.dirty = YES;
    [[QWindowController shared] refreshChrome];
}

- (void)storageEdited:(NSNotification *)note {
    NSTextStorage *storage = note.object;
    if (!(storage.editedMask & NSTextStorageEditedCharacters)) return;
    [_syntax invalidateFromCharacterIndex:
        MIN(storage.editedRange.location, storage.length)];
    [self scheduleHighlight];
    // The line count is only known once the edit is over.
    dispatch_async(dispatch_get_main_queue(), ^{ [self refreshGutter]; });
}

- (void)scheduleHighlight {
    if (_highlightScheduled) return;
    _highlightScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_highlightScheduled = NO;
        [self highlightVisible];
    });
}

- (void)highlightVisible {
    if (!_textView.layoutManager) return;
    NSRange glyphs = [_textView.layoutManager
        glyphRangeForBoundingRect:_scrollView.contentView.bounds
                  inTextContainer:_textView.textContainer];
    NSRange chars = [_textView.layoutManager
        characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
    [_syntax applyToLayoutManager:_textView.layoutManager characterRange:chars];
}

#pragma mark - Position

- (NSInteger)currentLine {
    NSUInteger caret = _textView.selectedRange.location;
    NSString *text = _textView.string;
    NSInteger line = 1;
    for (NSUInteger i = 0; i < caret; ) {
        NSRange r = [text lineRangeForRange:NSMakeRange(i, 0)];
        if (r.length == 0) break;
        i = NSMaxRange(r);
        if (i <= caret) line++;
    }
    return line;
}

- (NSInteger)currentColumn {
    NSUInteger caret = _textView.selectedRange.location;
    NSRange line = [_textView.string lineRangeForRange:NSMakeRange(caret, 0)];
    return (NSInteger)(caret - line.location) + 1;
}

- (void)goToLine:(NSInteger)line column:(NSInteger)column {
    NSString *text = _textView.string;
    NSUInteger index = 0;
    for (NSInteger l = 1; l < line && index < text.length; l++)
        index = NSMaxRange([text lineRangeForRange:NSMakeRange(index, 0)]);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(MIN(index, text.length), 0)];
    NSUInteger target = lineRange.location +
        MIN((NSUInteger)MAX(column - 1, 0), lineRange.length ? lineRange.length - 1 : 0);
    [_textView setSelectedRange:NSMakeRange(target, 0)];
    [_textView scrollRangeToVisible:NSMakeRange(target, 0)];
    [_textView showFindIndicatorForRange:lineRange];
}

- (void)toggleBreakpointAtLine:(NSUInteger)line {
    if ([_document.breakpoints containsIndex:line])
        [_document.breakpoints removeIndex:line];
    else
        [_document.breakpoints addIndex:line];
    _gutter.needsDisplay = YES;
    [[QDebugger shared] breakpointsChanged];
}

#pragma mark - NSTextViewDelegate

- (NSUndoManager *)undoManagerForTextView:(NSTextView *)view {
    return _document.undoManager;
}

/// Undo and Redo come through here too, so marks follow those as well.
- (BOOL)textView:(NSTextView *)view shouldChangeTextInRange:(NSRange)range
        replacementString:(NSString *)text {
    if (text && [_document adjustLinesForEditInRange:range replacement:text])
        dispatch_async(dispatch_get_main_queue(), ^{
            [[QDebugger shared] breakpointsChanged];
        });
    return YES;
}

- (void)textViewDidChangeSelection:(NSNotification *)note {
    [[QWindowController shared] updateCaretPosition];
    _gutter.needsDisplay = YES;
}

@end

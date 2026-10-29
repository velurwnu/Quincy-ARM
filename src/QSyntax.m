//
//  QSyntax.m — incremental C/C++ colouriser.
//
//  Lexing is per line.  The only state that crosses a line boundary is
//  "inside a /* */ comment", so one byte per line is enough to restart the
//  lexer anywhere; the cache is truncated at the first edited line and
//  rebuilt lazily as lines come into view.
//

#import "Quincy.h"

typedef NS_ENUM(uint8_t, QLineState) {
    QLineStateNormal = 0,
    QLineStateComment = 1,
};

typedef NS_ENUM(NSInteger, QToken) {
    QTokenText = 0,
    QTokenComment,
    QTokenKeyword,
    QTokenString,
};

@implementation QSyntax {
    __weak NSTextStorage *_storage;
    NSMutableData        *_states;      // QLineState per line
    NSUInteger            _validLines;  // how many entries of _states are good
    NSMutableArray<NSNumber *> *_lineStarts;
    BOOL                  _lineStartsDirty;
}

+ (NSSet<NSString *> *)keywords {
    static NSSet *kw;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kw = [NSSet setWithArray:@[
            @"asm", @"auto", @"bool", @"break", @"case", @"catch", @"char",
            @"class", @"const", @"const_cast", @"continue", @"default",
            @"delete", @"do", @"double", @"dynamic_cast", @"else", @"enum",
            @"explicit", @"export", @"extern", @"false", @"float", @"for",
            @"friend", @"goto", @"if", @"inline", @"int", @"long", @"mutable",
            @"namespace", @"new", @"operator", @"private", @"protected",
            @"public", @"register", @"reinterpret_cast", @"return", @"short",
            @"signed", @"sizeof", @"static", @"static_cast", @"struct",
            @"switch", @"template", @"this", @"throw", @"true", @"try",
            @"typedef", @"typeid", @"typename", @"union", @"unsigned",
            @"using", @"virtual", @"void", @"volatile", @"wchar_t", @"while",
            // C99 / later spellings the original's gcc also accepted
            @"_Bool", @"_Complex", @"_Imaginary", @"restrict", @"inline",
        ]];
    });
    return kw;
}

- (instancetype)initWithTextStorage:(NSTextStorage *)storage {
    if (!(self = [super init])) return nil;
    _storage = storage;
    _states = [NSMutableData data];
    _lineStartsDirty = YES;
    return self;
}

#pragma mark - Line index

- (void)rebuildLineStarts {
    NSString *s = _storage.string;
    NSUInteger len = s.length;
    NSMutableArray *starts = [NSMutableArray arrayWithCapacity:len / 24 + 8];
    [starts addObject:@0];
    [s enumerateSubstringsInRange:NSMakeRange(0, len)
                          options:NSStringEnumerationByLines |
                                  NSStringEnumerationSubstringNotRequired
                       usingBlock:^(NSString *sub, NSRange r, NSRange e, BOOL *stop) {
        NSUInteger next = NSMaxRange(e);
        if (next < len) [starts addObject:@(next)];
    }];
    _lineStarts = starts;
    _lineStartsDirty = NO;
}

- (NSArray<NSNumber *> *)lineStarts {
    if (_lineStartsDirty) [self rebuildLineStarts];
    return _lineStarts;
}

- (NSUInteger)lineForCharacterIndex:(NSUInteger)index {
    NSArray<NSNumber *> *starts = [self lineStarts];
    NSUInteger lo = 0, hi = starts.count;
    while (lo + 1 < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (starts[mid].unsignedIntegerValue <= index) lo = mid; else hi = mid;
    }
    return lo;
}

- (NSRange)rangeOfLine:(NSUInteger)line {
    NSArray<NSNumber *> *starts = [self lineStarts];
    if (line >= starts.count) return NSMakeRange(_storage.length, 0);
    NSUInteger from = starts[line].unsignedIntegerValue;
    NSUInteger to = line + 1 < starts.count
        ? starts[line + 1].unsignedIntegerValue : _storage.length;
    return NSMakeRange(from, to - from);
}

#pragma mark - Invalidation

- (void)invalidateFromCharacterIndex:(NSUInteger)index {
    NSUInteger line = _lineStartsDirty ? 0 : [self lineForCharacterIndex:index];
    _lineStartsDirty = YES;
    if (line < _validLines) _validLines = line;
}

#pragma mark - Lexer

/// Lexes one line, reporting tokens through `emit`, and returns the state the
/// next line starts in.
- (QLineState)lexLine:(NSString *)text
                range:(NSRange)lineRange
                state:(QLineState)state
                 emit:(void (^)(NSRange r, QToken t))emit {
    NSUInteger i = lineRange.location;
    unichar buf[1024];
    unichar *chars = NULL;
    BOOL heap = NO;
    if (lineRange.length <= 1024) {
        [text getCharacters:buf range:lineRange];
        chars = buf;
    } else {
        chars = malloc(lineRange.length * sizeof(unichar));
        heap = YES;
        [text getCharacters:chars range:lineRange];
    }
    NSUInteger n = lineRange.length, p = 0;
    BOOL seenNonSpace = NO;

    while (p < n) {
        if (state == QLineStateComment) {
            NSUInteger start = p;
            while (p < n && !(chars[p] == '*' && p + 1 < n && chars[p + 1] == '/'))
                p++;
            if (p < n) { p += 2; state = QLineStateNormal; }
            emit(NSMakeRange(i + start, p - start), QTokenComment);
            continue;
        }
        unichar c = chars[p];
        if (c == '/' && p + 1 < n && chars[p + 1] == '/') {
            emit(NSMakeRange(i + p, n - p), QTokenComment);
            break;
        }
        if (c == '/' && p + 1 < n && chars[p + 1] == '*') {
            p += 2;
            state = QLineStateComment;
            NSUInteger start = p - 2;
            while (p < n && !(chars[p] == '*' && p + 1 < n && chars[p + 1] == '/'))
                p++;
            if (p < n) { p += 2; state = QLineStateNormal; }
            emit(NSMakeRange(i + start, p - start), QTokenComment);
            continue;
        }
        if (c == '"' || c == '\'') {
            unichar quote = c;
            NSUInteger start = p++;
            while (p < n) {
                if (chars[p] == '\\') { p += 2; continue; }
                if (chars[p] == quote) { p++; break; }
                p++;
            }
            if (p > n) p = n;
            emit(NSMakeRange(i + start, p - start), QTokenString);
            seenNonSpace = YES;
            continue;
        }
        if (c == '#' && !seenNonSpace) {
            NSUInteger start = p++;
            while (p < n && (isalnum(chars[p]) || chars[p] == '_')) p++;
            emit(NSMakeRange(i + start, p - start), QTokenKeyword);
            seenNonSpace = YES;
            continue;
        }
        if (isalpha(c) || c == '_') {
            NSUInteger start = p;
            while (p < n && (isalnum(chars[p]) || chars[p] == '_')) p++;
            NSString *word = [NSString stringWithCharacters:chars + start
                                                     length:p - start];
            if ([[QSyntax keywords] containsObject:word])
                emit(NSMakeRange(i + start, p - start), QTokenKeyword);
            seenNonSpace = YES;
            continue;
        }
        if (c != ' ' && c != '\t' && c != '\r' && c != '\n') seenNonSpace = YES;
        p++;
    }
    if (heap) free(chars);
    return state;
}

- (QLineState)stateAtLine:(NSUInteger)line {
    NSArray<NSNumber *> *starts = [self lineStarts];
    if (line == 0) return QLineStateNormal;
    if (line > starts.count) line = starts.count;
    if (_states.length < starts.count)
        [_states increaseLengthBy:starts.count - _states.length];
    QLineState *st = _states.mutableBytes;
    NSString *text = _storage.string;
    while (_validLines < line) {
        NSUInteger l = _validLines;
        QLineState s = (l == 0) ? QLineStateNormal : st[l - 1];
        // st[l] is the state the line *after* l starts in.
        st[l] = [self lexLine:text range:[self rangeOfLine:l] state:s
                         emit:^(NSRange r, QToken t) {}];
        _validLines = l + 1;
    }
    return st[line - 1];
}

#pragma mark - One-shot colouring

+ (NSAttributedString *)colourise:(NSString *)source font:(NSFont *)font {
    QOptions *opt = [QOptions shared];
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:source];
    QSyntax *syntax = [[QSyntax alloc] initWithTextStorage:storage];
    NSMutableAttributedString *out =
        [[NSMutableAttributedString alloc] initWithString:source attributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: opt.textColour,
        }];
    if (!opt.syntaxEnabled) return out;
    NSDictionary *colours = @{
        @(QTokenComment): opt.commentColour,
        @(QTokenKeyword): opt.keywordColour,
        @(QTokenString):  opt.stringColour,
    };
    NSArray<NSNumber *> *starts = [syntax lineStarts];
    QLineState state = QLineStateNormal;
    for (NSUInteger l = 0; l < starts.count; l++) {
        state = [syntax lexLine:source range:[syntax rangeOfLine:l] state:state
                           emit:^(NSRange r, QToken t) {
            NSColor *c = colours[@(t)];
            if (c) [out addAttribute:NSForegroundColorAttributeName
                               value:c range:r];
        }];
    }
    return out;
}

#pragma mark - Painting

- (void)applyToLayoutManager:(NSLayoutManager *)lm characterRange:(NSRange)range {
    if (!_storage || _storage.length == 0) return;
    NSUInteger first = [self lineForCharacterIndex:range.location];
    NSUInteger last = [self lineForCharacterIndex:
                       MIN(NSMaxRange(range), _storage.length ? _storage.length - 1 : 0)];
    NSArray<NSNumber *> *starts = [self lineStarts];
    if (last >= starts.count) last = starts.count - 1;

    NSUInteger from = [self rangeOfLine:first].location;
    NSRange whole = NSMakeRange(from,
                                NSMaxRange([self rangeOfLine:last]) - from);
    [lm removeTemporaryAttribute:NSForegroundColorAttributeName
               forCharacterRange:whole];

    QOptions *opt = [QOptions shared];
    if (!opt.syntaxEnabled) return;
    NSDictionary *colours = @{
        @(QTokenComment): opt.commentColour,
        @(QTokenKeyword): opt.keywordColour,
        @(QTokenString):  opt.stringColour,
    };
    NSString *text = _storage.string;
    QLineState state = [self stateAtLine:first];
    for (NSUInteger l = first; l <= last; l++) {
        state = [self lexLine:text range:[self rangeOfLine:l] state:state
                         emit:^(NSRange r, QToken t) {
            NSColor *c = colours[@(t)];
            if (c) [lm addTemporaryAttribute:NSForegroundColorAttributeName
                                       value:c forCharacterRange:r];
        }];
    }
}

@end

#pragma mark - Brace matching

/// Edit ▸ Balance Braces.  `caret` is the insertion point; the brace just
/// before or just after it is matched, counting only braces that are really
/// code — ones inside comments or literals are invisible, as in the original.
/// Returns the index of the partner, or NSNotFound when there is none.
NSUInteger QMatchingBraceIndex(NSString *text, NSUInteger caret) {
    NSUInteger n = text.length;
    if (n == 0) return NSNotFound;

    // One pass marks every character that is code rather than comment or
    // literal; the matcher then only has to count.
    uint8_t *code = calloc(n, 1);
    if (!code) return NSNotFound;
    unichar *chars = malloc(n * sizeof(unichar));
    if (!chars) { free(code); return NSNotFound; }
    [text getCharacters:chars range:NSMakeRange(0, n)];

    enum { Plain, Line, Block, Str, Chr } state = Plain;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = chars[i];
        switch (state) {
            case Plain:
                if (c == '/' && i + 1 < n && chars[i + 1] == '/') { state = Line; i++; }
                else if (c == '/' && i + 1 < n && chars[i + 1] == '*') { state = Block; i++; }
                else if (c == '"')  state = Str;
                else if (c == '\'') state = Chr;
                else code[i] = 1;
                break;
            case Line:
                if (c == '\n') state = Plain;
                break;
            case Block:
                if (c == '*' && i + 1 < n && chars[i + 1] == '/') { state = Plain; i++; }
                break;
            case Str:
            case Chr:
                if (c == '\\') i++;
                else if ((state == Str && c == '"') || (state == Chr && c == '\''))
                    state = Plain;
                break;
        }
    }

    static const char opens[]  = "([{";
    static const char closes[] = ")]}";

    NSUInteger found = NSNotFound;
    // Look at the character after the caret first, then the one before it.
    NSUInteger candidates[2] = { caret, caret ? caret - 1 : NSNotFound };
    for (int k = 0; k < 2 && found == NSNotFound; k++) {
        NSUInteger at = candidates[k];
        if (at == NSNotFound || at >= n || !code[at]) continue;
        unichar c = chars[at];
        const char *o = strchr(opens, c), *e = strchr(closes, c);
        if (o) {
            unichar want = closes[o - opens];
            NSInteger depth = 0;
            for (NSUInteger i = at; i < n; i++) {
                if (!code[i]) continue;
                if (chars[i] == c) depth++;
                else if (chars[i] == want && --depth == 0) { found = i; break; }
            }
        } else if (e) {
            unichar want = opens[e - closes];
            NSInteger depth = 0;
            for (NSUInteger i = at + 1; i-- > 0; ) {
                if (!code[i]) continue;
                if (chars[i] == c) depth++;
                else if (chars[i] == want && --depth == 0) { found = i; break; }
            }
        }
    }

    free(chars);
    free(code);
    return found;
}

//
//  QDocument.m — the text behind one or more editor views.
//
//  The text storage is the shared thing, so Window ▸ New Window can put a
//  second view on the same document the way the original's MDI did.
//

#import "Quincy.h"

@implementation QDocumentModel

static int sUntitledCounter = 0;

- (instancetype)initCommon {
    if (!(self = [super init])) return nil;
    _breakpoints = [NSMutableIndexSet indexSet];
    _currentLine = NSNotFound;
    _undoManager = [[NSUndoManager alloc] init];
    _undoManager.levelsOfUndo = (NSUInteger)MAX((NSInteger)1, [QOptions shared].maxUndos);
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(optionsChanged:) name:QOptionsDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)optionsChanged:(NSNotification *)note {
    _undoManager.levelsOfUndo = (NSUInteger)MAX((NSInteger)1, [QOptions shared].maxUndos);
}

static NSUInteger CountNewlines(NSString *s) {
    NSUInteger n = 0, len = s.length;
    for (NSUInteger i = 0; i < len; i++)
        if ([s characterAtIndex:i] == '\n') n++;
    return n;
}

/// An edit that starts at the beginning of a line removes whole lines from
/// there on, so the marks on those lines go and the next line's mark moves
/// up.  Anywhere else the line holding the start of the edit keeps its mark
/// and only the lines that were swallowed lose theirs.
- (BOOL)adjustLinesForEditInRange:(NSRange)range replacement:(NSString *)text {
    NSString *old = _textStorage.string;
    if (NSMaxRange(range) > old.length) return NO;
    NSUInteger removed = CountNewlines([old substringWithRange:range]);
    NSUInteger added = CountNewlines(text);
    if (removed == 0 && added == 0) return NO;

    NSUInteger line = 0;
    for (NSUInteger i = 0; i < range.location; i++)
        if ([old characterAtIndex:i] == '\n') line++;
    BOOL atLineStart = range.location == 0 ||
                       [old characterAtIndex:range.location - 1] == '\n';
    // Lines [first, first + removed) disappear; everything after them shifts.
    NSUInteger first = atLineStart ? line : line + 1;
    NSInteger delta = (NSInteger)added - (NSInteger)removed;

    NSUInteger (^map)(NSUInteger) = ^NSUInteger(NSUInteger l) {
        if (l < first) return l;
        if (l < first + removed) return NSNotFound;
        return (NSUInteger)((NSInteger)l + delta);
    };

    NSMutableIndexSet *moved = [NSMutableIndexSet indexSet];
    [_breakpoints enumerateIndexesUsingBlock:^(NSUInteger l, BOOL *stop) {
        NSUInteger to = map(l);
        if (to != NSNotFound) [moved addIndex:to];
    }];
    if (_currentLine != NSNotFound) _currentLine = map(_currentLine);
    if ([moved isEqualToIndexSet:_breakpoints]) return NO;
    [_breakpoints removeAllIndexes];
    [_breakpoints addIndexes:moved];
    return YES;
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error {
    if (!(self = [self initCommon])) return nil;
    NSStringEncoding used = 0;
    NSString *text = [NSString stringWithContentsOfURL:url
                                          usedEncoding:&used error:NULL];
    if (!text)  // old sources are rarely UTF-8; Latin-1 never fails
        text = [NSString stringWithContentsOfURL:url
                                        encoding:NSISOLatin1StringEncoding
                                           error:error];
    if (!text) return nil;
    // Normalise CRLF: the original is a Windows program and its files have it.
    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    _url = url;
    _displayName = [url.lastPathComponent copy];
    _textStorage = [[NSTextStorage alloc] initWithString:text];
    return self;
}

- (instancetype)initUntitledWithExtension:(NSString *)ext {
    if (!(self = [self initCommon])) return nil;
    if (ext.length && ![ext hasPrefix:@"."]) ext = [@"." stringByAppendingString:ext];
    _displayName = [NSString stringWithFormat:@"Untitled%d%@",
                    ++sUntitledCounter, ext ?: @""];
    _textStorage = [[NSTextStorage alloc] initWithString:@""];
    return self;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
    if (![_textStorage.string writeToURL:url atomically:YES
                               encoding:NSUTF8StringEncoding error:error])
        return NO;
    _url = url;
    _displayName = [url.lastPathComponent copy];
    _dirty = NO;
    return YES;
}

- (NSString *)extension {
    return (_url.lastPathComponent ?: _displayName).pathExtension.lowercaseString;
}

- (BOOL)isSourceFile {
    return [@[@"c", @"cpp", @"cc", @"cxx"] containsObject:[self extension]];
}

- (BOOL)isProject {
    return [[self extension] isEqual:@"prj"];
}

- (NSString *)symbolName {
    NSString *ext = [self extension];
    if ([ext isEqual:@"prj"]) return @"shippingbox";
    if ([ext isEqual:@"h"] || [ext isEqual:@"hpp"]) return @"doc.text";
    if ([self isSourceFile]) return @"chevron.left.forwardslash.chevron.right";
    return @"doc.plaintext";
}

@end

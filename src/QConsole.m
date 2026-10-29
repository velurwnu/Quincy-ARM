//
//  QConsole.m — the program's console window.
//
//  The original ran programs in a Windows console; here they get a pty of
//  their own and this window plays the terminal: grey on black, 80×25, just
//  enough emulation for \r \n \b \t, with escape sequences swallowed.  Ctrl+C
//  goes down the pty as 0x03, so the line discipline turns it into SIGINT.
//

#import "QChrome.h"
#include <util.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>

#pragma mark - Terminal view

@interface QConsoleView : NSTextView
@property (nonatomic, copy) void (^onKey)(NSData *bytes);
@end

@implementation QConsoleView

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags mods = event.modifierFlags &
        NSEventModifierFlagDeviceIndependentFlagsMask;
    if (mods & NSEventModifierFlagCommand) { [super keyDown:event]; return; }
    NSString *chars = event.characters;
    if (!chars.length) return;
    unichar c = [chars characterAtIndex:0];
    NSData *bytes = nil;
    switch (c) {
        case NSCarriageReturnCharacter:
        case NSEnterCharacter:     bytes = [NSData dataWithBytes:"\r" length:1]; break;
        case NSDeleteCharacter:
        case NSBackspaceCharacter: bytes = [NSData dataWithBytes:"\x7f" length:1]; break;
        case NSUpArrowFunctionKey:    bytes = [NSData dataWithBytes:"\033[A" length:3]; break;
        case NSDownArrowFunctionKey:  bytes = [NSData dataWithBytes:"\033[B" length:3]; break;
        case NSRightArrowFunctionKey: bytes = [NSData dataWithBytes:"\033[C" length:3]; break;
        case NSLeftArrowFunctionKey:  bytes = [NSData dataWithBytes:"\033[D" length:3]; break;
        default:
            if (c >= 0xF700) return;       // other function keys mean nothing here
            bytes = [chars dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (self.onKey && bytes) self.onKey(bytes);
}

/// Paste types into the program, as it would in a terminal.
- (void)paste:(id)sender {
    NSString *s = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
    if (self.onKey && s) self.onKey([s dataUsingEncoding:NSUTF8StringEncoding]);
}

@end

#pragma mark - Console window

static const int kColumns = 80, kRows = 25, kScrollback = 2000;

@implementation QConsoleWindowController {
    QConsoleView *_view;
    NSMutableArray<NSMutableString *> *_lines;
    NSInteger _row, _col;
    int _escape;                    // 0 none, 1 after ESC, 2 inside CSI
    int _master, _slave;
    NSString *_slavePath;
    dispatch_source_t _reader;
    dispatch_source_t _exitWatch;
    pid_t _child;
    BOOL _waitingForEnter;
    NSMutableData *_utf8Carry;
}

+ (instancetype)shared {
    static QConsoleWindowController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[QConsoleWindowController alloc] init]; });
    return shared;
}

- (NSFont *)font {
    return [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
}

- (instancetype)init {
    NSFont *font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    CGFloat cw = [@"M" sizeWithAttributes:@{NSFontAttributeName: font}].width;
    CGFloat lh = ceil(font.ascender - font.descender + font.leading) + 1;
    NSRect content = NSMakeRect(0, 0, ceil(cw * kColumns) + 24, lh * kRows + 16);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:content
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
          backing:NSBackingStoreBuffered defer:YES];
    w.title = @"Quincy 2005";
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    w.backgroundColor = NSColor.blackColor;
    w.releasedWhenClosed = NO;
    if (!(self = [super initWithWindow:w])) return nil;
    _master = _slave = -1;
    _lines = [NSMutableArray arrayWithObject:[NSMutableString string]];
    _utf8Carry = [NSMutableData data];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:content];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = YES;
    scroll.backgroundColor = NSColor.blackColor;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _view = [[QConsoleView alloc] initWithFrame:content];
    _view.editable = NO;
    _view.selectable = YES;
    _view.richText = NO;
    _view.backgroundColor = NSColor.blackColor;
    _view.textColor = QRGB(192, 192, 192);
    _view.font = font;
    _view.textContainerInset = NSMakeSize(8, 8);
    _view.autoresizingMask = NSViewWidthSizable;
    _view.verticallyResizable = YES;
    __weak typeof(self) weakSelf = self;
    _view.onKey = ^(NSData *bytes) { [weakSelf typed:bytes]; };
    scroll.documentView = _view;
    w.contentView = scroll;
    [w center];
    // The original remembered "Console Position"; so does this.
    [w setFrameAutosaveName:@"Console Position"];
    return self;
}

- (BOOL)isRunning { return _child > 0 || [QDebugger shared].active; }

#pragma mark - Pty

- (void)closePty {
    if (_reader) { dispatch_source_cancel(_reader); _reader = nil; }
    if (_master >= 0) { close(_master); _master = -1; }
    if (_slave >= 0) { close(_slave); _slave = -1; }
}

- (NSString *)openTerminalForTitle:(NSString *)title {
    [self closePty];
    struct winsize ws = { .ws_row = kRows, .ws_col = kColumns };
    char name[128];
    if (openpty(&_master, &_slave, name, NULL, &ws) != 0) return nil;
    _slavePath = @(name);
    fcntl(_master, F_SETFD, FD_CLOEXEC);
    fcntl(_slave, F_SETFD, FD_CLOEXEC);

    [_lines removeAllObjects];
    [_lines addObject:[NSMutableString string]];
    _row = _col = 0;
    _escape = 0;
    _waitingForEnter = NO;
    [self render];
    self.window.title = title.length ? [NSString stringWithFormat:@"Quincy 2005 — %@", title]
                                     : @"Quincy 2005";
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:_view];

    int fd = _master;
    _reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0,
                                     dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_reader, ^{
        char buf[8192];
        ssize_t n = read(fd, buf, sizeof buf);
        if (n > 0) [weakSelf output:[NSData dataWithBytes:buf length:(NSUInteger)n]];
        else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR)) {
            typeof(self) s = weakSelf;
            if (s && s->_reader) { dispatch_source_cancel(s->_reader); s->_reader = nil; }
        }
    });
    dispatch_resume(_reader);
    return _slavePath;
}

- (BOOL)runProgram:(NSString *)path arguments:(NSArray<NSString *> *)args
         directory:(NSString *)dir {
    if (![self openTerminalForTitle:path.lastPathComponent]) return NO;

    // Everything the child needs is prepared before fork: after it only
    // async-signal-safe calls are allowed.
    NSMutableArray *all = [NSMutableArray arrayWithObject:path];
    [all addObjectsFromArray:args ?: @[]];
    char **argv = calloc(all.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < all.count; i++) argv[i] = strdup([all[i] UTF8String]);
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"TERM"] = @"dumb";
    env[@"COLUMNS"] = @"80";
    env[@"LINES"] = @"25";
    char **envp = calloc(env.count + 1, sizeof(char *));
    NSUInteger e = 0;
    for (NSString *k in env)
        envp[e++] = strdup([[NSString stringWithFormat:@"%@=%@", k, env[k]] UTF8String]);
    const char *cdir = strdup((dir.length ? dir : path.stringByDeletingLastPathComponent)
                              .fileSystemRepresentation);
    const char *cpath = strdup(path.fileSystemRepresentation);
    int slave = _slave, master = _master;

    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        ioctl(slave, TIOCSCTTY, 0);
        dup2(slave, 0); dup2(slave, 1); dup2(slave, 2);
        if (slave > 2) close(slave);
        close(master);
        chdir(cdir);
        execve(cpath, argv, envp);
        const char msg[] = "Quincy: cannot run the program\n";
        write(2, msg, sizeof msg - 1);
        _exit(127);
    }
    for (NSUInteger i = 0; argv[i]; i++) free(argv[i]);
    for (NSUInteger i = 0; envp[i]; i++) free(envp[i]);
    free(argv); free(envp); free((void *)cdir); free((void *)cpath);
    if (pid < 0) return NO;
    _child = pid;

    _exitWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid,
                                        DISPATCH_PROC_EXIT, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_exitWatch, ^{
        int status = 0;
        waitpid(pid, &status, 0);
        typeof(self) s = weakSelf;
        if (!s) return;
        dispatch_source_cancel(s->_exitWatch);
        s->_exitWatch = nil;
        s->_child = 0;
        // Let the last of the output drain before the closing prompt.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            [s programExitedWithStatus:WIFEXITED(status) ? WEXITSTATUS(status)
                                                          : 128 + WTERMSIG(status)];
        });
    });
    dispatch_resume(_exitWatch);
    [[QWindowController shared] refreshChrome];
    return YES;
}

- (void)programExitedWithStatus:(int)status {
    // Drain anything still sitting in the pty.
    if (_master >= 0) {
        int flags = fcntl(_master, F_GETFL);
        fcntl(_master, F_SETFL, flags | O_NONBLOCK);
        char buf[8192];
        ssize_t n;
        while ((n = read(_master, buf, sizeof buf)) > 0)
            [self output:[NSData dataWithBytes:buf length:(NSUInteger)n]];
        fcntl(_master, F_SETFL, flags);
    }
    if (_col != 0) [self newline];
    [self put:@"\nPress Enter to return to Quincy..."];
    [self render];
    _waitingForEnter = YES;
    QWindowController *wc = [QWindowController shared];
    [wc showStatus:[NSString stringWithFormat:@"Program exited with status %d", status]];
    [wc refreshChrome];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)terminate {
    if (_child > 0) kill(-_child, SIGKILL), kill(_child, SIGKILL);
}

- (void)typed:(NSData *)bytes {
    if (_waitingForEnter) {
        const char *b = bytes.bytes;
        if (bytes.length && (b[0] == '\r' || b[0] == '\n')) {
            _waitingForEnter = NO;
            [self closePty];
            [self.window orderOut:nil];
            [[QWindowController shared].window makeKeyAndOrderFront:nil];
        }
        return;
    }
    if (_master >= 0) write(_master, bytes.bytes, bytes.length);
}

#pragma mark - Emulation

- (NSMutableString *)currentLine {
    while ((NSInteger)_lines.count <= _row) [_lines addObject:[NSMutableString string]];
    return _lines[_row];
}

- (void)newline {
    _row++;
    _col = 0;
    [self currentLine];
    if (_lines.count > kScrollback) {
        NSUInteger drop = _lines.count - kScrollback;
        [_lines removeObjectsInRange:NSMakeRange(0, drop)];
        _row -= drop;
    }
}

- (void)putCharacter:(unichar)c {
    NSMutableString *line = [self currentLine];
    if (_col >= kColumns) { [self newline]; line = [self currentLine]; }
    while ((NSInteger)line.length < _col) [line appendString:@" "];
    NSString *s = [NSString stringWithCharacters:&c length:1];
    if (_col < (NSInteger)line.length)
        [line replaceCharactersInRange:NSMakeRange(_col, 1) withString:s];
    else
        [line appendString:s];
    _col++;
}

- (void)put:(NSString *)text {
    NSUInteger n = text.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [text characterAtIndex:i];
        if (_escape == 1) { _escape = (c == '[') ? 2 : 0; continue; }
        if (_escape == 2) { if (c >= 0x40 && c <= 0x7e) _escape = 0; continue; }
        switch (c) {
            case 0x1b: _escape = 1; break;
            case '\n': [self newline]; break;
            case '\r': _col = 0; break;
            case '\b': if (_col > 0) _col--; break;
            case '\t': {
                NSInteger next = (_col / 8 + 1) * 8;
                while (_col < next && _col < kColumns) [self putCharacter:' '];
                break;
            }
            case 0x07: NSBeep(); break;
            default:
                if (c >= 0x20) [self putCharacter:c];
        }
    }
}

- (void)output:(NSData *)data {
    // A UTF-8 sequence can be split across reads; keep the tail for next time.
    [_utf8Carry appendData:data];
    const unsigned char *b = _utf8Carry.bytes;
    NSUInteger len = _utf8Carry.length, cut = len;
    for (NSUInteger k = 0; k < 4 && k < len; k++) {
        unsigned char c = b[len - 1 - k];
        if ((c & 0xC0) == 0x80) continue;
        NSUInteger need = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1;
        if (k + 1 < need) cut = len - 1 - k;
        break;
    }
    NSData *ready = [_utf8Carry subdataWithRange:NSMakeRange(0, cut)];
    NSString *s = [[NSString alloc] initWithData:ready encoding:NSUTF8StringEncoding]
               ?: [[NSString alloc] initWithData:ready encoding:NSISOLatin1StringEncoding];
    [_utf8Carry replaceBytesInRange:NSMakeRange(0, cut) withBytes:NULL length:0];
    [self put:s ?: @""];
    [self render];
}

- (NSString *)screenText { return [_lines componentsJoinedByString:@"\n"]; }

- (void)render {
    NSString *text = [self screenText];
    NSDictionary *attrs = @{NSFontAttributeName: [self font],
                            NSForegroundColorAttributeName: QRGB(192, 192, 192)};
    [_view.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:text attributes:attrs]];
    [_view scrollRangeToVisible:NSMakeRange(text.length, 0)];
}

@end

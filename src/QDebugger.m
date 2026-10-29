//
//  QDebugger.m — lldb behind Run, Step, Step Over, Step Out, Watch, Examine.
//
//  The original talked to gdb through pipes; this talks to lldb the same
//  way.  lldb runs synchronously (SetAsync(False)), so each command returns
//  only when the program has stopped again, and a marker printed after every
//  command — script print("@@DONE<n>") — says where its output ends.  The
//  program's own I/O goes to the console window's pty.
//

#import "QChrome.h"
#include <sys/sysctl.h>

@interface QLLDBCommand : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) NSInteger serial;
@property (nonatomic, copy) void (^completion)(NSString *output);
@end
@implementation QLLDBCommand @end

@implementation QDebugger {
    NSTask *_lldb;
    NSFileHandle *_toLLDB;
    NSMutableData *_inbox;
    NSMutableString *_collected;
    NSMutableArray<QLLDBCommand *> *_queue;
    QLLDBCommand *_current;
    NSInteger _serial;
    BOOL _running;              // a run-type command is in flight
    BOOL _stopped;
    BOOL _ending;
    NSInteger _autoFinishes;    // guards the step-out-of-library loop
    NSString *_program;
    QDocumentModel *_stoppedIn;
}

+ (instancetype)shared {
    static QDebugger *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[QDebugger alloc] init]; });
    return shared;
}

- (BOOL)isActive { return _lldb != nil; }
- (BOOL)isStopped { return _lldb != nil && _stopped && !_running; }

#pragma mark - lldb process

- (void)console:(NSString *)text {
    for (NSString *line in [text componentsSeparatedByString:@"\n"])
        if (line.length) [[QWindowController shared] appendConsoleLine:line];
}

- (BOOL)launchLLDB {
    NSString *lldb = @"/usr/bin/lldb";
    _lldb = [[NSTask alloc] init];
    _lldb.executableURL = [NSURL fileURLWithPath:lldb];
    _lldb.arguments = @[@"--no-lldbinit", @"--no-use-colors"];
    NSPipe *in = [NSPipe pipe], *out = [NSPipe pipe];
    _lldb.standardInput = in;
    _lldb.standardOutput = out;
    _lldb.standardError = out;
    _toLLDB = in.fileHandleForWriting;
    _inbox = [NSMutableData data];
    _collected = [NSMutableString string];
    _queue = [NSMutableArray array];
    _current = nil;
    __weak typeof(self) weakSelf = self;
    out.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData;
        if (!d.length) { h.readabilityHandler = nil; return; }
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf received:d]; });
    };
    _lldb.terminationHandler = ^(NSTask *t) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf lldbEnded]; });
    };
    NSError *error = nil;
    if (![_lldb launchAndReturnError:&error]) {
        _lldb = nil;
        [self alert:@"lldb could not be started."
               info:@"Install the Command Line Tools with xcode-select --install."];
        return NO;
    }
    [self console:@"(lldb started)"];
    for (NSString *c in @[
        @"script lldb.debugger.SetAsync(False)",
        @"settings set use-color false",
        @"settings set auto-confirm true",
        @"settings set stop-line-count-before 0",
        @"settings set stop-line-count-after 0",
        @"settings set stop-disassembly-display never",
        @"settings set frame-format \"@@F ${line.file.fullpath}:${line.number}:${function.name}\\n\"",
        @"settings set thread-stop-format \"@@S ${thread.stop-reason}\\n\"",
    ]) [self send:c then:nil];
    return YES;
}

- (void)send:(NSString *)text then:(void (^)(NSString *output))completion {
    if (!_lldb) return;
    QLLDBCommand *c = [[QLLDBCommand alloc] init];
    c.text = text;
    c.serial = ++_serial;
    c.completion = completion;
    [_queue addObject:c];
    [self pump];
}

- (void)pump {
    if (_current || !_queue.count || !_lldb) return;
    _current = _queue.firstObject;
    [_queue removeObjectAtIndex:0];
    [_collected setString:@""];
    [self console:[@"(lldb) " stringByAppendingString:_current.text]];
    NSString *wire = [NSString stringWithFormat:@"%@\nscript print(\"@@DONE%ld\")\n",
                      _current.text, (long)_current.serial];
    @try { [_toLLDB writeData:[wire dataUsingEncoding:NSUTF8StringEncoding]]; }
    @catch (NSException *e) { [self lldbEnded]; }
}

- (void)received:(NSData *)data {
    [_inbox appendData:data];
    NSData *nl = [NSData dataWithBytes:"\n" length:1];
    while (YES) {
        NSRange r = [_inbox rangeOfData:nl options:0 range:NSMakeRange(0, _inbox.length)];
        if (r.location == NSNotFound) break;
        NSString *line = [[NSString alloc] initWithData:
                          [_inbox subdataWithRange:NSMakeRange(0, r.location)]
                                               encoding:NSUTF8StringEncoding] ?: @"";
        [_inbox replaceBytesInRange:NSMakeRange(0, r.location + 1) withBytes:NULL length:0];
        while ([line hasPrefix:@"(lldb) "]) line = [line substringFromIndex:7];
        if (_current && [line isEqual:[NSString stringWithFormat:@"@@DONE%ld",
                                       (long)_current.serial]]) {
            QLLDBCommand *done = _current;
            NSString *output = [_collected copy];
            _current = nil;
            if (done.completion) done.completion(output);
            [self pump];
            continue;
        }
        // lldb echoes what it reads from a pipe; the console shows each
        // command once, and never the end markers.
        if (_current && [line isEqual:_current.text]) continue;
        if ([line hasPrefix:@"script print(\"@@DONE"]) continue;
        if (line.length) [self console:line];
        [_collected appendString:line];
        [_collected appendString:@"\n"];
    }
}

- (void)lldbEnded {
    if (!_lldb) return;
    _lldb = nil;
    _toLLDB = nil;
    _running = NO;
    _stopped = NO;
    [_queue removeAllObjects];
    _current = nil;
    [self clearCurrentLine];
    [self console:@"(lldb ended)"];
    [[QWindowController shared] refreshChrome];
}

- (void)alert:(NSString *)message info:(NSString *)info {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = message;
    a.informativeText = info ?: @"";
    a.alertStyle = NSAlertStyleWarning;
    [a beginSheetModalForWindow:[QWindowController shared].window completionHandler:nil];
}

#pragma mark - Breakpoints

- (NSArray<NSString *> *)breakpointCommands {
    NSMutableArray *cmds = [NSMutableArray array];
    for (QDocumentModel *d in [QWindowController shared].documents) {
        if (!d.url) continue;
        [d.breakpoints enumerateIndexesUsingBlock:^(NSUInteger line, BOOL *stop) {
            [cmds addObject:[NSString stringWithFormat:@"breakpoint set -f \"%@\" -l %lu",
                             d.url.path, (unsigned long)line + 1]];
        }];
    }
    return cmds;
}

/// Breakpoints set while the program runs wait in lldb's input until it next
/// stops — the queue the original kept by hand comes free with synchronous
/// mode.  Each change replaces the whole set; it is never large.
- (void)breakpointsChanged {
    if (!_lldb) return;
    [self send:@"breakpoint delete" then:nil];
    for (NSString *c in [self breakpointCommands]) [self send:c then:nil];
}

#pragma mark - Running

- (void)startProgram:(NSString *)path arguments:(NSArray<NSString *> *)args
           directory:(NSString *)dir {
    [self startProgram:path arguments:args directory:dir extra:nil];
}

- (void)startProgram:(NSString *)path arguments:(NSArray<NSString *> *)args
           directory:(NSString *)dir extra:(NSArray<NSString *> *)extra {
    if (_lldb) return;
    QConsoleWindowController *console = [QConsoleWindowController shared];
    NSString *tty = [console openTerminalForTitle:path.lastPathComponent];
    if (!tty || ![self launchLLDB]) return;
    _program = path;
    _ending = NO;
    _autoFinishes = 0;
    [[QWindowController shared] showBottomTab:1];
    [self send:[NSString stringWithFormat:@"target create \"%@\"", path] then:nil];
    for (NSString *c in [self breakpointCommands]) [self send:c then:nil];
    for (NSString *c in extra) [self send:c then:nil];

    NSMutableString *launch = [NSMutableString stringWithFormat:
        @"process launch -i %@ -o %@ -e %@ -w \"%@\"", tty, tty, tty,
        dir.length ? dir : path.stringByDeletingLastPathComponent];
    if (args.count) {
        [launch appendString:@" --"];
        for (NSString *a in args)
            [launch appendFormat:@" \"%@\"",
             [a stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    }
    [self runCommand:launch];
}

/// Every command that lets the program run goes through here; its output
/// says where the program stopped or that it has ended.
- (void)runCommand:(NSString *)command {
    _running = YES;
    _stopped = NO;
    [self clearCurrentLine];
    [[QWindowController shared] showStatus:@"Running…"];
    [[QWindowController shared] refreshChrome];
    __weak typeof(self) weakSelf = self;
    [self send:command then:^(NSString *output) { [weakSelf afterRun:output]; }];
}

- (void)afterRun:(NSString *)output {
    _running = NO;
    QWindowController *wc = [QWindowController shared];

    NSRegularExpression *exited = [NSRegularExpression
        regularExpressionWithPattern:@"Process \\d+ exited with status = (-?\\d+)"
                             options:0 error:NULL];
    NSTextCheckingResult *m = [exited firstMatchInString:output options:0
                                                   range:NSMakeRange(0, output.length)];
    if (m) {
        int status = [[output substringWithRange:[m rangeAtIndex:1]] intValue];
        [self finishSession];
        [[QConsoleWindowController shared] programExitedWithStatus:status];
        return;
    }
    if ([output containsString:@"error: "] &&
        ([output containsString:@"attach failed"] ||
         [output containsString:@"not allowed"] ||
         [output containsString:@"Not allowed"] ||
         [output containsString:@"debugserver"])) {
        [self finishSession];
        [self alert:@"macOS did not allow Quincy to debug the program."
               info:@"Enable developer mode for the debugger once in Terminal:\n\n"
                     "sudo DevToolsSecurity -enable\n\nThen run the program again."];
        return;
    }
    if (![output containsString:@"@@S"] && ![output containsString:@"@@F"]) {
        // No stop and no exit: launch failed outright.
        if ([output containsString:@"error:"]) {
            NSRange e = [output rangeOfString:@"error:"];
            [wc showStatus:[[output substringFromIndex:e.location]
                            componentsSeparatedByString:@"\n"].firstObject];
            [self finishSession];
            return;
        }
    }

    // The last frame line is where the program now is.
    NSString *where = nil;
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSRange f = [line rangeOfString:@"@@F "];
        if (f.location != NSNotFound) where = [line substringFromIndex:NSMaxRange(f)];
    }
    NSString *file = nil;
    NSInteger lineNo = 0;
    if (where) {
        NSArray *parts = [where componentsSeparatedByString:@":"];
        if (parts.count >= 3) {
            file = parts[0];
            lineNo = [parts[1] integerValue];
        }
    }
    BOOL known = file.length && lineNo > 0 &&
                 [NSFileManager.defaultManager fileExistsAtPath:file];
    if (!known) {
        // Stopped inside a library with no source: step back out to the
        // caller, as the original did with gdb.
        if (_autoFinishes++ < 8) { [self runCommand:@"finish"]; return; }
        _autoFinishes = 0;
        _stopped = YES;
        [wc showStatus:@"Stopped where there is no source"];
        [wc refreshChrome];
        return;
    }
    _autoFinishes = 0;
    _stopped = YES;
    QDocumentModel *doc = [wc openURL:[NSURL fileURLWithPath:file]];
    if (doc) {
        doc.currentLine = (NSUInteger)(lineNo - 1);
        _stoppedIn = doc;
        [wc.window makeKeyAndOrderFront:nil];
        [[wc editorForDocument:doc] goToLine:lineNo column:1];
        [wc refreshGuttersForDocument:doc];
    }
    [wc showStatus:[NSString stringWithFormat:@"Stopped at %@, line %ld",
                    file.lastPathComponent, (long)lineNo]];
    [wc refreshChrome];
    [self refreshWatches];
}

- (void)clearCurrentLine {
    if (!_stoppedIn) return;
    _stoppedIn.currentLine = NSNotFound;
    [[QWindowController shared] refreshGuttersForDocument:_stoppedIn];
    _stoppedIn = nil;
}

- (void)finishSession {
    if (!_lldb || _ending) return;
    _ending = YES;
    _stopped = NO;
    [self clearCurrentLine];
    [self send:@"quit" then:nil];
    NSTask *lldb = _lldb;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (lldb.isRunning) [lldb terminate];
    });
    [[QWindowController shared] refreshChrome];
}

#pragma mark - Commands

- (void)continueRunning { if (self.stopped) [self runCommand:@"continue"]; }

/// The LLDB Console's input line.  Commands that let the program run go
/// through runCommand: so the next stop is followed in the editor; quitting
/// is Stop; anything else is passed on and its answer shows in the console.
- (void)sendUserCommand:(NSString *)text {
    NSCharacterSet *space = NSCharacterSet.whitespaceCharacterSet;
    text = [text stringByTrimmingCharactersInSet:space];
    if (!text.length || !_lldb) { NSBeep(); return; }
    NSString *verb = [text componentsSeparatedByCharactersInSet:space].firstObject;
    static NSSet *resuming, *ending, *launching;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        resuming = [NSSet setWithArray:@[@"c", @"continue", @"n", @"next", @"s",
            @"step", @"si", @"stepi", @"ni", @"nexti", @"finish", @"until", @"u"]];
        ending = [NSSet setWithArray:@[@"q", @"quit", @"exit", @"kill"]];
        launching = [NSSet setWithArray:@[@"r", @"run", @"process launch"]];
    });
    BOOL threadRun = [verb isEqual:@"thread"] &&
        ([text containsString:@" step"] || [text containsString:@" continue"] ||
         [text containsString:@" until"]);
    if ([ending containsObject:verb] || [text hasPrefix:@"process kill"]) {
        [self stop];
    } else if ([launching containsObject:verb] || [text hasPrefix:@"process launch"]) {
        [self console:@"The program is already running; use Stop, then Run."];
    } else if ([resuming containsObject:verb] || threadRun ||
               [text hasPrefix:@"process continue"]) {
        if (self.stopped) [self runCommand:text];
        else [self console:@"The program is running; pause it at a breakpoint first."];
    } else {
        __weak typeof(self) weakSelf = self;
        [self send:text then:^(NSString *output) {
            if (weakSelf.stopped) [weakSelf refreshWatches];
        }];
    }
}
- (void)step           { if (self.stopped) [self runCommand:@"thread step-in"]; }
- (void)stepOver       { if (self.stopped) [self runCommand:@"thread step-over"]; }
- (void)stepOut        { if (self.stopped) [self runCommand:@"finish"]; }

- (void)runToFile:(NSString *)file line:(NSInteger)line {
    if (!self.stopped) return;
    [self send:[NSString stringWithFormat:@"breakpoint set -o true -f \"%@\" -l %ld",
                file, (long)line] then:nil];
    [self runCommand:@"continue"];
}

/// Descendants of lldb other than its debug server: that is the program.
- (NSArray<NSNumber *> *)inferiorPIDs {
    if (!_lldb) return @[];
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0) return @[];
    struct kinfo_proc *procs = malloc(size);
    if (sysctl(mib, 3, procs, &size, NULL, 0) != 0) { free(procs); return @[]; }
    size_t n = size / sizeof(struct kinfo_proc);
    NSMutableSet *family = [NSMutableSet setWithObject:@(_lldb.processIdentifier)];
    NSMutableArray *found = [NSMutableArray array];
    BOOL grew = YES;
    while (grew) {
        grew = NO;
        for (size_t i = 0; i < n; i++) {
            NSNumber *pid = @(procs[i].kp_proc.p_pid);
            if ([family containsObject:pid]) continue;
            if (![family containsObject:@(procs[i].kp_eproc.e_ppid)]) continue;
            [family addObject:pid];
            grew = YES;
            NSString *name = @(procs[i].kp_proc.p_comm);
            if (![name hasPrefix:@"debugserver"] && ![name hasPrefix:@"lldb"])
                [found addObject:pid];
        }
    }
    free(procs);
    return found;
}

- (void)stop {
    if (!_lldb) return;
    for (NSNumber *pid in [self inferiorPIDs]) kill(pid.intValue, SIGKILL);
    if (self.stopped) {
        // The program is paused, so lldb is listening: let it do the killing.
        [self send:@"process kill" then:nil];
        [self finishSession];
        [[QConsoleWindowController shared] programExitedWithStatus:SIGKILL + 128];
    }
    // Otherwise the run in flight comes back with "exited", and afterRun:
    // closes the session.
}

#pragma mark - Examine and Watch

- (void)evaluate:(NSString *)expression
      completion:(void (^)(NSString *value, NSString *error))completion {
    if (!self.stopped) { completion(nil, @"The program is not stopped"); return; }
    [self send:[@"expression -- " stringByAppendingString:expression]
          then:^(NSString *output) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSRange err = [trimmed rangeOfString:@"error:"];
        if (err.location != NSNotFound) {
            completion(nil, [[trimmed substringFromIndex:err.location + 6]
                             stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceCharacterSet]);
            return;
        }
        // "(int) $0 = 42" — keep what follows the first " = ".
        NSRange eq = [trimmed rangeOfString:@" = "];
        completion(eq.location != NSNotFound
                   ? [trimmed substringFromIndex:NSMaxRange(eq)] : trimmed, nil);
    }];
}

- (void)refreshWatches {
    QWindowController *wc = [QWindowController shared];
    for (NSString *expr in [wc watchExpressions]) {
        [self evaluate:expr completion:^(NSString *value, NSString *error) {
            [wc setWatchValue:value ?: @"??" forExpression:expr];
        }];
    }
}

@end

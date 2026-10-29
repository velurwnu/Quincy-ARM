//
//  QBuilder.m — Compile, Build, Rebuild All, Link, Stop.
//
//  The original drove MinGW's gcc; this drives clang with the same options
//  mapped flag for flag (HANDOFF.md has the table): -gstabs became -g, -O4
//  ("for space") is -Os, and -fshort-enums is gone because the Mac ABI
//  forbids it.  Commands run one at a time on NSTask; each command line goes
//  into the build log ahead of its output, as it did in the Build window.
//

#import "QChrome.h"


@interface QBuildJob : NSObject
@property (nonatomic, copy) NSString *tool;
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic, copy) NSString *directory;
@end
@implementation QBuildJob @end

@implementation QBuilder {
    NSMutableArray<QBuildJob *> *_queue;
    NSTask *_task;
    NSMutableData *_pending;
    BOOL _stopped;
    BOOL _failed;
    NSString *_target;
    void (^_completion)(BOOL ok, NSString *target);
}

+ (instancetype)shared {
    static QBuilder *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[QBuilder alloc] init]; });
    return shared;
}

- (BOOL)isBusy { return _task != nil || _queue.count > 0; }

#pragma mark - Flags

static NSArray<NSString *> *SplitList(NSString *s, NSString *separators) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *part in [s componentsSeparatedByCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:separators]]) {
        NSString *t = [part stringByTrimmingCharactersInSet:
                       NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length) [out addObject:t];
    }
    return out;
}

static BOOL IsCPlusPlus(NSString *path) {
    return ![path.pathExtension.lowercaseString isEqual:@"c"];
}

static NSString *ObjectPath(NSString *source) {
    return [source.stringByDeletingPathExtension stringByAppendingPathExtension:@"o"];
}

/// clang's -MMD list of the headers an object was built from.  It lives in
/// the caches folder rather than beside the sources, which keep only the .o
/// files the original left there.
static NSString *DependencyPath(NSString *object) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory
                                                             inDomains:NSUserDomainMask].firstObject;
        dir = [[caches.path stringByAppendingPathComponent:
                NSBundle.mainBundle.bundleIdentifier ?: @"Quincy"]
               stringByAppendingPathComponent:@"Dependencies"];
        [NSFileManager.defaultManager createDirectoryAtPath:dir
                                withIntermediateDirectories:YES attributes:nil error:NULL];
    });
    uint64_t h = 1469598103934665603ULL;    // FNV-1a of the full path
    for (const char *c = object.fileSystemRepresentation; *c; c++)
        h = (h ^ (uint8_t)*c) * 1099511628211ULL;
    return [dir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@-%016llx.d", object.lastPathComponent, h]];
}

/// The prerequisites in a make-style .d file, with escaped spaces undone.
static NSArray<NSString *> *ReadDependencies(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding error:NULL];
    NSRange colon = [text rangeOfString:@": "];
    if (colon.location == NSNotFound) return nil;
    text = [[text substringFromIndex:NSMaxRange(colon)]
            stringByReplacingOccurrencesOfString:@"\\\n" withString:@" "];
    text = [text stringByReplacingOccurrencesOfString:@"\\ " withString:@"\x01"];
    NSMutableArray *deps = [NSMutableArray array];
    for (NSString *word in [text componentsSeparatedByCharactersInSet:
                            NSCharacterSet.whitespaceAndNewlineCharacterSet])
        if (word.length)
            [deps addObject:[word stringByReplacingOccurrencesOfString:@"\x01"
                                                            withString:@" "]];
    return deps;
}

- (NSString *)compilerFor:(BOOL)cplusplus {
    NSString *c = [[QOptions shared] compilerPath];
    if (!cplusplus) return c;
    NSString *cxx = [c stringByAppendingString:@"++"];
    return [NSFileManager.defaultManager isExecutableFileAtPath:cxx] ? cxx : c;
}

/// Options ▸ Build, as the original turned them into a gcc command line.
- (NSArray<NSString *> *)compileFlagsFor:(NSString *)source project:(QProject *)project {
    QOptions *o = [QOptions shared];
    BOOL cpp = IsCPlusPlus(source);
    NSMutableArray *a = [NSMutableArray array];
    if (o.debugInfo) [a addObject:@"-g"];
    switch (o.optimize) {
        case 1: [a addObject:@"-O1"]; break;
        case 2: [a addObject:@"-O2"]; break;
        case 3: [a addObject:@"-O3"]; break;
        case 4: [a addObject:@"-Os"]; break;
        default: break;
    }
    if (cpp && !o.rtti) [a addObject:@"-fno-rtti"];
    if (cpp && !o.exceptions) [a addObject:@"-fno-exceptions"];
    if (o.strictAnsi) {
        [a addObjectsFromArray:@[@"-pedantic-errors", @"-Wno-long-long",
                                 cpp ? @"-std=c++98" : @"-std=iso9899:199409"]];
    } else if (o.c99 && !cpp) {
        [a addObjectsFromArray:@[@"-std=c99", @"-fgnu89-inline"]];
    }
    if (o.warnings == QWarningsAll)
        [a addObjectsFromArray:@[@"-Wall", @"-Wextra", @"-Wconversion", @"-Wshadow",
                                 @"-Wpointer-arith", @"-Wcast-qual", @"-Wcast-align",
                                 @"-Wwrite-strings", @"-fno-common"]];
    else if (o.warnings == QWarningsNone)
        [a addObject:@"-w"];
    NSString *defines = [NSString stringWithFormat:@"%@;%@", o.defines ?: @"",
                         project.defines ?: @""];
    for (NSString *d in SplitList(defines, @";"))
        [a addObject:[@"-D" stringByAppendingString:d]];
    NSString *includes = [NSString stringWithFormat:@"%@;%@", o.includes ?: @"",
                          project.includes ?: @""];
    for (NSString *i in SplitList(includes, @";"))
        [a addObject:[@"-I" stringByAppendingString:
                      project ? [project absolutePath:i] : i]];
    [a addObjectsFromArray:SplitList(o.compilerOptions, @" ")];
    // Diagnostics the build log can parse: one line each, no colour.
    [a addObjectsFromArray:@[@"-fno-color-diagnostics", @"-fno-caret-diagnostics"]];
    return a;
}

- (NSArray<NSString *> *)linkFlagsForProject:(QProject *)project {
    QOptions *o = [QOptions shared];
    NSMutableArray *a = [NSMutableArray array];
    if (o.debugInfo) [a addObject:@"-g"];
    NSString *libs = [NSString stringWithFormat:@"%@;%@", o.libraries ?: @"",
                      project.libraries ?: @""];
    // A folder is a search path (-L), a bare name is a library (-l).
    for (NSString *l in SplitList(libs, @";")) {
        if ([l containsString:@"/"]) [a addObject:[@"-L" stringByAppendingString:l]];
        else [a addObject:[@"-l" stringByAppendingString:
                           [l hasPrefix:@"lib"] ? [l substringFromIndex:3] : l]];
    }
    [a addObjectsFromArray:SplitList(o.linkerOptions, @" ")];
    return a;
}

#pragma mark - Dates

static NSDate *ModDate(NSString *path) {
    return [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL]
        .fileModificationDate;
}

static BOOL Newer(NSString *a, NSString *b) {   // is a newer than b (or b missing)?
    NSDate *da = ModDate(a), *db = ModDate(b);
    if (!db) return YES;
    if (!da) return NO;
    return [da compare:db] == NSOrderedDescending;
}

- (NSArray<NSString *> *)sourcesFor:(QProject *)project document:(QDocumentModel *)doc {
    if (project) return [project sourcePaths];
    if (doc.url && [doc isSourceFile]) return @[doc.url.path];
    return @[];
}

- (NSString *)targetPathForProject:(QProject *)project document:(QDocumentModel *)doc {
    if (project) return [project targetPath];
    if (doc.url && [doc isSourceFile]) return doc.url.path.stringByDeletingPathExtension;
    return nil;
}

/// The object is stale when its source or any header it included is newer.
/// Without a dependency list (an object from an older build), the project's
/// own headers stand in for it.
- (BOOL)isObjectOutOfDate:(NSString *)source headers:(NSArray *)headers {
    NSString *obj = ObjectPath(source);
    if (Newer(source, obj)) return YES;
    NSString *depFile = DependencyPath(obj);
    NSArray *deps = ReadDependencies(depFile);
    for (NSString *h in deps ?: headers) {
        NSString *full = h.isAbsolutePath ? h
            : [source.stringByDeletingLastPathComponent stringByAppendingPathComponent:h];
        if (Newer(full, obj)) return YES;
    }
    return NO;
}

- (BOOL)isTargetOutOfDateForProject:(QProject *)project document:(QDocumentModel *)doc {
    NSString *target = [self targetPathForProject:project document:doc];
    if (!target || !ModDate(target)) return YES;
    NSArray *headers = project ? [project headerPaths] : @[];
    for (NSString *src in [self sourcesFor:project document:doc]) {
        if ([self isObjectOutOfDate:src headers:headers]) return YES;
        if (Newer(src, target)) return YES;
    }
    for (NSString *a in project.archivePaths) if (Newer(a, target)) return YES;
    return NO;
}

/// The original asked "No debug information. Run anyway?" when the program
/// was built without -g; a dSYM-less Mac binary keeps its DWARF in the .o
/// files, so the test is whether the debug map is there.
- (BOOL)targetHasDebugInfo:(NSString *)path {
    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/nm"];
    t.arguments = @[@"-ap", path];
    NSPipe *pipe = [NSPipe pipe];
    t.standardOutput = pipe;
    t.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![t launchAndReturnError:NULL]) return YES;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [s containsString:@" OSO "] || [s containsString:@" SO "];
}

#pragma mark - Commands

- (void)log:(NSString *)text {
    [[QWindowController shared] appendBuildMessage:[QBuildMessage messageWithText:text]];
}

/// Everything is saved first, as the original did before a build.
- (void)saveAll {
    QWindowController *wc = [QWindowController shared];
    for (QDocumentModel *d in wc.documents)
        if (d.dirty && d.url) [wc saveDocument:d as:NO];
}

- (void)compileDocument:(QDocumentModel *)doc {
    if (self.busy || !doc) return;
    QWindowController *wc = [QWindowController shared];
    if (!doc.url && ![wc saveDocument:doc as:NO]) return;
    [self saveAll];
    if (![doc isSourceFile]) { NSBeep(); return; }
    [wc clearBuildLog];
    NSString *src = doc.url.path;
    QBuildJob *job = [self compileJobFor:src project:nil];
    [self runJobs:@[job] target:ObjectPath(src) completion:nil];
}

- (QBuildJob *)compileJobFor:(NSString *)src project:(QProject *)project {
    QBuildJob *job = [[QBuildJob alloc] init];
    job.tool = [self compilerFor:IsCPlusPlus(src)];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-c", src, @"-o",
                            ObjectPath(src), @"-MMD", @"-MF",
                            DependencyPath(ObjectPath(src)), nil];
    [args addObjectsFromArray:[self compileFlagsFor:src project:project]];
    job.arguments = args;
    job.directory = src.stringByDeletingLastPathComponent;
    return job;
}

- (void)buildProject:(QProject *)project document:(QDocumentModel *)doc
             rebuild:(BOOL)rebuild linkOnly:(BOOL)linkOnly
          completion:(void (^)(BOOL ok, NSString *target))completion {
    if (self.busy) return;
    QWindowController *wc = [QWindowController shared];
    if (!project && doc && !doc.url && ![wc saveDocument:doc as:NO]) return;
    [self saveAll];

    NSArray<NSString *> *sources = [self sourcesFor:project document:doc];
    NSString *target = [self targetPathForProject:project document:doc];
    if (!sources.count || !target) {
        [wc showStatus:@"There is nothing to build"];
        NSBeep();
        if (completion) completion(NO, nil);
        return;
    }
    if (project && project.type >= QProjectWin32GUI) {
        [wc clearBuildLog];
        [self log:@"This project type needs Windows libraries and is not available on macOS."];
        [self log:@"Unsuccessful build"];
        if (completion) completion(NO, nil);
        return;
    }

    [wc clearBuildLog];
    [self log:@"Checking dependencies"];
    NSArray *headers = project ? [project headerPaths] : @[];
    NSMutableArray<QBuildJob *> *jobs = [NSMutableArray array];
    BOOL cpp = NO;
    for (NSString *src in sources) {
        if (IsCPlusPlus(src)) cpp = YES;
        if (linkOnly) continue;
        if (rebuild || [self isObjectOutOfDate:src headers:headers])
            [jobs addObject:[self compileJobFor:src project:project]];
    }
    if (!rebuild && !jobs.count && ![self isTargetOutOfDateForProject:project document:doc]) {
        [self log:[NSString stringWithFormat:@"%@ is up to date",
                   target.lastPathComponent]];
        if (completion) completion(YES, target);
        return;
    }

    NSMutableArray *objects = [NSMutableArray array];
    for (NSString *src in sources) [objects addObject:ObjectPath(src)];

    QBuildJob *link = [[QBuildJob alloc] init];
    link.directory = target.stringByDeletingLastPathComponent;
    QProjectType type = project ? project.type : QProjectConsole;
    if (type == QProjectLibrary) {
        // `ar rc` as in the original, plus `s` for the symbol index that the
        // Mac linker insists on.
        [NSFileManager.defaultManager removeItemAtPath:target error:NULL];
        link.tool = @"/usr/bin/ar";
        link.arguments = [@[@"rcs", target] arrayByAddingObjectsFromArray:objects];
    } else {
        link.tool = [self compilerFor:cpp];
        NSMutableArray *args = [NSMutableArray array];
        if (type == QProjectDylib)
            [args addObjectsFromArray:@[@"-dynamiclib", @"-install_name",
                                        [@"@rpath/" stringByAppendingString:
                                         target.lastPathComponent]]];
        [args addObjectsFromArray:objects];
        [args addObjectsFromArray:project.archivePaths ?: @[]];
        [args addObjectsFromArray:@[@"-o", target]];
        [args addObjectsFromArray:[self linkFlagsForProject:project]];
        // Programs find a project's own .dylib next to themselves.
        [args addObjectsFromArray:@[@"-Wl,-rpath,@executable_path"]];
        link.arguments = args;
    }
    [jobs addObject:link];
    [self runJobs:jobs target:target completion:completion];
}

#pragma mark - Running jobs

- (void)runJobs:(NSArray<QBuildJob *> *)jobs target:(NSString *)target
     completion:(void (^)(BOOL ok, NSString *target))completion {
    _queue = [jobs mutableCopy];
    _target = target;
    _completion = completion;
    _stopped = NO;
    _failed = NO;
    QWindowController *wc = [QWindowController shared];
    [wc showStatus:@"Building…"];
    [wc refreshChrome];
    [self next];
}

- (void)next {
    if (_stopped || _failed || !_queue.count) { [self finish]; return; }
    QBuildJob *job = _queue.firstObject;
    [_queue removeObjectAtIndex:0];

    // The command as the user would type it; the dependency bookkeeping is
    // Quincy's business and stays out of the log.
    NSMutableArray *shown = [NSMutableArray arrayWithObject:job.tool.lastPathComponent];
    for (NSUInteger i = 0; i < job.arguments.count; i++) {
        NSString *a = job.arguments[i];
        if ([a isEqual:@"-MMD"]) continue;
        if ([a isEqual:@"-MF"]) { i++; continue; }
        [shown addObject:[a containsString:@" "]
                         ? [NSString stringWithFormat:@"\"%@\"", a] : a];
    }
    [self log:[shown componentsJoinedByString:@" "]];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:job.tool];
    task.arguments = job.arguments;
    task.currentDirectoryURL = [NSURL fileURLWithPath:job.directory];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    _pending = [NSMutableData data];
    __weak typeof(self) weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData;
        if (!d.length) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf received:d]; });
    };
    task.terminationHandler = ^(NSTask *t) {
        pipe.fileHandleForReading.readabilityHandler = nil;
        NSData *rest = [pipe.fileHandleForReading readDataToEndOfFile];
        int status = t.terminationStatus;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) s = weakSelf;
            if (!s) return;
            if (rest.length) [s received:rest];
            [s flushPending];
            s->_task = nil;
            if (status != 0) s->_failed = YES;
            [s next];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self log:[NSString stringWithFormat:@"Cannot run %@: %@", job.tool,
                   error.localizedDescription]];
        _failed = YES;
        [self finish];
        return;
    }
    _task = task;
}

- (void)received:(NSData *)data {
    [_pending appendData:data];
    while (YES) {
        NSRange nl = [_pending rangeOfData:[NSData dataWithBytes:"\n" length:1]
                                   options:0 range:NSMakeRange(0, _pending.length)];
        if (nl.location == NSNotFound) break;
        NSData *line = [_pending subdataWithRange:NSMakeRange(0, nl.location)];
        [_pending replaceBytesInRange:NSMakeRange(0, nl.location + 1)
                            withBytes:NULL length:0];
        [self emitLine:[[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding]
                       ?: @""];
    }
}

- (void)flushPending {
    if (_pending.length)
        [self emitLine:[[NSString alloc] initWithData:_pending
                                             encoding:NSUTF8StringEncoding] ?: @""];
    _pending = [NSMutableData data];
}

/// `file:line:col: error: text` becomes a message that a double-click opens.
- (void)emitLine:(NSString *)line {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^(.+?):(\\d+):(?:(\\d+):)?\\s"
                                                       options:0 error:NULL];
    });
    QBuildMessage *m = [QBuildMessage messageWithText:line];
    NSTextCheckingResult *r = [re firstMatchInString:line options:0
                                               range:NSMakeRange(0, line.length)];
    if (r) {
        NSString *path = [line substringWithRange:[r rangeAtIndex:1]];
        if (!path.isAbsolutePath && _task.currentDirectoryURL)
            path = [_task.currentDirectoryURL.path stringByAppendingPathComponent:path];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
            m.path = path;
            // Show the file name, keep the full path for the jump.
            m.text = [path.lastPathComponent stringByAppendingString:
                      [line substringFromIndex:[r rangeAtIndex:1].length]];
            m.line = [[line substringWithRange:[r rangeAtIndex:2]] integerValue];
            NSRange col = [r rangeAtIndex:3];
            m.column = col.location != NSNotFound
                ? [[line substringWithRange:col] integerValue] : 1;
        }
    }
    [[QWindowController shared] appendBuildMessage:m];
}

- (void)finish {
    QWindowController *wc = [QWindowController shared];
    BOOL ok = !_failed && !_stopped;
    NSString *result = _stopped ? @"Build stopped by user"
                     : (ok ? @"Successful build" : @"Unsuccessful build");
    [self log:result];
    [wc showStatus:result];
    [_queue removeAllObjects];
    _task = nil;
    void (^done)(BOOL, NSString *) = _completion;
    _completion = nil;
    [wc refreshChrome];
    if (done) done(ok, _target);
}

- (void)stop {
    if (!self.busy) return;
    _stopped = YES;
    [_queue removeAllObjects];
    [_task terminate];
}

@end

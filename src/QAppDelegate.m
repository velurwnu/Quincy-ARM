//
//  QAppDelegate.m — the menu bar, the session and the F-key accelerators.
//
//  The menus carry the original's items in the original order, re-grouped
//  only where macOS insists (About and Settings belong in the application
//  menu, Quit is not a File item).  Highlighting an item puts its help
//  string in the status bar, which is what the Windows version did.
//

#import "QChrome.h"

@interface QAppDelegate () <NSMenuDelegate, NSMenuItemValidation>
- (BOOL)handleKeyEvent:(NSEvent *)event;
@end

@implementation QAppDelegate {
    NSMenu *_recentMenu;
    id      _keyMonitor;
}

#pragma mark - Launch

- (void)applicationWillFinishLaunching:(NSNotification *)note {
    [self buildMenuBar];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    QWindowController *wc = [QWindowController shared];
    [wc showWindow:nil];
    [wc.window makeKeyAndOrderFront:nil];
    [self restoreSession];
    [self installKeyMonitor];
    [self rebuildRecentMenu];
    [wc showStatus:@"Ready"];
    [self snapshotIfRequested];
}

/// QUINCY_SNAPSHOT=<png> renders the window to a file and quits: a way to see
/// the UI without screen-recording permission.  QUINCY_OPEN opens a file
/// first; QUINCY_SNAPSHOT_SETTINGS=1 shoots the Settings window instead.
/// QUINCY_SCRIPT drives the app for automated checks: `;`-separated steps —
/// a command id, `wait:secs`, `shot:path` (screencapture of the key window),
/// `line:n`, `bp:n`, `key:text` (typed into the console), `watch:expr`,
/// `open:path`, `log:path` (build log and console to a file), `quit`.
- (void)runScriptSteps:(NSMutableArray<NSString *> *)steps {
    QWindowController *wc = [QWindowController shared];
    while (steps.count) {
        NSString *step = steps.firstObject;
        [steps removeObjectAtIndex:0];
        NSRange colon = [step rangeOfString:@":"];
        NSString *verb = colon.location == NSNotFound ? step : [step substringToIndex:colon.location];
        NSString *arg = colon.location == NSNotFound ? @"" : [step substringFromIndex:colon.location + 1];
        if ([verb isEqual:@"wait"]) {
            // Real use is event-driven, and undo groups close per event; a
            // dummy event ends each scripted step the same way.
            [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
                location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
                context:nil subtype:0 data1:0 data2:0] atStart:NO];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(arg.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self runScriptSteps:steps]; });
            return;
        }
        if ([verb isEqual:@"shot"]) {
            NSWindow *w = NSApp.keyWindow ?: wc.window;
            if ([arg hasPrefix:@"settings="]) {
                w = [QSettingsWindowController shared].window;
                arg = [arg substringFromIndex:9];
            }
            if ([arg hasPrefix:@"panel="]) {   // e.g. the About panel
                for (NSWindow *x in NSApp.windows)
                    if (x.isVisible && [x isKindOfClass:NSPanel.class]) w = x;
                arg = [arg substringFromIndex:6];
            }
            if ([arg hasPrefix:@"console="]) {
                w = [QConsoleWindowController shared].window;
                arg = [arg substringFromIndex:8];
            }
            NSTask *t = [NSTask launchedTaskWithExecutableURL:
                [NSURL fileURLWithPath:@"/usr/sbin/screencapture"]
                arguments:@[@"-x", @"-o", @"-l", [NSString stringWithFormat:@"%ld", (long)w.windowNumber], arg]
                error:NULL terminationHandler:nil];
            [t waitUntilExit];
        } else if ([verb isEqual:@"line"]) {
            [wc.activeEditor goToLine:arg.integerValue column:1];
        } else if ([verb isEqual:@"bp"]) {
            [wc.activeEditor toggleBreakpointAtLine:arg.integerValue - 1];
        } else if ([verb isEqual:@"key"]) {
            NSString *text = [arg stringByReplacingOccurrencesOfString:@"\\r" withString:@"\r"];
            [[QConsoleWindowController shared] performSelector:@selector(typed:)
                withObject:[text dataUsingEncoding:NSUTF8StringEncoding]];
        } else if ([verb isEqual:@"watch"]) {
            [wc performSelector:@selector(addWatchExpression:) withObject:arg];
        } else if ([verb isEqual:@"open"]) {
            [wc openURL:[NSURL fileURLWithPath:arg]];
        } else if ([verb isEqual:@"log"]) {
            [[wc performSelector:@selector(transcript)] writeToFile:arg atomically:YES
                                                         encoding:NSUTF8StringEncoding error:NULL];
        } else if ([verb isEqual:@"grep"]) {
            NSString *folder = wc.activeDocument.url.URLByDeletingLastPathComponent.path;
            [QGrepSheet runGrep:arg folder:folder patterns:@"*.c *.cpp *.h"
                      matchCase:NO matchWord:YES];
        } else if ([verb isEqual:@"beautify"]) {
            NSTextView *tv = wc.activeEditor.textView;
            NSString *err = nil;
            NSString *out = QAStyleFormat(tv.string, [[QOptions shared] astyleOptions], &err);
            if (out && [tv shouldChangeTextInRange:NSMakeRange(0, tv.string.length)
                                 replacementString:out]) {
                [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length)
                                              withString:out];
                [tv didChangeText];
            }
        } else if ([verb isEqual:@"caret"]) {
            [wc.activeEditor.textView setSelectedRange:NSMakeRange(arg.integerValue, 0)];
        } else if ([verb isEqual:@"type"]) {
            [wc.activeEditor.textView insertText:arg
                                replacementRange:wc.activeEditor.textView.selectedRange];
        } else if ([verb isEqual:@"text"]) {
            [wc.activeEditor.textView.string writeToFile:arg atomically:YES
                                                encoding:NSUTF8StringEncoding error:NULL];
        } else if ([verb isEqual:@"pdf"]) {
            NSPrintInfo *info = [NSPrintInfo.sharedPrintInfo copy];
            info.jobDisposition = NSPrintSaveJob;
            info.dictionary[NSPrintJobSavingURL] = [NSURL fileURLWithPath:arg];
            NSTextView *page = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 700)];
            page.font = [[QOptions shared] editorFont];
            page.string = [wc performSelector:@selector(printableText)];
            NSPrintOperation *op = [NSPrintOperation printOperationWithView:page printInfo:info];
            op.showsPrintPanel = NO;
            op.showsProgressPanel = NO;
            [op runOperation];
        } else if ([verb isEqual:@"width"]) {
            NSRect f = wc.window.frame;
            f.size.width = arg.doubleValue;
            [wc.window setFrame:f display:YES];
        } else if ([verb isEqual:@"tab"]) {
            NSTabViewController *tabs = (NSTabViewController *)
                [QSettingsWindowController shared].contentViewController;
            tabs.selectedTabViewItemIndex = arg.integerValue;
        } else if ([verb isEqual:@"jump"]) {
            [wc performSelector:@selector(jumpToMessage:) withObject:@(arg.integerValue)];
        } else if ([verb isEqual:@"terminate"]) {
            [NSApp terminate:nil];
        } else if ([verb isEqual:@"docs"]) {
            NSMutableString *list = [NSMutableString string];
            for (QDocumentModel *d in wc.documents)
                [list appendFormat:@"%@%@\n", d.displayName, d == wc.activeDocument ? @" *" : @""];
            [list appendFormat:@"project: %@\n", wc.project.url.lastPathComponent ?: @"-"];
            [list writeToFile:arg atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        } else if ([verb isEqual:@"bps"]) {
            NSMutableString *list = [NSMutableString string];
            [wc.activeDocument.breakpoints enumerateIndexesUsingBlock:^(NSUInteger l, BOOL *stop) {
                [list appendFormat:@"%lu ", (unsigned long)l + 1];
            }];
            [list appendFormat:@"\ndirty=%d undo=%d\n", wc.activeDocument.dirty,
                wc.activeEditor.textView.undoManager.canUndo];
            [list writeToFile:arg atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        } else if ([verb isEqual:@"windows"]) {
            NSMutableString *list = [NSMutableString string];
            for (NSWindow *w in NSApp.orderedWindows)
                if (w.isVisible) [list appendFormat:@"%@%@\n", w.title, w.isKeyWindow ? @" *" : @""];
            [list writeToFile:arg atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        } else if ([verb isEqual:@"lldb"]) {
            [[QDebugger shared] sendUserCommand:arg];
        } else if ([verb isEqual:@"undolog"]) {
            NSUndoManager *u = wc.activeEditor.textView.undoManager;
            NSString *line = [NSString stringWithFormat:@"level=%ld canUndo=%d name=%@ byEvent=%d\n",
                (long)u.groupingLevel, u.canUndo, u.undoActionName, u.groupsByEvent];
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:arg];
            if (!h) { [line writeToFile:arg atomically:NO encoding:NSUTF8StringEncoding error:NULL]; }
            else { [h seekToEndOfFile]; [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
        } else if ([verb isEqual:@"keys"]) {
            // Types through the same path a real keystroke takes; `\n` is
            // Return, `\l` the left arrow.
            NSTextView *tv = wc.activeEditor.textView;
            [tv.window makeFirstResponder:tv];
            NSString *text = [[arg stringByReplacingOccurrencesOfString:@"\\n" withString:@"\r"]
                stringByReplacingOccurrencesOfString:@"\\l"
                withString:[NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey]];
            for (NSUInteger i = 0; i < text.length; i++) {
                NSString *ch = [text substringWithRange:NSMakeRange(i, 1)];
                BOOL arrow = [ch characterAtIndex:0] == NSLeftArrowFunctionKey;
                NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                    modifierFlags:arrow ? NSEventModifierFlagFunction | NSEventModifierFlagNumericPad : 0
                    timestamp:0 windowNumber:tv.window.windowNumber context:nil
                    characters:ch charactersIgnoringModifiers:ch isARepeat:NO
                    keyCode:arrow ? 123 : ([ch isEqual:@"\r"] ? 36 : 0)];
                if (![self handleKeyEvent:e]) [tv keyDown:e];
            }
        } else if ([verb isEqual:@"quit"]) {
            exit(0);
        } else if (verb.integerValue) {
            [wc performCommand:(QCommand)verb.integerValue];
        }
    }
}

- (void)snapshotIfRequested {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    if (env[@"QUINCY_SCRIPT"]) {
        NSMutableArray *steps = [[env[@"QUINCY_SCRIPT"] componentsSeparatedByString:@";"] mutableCopy];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2),
                       dispatch_get_main_queue(), ^{ [self runScriptSteps:steps]; });
        return;
    }
    QWindowController *wc = [QWindowController shared];
    if (env[@"QUINCY_WINDOW_ID"]) {
        for (NSString *path in [env[@"QUINCY_OPEN"] componentsSeparatedByString:@":"])
            if (path.length) [wc openURL:[NSURL fileURLWithPath:path]];
        NSString *cmd = env[@"QUINCY_SNAPSHOT_COMMAND"];
        if (cmd.length) [wc performCommand:(QCommand)cmd.integerValue];
        [env[@"QUINCY_WINDOW_ID"] isEqual:@"1"] ? (void)0 : (void)0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSWindow *w = NSApp.keyWindow ?: wc.window;
            NSString *ids = [NSString stringWithFormat:@"%ld %ld\n",
                             (long)wc.window.windowNumber, (long)w.windowNumber];
            [ids writeToFile:env[@"QUINCY_WINDOW_ID"] atomically:YES
                    encoding:NSUTF8StringEncoding error:NULL];
        });
        return;
    }
    NSString *out = env[@"QUINCY_SNAPSHOT"];
    if (!out.length) return;
    for (NSString *path in [env[@"QUINCY_OPEN"] componentsSeparatedByString:@":"])
        if (path.length) [wc openURL:[NSURL fileURLWithPath:path]];
    NSString *cmd = env[@"QUINCY_SNAPSHOT_COMMAND"];
    if (cmd.length) [wc performCommand:(QCommand)cmd.integerValue];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (env[@"QUINCY_DUMP"]) {
            __block void (^dump)(NSView *, int);
            void (^__block __weak weakDump)(NSView *, int);
            weakDump = dump = ^(NSView *v, int depth) {
                if (depth > 12) return;
                fprintf(stderr, "%*s%s %s%s\n", depth * 2, "",
                        NSStringFromClass(v.class).UTF8String,
                        NSStringFromRect(v.frame).UTF8String,
                        v.hidden ? " hidden" : "");
                for (NSView *sub in v.subviews) weakDump(sub, depth + 1);
            };
            dump(wc.window.contentView, 0);
            fprintf(stderr, "contentLayoutRect %s style %lx safe top %.1f\n",
                    NSStringFromRect(wc.window.contentLayoutRect).UTF8String,
                    (unsigned long)wc.window.styleMask,
                    wc.window.contentView.safeAreaInsets.top);
        }
        NSWindow *w = NSApp.keyWindow ?: wc.window;
        if (w.attachedSheet) w = w.attachedSheet;
        NSView *frameView = w.contentView.superview ?: w.contentView;
        if (env[@"QUINCY_SNAPSHOT_EDITOR"]) frameView = wc.activeEditor.superview.superview.superview.superview.superview;
        NSBitmapImageRep *rep = [frameView bitmapImageRepForCachingDisplayInRect:
                                 frameView.bounds];
        [frameView cacheDisplayInRect:frameView.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:out atomically:YES];
        exit(0);
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    QWindowController *wc = [QWindowController shared];
    QConsoleWindowController *console = [QConsoleWindowController shared];
    if (console.running) {
        if (![wc ask:@"Terminate running program?"]) return NSTerminateCancel;
        [console terminate];
        [[QDebugger shared] stop];
    }
    if (![wc confirmCloseOfAllDocuments]) return NSTerminateCancel;
    if ([QBuilder shared].busy) [[QBuilder shared] stop];
    return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [self saveSession];
    [[QOptions shared] save];
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
}

- (BOOL)application:(NSApplication *)app openFile:(NSString *)path {
    [[QWindowController shared] openURL:[NSURL fileURLWithPath:path]];
    return YES;
}

#pragma mark - Session

- (void)restoreSession {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    QWindowController *wc = [QWindowController shared];
    NSMutableArray *recent = [NSMutableArray array];
    for (NSString *path in [d stringArrayForKey:@"Recent File List"] ?: @[]) {
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        NSURL *url = [NSURL fileURLWithPath:path].URLByResolvingSymlinksInPath;
        if (![recent containsObject:url]) [recent addObject:url];
    }
    wc.recentFiles = recent;

    for (NSString *path in [d stringArrayForKey:@"Open Documents"] ?: @[])
        if ([NSFileManager.defaultManager fileExistsAtPath:path])
            [wc openURL:[NSURL fileURLWithPath:path]];

    NSString *project = [d stringForKey:@"Open Project"];
    if (project && [NSFileManager.defaultManager fileExistsAtPath:project])
        [wc openProjectURL:[NSURL fileURLWithPath:project]];

    NSString *active = [d stringForKey:@"Active Document"];
    if (active)
        for (QDocumentModel *doc in wc.documents)
            if ([doc.url.path isEqual:active]) { [wc presentDocument:doc]; break; }
    [wc refreshChrome];
}

- (void)saveSession {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    QWindowController *wc = [QWindowController shared];
    NSMutableArray *paths = [NSMutableArray array];
    for (QDocumentModel *doc in wc.documents)
        if (doc.url) [paths addObject:doc.url.path];
    [d setObject:paths forKey:@"Open Documents"];
    if (wc.activeDocument.url)
        [d setObject:wc.activeDocument.url.path forKey:@"Active Document"];
    if (wc.project.url) [d setObject:wc.project.url.path forKey:@"Open Project"];
    else [d removeObjectForKey:@"Open Project"];
}

#pragma mark - Menu bar

/// Makes one menu item for a command, with its Mac key equivalent.
- (NSMenuItem *)itemForCommand:(QCommand)command {
    NSString *key = nil;
    NSEventModifierFlags mods = 0;
    QCommandShortcut(command, &key, &mods);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:QCommandTitle(command)
                                                 action:@selector(menuCommand:)
                                          keyEquivalent:key ?: @""];
    item.keyEquivalentModifierMask = mods;
    item.target = self;
    item.tag = command;
    return item;
}

- (NSMenu *)menuTitled:(NSString *)title commands:(NSArray<NSNumber *> *)commands {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    menu.delegate = self;
    for (NSNumber *n in commands) {
        if (n.integerValue == QCommandNone) [menu addItem:NSMenuItem.separatorItem];
        else [menu addItem:[self itemForCommand:(QCommand)n.integerValue]];
    }
    return menu;
}

- (void)addMenu:(NSMenu *)menu toBar:(NSMenu *)bar {
    NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:menu.title
                                                    action:NULL
                                             keyEquivalent:@""];
    holder.submenu = menu;
    [bar addItem:holder];
}

- (void)buildMenuBar {
    NSMenu *bar = [[NSMenu alloc] init];

    // Application menu
    NSMenu *app = [[NSMenu alloc] init];
    app.delegate = self;
    [app addItem:[self itemForCommand:QCommandAbout]];
    [app addItem:NSMenuItem.separatorItem];
    [app addItem:[self itemForCommand:QCommandSettings]];
    [app addItem:NSMenuItem.separatorItem];
    NSMenuItem *services = [[NSMenuItem alloc] initWithTitle:@"Services"
                                                      action:NULL
                                               keyEquivalent:@""];
    services.submenu = [[NSMenu alloc] initWithTitle:@"Services"];
    NSApp.servicesMenu = services.submenu;
    [app addItem:services];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:@"Hide Quincy 2005" action:@selector(hide:)
            keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [app addItemWithTitle:@"Hide Others"
                                            action:@selector(hideOtherApplications:)
                                     keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand |
                                           NSEventModifierFlagOption;
    [app addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:)
            keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:@"Quit Quincy 2005" action:@selector(terminate:)
            keyEquivalent:@"q"];
    [self addMenu:app toBar:bar];

    // File — with the original's Recent File List as Open Recent
    NSMenu *file = [self menuTitled:@"File" commands:@[
        @(QCommandFileNew), @(QCommandFileOpen)]];
    NSMenuItem *recent = [[NSMenuItem alloc] initWithTitle:@"Open Recent"
                                                    action:NULL
                                             keyEquivalent:@""];
    _recentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    recent.submenu = _recentMenu;
    [file addItem:recent];
    for (NSNumber *n in @[@(QCommandNone), @(QCommandFileClose),
                          @(QCommandFileCloseAll), @(QCommandFileCloseProject),
                          @(QCommandNone),
                          @(QCommandFileSave), @(QCommandFileSaveAll),
                          @(QCommandFileSaveAs), @(QCommandNone),
                          @(QCommandFilePrintSetup), @(QCommandFilePrint),
                          @(QCommandFilePrintPreview)]) {
        if (n.integerValue == QCommandNone) [file addItem:NSMenuItem.separatorItem];
        else [file addItem:[self itemForCommand:(QCommand)n.integerValue]];
    }
    [self addMenu:file toBar:bar];

    [self addMenu:[self menuTitled:@"Edit" commands:@[
        @(QCommandEditUndo), @(QCommandEditRedo), @(QCommandNone),
        @(QCommandEditCut), @(QCommandEditCopy), @(QCommandEditPaste),
        @(QCommandEditClear), @(QCommandEditSelectAll), @(QCommandNone),
        @(QCommandEditFind), @(QCommandEditReplace), @(QCommandEditFindNext),
        @(QCommandNone), @(QCommandEditMatchBraces),
    ]] toBar:bar];

    NSMenu *view = [self menuTitled:@"View" commands:@[
        @(QCommandViewSidebar), @(QCommandViewWatch), @(QCommandNone),
        @(QCommandViewBuildLog), @(QCommandViewConsole), @(QCommandNone),
    ]];
    // The window's own toolbar items, which AppKit titles and validates.
    NSMenuItem *toolbar = [view addItemWithTitle:@"Hide Toolbar"
                                          action:@selector(toggleToolbarShown:)
                                   keyEquivalent:@"t"];
    toolbar.keyEquivalentModifierMask = NSEventModifierFlagCommand |
                                        NSEventModifierFlagOption;
    [view addItemWithTitle:@"Customize Toolbar…"
                    action:@selector(runToolbarCustomizationPalette:)
             keyEquivalent:@""];
    [view addItem:[self itemForCommand:QCommandViewStatusBar]];
    [self addMenu:view toBar:bar];

    [self addMenu:[self menuTitled:@"Project" commands:@[
        @(QCommandProjectInsertFiles), @(QCommandProjectOpenHeaders),
        @(QCommandProjectDeleteFiles), @(QCommandProjectProperties),
        @(QCommandNone),
        @(QCommandBuildCompile), @(QCommandBuildLink), @(QCommandNone),
        @(QCommandBuildBuild), @(QCommandBuildRebuildAll), @(QCommandBuildStop),
        @(QCommandNone), @(QCommandDebugRun),
    ]] toBar:bar];

    [self addMenu:[self menuTitled:@"Debug" commands:@[
        @(QCommandDebugRun), @(QCommandDebugStart), @(QCommandDebugStep), @(QCommandDebugStepOver),
        @(QCommandDebugStepToCursor), @(QCommandDebugStepOut),
        @(QCommandBuildStop), @(QCommandNone),
        @(QCommandDebugBreakpoint), @(QCommandDebugClearBreaks), @(QCommandNone),
        @(QCommandDebugExamine), @(QCommandViewWatch),
    ]] toBar:bar];

    NSMenu *tools = [self menuTitled:@"Tools" commands:@[
        @(QCommandToolsGrep), @(QCommandToolsBeautifier),
        @(QCommandToolsResourceEditor), @(QCommandToolsFluid),
        @(QCommandToolsTerminal), @(QCommandNone),
    ]];
    NSMenuItem *macro = [[NSMenuItem alloc] initWithTitle:@"Macro" action:NULL
                                            keyEquivalent:@""];
    macro.submenu = [self menuTitled:@"Macro" commands:@[
        @(QCommandMacroRecord), @(QCommandMacroPlayback), @(QCommandMacroStop)]];
    [tools addItem:macro];
    [self addMenu:tools toBar:bar];

    NSMenu *window = [[NSMenu alloc] initWithTitle:@"Window"];
    window.delegate = self;
    [window addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:)
               keyEquivalent:@"m"];
    [window addItemWithTitle:@"Zoom" action:@selector(performZoom:)
               keyEquivalent:@""];
    [window addItem:NSMenuItem.separatorItem];
    [window addItem:[self itemForCommand:QCommandWindowNewWindow]];
    [window addItem:NSMenuItem.separatorItem];
    [window addItem:[self itemForCommand:QCommandWindowNextDoc]];
    [window addItem:[self itemForCommand:QCommandWindowPreviousDoc]];
    [window addItem:NSMenuItem.separatorItem];
    [window addItemWithTitle:@"Bring All to Front"
                      action:@selector(arrangeInFront:) keyEquivalent:@""];
    [self addMenu:window toBar:bar];
    NSApp.windowsMenu = window;

    NSMenu *help = [self menuTitled:@"Help" commands:@[
        @(QCommandHelpUserGuide), @(QCommandHelpProgrammer), @(QCommandNone),
        @(QCommandHelpExamples), @(QCommandHelpTutorial),
    ]];
    [self addMenu:help toBar:bar];
    NSApp.helpMenu = help;

    NSApp.mainMenu = bar;
}

- (void)rebuildRecentMenu {
    [_recentMenu removeAllItems];
    NSArray<NSURL *> *recent = [QWindowController shared].recentFiles;
    for (NSURL *url in recent) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:url.lastPathComponent
                   action:@selector(openRecent:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = url;
        item.toolTip = url.path;
        [_recentMenu addItem:item];
    }
    if (recent.count) {
        [_recentMenu addItem:NSMenuItem.separatorItem];
        NSMenuItem *clear = [[NSMenuItem alloc] initWithTitle:@"Clear Menu"
                                                       action:@selector(clearRecent:)
                                                keyEquivalent:@""];
        clear.target = self;
        [_recentMenu addItem:clear];
    } else {
        NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"No Recent Files"
                                                      action:NULL
                                               keyEquivalent:@""];
        none.enabled = NO;
        [_recentMenu addItem:none];
    }
}

- (void)openRecent:(NSMenuItem *)sender {
    [[QWindowController shared] openURL:sender.representedObject];
}

- (void)clearRecent:(id)sender {
    [QWindowController shared].recentFiles = @[];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"Recent File List"];
    [self rebuildRecentMenu];
    [[QWindowController shared] refreshChrome];
}

#pragma mark - Menu behaviour

- (void)menuCommand:(NSMenuItem *)sender {
    [[QWindowController shared] performCommand:(QCommand)sender.tag];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action != @selector(menuCommand:)) return YES;
    QCommand command = (QCommand)item.tag;
    QWindowController *wc = [QWindowController shared];

    // Two items read their own state: the sidebar and the Watch inspector.
    if (command == QCommandViewSidebar)
        item.title = [wc isSidebarVisible] ? @"Hide Sidebar" : @"Show Sidebar";
    if (command == QCommandViewStatusBar)
        item.title = [wc isStatusBarVisible] ? @"Hide Status Bar" : @"Show Status Bar";
    if (command == QCommandViewWatch)
        item.state = [wc isInspectorVisible] ? NSControlStateValueOn
                                             : NSControlStateValueOff;
    if (command == QCommandMacroStop)
        item.hidden = ![wc isRecordingMacro];
    return [wc isCommandEnabled:command];
}

/// MFC put the first half of the help string in the status bar as the user
/// moved through the menus; so does this.
- (void)menu:(NSMenu *)menu willHighlightItem:(NSMenuItem *)item {
    QWindowController *wc = [QWindowController shared];
    if (item && item.action == @selector(menuCommand:))
        [wc showStatus:QCommandHelp((QCommand)item.tag)];
    else if (!item)
        [wc showStatus:@"Ready"];
}

#pragma mark - Legacy accelerators

/// The original's F1–F10 still work; macOS gives them to nobody else, so a
/// local monitor is the whole mechanism.  Everything else typed into the
/// editor goes to a macro being recorded.
- (void)installKeyMonitor {
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                        handler:^NSEvent *(NSEvent *event) {
        return [self handleKeyEvent:event] ? nil : event;
    }];
}

/// YES when the key was an F-key command and is used up.
- (BOOL)handleKeyEvent:(NSEvent *)event {
    QWindowController *wc = [QWindowController shared];
    NSEventModifierFlags mods = event.modifierFlags &
        NSEventModifierFlagDeviceIndependentFlagsMask;
    if (mods & NSEventModifierFlagCommand) return NO;   // menus, never recorded
    unichar c = event.charactersIgnoringModifiers.length == 1
        ? [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
    if (!(mods & (NSEventModifierFlagOption | NSEventModifierFlagControl)) &&
        c >= NSF1FunctionKey && c <= NSF35FunctionKey) {
        static const QCommand candidates[] = {
            QCommandHelpUserGuide, QCommandDebugBreakpoint, QCommandEditFindNext,
            QCommandHelpExamples, QCommandBuildCompile, QCommandBuildBuild,
            QCommandDebugStep, QCommandDebugStepOver, QCommandDebugRun,
            QCommandDebugStepToCursor,
        };
        for (size_t i = 0; i < sizeof(candidates) / sizeof(*candidates); i++) {
            if (QCommandLegacyFunctionKey(candidates[i]) == c) {
                if ([wc isCommandEnabled:candidates[i]])
                    [wc performCommand:candidates[i]];
                else
                    NSBeep();
                return YES;
            }
        }
    }
    [wc recordMacroEvent:event];
    return NO;
}

@end

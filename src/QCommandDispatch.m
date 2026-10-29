//
//  QCommandDispatch.m — what each command does.
//
//  Kept apart from the window's layout so the table of commands reads as a
//  table.  Build, Run and the debugging commands hand off to QBuilder and
//  QDebugger; everything else is handled here.
//

#import "QChrome.h"

@implementation QWindowController (Commands)

#pragma mark - Dispatch

- (void)performCommand:(QCommand)command {
    if (QCommandUnavailableOnMac(command)) {
        [self showStatus:QCommandHelp(command)];
        NSBeep();
        return;
    }
    QEditorView *editor = [self activeEditor];
    NSTextView *text = editor.textView;

    switch (command) {
        // File
        case QCommandFileNew: {
            [QNewDocumentSheet beginSheetForWindow:self.window
                                        completion:^(NSString *ext) {
                if (!ext) return;
                if ([ext isEqual:@".prj"]) { [self createProject]; return; }
                [self addDocument:[[QDocumentModel alloc]
                                   initUntitledWithExtension:ext]];
            }];
            break;
        }
        case QCommandFileOpen: {
            NSOpenPanel *panel = [NSOpenPanel openPanel];
            panel.allowsMultipleSelection = YES;
            panel.allowedFileTypes = @[@"c", @"cpp", @"cc", @"cxx", @"h", @"hpp",
                                       @"rc", @"def", @"prj", @"txt"];
            if ([panel runModal] != NSModalResponseOK) break;
            for (NSURL *url in panel.URLs) [self openURL:url];
            break;
        }
        case QCommandFileClose:     [self closeDocument:self.activeDocument]; break;
        case QCommandFileCloseProject:
            self.project = nil;
            [self refreshChrome];
            [self showStatus:@"Project closed"];
            break;
        case QCommandFileCloseAll:
            for (QDocumentModel *d in [self.documents copy]) [self closeDocument:d];
            break;
        case QCommandFileSave:      [self saveDocument:self.activeDocument as:NO]; break;
        case QCommandFileSaveAs:    [self saveDocument:self.activeDocument as:YES]; break;
        case QCommandFileSaveAll:
            for (QDocumentModel *d in [self.documents copy])
                if (d.dirty) [self saveDocument:d as:NO];
            break;
        case QCommandFilePrint:        [self printDocument]; break;
        case QCommandFilePrintSetup:   [self runPageSetup]; break;
        case QCommandFilePrintPreview: [self printDocument]; break;

        // Edit
        case QCommandEditUndo:      [text.undoManager undo]; break;
        case QCommandEditRedo:      [text.undoManager redo]; break;
        case QCommandEditCut:       [text cut:nil]; break;
        case QCommandEditCopy:      [text copy:nil]; break;
        case QCommandEditPaste:     [text paste:nil]; break;
        case QCommandEditClear:     [text delete:nil]; break;
        case QCommandEditSelectAll: [text selectAll:nil]; break;
        case QCommandEditFind:
            [text performTextFinderAction:
                [self actionWithTag:NSTextFinderActionShowFindInterface]];
            break;
        case QCommandEditReplace:
            [text performTextFinderAction:
                [self actionWithTag:NSTextFinderActionShowReplaceInterface]];
            break;
        case QCommandEditFindNext:
            [text performTextFinderAction:
                [self actionWithTag:NSTextFinderActionNextMatch]];
            break;
        case QCommandEditMatchBraces: [self matchBraces]; break;

        // View
        case QCommandViewSidebar:
            [self setSidebarVisible:![self isSidebarVisible]];
            break;
        case QCommandViewStatusBar:
            [self setStatusBarVisible:![self isStatusBarVisible]];
            break;
        case QCommandViewBuildLog:
            [self showBottomTab:0];
            break;
        case QCommandViewConsole:
            [self showBottomTab:1];
            break;
        case QCommandViewWatch:
            [self setInspectorVisible:![self isInspectorVisible]];
            break;

        // Project and build
        case QCommandProjectProperties:
            [QProjectPropertiesSheet beginSheetForWindow:self.window];
            break;
        case QCommandProjectInsertFiles:  [self insertProjectFiles]; break;
        case QCommandProjectOpenHeaders:
            for (NSString *h in [self.project headerPaths])
                [self openURL:[NSURL fileURLWithPath:h]];
            break;
        case QCommandProjectDeleteFiles:  [self deleteProjectFile]; break;
        case QCommandBuildCompile:
            [[QBuilder shared] compileDocument:self.activeDocument];
            break;
        case QCommandBuildLink:
            [[QBuilder shared] buildProject:[self buildTargetProject] document:self.activeDocument
                                    rebuild:NO linkOnly:YES completion:nil];
            break;
        case QCommandBuildBuild:
            [[QBuilder shared] buildProject:[self buildTargetProject] document:self.activeDocument
                                    rebuild:NO linkOnly:NO completion:nil];
            break;
        case QCommandBuildRebuildAll:
            [[QBuilder shared] buildProject:[self buildTargetProject] document:self.activeDocument
                                    rebuild:YES linkOnly:NO completion:nil];
            break;
        case QCommandBuildStop:
            if (QGrepSheet.searching) [QGrepSheet stop];
            else if ([QBuilder shared].busy) [[QBuilder shared] stop];
            else if ([QDebugger shared].active) [[QDebugger shared] stop];
            else [[QConsoleWindowController shared] terminate];
            break;

        // Debug
        case QCommandDebugRun:
            if ([QDebugger shared].stopped) [[QDebugger shared] continueRunning];
            else [self runProgramWithDebugger:NO extra:nil];
            break;
        case QCommandDebugStart:
            // Under lldb: stop at the breakpoints, or at main when there are none.
            if ([QDebugger shared].stopped) [[QDebugger shared] continueRunning];
            else [self runProgramWithDebugger:YES
                                        extra:[self hasBreakpoints] ? nil
                                              : @[@"breakpoint set -o true -n main"]];
            break;
        case QCommandDebugStep:
            if ([QDebugger shared].stopped) [[QDebugger shared] step];
            else [self runProgramWithDebugger:YES
                                        extra:@[@"breakpoint set -o true -n main"]];
            break;
        case QCommandDebugStepOver:
            if ([QDebugger shared].stopped) [[QDebugger shared] stepOver];
            else [self runProgramWithDebugger:YES
                                        extra:@[@"breakpoint set -o true -n main"]];
            break;
        case QCommandDebugStepOut:
            [[QDebugger shared] stepOut];
            break;
        case QCommandDebugStepToCursor: {
            NSString *file = self.activeDocument.url.path;
            NSInteger line = editor.currentLine;
            if (!file) { NSBeep(); break; }
            if ([QDebugger shared].stopped) [[QDebugger shared] runToFile:file line:line];
            else [self runProgramWithDebugger:YES extra:@[
                [NSString stringWithFormat:@"breakpoint set -o true -f \"%@\" -l %ld",
                 file, (long)line]]];
            break;
        }
        case QCommandDebugBreakpoint:
            if (editor) [editor toggleBreakpointAtLine:editor.currentLine - 1];
            break;
        case QCommandDebugClearBreaks:
            for (QDocumentModel *d in self.documents) [d.breakpoints removeAllIndexes];
            [editor refreshGutter];
            [[QDebugger shared] breakpointsChanged];
            [self showStatus:@"All breakpoints cleared"];
            break;
        case QCommandDebugExamine:
            [QExamineSheet beginSheetForWindow:self.window
                                    expression:[self wordAtCaret]];
            break;

        // Tools
        case QCommandToolsGrep:       [QGrepSheet beginSheetForWindow:self.window]; break;
        case QCommandToolsBeautifier: [QBeautifierSheet beginSheetForWindow:self.window]; break;
        case QCommandToolsTerminal:   [self openTerminal]; break;
        case QCommandMacroRecord:     [self toggleMacroRecording]; break;
        case QCommandMacroStop:       [self toggleMacroRecording]; break;
        case QCommandMacroPlayback:   [self playbackMacro]; break;
        case QCommandSettings:        [QSettingsWindowController showSettings]; break;

        // Window
        case QCommandWindowNewWindow: [self openNewWindowForActiveDocument]; break;
        case QCommandWindowNextDoc:     [self stepDocumentBy:1]; break;
        case QCommandWindowPreviousDoc: [self stepDocumentBy:-1]; break;

        // Help
        case QCommandHelpUserGuide:  [self openHelp:@"quincy2005.htm"]; break;
        case QCommandHelpProgrammer: [self openHelp:@"programmerGuide.htm"]; break;
        case QCommandHelpExamples:
        case QCommandHelpTutorial:   [self openHelp:@"tutorial.htm"]; break;
        case QCommandAbout:          [QAboutPanel show]; break;

        default:
            NSBeep();
            break;
    }
}

/// NSTextView wants the finder action as a sender's tag, so wrap it.
- (id)actionWithTag:(NSInteger)tag {
    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.tag = tag;
    return item;
}

#pragma mark - Enablement

- (BOOL)isCommandEnabled:(QCommand)command {
    if (QCommandUnavailableOnMac(command)) return NO;
    QEditorView *editor = [self activeEditor];
    BOOL hasDoc = self.activeDocument != nil;
    switch (command) {
        case QCommandFileNew: case QCommandFileOpen: case QCommandSettings:
        case QCommandToolsGrep: case QCommandToolsTerminal:
        case QCommandHelpUserGuide: case QCommandHelpProgrammer:
        case QCommandHelpExamples: case QCommandHelpTutorial:
        case QCommandAbout: case QCommandViewSidebar: case QCommandViewWatch:
        case QCommandViewBuildLog: case QCommandViewConsole:
        case QCommandViewStatusBar:
            return YES;
        case QCommandFileSave:
            return hasDoc && self.activeDocument.dirty;
        case QCommandFileSaveAll:
            for (QDocumentModel *d in self.documents) if (d.dirty) return YES;
            return NO;
        case QCommandEditUndo:  return editor.textView.undoManager.canUndo;
        case QCommandEditRedo:  return editor.textView.undoManager.canRedo;
        case QCommandEditCut: case QCommandEditCopy: case QCommandEditClear:
            return editor != nil;
        case QCommandEditPaste:
            return editor != nil && [NSPasteboard.generalPasteboard
                stringForType:NSPasteboardTypeString] != nil;
        case QCommandBuildStop:
            return QGrepSheet.searching || [QBuilder shared].busy || [QDebugger shared].active ||
                   [QConsoleWindowController shared].running;
        case QCommandBuildCompile:
            return ![QBuilder shared].busy && self.activeDocument.isSourceFile;
        case QCommandBuildBuild: case QCommandBuildRebuildAll: case QCommandBuildLink:
            return ![QBuilder shared].busy && ![QDebugger shared].active &&
                   ([self buildTargetProject] != nil || self.activeDocument.isSourceFile);
        case QCommandDebugRun:
            return ![QBuilder shared].busy &&
                   ([QDebugger shared].stopped ||
                    (![QDebugger shared].active &&
                     ![QConsoleWindowController shared].running &&
                     ([self buildTargetProject] != nil || self.activeDocument.isSourceFile)));
        case QCommandDebugStep: case QCommandDebugStepOver:
        case QCommandDebugStepToCursor: case QCommandDebugStart:
            return ![QBuilder shared].busy &&
                   ([QDebugger shared].stopped ||
                    (![QDebugger shared].active &&
                     ![QConsoleWindowController shared].running &&
                     ([self buildTargetProject] != nil || self.activeDocument.isSourceFile)));
        case QCommandDebugStepOut: case QCommandDebugExamine:
            return [QDebugger shared].stopped;
        case QCommandProjectInsertFiles: case QCommandProjectProperties:
        case QCommandFileCloseProject:
            return self.project != nil;
        case QCommandProjectOpenHeaders:
            return [self.project headerPaths].count > 0;
        case QCommandProjectDeleteFiles:
            return [self selectedProjectFile] != nil;
        case QCommandDebugClearBreaks:
            for (QDocumentModel *d in self.documents) if (d.breakpoints.count) return YES;
            return NO;
        case QCommandWindowNextDoc:
        case QCommandWindowPreviousDoc:
            return self.documents.count > 1;
        default:
            return hasDoc;
    }
}

- (BOOL)isCommandOn:(QCommand)command {
    switch (command) {
        case QCommandViewSidebar:   return [self isSidebarVisible];
        case QCommandViewWatch:     return [self isInspectorVisible];
        default: return NO;
    }
}

#pragma mark - Running

/// What Build and Run act on.  The project, unless the file in front is a
/// source file that is not one of its members: then that file on its own,
/// which is what someone who just opened it expects.
- (QProject *)buildTargetProject {
    QProject *p = self.project;
    QDocumentModel *doc = self.activeDocument;
    if (!p) return nil;
    if (!doc || !doc.isSourceFile || !doc.url) return p;
    NSString *path = doc.url.URLByResolvingSymlinksInPath.path;
    for (NSString *f in p.files)
        if ([[[NSURL fileURLWithPath:[p absolutePath:f]] URLByResolvingSymlinksInPath].path
             isEqual:path]) return p;
    return nil;
}

/// The word under the caret, to start Examine with.
- (NSString *)wordAtCaret {
    NSTextView *tv = [self activeEditor].textView;
    if (!tv) return @"";
    if (tv.selectedRange.length) return [tv.string substringWithRange:tv.selectedRange];
    NSRange r = [tv selectionRangeForProposedRange:tv.selectedRange
                                       granularity:NSSelectByWord];
    NSString *w = r.length ? [tv.string substringWithRange:r] : @"";
    return [w stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (BOOL)ask:(NSString *)question {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = question;
    [a addButtonWithTitle:@"Yes"];
    [a addButtonWithTitle:@"No"];
    return [a runModal] == NSAlertFirstButtonReturn;
}

/// Run ▸ Arguments: none, fixed, or asked for each time.
- (NSArray<NSString *> *)programArguments:(BOOL *)cancelled {
    QOptions *o = [QOptions shared];
    NSString *line = @"";
    if (o.argumentsMode == QArgumentsFixed) line = o.arguments ?: @"";
    else if (o.argumentsMode == QArgumentsPrompt) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"Command line arguments";
        a.informativeText = @"Arguments passed to the program:";
        NSTextField *f = QTextField(@"");
        f.stringValue = o.arguments ?: @"";
        f.frame = NSMakeRect(0, 0, 300, 24);
        a.accessoryView = f;
        [a addButtonWithTitle:@"Run"];
        [a addButtonWithTitle:@"Cancel"];
        a.window.initialFirstResponder = f;
        if ([a runModal] != NSAlertFirstButtonReturn) { *cancelled = YES; return nil; }
        line = f.stringValue;
        o.arguments = line;
        [o save];
    }
    // Split like a shell would for plain words and "quoted strings".
    NSMutableArray *args = [NSMutableArray array];
    NSScanner *sc = [NSScanner scannerWithString:line];
    sc.charactersToBeSkipped = NSCharacterSet.whitespaceCharacterSet;
    while (!sc.isAtEnd) {
        NSString *word = nil;
        if ([sc scanString:@"\"" intoString:NULL]) {
            [sc scanUpToString:@"\"" intoString:&word];
            [sc scanString:@"\"" intoString:NULL];
        } else {
            [sc scanUpToCharactersFromSet:NSCharacterSet.whitespaceCharacterSet
                               intoString:&word];
        }
        [args addObject:word ?: @""];
    }
    return args;
}

/// Breakpoints only count in files that are part of what is being run.
- (BOOL)hasBreakpoints {
    QProject *p = [self buildTargetProject];
    NSMutableSet *members = [NSMutableSet set];
    if (p) for (NSString *f in p.files) [members addObject:[p absolutePath:f]];
    else if (self.activeDocument.url) [members addObject:self.activeDocument.url.path];
    for (QDocumentModel *d in self.documents)
        if (d.url && d.breakpoints.count && [members containsObject:d.url.path]) return YES;
    return NO;
}

/// F9 and the first Step: build if needed (asking, as the original did), then
/// run in the console — under lldb when there are breakpoints or a step.
- (void)runProgramWithDebugger:(BOOL)debug extra:(NSArray<NSString *> *)extra {
    QBuilder *builder = [QBuilder shared];
    QConsoleWindowController *console = [QConsoleWindowController shared];
    if (console.running) {
        if (![self ask:@"Terminate running program?"]) return;
        [console terminate];
        [[QDebugger shared] stop];
        return;
    }
    QProject *project = [self buildTargetProject];
    QDocumentModel *doc = self.activeDocument;
    if (project && project.type != QProjectConsole) {
        [self showStatus:@"Only console projects can be run"];
        NSBeep();
        return;
    }
    NSString *target = [builder targetPathForProject:project document:doc];
    if (!target) { NSBeep(); return; }

    void (^launch)(NSString *) = ^(NSString *exe) {
        BOOL cancelled = NO;
        NSArray *args = [self programArguments:&cancelled];
        if (cancelled) return;
        NSString *dir = [QOptions shared].workingDirectory;
        if (!dir.length) dir = exe.stringByDeletingLastPathComponent;
        BOOL underDebugger = debug || [self hasBreakpoints];
        if (underDebugger && ![builder targetHasDebugInfo:exe]) {
            if (![self ask:@"No debug information. Run anyway?"]) return;
            underDebugger = NO;
        }
        if (underDebugger)
            [[QDebugger shared] startProgram:exe arguments:args directory:dir extra:extra];
        else
            [console runProgram:exe arguments:args directory:dir];
    };

    BOOL exists = [NSFileManager.defaultManager isExecutableFileAtPath:target];
    BOOL stale = [builder isTargetOutOfDateForProject:project document:doc] ||
                 doc.dirty;
    if (!exists || (stale && [self ask:[NSString stringWithFormat:
                                @"%@ is out of date. Rebuild?",
                                target.lastPathComponent]])) {
        [builder buildProject:project document:doc rebuild:NO linkOnly:NO
                   completion:^(BOOL ok, NSString *built) {
            if (ok) launch(built);
        }];
        return;
    }
    launch(target);
}

#pragma mark - Project files

- (void)createProject {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"Untitled.prj";
    panel.canCreateDirectories = YES;
    panel.message = @"Choose where the new project lives. Its files go in the same folder.";
    if ([panel runModal] != NSModalResponseOK) return;
    QProject *p = [[QProject alloc] initNewAtURL:panel.URL];
    NSError *error = nil;
    if (![p save:&error]) { [self reportError:error message:@"Failed to save document."]; return; }
    self.project = p;
    [self noteRecentURL:panel.URL];
    [self refreshChrome];
}

- (void)insertProjectFiles {
    QProject *p = self.project;
    if (!p) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.directoryURL = [NSURL fileURLWithPath:p.folder];
    panel.allowedFileTypes = @[@"c", @"cpp", @"cc", @"cxx", @"h", @"hpp", @"a",
                               @"o", @"dylib", @"rc", @"def"];
    if ([panel runModal] != NSModalResponseOK) return;
    for (NSURL *u in panel.URLs) {
        NSString *rel = [p relativePath:u.path];
        if (![p.files containsObject:rel]) [p.files addObject:rel];
    }
    NSError *error = nil;
    if (![p save:&error]) [self reportError:error message:@"Failed to save document."];
    [self refreshChrome];
}

- (void)deleteProjectFile {
    QProject *p = self.project;
    NSString *rel = [self selectedProjectFile];
    if (!p || !rel) return;
    [p.files removeObject:rel];
    NSError *error = nil;
    if (![p save:&error]) [self reportError:error message:@"Failed to save document."];
    [self refreshChrome];
}

#pragma mark - Pieces

- (void)stepDocumentBy:(NSInteger)delta {
    if (self.documents.count < 2) return;
    NSInteger at = (NSInteger)[self.documents indexOfObject:self.activeDocument];
    NSInteger n = (NSInteger)self.documents.count;
    [self presentDocument:self.documents[((at + delta) % n + n) % n]];
}

- (void)matchBraces {
    QEditorView *editor = [self activeEditor];
    if (!editor) return;
    NSUInteger caret = editor.textView.selectedRange.location;
    NSUInteger partner = QMatchingBraceIndex(editor.textView.string, caret);
    if (partner == NSNotFound) {
        // The original said exactly this when there was no partner.
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No matching brace.";
        alert.informativeText = @"Put the insertion point next to a brace, "
                                 "bracket or parenthesis and try again.";
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    [editor.textView setSelectedRange:NSMakeRange(partner, 1)];
    [editor.textView scrollRangeToVisible:NSMakeRange(partner, 1)];
    [editor.textView showFindIndicatorForRange:NSMakeRange(partner, 1)];
}

- (void)openTerminal {
    NSString *folder = self.activeDocument.url.URLByDeletingLastPathComponent.path
                     ?: NSHomeDirectory();
    NSURL *terminal = [NSURL fileURLWithPath:@"/System/Applications/Utilities/Terminal.app"];
    NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
    [NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:folder]]
                     withApplicationAtURL:terminal
                            configuration:config
                        completionHandler:nil];
}

- (void)openHelp:(NSString *)page {
    NSString *base = [NSBundle.mainBundle.resourcePath
                      stringByAppendingPathComponent:@"help"];
    NSString *path = [base stringByAppendingPathComponent:page];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path]) {
        // The guides live under html/ in the original layout.
        path = [[base stringByAppendingPathComponent:@"html"]
                stringByAppendingPathComponent:page];
    }
    if (![fm fileExistsAtPath:path]) {
        [self showStatus:[NSString stringWithFormat:@"Help page %@ is missing", page]];
        NSBeep();
        return;
    }
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]];
}

#pragma mark - Printing

- (void)printDocument {
    QEditorView *editor = [self activeEditor];
    if (!editor) return;
    NSPrintInfo *info = [NSPrintInfo.sharedPrintInfo copy];
    info.horizontalPagination = NSPrintingPaginationModeFit;
    NSTextView *page = [[NSTextView alloc] initWithFrame:
        NSMakeRect(0, 0, info.paperSize.width - 100, info.paperSize.height - 100)];
    page.font = [[QOptions shared] editorFont];
    page.string = [self printableText];
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:page
                                                          printInfo:info];
    op.jobTitle = self.activeDocument.displayName;
    [op runOperationModalForWindow:self.window delegate:nil
                   didRunSelector:NULL contextInfo:NULL];
}

/// Honours the original's "Print line numbers" option.
- (NSString *)printableText {
    QEditorView *editor = [self activeEditor];
    NSString *text = editor.textView.string;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"Print Line Numbers"])
        return text;
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < lines.count; i++)
        [out appendFormat:@"%5lu  %@\n", (unsigned long)(i + 1), lines[i]];
    return out;
}

- (void)runPageSetup {
    NSPageLayout *layout = [NSPageLayout pageLayout];
    NSButton *numbers = [NSButton checkboxWithTitle:@"Print line numbers"
                                             target:self
                                             action:@selector(toggleLineNumbers:)];
    numbers.state = [NSUserDefaults.standardUserDefaults
                     boolForKey:@"Print Line Numbers"] ? NSControlStateValueOn
                                                       : NSControlStateValueOff;
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 32)];
    numbers.frame = NSMakeRect(12, 6, 220, 20);
    [accessory addSubview:numbers];
    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = accessory;
    vc.title = @"Quincy";
    [layout addAccessoryController:vc];
    [layout beginSheetWithPrintInfo:NSPrintInfo.sharedPrintInfo
                    modalForWindow:self.window delegate:nil
                    didEndSelector:NULL contextInfo:NULL];
}

- (void)toggleLineNumbers:(NSButton *)sender {
    [NSUserDefaults.standardUserDefaults
        setBool:sender.state == NSControlStateValueOn
         forKey:@"Print Line Numbers"];
}

#pragma mark - Macros

/// A macro is the editor keystrokes typed while recording — text, arrows,
/// Return, Delete and their Shift/Option/Control forms — replayed through the
/// text view as if typed again, so navigation is repeated as well as text.
static NSMutableArray<NSEvent *> *sMacro = nil;
static BOOL sRecording = NO;

- (void)toggleMacroRecording {
    sRecording = !sRecording;
    if (sRecording) {
        sMacro = [NSMutableArray array];
        [self showStatus:@"Recording a macro — choose Stop Recording to finish"];
    } else {
        [self showStatus:[NSString stringWithFormat:@"Macro recorded (%lu keystrokes)",
                          (unsigned long)sMacro.count]];
    }
}

- (BOOL)isRecordingMacro { return sRecording; }

- (void)recordMacroEvent:(NSEvent *)event {
    if (!sRecording || event.type != NSEventTypeKeyDown) return;
    NSWindow *window = event.window ?: [NSApp windowWithWindowNumber:event.windowNumber];
    if (window.firstResponder != self.activeEditor.textView) return;
    [sMacro addObject:event];
}

- (void)playbackMacro {
    QEditorView *editor = [self activeEditor];
    if (!editor || !sMacro.count || sRecording) { NSBeep(); return; }
    NSTextView *tv = editor.textView;
    [tv.window makeFirstResponder:tv];
    // Playback happens within one event, so the undo manager's grouping by
    // event already makes it a single Undo.
    [tv breakUndoCoalescing];
    for (NSEvent *e in sMacro) {
        NSEvent *again = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                          location:NSZeroPoint
                                     modifierFlags:e.modifierFlags
                                         timestamp:NSProcessInfo.processInfo.systemUptime
                                      windowNumber:tv.window.windowNumber
                                           context:nil
                                        characters:e.characters
                       charactersIgnoringModifiers:e.charactersIgnoringModifiers
                                         isARepeat:NO
                                           keyCode:e.keyCode];
        [tv keyDown:again];
    }
    [tv breakUndoCoalescing];
    [tv.undoManager setActionName:@"Macro"];
}

@end

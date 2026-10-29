//
//  QSheets.m — the original's small dialogs as macOS sheets.
//
//  Each one keeps its original controls; the layout is a standard form
//  (labels right-aligned in a grid, buttons bottom-right, default button
//  last) rather than the dialog-unit geometry of the Windows templates.
//

#import "QChrome.h"
#import <objc/runtime.h>

#pragma mark - Sheet scaffolding

/// A sheet window with a form and a row of buttons, retained until it ends.
@interface QSheet : NSObject
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSStackView *buttons;
@property (nonatomic, copy) void (^onEnd)(NSModalResponse response);
+ (instancetype)sheetWithTitle:(NSString *)title content:(NSView *)content;
- (NSButton *)addButton:(NSString *)title response:(NSModalResponse)response
               isDefault:(BOOL)isDefault;
- (void)beginForWindow:(NSWindow *)parent;
@end

static NSMutableSet<QSheet *> *sLiveSheets;

@implementation QSheet

+ (instancetype)sheetWithTitle:(NSString *)title content:(NSView *)content {
    QSheet *s = [[QSheet alloc] init];
    NSView *root = [[NSView alloc] init];

    NSTextField *heading = [NSTextField labelWithString:title];
    heading.font = [NSFont systemFontOfSize:NSFont.systemFontSize + 2
                                     weight:NSFontWeightSemibold];

    s.buttons = [[NSStackView alloc] init];
    s.buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    s.buttons.spacing = 10;

    for (NSView *v in @[heading, content, s.buttons]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [heading.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],
        [heading.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [content.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:14],
        [content.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [content.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [s.buttons.topAnchor constraintEqualToAnchor:content.bottomAnchor constant:20],
        [s.buttons.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [s.buttons.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20],
        [root.widthAnchor constraintGreaterThanOrEqualToConstant:420],
    ]];

    s.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 200)
                                           styleMask:NSWindowStyleMaskTitled
                                             backing:NSBackingStoreBuffered
                                               defer:YES];
    s.window.contentView = root;
    return s;
}

- (NSButton *)addButton:(NSString *)title response:(NSModalResponse)response
               isDefault:(BOOL)isDefault {
    NSButton *b = [NSButton buttonWithTitle:title target:self
                                     action:@selector(buttonClicked:)];
    b.tag = response;
    if (isDefault) b.keyEquivalent = @"\r";
    else if (response == NSModalResponseCancel) b.keyEquivalent = @"\033";
    [b.widthAnchor constraintGreaterThanOrEqualToConstant:80].active = YES;
    [self.buttons addArrangedSubview:b];
    return b;
}

- (void)buttonClicked:(NSButton *)sender {
    [self endWith:sender.tag];
}

- (void)endWith:(NSModalResponse)response {
    NSWindow *parent = self.window.sheetParent;
    if (self.onEnd) self.onEnd(response);
    // Continue (and the one after it) are buttons that keep the sheet open.
    if (response == NSModalResponseContinue ||
        response == NSModalResponseContinue + 1) return;
    [parent endSheet:self.window returnCode:response];
}

- (void)beginForWindow:(NSWindow *)parent {
    if (!sLiveSheets) sLiveSheets = [NSMutableSet set];
    [sLiveSheets addObject:self];
    [self.window layoutIfNeeded];
    [parent beginSheet:self.window completionHandler:^(NSModalResponse r) {
        [sLiveSheets removeObject:self];
    }];
}

@end

/// A two-column form: labels on the right edge of the first column.
static NSGridView *Form(NSArray<NSArray<NSView *> *> *rows) {
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.rowSpacing = 8;
    grid.columnSpacing = 8;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    return grid;
}

#pragma mark - File ▸ New

@implementation QNewDocumentSheet

+ (void)beginSheetForWindow:(NSWindow *)window
                 completion:(void (^)(NSString *extension))completion {
    // The original's document templates, in its order, with Project first.
    NSArray *types = @[
        @[@"Project",              @".prj", @"shippingbox"],
        @[@"C++ Source File",      @".cpp", @"chevron.left.forwardslash.chevron.right"],
        @[@"C Source File",        @".c",   @"chevron.left.forwardslash.chevron.right"],
        @[@"Header File",          @".h",   @"doc.text"],
        @[@"Resource Source File", @".rc",  @"doc.text.image"],
        @[@"DLL Export List",      @".def", @"list.bullet"],
        @[@"Text File",            @".txt", @"doc.plaintext"],
    ];
    NSStackView *list = [[NSStackView alloc] init];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.spacing = 6;
    NSMutableArray<NSButton *> *radios = [NSMutableArray array];
    for (NSArray *t in types) {
        NSButton *r = [NSButton radioButtonWithTitle:
                       [NSString stringWithFormat:@"%@  (%@)", t[0], t[1]]
                                              target:nil action:nil];
        r.image = [NSImage imageWithSystemSymbolName:t[2]
                            accessibilityDescription:nil];
        r.imagePosition = NSImageLeading;
        [radios addObject:r];
        [list addArrangedSubview:r];
    }
    radios[1].state = NSControlStateValueOn;   // C++ is what people want
    // Radios in one stack act as a group only if they share an action.
    for (NSButton *r in radios) QSetBlockAction(r, ^(id sender) {});

    QSheet *sheet = [QSheet sheetWithTitle:@"New" content:list];
    [sheet addButton:@"Cancel" response:NSModalResponseCancel isDefault:NO];
    [sheet addButton:@"Create" response:NSModalResponseOK isDefault:YES];
    sheet.onEnd = ^(NSModalResponse r) {
        if (r != NSModalResponseOK) { completion(nil); return; }
        for (NSUInteger i = 0; i < radios.count; i++)
            if (radios[i].state == NSControlStateValueOn) {
                completion(types[i][1]);
                return;
            }
        completion(nil);
    };
    [sheet beginForWindow:window];
}

@end

#pragma mark - Add Watch

@implementation QAddWatchSheet

+ (void)beginSheetForWindow:(NSWindow *)window
                 completion:(void (^)(NSString *expression))completion {
    NSTextField *field = QTextField(@"e.g. count or argv[0]");
    field.font = [NSFont monospacedSystemFontOfSize:NSFont.systemFontSize
                                             weight:NSFontWeightRegular];
    [field.widthAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;
    NSGridView *form = Form(@[@[QLabel(@"Expression:"), field]]);

    QSheet *sheet = [QSheet sheetWithTitle:@"Add Watch" content:form];
    [sheet addButton:@"Cancel" response:NSModalResponseCancel isDefault:NO];
    [sheet addButton:@"Add" response:NSModalResponseOK isDefault:YES];
    sheet.onEnd = ^(NSModalResponse r) {
        completion(r == NSModalResponseOK
                   ? [field.stringValue stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceCharacterSet]
                   : nil);
    };
    [sheet beginForWindow:window];
    [sheet.window makeFirstResponder:field];
}

@end

#pragma mark - Project Properties

@implementation QProjectPropertiesSheet

+ (void)beginSheetForWindow:(NSWindow *)window {
    QWindowController *wc = [QWindowController shared];
    QProject *project = wc.project;
    if (!project) { NSBeep(); return; }

    NSTextField *target = QTextField(@"Target name");
    target.stringValue = project.target ?: @"";
    NSTextField *output = QTextField(@"Same folder as the project");
    output.stringValue = project.outputDirectory ?: @"";
    NSTextField *includes = QTextField(@"folders separated by ;");
    includes.stringValue = project.includes ?: @"";
    NSTextField *defines = QTextField(@"NAME;NAME=value");
    defines.stringValue = project.defines ?: @"";
    NSTextField *libraries = QTextField(@"m;pthread or a folder");
    libraries.stringValue = project.libraries ?: @"";
    [target.widthAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;

    NSPopUpButton *type = [[NSPopUpButton alloc] init];
    NSArray *kinds = @[@"Console application", @"Static library (.a)",
                       @"Dynamic library (.dylib)", @"Win32 GUI application",
                       @"WinBGIm graphics", @"koolplot", @"FLTK"];
    [type addItemsWithTitles:kinds];
    type.autoenablesItems = NO;
    for (NSInteger i = QProjectWin32GUI; i < (NSInteger)kinds.count; i++) {
        NSMenuItem *it = [type itemAtIndex:i];
        it.enabled = NO;
        it.toolTip = @"Not available on macOS";
    }
    [type selectItemAtIndex:project.type];

    NSGridView *form = Form(@[
        @[QLabel(@"Target:"), target],
        @[QLabel(@"Type:"), type],
        @[QLabel(@"Output folder:"), output],
        @[QLabel(@"Include paths:"), includes],
        @[QLabel(@"Defines:"), defines],
        @[QLabel(@"Libraries:"), libraries],
        @[[NSGridCell emptyContentView],
          QSecondaryLabel(@"Win32 GUI, WinBGIm, koolplot and FLTK targets need "
                          "Windows libraries and are not available on macOS.")],
    ]);

    QSheet *sheet = [QSheet sheetWithTitle:@"Project Properties" content:form];
    [sheet addButton:@"Cancel" response:NSModalResponseCancel isDefault:NO];
    [sheet addButton:@"OK" response:NSModalResponseOK isDefault:YES];
    sheet.onEnd = ^(NSModalResponse r) {
        if (r != NSModalResponseOK) return;
        project.target = target.stringValue;
        project.type = (QProjectType)type.indexOfSelectedItem;
        project.outputDirectory = output.stringValue;
        project.includes = includes.stringValue;
        project.defines = defines.stringValue;
        project.libraries = libraries.stringValue;
        NSError *error = nil;
        if (![project save:&error]) [wc reportError:error message:@"Failed to save document."];
        [wc refreshChrome];
    };
    [sheet beginForWindow:window];
}

@end

#pragma mark - Examine

@implementation QExamineSheet

+ (void)beginSheetForWindow:(NSWindow *)window expression:(NSString *)expression {
    NSTextField *expr = QTextField(@"Expression");
    expr.stringValue = expression ?: @"";
    expr.font = [NSFont monospacedSystemFontOfSize:NSFont.systemFontSize
                                            weight:NSFontWeightRegular];
    [expr.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    NSTextField *value = [NSTextField wrappingLabelWithString:@""];
    value.font = expr.font;
    value.selectable = YES;
    NSTextField *change = QTextField(@"New value");
    change.font = expr.font;

    NSGridView *form = Form(@[
        @[QLabel(@"Expression:"), expr],
        @[QLabel(@"Value:"), value],
        @[QLabel(@"Change to:"), change],
    ]);

    void (^examine)(void) = ^{
        NSString *e = expr.stringValue;
        if (!e.length) return;
        [[QDebugger shared] evaluate:e completion:^(NSString *v, NSString *error) {
            value.stringValue = v ?: [@"?? " stringByAppendingString:error ?: @""];
        }];
    };
    QSetBlockAction(expr, ^(id sender) { examine(); });

    QSheet *sheet = [QSheet sheetWithTitle:@"Examine" content:form];
    [sheet addButton:@"Close" response:NSModalResponseCancel isDefault:NO];
    [sheet addButton:@"Change" response:NSModalResponseContinue + 1 isDefault:NO];
    [sheet addButton:@"Examine" response:NSModalResponseContinue isDefault:YES];
    sheet.onEnd = ^(NSModalResponse r) {
        if (r == NSModalResponseContinue) { examine(); return; }
        if (r == NSModalResponseContinue + 1) {
            if (!expr.stringValue.length || !change.stringValue.length) return;
            NSString *assign = [NSString stringWithFormat:@"%@ = %@",
                                expr.stringValue, change.stringValue];
            [[QDebugger shared] evaluate:assign completion:^(NSString *v, NSString *error) {
                value.stringValue = v ?: [@"?? " stringByAppendingString:error ?: @""];
                [[QDebugger shared] refreshWatches];
            }];
        }
    };
    [sheet beginForWindow:window];
    [sheet.window makeFirstResponder:expr];
    examine();
}

@end

#pragma mark - Grep

@implementation QGrepSheet

+ (void)beginSheetForWindow:(NSWindow *)window {
    QWindowController *wc = [QWindowController shared];
    NSTextField *pattern = QTextField(@"Text to find");
    [pattern.widthAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;
    NSString *selection = nil;
    NSTextView *tv = wc.activeEditor.textView;
    if (tv.selectedRange.length && tv.selectedRange.length < 100)
        selection = [tv.string substringWithRange:tv.selectedRange];
    pattern.stringValue = selection ?: @"";

    NSString *folder = wc.activeDocument.url.URLByDeletingLastPathComponent.path
                     ?: NSHomeDirectory();
    NSTextField *where = QTextField(@"Folder");
    where.stringValue = folder;
    NSTextField *files = QTextField(@"File types");
    files.stringValue = @"*.c *.cpp *.cc *.cxx *.h *.rc";
    NSButton *matchCase = [NSButton checkboxWithTitle:@"Match case"
                                               target:nil action:nil];
    NSButton *matchWord = [NSButton checkboxWithTitle:@"Match whole word"
                                               target:nil action:nil];

    NSGridView *form = Form(@[
        @[QLabel(@"Find:"), pattern],
        @[QLabel(@"In folder:"), where],
        @[QLabel(@"Files:"), files],
        @[[NSGridCell emptyContentView], matchCase],
        @[[NSGridCell emptyContentView], matchWord],
    ]);

    QSheet *sheet = [QSheet sheetWithTitle:@"Find in Files" content:form];
    [sheet addButton:@"Cancel" response:NSModalResponseCancel isDefault:NO];
    [sheet addButton:@"Find" response:NSModalResponseOK isDefault:YES];
    sheet.onEnd = ^(NSModalResponse r) {
        if (r != NSModalResponseOK || !pattern.stringValue.length) return;
        [self runGrep:pattern.stringValue folder:where.stringValue
             patterns:files.stringValue
            matchCase:matchCase.state == NSControlStateValueOn
            matchWord:matchWord.state == NSControlStateValueOn];
    };
    [sheet beginForWindow:window];
    [sheet.window makeFirstResponder:pattern];
}

/// Bumped by every new search and by Stop; a search whose number is no
/// longer current gives up between files.
static _Atomic(uint32_t) sGrepGeneration = 0;
static BOOL sGrepSearching = NO;

+ (BOOL)isSearching { return sGrepSearching; }

+ (void)stop {
    if (!sGrepSearching) return;
    sGrepGeneration++;
    sGrepSearching = NO;
    QWindowController *wc = [QWindowController shared];
    [wc appendBuildMessage:[QBuildMessage messageWithText:@"Search stopped by user"]];
    [wc showStatus:@"Search stopped by user"];
    [wc refreshChrome];
}

/// Native search on a background queue; results stream into the build log,
/// where a double-click opens the file at the line — the original's Grep
/// Results window did the same.
+ (void)runGrep:(NSString *)needle folder:(NSString *)folder
       patterns:(NSString *)patternList
      matchCase:(BOOL)matchCase matchWord:(BOOL)matchWord {
    QWindowController *wc = [QWindowController shared];
    [wc clearBuildLog];
    [wc showBottomTab:0];
    [wc showStatus:[NSString stringWithFormat:@"Searching for \"%@\"…", needle]];

    NSMutableSet *extensions = [NSMutableSet set];
    for (NSString *p in [patternList componentsSeparatedByCharactersInSet:
                         NSCharacterSet.whitespaceCharacterSet])
        if ([p hasPrefix:@"*."]) [extensions addObject:[p substringFromIndex:2].lowercaseString];

    NSRegularExpressionOptions opts = matchCase ? 0 : NSRegularExpressionCaseInsensitive;
    NSString *escaped = [NSRegularExpression escapedPatternForString:needle];
    if (matchWord) escaped = [NSString stringWithFormat:@"\\b%@\\b", escaped];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:escaped
                                                                        options:opts
                                                                          error:NULL];
    uint32_t generation = ++sGrepGeneration;
    sGrepSearching = YES;
    [wc refreshChrome];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block NSUInteger hits = 0;
        NSUInteger filesSeen = 0;
        NSDirectoryEnumerator *e = [NSFileManager.defaultManager
            enumeratorAtURL:[NSURL fileURLWithPath:folder]
            includingPropertiesForKeys:nil
            options:NSDirectoryEnumerationSkipsHiddenFiles |
                    NSDirectoryEnumerationSkipsPackageDescendants
            errorHandler:nil];
        for (NSURL *url in e) {
            if (generation != sGrepGeneration) return;
            if (![extensions containsObject:url.pathExtension.lowercaseString]) continue;
            NSString *text = [NSString stringWithContentsOfURL:url
                                                      encoding:NSUTF8StringEncoding
                                                         error:NULL]
                ?: [NSString stringWithContentsOfURL:url
                                            encoding:NSISOLatin1StringEncoding
                                               error:NULL];
            if (!text) continue;
            filesSeen++;
            __block NSInteger lineNo = 0;
            [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
                lineNo++;
                NSTextCheckingResult *m = [re firstMatchInString:line options:0
                                                           range:NSMakeRange(0, line.length)];
                if (!m) return;
                hits++;
                QBuildMessage *msg = [QBuildMessage messageWithText:
                    [NSString stringWithFormat:@"%@:%ld: %@",
                     [url.path hasPrefix:[folder stringByAppendingString:@"/"]]
                        ? [url.path substringFromIndex:folder.length + 1]
                        : url.path.lastPathComponent,
                     (long)lineNo, [line stringByTrimmingCharactersInSet:
                                    NSCharacterSet.whitespaceCharacterSet]]];
                msg.path = url.path;
                msg.line = lineNo;
                msg.column = (NSInteger)m.range.location + 1;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [wc appendBuildMessage:msg];
                });
            }];
        }
        NSString *summary = [NSString stringWithFormat:@"%lu %@ found in %lu files",
                             (unsigned long)hits, hits == 1 ? @"match" : @"matches",
                             (unsigned long)filesSeen];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != sGrepGeneration) return;
            sGrepSearching = NO;
            [wc appendBuildMessage:[QBuildMessage messageWithText:summary]];
            [wc showStatus:summary];
            [wc refreshChrome];
        });
    });
}

@end

#pragma mark - Code Beautifier

@implementation QBeautifierSheet

+ (void)beginSheetForWindow:(NSWindow *)window {
    QOptions *opt = [QOptions shared];
    QWindowController *wc = [QWindowController shared];

    NSPopUpButton *style = [[NSPopUpButton alloc] init];
    [style addItemsWithTitles:@[@"ALLMAN / BSD", @"K&R", @"ANSI", @"GNU", @"Custom"]];
    [style selectItemAtIndex:opt.indentStyle];

    NSTextField *custom = QTextField(@"AStyle options");
    custom.stringValue = opt.customAStyleOptions ?: @"";
    custom.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize
                                              weight:NSFontWeightRegular];
    [custom.widthAnchor constraintGreaterThanOrEqualToConstant:320].active = YES;

    NSTextField *commandLine = QSecondaryLabel(@"");
    commandLine.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize
                                                   weight:NSFontWeightRegular];

    // A live sample, as the original had, run through AStyle itself.
    NSTextView *sample = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 380, 160)];
    sample.editable = NO;
    sample.textContainerInset = NSMakeSize(6, 6);
    NSScrollView *sampleScroll = [[NSScrollView alloc] init];
    sampleScroll.documentView = sample;
    sampleScroll.hasVerticalScroller = YES;
    sampleScroll.borderType = NSBezelBorder;
    [sampleScroll.heightAnchor constraintEqualToConstant:170].active = YES;

    NSString *source = @"namespace demo {\nclass Counter {\npublic:\n"
        "int next(int step) { if (step < 0) { return value; } "
        "switch (step) { case 0: return value; default: value += step; } "
        "return value; }\nprivate:\nint value;\n};\n}\n";

    void (^refresh)(void) = ^{
        opt.indentStyle = style.indexOfSelectedItem;
        opt.customAStyleOptions = custom.stringValue;
        custom.enabled = opt.indentStyle == QIndentCustom;
        commandLine.stringValue = [NSString stringWithFormat:@"astyle %@",
                                   [opt astyleOptions]];
        NSString *error = nil;
        NSString *formatted = QAStyleFormat(source, [opt astyleOptions], &error);
        [sample.textStorage setAttributedString:
            [QSyntax colourise:formatted ?: (error ?: source)
                          font:[NSFont monospacedSystemFontOfSize:11
                                                           weight:NSFontWeightRegular]]];
    };
    QSetBlockAction(style, ^(id sender) { refresh(); });
    QSetBlockAction(custom, ^(id sender) { refresh(); });

    NSGridView *form = Form(@[
        @[QLabel(@"Style:"), style],
        @[QLabel(@"Options:"), custom],
        @[[NSGridCell emptyContentView], commandLine],
        @[QLabel(@"Sample:"), sampleScroll],
    ]);
    refresh();

    QSheet *sheet = [QSheet sheetWithTitle:@"Code Beautifier" content:form];
    [sheet addButton:@"Cancel" response:NSModalResponseCancel isDefault:NO];
    [sheet addButton:@"Test" response:NSModalResponseContinue isDefault:NO];
    [sheet addButton:@"Beautify" response:NSModalResponseOK isDefault:YES];
    sheet.onEnd = ^(NSModalResponse r) {
        if (r == NSModalResponseContinue) { refresh(); return; }
        [opt save];
        if (r != NSModalResponseOK) return;
        NSTextView *tv = wc.activeEditor.textView;
        if (!tv) return;
        NSString *error = nil;
        NSString *formatted = QAStyleFormat(tv.string, [opt astyleOptions], &error);
        if (!formatted) {
            [wc showStatus:error ?: @"AStyle failed"];
            NSBeep();
            return;
        }
        // One undoable edit for the whole file.
        NSRange all = NSMakeRange(0, tv.string.length);
        if ([tv shouldChangeTextInRange:all replacementString:formatted]) {
            [tv.textStorage replaceCharactersInRange:all withString:formatted];
            [tv didChangeText];
        }
        [wc showStatus:@"Code beautified"];
    };
    [sheet beginForWindow:window];
}

@end

#pragma mark - About

@implementation QAboutPanel

+ (NSString *)clangVersion {
    static NSString *version;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:[[QOptions shared] compilerPath]];
        task.arguments = @[@"--version"];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = NSFileHandle.fileHandleWithNullDevice;
        if (![task launchAndReturnError:NULL]) { version = @"clang not found"; return; }
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        [task waitUntilExit];
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        version = [s componentsSeparatedByString:@"\n"].firstObject ?: @"";
    });
    return version;
}

+ (void)show {
    NSProcessInfo *pi = NSProcessInfo.processInfo;
    NSOperatingSystemVersion v = pi.operatingSystemVersion;
    NSString *credits = [NSString stringWithFormat:
        @"Quincy 2005 v1.3 05-Feb-2008\n"
         "by Al Stevens, Dr. Dobb's Journal\n"
         "http://www.codecutter.net/tools/quincy/\n"
         "%@\nAStyle %@\nmacOS %ld.%ld.%ld (arm64)",
        [self clangVersion], QAStyleVersion(),
        (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion];
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
        NSParagraphStyleAttributeName: ps,
    };
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];

    // The Dr. Dobb's logo from the original About box, on its own line.
    NSImage *logo = [NSImage imageNamed:@"ddj"];
    if (logo) {
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        attachment.image = logo;
        // A little smaller than on Windows, so every line fits unscrolled.
        attachment.bounds = NSMakeRect(0, 0, round(logo.size.width * 0.7),
                                       round(logo.size.height * 0.7));
        NSMutableAttributedString *picture = [[NSAttributedString
            attributedStringWithAttachment:attachment] mutableCopy];
        [picture addAttribute:NSParagraphStyleAttributeName value:ps
                        range:NSMakeRange(0, picture.length)];
        [text appendAttributedString:picture];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
                                                                     attributes:attrs]];
    }
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:credits
                                                                 attributes:attrs]];
    NSString *site = @"http://www.codecutter.net/tools/quincy/";
    NSRange link = [text.string rangeOfString:site];
    if (link.location != NSNotFound)
        [text addAttribute:NSLinkAttributeName value:[NSURL URLWithString:site] range:link];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        NSAboutPanelOptionApplicationName: @"Quincy 2005",
        NSAboutPanelOptionApplicationVersion: @"1.3",
        NSAboutPanelOptionVersion: @"05-Feb-2008",
        NSAboutPanelOptionCredits: text,
    }];
}

@end

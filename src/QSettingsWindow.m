//
//  QSettingsWindow.m — Quincy ▸ Settings.
//
//  The original's Options dialog had Build, Run and Editor tabs; this is the
//  same three pages in the macOS Settings form: a toolbar of panes, changes
//  applied as they are made, no OK or Cancel.
//

#import "QChrome.h"
#import <objc/runtime.h>

static NSGridView *SettingsForm(NSArray<NSArray<NSView *> *> *rows) {
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.rowSpacing = 10;
    grid.columnSpacing = 10;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    return grid;
}

/// Wraps a form in the standard Settings margins.
static NSViewController *Page(NSString *title, NSString *symbol, NSView *content) {
    NSView *root = [[NSView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:root.topAnchor constant:20],
        [content.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:30],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor
                                                         constant:-30],
        [content.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-20],
        [root.widthAnchor constraintGreaterThanOrEqualToConstant:540],
    ]];
    // Each pane asks for exactly its own size, so the window resizes per pane
    // as Settings windows do.
    [root layoutSubtreeIfNeeded];
    NSSize fit = content.fittingSize;
    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = root;
    vc.title = title;
    vc.preferredContentSize = NSMakeSize(MAX(540, fit.width + 60), fit.height + 40);
    objc_setAssociatedObject(vc, "symbol", symbol, OBJC_ASSOCIATION_COPY);
    return vc;
}

static NSButton *Check(NSString *title, BOOL on, void (^changed)(BOOL on)) {
    NSButton *b = [NSButton checkboxWithTitle:title target:nil action:nil];
    b.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    QSetBlockAction(b, ^(NSButton *sender) {
        changed(sender.state == NSControlStateValueOn);
        [[QOptions shared] save];
    });
    return b;
}

static NSTextField *Field(NSString *value, NSString *placeholder,
                          void (^changed)(NSString *value)) {
    NSTextField *f = QTextField(placeholder);
    f.stringValue = value ?: @"";
    [f.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    QSetBlockAction(f, ^(NSTextField *sender) {
        changed(sender.stringValue);
        [[QOptions shared] save];
    });
    // Commit on every keystroke too, so closing the window never loses an edit.
    [NSNotificationCenter.defaultCenter
        addObserverForName:NSControlTextDidChangeNotification object:f queue:nil
                usingBlock:^(NSNotification *note) {
        changed(f.stringValue);
        [[QOptions shared] save];
    }];
    return f;
}

static NSPopUpButton *Popup(NSArray<NSString *> *titles, NSInteger selected,
                            void (^changed)(NSInteger index)) {
    NSPopUpButton *p = [[NSPopUpButton alloc] init];
    [p addItemsWithTitles:titles];
    [p selectItemAtIndex:selected];
    QSetBlockAction(p, ^(NSPopUpButton *sender) {
        changed(sender.indexOfSelectedItem);
        [[QOptions shared] save];
    });
    return p;
}

@implementation QSettingsWindowController {
    NSTextView *_sample;
    NSArray<NSColorWell *> *_wells;
}

+ (instancetype)shared {
    static QSettingsWindowController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[QSettingsWindowController alloc] init]; });
    return shared;
}

+ (void)showSettings {
    QSettingsWindowController *wc = [self shared];
    [wc showWindow:nil];
    [wc.window makeKeyAndOrderFront:nil];
}

- (instancetype)init {
    NSTabViewController *tabs = [[NSTabViewController alloc] init];
    tabs.tabStyle = NSTabViewControllerTabStyleToolbar;
    NSWindow *window = [NSWindow windowWithContentViewController:tabs];
    window.styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    window.toolbarStyle = NSWindowToolbarStylePreference;
    if (!(self = [super initWithWindow:window])) return nil;

    for (NSViewController *vc in @[[self buildPage], [self runPage], [self editorPage]]) {
        NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:vc];
        item.label = vc.title;
        item.image = [NSImage imageWithSystemSymbolName:
                      objc_getAssociatedObject(vc, "symbol")
                               accessibilityDescription:vc.title];
        [tabs addTabViewItem:item];
    }
    [window center];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(refreshSample) name:QOptionsDidChangeNotification
          object:nil];
    return self;
}

#pragma mark - Build

- (NSViewController *)buildPage {
    QOptions *o = [QOptions shared];
    NSStackView *checks = [NSStackView stackViewWithViews:@[
        Check(@"Include debug information", o.debugInfo, ^(BOOL on) { o.debugInfo = on; }),
        Check(@"Run-time type information (RTTI)", o.rtti, ^(BOOL on) { o.rtti = on; }),
        Check(@"C++ exceptions", o.exceptions, ^(BOOL on) { o.exceptions = on; }),
        Check(@"Strict ANSI/ISO conformance", o.strictAnsi, ^(BOOL on) { o.strictAnsi = on; }),
        Check(@"C99", o.c99, ^(BOOL on) { o.c99 = on; }),
    ]];
    checks.orientation = NSUserInterfaceLayoutOrientationVertical;
    checks.alignment = NSLayoutAttributeLeading;
    checks.spacing = 6;

    NSGridView *form = SettingsForm(@[
        @[QLabel(@"Compiler:"), checks],
        @[QLabel(@"Optimization:"), Popup(@[@"None", @"Level 1 (-O1)",
                                             @"Level 2 (-O2)", @"Level 3 (-O3)",
                                             @"Smallest (-Os)"],
                                           o.optimize, ^(NSInteger i) { o.optimize = i; })],
        @[QLabel(@"Warnings:"), Popup(@[@"Default", @"All (-Wall)", @"None (-w)"],
                                       o.warnings, ^(NSInteger i) { o.warnings = i; })],
        @[QLabel(@"Defines:"), Field(o.defines, @"NAME;NAME=value",
                                      ^(NSString *v) { o.defines = v; })],
        @[QLabel(@"Include paths:"), Field(o.includes, @"folders separated by ;",
                                            ^(NSString *v) { o.includes = v; })],
        @[QLabel(@"Libraries:"), Field(o.libraries, @"m;pthread",
                                        ^(NSString *v) { o.libraries = v; })],
        @[QLabel(@"Compiler options:"), Field(o.compilerOptions, @"extra flags",
                                               ^(NSString *v) { o.compilerOptions = v; })],
        @[QLabel(@"Linker options:"), Field(o.linkerOptions, @"extra flags",
                                             ^(NSString *v) { o.linkerOptions = v; })],
        @[QLabel(@"Toolchain:"), Field(o.toolchainPath, @"/usr/bin (Command Line Tools)",
                                        ^(NSString *v) { o.toolchainPath = v; })],
    ]);
    return Page(@"Build", @"hammer", form);
}

#pragma mark - Run

- (NSViewController *)runPage {
    QOptions *o = [QOptions shared];
    NSTextField *args = Field(o.arguments, @"arguments passed to the program",
                              ^(NSString *v) { o.arguments = v; });
    args.enabled = o.argumentsMode == QArgumentsFixed;

    NSArray *titles = @[@"None", @"Ask each time the program runs", @"Always use:"];
    NSMutableArray<NSButton *> *radios = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSButton *r = [NSButton radioButtonWithTitle:titles[i] target:nil action:nil];
        r.state = (NSInteger)i == o.argumentsMode ? NSControlStateValueOn
                                                  : NSControlStateValueOff;
        QSetBlockAction(r, ^(id sender) {
            o.argumentsMode = (QArgumentsMode)i;
            args.enabled = i == QArgumentsFixed;
            [o save];
        });
        [radios addObject:r];
    }
    NSStackView *argStack = [NSStackView stackViewWithViews:@[radios[0], radios[1],
                                                              radios[2], args]];
    argStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    argStack.alignment = NSLayoutAttributeLeading;
    argStack.spacing = 6;

    NSTextField *dir = Field(o.workingDirectory, @"the program's own folder",
                             ^(NSString *v) { o.workingDirectory = v; });
    NSButton *choose = [NSButton buttonWithTitle:@"Choose…" target:nil action:nil];
    QSetBlockAction(choose, ^(id sender) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.canChooseDirectories = YES;
        panel.canChooseFiles = NO;
        if ([panel runModal] != NSModalResponseOK) return;
        dir.stringValue = panel.URL.path;
        o.workingDirectory = panel.URL.path;
        [o save];
    });
    NSStackView *dirRow = [NSStackView stackViewWithViews:@[dir, choose]];
    dirRow.spacing = 8;

    NSGridView *form = SettingsForm(@[
        @[QLabel(@"Arguments:"), argStack],
        @[QLabel(@"Working folder:"), dirRow],
        @[[NSGridCell emptyContentView],
          QSecondaryLabel(@"Programs run in Quincy's own console window. "
                          "Leave the folder empty to run in the program's folder.")],
    ]);
    return Page(@"Run", @"play", form);
}

#pragma mark - Editor

- (NSViewController *)editorPage {
    QOptions *o = [QOptions shared];
    __weak typeof(self) weakSelf = self;

    NSColorWell *(^well)(NSColor *, void (^)(NSColor *)) =
        ^NSColorWell *(NSColor *c, void (^set)(NSColor *)) {
        NSColorWell *w = [[NSColorWell alloc] init];
        if (@available(macOS 13.0, *)) w.colorWellStyle = NSColorWellStyleMinimal;
        w.color = c;
        [w.widthAnchor constraintEqualToConstant:44].active = YES;
        QSetBlockAction(w, ^(NSColorWell *sender) {
            set(sender.color);
            o.themeKind = QThemeCustom;
            [o save];
        });
        return w;
    };
    NSColorWell *bg = well(o.customBackground, ^(NSColor *c) { o.customBackground = c; });
    NSColorWell *fg = well(o.customText, ^(NSColor *c) { o.customText = c; });
    NSColorWell *cm = well(o.customComment, ^(NSColor *c) { o.customComment = c; });
    NSColorWell *kw = well(o.customKeyword, ^(NSColor *c) { o.customKeyword = c; });
    NSColorWell *st = well(o.customString, ^(NSColor *c) { o.customString = c; });
    _wells = @[bg, fg, cm, kw, st];

    NSStackView *colours = [[NSStackView alloc] init];
    colours.spacing = 12;
    NSArray *names = @[@"Background", @"Text", @"Comments", @"Keywords", @"Strings"];
    for (NSUInteger i = 0; i < _wells.count; i++) {
        NSStackView *cell = [NSStackView stackViewWithViews:@[_wells[i],
                                                              QSecondaryLabel(names[i])]];
        cell.orientation = NSUserInterfaceLayoutOrientationVertical;
        cell.spacing = 4;
        [colours addArrangedSubview:cell];
    }

    NSPopUpButton *theme = Popup(@[@"Match System Appearance",
                                   @"Classic (white, as in Quincy for Windows)",
                                   @"Custom"], o.themeKind,
                                 ^(NSInteger i) { o.themeKind = (QThemeKind)i; });

    // Font size with −/+ as the original had, through a standard stepper.
    NSTextField *sizeLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"%.0f pt", o.fontSize]];
    NSStepper *stepper = [[NSStepper alloc] init];
    stepper.minValue = 8;
    stepper.maxValue = 36;
    stepper.increment = 1;
    stepper.doubleValue = o.fontSize;
    QSetBlockAction(stepper, ^(NSStepper *sender) {
        o.fontSize = sender.doubleValue;
        sizeLabel.stringValue = [NSString stringWithFormat:@"%.0f pt", o.fontSize];
        [o save];
    });
    NSButton *bold = Check(@"Bold", o.fontBold, ^(BOOL on) { o.fontBold = on; });
    NSStackView *fontRow = [NSStackView stackViewWithViews:@[sizeLabel, stepper, bold]];
    fontRow.spacing = 8;

    NSTextField *tabLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"%ld", (long)o.tabStops]];
    NSStepper *tabStepper = [[NSStepper alloc] init];
    tabStepper.minValue = 1;
    tabStepper.maxValue = 16;
    tabStepper.integerValue = o.tabStops;
    QSetBlockAction(tabStepper, ^(NSStepper *sender) {
        o.tabStops = sender.integerValue;
        tabLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)o.tabStops];
        [o save];
    });
    NSButton *useTabs = Check(@"Insert tab characters", o.useTabCharacters,
                              ^(BOOL on) { o.useTabCharacters = on; });
    NSStackView *tabRow = [NSStackView stackViewWithViews:@[tabLabel, tabStepper, useTabs]];
    tabRow.spacing = 8;

    NSTextField *undos = Field([NSString stringWithFormat:@"%ld", (long)o.maxUndos], @"",
                               ^(NSString *v) { o.maxUndos = MAX(1, v.integerValue); });
    [undos.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *behaviour = [NSStackView stackViewWithViews:@[
        Check(@"Syntax colouring", o.syntaxEnabled, ^(BOOL on) { o.syntaxEnabled = on; }),
        Check(@"Automatic indentation", o.autoindent, ^(BOOL on) { o.autoindent = on; }),
        Check(@"Show line numbers", o.showLineNumbers, ^(BOOL on) { o.showLineNumbers = on; }),
    ]];
    behaviour.orientation = NSUserInterfaceLayoutOrientationVertical;
    behaviour.alignment = NSLayoutAttributeLeading;
    behaviour.spacing = 6;

    _sample = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 380, 120)];
    _sample.editable = NO;
    _sample.textContainerInset = NSMakeSize(8, 8);
    NSScrollView *sampleScroll = [[NSScrollView alloc] init];
    sampleScroll.documentView = _sample;
    sampleScroll.borderType = NSBezelBorder;
    [sampleScroll.heightAnchor constraintEqualToConstant:130].active = YES;
    [sampleScroll.widthAnchor constraintGreaterThanOrEqualToConstant:380].active = YES;

    NSButton *restore = [NSButton buttonWithTitle:@"Restore Defaults" target:nil action:nil];
    QSetBlockAction(restore, ^(id sender) {
        [o restoreEditorDefaults];
        [o save];
        [weakSelf reloadEditorControls];
    });

    NSGridView *form = SettingsForm(@[
        @[QLabel(@"Theme:"), theme],
        @[QLabel(@"Colours:"), colours],
        @[QLabel(@"Font size:"), fontRow],
        @[QLabel(@"Tab width:"), tabRow],
        @[QLabel(@"Undo levels:"), undos],
        @[QLabel(@"Editing:"), behaviour],
        @[QLabel(@"Sample:"), sampleScroll],
        @[[NSGridCell emptyContentView], restore],
    ]);
    [self refreshSample];
    return Page(@"Editor", @"character.cursor.ibeam", form);
}

- (void)reloadEditorControls {
    // Simplest faithful reset: rebuild the window from current settings.
    NSTabViewController *tabs = (NSTabViewController *)self.contentViewController;
    NSInteger selected = tabs.selectedTabViewItemIndex;
    [tabs removeTabViewItem:tabs.tabViewItems.lastObject];
    NSViewController *vc = [self editorPage];
    NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:vc];
    item.label = vc.title;
    item.image = [NSImage imageWithSystemSymbolName:@"character.cursor.ibeam"
                           accessibilityDescription:vc.title];
    [tabs addTabViewItem:item];
    tabs.selectedTabViewItemIndex = selected;
}

- (void)refreshSample {
    if (!_sample) return;
    QOptions *o = [QOptions shared];
    NSString *code = @"#include <iostream>\n\n/* Quincy 2005 */\nint main()\n{\n"
                      "    // say hello\n    std::cout << \"Hello, world\" << '\\n';\n"
                      "    return 0;\n}\n";
    [_sample.textStorage setAttributedString:[QSyntax colourise:code font:[o editorFont]]];
    _sample.backgroundColor = [o backgroundColour];
    for (NSColorWell *w in _wells) w.enabled = o.themeKind == QThemeCustom;
}

@end

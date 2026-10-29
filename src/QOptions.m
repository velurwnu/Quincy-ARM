//
//  QOptions.m — persisted settings.
//
//  The defaults keys keep the original's spelling ("Tab Stops", "Max Undos"),
//  so an old Quincy.ini carried over by hand still reads.  Colours are stored
//  as "r,g,b" for the same reason.
//

#import "Quincy.h"

NSNotificationName const QOptionsDidChangeNotification = @"QOptionsDidChange";

static NSString *const kBackground   = @"Background Color";
static NSString *const kText         = @"Text Color";
static NSString *const kComment      = @"Comment Color";
static NSString *const kKeyword      = @"Keyword Color";
static NSString *const kString       = @"String Color";
static NSString *const kTheme        = @"Theme";
static NSString *const kSyntax       = @"Syntax Colors";
static NSString *const kAutoindent   = @"Autoindent";
static NSString *const kTabChars     = @"Tab Characters";
static NSString *const kTabStops     = @"Tab Stops";
static NSString *const kMaxUndos     = @"Max Undos";
static NSString *const kLineNumbers  = @"Line Numbers";
static NSString *const kFontSize     = @"Font Size";
static NSString *const kFontBold     = @"Font Bold";
static NSString *const kDebugInfo    = @"Debug Info";
static NSString *const kRtti         = @"RTTI";
static NSString *const kExceptions   = @"Exceptions";
static NSString *const kOptimize     = @"Optimize";
static NSString *const kStrictAnsi   = @"Strict";
static NSString *const kC99          = @"C99";
static NSString *const kWarnings     = @"Warnings";
static NSString *const kDefines      = @"Defines";
static NSString *const kIncludes     = @"Includes";
static NSString *const kLibraries    = @"Libraries";
static NSString *const kToolchain    = @"Compiler Path";
static NSString *const kCompilerOpts = @"Compiler Options";
static NSString *const kLinkerOpts   = @"Linker Options";
static NSString *const kArgsMode     = @"Arguments Mode";
static NSString *const kArgs         = @"Arguments";
static NSString *const kWorkingDir   = @"Working Directory";
static NSString *const kIndentStyle  = @"Indent Style";
static NSString *const kAStyleOpts   = @"Beautifier Options";
static NSString *const kSidebar      = @"Show Sidebar";
static NSString *const kBottomPanel  = @"Show Bottom Panel";
static NSString *const kInspector    = @"Show Inspector";
static NSString *const kStatusBar    = @"Show Status Bar";

static NSColor *ColourFromDefaults(NSString *key, NSColor *fallback) {
    NSString *s = [NSUserDefaults.standardUserDefaults stringForKey:key];
    NSArray *parts = [s componentsSeparatedByString:@","];
    if (parts.count != 3) return fallback;
    return QRGB([parts[0] intValue], [parts[1] intValue], [parts[2] intValue]);
}

static void ColourToDefaults(NSString *key, NSColor *c) {
    NSColor *rgb = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    [NSUserDefaults.standardUserDefaults
        setObject:[NSString stringWithFormat:@"%d,%d,%d",
                   (int)lround(rgb.redComponent * 255),
                   (int)lround(rgb.greenComponent * 255),
                   (int)lround(rgb.blueComponent * 255)]
           forKey:key];
}

@implementation QOptions

+ (instancetype)shared {
    static QOptions *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[QOptions alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d registerDefaults:@{
        kSyntax: @YES, kAutoindent: @YES, kTabChars: @NO, kLineNumbers: @YES,
        kTabStops: @4, kMaxUndos: @1024, kFontSize: @13.0, kFontBold: @NO,
        kTheme: @(QThemeSystem),
        kDebugInfo: @YES, kRtti: @YES, kExceptions: @YES, kOptimize: @0,
        kStrictAnsi: @NO, kC99: @NO, kWarnings: @0,
        kDefines: @"", kIncludes: @"", kLibraries: @"",
        kToolchain: @"", kCompilerOpts: @"", kLinkerOpts: @"",
        kArgsMode: @(QArgumentsNone), kArgs: @"", kWorkingDir: @"",
        kIndentStyle: @(QIndentAllman),
        kAStyleOpts: @"--break-blocks --indent-namespaces --pad-oper",
        kSidebar: @YES, kBottomPanel: @NO, kInspector: @NO, kStatusBar: @YES,
    }];
    // The original's own palette, used as-is by the Classic theme and as the
    // starting point for a custom one.
    _customBackground = ColourFromDefaults(kBackground, QRGB(255, 255, 255));
    _customText       = ColourFromDefaults(kText,       QRGB(0, 0, 0));
    _customComment    = ColourFromDefaults(kComment,    QRGB(0, 128, 0));
    _customKeyword    = ColourFromDefaults(kKeyword,    QRGB(0, 0, 255));
    _customString     = ColourFromDefaults(kString,     QRGB(255, 0, 0));
    _themeKind        = [d integerForKey:kTheme];
    _syntaxEnabled    = [d boolForKey:kSyntax];
    _autoindent       = [d boolForKey:kAutoindent];
    _useTabCharacters = [d boolForKey:kTabChars];
    _showLineNumbers  = [d boolForKey:kLineNumbers];
    _tabStops         = [d integerForKey:kTabStops];
    _maxUndos         = [d integerForKey:kMaxUndos];
    _fontSize         = [d doubleForKey:kFontSize];
    _fontBold         = [d boolForKey:kFontBold];
    _debugInfo        = [d boolForKey:kDebugInfo];
    _rtti             = [d boolForKey:kRtti];
    _exceptions       = [d boolForKey:kExceptions];
    _optimize         = [d integerForKey:kOptimize];
    _strictAnsi       = [d boolForKey:kStrictAnsi];
    _c99              = [d boolForKey:kC99];
    _warnings         = [d integerForKey:kWarnings];
    _defines          = [d stringForKey:kDefines];
    _includes         = [d stringForKey:kIncludes];
    _libraries        = [d stringForKey:kLibraries];
    _toolchainPath    = [d stringForKey:kToolchain];
    _compilerOptions  = [d stringForKey:kCompilerOpts];
    _linkerOptions    = [d stringForKey:kLinkerOpts];
    _argumentsMode    = [d integerForKey:kArgsMode];
    _arguments        = [d stringForKey:kArgs];
    _workingDirectory = [d stringForKey:kWorkingDir];
    _indentStyle      = [d integerForKey:kIndentStyle];
    _customAStyleOptions = [d stringForKey:kAStyleOpts];
    _showSidebar      = [d boolForKey:kSidebar];
    _showBottomPanel  = [d boolForKey:kBottomPanel];
    _showInspector    = [d boolForKey:kInspector];
    _showStatusBar    = [d boolForKey:kStatusBar];
    return self;
}

#pragma mark - Colours

/// YES when the window is currently drawing in a dark appearance.
static BOOL DarkAppearance(void) {
    NSAppearance *a = NSApp.effectiveAppearance ?: NSAppearance.currentDrawingAppearance;
    NSAppearanceName name =
        [a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,
                                               NSAppearanceNameDarkAqua]];
    return [name isEqual:NSAppearanceNameDarkAqua];
}

- (NSColor *)backgroundColour {
    switch (_themeKind) {
        case QThemeClassic: return QRGB(255, 255, 255);
        case QThemeCustom:  return _customBackground;
        default: return NSColor.textBackgroundColor;
    }
}

- (NSColor *)textColour {
    switch (_themeKind) {
        case QThemeClassic: return QRGB(0, 0, 0);
        case QThemeCustom:  return _customText;
        default: return NSColor.textColor;
    }
}

// The system theme keeps the original's hues but lifts them for dark mode,
// where 0,0,255 on black is unreadable.
- (NSColor *)commentColour {
    switch (_themeKind) {
        case QThemeClassic: return QRGB(0, 128, 0);
        case QThemeCustom:  return _customComment;
        default: return DarkAppearance() ? QRGB(108, 196, 120)
                                         : QRGB(0, 128, 0);
    }
}

- (NSColor *)keywordColour {
    switch (_themeKind) {
        case QThemeClassic: return QRGB(0, 0, 255);
        case QThemeCustom:  return _customKeyword;
        default: return DarkAppearance() ? QRGB(167, 153, 255)
                                         : QRGB(0, 0, 255);
    }
}

- (NSColor *)stringColour {
    switch (_themeKind) {
        case QThemeClassic: return QRGB(255, 0, 0);
        case QThemeCustom:  return _customString;
        default: return DarkAppearance() ? QRGB(255, 130, 120)
                                         : QRGB(196, 26, 22);
    }
}

- (NSFont *)editorFont {
    NSFontWeight weight = _fontBold ? NSFontWeightBold : NSFontWeightRegular;
    // Courier New if the user still has it, otherwise the system's own
    // monospaced face, which is what a Mac editor should use.
    NSFont *f = [NSFont fontWithName:_fontBold ? @"Courier New Bold"
                                               : @"Courier New"
                               size:_fontSize];
    if (!f) f = [NSFont monospacedSystemFontOfSize:_fontSize weight:weight];
    return f;
}

#pragma mark - Toolchain

/// Falls back to the active developer directory, the way the original fell
/// back to the MinGW it shipped with.
- (NSString *)compilerPath {
    if (_toolchainPath.length) {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *candidate = [_toolchainPath stringByAppendingPathComponent:@"clang"];
        if ([fm isExecutableFileAtPath:candidate]) return candidate;
        if ([fm isExecutableFileAtPath:_toolchainPath]) return _toolchainPath;
    }
    return @"/usr/bin/clang";
}

/// The original's own AStyle command lines, with the indent width appended
/// exactly as it did ("%s --indent=%s=%d").
- (NSString *)astyleOptions {
    // The original's command lines, in AStyle 2.06 terms: --brackets=linux
    // and --brackets=break became --style=kr and --style=allman, --pad=oper
    // is --pad-oper, and GNU style already does what --indent-blocks did.
    NSString *base;
    switch (_indentStyle) {
        case QIndentKR:     base = @"--mode=c --style=kr --indent-switches"; break;
        case QIndentANSI:   base = @"--style=ansi"; break;
        case QIndentGNU:    base = @"--style=gnu"; break;
        case QIndentCustom: base = _customAStyleOptions ?: @""; break;
        default:
            base = @"--style=allman --break-blocks --indent-namespaces --pad-oper";
            break;
    }
    return [NSString stringWithFormat:@"%@ --indent=%@=%ld", base,
            _useTabCharacters ? @"tab" : @"spaces", (long)_tabStops];
}

#pragma mark - Persisting

- (void)restoreEditorDefaults {
    _themeKind        = QThemeSystem;
    _customBackground = QRGB(255, 255, 255);
    _customText       = QRGB(0, 0, 0);
    _customComment    = QRGB(0, 128, 0);
    _customKeyword    = QRGB(0, 0, 255);
    _customString     = QRGB(255, 0, 0);
    _syntaxEnabled    = YES;
    _autoindent       = YES;
    _showLineNumbers  = YES;
    _useTabCharacters = NO;
    _tabStops         = 4;
    _maxUndos         = 1024;
    _fontSize         = 13.0;
    _fontBold         = NO;
}

- (void)save {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    ColourToDefaults(kBackground, _customBackground);
    ColourToDefaults(kText, _customText);
    ColourToDefaults(kComment, _customComment);
    ColourToDefaults(kKeyword, _customKeyword);
    ColourToDefaults(kString, _customString);
    [d setInteger:_themeKind forKey:kTheme];
    [d setBool:_syntaxEnabled forKey:kSyntax];
    [d setBool:_autoindent forKey:kAutoindent];
    [d setBool:_useTabCharacters forKey:kTabChars];
    [d setBool:_showLineNumbers forKey:kLineNumbers];
    [d setInteger:_tabStops forKey:kTabStops];
    [d setInteger:_maxUndos forKey:kMaxUndos];
    [d setDouble:_fontSize forKey:kFontSize];
    [d setBool:_fontBold forKey:kFontBold];
    [d setBool:_debugInfo forKey:kDebugInfo];
    [d setBool:_rtti forKey:kRtti];
    [d setBool:_exceptions forKey:kExceptions];
    [d setInteger:_optimize forKey:kOptimize];
    [d setBool:_strictAnsi forKey:kStrictAnsi];
    [d setBool:_c99 forKey:kC99];
    [d setInteger:_warnings forKey:kWarnings];
    [d setObject:_defines ?: @"" forKey:kDefines];
    [d setObject:_includes ?: @"" forKey:kIncludes];
    [d setObject:_libraries ?: @"" forKey:kLibraries];
    [d setObject:_toolchainPath ?: @"" forKey:kToolchain];
    [d setObject:_compilerOptions ?: @"" forKey:kCompilerOpts];
    [d setObject:_linkerOptions ?: @"" forKey:kLinkerOpts];
    [d setInteger:_argumentsMode forKey:kArgsMode];
    [d setObject:_arguments ?: @"" forKey:kArgs];
    [d setObject:_workingDirectory ?: @"" forKey:kWorkingDir];
    [d setInteger:_indentStyle forKey:kIndentStyle];
    [d setObject:_customAStyleOptions ?: @"" forKey:kAStyleOpts];
    [d setBool:_showSidebar forKey:kSidebar];
    [d setBool:_showBottomPanel forKey:kBottomPanel];
    [d setBool:_showInspector forKey:kInspector];
    [d setBool:_showStatusBar forKey:kStatusBar];
    [NSNotificationCenter.defaultCenter
        postNotificationName:QOptionsDidChangeNotification object:self];
}

@end

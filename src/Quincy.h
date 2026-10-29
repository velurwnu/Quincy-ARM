//
//  Quincy.h — common declarations.
//
//  A rebuild of Al Stevens' Windows IDE Quincy 2005 as a native Mac app:
//  the same commands and workflow, laid out the way macOS lays out an
//  editor — source list on the left, document tabs, a build area below and
//  an inspector on the right — and built with clang and lldb.
//

#import <Cocoa/Cocoa.h>

/// sRGB colour from 0…255 components, the way the original's .ini stored them.
static inline NSColor *QRGB(int r, int g, int b) {
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0
                                blue:b / 255.0 alpha:1.0];
}

#pragma mark - Commands

/// Every command the original had.  The raw values are its resource ids, so
/// the tables still line up with reference/dumps.
typedef NS_ENUM(NSInteger, QCommand) {
    QCommandNone                = 0,

    QCommandFileNew             = 57600,
    QCommandFileOpen            = 57601,
    QCommandFileClose           = 57602,
    QCommandFileCloseAll        = 32813,
    QCommandFileCloseProject    = 32900,   // Mac addition: the project had no close
    QCommandFileSave            = 57603,
    QCommandFileSaveAll         = 32814,
    QCommandFileSaveAs          = 57604,
    QCommandFilePrint           = 57607,
    QCommandFilePrintSetup      = 57606,
    QCommandFilePrintPreview    = 57609,

    QCommandEditUndo            = 57643,
    QCommandEditRedo            = 57644,
    QCommandEditCut             = 57635,
    QCommandEditCopy            = 57634,
    QCommandEditPaste           = 57637,
    QCommandEditClear           = 57632,
    QCommandEditSelectAll       = 57642,
    QCommandEditFind            = 57636,
    QCommandEditReplace         = 57641,
    QCommandEditFindNext        = 32829,
    QCommandEditMatchBraces     = 32830,

    QCommandViewWatch           = 32799,
    QCommandViewConsole         = 32836,
    QCommandViewBuildLog        = 32786,
    QCommandViewSidebar         = 59392,
    QCommandViewStatusBar       = 59393,

    QCommandProjectInsertFiles  = 32774,
    QCommandProjectOpenHeaders  = 32852,
    QCommandProjectDeleteFiles  = 32775,
    QCommandProjectProperties   = 32816,
    QCommandBuildCompile        = 32776,
    QCommandBuildLink           = 32840,
    QCommandBuildBuild          = 32777,
    QCommandBuildRebuildAll     = 32805,
    QCommandBuildStop           = 32782,

    QCommandDebugRun            = 32778,
    QCommandDebugStart          = 32821,   // the original's "Start Debugging" (Ctrl+F9)
    QCommandDebugStep           = 32790,
    QCommandDebugStepOver       = 32796,
    QCommandDebugStepToCursor   = 32806,
    QCommandDebugStepOut        = 32815,
    QCommandDebugBreakpoint     = 32791,
    QCommandDebugClearBreaks    = 32792,
    QCommandDebugExamine        = 32798,

    QCommandToolsGrep           = 32818,
    QCommandToolsBeautifier     = 32838,
    QCommandToolsResourceEditor = 32817,
    QCommandToolsFluid          = 32848,
    QCommandToolsTerminal       = 32849,
    QCommandMacroRecord         = 32826,
    QCommandMacroPlayback       = 32827,
    QCommandMacroStop           = 32828,
    QCommandSettings            = 32784,

    QCommandWindowNewWindow     = 57648,
    QCommandWindowNextDoc       = 57688,
    QCommandWindowPreviousDoc   = 57689,

    QCommandHelpProgrammer      = 32844,
    QCommandHelpUserGuide       = 57670,
    QCommandHelpExamples        = 32811,
    QCommandHelpTutorial        = 32808,
    QCommandAbout               = 57664,
};

/// Menu title, as the original spelled it.
NSString *QCommandTitle(QCommand command);
/// Short label for toolbar buttons.
NSString *QCommandShortTitle(QCommand command);
/// One-line description, shown as the button's tooltip and in the status bar.
NSString *QCommandHelp(QCommand command);
/// SF Symbol name.
NSString *QCommandSymbol(QCommand command);
/// Mac keyboard shortcut; `key` is empty when the command has none.
void QCommandShortcut(QCommand command, NSString **key,
                      NSEventModifierFlags *modifiers);
/// The original's F-key accelerator (NSF5FunctionKey…), or 0.
unichar QCommandLegacyFunctionKey(QCommand command);
/// Commands the Windows original had that macOS cannot provide.
BOOL QCommandUnavailableOnMac(QCommand command);
/// The toolbar's default set, in the original's order; QCommandNone marks a
/// group break.
const QCommand *QToolbarCommands(NSUInteger *count);

#pragma mark - Classes

@class QDocumentModel, QEditorView, QProject, QWindowController, QSidebarController,
       QTabBarView, QBottomPanelController, QWatchController;

#pragma mark - Settings

/// Where the editor takes its colours from.
typedef NS_ENUM(NSInteger, QThemeKind) {
    QThemeSystem = 0,    // follows the system appearance
    QThemeClassic = 1,   // the original's black-on-white with green comments
    QThemeCustom = 2,
};

typedef NS_ENUM(NSInteger, QWarningLevel) {
    QWarningsDefault = 0, QWarningsAll = 1, QWarningsNone = 2,
};

typedef NS_ENUM(NSInteger, QArgumentsMode) {
    QArgumentsNone = 0, QArgumentsPrompt = 1, QArgumentsFixed = 2,
};

typedef NS_ENUM(NSInteger, QIndentStyle) {
    QIndentAllman = 0, QIndentKR = 1, QIndentANSI = 2, QIndentGNU = 3,
    QIndentCustom = 4,
};

@interface QOptions : NSObject

+ (instancetype)shared;

// Editor
@property (nonatomic, assign) NSInteger tabStops;
@property (nonatomic, assign) BOOL      useTabCharacters;
@property (nonatomic, assign) BOOL      autoindent;
@property (nonatomic, assign) NSInteger maxUndos;
@property (nonatomic, assign) BOOL      syntaxEnabled;
@property (nonatomic, assign) BOOL      showLineNumbers;
@property (nonatomic, assign) CGFloat   fontSize;
@property (nonatomic, assign) BOOL      fontBold;
@property (nonatomic, assign) QThemeKind themeKind;
@property (nonatomic, strong) NSColor  *customBackground;
@property (nonatomic, strong) NSColor  *customText;
@property (nonatomic, strong) NSColor  *customComment;
@property (nonatomic, strong) NSColor  *customKeyword;
@property (nonatomic, strong) NSColor  *customString;

// Build
@property (nonatomic, assign) BOOL      debugInfo;
@property (nonatomic, assign) BOOL      rtti;
@property (nonatomic, assign) BOOL      exceptions;
@property (nonatomic, assign) NSInteger optimize;       // 0…4, 4 = for space
@property (nonatomic, assign) BOOL      strictAnsi;
@property (nonatomic, assign) BOOL      c99;
@property (nonatomic, assign) QWarningLevel warnings;
@property (nonatomic, copy)   NSString *defines;        // ';'-separated
@property (nonatomic, copy)   NSString *includes;
@property (nonatomic, copy)   NSString *libraries;
@property (nonatomic, copy)   NSString *toolchainPath;
@property (nonatomic, copy)   NSString *compilerOptions;
@property (nonatomic, copy)   NSString *linkerOptions;

// Run
@property (nonatomic, assign) QArgumentsMode argumentsMode;
@property (nonatomic, copy)   NSString *arguments;
@property (nonatomic, copy)   NSString *workingDirectory;

// Beautifier
@property (nonatomic, assign) QIndentStyle indentStyle;
@property (nonatomic, copy)   NSString *customAStyleOptions;

// Window state
@property (nonatomic, assign) BOOL showSidebar;
@property (nonatomic, assign) BOOL showBottomPanel;
@property (nonatomic, assign) BOOL showInspector;
@property (nonatomic, assign) BOOL showStatusBar;

/// Resolved colours for the current appearance and theme.
- (NSColor *)backgroundColour;
- (NSColor *)textColour;
- (NSColor *)commentColour;
- (NSColor *)keywordColour;
- (NSColor *)stringColour;

- (NSFont *)editorFont;
/// Where clang lives, falling back to the Command Line Tools.
- (NSString *)compilerPath;
/// The beautifier command line, with the indent option appended.
- (NSString *)astyleOptions;

- (void)restoreEditorDefaults;
- (void)save;
@end

/// Posted when settings change so open editors can restyle themselves.
extern NSNotificationName const QOptionsDidChangeNotification;

#pragma mark - Documents

@interface QDocumentModel : NSObject
@property (nonatomic, strong) NSTextStorage *textStorage;
@property (nonatomic, copy)   NSURL        *url;         // nil until saved
@property (nonatomic, copy)   NSString     *displayName;
@property (nonatomic, assign) BOOL          dirty;
/// Zero-based lines carrying a breakpoint.
@property (nonatomic, strong) NSMutableIndexSet *breakpoints;
/// Zero-based line the debugger stopped on, or NSNotFound.
@property (nonatomic, assign) NSUInteger    currentLine;
/// Each document keeps its own undo history, as each MDI child did; every
/// view on it shares this one.
@property (nonatomic, readonly) NSUndoManager *undoManager;

/// Keeps breakpoints and the debugger arrow on their lines while the text
/// around them is edited.  Returns YES if any breakpoint moved or went away.
- (BOOL)adjustLinesForEditInRange:(NSRange)range replacement:(NSString *)text;

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error;
- (instancetype)initUntitledWithExtension:(NSString *)ext;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)isSourceFile;
- (BOOL)isProject;
/// SF Symbol for the sidebar and the tab.
- (NSString *)symbolName;
@end

#pragma mark - Syntax

@interface QSyntax : NSObject
+ (NSSet<NSString *> *)keywords;
- (instancetype)initWithTextStorage:(NSTextStorage *)storage;
/// Call after an edit; drops cached lexer state from that character on.
- (void)invalidateFromCharacterIndex:(NSUInteger)index;
/// Paint temporary attributes for the lines covering `range`.
- (void)applyToLayoutManager:(NSLayoutManager *)lm characterRange:(NSRange)range;
/// Colourise a short snippet in one go — the settings page's live sample.
+ (NSAttributedString *)colourise:(NSString *)source font:(NSFont *)font;
@end

/// Edit ▸ Match Braces, skipping comments and string literals.
NSUInteger QMatchingBraceIndex(NSString *text, NSUInteger caret);

#pragma mark - Editor

@interface QEditorView : NSView
@property (nonatomic, readonly) NSTextView   *textView;
@property (nonatomic, readonly) NSScrollView *scrollView;
@property (nonatomic, weak)     QDocumentModel *document;

- (instancetype)initWithDocument:(QDocumentModel *)doc;
- (void)goToLine:(NSInteger)line column:(NSInteger)column;
- (NSInteger)currentLine;      // 1-based
- (NSInteger)currentColumn;    // 1-based
- (void)refreshAppearance;
- (void)refreshGutter;
- (void)toggleBreakpointAtLine:(NSUInteger)line;
@end

#pragma mark - AStyle

#ifdef __cplusplus
extern "C" {
#endif
/// Runs AStyle 2.06 in-process; returns nil and fills `error` on failure.
NSString *QAStyleFormat(NSString *source, NSString *options, NSString **error);
NSString *QAStyleVersion(void);
#ifdef __cplusplus
}
#endif

#pragma mark - Build log

@interface QBuildMessage : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *path;    // nil when not a diagnostic
@property (nonatomic, assign) NSInteger line;
@property (nonatomic, assign) NSInteger column;
+ (instancetype)messageWithText:(NSString *)text;
@end

#pragma mark - Window

/// The one main window: toolbar, sidebar, document tabs, editor, build area
/// and the Watch inspector.
@interface QWindowController : NSWindowController

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<QDocumentModel *> *documents;
@property (nonatomic, strong)   QDocumentModel *activeDocument;
@property (nonatomic, readonly) QEditorView *activeEditor;
/// The editor for a document in the main window, whichever window is key.
- (QEditorView *)editorForDocument:(QDocumentModel *)doc;
/// Redraws the gutter of every view on a document (breakpoints, arrow).
- (void)refreshGuttersForDocument:(QDocumentModel *)doc;

- (void)presentDocument:(QDocumentModel *)doc;
- (QDocumentModel *)openURL:(NSURL *)url;
- (void)closeDocument:(QDocumentModel *)doc;

- (void)showStatus:(NSString *)message;
- (void)updateCaretPosition;
- (void)refreshChrome;

// Build log and console, shown in the bottom panel.
- (void)appendBuildMessage:(QBuildMessage *)message;
- (void)appendConsoleLine:(NSString *)line;
- (void)clearBuildLog;
- (void)revealPath:(NSString *)path line:(NSInteger)line column:(NSInteger)column;

@property (nonatomic, copy) NSArray<NSURL *> *recentFiles;
/// The open project, if any; at most one, as in the original.
@property (nonatomic, strong) QProject *project;
@end

@interface QWindowController (Commands)
- (void)performCommand:(QCommand)command;
- (BOOL)isCommandEnabled:(QCommand)command;
- (BOOL)isCommandOn:(QCommand)command;
@end

#pragma mark - Settings window

@interface QSettingsWindowController : NSWindowController
+ (instancetype)shared;
+ (void)showSettings;
@end

#pragma mark - Sheets

@interface QNewDocumentSheet : NSObject
/// Asks for a document type and returns its extension, or nil if cancelled.
+ (void)beginSheetForWindow:(NSWindow *)window
                 completion:(void (^)(NSString *extension))completion;
@end

@interface QBeautifierSheet : NSObject
+ (void)beginSheetForWindow:(NSWindow *)window;
@end

@interface QGrepSheet : NSObject
+ (void)beginSheetForWindow:(NSWindow *)window;
+ (void)runGrep:(NSString *)needle folder:(NSString *)folder
       patterns:(NSString *)patternList
      matchCase:(BOOL)matchCase matchWord:(BOOL)matchWord;
@property (class, nonatomic, readonly, getter=isSearching) BOOL searching;
+ (void)stop;
@end

@interface QAddWatchSheet : NSObject
+ (void)beginSheetForWindow:(NSWindow *)window
                 completion:(void (^)(NSString *expression))completion;
@end

@interface QProjectPropertiesSheet : NSObject
+ (void)beginSheetForWindow:(NSWindow *)window;
@end

/// Debug ▸ Examine: Expression, Value, and Change to assign a new value.
@interface QExamineSheet : NSObject
+ (void)beginSheetForWindow:(NSWindow *)window expression:(NSString *)expression;
@end

@interface QAboutPanel : NSObject
+ (void)show;
@end

#pragma mark - Application

@interface QAppDelegate : NSObject <NSApplicationDelegate>
- (void)buildMenuBar;
@end

#pragma mark - Small helpers

/// A label configured the way AppKit wants for form rows.
NSTextField *QLabel(NSString *text);
NSTextField *QSecondaryLabel(NSString *text);
/// A bordered text field for a settings form.
NSTextField *QTextField(NSString *placeholder);
/// Section header for a settings page.
NSTextField *QSectionHeader(NSString *text);

/// Target/action with a block, kept alive by the control it is attached to.
@interface QBlockTarget : NSObject
@property (nonatomic, copy) void (^block)(id sender);
+ (instancetype)targetWithBlock:(void (^)(id sender))block;
- (void)fire:(id)sender;
@end
void QSetBlockAction(NSControl *control, void (^block)(id sender));

#pragma mark - Projects

typedef NS_ENUM(NSInteger, QProjectType) {
    QProjectConsole = 0,
    QProjectLibrary = 1,     // ar rc → .a
    QProjectDylib   = 2,     // the original's DLL
    QProjectWin32GUI, QProjectWinBGIm, QProjectKoolplot, QProjectFLTK,  // Windows only
};

/// A .prj: a plain text file of `Key=Value` lines, one `File=` per member.
@interface QProject : NSObject
@property (nonatomic, copy)   NSURL *url;
@property (nonatomic, copy)   NSString *target;          // output name, no extension
@property (nonatomic, assign) QProjectType type;
@property (nonatomic, copy)   NSString *outputDirectory; // relative to the .prj
@property (nonatomic, copy)   NSString *includes;        // added to Settings ▸ Build
@property (nonatomic, copy)   NSString *defines;
@property (nonatomic, copy)   NSString *libraries;
@property (nonatomic, strong) NSMutableArray<NSString *> *files;   // relative paths

+ (instancetype)projectWithURL:(NSURL *)url error:(NSError **)error;
- (instancetype)initNewAtURL:(NSURL *)url;
- (BOOL)save:(NSError **)error;
- (NSString *)folder;
- (NSString *)absolutePath:(NSString *)relative;
- (NSString *)relativePath:(NSString *)absolute;
- (NSArray<NSString *> *)sourcePaths;     // absolute, compilable files
- (NSArray<NSString *> *)headerPaths;
- (NSArray<NSString *> *)archivePaths;    // .a members, linked in
- (NSString *)targetPath;
@end

#pragma mark - Building

/// Runs clang the way the original ran MinGW: one command at a time, every
/// command line and every message into the build log.
@interface QBuilder : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly, getter=isBusy) BOOL busy;
/// What would be built for the current window state: a project if one is
/// open, otherwise the active source file.  nil when there is nothing.
- (NSString *)targetPathForProject:(QProject *)project document:(QDocumentModel *)doc;
- (BOOL)isTargetOutOfDateForProject:(QProject *)project document:(QDocumentModel *)doc;
- (BOOL)targetHasDebugInfo:(NSString *)path;
- (void)compileDocument:(QDocumentModel *)doc;
- (void)buildProject:(QProject *)project document:(QDocumentModel *)doc
             rebuild:(BOOL)rebuild linkOnly:(BOOL)linkOnly
          completion:(void (^)(BOOL ok, NSString *target))completion;
- (void)stop;
@end

#pragma mark - Running

/// The program's own console window: a pty, 80×25, grey on black.
@interface QConsoleWindowController : NSWindowController
+ (instancetype)shared;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
/// Opens a pty and returns its slave path; the window shows its output.
- (NSString *)openTerminalForTitle:(NSString *)title;
/// Starts `path` directly on the console's pty.
- (BOOL)runProgram:(NSString *)path arguments:(NSArray<NSString *> *)args
         directory:(NSString *)dir;
/// Called by whoever owned the program once it has exited.
- (void)programExitedWithStatus:(int)status;
- (void)terminate;
/// What the console window shows, as plain text.
@property (nonatomic, readonly) NSString *screenText;
@end

#pragma mark - Debugging

@interface QDebugger : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly, getter=isStopped) BOOL stopped;
- (void)startProgram:(NSString *)path arguments:(NSArray<NSString *> *)args
           directory:(NSString *)dir;
/// `extra` are lldb commands sent before launch, e.g. a one-shot breakpoint.
- (void)startProgram:(NSString *)path arguments:(NSArray<NSString *> *)args
           directory:(NSString *)dir extra:(NSArray<NSString *> *)extra;
- (void)continueRunning;
- (void)step;
- (void)stepOver;
- (void)stepOut;
- (void)runToFile:(NSString *)file line:(NSInteger)line;
- (void)stop;
- (void)breakpointsChanged;
/// Examine: evaluates and reports `(value, error)` on the main queue.
- (void)evaluate:(NSString *)expression
      completion:(void (^)(NSString *value, NSString *error))completion;
- (void)refreshWatches;
/// A command typed into the LLDB Console.
- (void)sendUserCommand:(NSString *)text;
@end

//
//  QCommands.m — the command table.
//
//  Titles and the one-line descriptions are the original's, taken from its
//  string table (reference/dumps/menu_accel_strings_toolbar.txt), with the
//  Windows mnemonic ampersands dropped and "..." spelled as an ellipsis.
//  Keyboard equivalents are Mac ones; the original's F-keys still work
//  alongside them, which is what `legacy` is for.
//

#import "Quincy.h"

typedef struct {
    QCommand        command;
    const char     *title;
    const char     *shortTitle;
    const char     *help;
    const char     *symbol;
    const char     *key;        // "" for none
    unsigned        mods;       // NSEventModifierFlags
    unichar         legacy;     // original F-key, 0 for none
    BOOL            unavailable;
} QCommandInfo;

#define CMD   NSEventModifierFlagCommand
#define SHIFT NSEventModifierFlagShift
#define OPT   NSEventModifierFlagOption
#define CTRL  NSEventModifierFlagControl

static const QCommandInfo kCommands[] = {
// File
{QCommandFileNew,          "New…",                 "New",        "Create a new file or project",                           "doc.badge.plus",                   "n",  CMD,         0, NO},
{QCommandFileOpen,         "Open…",                "Open",       "Open an existing document",                              "folder",                           "o",  CMD,         0, NO},
{QCommandFileClose,        "Close",                "Close",      "Close the active document",                              "xmark",                            "w",  CMD,         0, NO},
{QCommandFileCloseAll,     "Close All",            "Close All",  "Close all document windows",                             "xmark.square",                     "w",  CMD|OPT,     0, NO},
{QCommandFileCloseProject, "Close Project",        "Close Project","Close the open project",                               "shippingbox",                      "",   0,           0, NO},
{QCommandFileSave,         "Save",                 "Save",       "Save the active document",                               "square.and.arrow.down",            "s",  CMD,         0, NO},
{QCommandFileSaveAll,      "Save All",             "Save All",   "Save all active documents",                              "square.and.arrow.down.on.square",  "s",  CMD|OPT,     0, NO},
{QCommandFileSaveAs,       "Save As…",             "Save As",    "Save the active document with a new name",               "doc.badge.ellipsis",               "s",  CMD|SHIFT,   0, NO},
{QCommandFilePrint,        "Print…",               "Print",      "Print the active document",                              "printer",                          "p",  CMD,         0, NO},
{QCommandFilePrintSetup,   "Page Setup…",          "Page Setup", "Change the printer and printing options",                "printer.dotmatrix",                "p",  CMD|SHIFT,   0, NO},
{QCommandFilePrintPreview, "Print Preview",        "Preview",    "Display full pages",                                     "doc.richtext",                     "",   0,           0, NO},
// Edit
{QCommandEditUndo,         "Undo",                 "Undo",       "Undo the last action",                                   "arrow.uturn.backward",             "z",  CMD,         0, NO},
{QCommandEditRedo,         "Redo",                 "Redo",       "Redo the previously undone action",                      "arrow.uturn.forward",              "z",  CMD|SHIFT,   0, NO},
{QCommandEditCut,          "Cut",                  "Cut",        "Cut the selection and put it on the Clipboard",          "scissors",                         "x",  CMD,         0, NO},
{QCommandEditCopy,         "Copy",                 "Copy",       "Copy the selection to the Clipboard",                    "doc.on.doc",                       "c",  CMD,         0, NO},
{QCommandEditPaste,        "Paste",                "Paste",      "Insert Clipboard contents",                              "doc.on.clipboard",                 "v",  CMD,         0, NO},
{QCommandEditClear,        "Delete",               "Erase",      "Erase the selection",                                    "delete.left",                      "",   0,           0, NO},
{QCommandEditSelectAll,    "Select All",           "Select All", "Select the entire document",                             "checkmark.rectangle",              "a",  CMD,         0, NO},
{QCommandEditFind,         "Find…",                "Find",       "Find the specified text",                                "magnifyingglass",                  "f",  CMD,         0, NO},
{QCommandEditReplace,      "Find and Replace…",    "Replace",    "Replace specific text with different text",              "text.magnifyingglass",             "f",  CMD|OPT,     0, NO},
{QCommandEditFindNext,     "Find Next",            "Find Next",  "Find next matching string",                              "magnifyingglass.circle",           "g",  CMD,         NSF3FunctionKey, NO},
{QCommandEditMatchBraces,  "Balance Braces",       "Match Braces","Find matching brace character in source code",          "curlybraces",                      "b",  CMD|CTRL,    0, NO},
// View
{QCommandViewSidebar,      "Hide Sidebar",         "Sidebar",    "Show or hide the sidebar",                               "sidebar.left",                     "s",  CMD|CTRL,    0, NO},
{QCommandViewBuildLog,     "Build Log",            "Errors",    "Display the latest compiler error and warning message log","exclamationmark.bubble",           "9",  CMD,         0, NO},
{QCommandViewConsole,      "Debugger Console",     "Console",    "View the lldb console window",                           "terminal",                         "c",  CMD|SHIFT,   0, NO},
{QCommandViewWatch,        "Watch",                "Watch",      "Watch variables while the program runs",                 "eye",                              "0",  CMD|OPT,     0, NO},
{QCommandViewStatusBar,    "Hide Status Bar",      "Status Bar", "Show or hide the status bar",                            "rectangle.bottomthird.inset.filled","", 0,           0, NO},
// Project
{QCommandProjectInsertFiles,"Add Files…",          "Insert",     "Insert a file into the project",                         "plus.rectangle.on.folder",         "",   0,           0, NO},
{QCommandProjectOpenHeaders,"Open Headers",        "Headers",    "Open project header files",                              "chevron.left.forwardslash.chevron.right","",0,       0, NO},
{QCommandProjectDeleteFiles,"Remove Files",        "Delete",     "Delete the selected file from the project",               "trash",                            "",   0,           0, NO},
{QCommandProjectProperties,"Project Properties…",  "Properties", "View and modify the project's properties",               "info.circle",                      "i",  CMD,         0, NO},
{QCommandBuildCompile,     "Compile",              "Compile",    "Compile the source code file into an object file",       "hammer",                           "b",  CMD|SHIFT,   NSF5FunctionKey, NO},
{QCommandBuildLink,        "Link",                 "Link",       "Combine object files and libraries to produce the target","link",                             "l",  CMD|CTRL,    0, NO},
{QCommandBuildBuild,       "Build",                "Build",      "Build an executable file",                               "hammer.fill",                      "b",  CMD,         NSF6FunctionKey, NO},
{QCommandBuildRebuildAll,  "Rebuild All",          "Build All",  "Recompile and link everything in the project",           "arrow.triangle.2.circlepath",      "b",  CMD|OPT,     0, NO},
{QCommandBuildStop,        "Stop",                 "Stop",       "Stop the running program",                               "stop.fill",                        ".",  CMD,         0, NO},
// Debug
{QCommandDebugRun,         "Run",                  "Run",        "Execute the program",                                    "play.fill",                        "r",  CMD,         NSF9FunctionKey, NO},
{QCommandDebugStart,       "Start Debugging",      "Debug",      "Start debugging the program",                            "ladybug",                          "y",  CMD,         0, NO},
{QCommandDebugStep,        "Step Into",            "Step",       "Step through the program",                               "arrow.down.to.line",               "",   0,           NSF7FunctionKey, NO},
{QCommandDebugStepOver,    "Step Over",            "Step Over",  "Step over the function",                                 "arrow.right.to.line",              "",   0,           NSF8FunctionKey, NO},
{QCommandDebugStepToCursor,"Step to Cursor",       "Step to Cursor","Step to the line where the cursor is positioned",      "arrow.down.right.circle",          "",   0,           NSF10FunctionKey, NO},
{QCommandDebugStepOut,     "Step Out of Function", "Step Out",   "Step out of the current function",                       "arrow.up.to.line",                 "",   0,           0, NO},
{QCommandDebugBreakpoint,  "Toggle Breakpoint",    "Breakpoint", "Set and clear a breakpoint",                             "hand.raised.fill",                 "\\", CMD,         NSF2FunctionKey, NO},
{QCommandDebugClearBreaks, "Clear Breakpoints",    "Clear Breakpoints","Clear all breakpoints",                            "hand.raised.slash",                "\\", CMD|OPT,     0, NO},
{QCommandDebugExamine,     "Examine…",             "Examine",    "Examine and modify variables",                           "viewfinder",                       "e",  CMD|CTRL,    0, NO},
// Tools
{QCommandToolsGrep,        "Find in Files…",       "Grep",       "Text search utility",                                    "doc.text.magnifyingglass",         "f",  CMD|SHIFT,   0, NO},
{QCommandToolsBeautifier,  "Code Beautifier…",     "Beautifier", "Code beautifier utility",                                "wand.and.stars",                   "",   0,           0, NO},
{QCommandToolsResourceEditor,"Resource Editor",    "Resource Editor","Windows resource file editor",                       "photo.on.rectangle",               "",   0,           0, YES},
{QCommandToolsFluid,       "FLUID Screen Designer","FLUID",      "Open the FLTK GUI builder",                              "rectangle.3.group",                "",   0,           0, YES},
{QCommandToolsTerminal,    "Open in Terminal",     "Terminal",   "Open Terminal in the project folder",                    "terminal.fill",                    "",   0,           0, NO},
{QCommandMacroRecord,      "Record",               "Record",     "Record a macro",                                         "record.circle",                    "r",  CMD|OPT,     0, NO},
{QCommandMacroPlayback,    "Playback",             "Playback",   "Playback a macro",                                       "play.rectangle",                   "m",  CMD|OPT,     0, NO},
{QCommandMacroStop,        "Stop Recording",       "Stop",       "Stop recording the macro",                               "stop.circle",                      "",   0,           0, NO},
{QCommandSettings,         "Settings…",            "Settings",   "Set Quincy options",                                     "gearshape",                        ",",  CMD,         0, NO},
// Window
{QCommandWindowNewWindow,  "New Window",           "New Window", "Open another window for the active document",            "macwindow.badge.plus",             "",   0,           0, NO},
{QCommandWindowNextDoc,    "Next Document",        "Next",       "Switch to the next document",                            "chevron.right",                    "]",  CMD|SHIFT,   0, NO},
{QCommandWindowPreviousDoc,"Previous Document",    "Previous",   "Switch back to the previous document",                   "chevron.left",                     "[",  CMD|SHIFT,   0, NO},
// Help
{QCommandHelpProgrammer,   "Programmer's Help",    "Info",       "C and C++ language and libraries info",                  "book",                             "",   0,           0, NO},
{QCommandHelpUserGuide,    "Quincy 2005 User's Guide","Help",    "IDE help",                                               "questionmark.circle",              "?",  CMD,         NSF1FunctionKey, NO},
{QCommandHelpExamples,     "Example Programs…",    "Examples",   "View the example programs",                              "lightbulb",                        "",   0,           NSF4FunctionKey, NO},
{QCommandHelpTutorial,     "Tutorial",             "Tutorial",   "Work through the Quincy tutorial",                       "graduationcap",                    "",   0,           0, NO},
{QCommandAbout,            "About Quincy 2005",    "About",      "Display program information, version number and copyright","info.bubble",                    "",   0,           0, NO},
};

static const QCommandInfo *Lookup(QCommand command) {
    static CFMutableDictionaryRef index;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        index = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        for (size_t i = 0; i < sizeof(kCommands) / sizeof(*kCommands); i++)
            CFDictionarySetValue(index, (const void *)(intptr_t)kCommands[i].command,
                                 &kCommands[i]);
    });
    return CFDictionaryGetValue(index, (const void *)(intptr_t)command);
}

NSString *QCommandTitle(QCommand command) {
    const QCommandInfo *i = Lookup(command);
    return i ? @(i->title) : @"";
}

NSString *QCommandShortTitle(QCommand command) {
    const QCommandInfo *i = Lookup(command);
    return i ? @(i->shortTitle) : @"";
}

NSString *QCommandHelp(QCommand command) {
    const QCommandInfo *i = Lookup(command);
    if (!i) return @"";
    if (i->unavailable)
        return [@(i->help) stringByAppendingString:@" — not available on macOS"];
    return @(i->help);
}

NSString *QCommandSymbol(QCommand command) {
    const QCommandInfo *i = Lookup(command);
    return i ? @(i->symbol) : @"questionmark";
}

void QCommandShortcut(QCommand command, NSString **key,
                      NSEventModifierFlags *modifiers) {
    const QCommandInfo *i = Lookup(command);
    if (key) *key = i ? @(i->key) : @"";
    if (modifiers) *modifiers = i ? i->mods : 0;
}

unichar QCommandLegacyFunctionKey(QCommand command) {
    const QCommandInfo *i = Lookup(command);
    return i ? i->legacy : 0;
}

BOOL QCommandUnavailableOnMac(QCommand command) {
    const QCommandInfo *i = Lookup(command);
    return i ? i->unavailable : NO;
}

/// The toolbar: only what a build-run-debug cycle needs; every other
/// original button is in the customisation palette.  QCommandNone is a gap.
const QCommand *QToolbarCommands(NSUInteger *count) {
    static const QCommand items[] = {
        QCommandFileNew, QCommandFileOpen, QCommandFileSave,
        QCommandNone,
        QCommandBuildBuild,
        QCommandNone,
        QCommandDebugRun, QCommandDebugStart, QCommandBuildStop,
        QCommandNone,
        QCommandDebugStepOver, QCommandDebugStep, QCommandDebugStepOut,
        QCommandNone,
        QCommandDebugBreakpoint, QCommandViewWatch,
    };
    if (count) *count = sizeof(items) / sizeof(*items);
    return items;
}

//
//  QWindowController.m — the one main window.
//
//  Layout, left to right: a source-list sidebar, the editor with its document
//  tabs above and the build area below, and the Watch inspector.  The toolbar
//  carries the original's buttons in the original order; everything is a
//  system control in its system appearance.
//

#import "QChrome.h"

@implementation QBuildMessage
+ (instancetype)messageWithText:(NSString *)text {
    QBuildMessage *m = [[QBuildMessage alloc] init];
    m.text = text;
    m.line = m.column = 0;
    return m;
}
@end

#pragma mark - Sidebar

/// One row of the source list.  Groups are the headers; a leaf carries either
/// an open document or a path from the Recent list.
@interface QSidebarItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, strong) QDocumentModel *document;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, strong) NSMutableArray<QSidebarItem *> *children;
@end
@implementation QSidebarItem @end

@interface QSidebarController : NSViewController <NSOutlineViewDataSource,
                                                 NSOutlineViewDelegate>
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong) NSMutableArray<QSidebarItem *> *groups;
@property (nonatomic, copy) void (^onPick)(QSidebarItem *item);
@property (nonatomic, strong) QProject *project;
- (void)reloadWithDocuments:(NSArray<QDocumentModel *> *)documents
                     recent:(NSArray<NSURL *> *)recent
                     active:(QDocumentModel *)active;
- (NSString *)selectedProjectFile;
@end

@implementation QSidebarController {
    QDocumentModel *_active;
}

- (void)loadView {
    _groups = [NSMutableArray array];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 240, 480)];
    _outline = [[NSOutlineView alloc] initWithFrame:scroll.bounds];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_outline addTableColumn:col];
    _outline.outlineTableColumn = col;
    _outline.headerView = nil;
    _outline.dataSource = self;
    _outline.delegate = self;
    _outline.style = NSTableViewStyleSourceList;
    _outline.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    _outline.floatsGroupRows = NO;
    _outline.indentationPerLevel = 12;
    _outline.target = self;
    _outline.action = @selector(rowClicked:);
    scroll.documentView = _outline;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view = scroll;
}

- (void)reloadWithDocuments:(NSArray<QDocumentModel *> *)documents
                     recent:(NSArray<NSURL *> *)recent
                     active:(QDocumentModel *)active {
    _active = active;
    [_groups removeAllObjects];

    if (_project) {
        QSidebarItem *proj = [[QSidebarItem alloc] init];
        proj.title = [_project.url.lastPathComponent uppercaseString];
        proj.children = [NSMutableArray array];
        for (NSString *f in _project.files) {
            QSidebarItem *item = [[QSidebarItem alloc] init];
            item.title = f;
            NSString *ext = f.pathExtension.lowercaseString;
            item.symbol = [@[@"h", @"hpp"] containsObject:ext] ? @"doc.text"
                        : [@[@"a", @"o", @"dylib"] containsObject:ext] ? @"books.vertical"
                        : @"chevron.left.forwardslash.chevron.right";
            item.url = [NSURL fileURLWithPath:[_project absolutePath:f]];
            [proj.children addObject:item];
        }
        [_groups addObject:proj];
    }

    QSidebarItem *open = [[QSidebarItem alloc] init];
    open.title = @"Open Files";
    open.children = [NSMutableArray array];
    for (QDocumentModel *d in documents) {
        QSidebarItem *item = [[QSidebarItem alloc] init];
        // The tab's dot and the close button already say it is edited.
        item.title = d.displayName;
        item.symbol = [d symbolName];
        item.document = d;
        [open.children addObject:item];
    }
    [_groups addObject:open];

    if (recent.count) {
        QSidebarItem *group = [[QSidebarItem alloc] init];
        group.title = @"Recent Files";
        group.children = [NSMutableArray array];
        for (NSURL *url in recent) {
            QSidebarItem *item = [[QSidebarItem alloc] init];
            item.title = url.lastPathComponent;
            item.symbol = @"clock";
            item.url = url;
            [group.children addObject:item];
        }
        [_groups addObject:group];
    }

    [_outline reloadData];
    for (QSidebarItem *g in _groups) [_outline expandItem:g];

    NSInteger row = -1;
    for (NSInteger i = 0; i < _outline.numberOfRows; i++) {
        QSidebarItem *item = [_outline itemAtRow:i];
        if (item.document && item.document == active) { row = i; break; }
    }
    if (row >= 0)
        [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
              byExtendingSelection:NO];
}

- (NSString *)selectedProjectFile {
    NSInteger row = _outline.selectedRow;
    if (row < 0 || !_project) return nil;
    QSidebarItem *item = [_outline itemAtRow:row];
    QSidebarItem *parent = [_outline parentForItem:item];
    if (!parent || parent != _groups.firstObject || !item.url) return nil;
    return [_project relativePath:item.url.path];
}

- (void)rowClicked:(id)sender {
    NSInteger row = _outline.clickedRow;
    if (row < 0) return;
    QSidebarItem *item = [_outline itemAtRow:row];
    if (item.children) return;
    if (self.onPick) self.onPick(item);
}

- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item {
    if (!item) return (NSInteger)_groups.count;
    return (NSInteger)[(QSidebarItem *)item children].count;
}

- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item {
    if (!item) return _groups[index];
    return [(QSidebarItem *)item children][index];
}

- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item {
    return [(QSidebarItem *)item children] != nil;
}

- (BOOL)outlineView:(NSOutlineView *)view isGroupItem:(id)item {
    return [(QSidebarItem *)item children] != nil;
}

- (BOOL)outlineView:(NSOutlineView *)view shouldSelectItem:(id)item {
    return [(QSidebarItem *)item children] == nil;
}

- (NSView *)outlineView:(NSOutlineView *)view
     viewForTableColumn:(NSTableColumn *)column item:(id)item {
    QSidebarItem *it = item;
    NSTableCellView *cell = [view makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
        NSImageView *image = [[NSImageView alloc] init];
        NSTextField *text = [NSTextField labelWithString:@""];
        text.lineBreakMode = NSLineBreakByTruncatingMiddle;
        image.translatesAutoresizingMaskIntoConstraints = NO;
        text.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:image];
        [cell addSubview:text];
        cell.imageView = image;
        cell.textField = text;
        cell.identifier = @"cell";
        [NSLayoutConstraint activateConstraints:@[
            [image.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor],
            [image.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [image.widthAnchor constraintEqualToConstant:16],
            [text.leadingAnchor constraintEqualToAnchor:image.trailingAnchor constant:6],
            [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    cell.textField.stringValue = it.title ?: @"";
    if (it.children) {
        cell.imageView.image = nil;
        cell.imageView.hidden = YES;
        cell.textField.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize
                                                weight:NSFontWeightSemibold];
        cell.textField.textColor = NSColor.secondaryLabelColor;
    } else {
        cell.imageView.hidden = NO;
        cell.imageView.image = [NSImage imageWithSystemSymbolName:it.symbol ?: @"doc"
                                         accessibilityDescription:nil];
        cell.imageView.contentTintColor = NSColor.secondaryLabelColor;
        cell.textField.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
        cell.textField.textColor = NSColor.labelColor;
    }
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note {
    NSInteger row = _outline.selectedRow;
    if (row < 0) return;
    QSidebarItem *item = [_outline itemAtRow:row];
    if (item.children || (item.document && item.document == _active)) return;
    if (self.onPick) self.onPick(item);
}

@end

#pragma mark - Window controller

#pragma mark - Second window

/// A window holding one more view on a document (Window ▸ New Window).
@interface QSecondWindow : NSWindow
@property (nonatomic, strong) QEditorView *editor;
@property (nonatomic, assign) NSUInteger number;
@end

@implementation QSecondWindow
@end

@interface QWindowController () <NSToolbarDelegate, NSTableViewDataSource, NSWindowDelegate,
                                 NSTableViewDelegate>
@end

@implementation QWindowController {
    NSMutableArray<QDocumentModel *>   *_documents;
    NSMapTable<QDocumentModel *, QEditorView *> *_editors;

    QSidebarController *_sidebar;
    NSSplitViewController *_outerSplit;
    NSSplitViewController *_centreSplit;
    NSSplitViewItem    *_sidebarItem;
    NSSplitViewItem    *_inspectorItem;
    NSSplitViewItem    *_bottomItem;
    NSView             *_centre;
    NSView             *_editorHost;
    QTabBarView        *_tabs;
    QStatusBarView     *_status;

    NSView             *_bottomPanel;
    NSSegmentedControl *_bottomPicker;
    NSTableView        *_buildTable;
    NSTextView         *_consoleText;
    NSScrollView       *_buildScroll;
    NSScrollView       *_consoleScroll;
    NSTextField        *_consoleInput;
    NSMutableArray<QBuildMessage *> *_buildMessages;

    NSView             *_inspector;
    NSTableView        *_watchTable;
    NSMutableArray<NSMutableDictionary *> *_watches;
    NSMutableArray<QSecondWindow *> *_secondWindows;

    NSToolbar          *_toolbar;
    NSString           *_statusMessage;
}

+ (instancetype)shared {
    static QWindowController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[QWindowController alloc] init]; });
    return shared;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1180, 760)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered defer:NO];
    window.title = @"Quincy 2005";
    window.minSize = NSMakeSize(760, 480);
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
    window.tabbingMode = NSWindowTabbingModeDisallowed;

    if (!(self = [super initWithWindow:window])) return nil;
    _documents = [NSMutableArray array];
    _editors = [NSMapTable strongToStrongObjectsMapTable];
    _buildMessages = [NSMutableArray array];
    _watches = [NSMutableArray array];
    _secondWindows = [NSMutableArray array];
    _recentFiles = @[];
    _statusMessage = @"Ready";

    [self buildChrome];
    [self buildToolbar];
    self.window.delegate = (id)self;
    [self.window setFrameAutosaveName:@"QuincyMainWindow"];
    [self refreshChrome];
    return self;
}

#pragma mark - Chrome

- (void)buildChrome {
    _sidebar = [[QSidebarController alloc] init];
    __weak typeof(self) weakSelf = self;
    _sidebar.onPick = ^(QSidebarItem *item) {
        if (item.document) [weakSelf presentDocument:item.document];
        else if (item.url) [weakSelf openURL:item.url];
    };

    _centre = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 700)];

    _tabs = [[QTabBarView alloc] initWithFrame:NSMakeRect(0, 0, 800, 30)];
    _tabs.onSelect = ^(NSInteger index) {
        typeof(self) s = weakSelf;
        if (index < (NSInteger)s.documents.count)
            [s presentDocument:s.documents[index]];
    };
    _tabs.onClose = ^(NSInteger index) {
        typeof(self) s = weakSelf;
        if (index < (NSInteger)s.documents.count)
            [s closeDocument:s.documents[index]];
    };

    _editorHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
    [self buildBottomPanel];

    // Editor above, build area below: a split view controller, so the build
    // area collapses and remembers its height the system way.
    _centreSplit = [[NSSplitViewController alloc] init];
    _centreSplit.splitView.vertical = NO;
    _centreSplit.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _centreSplit.splitView.autosaveName = @"QuincyCentreSplit";
    NSViewController *editorVC = [[NSViewController alloc] init];
    editorVC.view = _editorHost;
    NSSplitViewItem *editorItem = [NSSplitViewItem splitViewItemWithViewController:editorVC];
    editorItem.minimumThickness = 120;
    editorItem.holdingPriority = NSLayoutPriorityDefaultLow;
    NSViewController *bottomVC = [[NSViewController alloc] init];
    bottomVC.view = _bottomPanel;
    _bottomItem = [NSSplitViewItem splitViewItemWithViewController:bottomVC];
    _bottomItem.canCollapse = YES;
    _bottomItem.minimumThickness = 100;
    _bottomItem.holdingPriority = NSLayoutPriorityDefaultLow + 10;
    [_centreSplit addSplitViewItem:editorItem];
    [_centreSplit addSplitViewItem:_bottomItem];
    NSView *centreSplitView = _centreSplit.view;

    _status = [[QStatusBarView alloc] initWithFrame:NSMakeRect(0, 0, 800, 24)];

    for (NSView *v in @[_tabs, centreSplitView, _status]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [_centre addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_tabs.topAnchor constraintEqualToAnchor:_centre.topAnchor],
        [_tabs.leadingAnchor constraintEqualToAnchor:_centre.leadingAnchor],
        [_tabs.trailingAnchor constraintEqualToAnchor:_centre.trailingAnchor],
        [_tabs.heightAnchor constraintEqualToConstant:[_tabs intrinsicHeight]],
        [centreSplitView.topAnchor constraintEqualToAnchor:_tabs.bottomAnchor],
        [centreSplitView.leadingAnchor constraintEqualToAnchor:_centre.leadingAnchor],
        [centreSplitView.trailingAnchor constraintEqualToAnchor:_centre.trailingAnchor],
        [_status.topAnchor constraintEqualToAnchor:centreSplitView.bottomAnchor],
        [_status.leadingAnchor constraintEqualToAnchor:_centre.leadingAnchor],
        [_status.trailingAnchor constraintEqualToAnchor:_centre.trailingAnchor],
        [_status.bottomAnchor constraintEqualToAnchor:_centre.bottomAnchor],
    ]];

    [self buildInspector];

    // Sidebar, content, inspector: the standard three-part Mac window.
    _outerSplit = [[NSSplitViewController alloc] init];
    _outerSplit.splitView.autosaveName = @"QuincyOuterSplit";
    _sidebarItem = [NSSplitViewItem sidebarWithViewController:_sidebar];
    _sidebarItem.minimumThickness = 180;
    _sidebarItem.maximumThickness = 400;
    _sidebarItem.preferredThicknessFraction = 0.2;
    NSViewController *centreVC = [[NSViewController alloc] init];
    centreVC.view = _centre;
    [centreVC addChildViewController:_centreSplit];
    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:centreVC];
    contentItem.minimumThickness = 400;
    NSViewController *inspectorVC = [[NSViewController alloc] init];
    inspectorVC.view = _inspector;
    if (@available(macOS 14.0, *))
        _inspectorItem = [NSSplitViewItem inspectorWithViewController:inspectorVC];
    else
        _inspectorItem = [NSSplitViewItem splitViewItemWithViewController:inspectorVC];
    _inspectorItem.canCollapse = YES;
    _inspectorItem.minimumThickness = 220;
    _inspectorItem.maximumThickness = 420;
    [_outerSplit addSplitViewItem:_sidebarItem];
    [_outerSplit addSplitViewItem:contentItem];
    [_outerSplit addSplitViewItem:_inspectorItem];

    NSRect frame = self.window.frame;
    self.window.contentViewController = _outerSplit;
    [self.window setFrame:frame display:NO];
    // Since macOS 26 split views run under the toolbar glass; the tab strip
    // must start below it.
    NSLayoutGuide *content = (NSLayoutGuide *)self.window.contentLayoutGuide;
    for (NSLayoutConstraint *c in _centre.constraints)
        if (c.firstItem == _tabs && c.firstAttribute == NSLayoutAttributeTop)
            c.active = NO;
    [_tabs.topAnchor constraintEqualToAnchor:content.topAnchor].active = YES;

    QOptions *opt = [QOptions shared];
    _sidebarItem.collapsed = !opt.showSidebar;
    _bottomItem.collapsed = !opt.showBottomPanel;
    _inspectorItem.collapsed = !opt.showInspector;
    _status.collapsed = !opt.showStatusBar;
}

- (void)buildBottomPanel {
    _bottomPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 200)];

    _bottomPicker = [NSSegmentedControl segmentedControlWithLabels:@[@"Build", @"Console"]
        trackingMode:NSSegmentSwitchTrackingSelectOne
              target:self action:@selector(bottomTabChanged:)];
    _bottomPicker.selectedSegment = 0;
    _bottomPicker.controlSize = NSControlSizeSmall;
    _bottomPicker.segmentStyle = NSSegmentStyleTexturedRounded;

    NSButton *clear = [NSButton buttonWithImage:
        [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:@"Clear"]
                                         target:self action:@selector(clearBottom:)];
    clear.bezelStyle = NSBezelStyleTexturedRounded;
    clear.controlSize = NSControlSizeSmall;
    clear.toolTip = @"Clear";

    NSButton *hide = [NSButton buttonWithImage:
        [NSImage imageWithSystemSymbolName:@"chevron.down"
                 accessibilityDescription:@"Hide"]
                                        target:self action:@selector(hideBottom:)];
    hide.bezelStyle = NSBezelStyleTexturedRounded;
    hide.controlSize = NSControlSizeSmall;
    hide.toolTip = @"Hide the build area";

    // Build log: one row per compiler message, double-click jumps to the line.
    _buildTable = [[NSTableView alloc] init];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"text"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_buildTable addTableColumn:col];
    _buildTable.headerView = nil;
    _buildTable.dataSource = self;
    _buildTable.delegate = self;
    _buildTable.rowHeight = 17;
    _buildTable.style = NSTableViewStylePlain;
    _buildTable.intercellSpacing = NSMakeSize(0, 0);
    _buildTable.target = self;
    _buildTable.doubleAction = @selector(buildRowDoubleClicked:);
    _buildScroll = [[NSScrollView alloc] init];
    _buildScroll.documentView = _buildTable;
    _buildScroll.hasVerticalScroller = YES;
    _buildScroll.drawsBackground = NO;

    // The lldb conversation, verbatim, as the original's gdb console showed it.
    _consoleText = [[NSTextView alloc] init];
    _consoleText.editable = NO;
    _consoleText.richText = NO;
    _consoleText.drawsBackground = NO;
    _consoleText.textContainerInset = NSMakeSize(6, 4);
    _consoleText.font = [NSFont monospacedSystemFontOfSize:11
                                                    weight:NSFontWeightRegular];
    _consoleScroll = [[NSScrollView alloc] init];
    _consoleScroll.documentView = _consoleText;
    _consoleScroll.hasVerticalScroller = YES;
    _consoleScroll.drawsBackground = NO;
    _consoleScroll.hidden = YES;

    // The original's GDB Console took commands too.
    _consoleInput = [NSTextField textFieldWithString:@""];
    _consoleInput.placeholderString = @"lldb command";
    _consoleInput.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _consoleInput.bezelStyle = NSTextFieldRoundedBezel;
    _consoleInput.target = self;
    _consoleInput.action = @selector(consoleCommand:);
    _consoleInput.hidden = YES;
    _consoleInput.enabled = NO;

    NSBox *divider = [[NSBox alloc] init];
    divider.boxType = NSBoxSeparator;

    NSArray *views = @[_bottomPicker, clear, hide, divider, _buildScroll, _consoleScroll,
                       _consoleInput];
    for (NSView *v in views) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [_bottomPanel addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_bottomPicker.leadingAnchor constraintEqualToAnchor:_bottomPanel.leadingAnchor constant:10],
        [_bottomPicker.topAnchor constraintEqualToAnchor:_bottomPanel.topAnchor constant:6],
        [clear.leadingAnchor constraintEqualToAnchor:_bottomPicker.trailingAnchor constant:8],
        [clear.centerYAnchor constraintEqualToAnchor:_bottomPicker.centerYAnchor],
        [hide.trailingAnchor constraintEqualToAnchor:_bottomPanel.trailingAnchor constant:-10],
        [hide.centerYAnchor constraintEqualToAnchor:_bottomPicker.centerYAnchor],
        [divider.topAnchor constraintEqualToAnchor:_bottomPicker.bottomAnchor constant:6],
        [divider.leadingAnchor constraintEqualToAnchor:_bottomPanel.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:_bottomPanel.trailingAnchor],
    ]];
    for (NSScrollView *s in @[_buildScroll, _consoleScroll]) {
        [NSLayoutConstraint activateConstraints:@[
            [s.topAnchor constraintEqualToAnchor:divider.bottomAnchor],
            [s.leadingAnchor constraintEqualToAnchor:_bottomPanel.leadingAnchor],
            [s.trailingAnchor constraintEqualToAnchor:_bottomPanel.trailingAnchor],
        ]];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_buildScroll.bottomAnchor constraintEqualToAnchor:_bottomPanel.bottomAnchor],
        [_consoleInput.topAnchor constraintEqualToAnchor:_consoleScroll.bottomAnchor constant:6],
        [_consoleInput.leadingAnchor constraintEqualToAnchor:_bottomPanel.leadingAnchor constant:10],
        [_consoleInput.trailingAnchor constraintEqualToAnchor:_bottomPanel.trailingAnchor constant:-10],
        [_consoleInput.bottomAnchor constraintEqualToAnchor:_bottomPanel.bottomAnchor constant:-8],
    ]];
}

- (void)consoleCommand:(NSTextField *)sender {
    NSString *text = sender.stringValue;
    if (!text.length) return;
    sender.stringValue = @"";
    [[QDebugger shared] sendUserCommand:text];
}

- (void)buildInspector {
    _inspector = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 700)];

    NSTextField *header = QSectionHeader(@"Watch");
    header.translatesAutoresizingMaskIntoConstraints = NO;

    _watchTable = [[NSTableView alloc] init];
    NSTableColumn *expr = [[NSTableColumn alloc] initWithIdentifier:@"expression"];
    expr.title = @"Expression";
    expr.width = 110;
    NSTableColumn *value = [[NSTableColumn alloc] initWithIdentifier:@"value"];
    value.title = @"Value";
    value.width = 110;
    [_watchTable addTableColumn:expr];
    [_watchTable addTableColumn:value];
    _watchTable.dataSource = self;
    _watchTable.delegate = self;
    _watchTable.style = NSTableViewStyleInset;
    _watchTable.usesAlternatingRowBackgroundColors = NO;

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = _watchTable;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;

    NSButton *add = [NSButton buttonWithImage:
        [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add"]
                                       target:self action:@selector(addWatchClicked:)];
    NSButton *remove = [NSButton buttonWithImage:
        [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Remove"]
                                          target:self action:@selector(removeWatchClicked:)];
    for (NSButton *b in @[add, remove]) {
        b.bezelStyle = NSBezelStyleTexturedRounded;
        b.controlSize = NSControlSizeSmall;
    }
    add.toolTip = @"Add a watch expression";
    remove.toolTip = @"Remove the selected watch";

    for (NSView *v in @[header, scroll, add, remove]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [_inspector addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:_inspector.topAnchor constant:10],
        [header.leadingAnchor constraintEqualToAnchor:_inspector.leadingAnchor constant:12],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:_inspector.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_inspector.trailingAnchor],
        [add.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:6],
        [add.leadingAnchor constraintEqualToAnchor:_inspector.leadingAnchor constant:10],
        [remove.leadingAnchor constraintEqualToAnchor:add.trailingAnchor constant:6],
        [remove.centerYAnchor constraintEqualToAnchor:add.centerYAnchor],
        [add.bottomAnchor constraintEqualToAnchor:_inspector.bottomAnchor constant:-10],
    ]];
}

#pragma mark - Toolbar

- (void)buildToolbar {
    _toolbar = [[NSToolbar alloc] initWithIdentifier:@"QuincyToolbar.2"];
    _toolbar.delegate = self;
    _toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    _toolbar.allowsUserCustomization = YES;
    _toolbar.autosavesConfiguration = YES;
    self.window.toolbar = _toolbar;
}

static NSString *IdentifierForCommand(QCommand command) {
    return [NSString stringWithFormat:@"cmd.%ld", (long)command];
}

static QCommand CommandForIdentifier(NSToolbarItemIdentifier identifier) {
    if (![identifier hasPrefix:@"cmd."]) return QCommandNone;
    return (QCommand)[[identifier substringFromIndex:4] integerValue];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    NSMutableArray *ids = [NSMutableArray array];
    [ids addObject:NSToolbarToggleSidebarItemIdentifier];
    [ids addObject:NSToolbarSidebarTrackingSeparatorItemIdentifier];
    NSUInteger count = 0;
    const QCommand *commands = QToolbarCommands(&count);
    for (NSUInteger i = 0; i < count; i++) {
        if (commands[i] == QCommandNone)
            [ids addObject:NSToolbarSpaceItemIdentifier];
        else
            [ids addObject:IdentifierForCommand(commands[i])];
    }
    return ids;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    NSMutableArray *ids = [[self toolbarDefaultItemIdentifiers:toolbar] mutableCopy];
    for (NSNumber *c in @[@(QCommandFileSaveAll), @(QCommandEditCut),
                         @(QCommandEditCopy), @(QCommandEditPaste),
                         @(QCommandEditFind), @(QCommandEditUndo),
                         @(QCommandEditRedo), @(QCommandEditMatchBraces),
                         @(QCommandBuildRebuildAll), @(QCommandDebugStepToCursor),
                         @(QCommandDebugClearBreaks), @(QCommandDebugExamine),
                         @(QCommandViewBuildLog),
                         @(QCommandFileSaveAs), @(QCommandFilePrint),
                         @(QCommandFilePrintPreview), @(QCommandEditSelectAll),
                         @(QCommandEditReplace), @(QCommandEditFindNext),
                         @(QCommandBuildCompile), @(QCommandBuildLink),
                         @(QCommandProjectProperties), @(QCommandToolsGrep),
                         @(QCommandToolsBeautifier), @(QCommandHelpExamples),
                         @(QCommandHelpTutorial), @(QCommandViewConsole),
                         @(QCommandSettings)]) {
        NSString *identifier = IdentifierForCommand((QCommand)c.integerValue);
        if (![ids containsObject:identifier]) [ids addObject:identifier];
    }
    [ids addObjectsFromArray:@[NSToolbarFlexibleSpaceItemIdentifier,
                               NSToolbarSpaceItemIdentifier]];
    return ids;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    QCommand command = CommandForIdentifier(identifier);
    if (command == QCommandNone) return nil;
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = QCommandShortTitle(command);
    item.paletteLabel = QCommandShortTitle(command);
    item.toolTip = QCommandHelp(command);
    NSImage *image = [NSImage imageWithSystemSymbolName:QCommandSymbol(command)
                              accessibilityDescription:item.label];
    if (!image) image = [NSImage imageWithSystemSymbolName:@"square.dashed"
                                 accessibilityDescription:item.label];
    item.image = image;
    item.target = self;
    item.action = @selector(toolbarItemClicked:);
    item.tag = command;
    item.bordered = YES;
    // When the window narrows, these stay; the rest go to the » menu first.
    switch (command) {
        case QCommandFileNew: case QCommandFileOpen: case QCommandDebugRun:
        case QCommandDebugStart: case QCommandBuildStop:
            item.visibilityPriority = NSToolbarItemVisibilityPriorityUser;
            break;
        case QCommandBuildBuild:
            item.visibilityPriority = NSToolbarItemVisibilityPriorityHigh;
            break;
        default:
            item.visibilityPriority = NSToolbarItemVisibilityPriorityLow;
    }
    return item;
}

- (void)toolbarItemClicked:(NSToolbarItem *)item {
    [self performCommand:(QCommand)item.tag];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    QCommand command = (QCommand)item.tag;
    return command == QCommandNone ? YES : [self isCommandEnabled:command];
}

#pragma mark - Panels

- (void)setSidebarVisible:(BOOL)visible {
    _sidebarItem.animator.collapsed = !visible;
    [QOptions shared].showSidebar = visible;
}

- (void)setInspectorVisible:(BOOL)visible {
    _inspectorItem.animator.collapsed = !visible;
    [QOptions shared].showInspector = visible;
}

- (void)setBottomPanelVisible:(BOOL)visible {
    _bottomItem.animator.collapsed = !visible;
    [QOptions shared].showBottomPanel = visible;
}

- (void)setStatusBarVisible:(BOOL)visible {
    _status.collapsed = !visible;
    [QOptions shared].showStatusBar = visible;
}

- (BOOL)isStatusBarVisible { return !_status.collapsed; }

- (BOOL)isSidebarVisible { return !_sidebarItem.isCollapsed; }
- (BOOL)isInspectorVisible { return !_inspectorItem.isCollapsed; }
- (BOOL)isBottomPanelVisible { return !_bottomItem.isCollapsed; }

- (void)showBottomTab:(NSInteger)index {
    _bottomPicker.selectedSegment = index;
    [self bottomTabChanged:_bottomPicker];
    [self setBottomPanelVisible:YES];
}

- (void)bottomTabChanged:(NSSegmentedControl *)sender {
    _buildScroll.hidden = sender.selectedSegment != 0;
    _consoleScroll.hidden = sender.selectedSegment != 1;
    _consoleInput.hidden = sender.selectedSegment != 1;
}

- (void)clearBottom:(id)sender {
    if (_bottomPicker.selectedSegment == 0) [self clearBuildLog];
    else _consoleText.string = @"";
}

- (void)hideBottom:(id)sender { [self setBottomPanelVisible:NO]; }

#pragma mark - Documents

- (NSArray<QDocumentModel *> *)documents { return _documents; }

/// While a New Window is key, commands act on the document it shows.
- (QSecondWindow *)keySecondWindow {
    NSWindow *key = NSApp.keyWindow;
    return [key isKindOfClass:QSecondWindow.class] ? (QSecondWindow *)key : nil;
}

- (QEditorView *)activeEditor {
    QSecondWindow *second = [self keySecondWindow];
    if (second) return second.editor;
    return _activeDocument ? [_editors objectForKey:_activeDocument] : nil;
}

- (QDocumentModel *)activeDocument {
    QSecondWindow *second = [self keySecondWindow];
    return second ? second.editor.document : _activeDocument;
}

- (QEditorView *)editorForDocument:(QDocumentModel *)doc {
    return doc ? [_editors objectForKey:doc] : nil;
}

- (void)refreshGuttersForDocument:(QDocumentModel *)doc {
    [[_editors objectForKey:doc] refreshGutter];
    for (QSecondWindow *w in _secondWindows)
        if (w.editor.document == doc) [w.editor refreshGutter];
}

#pragma mark - New Window

/// Window ▸ New Window: another view on the active document, in a window of
/// its own.  Text, undo and breakpoints are the document's, so both views
/// stay in step, as the original's second MDI child did.
- (void)openNewWindowForActiveDocument {
    QDocumentModel *doc = self.activeDocument;
    if (!doc) { NSBeep(); return; }
    QEditorView *editor = [[QEditorView alloc] initWithDocument:doc];
    NSRect frame = NSMakeRect(0, 0, 720, 560);
    QSecondWindow *w = [[QSecondWindow alloc] initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
          backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.tabbingMode = NSWindowTabbingModeDisallowed;
    w.editor = editor;
    w.contentView = editor;
    w.delegate = self;
    NSUInteger n = 2;
    for (QSecondWindow *other in _secondWindows)
        if (other.editor.document == doc) n = MAX(n, other.number + 1);
    w.number = n;
    [_secondWindows addObject:w];
    [self titleSecondWindow:w];
    NSWindow *from = NSApp.keyWindow ?: self.window;
    NSPoint corner = NSMakePoint(NSMinX(from.frame) + 40, NSMaxY(from.frame) - 40);
    [w setFrameTopLeftPoint:corner];
    [w makeKeyAndOrderFront:nil];
    [editor goToLine:[[_editors objectForKey:doc] currentLine] column:1];
    [w makeFirstResponder:editor.textView];
}

- (void)titleSecondWindow:(QSecondWindow *)w {
    QDocumentModel *doc = w.editor.document;
    w.title = [NSString stringWithFormat:@"%@:%lu", doc.displayName,
               (unsigned long)w.number];
    w.subtitle = doc.url ? doc.url.URLByDeletingLastPathComponent.path
                              .stringByAbbreviatingWithTildeInPath : @"";
    w.representedURL = doc.url;
    w.documentEdited = doc.dirty;
}

- (void)closeSecondWindowsForDocument:(QDocumentModel *)doc {
    for (QSecondWindow *w in [_secondWindows copy])
        if (!doc || w.editor.document == doc) [w close];
}

- (void)addDocument:(QDocumentModel *)doc {
    [_documents addObject:doc];
    QEditorView *editor = [[QEditorView alloc] initWithDocument:doc];
    [_editors setObject:editor forKey:doc];
    [self presentDocument:doc];
}

- (void)presentDocument:(QDocumentModel *)doc {
    if (!doc) return;
    _activeDocument = doc;
    QEditorView *editor = [_editors objectForKey:doc];
    if (!editor) {
        editor = [[QEditorView alloc] initWithDocument:doc];
        [_editors setObject:editor forKey:doc];
    }
    for (NSView *v in [_editorHost.subviews copy]) [v removeFromSuperview];
    editor.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorHost addSubview:editor];
    [NSLayoutConstraint activateConstraints:@[
        [editor.topAnchor constraintEqualToAnchor:_editorHost.topAnchor],
        [editor.bottomAnchor constraintEqualToAnchor:_editorHost.bottomAnchor],
        [editor.leadingAnchor constraintEqualToAnchor:_editorHost.leadingAnchor],
        [editor.trailingAnchor constraintEqualToAnchor:_editorHost.trailingAnchor],
    ]];
    [self.window makeFirstResponder:editor.textView];
    [self refreshChrome];
}

- (void)openProjectURL:(NSURL *)url {
    NSError *error = nil;
    QProject *p = [QProject projectWithURL:url error:&error];
    if (!p) { [self reportError:error message:@"Failed to open document."]; return; }
    self.project = p;
    [self noteRecentURL:url];
    [self refreshChrome];
    [self showStatus:[NSString stringWithFormat:@"Project %@ opened",
                      url.lastPathComponent]];
}

- (QDocumentModel *)openURL:(NSURL *)url {
    url = url.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    if ([url.pathExtension.lowercaseString isEqual:@"prj"]) {
        [self openProjectURL:url];
        return nil;
    }
    for (QDocumentModel *d in _documents)
        if ([d.url isEqual:url]) { [self presentDocument:d]; return d; }
    NSError *error = nil;
    QDocumentModel *doc = [[QDocumentModel alloc] initWithURL:url error:&error];
    if (!doc) {
        [self reportError:error ?: nil message:@"Failed to open document."];
        return nil;
    }
    [self addDocument:doc];
    [self noteRecentURL:url];
    return doc;
}

- (BOOL)confirmCloseOfDocument:(QDocumentModel *)doc {
    if (!doc.dirty) return YES;
    if (doc != _activeDocument) [self presentDocument:doc];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Save changes to %@?",
                         doc.displayName];
    alert.informativeText = @"Your changes will be lost if you don't save them.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Don't Save"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertSecondButtonReturn) return NO;
    if (r == NSAlertFirstButtonReturn) return [self saveDocument:doc as:NO];
    return YES;
}

- (BOOL)confirmCloseOfAllDocuments {
    for (QDocumentModel *doc in [_documents copy])
        if (![self confirmCloseOfDocument:doc]) return NO;
    return YES;
}

- (void)closeDocument:(QDocumentModel *)doc {
    if (!doc || ![self confirmCloseOfDocument:doc]) return;
    [self closeSecondWindowsForDocument:doc];
    NSUInteger index = [_documents indexOfObject:doc];
    [_editors removeObjectForKey:doc];
    [_documents removeObject:doc];
    if (_activeDocument == doc) {
        _activeDocument = nil;
        if (_documents.count) {
            NSUInteger next = MIN(index, _documents.count - 1);
            [self presentDocument:_documents[next]];
            return;
        }
        for (NSView *v in [_editorHost.subviews copy]) [v removeFromSuperview];
    }
    [self refreshChrome];
}

- (BOOL)saveDocument:(QDocumentModel *)doc as:(BOOL)forceAsk {
    if (!doc) return NO;
    NSURL *url = doc.url;
    if (!url || forceAsk) {
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.nameFieldStringValue = doc.displayName ?: @"Untitled.cpp";
        panel.canCreateDirectories = YES;
        if ([panel runModal] != NSModalResponseOK) return NO;
        url = panel.URL;
    }
    NSError *error = nil;
    if (![doc saveToURL:url error:&error]) {
        [self reportError:error message:@"Failed to save document."];
        return NO;
    }
    [self noteRecentURL:url];
    [self refreshChrome];
    [self showStatus:[NSString stringWithFormat:@"Saved %@", doc.displayName]];
    return YES;
}

- (void)noteRecentURL:(NSURL *)url {
    NSMutableArray *list = [_recentFiles mutableCopy] ?: [NSMutableArray array];
    [list removeObject:url];
    [list insertObject:url atIndex:0];
    while (list.count > 10) [list removeLastObject];
    _recentFiles = list;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSURL *u in list) [paths addObject:u.path];
    [NSUserDefaults.standardUserDefaults setObject:paths
                                            forKey:@"Recent File List"];
    [[NSApp delegate] performSelector:@selector(rebuildRecentMenu)];
}

- (void)reportError:(NSError *)error message:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = error.localizedDescription ?: @"";
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

#pragma mark - Chrome refresh

- (void)refreshChrome {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *symbols = [NSMutableArray array];
    NSMutableArray *dirty = [NSMutableArray array];
    NSInteger selected = -1;
    for (NSUInteger i = 0; i < _documents.count; i++) {
        QDocumentModel *d = _documents[i];
        [titles addObject:d.displayName ?: @"Untitled"];
        [symbols addObject:[d symbolName]];
        [dirty addObject:@(d.dirty)];
        if (d == _activeDocument) selected = (NSInteger)i;
    }
    [_tabs setTitles:titles symbols:symbols dirtyFlags:dirty selected:selected];
    _sidebar.project = _project;
    [_sidebar reloadWithDocuments:_documents recent:_recentFiles
                           active:_activeDocument];

    // Document name as the title, its folder as the subtitle: the macOS form
    // of the original's "Quincy 2005 - [name]".
    NSString *name = _activeDocument.displayName;
    self.window.title = name.length ? name : @"Quincy 2005";
    self.window.subtitle = _activeDocument.url
        ? _activeDocument.url.URLByDeletingLastPathComponent.path.stringByAbbreviatingWithTildeInPath
        : (name.length ? @"Quincy 2005" : @"");
    self.window.representedURL = _activeDocument.url;
    self.window.documentEdited = _activeDocument.dirty;
    for (QSecondWindow *w in _secondWindows) [self titleSecondWindow:w];
    _consoleInput.enabled = [QDebugger shared].active;
    [self updateCaretPosition];
    [_toolbar validateVisibleItems];
}

- (void)updateCaretPosition {
    QEditorView *editor = [self activeEditor];
    if (!editor) { [_status setPosition:@""]; [_status setMessage:_statusMessage]; return; }
    [_status setPosition:[NSString stringWithFormat:@"Ln %ld, Col %ld",
                          (long)editor.currentLine, (long)editor.currentColumn]];
    [_status setMessage:_statusMessage];
}

- (void)showStatus:(NSString *)message {
    _statusMessage = message ?: @"";
    [_status setMessage:_statusMessage];
}

#pragma mark - Build log and console

- (void)appendBuildMessage:(QBuildMessage *)message {
    [_buildMessages addObject:message];
    [_buildTable reloadData];
    [_buildTable scrollRowToVisible:(NSInteger)_buildMessages.count - 1];
    if (![self isBottomPanelVisible]) [self showBottomTab:0];
}

- (void)appendConsoleLine:(NSString *)line {
    NSAttributedString *s = [[NSAttributedString alloc]
        initWithString:[line stringByAppendingString:@"\n"]
            attributes:@{NSFontAttributeName: _consoleText.font,
                         NSForegroundColorAttributeName: NSColor.labelColor}];
    [_consoleText.textStorage appendAttributedString:s];
    [_consoleText scrollRangeToVisible:
        NSMakeRange(_consoleText.string.length, 0)];
}

- (void)clearBuildLog {
    [_buildMessages removeAllObjects];
    [_buildTable reloadData];
}

- (void)revealPath:(NSString *)path line:(NSInteger)line column:(NSInteger)column {
    if (!path.length) return;
    QDocumentModel *doc = [self openURL:[NSURL fileURLWithPath:path]];
    if (!doc) return;
    [self.window makeKeyAndOrderFront:nil];
    [[self editorForDocument:doc] goToLine:line column:column];
}

- (void)jumpToMessage:(NSNumber *)index {
    NSInteger n = index.integerValue;
    for (QBuildMessage *m in _buildMessages)
        if (m.path && n-- == 0) { [self revealPath:m.path line:m.line column:m.column]; return; }
}

- (void)buildRowDoubleClicked:(id)sender {
    NSInteger row = _buildTable.clickedRow;
    if (row < 0 || row >= (NSInteger)_buildMessages.count) return;
    QBuildMessage *m = _buildMessages[row];
    [self revealPath:m.path line:m.line column:m.column];
}

- (NSString *)selectedProjectFile { return [_sidebar selectedProjectFile]; }

#pragma mark - Watch

- (void)addWatchClicked:(id)sender {
    [QAddWatchSheet beginSheetForWindow:self.window
                             completion:^(NSString *expression) {
        if (!expression.length) return;
        [self->_watches addObject:[@{@"expression": expression,
                                     @"value": @"??"} mutableCopy]];
        [self->_watchTable reloadData];
        if ([QDebugger shared].stopped) [[QDebugger shared] refreshWatches];
    }];
}

- (void)addWatchExpression:(NSString *)expression {
    [_watches addObject:[@{@"expression": expression, @"value": @"??"} mutableCopy]];
    [_watchTable reloadData];
    [self setInspectorVisible:YES];
}

/// Build log and debugger console as plain text, for the test script.
- (NSString *)transcript {
    NSMutableString *s = [NSMutableString stringWithString:@"--- build\n"];
    for (QBuildMessage *m in _buildMessages)
        [s appendFormat:@"%@%@\n", m.text, m.path ? [NSString stringWithFormat:@"  [%@:%ld]",
                                                      m.path.lastPathComponent, (long)m.line] : @""];
    [s appendString:@"--- console\n"];
    [s appendString:_consoleText.string ?: @""];
    [s appendString:@"\n--- watch\n"];
    for (NSDictionary *w in _watches) [s appendFormat:@"%@ := %@\n", w[@"expression"], w[@"value"]];
    [s appendFormat:@"--- program\n%@\n", [QConsoleWindowController shared].screenText];
    [s appendFormat:@"--- status\n%@\n", _statusMessage];
    [s appendFormat:@"--- caret\n%@ Ln %ld Col %ld\n", _activeDocument.displayName,
     (long)self.activeEditor.currentLine, (long)self.activeEditor.currentColumn];
    return s;
}

- (void)removeWatchClicked:(id)sender {
    NSInteger row = _watchTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_watches.count) return;
    [_watches removeObjectAtIndex:row];
    [_watchTable reloadData];
}

#pragma mark - Table data

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {
    if (table == _buildTable) return (NSInteger)_buildMessages.count;
    if (table == _watchTable) return (NSInteger)_watches.count;
    return 0;
}

- (NSView *)tableView:(NSTableView *)table
   viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTextField *field = [table makeViewWithIdentifier:@"text" owner:self];
    if (!field) {
        field = [NSTextField labelWithString:@""];
        field.identifier = @"text";
        field.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    if (table == _buildTable) {
        QBuildMessage *m = _buildMessages[row];
        field.stringValue = m.text ?: @"";
        field.font = [NSFont monospacedSystemFontOfSize:11
                                                 weight:NSFontWeightRegular];
        field.textColor = m.path ? NSColor.labelColor : NSColor.secondaryLabelColor;
    } else {
        NSDictionary *w = _watches[row];
        field.stringValue = [column.identifier isEqual:@"expression"]
            ? w[@"expression"] : w[@"value"];
        field.font = [NSFont monospacedSystemFontOfSize:11
                                                 weight:NSFontWeightRegular];
        field.textColor = NSColor.labelColor;
    }
    return field;
}

#pragma mark - Watch expressions, for the debugger to read back

- (NSArray<NSString *> *)watchExpressions {
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *w in _watches) [list addObject:w[@"expression"]];
    return list;
}

- (void)setWatchValue:(NSString *)value forExpression:(NSString *)expression {
    for (NSMutableDictionary *w in _watches)
        if ([w[@"expression"] isEqual:expression]) w[@"value"] = value ?: @"??";
    [_watchTable reloadData];
}

#pragma mark - Window delegate

/// The main window is the application, as it was on Windows: closing it
/// quits, and quitting asks about running programs and unsaved files first.
- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender != self.window) return YES;
    [NSApp terminate:sender];
    return NO;
}

- (void)windowWillClose:(NSNotification *)note {
    QSecondWindow *w = note.object;
    if (![w isKindOfClass:QSecondWindow.class]) return;
    // The text view's delegate must not outlive the window it was in.
    w.contentView = [[NSView alloc] init];
    [_secondWindows removeObject:w];
}

@end

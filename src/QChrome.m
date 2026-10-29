//
//  QChrome.m — the window's furniture: document tabs, sidebar, bottom panel,
//  Watch inspector and status bar.
//
//  Everything here is a plain AppKit control in its system appearance; the
//  only thing drawn by hand is the tab strip, which macOS has no public
//  control for but which Xcode and Safari have made a system pattern.
//

#import "QChrome.h"

#pragma mark - Tab strip

@implementation QTabBarView {
    NSMutableArray<NSButton *> *_closeButtons;
    NSInteger _hovered;
    NSTrackingArea *_tracking;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    _closeButtons = [NSMutableArray array];
    _hovered = -1;
    _titles = @[];
    _symbols = @[];
    _dirtyFlags = @[];
    return self;
}

- (BOOL)isOpaque { return YES; }
- (CGFloat)intrinsicHeight { return 30; }

- (void)setTitles:(NSArray<NSString *> *)titles
          symbols:(NSArray<NSString *> *)symbols
       dirtyFlags:(NSArray<NSNumber *> *)dirty
         selected:(NSInteger)selected {
    _titles = [titles copy];
    _symbols = [symbols copy];
    _dirtyFlags = [dirty copy];
    _selectedIndex = selected;
    [self rebuildCloseButtons];
    self.needsDisplay = YES;
}

- (CGFloat)tabWidth {
    if (_titles.count == 0) return 0;
    CGFloat available = NSWidth(self.bounds);
    CGFloat ideal = 190;
    return MIN(ideal, MAX(90, available / (CGFloat)_titles.count));
}

- (NSRect)rectForTab:(NSInteger)index {
    CGFloat w = [self tabWidth];
    return NSMakeRect(index * w, 0, w, NSHeight(self.bounds));
}

- (void)rebuildCloseButtons {
    for (NSButton *b in _closeButtons) [b removeFromSuperview];
    [_closeButtons removeAllObjects];
    for (NSInteger i = 0; i < (NSInteger)_titles.count; i++) {
        NSButton *b = [NSButton buttonWithImage:
            [NSImage imageWithSystemSymbolName:@"xmark"
                     accessibilityDescription:@"Close tab"]
                                          target:self
                                          action:@selector(closeClicked:)];
        b.bezelStyle = NSBezelStyleCircular;
        b.bordered = NO;
        b.tag = i;
        b.imageScaling = NSImageScaleProportionallyDown;
        b.toolTip = @"Close";
        b.hidden = YES;
        [self addSubview:b];
        [_closeButtons addObject:b];
    }
    [self layout];
}

- (void)layout {
    [super layout];
    for (NSInteger i = 0; i < (NSInteger)_closeButtons.count; i++) {
        NSRect r = [self rectForTab:i];
        _closeButtons[i].frame = NSMakeRect(NSMinX(r) + 6,
                                            NSMidY(r) - 7, 14, 14);
        _closeButtons[i].hidden = !(i == _hovered || i == _selectedIndex);
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                NSTrackingActiveInKeyWindow
          owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat w = [self tabWidth];
    NSInteger index = w > 0 ? (NSInteger)floor(p.x / w) : -1;
    if (index >= (NSInteger)_titles.count) index = -1;
    if (index != _hovered) { _hovered = index; [self layout]; self.needsDisplay = YES; }
}

- (void)mouseExited:(NSEvent *)event {
    _hovered = -1;
    [self layout];
    self.needsDisplay = YES;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat w = [self tabWidth];
    if (w <= 0) return;
    NSInteger index = (NSInteger)floor(p.x / w);
    if (index < 0 || index >= (NSInteger)_titles.count) return;
    if (self.onSelect) self.onSelect(index);
}

- (void)closeClicked:(NSButton *)sender {
    if (self.onClose) self.onClose(sender.tag);
}

- (void)drawRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(rect);

    NSFont *font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    CGFloat w = [self tabWidth];

    for (NSInteger i = 0; i < (NSInteger)_titles.count; i++) {
        NSRect r = [self rectForTab:i];
        if (!NSIntersectsRect(r, rect)) continue;
        BOOL active = (i == _selectedIndex);

        if (active) {
            [NSColor.controlBackgroundColor setFill];
            NSRectFill(r);
        } else if (i == _hovered) {
            [[NSColor.controlBackgroundColor colorWithAlphaComponent:0.4] setFill];
            NSRectFill(r);
        } else {
            // A hairline under the inactive tabs joins them to the strip.
            [NSColor.separatorColor setFill];
            NSRectFill(NSMakeRect(NSMinX(r), 0, NSWidth(r), 1));
        }
        if (i > 0) {
            [NSColor.separatorColor setFill];
            NSRectFill(NSMakeRect(NSMinX(r), 5, 1, NSHeight(r) - 10));
        }

        CGFloat x = NSMinX(r) + 24;
        NSString *symbol = i < (NSInteger)_symbols.count ? _symbols[i] : @"doc";
        NSImage *icon = [NSImage imageWithSystemSymbolName:symbol
                                 accessibilityDescription:nil];
        if (icon) {
            icon = [icon imageWithSymbolConfiguration:
                [NSImageSymbolConfiguration configurationWithPointSize:11
                                                                weight:NSFontWeightRegular]];
            NSRect box = NSMakeRect(x, NSMidY(r) - 7, 14, 14);
            [(active ? NSColor.labelColor : NSColor.secondaryLabelColor) set];
            [icon drawInRect:box fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver fraction:1.0
              respectFlipped:YES hints:@{NSImageHintInterpolation:
                                         @(NSImageInterpolationHigh)}];
            x += 18;
        }

        BOOL dirty = i < (NSInteger)_dirtyFlags.count && _dirtyFlags[i].boolValue;
        NSString *title = _titles[i];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: active ? NSColor.labelColor
                                                   : NSColor.secondaryLabelColor,
        };
        CGFloat room = NSMaxX(r) - x - (dirty ? 18 : 8);
        NSRect textBox = NSMakeRect(x, NSMidY(r) - 8, MAX(room, 0), 16);
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.lineBreakMode = NSLineBreakByTruncatingTail;
        NSMutableDictionary *m = [attrs mutableCopy];
        m[NSParagraphStyleAttributeName] = ps;
        [title drawInRect:textBox withAttributes:m];

        if (dirty) {
            NSRect dot = NSMakeRect(NSMaxX(r) - 15, NSMidY(r) - 3, 6, 6);
            [NSColor.tertiaryLabelColor setFill];
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
    }

    // Bottom edge of the whole strip, beyond the last tab.
    CGFloat used = w * (CGFloat)_titles.count;
    if (used < NSWidth(self.bounds)) {
        [NSColor.separatorColor setFill];
        NSRectFill(NSMakeRect(used, 0, NSWidth(self.bounds) - used, 1));
    }
}

@end

#pragma mark - Status bar

@implementation QStatusBarView {
    NSTextField *_message;
    NSTextField *_position;
    NSLayoutConstraint *_height;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    _message = [NSTextField labelWithString:@""];
    _message.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _message.textColor = NSColor.secondaryLabelColor;
    _message.lineBreakMode = NSLineBreakByTruncatingTail;

    _position = [NSTextField labelWithString:@""];
    _position.font = [NSFont monospacedDigitSystemFontOfSize:
                      NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    _position.textColor = NSColor.secondaryLabelColor;
    _position.alignment = NSTextAlignmentRight;

    for (NSTextField *f in @[_message, _position]) {
        f.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:f];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_message.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_message.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_position.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_position.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_position.leadingAnchor constraintGreaterThanOrEqualToAnchor:
            _message.trailingAnchor constant:8],
    ]];
    _height = [self.heightAnchor constraintEqualToConstant:24];
    _height.active = YES;
    return self;
}

- (BOOL)collapsed { return self.hidden; }

- (void)setCollapsed:(BOOL)collapsed {
    self.hidden = collapsed;
    _height.constant = collapsed ? 0 : 24;
}

- (BOOL)isOpaque { return YES; }

- (void)drawRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(rect);
    [NSColor.separatorColor setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 1, NSWidth(self.bounds), 1));
}

- (void)setMessage:(NSString *)message {
    _message.stringValue = message ?: @"";
}

- (void)setPosition:(NSString *)position {
    _position.stringValue = position ?: @"";
}

@end

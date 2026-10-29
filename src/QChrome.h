//
//  QChrome.h — views used only by the main window.
//

#import "Quincy.h"

/// The document tab strip above the editor.
@interface QTabBarView : NSView
@property (nonatomic, copy, readonly) NSArray<NSString *> *titles;
@property (nonatomic, copy, readonly) NSArray<NSString *> *symbols;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *dirtyFlags;
@property (nonatomic, assign, readonly) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
@property (nonatomic, copy) void (^onClose)(NSInteger index);
- (CGFloat)intrinsicHeight;
- (void)setTitles:(NSArray<NSString *> *)titles
          symbols:(NSArray<NSString *> *)symbols
       dirtyFlags:(NSArray<NSNumber *> *)dirty
         selected:(NSInteger)selected;
@end

/// Message on the left, caret position on the right.
@interface QStatusBarView : NSView
- (void)setMessage:(NSString *)message;
- (void)setPosition:(NSString *)position;
/// Hidden and zero height, so the editor takes the room.
@property (nonatomic, assign) BOOL collapsed;
@end

/// Parts of the window controller that its own files share.
@interface QWindowController (Internal)
- (void)addDocument:(QDocumentModel *)doc;
- (BOOL)saveDocument:(QDocumentModel *)doc as:(BOOL)forceAsk;
/// Offers to save a changed document; NO means the user cancelled.
- (BOOL)confirmCloseOfDocument:(QDocumentModel *)doc;
/// The same for every open document, before quitting.
- (BOOL)confirmCloseOfAllDocuments;
- (BOOL)ask:(NSString *)question;
- (void)setSidebarVisible:(BOOL)visible;
- (void)setInspectorVisible:(BOOL)visible;
- (void)setBottomPanelVisible:(BOOL)visible;
- (BOOL)isSidebarVisible;
- (BOOL)isInspectorVisible;
- (BOOL)isBottomPanelVisible;
- (void)showBottomTab:(NSInteger)index;
- (void)setStatusBarVisible:(BOOL)visible;
- (BOOL)isStatusBarVisible;
- (void)openNewWindowForActiveDocument;
- (void)noteRecentURL:(NSURL *)url;
- (void)reportError:(NSError *)error message:(NSString *)message;
- (NSArray<NSString *> *)watchExpressions;
- (void)setWatchValue:(NSString *)value forExpression:(NSString *)expression;
- (BOOL)isRecordingMacro;
- (NSString *)selectedProjectFile;
- (void)openProjectURL:(NSURL *)url;
- (void)recordMacroEvent:(NSEvent *)event;
@end

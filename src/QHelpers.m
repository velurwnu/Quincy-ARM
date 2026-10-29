//
//  QHelpers.m — the few view constructors the settings pages and sheets share.
//

#import "Quincy.h"
#import <objc/runtime.h>

NSTextField *QLabel(NSString *text) {
    NSTextField *f = [NSTextField labelWithString:text ?: @""];
    f.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    f.alignment = NSTextAlignmentRight;
    return f;
}

NSTextField *QSecondaryLabel(NSString *text) {
    NSTextField *f = [NSTextField labelWithString:text ?: @""];
    f.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    f.textColor = NSColor.secondaryLabelColor;
    f.lineBreakMode = NSLineBreakByWordWrapping;
    f.maximumNumberOfLines = 0;
    f.preferredMaxLayoutWidth = 380;
    return f;
}

NSTextField *QTextField(NSString *placeholder) {
    NSTextField *f = [NSTextField textFieldWithString:@""];
    f.placeholderString = placeholder;
    f.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    f.bezelStyle = NSTextFieldRoundedBezel;
    return f;
}

NSTextField *QSectionHeader(NSString *text) {
    NSTextField *f = [NSTextField labelWithString:text ?: @""];
    f.font = [NSFont systemFontOfSize:NSFont.systemFontSize
                               weight:NSFontWeightSemibold];
    return f;
}

@implementation QBlockTarget
+ (instancetype)targetWithBlock:(void (^)(id sender))block {
    QBlockTarget *t = [[QBlockTarget alloc] init];
    t.block = block;
    return t;
}
- (void)fire:(id)sender { if (self.block) self.block(sender); }
@end

void QSetBlockAction(NSControl *control, void (^block)(id sender)) {
    QBlockTarget *t = [QBlockTarget targetWithBlock:block];
    objc_setAssociatedObject(control, @selector(fire:), t,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    control.target = t;
    control.action = @selector(fire:);
}

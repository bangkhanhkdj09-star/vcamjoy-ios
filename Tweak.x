#import <UIKit/UIKit.h>

@interface BubbleWindow : UIWindow
@end

@implementation BubbleWindow

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 60, 60)];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = NO;
        self.layer.cornerRadius = 30;
        self.clipsToBounds = YES;

        UIView *bubble = [[UIView alloc] initWithFrame:self.bounds];
        bubble.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.85];
        bubble.layer.cornerRadius = 30;
        [self addSubview:bubble];

        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.text = @"✓ DEB";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:11];
        label.numberOfLines = 2;
        [self addSubview:label];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)gr {
    CGPoint translation = [gr translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x,
                              self.center.y + translation.y);
    [gr setTranslation:CGPointZero inView:self.superview];
}

- (void)handleTap {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Tweak hoat dong!"
        message:@"File .deb da cai thanh cong.\nRootHide palera1n iOS 16.7.x"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *root = [UIApplication sharedApplication]
        .windows.firstObject.rootViewController;
    [root presentViewController:alert animated:YES completion:nil];
}

@end

static BubbleWindow *bubbleWindow;

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
            bubbleWindow = [[BubbleWindow alloc] init];
        });
}
%end

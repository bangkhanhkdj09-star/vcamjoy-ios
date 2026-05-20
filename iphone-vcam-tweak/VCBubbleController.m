#import "VCBubbleController.h"
#import <WebKit/WebKit.h>

static NSString * const VCPrefsPath = @"/var/mobile/Library/Preferences/local.vcambubble.plist";

@interface VCBubbleController () <UITextFieldDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextField *ipField;
@property (nonatomic, strong) WKWebView *streamView;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, strong) NSTimer *statusTimer;
@property (nonatomic, strong) NSTimer *flashTimer;
@property (nonatomic, strong) UISwitch *hookSwitch;
@end

@implementation VCBubbleController

+ (instancetype)sharedController {
    static VCBubbleController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [VCBubbleController new];
    });
    return controller;
}

- (void)install {
    if (self.window) return;

    UIWindowScene *targetScene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:UIWindowScene.class]) {
                targetScene = (UIWindowScene *)scene;
                break;
            }
        }
    }

    if (@available(iOS 13.0, *)) {
        self.window = [[UIWindow alloc] initWithWindowScene:targetScene ?: (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject];
        self.window.frame = UIScreen.mainScreen.bounds;
    } else {
        self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    self.window.windowLevel = UIWindowLevelAlert + 30;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.hidden = NO;
    self.window.rootViewController = [UIViewController new];
    self.window.userInteractionEnabled = YES;
    [self.window makeKeyAndVisible];

    [self buildStreamOverlay];
    [self buildBubble];
    [self buildPanel];
    [self loadPrefs];
}

- (void)buildStreamOverlay {
    self.streamView = [[WKWebView alloc] initWithFrame:self.window.bounds];
    self.streamView.backgroundColor = UIColor.clearColor;
    self.streamView.opaque = NO;
    self.streamView.scrollView.scrollEnabled = NO;
    self.streamView.userInteractionEnabled = NO;
    self.streamView.hidden = YES;
    [self.window.rootViewController.view addSubview:self.streamView];

    self.tintView = [[UIView alloc] initWithFrame:self.window.bounds];
    self.tintView.backgroundColor = UIColor.clearColor;
    self.tintView.userInteractionEnabled = NO;
    [self.window.rootViewController.view addSubview:self.tintView];
}

- (void)buildBubble {
    self.bubble = [[UIView alloc] initWithFrame:CGRectMake(285, 170, 74, 74)];
    self.bubble.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
    self.bubble.layer.cornerRadius = 37;
    self.bubble.layer.borderWidth = 2;
    self.bubble.layer.borderColor = UIColor.whiteColor.CGColor;

    UILabel *label = [[UILabel alloc] initWithFrame:self.bubble.bounds];
    label.text = @"VC";
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:20];
    [self.bubble addSubview:label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePanel)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveBubble:)];
    [self.bubble addGestureRecognizer:tap];
    [self.bubble addGestureRecognizer:pan];
    [self.window.rootViewController.view addSubview:self.bubble];
}

- (void)buildPanel {
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(28, 120, 278, 214)];
    self.panel.backgroundColor = [UIColor colorWithWhite:1 alpha:0.94];
    self.panel.layer.cornerRadius = 8;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.18].CGColor;
    self.panel.layer.borderWidth = 1;
    self.panel.hidden = YES;

    self.ipField = [[UITextField alloc] initWithFrame:CGRectMake(16, 18, 246, 42)];
    self.ipField.borderStyle = UITextBorderStyleRoundedRect;
    self.ipField.placeholder = @"http://192.168.1.10:8080";
    self.ipField.keyboardType = UIKeyboardTypeURL;
    self.ipField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.ipField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.ipField.delegate = self;
    [self.panel addSubview:self.ipField];

    UIButton *connect = [UIButton buttonWithType:UIButtonTypeSystem];
    connect.frame = CGRectMake(16, 74, 116, 40);
    [connect setTitle:@"Connect" forState:UIControlStateNormal];
    [connect addTarget:self action:@selector(connect) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:connect];

    UIButton *show = [UIButton buttonWithType:UIButtonTypeSystem];
    show.frame = CGRectMake(146, 74, 116, 40);
    [show setTitle:@"Show stream" forState:UIControlStateNormal];
    [show addTarget:self action:@selector(toggleStream) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:show];

    UILabel *hookLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 120, 170, 32)];
    hookLabel.text = @"Hook camera";
    hookLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    hookLabel.textColor = UIColor.blackColor;
    [self.panel addSubview:hookLabel];

    self.hookSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(204, 118, 58, 32)];
    [self.hookSwitch addTarget:self action:@selector(hookSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.hookSwitch];

    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(16, 166, 246, 30)];
    note.text = @"PC URL: http://IP:8080";
    note.font = [UIFont systemFontOfSize:12];
    note.textColor = UIColor.darkGrayColor;
    [self.panel addSubview:note];

    [self.window.rootViewController.view addSubview:self.panel];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
}

- (void)toggleStream {
    self.streamView.hidden = !self.streamView.hidden;
}

- (void)hookSwitchChanged {
    [self savePrefs];
}

- (void)moveBubble:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.window.rootViewController.view];
    CGPoint center = self.bubble.center;
    center.x += translation.x;
    center.y += translation.y;
    self.bubble.center = center;
    [gesture setTranslation:CGPointZero inView:self.window.rootViewController.view];
}

- (void)connect {
    NSString *input = self.ipField.text.length ? self.ipField.text : self.ipField.placeholder;
    self.baseURL = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self loadStreamView];
    [self savePrefs];
    [self startStatusPolling];
    self.streamView.hidden = NO;
}

- (void)loadStreamView {
    if (!self.baseURL.length) return;
    NSString *streamURL = [NSString stringWithFormat:@"%@/stream?t=%f", self.baseURL, NSDate.date.timeIntervalSince1970];
    NSString *html = [NSString stringWithFormat:
        @"<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<style>html,body{margin:0;width:100%%;height:100%%;background:transparent;overflow:hidden}"
        "img{width:100%%;height:100%%;object-fit:contain}</style>"
        "<img src='%@'>", streamURL];
    [self.streamView loadHTMLString:html baseURL:nil];
}

- (void)loadPrefs {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCPrefsPath];
    NSString *url = prefs[@"baseURL"];
    if ([url isKindOfClass:NSString.class] && url.length) {
        self.baseURL = url;
        self.ipField.text = url;
    }
    self.hookSwitch.on = [prefs[@"enabled"] boolValue];
}

- (void)savePrefs {
    NSDictionary *prefs = @{
        @"baseURL": self.baseURL ?: @"",
        @"enabled": @(self.hookSwitch.on)
    };
    [prefs writeToFile:VCPrefsPath atomically:YES];
}

- (void)startStatusPolling {
    [self.statusTimer invalidate];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) {
        [self fetchStatus];
    }];
    [self fetchStatus];
}

- (void)fetchStatus {
    if (!self.baseURL.length) return;
    NSURL *url = [NSURL URLWithString:[self.baseURL stringByAppendingString:@"/status"]];
    if (!url) return;

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, __unused NSURLResponse *response, NSError *error) {
        if (error || !data.length) return;
        NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([payload isKindOfClass:NSDictionary.class]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self applyState:payload];
            });
        }
    }];
    [task resume];
}

- (void)applyState:(NSDictionary *)state {
    NSDictionary *rgb = state[@"rgb"];
    if (![rgb isKindOfClass:NSDictionary.class]) return;

    CGFloat r = [rgb[@"r"] doubleValue] / 255.0;
    CGFloat g = [rgb[@"g"] doubleValue] / 255.0;
    CGFloat b = [rgb[@"b"] doubleValue] / 255.0;
    CGFloat brightness = MAX(0.0, MIN(1.0, [rgb[@"brightness"] doubleValue]));
    self.tintView.backgroundColor = [[UIColor colorWithRed:r green:g blue:b alpha:1] colorWithAlphaComponent:0.18 * brightness];

    NSString *mode = rgb[@"mode"];
    BOOL autoFlash = [mode isEqualToString:@"breath"];
    NSTimeInterval interval = MAX(0.2, 1.0 / MAX(0.2, [rgb[@"speed"] doubleValue]));
    [self.flashTimer invalidate];
    self.flashTimer = nil;

    if (autoFlash) {
        self.flashTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(__unused NSTimer *timer) {
            self.tintView.alpha = self.tintView.alpha < 0.2 ? 1.0 : 0.08;
        }];
    } else {
        self.tintView.alpha = 1.0;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self connect];
    return YES;
}

@end

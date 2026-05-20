#import "VCBubbleController.h"
#import <WebKit/WebKit.h>

static NSString * const VCPrefsPath = @"/var/mobile/Library/Preferences/local.vcambubble.plist";

@interface VCPassthroughWindow : UIWindow
@property (nonatomic, weak) UIView *touchBubble;
@property (nonatomic, weak) UIView *touchPanel;
@end

@implementation VCPassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit || hit == self || hit == self.rootViewController.view) return nil;

    CGPoint bubblePoint = [self.touchBubble convertPoint:point fromView:self];
    if (!self.touchBubble.hidden && [self.touchBubble pointInside:bubblePoint withEvent:event]) return hit;

    CGPoint panelPoint = [self.touchPanel convertPoint:point fromView:self];
    if (!self.touchPanel.hidden && [self.touchPanel pointInside:panelPoint withEvent:event]) return hit;

    return nil;
}

@end

@interface VCBubbleController () <UITextFieldDelegate>
@property (nonatomic, strong) VCPassthroughWindow *window;
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextField *ipField;
@property (nonatomic, strong) WKWebView *streamView;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, strong) NSTimer *statusTimer;
@property (nonatomic, strong) NSTimer *flashTimer;
@property (nonatomic, strong) UISwitch *hookSwitch;
@property (nonatomic, strong) UISwitch *colorSwitch;
@property (nonatomic, strong) UILabel *playLabel;
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
        self.window = [[VCPassthroughWindow alloc] initWithWindowScene:targetScene ?: (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject];
        self.window.frame = UIScreen.mainScreen.bounds;
    } else {
        self.window = [[VCPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    self.window.windowLevel = UIWindowLevelAlert + 30;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.hidden = NO;
    self.window.rootViewController = [UIViewController new];
    self.window.userInteractionEnabled = YES;

    [self buildStreamOverlay];
    [self buildBubble];
    [self buildPanel];
    self.window.touchBubble = self.bubble;
    self.window.touchPanel = self.panel;
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
    self.bubble = [[UIView alloc] initWithFrame:CGRectMake(285, 170, 68, 68)];
    self.bubble.backgroundColor = [UIColor colorWithRed:0.0 green:0.95 blue:0.12 alpha:1.0];
    self.bubble.layer.cornerRadius = 37;
    self.bubble.layer.borderWidth = 3;
    self.bubble.layer.borderColor = [UIColor colorWithRed:0.58 green:1.0 blue:0.5 alpha:1.0].CGColor;
    self.bubble.layer.shadowColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.1 alpha:1.0].CGColor;
    self.bubble.layer.shadowOpacity = 0.65;
    self.bubble.layer.shadowRadius = 10;
    self.bubble.layer.shadowOffset = CGSizeZero;

    UILabel *label = [[UILabel alloc] initWithFrame:self.bubble.bounds];
    label.text = @"J";
    label.textColor = UIColor.blackColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:32];
    [self.bubble addSubview:label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(togglePanel)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveBubble:)];
    [self.bubble addGestureRecognizer:tap];
    [self.bubble addGestureRecognizer:pan];
    [self.window.rootViewController.view addSubview:self.bubble];
}

- (void)buildPanel {
    UIColor *green = [UIColor colorWithRed:0.0 green:1.0 blue:0.10 alpha:1.0];
    UIColor *dark = [UIColor colorWithRed:0.06 green:0.07 blue:0.07 alpha:0.96];
    UIColor *card = [UIColor colorWithRed:0.14 green:0.15 blue:0.15 alpha:1.0];

    self.panel = [[UIView alloc] initWithFrame:CGRectMake(18, 92, 340, 430)];
    self.panel.backgroundColor = dark;
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    self.panel.layer.borderWidth = 1;
    self.panel.hidden = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 18, 250, 42)];
    title.text = @"NovaCam Local";
    title.textColor = green;
    title.font = [UIFont boldSystemFontOfSize:28];
    [self.panel addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(292, 20, 34, 34);
    close.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    close.layer.cornerRadius = 17;
    [close setTitle:@"x" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:1] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:close];

    self.playLabel = [[UILabel alloc] initWithFrame:CGRectMake(22, 66, 296, 28)];
    self.playLabel.text = @"[OK] Dang phat: Local Stream";
    self.playLabel.textColor = green;
    self.playLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.panel addSubview:self.playLabel];

    UIButton *wifi = [UIButton buttonWithType:UIButtonTypeSystem];
    wifi.frame = CGRectMake(20, 106, 300, 48);
    wifi.backgroundColor = green;
    wifi.layer.cornerRadius = 12;
    [wifi setTitle:@"WiFi" forState:UIControlStateNormal];
    [wifi setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    wifi.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [self.panel addSubview:wifi];

    UIView *ipCard = [[UIView alloc] initWithFrame:CGRectMake(20, 170, 300, 64)];
    ipCard.backgroundColor = card;
    ipCard.layer.cornerRadius = 12;
    [self.panel addSubview:ipCard];

    self.ipField = [[UITextField alloc] initWithFrame:CGRectMake(14, 11, 272, 42)];
    self.ipField.borderStyle = UITextBorderStyleNone;
    self.ipField.backgroundColor = UIColor.clearColor;
    self.ipField.textColor = green;
    self.ipField.tintColor = green;
    self.ipField.placeholder = @"192.168.1.xx";
    self.ipField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.ipField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.ipField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.ipField.font = [UIFont boldSystemFontOfSize:21];
    self.ipField.delegate = self;
    [ipCard addSubview:self.ipField];

    UIButton *stop = [self panelButtonWithTitle:@"Dung phat" color:[UIColor redColor] frame:CGRectMake(20, 250, 148, 58)];
    [stop addTarget:self action:@selector(toggleStream) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:stop];

    UIButton *connect = [self panelButtonWithTitle:@"Connect" color:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0] frame:CGRectMake(188, 250, 132, 58)];
    [connect addTarget:self action:@selector(connect) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:connect];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(22, 316, 296, 22)];
    hint.text = @"Nhap IP PC roi bam Connect";
    hint.textColor = UIColor.whiteColor;
    hint.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.panel addSubview:hint];

    UILabel *hookLabel = [[UILabel alloc] initWithFrame:CGRectMake(22, 352, 200, 32)];
    hookLabel.text = @"Bat Camera Ao";
    hookLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    hookLabel.textColor = UIColor.whiteColor;
    [self.panel addSubview:hookLabel];

    self.hookSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(254, 350, 58, 32)];
    self.hookSwitch.onTintColor = green;
    [self.hookSwitch addTarget:self action:@selector(hookSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.hookSwitch];

    UILabel *colorLabel = [[UILabel alloc] initWithFrame:CGRectMake(22, 390, 200, 32)];
    colorLabel.text = @"ColorSync (60Hz)";
    colorLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    colorLabel.textColor = UIColor.whiteColor;
    [self.panel addSubview:colorLabel];

    self.colorSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(254, 388, 58, 32)];
    self.colorSwitch.on = YES;
    self.colorSwitch.onTintColor = green;
    [self.colorSwitch addTarget:self action:@selector(colorSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.colorSwitch];

    [self.window.rootViewController.view addSubview:self.panel];
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
}

- (UIButton *)panelButtonWithTitle:(NSString *)title color:(UIColor *)color frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    button.backgroundColor = color;
    button.layer.cornerRadius = 12;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    return button;
}

- (void)closePanel {
    self.panel.hidden = YES;
}

- (void)toggleStream {
    self.streamView.hidden = !self.streamView.hidden;
}

- (void)hookSwitchChanged {
    [self savePrefs];
}

- (void)colorSwitchChanged {
    self.tintView.hidden = !self.colorSwitch.on;
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
    self.baseURL = [self normalizedBaseURLFromInput:input];
    self.ipField.text = [self displayIPFromBaseURL:self.baseURL];
    [self loadStreamView];
    [self savePrefs];
    [self startStatusPolling];
    self.streamView.hidden = NO;
    self.playLabel.text = @"[OK] Dang phat: WiFi Stream";
}

- (NSString *)normalizedBaseURLFromInput:(NSString *)input {
    NSString *value = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([value hasPrefix:@"http://"] || [value hasPrefix:@"https://"]) return value;
    if ([value containsString:@":"]) return [@"http://" stringByAppendingString:value];
    return [NSString stringWithFormat:@"http://%@:8080", value];
}

- (NSString *)displayIPFromBaseURL:(NSString *)url {
    NSString *value = [url stringByReplacingOccurrencesOfString:@"http://" withString:@""];
    value = [value stringByReplacingOccurrencesOfString:@"https://" withString:@""];
    NSArray *parts = [value componentsSeparatedByString:@":"];
    return parts.firstObject ?: value;
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
        self.ipField.text = [self displayIPFromBaseURL:url];
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

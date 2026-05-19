/*
 * MainViewController.m — VCamJoy v4.0
 *
 * App chạy như daemon trên JB device.
 * Khi mở lần đầu: cấu hình IP + bật vcam.
 * Sau đó minimize → bubble nổi trên mọi app (qua assistive touch trick).
 *
 * Giao tiếp với Tweak qua NSUserDefaults "com.vcamjoy.prefs"
 * + Darwin notification "com.vcamjoy.prefschanged"
 */

#import "MainViewController.h"

// ── SharedPrefs helper ────────────────────────────────────────────────────
static NSUserDefaults *prefs(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
}
static void notifyTweak(void) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vcamjoy.prefschanged"), NULL, NULL, YES);
}

@interface MainViewController ()
@property (nonatomic, strong) UITextField *ipField;
@property (nonatomic, strong) UISwitch    *vcamSwitch;
@property (nonatomic, strong) UILabel     *statusLabel;
@property (nonatomic, strong) UIView      *statusDot;
// Floating bubble (hiện khi app chạy nền)
@property (nonatomic, strong) UIWindow    *bubbleWindow;
@property (nonatomic, strong) UIButton    *bubbleBtn;
@property (nonatomic, assign) BOOL         bubbleVisible;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildUI];
    [self loadPrefs];
}

// ── Load / Save ───────────────────────────────────────────────────────────
- (void)loadPrefs {
    NSUserDefaults *p = prefs();
    [p synchronize];
    NSString *url = [p stringForKey:@"streamURL"];
    BOOL enabled   = [p boolForKey:@"vcamEnabled"];
    if (url) self.ipField.text = url;
    self.vcamSwitch.on = enabled;
    [self updateStatus:enabled];
}

- (void)savePrefs {
    NSString *url = [self.ipField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL enabled = self.vcamSwitch.on;
    NSUserDefaults *p = prefs();
    [p setObject:url forKey:@"streamURL"];
    [p setBool:enabled forKey:@"vcamEnabled"];
    [p synchronize];
    notifyTweak();
    [self updateStatus:enabled];
}

- (void)updateStatus:(BOOL)on {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusDot.backgroundColor = on
            ? [UIColor colorWithRed:0.2 green:0.9 blue:0.4 alpha:1]
            : [UIColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:1];
        self.statusLabel.text = on ? @"Camera Ảo: BẬT" : @"Camera Ảo: TẮT";
        // Cập nhật bubble emoji
        if (self.bubbleBtn)
            [self.bubbleBtn setTitle:(on ? @"🟢" : @"🎥")
                           forState:UIControlStateNormal];
    });
}

// ── Actions ───────────────────────────────────────────────────────────────
- (void)connectTapped {
    [self.ipField resignFirstResponder];
    [self savePrefs];

    // Visual feedback
    UIButton *btn = (UIButton *)[self.view viewWithTag:99];
    btn.backgroundColor = [UIColor colorWithRed:0.1 green:0.7 blue:0.3 alpha:1];
    [btn setTitle:@"✓ Đã lưu!" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        btn.backgroundColor = [UIColor colorWithRed:0.18 green:0.56 blue:1 alpha:1];
        [btn setTitle:@"Lưu & Kết nối" forState:UIControlStateNormal];
    });
}

- (void)switchChanged:(UISwitch *)sw {
    [self savePrefs];
}

- (void)minimizeTapped {
    // Show floating bubble rồi đưa app xuống nền
    [self showBubble];
    // Simulate home button
    [[UIApplication sharedApplication] performSelector:@selector(suspend)];
}

// ── Floating Bubble ───────────────────────────────────────────────────────
- (void)showBubble {
    if (self.bubbleWindow) {
        self.bubbleWindow.hidden = NO;
        return;
    }

    // Tạo UIWindow riêng level alert+100 — luôn nổi trên mọi app
    self.bubbleWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.bubbleWindow.windowLevel = UIWindowLevelAlert + 100;
    self.bubbleWindow.backgroundColor = [UIColor clearColor];
    self.bubbleWindow.userInteractionEnabled = YES;

    // Bắt buộc cần rootViewController
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor clearColor];
    self.bubbleWindow.rootViewController = vc;
    [self.bubbleWindow makeKeyAndVisible];

    // Bubble button
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.bubbleBtn.frame = CGRectMake(16, 120, 60, 60);
    self.bubbleBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    self.bubbleBtn.layer.cornerRadius = 30;
    self.bubbleBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    self.bubbleBtn.layer.shadowRadius = 8;
    self.bubbleBtn.layer.shadowOpacity = 0.7;
    self.bubbleBtn.layer.shadowOffset = CGSizeMake(0, 3);
    self.bubbleBtn.titleLabel.font = [UIFont systemFontOfSize:26];
    BOOL on = [prefs() boolForKey:@"vcamEnabled"];
    [self.bubbleBtn setTitle:(on ? @"🟢" : @"🎥") forState:UIControlStateNormal];

    [self.bubbleBtn addTarget:self action:@selector(bubbleTapped)
             forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(bubblePanned:)];
    [self.bubbleBtn addGestureRecognizer:pan];

    [vc.view addSubview:self.bubbleBtn];

    NSLog(@"[VCamJoy App] Bubble shown");
}

- (void)bubbleTapped {
    // Mở lại app
    [[UIApplication sharedApplication]
        openURL:[NSURL URLWithString:@"vcamjoy://open"]
        options:@{}
        completionHandler:nil];
    // Fallback: bật/tắt trực tiếp
    BOOL cur = [prefs() boolForKey:@"vcamEnabled"];
    NSUserDefaults *p = prefs();
    [p setBool:!cur forKey:@"vcamEnabled"];
    [p synchronize];
    notifyTweak();
    [self.bubbleBtn setTitle:(!cur ? @"🟢" : @"🎥") forState:UIControlStateNormal];
}

- (void)bubblePanned:(UIPanGestureRecognizer *)gr {
    CGPoint delta = [gr translationInView:self.bubbleWindow];
    CGRect f = self.bubbleBtn.frame;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    f.origin.x = MAX(0, MIN(f.origin.x + delta.x, sc.width  - f.size.width));
    f.origin.y = MAX(20, MIN(f.origin.y + delta.y, sc.height - f.size.height - 20));
    self.bubbleBtn.frame = f;
    [gr setTranslation:CGPointZero inView:self.bubbleWindow];
}

// ── Build UI ──────────────────────────────────────────────────────────────
- (void)buildUI {
    CGFloat sw = self.view.bounds.size.width;
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];

    // Header
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 100)];
    header.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    [self.view addSubview:header];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, sw-40, 36)];
    title.text = @"🎥  VCamJoy";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:26];
    [header addSubview:title];

    // Status row
    self.statusDot = [[UIView alloc] initWithFrame:CGRectMake(20, 122, 12, 12)];
    self.statusDot.layer.cornerRadius = 6;
    self.statusDot.backgroundColor = [UIColor grayColor];
    [self.view addSubview:self.statusDot];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 114, sw-60, 28)];
    self.statusLabel.text = @"Camera Ảo: TẮT";
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.statusLabel];

    // Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 158, sw-32, 220)];
    card.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    card.layer.cornerRadius = 14;
    [self.view addSubview:card];

    UILabel *lbl1 = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, sw-64, 20)];
    lbl1.text = @"Stream URL (PC)";
    lbl1.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    lbl1.font = [UIFont systemFontOfSize:13];
    [card addSubview:lbl1];

    self.ipField = [[UITextField alloc] initWithFrame:CGRectMake(16, 44, sw-64, 44)];
    self.ipField.placeholder = @"http://192.168.x.x:8080/stream";
    self.ipField.textColor = [UIColor whiteColor];
    self.ipField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    self.ipField.layer.cornerRadius = 8;
    self.ipField.keyboardType = UIKeyboardTypeURL;
    self.ipField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.ipField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.ipField.returnKeyType = UIReturnKeyDone;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0,0,12,1)];
    self.ipField.leftView = pad;
    self.ipField.leftViewMode = UITextFieldViewModeAlways;
    [card addSubview:self.ipField];

    UIButton *conn = [UIButton buttonWithType:UIButtonTypeCustom];
    conn.tag = 99;
    conn.frame = CGRectMake(16, 102, sw-64, 44);
    conn.backgroundColor = [UIColor colorWithRed:0.18 green:0.56 blue:1 alpha:1];
    conn.layer.cornerRadius = 8;
    [conn setTitle:@"Lưu & Kết nối" forState:UIControlStateNormal];
    [conn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    conn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [conn addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:conn];

    UILabel *lbl2 = [[UILabel alloc] initWithFrame:CGRectMake(16, 162, sw-100, 28)];
    lbl2.text = @"Bật Camera Ảo";
    lbl2.textColor = [UIColor whiteColor];
    lbl2.font = [UIFont systemFontOfSize:15];
    [card addSubview:lbl2];

    self.vcamSwitch = [[UISwitch alloc] init];
    self.vcamSwitch.frame = CGRectMake(sw-32-16-51, 160, 51, 31);
    self.vcamSwitch.onTintColor = [UIColor colorWithRed:0.2 green:0.82 blue:0.4 alpha:1];
    [self.vcamSwitch addTarget:self action:@selector(switchChanged:)
              forControlEvents:UIControlEventValueChanged];
    [card addSubview:self.vcamSwitch];

    // Minimize button → hiện bubble
    UIButton *min = [UIButton buttonWithType:UIButtonTypeCustom];
    min.frame = CGRectMake(16, 398, sw-32, 50);
    min.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    min.layer.cornerRadius = 12;
    [min setTitle:@"⬇  Ẩn app & hiện bong bóng" forState:UIControlStateNormal];
    [min setTitleColor:[UIColor colorWithRed:0.8 green:0.8 blue:1 alpha:1]
             forState:UIControlStateNormal];
    min.titleLabel.font = [UIFont systemFontOfSize:15];
    [min addTarget:self action:@selector(minimizeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:min];

    // Hướng dẫn
    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(16, 460, sw-32, 80)];
    tip.text = @"① Nhập IP PC → Lưu & Kết nối\n② Bật switch Camera Ảo\n③ Bấm nút ⬇ → bubble 🎥 nổi trên mọi app\n④ Bấm bubble để bật/tắt nhanh";
    tip.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    tip.font = [UIFont systemFontOfSize:12];
    tip.numberOfLines = 0;
    [self.view addSubview:tip];
}

@end

#import "VCViewController.h"
#import <WebKit/WebKit.h>

static NSString * const VCPrefsPath = @"/var/mobile/Library/Preferences/local.vcambubble.plist";

@interface VCViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *ipField;
@property (nonatomic, strong) UISwitch *hookSwitch;
@property (nonatomic, strong) UISwitch *colorSwitch;
@property (nonatomic, strong) WKWebView *preview;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy) NSString *baseURL;
@end

@implementation VCViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.06 alpha:1.0];
    [self buildUI];
    [self loadPrefs];
}

- (void)buildUI {
    UIColor *green = [UIColor colorWithRed:0.0 green:1.0 blue:0.10 alpha:1.0];
    UIColor *card = [UIColor colorWithRed:0.12 green:0.13 blue:0.13 alpha:1.0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(22, 58, self.view.bounds.size.width - 44, 48)];
    title.text = @"NovaCam Local";
    title.textColor = green;
    title.font = [UIFont boldSystemFontOfSize:34];
    [self.view addSubview:title];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 112, self.view.bounds.size.width - 48, 28)];
    self.statusLabel.text = @"[OK] San sang ket noi WiFi";
    self.statusLabel.textColor = green;
    self.statusLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.view addSubview:self.statusLabel];

    UILabel *wifi = [[UILabel alloc] initWithFrame:CGRectMake(22, 154, self.view.bounds.size.width - 44, 50)];
    wifi.text = @"WiFi";
    wifi.textAlignment = NSTextAlignmentCenter;
    wifi.textColor = UIColor.blackColor;
    wifi.font = [UIFont boldSystemFontOfSize:23];
    wifi.backgroundColor = green;
    wifi.layer.cornerRadius = 12;
    wifi.clipsToBounds = YES;
    [self.view addSubview:wifi];

    UIView *ipCard = [[UIView alloc] initWithFrame:CGRectMake(22, 224, self.view.bounds.size.width - 44, 66)];
    ipCard.backgroundColor = card;
    ipCard.layer.cornerRadius = 12;
    [self.view addSubview:ipCard];

    self.ipField = [[UITextField alloc] initWithFrame:CGRectMake(16, 12, ipCard.bounds.size.width - 32, 42)];
    self.ipField.placeholder = @"192.168.1.xx";
    self.ipField.textColor = green;
    self.ipField.tintColor = green;
    self.ipField.font = [UIFont boldSystemFontOfSize:22];
    self.ipField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.ipField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.ipField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.ipField.delegate = self;
    [ipCard addSubview:self.ipField];

    UIButton *connect = [self button:@"Connect" color:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0] frame:CGRectMake(22, 306, self.view.bounds.size.width - 44, 58)];
    [connect addTarget:self action:@selector(connect) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:connect];

    [self addRow:@"Bat Camera Ao" switchView:&_hookSwitch y:388 color:green];
    [self addRow:@"ColorSync (60Hz)" switchView:&_colorSwitch y:448 color:green];

    UIButton *disable = [self button:@"Tat hook khan cap" color:UIColor.redColor frame:CGRectMake(22, 516, self.view.bounds.size.width - 44, 58)];
    [disable addTarget:self action:@selector(disableAll) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:disable];

    self.preview = [[WKWebView alloc] initWithFrame:CGRectMake(22, 596, self.view.bounds.size.width - 44, 180)];
    self.preview.backgroundColor = UIColor.blackColor;
    self.preview.layer.cornerRadius = 12;
    self.preview.clipsToBounds = YES;
    [self.view addSubview:self.preview];
}

- (UIButton *)button:(NSString *)title color:(UIColor *)color frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    button.backgroundColor = color;
    button.layer.cornerRadius = 12;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    return button;
}

- (void)addRow:(NSString *)title switchView:(UISwitch **)switchRef y:(CGFloat)y color:(UIColor *)green {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, y, 220, 44)];
    label.text = title;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:21];
    [self.view addSubview:label];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 86, y + 4, 58, 32)];
    sw.onTintColor = green;
    [sw addTarget:self action:@selector(savePrefs) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:sw];
    *switchRef = sw;
}

- (void)connect {
    self.baseURL = [self normalizedBaseURLFromInput:self.ipField.text.length ? self.ipField.text : self.ipField.placeholder];
    self.ipField.text = [self displayIPFromBaseURL:self.baseURL];
    self.hookSwitch.on = YES;
    [self savePrefs];
    [self loadPreview];
    self.statusLabel.text = @"[OK] Dang phat: WiFi Stream";
}

- (void)disableAll {
    self.hookSwitch.on = NO;
    self.colorSwitch.on = NO;
    [self savePrefs];
    [self.preview loadHTMLString:@"<body style='background:#000'></body>" baseURL:nil];
    self.statusLabel.text = @"[OFF] Da tat hook";
}

- (void)loadPreview {
    if (!self.baseURL.length) return;
    NSString *streamURL = [NSString stringWithFormat:@"%@/stream?t=%f", self.baseURL, NSDate.date.timeIntervalSince1970];
    NSString *html = [NSString stringWithFormat:
        @"<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<style>html,body{margin:0;width:100%%;height:100%%;background:#000;overflow:hidden}"
        "img{width:100%%;height:100%%;object-fit:contain}</style><img src='%@'>", streamURL];
    [self.preview loadHTMLString:html baseURL:nil];
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
    return [value componentsSeparatedByString:@":"].firstObject ?: value;
}

- (void)loadPrefs {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCPrefsPath];
    NSString *url = prefs[@"baseURL"];
    if ([url isKindOfClass:NSString.class] && url.length) {
        self.baseURL = url;
        self.ipField.text = [self displayIPFromBaseURL:url];
        [self loadPreview];
    }
    self.hookSwitch.on = [prefs[@"enabled"] boolValue];
    self.colorSwitch.on = [prefs[@"colorSync"] boolValue] || !prefs[@"colorSync"];
}

- (void)savePrefs {
    NSDictionary *prefs = @{
        @"baseURL": self.baseURL ?: @"",
        @"enabled": @(self.hookSwitch.on),
        @"colorSync": @(self.colorSwitch.on)
    };
    [prefs writeToFile:VCPrefsPath atomically:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self connect];
    return YES;
}

@end

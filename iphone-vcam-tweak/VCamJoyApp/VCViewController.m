#import "VCViewController.h"

static NSString * const VCPrefsPath = @"/var/mobile/Library/Preferences/local.vcambubble.plist";

@interface VCViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UITextField *ipField;
@property (nonatomic, strong) UISwitch *hookSwitch;
@property (nonatomic, strong) UISwitch *colorSwitch;
@property (nonatomic, strong) UIImageView *previewImage;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) NSString *baseURL;
@end

@implementation VCViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [self colorBg];
    [self buildUI];
    [self loadPrefs];
    [self startPolling];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.scrollView.frame = self.view.bounds;
    self.contentView.frame = CGRectMake(0, 0, self.view.bounds.size.width, 780);
    self.scrollView.contentSize = self.contentView.bounds.size;
}

- (UIColor *)colorBg { return [UIColor colorWithRed:0.035 green:0.045 blue:0.045 alpha:1.0]; }
- (UIColor *)colorCard { return [UIColor colorWithRed:0.105 green:0.12 blue:0.115 alpha:1.0]; }
- (UIColor *)colorGreen { return [UIColor colorWithRed:0.0 green:1.0 blue:0.10 alpha:1.0]; }
- (UIColor *)colorMuted { return [UIColor colorWithWhite:0.66 alpha:1.0]; }

- (void)buildUI {
    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    CGFloat pad = 20;
    CGFloat cardW = width - pad * 2;

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 780)];
    [self.scrollView addSubview:self.contentView];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, 54, cardW, 42)];
    title.text = @"VCamJoy Local";
    title.textColor = self.colorGreen;
    title.font = [UIFont boldSystemFontOfSize:32];
    [self.contentView addSubview:title];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 100, cardW, 24)];
    self.statusLabel.text = @"Chua ket noi PC";
    self.statusLabel.textColor = self.colorGreen;
    self.statusLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.contentView addSubview:self.statusLabel];

    self.detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 126, cardW, 22)];
    self.detailLabel.text = @"Nhap IP PC, bat Stream ON tren PC roi bam Connect.";
    self.detailLabel.textColor = self.colorMuted;
    self.detailLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.contentView addSubview:self.detailLabel];

    UIView *connectCard = [self card:CGRectMake(pad, 166, cardW, 204)];
    [self.contentView addSubview:connectCard];

    UILabel *wifi = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, cardW - 32, 48)];
    wifi.text = @"WiFi Local";
    wifi.textAlignment = NSTextAlignmentCenter;
    wifi.textColor = UIColor.blackColor;
    wifi.font = [UIFont boldSystemFontOfSize:22];
    wifi.backgroundColor = self.colorGreen;
    wifi.layer.cornerRadius = 12;
    wifi.clipsToBounds = YES;
    [connectCard addSubview:wifi];

    UIView *inputShell = [[UIView alloc] initWithFrame:CGRectMake(16, 80, cardW - 32, 52)];
    inputShell.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    inputShell.layer.cornerRadius = 10;
    [connectCard addSubview:inputShell];

    self.ipField = [[UITextField alloc] initWithFrame:CGRectMake(14, 7, inputShell.bounds.size.width - 28, 38)];
    self.ipField.placeholder = @"192.168.1.xx";
    self.ipField.textColor = self.colorGreen;
    self.ipField.tintColor = self.colorGreen;
    self.ipField.font = [UIFont monospacedDigitSystemFontOfSize:21 weight:UIFontWeightBold];
    self.ipField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.ipField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.ipField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.ipField.delegate = self;
    [inputShell addSubview:self.ipField];

    self.connectButton = [self button:@"Connect & Test" color:[UIColor colorWithRed:0.0 green:0.47 blue:1.0 alpha:1.0] frame:CGRectMake(16, 146, cardW - 32, 42)];
    [self.connectButton addTarget:self action:@selector(connect) forControlEvents:UIControlEventTouchUpInside];
    [connectCard addSubview:self.connectButton];

    UIView *switchCard = [self card:CGRectMake(pad, 386, cardW, 142)];
    [self.contentView addSubview:switchCard];
    self.hookSwitch = [self addRow:@"Camera Ao" subtitle:@"Thay frame camera bang anh/video tu PC" y:16 parent:switchCard];
    self.colorSwitch = [self addRow:@"ColorSync" subtitle:@"Dong bo trang thai mau tu PC" y:80 parent:switchCard];

    UIButton *disable = [self button:@"Tat hook khan cap" color:UIColor.redColor frame:CGRectMake(pad, 544, cardW, 52)];
    [disable addTarget:self action:@selector(disableAll) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:disable];

    UILabel *previewTitle = [[UILabel alloc] initWithFrame:CGRectMake(pad, 620, cardW, 24)];
    previewTitle.text = @"Preview PC";
    previewTitle.textColor = UIColor.whiteColor;
    previewTitle.font = [UIFont boldSystemFontOfSize:18];
    [self.contentView addSubview:previewTitle];

    UIView *previewCard = [self card:CGRectMake(pad, 654, cardW, 190)];
    previewCard.backgroundColor = UIColor.blackColor;
    [self.contentView addSubview:previewCard];

    self.previewImage = [[UIImageView alloc] initWithFrame:previewCard.bounds];
    self.previewImage.contentMode = UIViewContentModeScaleAspectFit;
    self.previewImage.backgroundColor = UIColor.blackColor;
    self.previewImage.clipsToBounds = YES;
    [previewCard addSubview:self.previewImage];
}

- (UIView *)card:(CGRect)frame {
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = self.colorCard;
    view.layer.cornerRadius = 16;
    view.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.07].CGColor;
    view.layer.borderWidth = 1;
    return view;
}

- (UIButton *)button:(NSString *)title color:(UIColor *)color frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    button.backgroundColor = color;
    button.layer.cornerRadius = 11;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    return button;
}

- (UISwitch *)addRow:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat)y parent:(UIView *)parent {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, y, parent.bounds.size.width - 96, 26)];
    label.text = title;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:19];
    [parent addSubview:label];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 27, parent.bounds.size.width - 96, 20)];
    sub.text = subtitle;
    sub.textColor = self.colorMuted;
    sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [parent addSubview:sub];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(parent.bounds.size.width - 68, y + 6, 58, 32)];
    sw.onTintColor = self.colorGreen;
    [sw addTarget:self action:@selector(savePrefs) forControlEvents:UIControlEventValueChanged];
    [parent addSubview:sw];
    return sw;
}

- (void)connect {
    self.baseURL = [self normalizedBaseURLFromInput:self.ipField.text.length ? self.ipField.text : self.ipField.placeholder];
    self.ipField.text = [self displayIPFromBaseURL:self.baseURL];
    self.hookSwitch.on = YES;
    [self savePrefs];
    [self fetchStatusOnce];
    [self fetchSnapshotOnce];
}

- (void)disableAll {
    self.hookSwitch.on = NO;
    self.colorSwitch.on = NO;
    [self savePrefs];
    self.previewImage.image = nil;
    self.statusLabel.text = @"Hook da tat";
    self.detailLabel.text = @"Mo lai Camera Ao khi can dung.";
}

- (void)startPolling {
    [self.pollTimer invalidate];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) {
        [self fetchStatusOnce];
        [self fetchSnapshotOnce];
    }];
}

- (void)fetchStatusOnce {
    if (!self.baseURL.length) return;
    NSURL *url = [NSURL URLWithString:[self.baseURL stringByAppendingString:@"/status"]];
    if (!url) return;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, __unused NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !data.length) {
                self.statusLabel.text = @"Khong ket noi duoc PC";
                self.detailLabel.text = @"Kiem tra WiFi, IP va firewall Windows.";
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            BOOL streaming = [json[@"streaming"] boolValue];
            NSNumber *clients = json[@"clients"];
            self.statusLabel.text = streaming ? @"[OK] Dang nhan stream PC" : @"PC dang Stream OFF";
            self.detailLabel.text = [NSString stringWithFormat:@"IP %@ | %@ thiet bi | %@", [self displayIPFromBaseURL:self.baseURL], clients ?: @0, streaming ? @"Camera Ao san sang" : @"Bat Stream ON tren PC"];
        });
    }];
    [task resume];
}

- (void)fetchSnapshotOnce {
    if (!self.baseURL.length) return;
    NSString *urlString = [NSString stringWithFormat:@"%@/snapshot.jpg?t=%lld", self.baseURL, (long long)(NSDate.date.timeIntervalSince1970 * 1000)];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, __unused NSURLResponse *response, NSError *error) {
        if (error || !data.length) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.previewImage.image = image;
        });
    }];
    [task resume];
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
    }
    self.hookSwitch.on = [prefs[@"enabled"] boolValue];
    self.colorSwitch.on = [prefs[@"colorSync"] boolValue] || !prefs[@"colorSync"];
    [self fetchStatusOnce];
    [self fetchSnapshotOnce];
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

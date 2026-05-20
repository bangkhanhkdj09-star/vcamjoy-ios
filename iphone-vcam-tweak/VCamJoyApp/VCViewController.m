#import "VCViewController.h"
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;

static NSString * const VCPrefsPath = @"/var/mobile/Library/Preferences/local.vcambubble.plist";

@interface VCViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UITextField *ipField;
@property (nonatomic, strong) UILabel *connectionValue;
@property (nonatomic, strong) UILabel *dateValue;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UILabel *previewStatus;
@property (nonatomic, strong) UIButton *usbButton;
@property (nonatomic, strong) UIButton *wifiButton;
@property (nonatomic, strong) UIImageView *previewImage;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) NSString *baseURL;
@end

@implementation VCViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [self bg];
    [self buildUI];
    [self loadPrefs];
    [self startPolling];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.scrollView.frame = self.view.bounds;
    self.contentView.frame = CGRectMake(0, 0, self.view.bounds.size.width, 880);
    self.scrollView.contentSize = self.contentView.bounds.size;
}

- (UIColor *)bg { return [UIColor colorWithRed:0.035 green:0.045 blue:0.043 alpha:1]; }
- (UIColor *)panel { return [UIColor colorWithRed:0.075 green:0.085 blue:0.083 alpha:1]; }
- (UIColor *)panel2 { return [UIColor colorWithRed:0.105 green:0.12 blue:0.115 alpha:1]; }
- (UIColor *)green { return [UIColor colorWithRed:0.0 green:1.0 blue:0.15 alpha:1]; }
- (UIColor *)magenta { return [UIColor colorWithRed:1.0 green:0.0 blue:0.95 alpha:1]; }
- (UIColor *)muted { return [UIColor colorWithWhite:0.66 alpha:1]; }

- (void)buildUI {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    CGFloat pad = 18;
    CGFloat cw = w - pad * 2;

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 880)];
    [self.scrollView addSubview:self.contentView];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, 54, cw, 44)];
    title.text = @"NovaCam";
    title.textColor = self.green;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:34];
    title.layer.shadowColor = self.green.CGColor;
    title.layer.shadowRadius = 8;
    title.layer.shadowOpacity = 0.7;
    title.layer.shadowOffset = CGSizeZero;
    [self.contentView addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(pad, 96, cw, 18)];
    subtitle.text = @"> NEURAL INTERFACE v5.3.0 PRO";
    subtitle.textColor = self.muted;
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
    [self.contentView addSubview:subtitle];

    UIView *status = [self box:CGRectMake(pad, 128, cw, 88) border:self.green];
    [self.contentView addSubview:status];
    [self label:@"SYSTEM STATUS" frame:CGRectMake(14, 10, cw - 28, 22) color:UIColor.whiteColor size:14 bold:YES parent:status];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(cw - 30, 15, 10, 10)];
    dot.backgroundColor = self.green;
    dot.layer.cornerRadius = 5;
    [status addSubview:dot];
    self.dateValue = [self label:@"" frame:CGRectMake(14, 42, 150, 18) color:self.green size:11 bold:YES parent:status];
    [self label:@"CONNECTION" frame:CGRectMake(14, 60, 120, 16) color:self.muted size:9 bold:YES parent:status];
    self.connectionValue = [self label:@"OFFLINE" frame:CGRectMake(cw - 142, 50, 120, 20) color:self.green size:11 bold:YES parent:status];
    self.connectionValue.textAlignment = NSTextAlignmentRight;

    UIView *usb = [self box:CGRectMake(pad, 234, cw, 142) border:self.green];
    [self.contentView addSubview:usb];
    [self label:@"USB LINK" frame:CGRectMake(14, 12, 130, 24) color:self.green size:19 bold:YES parent:usb];
    UILabel *badge = [self label:@"PC IP MODE" frame:CGRectMake(cw - 104, 16, 82, 18) color:self.green size:9 bold:YES parent:usb];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.borderWidth = 1;
    badge.layer.borderColor = self.green.CGColor;
    [self label:@"Direct wired connection.\nZero-lag. Start before PC client." frame:CGRectMake(14, 48, cw - 28, 34) color:self.muted size:11 bold:NO parent:usb].numberOfLines = 2;
    self.usbButton = [self button:@"STOP USB MODE" frame:CGRectMake(14, 94, cw - 28, 38) color:self.green text:UIColor.blackColor border:nil];
    [self.usbButton addTarget:self action:@selector(stopModes) forControlEvents:UIControlEventTouchUpInside];
    [usb addSubview:self.usbButton];

    UIView *wifi = [self box:CGRectMake(pad, 394, cw, 218) border:self.magenta];
    [self.contentView addSubview:wifi];
    [self label:@"WIFI LINK" frame:CGRectMake(14, 12, 130, 24) color:self.magenta size:19 bold:YES parent:wifi];
    UILabel *home = [self label:@"HOME" frame:CGRectMake(cw - 78, 16, 58, 18) color:self.magenta size:9 bold:YES parent:wifi];
    home.textAlignment = NSTextAlignmentCenter;
    home.layer.borderWidth = 1;
    home.layer.borderColor = self.magenta.CGColor;
    [self label:@"Connect over LAN to Studio Pro." frame:CGRectMake(14, 48, cw - 28, 18) color:self.muted size:11 bold:NO parent:wifi];
    [self label:@"TARGET SERVER (IP)" frame:CGRectMake(14, 76, cw - 28, 18) color:self.magenta size:10 bold:YES parent:wifi];

    UIView *input = [[UIView alloc] initWithFrame:CGRectMake(14, 98, cw - 28, 46)];
    input.backgroundColor = [UIColor colorWithWhite:0.02 alpha:1];
    input.layer.borderWidth = 1;
    input.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    [wifi addSubview:input];
    [self label:@">" frame:CGRectMake(10, 13, 22, 20) color:self.magenta size:18 bold:YES parent:input];
    self.ipField = [[UITextField alloc] initWithFrame:CGRectMake(36, 5, input.bounds.size.width - 46, 36)];
    self.ipField.placeholder = @"192.168.1.100";
    self.ipField.textColor = UIColor.whiteColor;
    self.ipField.tintColor = self.magenta;
    self.ipField.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightBold];
    self.ipField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.ipField.delegate = self;
    [input addSubview:self.ipField];

    self.wifiButton = [self button:@"START WIFI MODE" frame:CGRectMake(14, 162, cw - 28, 42) color:UIColor.clearColor text:self.magenta border:self.magenta];
    [self.wifiButton addTarget:self action:@selector(startWifiMode) forControlEvents:UIControlEventTouchUpInside];
    [wifi addSubview:self.wifiButton];

    UIView *previewBox = [self box:CGRectMake(pad, 632, cw, 180) border:[UIColor colorWithWhite:1 alpha:0.12]];
    previewBox.backgroundColor = UIColor.blackColor;
    [self.contentView addSubview:previewBox];
    self.previewImage = [[UIImageView alloc] initWithFrame:previewBox.bounds];
    self.previewImage.contentMode = UIViewContentModeScaleAspectFit;
    self.previewImage.clipsToBounds = YES;
    [previewBox addSubview:self.previewImage];

    self.previewStatus = [self label:@"NO PREVIEW" frame:CGRectMake(14, 12, cw - 28, 20) color:self.muted size:12 bold:YES parent:previewBox];
    self.previewStatus.textAlignment = NSTextAlignmentCenter;

    self.hintLabel = [self label:@"Open Firefox/Safari webcam test after START WIFI MODE." frame:CGRectMake(pad, 824, cw, 30) color:self.muted size:12 bold:NO parent:self.contentView];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
}

- (UIView *)box:(CGRect)frame border:(UIColor *)border {
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = self.panel;
    view.layer.cornerRadius = 2;
    view.layer.borderWidth = 1;
    view.layer.borderColor = border.CGColor;
    return view;
}

- (UILabel *)label:(NSString *)text frame:(CGRect)frame color:(UIColor *)color size:(CGFloat)size bold:(BOOL)bold parent:(UIView *)parent {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = color;
    label.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
    [parent addSubview:label];
    return label;
}

- (UIButton *)button:(NSString *)title frame:(CGRect)frame color:(UIColor *)color text:(UIColor *)textColor border:(UIColor *)border {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    button.backgroundColor = color;
    button.layer.cornerRadius = 5;
    if (border) {
        button.layer.borderWidth = 2;
        button.layer.borderColor = border.CGColor;
    }
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:textColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];
    return button;
}

- (void)startWifiMode {
    self.baseURL = [self normalizedBaseURLFromInput:self.ipField.text.length ? self.ipField.text : self.ipField.placeholder];
    self.ipField.text = [self displayIPFromBaseURL:self.baseURL];
    [self saveEnabled:YES colorSync:YES];
    self.connectionValue.text = @"WIFI ACTIVE";
    self.hintLabel.text = @"Restarting camera daemon. Reopen Camera after 2 seconds.";
    [self.wifiButton setTitle:@"STOP WIFI MODE" forState:UIControlStateNormal];
    [self restartCameraDaemon];
    [self fetchStatusOnce];
    [self fetchSnapshotOnce];
}

- (void)stopModes {
    [self saveEnabled:NO colorSync:NO];
    self.connectionValue.text = @"OFFLINE";
    self.hintLabel.text = @"Open Firefox/Safari webcam test after START WIFI MODE.";
    self.previewImage.image = nil;
    self.previewStatus.hidden = NO;
    [self.wifiButton setTitle:@"START WIFI MODE" forState:UIControlStateNormal];
    [self restartCameraDaemon];
}

- (void)restartCameraDaemon {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        pid_t pid = 0;
        char *argv[] = {"/usr/bin/killall", "-9", "mediaserverd", NULL};
        int status = posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, argv, environ);
        if (status == 0) {
            waitpid(pid, NULL, 0);
        }
    });
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
                self.connectionValue.text = @"NO PC";
                return;
            }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            BOOL streaming = [json[@"streaming"] boolValue];
            self.connectionValue.text = streaming ? @"WIFI ACTIVE" : @"PC STREAM OFF";
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
            self.previewStatus.hidden = YES;
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
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"dd/MM/yyyy";
    self.dateValue.text = [NSString stringWithFormat:@"LOCAL %@", [formatter stringFromDate:NSDate.date]];

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCPrefsPath];
    NSString *url = prefs[@"baseURL"];
    if ([url isKindOfClass:NSString.class] && url.length) {
        self.baseURL = url;
        self.ipField.text = [self displayIPFromBaseURL:url];
    }
    BOOL enabled = [prefs[@"enabled"] boolValue];
    self.connectionValue.text = enabled ? @"WIFI ACTIVE" : @"OFFLINE";
    [self.wifiButton setTitle:(enabled ? @"STOP WIFI MODE" : @"START WIFI MODE") forState:UIControlStateNormal];
    [self fetchStatusOnce];
    [self fetchSnapshotOnce];
}

- (void)saveEnabled:(BOOL)enabled colorSync:(BOOL)colorSync {
    NSDictionary *prefs = @{
        @"baseURL": self.baseURL ?: @"",
        @"enabled": @(enabled),
        @"colorSync": @(colorSync)
    };
    [prefs writeToFile:VCPrefsPath atomically:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self startWifiMode];
    return YES;
}

@end

#import "MainViewController.h"
#import "VCamReceiver.h"
#import "VCamHook.h"
#import <AVFoundation/AVFoundation.h>

static NSString *const kSuite = @"com.vcamjoy.prefs";
static NSData *kSOI = nil;
static NSData *kEOI = nil;

@interface MainViewController () <NSURLSessionDataDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (strong) NSURLSession *ses;
@property (strong) NSURLSessionDataTask *task;
@property (strong) NSMutableData *buf;
@property (assign) BOOL wifiOn;
@property (strong) UIImage *localImg;
@property (strong) AVPlayer *player;
@property (strong) AVPlayerLayer *playerLayer;
@property (assign) BOOL playing;
@property (strong) NSString *mediaName;
@property (assign) BOOL vcamOn;
@property (strong) AVCaptureSession *capSes;
@property (strong) CADisplayLink *csLink;
@property (strong) UILabel *lblStatus;
@property (strong) UILabel *lblConn;
@property (strong) UITextField *ipField;
@property (strong) UIButton *wifiBtn;
@property (strong) UILabel *lblMedia;
@property (strong) UIButton *btnPlay;
@property (strong) UISwitch *vcamSw;
@property (strong) UISwitch *csSw;
@property (strong) UIImageView *prevImg;
@property (strong) UILabel *fpsLbl;
@property (strong) UIView *prevCont;
@property (assign) NSUInteger fpsN;
@property (assign) NSTimeInterval fpsT;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBarHidden = YES;
    self.view.backgroundColor = [UIColor blackColor];
    uint8_t s[] = {0xFF, 0xD8}, e[] = {0xFF, 0xD9};
    kSOI = [NSData dataWithBytes:s length:2];
    kEOI = [NSData dataWithBytes:e length:2];
    self.buf = [NSMutableData data];
    [self buildUI];
    [self loadPrefs];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKB)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)dismissKB { [self.view endEditing:YES]; }

#pragma mark - Build UI

- (void)buildUI {
    CGFloat W = self.view.bounds.size.width;
    CGFloat cw = W - 32;

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    sv.backgroundColor = [UIColor blackColor];
    sv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:sv];

    UIView *c = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 1600)];
    c.backgroundColor = [UIColor blackColor];
    [sv addSubview:c];

    CGFloat y = 50;

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 200, 38)];
    title.text = @"VCamJoy";
    title.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    title.font = [UIFont boldSystemFontOfSize:28];
    [c addSubview:title];
    y += 46;

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(16, y, cw, 16)];
    sub.text = @"> VIRTUAL CAMERA v2.0";
    sub.textColor = [UIColor grayColor];
    sub.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    [c addSubview:sub];
    y += 28;

    // STATUS card
    CGFloat prevH = cw * 9 / 16;
    UIView *sc = [self makeCard:CGRectMake(16, y, cw, prevH + 86) borderColor:[UIColor whiteColor]];
    [c addSubview:sc];

    UILabel *sTitle = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, 150, 20)];
    sTitle.text = @"SYSTEM STATUS";
    sTitle.textColor = [UIColor whiteColor];
    sTitle.font = [UIFont boldSystemFontOfSize:13];
    [sc addSubview:sTitle];

    self.lblStatus = [[UILabel alloc] initWithFrame:CGRectMake(14, 34, cw - 120, 16)];
    self.lblStatus.text = @"CONNECTION";
    self.lblStatus.textColor = [UIColor grayColor];
    self.lblStatus.font = [UIFont systemFontOfSize:11];
    [sc addSubview:self.lblStatus];

    self.lblConn = [[UILabel alloc] initWithFrame:CGRectMake(cw - 110, 34, 96, 16)];
    self.lblConn.text = @"STANDBY";
    self.lblConn.textColor = [UIColor grayColor];
    self.lblConn.font = [UIFont boldSystemFontOfSize:11];
    self.lblConn.textAlignment = NSTextAlignmentRight;
    [sc addSubview:self.lblConn];

    self.prevCont = [[UIView alloc] initWithFrame:CGRectMake(14, 56, cw - 28, prevH)];
    self.prevCont.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    self.prevCont.layer.cornerRadius = 8;
    self.prevCont.clipsToBounds = YES;
    [sc addSubview:self.prevCont];

    self.prevImg = [[UIImageView alloc] initWithFrame:self.prevCont.bounds];
    self.prevImg.contentMode = UIViewContentModeScaleAspectFill;
    self.prevImg.clipsToBounds = YES;
    [self.prevCont addSubview:self.prevImg];

    UILabel *ph = [[UILabel alloc] initWithFrame:self.prevCont.bounds];
    ph.text = @"NO FEED";
    ph.textColor = [UIColor grayColor];
    ph.textAlignment = NSTextAlignmentCenter;
    ph.font = [UIFont systemFontOfSize:13];
    ph.tag = 77;
    [self.prevCont addSubview:ph];

    self.fpsLbl = [[UILabel alloc] initWithFrame:CGRectMake(6, 4, 80, 14)];
    self.fpsLbl.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    self.fpsLbl.font = [UIFont systemFontOfSize:9];
    [self.prevCont addSubview:self.fpsLbl];

    y += prevH + 86 + 8;

    // WIFI card
    UIView *wc = [self makeCard:CGRectMake(16, y, cw, 192) borderColor:[UIColor magentaColor]];
    [c addSubview:wc];

    UILabel *wTitle = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, 120, 20)];
    wTitle.text = @"WIFI LINK";
    wTitle.textColor = [UIColor magentaColor];
    wTitle.font = [UIFont boldSystemFontOfSize:13];
    [wc addSubview:wTitle];

    UILabel *wBadge = [self makeBadge:@"MJPEG" color:[UIColor magentaColor] frame:CGRectMake(cw - 76, 8, 62, 22)];
    [wc addSubview:wBadge];

    UILabel *wDesc = [[UILabel alloc] initWithFrame:CGRectMake(14, 36, cw - 28, 14)];
    wDesc.text = @"Nhận MJPEG stream từ VCamJoy PC qua WiFi.";
    wDesc.textColor = [UIColor grayColor];
    wDesc.font = [UIFont systemFontOfSize:10];
    [wc addSubview:wDesc];

    UILabel *ipHdr = [[UILabel alloc] initWithFrame:CGRectMake(14, 56, 150, 12)];
    ipHdr.text = @"TARGET SERVER (IP)";
    ipHdr.textColor = [UIColor magentaColor];
    ipHdr.font = [UIFont systemFontOfSize:9];
    [wc addSubview:ipHdr];

    UIView *ipBg = [[UIView alloc] initWithFrame:CGRectMake(14, 72, cw - 28, 42)];
    ipBg.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    ipBg.layer.cornerRadius = 6;
    ipBg.layer.borderWidth = 1;
    ipBg.layer.borderColor = [UIColor magentaColor].CGColor;
    [wc addSubview:ipBg];

    UILabel *gt = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 20, 42)];
    gt.text = @">";
    gt.textColor = [UIColor magentaColor];
    gt.font = [UIFont boldSystemFontOfSize:16];
    [ipBg addSubview:gt];

    self.ipField = [[UITextField alloc] initWithFrame:CGRectMake(30, 0, ipBg.frame.size.width - 38, 42)];
    self.ipField.textColor = [UIColor whiteColor];
    self.ipField.font = [UIFont boldSystemFontOfSize:17];
    self.ipField.keyboardType = UIKeyboardTypeURL;
    self.ipField.keyboardAppearance = UIKeyboardAppearanceDark;
    self.ipField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.ipField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.ipField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"192.168.1.x" attributes:@{NSForegroundColorAttributeName: [UIColor grayColor]}];
    [ipBg addSubview:self.ipField];

    self.wifiBtn = [self makeOutlineButton:@"START WIFI MODE _"
                                     color:[UIColor magentaColor]
                                     frame:CGRectMake(14, 124, cw - 28, 50)
                                    action:@selector(onWifi)];
    [wc addSubview:self.wifiBtn];
    y += 192 + 8;

    // LOCAL MEDIA card
    UIView *lc = [self makeCard:CGRectMake(16, y, cw, 168) borderColor:[UIColor cyanColor]];
    [c addSubview:lc];

    UILabel *lTitle = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, 150, 20)];
    lTitle.text = @"LOCAL MEDIA";
    lTitle.textColor = [UIColor cyanColor];
    lTitle.font = [UIFont boldSystemFontOfSize:13];
    [lc addSubview:lTitle];

    UILabel *lBadge = [self makeBadge:@"THƯ VIỆN" color:[UIColor cyanColor] frame:CGRectMake(cw - 86, 8, 72, 22)];
    [lc addSubview:lBadge];

    UILabel *lDesc = [[UILabel alloc] initWithFrame:CGRectMake(14, 36, cw - 28, 14)];
    lDesc.text = @"Phát ảnh/video từ thư viện làm nguồn camera ảo.";
    lDesc.textColor = [UIColor grayColor];
    lDesc.font = [UIFont systemFontOfSize:10];
    [lc addSubview:lDesc];

    self.lblMedia = [[UILabel alloc] initWithFrame:CGRectMake(14, 56, cw - 28, 16)];
    self.lblMedia.text = @"Chưa chọn media";
    self.lblMedia.textColor = [UIColor grayColor];
    self.lblMedia.font = [UIFont systemFontOfSize:11];
    [lc addSubview:self.lblMedia];

    CGFloat bw = (cw - 38) / 2;
    self.btnPlay = [self makeFillButton:@"▶  Phát"
                                     bg:[UIColor colorWithRed:0 green:1 blue:0.53 alpha:1]
                                  frame:CGRectMake(14, 80, bw, 46)
                                 action:@selector(onPlay)];
    [lc addSubview:self.btnPlay];

    UIButton *btnChange = [self makeFillButton:@"Đổi media"
                                            bg:[UIColor cyanColor]
                                         frame:CGRectMake(14 + bw + 10, 80, bw, 46)
                                        action:@selector(onPickMedia)];
    [lc addSubview:btnChange];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(14, 134, cw - 28, 14)];
    hint.text = @"👉 Chọn ảnh/video rồi bấm Phát";
    hint.textColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1];
    hint.font = [UIFont systemFontOfSize:10];
    [lc addSubview:hint];
    y += 168 + 8;

    // SETTINGS card
    UIView *setc = [self makeCard:CGRectMake(16, y, cw, 162) borderColor:[UIColor whiteColor]];
    [c addSubview:setc];

    UILabel *setTitle = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, 100, 20)];
    setTitle.text = @"CÀI ĐẶT";
    setTitle.textColor = [UIColor whiteColor];
    setTitle.font = [UIFont boldSystemFontOfSize:13];
    [setc addSubview:setTitle];

    // Camera Ao row
    UIView *r1 = [[UIView alloc] initWithFrame:CGRectMake(14, 36, cw - 28, 50)];
    r1.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    r1.layer.cornerRadius = 8;
    [setc addSubview:r1];
    UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, cw - 100, 50)];
    l1.text = @"Bật Camera Ảo";
    l1.textColor = [UIColor whiteColor];
    l1.font = [UIFont boldSystemFontOfSize:15];
    [r1 addSubview:l1];
    self.vcamSw = [[UISwitch alloc] init];
    self.vcamSw.center = CGPointMake(cw - 28 - 30, 25);
    self.vcamSw.onTintColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    [self.vcamSw addTarget:self action:@selector(onVcam:) forControlEvents:UIControlEventValueChanged];
    [r1 addSubview:self.vcamSw];

    // ColorSync row
    UIView *r2 = [[UIView alloc] initWithFrame:CGRectMake(14, 96, cw - 28, 50)];
    r2.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    r2.layer.cornerRadius = 8;
    [setc addSubview:r2];
    UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, cw - 100, 50)];
    l2.text = @"ColorSync (60Hz)";
    l2.textColor = [UIColor whiteColor];
    l2.font = [UIFont boldSystemFontOfSize:15];
    [r2 addSubview:l2];
    self.csSw = [[UISwitch alloc] init];
    self.csSw.center = CGPointMake(cw - 28 - 30, 25);
    self.csSw.onTintColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    [self.csSw addTarget:self action:@selector(onCS:) forControlEvents:UIControlEventValueChanged];
    [r2 addSubview:self.csSw];
    y += 162 + 8;

    // Bottom buttons
    CGFloat bw2 = (cw - 10) / 2;
    UIButton *btnS = [self makeFillButton:@"📞  Hỗ trợ" bg:[UIColor cyanColor]
                                    frame:CGRectMake(16, y, bw2, 46) action:@selector(onSupport)];
    [c addSubview:btnS];
    UIButton *btnQ = [self makeFillButton:@"● Thoát"
                                       bg:[UIColor colorWithRed:1 green:0.2 blue:0.26 alpha:1]
                                    frame:CGRectMake(16 + bw2 + 10, y, bw2, 46) action:@selector(onQuit)];
    [c addSubview:btnQ];
    y += 56;

    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(16, y, cw, 18)];
    ver.text = @"v2.0 VCamJoy  •  iOS 15-16 JB";
    ver.textColor = [UIColor grayColor];
    ver.font = [UIFont systemFontOfSize:9];
    ver.textAlignment = NSTextAlignmentCenter;
    [c addSubview:ver];
    y += 30;

    sv.contentSize = CGSizeMake(W, y);
}

#pragma mark - UI Helpers

- (UIView *)makeCard:(CGRect)f borderColor:(UIColor *)col {
    UIView *v = [[UIView alloc] initWithFrame:f];
    v.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    v.layer.cornerRadius = 12;
    v.clipsToBounds = YES;
    v.layer.borderWidth = 1;
    v.layer.borderColor = [col colorWithAlphaComponent:0.3].CGColor;
    return v;
}

- (UILabel *)makeBadge:(NSString *)t color:(UIColor *)c frame:(CGRect)f {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.text = t; l.textColor = c;
    l.font = [UIFont systemFontOfSize:9];
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.borderWidth = 1;
    l.layer.borderColor = c.CGColor;
    l.layer.cornerRadius = 3;
    l.clipsToBounds = YES;
    return l;
}

- (UIButton *)makeOutlineButton:(NSString *)t color:(UIColor *)c frame:(CGRect)f action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    b.backgroundColor = [UIColor clearColor];
    b.layer.borderWidth = 2;
    b.layer.borderColor = c.CGColor;
    b.layer.cornerRadius = 8;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:c forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIButton *)makeFillButton:(NSString *)t bg:(UIColor *)bg frame:(CGRect)f action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    b.backgroundColor = bg;
    b.layer.cornerRadius = 10;
    b.clipsToBounds = YES;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - Actions

- (void)onWifi {
    [self dismissKB];
    if (self.wifiOn) { [self wifiStop]; return; }
    NSString *ip = [self.ipField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!ip.length) { [self shake:self.ipField]; return; }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:8080/stream", ip]];
    if (!url) return;
    [self savePrefs];
    [[VCamReceiver sharedReceiver] startWithURL:url];
    [self wifiStart:url];
}

- (void)wifiStart:(NSURL *)url {
    [self.task cancel];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 10;
    cfg.timeoutIntervalForResource = 86400;
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    self.ses = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.task = [self.ses dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
    [self.task resume];
    self.lblConn.text = @"CONNECTING";
    self.lblConn.textColor = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1];
    [self.wifiBtn setTitle:@"NGẮT KẾT NỐI _" forState:UIControlStateNormal];
    self.wifiBtn.layer.borderColor = [UIColor colorWithRed:1 green:0.2 blue:0.26 alpha:1].CGColor;
    [self.wifiBtn setTitleColor:[UIColor colorWithRed:1 green:0.2 blue:0.26 alpha:1] forState:UIControlStateNormal];
}

- (void)wifiStop {
    [self.task cancel]; self.task = nil; self.wifiOn = NO;
    [[VCamReceiver sharedReceiver] stop];
    self.lblConn.text = @"STANDBY";
    self.lblConn.textColor = [UIColor grayColor];
    self.lblStatus.text = @"CONNECTION";
    self.lblStatus.textColor = [UIColor grayColor];
    [self.wifiBtn setTitle:@"START WIFI MODE _" forState:UIControlStateNormal];
    self.wifiBtn.layer.borderColor = [UIColor magentaColor].CGColor;
    [self.wifiBtn setTitleColor:[UIColor magentaColor] forState:UIControlStateNormal];
}

- (void)onPickMedia {
    UIImagePickerController *pk = [[UIImagePickerController alloc] init];
    pk.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    pk.mediaTypes = @[@"public.image", @"public.movie"];
    pk.delegate = self;
    [self presentViewController:pk animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)pk didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [pk dismissViewControllerAnimated:YES completion:nil];
    NSString *type = info[UIImagePickerControllerMediaType];
    if ([type isEqualToString:@"public.image"]) {
        self.localImg = info[UIImagePickerControllerOriginalImage];
        self.player = nil;
        self.mediaName = @"Ảnh đã chọn";
    } else {
        NSURL *u = info[UIImagePickerControllerMediaURL];
        if (!u) return;
        self.player = [AVPlayer playerWithURL:u];
        self.localImg = nil;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerEnd:)
            name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
        self.mediaName = u.lastPathComponent ?: @"Video";
    }
    self.lblMedia.text = self.mediaName;
    self.lblMedia.textColor = [UIColor cyanColor];
    [self.btnPlay setTitle:@"▶  Phát" forState:UIControlStateNormal];
    self.btnPlay.backgroundColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)pk {
    [pk dismissViewControllerAnimated:YES completion:nil];
}

- (void)onPlay {
    if (self.playing) { [self mediaStop]; return; }
    if (!self.localImg && !self.player) { [self onPickMedia]; return; }
    [self mediaStart];
}

- (void)mediaStart {
    self.playing = YES;
    [self.btnPlay setTitle:@"■  Dừng" forState:UIControlStateNormal];
    self.btnPlay.backgroundColor = [UIColor colorWithRed:1 green:0.2 blue:0.26 alpha:1];
    self.lblMedia.text = [NSString stringWithFormat:@"▶ %@", self.mediaName];
    [[self.prevImg.superview viewWithTag:77] setHidden:YES];
    if (self.localImg) {
        self.prevImg.image = self.localImg;
    } else if (self.player) {
        if (self.playerLayer) [self.playerLayer removeFromSuperlayer];
        self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        self.playerLayer.frame = self.prevCont.bounds;
        self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.prevCont.layer insertSublayer:self.playerLayer atIndex:0];
        [self.player play];
    }
}

- (void)mediaStop {
    self.playing = NO;
    [self.btnPlay setTitle:@"▶  Phát" forState:UIControlStateNormal];
    self.btnPlay.backgroundColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    self.lblMedia.text = self.mediaName ?: @"Chưa chọn media";
    [self.player pause];
    self.prevImg.image = nil;
    [[self.prevImg.superview viewWithTag:77] setHidden:NO];
}

- (void)playerEnd:(NSNotification *)n {
    [self.player seekToTime:kCMTimeZero];
    [self.player play];
}

- (void)onVcam:(UISwitch *)sw {
    self.vcamOn = sw.isOn;
    [VCamHook setEnabled:sw.isOn];
    if (sw.isOn) {
        NSString *ip = [self.ipField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (ip.length) {
            [VCamHook setStreamURL:[NSString stringWithFormat:@"http://%@:8080/stream", ip]];
        }
        self.lblStatus.text = @"CAMERA ẢO ĐANG HOẠT ĐỘNG";
        self.lblStatus.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    } else {
        [VCamHook setStreamURL:nil];
        self.lblStatus.text = @"CONNECTION";
        self.lblStatus.textColor = [UIColor grayColor];
    }
    [self savePrefs];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vcamjoy.prefschanged"), NULL, NULL, YES);
}

- (void)onCS:(UISwitch *)sw {
    if (sw.isOn) {
        self.csLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(csTick)];
        self.csLink.preferredFramesPerSecond = 60;
        [self.csLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else {
        [self.csLink invalidate]; self.csLink = nil;
    }
}

- (void)csTick {
    UIImage *img = self.prevImg.image; if (!img) return;
    CGImageRef cg = img.CGImage; if (!cg) return;
    CGFloat iw = CGImageGetWidth(cg), ih = CGImageGetHeight(cg);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    uint8_t px[4] = {0};
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, cs,
        kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(cs);
    if (!ctx) return;
    CGContextDrawImage(ctx, CGRectMake(-iw/2, -ih/2, iw, ih), cg);
    CGContextRelease(ctx);
    NSString *ip = self.ipField.text;
    if (!ip.length) return;
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:8080/settings", ip]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [[NSString stringWithFormat:@"{\"rgb_r\":%d,\"rgb_g\":%d,\"rgb_b\":%d,\"rgb_sync\":true}",
                     px[0], px[1], px[2]] dataUsingEncoding:NSUTF8StringEncoding];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req] resume];
}

- (void)onSupport {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com"]
                                       options:@{} completionHandler:nil];
}

- (void)onQuit { exit(0); }

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t
didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h {
    self.wifiOn = YES;
    [self.buf setLength:0];
    self.fpsN = 0; self.fpsT = CACurrentMediaTime();
    h(NSURLSessionResponseAllow);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.lblConn.text = @"CONNECTED";
        self.lblConn.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
        self.lblStatus.text = [NSString stringWithFormat:@"WiFi → %@", self.ipField.text];
        self.lblStatus.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
        [[self.prevImg.superview viewWithTag:77] setHidden:YES];
    });
}

- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    [self.buf appendData:d];
    [self parseFrames];
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
    self.wifiOn = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (e && e.code != NSURLErrorCancelled) {
            self.lblConn.text = @"ERROR";
            self.lblConn.textColor = [UIColor colorWithRed:1 green:0.2 blue:0.26 alpha:1];
        }
    });
}

- (void)parseFrames {
    while (YES) {
        NSRange r1 = [self.buf rangeOfData:kSOI options:0 range:NSMakeRange(0, self.buf.length)];
        if (r1.location == NSNotFound) { [self.buf setLength:0]; break; }
        NSRange sr = NSMakeRange(r1.location + 2, self.buf.length - r1.location - 2);
        NSRange r2 = [self.buf rangeOfData:kEOI options:0 range:sr];
        if (r2.location == NSNotFound) break;
        NSUInteger end = r2.location + 2;
        NSData *jpeg = [self.buf subdataWithRange:NSMakeRange(r1.location, end - r1.location)];
        [self.buf replaceBytesInRange:NSMakeRange(0, end) withBytes:NULL length:0];
        UIImage *img = [UIImage imageWithData:jpeg];
        if (!img) continue;
        self.fpsN++;
        NSTimeInterval now = CACurrentMediaTime();
        if (now - self.fpsT >= 1.0) {
            double fps = self.fpsN / (now - self.fpsT);
            self.fpsN = 0; self.fpsT = now;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.fpsLbl.text = [NSString stringWithFormat:@"%.0f fps", fps];
            });
        }
        dispatch_async(dispatch_get_main_queue(), ^{ self.prevImg.image = img; });
    }
}

#pragma mark - Prefs

- (void)savePrefs {
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
    if (self.ipField.text.length)
        [p setObject:[NSString stringWithFormat:@"http://%@:8080/stream", self.ipField.text] forKey:@"streamURL"];
    [p setBool:self.vcamSw.isOn forKey:@"vcamEnabled"];
    [p synchronize];
}

- (void)loadPrefs {
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
    NSString *url = [p stringForKey:@"streamURL"];
    if (url) {
        NSURL *u = [NSURL URLWithString:url];
        self.ipField.text = u.host ?: @"";
    }
    self.vcamSw.on = [p boolForKey:@"vcamEnabled"];
}

- (void)shake:(UIView *)v {
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    a.duration = 0.4;
    a.values = @[@(-8), @(8), @(-6), @(6), @(-3), @(3), @0];
    [v.layer addAnimation:a forKey:@"shake"];
}

@end

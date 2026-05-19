#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>

// ═══════════════════════════════════════
//  STATE
// ═══════════════════════════════════════
static UIImage       *gFrame    = nil;
static NSLock        *gLock     = nil;
static NSMutableData *gBuf      = nil;
static NSData        *kSOI      = nil;
static NSData        *kEOI      = nil;
static BOOL           gEnabled  = NO;
static NSString      *gURL      = nil;
static NSURLSession  *gSes      = nil;
static NSURLSessionDataTask *gTask = nil;
static NSUInteger     gFpsCount = 0;
static NSTimeInterval gFpsTime  = 0;

// ═══════════════════════════════════════
//  MJPEG RECEIVER
// ═══════════════════════════════════════
@interface VCamReceiver : NSObject <NSURLSessionDataDelegate>
+ (instancetype)shared;
- (void)startWithURL:(NSString *)url;
- (void)stop;
@end

@implementation VCamReceiver
+ (instancetype)shared {
    static VCamReceiver *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    uint8_t s[] = {0xFF,0xD8}, e[] = {0xFF,0xD9};
    kSOI = [NSData dataWithBytes:s length:2];
    kEOI = [NSData dataWithBytes:e length:2];
    gBuf = [NSMutableData data];
    gLock = [NSLock new];
    return self;
}
- (void)startWithURL:(NSString *)urlStr {
    [self stop];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest = 10;
    cfg.timeoutIntervalForResource = 86400;
    gSes = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    gTask = [gSes dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
    [gTask resume];
    NSLog(@"[VCamJoy] Stream started: %@", urlStr);
}
- (void)stop {
    [gTask cancel]; gTask = nil;
    [gBuf setLength:0];
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t
didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h {
    [gBuf setLength:0]; h(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    [gBuf appendData:d];
    while (YES) {
        NSRange r1 = [gBuf rangeOfData:kSOI options:0 range:NSMakeRange(0,gBuf.length)];
        if (r1.location == NSNotFound) { [gBuf setLength:0]; break; }
        NSRange sr = NSMakeRange(r1.location+2, gBuf.length-r1.location-2);
        NSRange r2 = [gBuf rangeOfData:kEOI options:0 range:sr];
        if (r2.location == NSNotFound) break;
        NSUInteger end = r2.location+2;
        NSData *jpeg = [gBuf subdataWithRange:NSMakeRange(r1.location, end-r1.location)];
        [gBuf replaceBytesInRange:NSMakeRange(0,end) withBytes:NULL length:0];
        UIImage *img = [UIImage imageWithData:jpeg];
        if (!img) continue;
        [gLock lock]; gFrame = img; [gLock unlock];
        gFpsCount++;
    }
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
    if (e && e.code != NSURLErrorCancelled && gEnabled && gURL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [[VCamReceiver shared] startWithURL:gURL];
        });
    }
}
@end

// ═══════════════════════════════════════
//  IMAGE → CMSampleBuffer
// ═══════════════════════════════════════
static CMSampleBufferRef imageToSampleBuffer(UIImage *image) CF_RETURNS_RETAINED {
    CGImageRef cg = image.CGImage; if (!cg) return NULL;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    NSDictionary *a = @{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,
                        (id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
    CVPixelBufferRef pb = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)a,&pb) != kCVReturnSuccess) return NULL;
    CVPixelBufferLockBaseAddress(pb,0);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb),w,h,8,
        CVPixelBufferGetBytesPerRow(pb),cs,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),cg);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pb,0);
    CMVideoFormatDescriptionRef fd = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pb,&fd);
    if (!fd) { CVPixelBufferRelease(pb); return NULL; }
    CMSampleTimingInfo ti = {CMTimeMake(1,30),
        CMTimeMakeWithSeconds(CACurrentMediaTime(),90000),kCMTimeInvalid};
    CMSampleBufferRef sb = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,pb,true,NULL,NULL,fd,&ti,&sb);
    CFRelease(fd); CVPixelBufferRelease(pb);
    return sb;
}

// ═══════════════════════════════════════
//  BUBBLE WINDOW
// ═══════════════════════════════════════
static UIWindow    *gWin    = nil;
static UIWindow    *gPanel  = nil;
static UIButton    *gBubble = nil;
static UITextField *gIPField = nil;
static UISwitch    *gSwitch  = nil;
static UILabel     *gStatus  = nil;
static UIImageView *gPreview = nil;
static UILabel     *gFpsLabel = nil;
static UIView      *gDot    = nil;
static BOOL         gPanelOpen = NO;

static void updateDot(void) {
    if (!gDot) return;
    [gLock lock]; BOOL hasFrame = gFrame != nil; [gLock unlock];
    UIColor *c = gEnabled && hasFrame ?
        [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1] :
        (gEnabled ? [UIColor yellowColor] : [UIColor grayColor]);
    gDot.backgroundColor = c;
}

static void showPanel(void);
static void hidePanel(void);

static void showBubble(void) {
    if (gWin) return;
    gWin = [[UIWindow alloc] initWithFrame:CGRectMake(10, 120, 64, 64)];
    gWin.windowLevel = 1000000;
    gWin.backgroundColor = [UIColor clearColor];
    gWin.hidden = NO;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor clearColor];
    gWin.rootViewController = vc;

    gBubble = [UIButton buttonWithType:UIButtonTypeCustom];
    gBubble.frame = CGRectMake(0,0,64,64);
    gBubble.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.95];
    gBubble.layer.cornerRadius = 32;
    gBubble.layer.borderWidth = 2.5;
    gBubble.layer.borderColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:0.8].CGColor;
    gBubble.layer.shadowColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:0.5].CGColor;
    gBubble.layer.shadowRadius = 8;
    gBubble.layer.shadowOpacity = 1;
    gBubble.layer.shadowOffset = CGSizeZero;

    UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(0,6,64,30)];
    icon.text = @"🎥"; icon.textAlignment = NSTextAlignmentCenter;
    icon.font = [UIFont systemFontOfSize:24];
    [gBubble addSubview:icon];

    gDot = [[UIView alloc] initWithFrame:CGRectMake(27,40,10,10)];
    gDot.backgroundColor = [UIColor grayColor];
    gDot.layer.cornerRadius = 5;
    [gBubble addSubview:gDot];

    [gBubble addTarget:gBubble action:@selector(vcamTap) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:gBubble action:@selector(vcamDrag:)];
    [gBubble addGestureRecognizer:pan];
    [vc.view addSubview:gBubble];
}

// Category on UIButton for tap/drag
@interface UIButton (VCam)
- (void)vcamTap;
- (void)vcamDrag:(UIPanGestureRecognizer *)pan;
@end
@implementation UIButton (VCam)
- (void)vcamTap {
    if (gPanelOpen) hidePanel(); else showPanel();
}
- (void)vcamDrag:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:gWin];
    CGRect f = gWin.frame;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    f.origin.x = MAX(0, MIN(sc.width-64, f.origin.x+t.x));
    f.origin.y = MAX(40, MIN(sc.height-64, f.origin.y+t.y));
    gWin.frame = f;
    [pan setTranslation:CGPointZero inView:gWin];
}
@end

static void showPanel(void) {
    if (gPanelOpen) return;
    gPanelOpen = YES;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    CGFloat pw = MIN(sc.width-32, 340);
    CGFloat ph = 460;

    gPanel = [[UIWindow alloc] initWithFrame:CGRectMake((sc.width-pw)/2,(sc.height-ph)/2,pw,ph)];
    gPanel.windowLevel = 999999;
    gPanel.backgroundColor = [UIColor clearColor];
    gPanel.hidden = NO;

    UIViewController *vc = [UIViewController new];
    UIView *bg = [[UIView alloc] initWithFrame:CGRectMake(0,0,pw,ph)];
    bg.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.07 alpha:0.97];
    bg.layer.cornerRadius = 18;
    bg.layer.borderWidth = 1;
    bg.layer.borderColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:0.3].CGColor;
    bg.clipsToBounds = YES;
    vc.view.backgroundColor = [UIColor clearColor];
    [vc.view addSubview:bg];
    gPanel.rootViewController = vc;

    CGFloat cw = pw-28; CGFloat y = 14;

    // Title + close
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14,y,cw-40,30)];
    title.text = @"VCamJoy";
    title.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    title.font = [UIFont boldSystemFontOfSize:22];
    [bg addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(pw-46,y,32,30);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:18];
    [close setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    [close addTarget:close action:@selector(vcamClose) forControlEvents:UIControlEventTouchUpInside];
    [bg addSubview:close];
    y += 38;

    // Preview
    CGFloat prevH = cw * 9/16;
    UIView *prevBox = [[UIView alloc] initWithFrame:CGRectMake(14,y,cw,prevH)];
    prevBox.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1];
    prevBox.layer.cornerRadius = 10;
    prevBox.clipsToBounds = YES;
    [bg addSubview:prevBox];

    gPreview = [[UIImageView alloc] initWithFrame:prevBox.bounds];
    gPreview.contentMode = UIViewContentModeScaleAspectFill;
    gPreview.clipsToBounds = YES;
    [prevBox addSubview:gPreview];

    UILabel *noFeed = [[UILabel alloc] initWithFrame:prevBox.bounds];
    noFeed.text = @"NO FEED"; noFeed.textColor = [UIColor grayColor];
    noFeed.textAlignment = NSTextAlignmentCenter;
    noFeed.font = [UIFont systemFontOfSize:13]; noFeed.tag = 88;
    [prevBox addSubview:noFeed];

    gFpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(6,4,80,14)];
    gFpsLabel.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    gFpsLabel.font = [UIFont systemFontOfSize:10];
    [prevBox addSubview:gFpsLabel];
    y += prevH + 10;

    // Status
    gStatus = [[UILabel alloc] initWithFrame:CGRectMake(14,y,cw,16)];
    gStatus.text = gURL ? @"Đã cấu hình" : @"Nhập IP PC bên dưới";
    gStatus.textColor = [UIColor grayColor];
    gStatus.font = [UIFont systemFontOfSize:12];
    [bg addSubview:gStatus];
    y += 22;

    // IP field
    UIView *ipBg = [[UIView alloc] initWithFrame:CGRectMake(14,y,cw,42)];
    ipBg.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    ipBg.layer.cornerRadius = 8;
    ipBg.layer.borderWidth = 1;
    ipBg.layer.borderColor = [UIColor colorWithRed:1 green:0 blue:0.8 alpha:0.5].CGColor;
    [bg addSubview:ipBg];

    UILabel *gt = [[UILabel alloc] initWithFrame:CGRectMake(8,0,18,42)];
    gt.text = @">"; gt.textColor = [UIColor colorWithRed:1 green:0 blue:0.8 alpha:1];
    gt.font = [UIFont boldSystemFontOfSize:15];
    [ipBg addSubview:gt];

    gIPField = [[UITextField alloc] initWithFrame:CGRectMake(28,0,cw-34,42)];
    gIPField.textColor = [UIColor whiteColor];
    gIPField.font = [UIFont boldSystemFontOfSize:16];
    gIPField.keyboardType = UIKeyboardTypeURL;
    gIPField.keyboardAppearance = UIKeyboardAppearanceDark;
    gIPField.autocorrectionType = UITextAutocorrectionTypeNo;
    gIPField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    gIPField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"192.168.x.x"
        attributes:@{NSForegroundColorAttributeName:[UIColor grayColor]}];
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    NSString *saved = [p stringForKey:@"streamURL"];
    if (saved) { NSURL *u=[NSURL URLWithString:saved]; gIPField.text=u.host?:@""; }
    [ipBg addSubview:gIPField];
    y += 50;

    // Connect button
    UIButton *connBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    connBtn.frame = CGRectMake(14,y,cw,46);
    connBtn.backgroundColor = [UIColor clearColor];
    connBtn.layer.borderWidth = 2;
    connBtn.layer.borderColor = [UIColor colorWithRed:1 green:0 blue:0.8 alpha:1].CGColor;
    connBtn.layer.cornerRadius = 10;
    [connBtn setTitle:@"START WIFI MODE _" forState:UIControlStateNormal];
    [connBtn setTitleColor:[UIColor colorWithRed:1 green:0 blue:0.8 alpha:1] forState:UIControlStateNormal];
    connBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [connBtn addTarget:connBtn action:@selector(vcamConnect) forControlEvents:UIControlEventTouchUpInside];
    [bg addSubview:connBtn];
    y += 54;

    // VCam toggle row
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(14,y,cw,48)];
    row.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    row.layer.cornerRadius = 10;
    [bg addSubview:row];

    UILabel *rowLbl = [[UILabel alloc] initWithFrame:CGRectMake(12,0,cw-70,48)];
    rowLbl.text = @"Bật Camera Ảo";
    rowLbl.textColor = [UIColor whiteColor];
    rowLbl.font = [UIFont boldSystemFontOfSize:15];
    [row addSubview:rowLbl];

    gSwitch = [[UISwitch alloc] init];
    gSwitch.center = CGPointMake(cw-26, 24);
    gSwitch.onTintColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    gSwitch.on = gEnabled;
    [gSwitch addTarget:gSwitch action:@selector(vcamToggle) forControlEvents:UIControlEventValueChanged];
    [row addSubview:gSwitch];

    // Start preview timer
    [NSTimer scheduledTimerWithTimeInterval:1.0/15 repeats:YES block:^(NSTimer *t){
        if (!gPanelOpen) { [t invalidate]; return; }
        [gLock lock]; UIImage *img = gFrame; [gLock unlock];
        if (!img) return;
        gPreview.image = img;
        [[gPreview.superview viewWithTag:88] setHidden:YES];
        gFpsCount++;
        NSTimeInterval now = CACurrentMediaTime();
        if (gFpsTime==0) gFpsTime=now;
        if (now-gFpsTime >= 1.0) {
            double fps = gFpsCount/(now-gFpsTime);
            gFpsCount=0; gFpsTime=now;
            gFpsLabel.text = [NSString stringWithFormat:@"%.0ffps",fps];
        }
        updateDot();
    }];
}

static void hidePanel(void) {
    if (!gPanelOpen) return;
    gPanelOpen = NO;
    [gIPField resignFirstResponder];
    gPanel.hidden = YES; gPanel = nil;
    gPreview=nil; gStatus=nil; gFpsLabel=nil; gSwitch=nil; gIPField=nil;
}

// Category for panel buttons
@interface UIButton (VCamPanel)
- (void)vcamClose;
- (void)vcamConnect;
@end
@implementation UIButton (VCamPanel)
- (void)vcamClose { hidePanel(); }
- (void)vcamConnect {
    [gIPField resignFirstResponder];
    NSString *ip = [gIPField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!ip.length) return;
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:8080/stream",ip];
    gURL = urlStr;
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    [p setObject:urlStr forKey:@"streamURL"]; [p synchronize];
    [[VCamReceiver shared] startWithURL:urlStr];
    if (gStatus) { gStatus.text=@"Đang kết nối..."; gStatus.textColor=[UIColor yellowColor]; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [gLock lock]; BOOL ok = gFrame!=nil; [gLock unlock];
        if (gStatus) {
            gStatus.text = ok ? [NSString stringWithFormat:@"✓ %@",ip] : @"❌ Không kết nối được";
            gStatus.textColor = ok ?
                [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1] : [UIColor redColor];
        }
        updateDot();
    });
}
@end

@interface UISwitch (VCamToggle)
- (void)vcamToggle;
@end
@implementation UISwitch (VCamToggle)
- (void)vcamToggle {
    gEnabled = self.isOn;
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    [p setBool:gEnabled forKey:@"vcamEnabled"]; [p synchronize];
    if (gEnabled && gURL) [[VCamReceiver shared] startWithURL:gURL];
    else if (!gEnabled) [[VCamReceiver shared] stop];
    updateDot();
}
@end

// ═══════════════════════════════════════
//  HOOK
// ═══════════════════════════════════════
@interface VCamProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> original;
@end
@implementation VCamProxy
- (void)captureOutput:(AVCaptureOutput *)o didOutputSampleBuffer:(CMSampleBufferRef)sb fromConnection:(AVCaptureConnection *)c {
    if (!gEnabled) { if([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) [self.original captureOutput:o didOutputSampleBuffer:sb fromConnection:c]; return; }
    [gLock lock]; UIImage *f=gFrame; [gLock unlock];
    if (!f) { if([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) [self.original captureOutput:o didOutputSampleBuffer:sb fromConnection:c]; return; }
    CMSampleBufferRef fake = imageToSampleBuffer(f);
    if (fake) { if([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) [self.original captureOutput:o didOutputSampleBuffer:fake fromConnection:c]; CFRelease(fake); }
}
- (void)captureOutput:(AVCaptureOutput *)o didDropSampleBuffer:(CMSampleBufferRef)sb fromConnection:(AVCaptureConnection *)c {
    if([self.original respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)]) [self.original captureOutput:o didDropSampleBuffer:sb fromConnection:c];
}
- (BOOL)respondsToSelector:(SEL)sel { return [super respondsToSelector:sel]||[self.original respondsToSelector:sel]; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { NSMethodSignature *s=[super methodSignatureForSelector:sel]; if(!s)s=[(id)self.original methodSignatureForSelector:sel]; return s; }
- (void)forwardInvocation:(NSInvocation *)inv { if([self.original respondsToSelector:inv.selector])[inv invokeWithTarget:self.original]; }
@end

static NSMapTable *gProxies = nil;
%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)d queue:(dispatch_queue_t)q {
    if (!d||[d isKindOfClass:[VCamProxy class]]) { %orig; return; }
    if (!gProxies) gProxies=[NSMapTable weakToStrongObjectsMapTable];
    VCamProxy *proxy=[gProxies objectForKey:d];
    if (!proxy) { proxy=[VCamProxy new]; proxy.original=d; [gProxies setObject:proxy forKey:d]; }
    %orig(proxy,q);
}
%end

// Show bubble when app becomes active
%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        showBubble();
    });
}
%end

static void vcamPrefsChanged(CFNotificationCenterRef c,void *o,CFStringRef n,const void *ob,CFDictionaryRef ui) {
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    NSString *url=[p stringForKey:@"streamURL"];
    if(url) gURL=url;
    if(gSwitch) dispatch_async(dispatch_get_main_queue(),^{gSwitch.on=gEnabled;});
    updateDot();
}

%ctor {
    NSLog(@"[VCamJoy] Tweak loaded!");
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    gURL=[p stringForKey:@"streamURL"];
    if(gEnabled&&gURL) [[VCamReceiver shared] startWithURL:gURL];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,vcamPrefsChanged,
        CFSTR("com.vcamjoy.prefschanged"),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
}

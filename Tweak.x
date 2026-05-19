#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>

// ═══════════════════════════════════════════════
//  SHARED STATE
// ═══════════════════════════════════════════════
static UIImage   *gLatestFrame = nil;
static NSLock    *gLock        = nil;
static NSMutableData *gBuf     = nil;
static NSData    *kSOI = nil, *kEOI = nil;
static BOOL       gEnabled     = NO;
static NSURLSession      *gSes  = nil;
static NSURLSessionDataTask *gTask = nil;
static NSString  *gStreamURL   = nil;

// ═══════════════════════════════════════════════
//  MJPEG RECEIVER
// ═══════════════════════════════════════════════
@interface VCamReceiver : NSObject <NSURLSessionDataDelegate>
+ (instancetype)shared;
- (void)startWithURL:(NSString *)url;
- (void)stop;
@end

@implementation VCamReceiver
+ (instancetype)shared {
    static VCamReceiver *s; static dispatch_once_t t;
    dispatch_once(&t,^{s=[self new]}); return s;
}
- (instancetype)init {
    if(!(self=[super init]))return nil;
    uint8_t s[]={0xFF,0xD8},e[]={0xFF,0xD9};
    kSOI=[NSData dataWithBytes:s length:2];
    kEOI=[NSData dataWithBytes:e length:2];
    gBuf=[NSMutableData data]; gLock=[NSLock new]; return self;
}
- (void)startWithURL:(NSString *)urlStr {
    [self stop];
    NSURL *url=[NSURL URLWithString:urlStr]; if(!url)return;
    NSURLSessionConfiguration *cfg=[NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest=10; cfg.timeoutIntervalForResource=86400;
    gSes=[NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    gTask=[gSes dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
    [gTask resume];
}
- (void)stop { [gTask cancel]; gTask=nil; [gBuf setLength:0]; }
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t
didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h {
    [gBuf setLength:0]; h(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    [gBuf appendData:d];
    while(YES){
        NSRange r1=[gBuf rangeOfData:kSOI options:0 range:NSMakeRange(0,gBuf.length)];
        if(r1.location==NSNotFound){[gBuf setLength:0];break;}
        NSRange sr=NSMakeRange(r1.location+2,gBuf.length-r1.location-2);
        NSRange r2=[gBuf rangeOfData:kEOI options:0 range:sr];
        if(r2.location==NSNotFound)break;
        NSUInteger end=r2.location+2;
        NSData *jpeg=[gBuf subdataWithRange:NSMakeRange(r1.location,end-r1.location)];
        [gBuf replaceBytesInRange:NSMakeRange(0,end) withBytes:NULL length:0];
        UIImage *img=[UIImage imageWithData:jpeg]; if(!img)continue;
        [gLock lock]; gLatestFrame=img; [gLock unlock];
    }
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
    if(e&&e.code!=NSURLErrorCancelled&&gEnabled&&gStreamURL){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            [[VCamReceiver shared] startWithURL:gStreamURL];
        });
    }
}
@end

// ═══════════════════════════════════════════════
//  IMAGE → CMSampleBuffer
// ═══════════════════════════════════════════════
static CMSampleBufferRef imageToSampleBuffer(UIImage *image) CF_RETURNS_RETAINED {
    CGImageRef cg=image.CGImage; if(!cg)return NULL;
    size_t w=CGImageGetWidth(cg),h=CGImageGetHeight(cg);
    NSDictionary *a=@{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,
                      (id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
    CVPixelBufferRef pb=NULL;
    if(CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_32BGRA,
                           (__bridge CFDictionaryRef)a,&pb)!=kCVReturnSuccess)return NULL;
    CVPixelBufferLockBaseAddress(pb,0);
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb),w,h,8,
        CVPixelBufferGetBytesPerRow(pb),cs,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),cg);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pb,0);
    CMVideoFormatDescriptionRef fd=NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pb,&fd);
    if(!fd){CVPixelBufferRelease(pb);return NULL;}
    CMSampleTimingInfo ti={CMTimeMake(1,30),CMTimeMakeWithSeconds(CACurrentMediaTime(),90000),kCMTimeInvalid};
    CMSampleBufferRef sb=NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,pb,true,NULL,NULL,fd,&ti,&sb);
    CFRelease(fd); CVPixelBufferRelease(pb); return sb;
}

// ═══════════════════════════════════════════════
//  PROXY DELEGATE
// ═══════════════════════════════════════════════
@interface VCamProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> original;
@end
@implementation VCamProxy
- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sb
       fromConnection:(AVCaptureConnection *)c {
    if(!gEnabled){
        if([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
            [self.original captureOutput:output didOutputSampleBuffer:sb fromConnection:c];
        return;
    }
    [gLock lock]; UIImage *frame=gLatestFrame; [gLock unlock];
    if(!frame){
        if([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
            [self.original captureOutput:output didOutputSampleBuffer:sb fromConnection:c];
        return;
    }
    CMSampleBufferRef fake=imageToSampleBuffer(frame);
    if(fake){
        if([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
            [self.original captureOutput:output didOutputSampleBuffer:fake fromConnection:c];
        CFRelease(fake);
    }
}
- (void)captureOutput:(AVCaptureOutput *)o didDropSampleBuffer:(CMSampleBufferRef)sb fromConnection:(AVCaptureConnection *)c {
    if([self.original respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)])
        [self.original captureOutput:o didDropSampleBuffer:sb fromConnection:c];
}
- (BOOL)respondsToSelector:(SEL)sel{return [super respondsToSelector:sel]||[self.original respondsToSelector:sel];}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel{
    NSMethodSignature *sig=[super methodSignatureForSelector:sel];
    if(!sig)sig=[(id)self.original methodSignatureForSelector:sel]; return sig;
}
- (void)forwardInvocation:(NSInvocation *)inv{
    if([self.original respondsToSelector:inv.selector])[inv invokeWithTarget:self.original];
}
@end

// ═══════════════════════════════════════════════
//  BUBBLE WINDOW (popup nổi)
// ═══════════════════════════════════════════════
@interface VCamBubble : NSObject
+ (void)show;
+ (void)hide;
@end

static UIWindow   *gBubbleWin    = nil;
static UIWindow   *gPanelWin     = nil;
static BOOL        gPanelVisible = NO;
static UILabel    *gStatusLbl    = nil;
static UILabel    *gFpsLbl       = nil;
static UISwitch   *gVcamSwitch   = nil;
static UITextField *gIPField     = nil;
static UIButton   *gConnectBtn   = nil;
static UIImageView *gPreviewImg  = nil;

@implementation VCamBubble

+ (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        if(gBubbleWin) return;

        // Bubble window
        gBubbleWin = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 60, 60)];
        gBubbleWin.windowLevel = UIWindowLevelAlert + 100;
        gBubbleWin.backgroundColor = [UIColor clearColor];
        gBubbleWin.hidden = NO;

        // Bubble button
        UIButton *bubble = [UIButton buttonWithType:UIButtonTypeCustom];
        bubble.frame = CGRectMake(0, 0, 60, 60);
        bubble.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.1 alpha:0.95];
        bubble.layer.cornerRadius = 30;
        bubble.layer.borderWidth = 2;
        bubble.layer.borderColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1].CGColor;

        // Camera icon
        UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(0,4,60,28)];
        icon.text = @"🎥"; icon.textAlignment = NSTextAlignmentCenter;
        icon.font = [UIFont systemFontOfSize:22]; [bubble addSubview:icon];

        // Status dot
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(22,38,8,8)];
        dot.backgroundColor = [UIColor grayColor];
        dot.layer.cornerRadius = 4;
        dot.tag = 999; [bubble addSubview:dot];

        // VC label
        UILabel *vcl = [[UILabel alloc] initWithFrame:CGRectMake(0,36,60,14)];
        vcl.text = @"VCAM"; vcl.textAlignment = NSTextAlignmentCenter;
        vcl.font = [UIFont boldSystemFontOfSize:8];
        vcl.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
        [bubble addSubview:vcl];

        [bubble addTarget:[VCamBubble class] action:@selector(onBubbleTap) forControlEvents:UIControlEventTouchUpInside];

        // Drag gesture
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:[VCamBubble class] action:@selector(onDrag:)];
        [bubble addGestureRecognizer:pan];

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view = [[UIView alloc] initWithFrame:gBubbleWin.bounds];
        vc.view.backgroundColor = [UIColor clearColor];
        [vc.view addSubview:bubble];
        gBubbleWin.rootViewController = vc;
    });
}

+ (void)onBubbleTap {
    if(gPanelVisible) [self hidePanel];
    else [self showPanel];
}

+ (void)onDrag:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:gBubbleWin];
    CGRect f = gBubbleWin.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    // Clamp to screen
    CGSize sc = [UIScreen mainScreen].bounds.size;
    f.origin.x = MAX(0, MIN(sc.width-60, f.origin.x));
    f.origin.y = MAX(40, MIN(sc.height-60, f.origin.y));
    gBubbleWin.frame = f;
    [pan setTranslation:CGPointZero inView:gBubbleWin];
}

+ (void)showPanel {
    gPanelVisible = YES;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    CGFloat pw = MIN(sc.width - 40, 340);
    CGFloat ph = 420;
    CGFloat px = (sc.width - pw) / 2;
    CGFloat py = (sc.height - ph) / 2;

    gPanelWin = [[UIWindow alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    gPanelWin.windowLevel = UIWindowLevelAlert + 99;
    gPanelWin.backgroundColor = [UIColor clearColor];
    gPanelWin.hidden = NO;

    UIViewController *vc = [[UIViewController alloc] init];
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0,0,pw,ph)];
    panel.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.97];
    panel.layer.cornerRadius = 16;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:0.4].CGColor;
    panel.clipsToBounds = YES;
    vc.view = [[UIView alloc] initWithFrame:gPanelWin.bounds];
    vc.view.backgroundColor = [UIColor clearColor];
    [vc.view addSubview:panel];
    gPanelWin.rootViewController = vc;

    CGFloat y = 12; CGFloat cw = pw - 28;

    // Header
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14,y,cw-44,28)];
    title.text = @"VCamJoy"; title.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    title.font = [UIFont boldSystemFontOfSize:20]; [panel addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(pw-44, y, 30, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    [closeBtn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    [closeBtn addTarget:[VCamBubble class] action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
    y += 36;

    // Preview
    UIView *prevBox = [[UIView alloc] initWithFrame:CGRectMake(14,y,cw,cw*9/16)];
    prevBox.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    prevBox.layer.cornerRadius = 8; prevBox.clipsToBounds = YES;
    [panel addSubview:prevBox];
    gPreviewImg = [[UIImageView alloc] initWithFrame:prevBox.bounds];
    gPreviewImg.contentMode = UIViewContentModeScaleAspectFill;
    gPreviewImg.clipsToBounds = YES; [prevBox addSubview:gPreviewImg];
    UILabel *noFeed = [[UILabel alloc] initWithFrame:prevBox.bounds];
    noFeed.text = @"NO FEED"; noFeed.textColor = [UIColor grayColor];
    noFeed.textAlignment = NSTextAlignmentCenter;
    noFeed.font = [UIFont systemFontOfSize:12]; noFeed.tag=88; [prevBox addSubview:noFeed];
    gFpsLbl = [[UILabel alloc] initWithFrame:CGRectMake(4,4,80,14)];
    gFpsLbl.textColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    gFpsLbl.font = [UIFont systemFontOfSize:10]; [prevBox addSubview:gFpsLbl];
    y += cw*9/16 + 10;

    // Status
    gStatusLbl = [[UILabel alloc] initWithFrame:CGRectMake(14,y,cw,16)];
    gStatusLbl.text = @"Chưa kết nối"; gStatusLbl.textColor = [UIColor grayColor];
    gStatusLbl.font = [UIFont systemFontOfSize:12]; [panel addSubview:gStatusLbl];
    y += 22;

    // IP field
    UIView *ipBg = [[UIView alloc] initWithFrame:CGRectMake(14,y,cw,40)];
    ipBg.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    ipBg.layer.cornerRadius = 8; ipBg.layer.borderWidth=1;
    ipBg.layer.borderColor = [UIColor colorWithRed:1 green:0 blue:0.8 alpha:0.6].CGColor;
    [panel addSubview:ipBg];
    UILabel *gt = [[UILabel alloc] initWithFrame:CGRectMake(8,0,16,40)];
    gt.text=@">"; gt.textColor=[UIColor colorWithRed:1 green:0 blue:0.8 alpha:1];
    gt.font=[UIFont boldSystemFontOfSize:14]; [ipBg addSubview:gt];
    gIPField = [[UITextField alloc] initWithFrame:CGRectMake(26,0,ipBg.frame.size.width-32,40)];
    gIPField.textColor = [UIColor whiteColor];
    gIPField.font = [UIFont boldSystemFontOfSize:16];
    gIPField.keyboardType = UIKeyboardTypeURL;
    gIPField.keyboardAppearance = UIKeyboardAppearanceDark;
    gIPField.autocorrectionType = UITextAutocorrectionTypeNo;
    gIPField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    gIPField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"192.168.x.x"
        attributes:@{NSForegroundColorAttributeName:[UIColor grayColor]}];
    // Load saved IP
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    NSString *savedURL = [p stringForKey:@"streamURL"];
    if(savedURL){ NSURL *u=[NSURL URLWithString:savedURL]; gIPField.text=u.host?:@""; }
    [ipBg addSubview:gIPField];
    y += 48;

    // Connect button
    gConnectBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    gConnectBtn.frame = CGRectMake(14,y,cw,44);
    gConnectBtn.backgroundColor = [UIColor clearColor];
    gConnectBtn.layer.borderWidth = 2;
    gConnectBtn.layer.borderColor = [UIColor colorWithRed:1 green:0 blue:0.8 alpha:1].CGColor;
    gConnectBtn.layer.cornerRadius = 8;
    [gConnectBtn setTitle:@"START WIFI MODE _" forState:UIControlStateNormal];
    [gConnectBtn setTitleColor:[UIColor colorWithRed:1 green:0 blue:0.8 alpha:1] forState:UIControlStateNormal];
    gConnectBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [gConnectBtn addTarget:[VCamBubble class] action:@selector(onConnect) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:gConnectBtn];
    y += 52;

    // VCam switch row
    UIView *swRow = [[UIView alloc] initWithFrame:CGRectMake(14,y,cw,44)];
    swRow.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    swRow.layer.cornerRadius = 8; [panel addSubview:swRow];
    UILabel *swLbl = [[UILabel alloc] initWithFrame:CGRectMake(12,0,cw-70,44)];
    swLbl.text = @"Bật Camera Ảo";
    swLbl.textColor = [UIColor whiteColor];
    swLbl.font = [UIFont boldSystemFontOfSize:15]; [swRow addSubview:swLbl];
    gVcamSwitch = [[UISwitch alloc] init];
    gVcamSwitch.center = CGPointMake(cw-28, 22);
    gVcamSwitch.onTintColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
    gVcamSwitch.on = gEnabled;
    [gVcamSwitch addTarget:[VCamBubble class] action:@selector(onVcamToggle:) forControlEvents:UIControlEventValueChanged];
    [swRow addSubview:gVcamSwitch];

    // Start preview update timer
    [NSTimer scheduledTimerWithTimeInterval:1.0/15.0 target:[VCamBubble class]
        selector:@selector(updatePreview) userInfo:nil repeats:YES];
}

+ (void)hidePanel {
    gPanelVisible = NO;
    [gIPField resignFirstResponder];
    gPanelWin.hidden = YES;
    gPanelWin = nil;
    gPreviewImg = nil; gStatusLbl = nil;
    gFpsLbl = nil; gVcamSwitch = nil;
    gConnectBtn = nil; gIPField = nil;
}

+ (void)onConnect {
    [gIPField resignFirstResponder];
    NSString *ip = [gIPField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if(!ip.length) return;

    if(gTask){ // đang kết nối → ngắt
        [[VCamReceiver shared] stop];
        gStreamURL = nil;
        gConnectBtn.layer.borderColor = [UIColor colorWithRed:1 green:0 blue:0.8 alpha:1].CGColor;
        [gConnectBtn setTitle:@"START WIFI MODE _" forState:UIControlStateNormal];
        [gConnectBtn setTitleColor:[UIColor colorWithRed:1 green:0 blue:0.8 alpha:1] forState:UIControlStateNormal];
        if(gStatusLbl) { gStatusLbl.text=@"Đã ngắt kết nối"; gStatusLbl.textColor=[UIColor grayColor]; }
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:@"http://%@:8080/stream", ip];
    gStreamURL = urlStr;

    // Save prefs
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    [prefs setObject:urlStr forKey:@"streamURL"];
    [prefs synchronize];

    [[VCamReceiver shared] startWithURL:urlStr];

    if(gStatusLbl){ gStatusLbl.text=[NSString stringWithFormat:@"Đang kết nối %@...",ip]; gStatusLbl.textColor=[UIColor yellowColor]; }
    gConnectBtn.layer.borderColor = [UIColor redColor].CGColor;
    [gConnectBtn setTitle:@"NGẮT KẾT NỐI _" forState:UIControlStateNormal];
    [gConnectBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];

    // Check connected after 3s
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [gLock lock]; BOOL hasFrame = gLatestFrame != nil; [gLock unlock];
        if(gStatusLbl){
            if(hasFrame){
                gStatusLbl.text=[NSString stringWithFormat:@"✓ Kết nối %@",ip];
                gStatusLbl.textColor=[UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
                // Update bubble dot
                if(gBubbleWin){
                    UIView *dot=[gBubbleWin.rootViewController.view viewWithTag:999];
                    dot.backgroundColor=[UIColor colorWithRed:0 green:1 blue:0.53 alpha:1];
                }
            } else {
                gStatusLbl.text=@"❌ Không kết nối được";
                gStatusLbl.textColor=[UIColor redColor];
            }
        }
    });
}

+ (void)onVcamToggle:(UISwitch *)sw {
    gEnabled = sw.isOn;
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    [p setBool:gEnabled forKey:@"vcamEnabled"];
    [p synchronize];
    if(gEnabled && gStreamURL) [[VCamReceiver shared] startWithURL:gStreamURL];
    else if(!gEnabled) [[VCamReceiver shared] stop];
    // Update bubble dot color
    if(gBubbleWin){
        UIView *dot=[gBubbleWin.rootViewController.view viewWithTag:999];
        dot.backgroundColor = gEnabled ?
            [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1] : [UIColor grayColor];
    }
}

static NSUInteger gFpsCount = 0;
static NSTimeInterval gFpsTime = 0;

+ (void)updatePreview {
    if(!gPreviewImg) return;
    [gLock lock]; UIImage *img = gLatestFrame; [gLock unlock];
    if(!img) return;
    gPreviewImg.image = img;
    [[gPreviewImg.superview viewWithTag:88] setHidden:YES];
    // FPS
    gFpsCount++;
    NSTimeInterval now = CACurrentMediaTime();
    if(gFpsTime == 0) gFpsTime = now;
    if(now - gFpsTime >= 1.0){
        double fps = gFpsCount / (now - gFpsTime);
        gFpsCount = 0; gFpsTime = now;
        if(gFpsLbl) gFpsLbl.text = [NSString stringWithFormat:@"%.0f fps", fps];
    }
}

+ (void)hide {
    gBubbleWin.hidden = YES; gBubbleWin = nil;
    [self hidePanel];
}
@end

// ═══════════════════════════════════════════════
//  HOOK AVCaptureVideoDataOutput
// ═══════════════════════════════════════════════
static NSMapTable *gProxies = nil;

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue {
    if(!delegate||[delegate isKindOfClass:[VCamProxy class]]){%orig;return;}
    if(!gProxies) gProxies=[NSMapTable weakToStrongObjectsMapTable];
    VCamProxy *proxy=[gProxies objectForKey:delegate];
    if(!proxy){
        proxy=[VCamProxy new]; proxy.original=delegate;
        [gProxies setObject:proxy forKey:delegate];
    }
    %orig(proxy,queue);
}
%end

// ═══════════════════════════════════════════════
//  INIT
// ═══════════════════════════════════════════════
static void vcamPrefsChanged(CFNotificationCenterRef c,void *o,CFStringRef n,const void *ob,CFDictionaryRef ui){
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    NSString *url=[p stringForKey:@"streamURL"];
    if(url) gStreamURL=url;
    if(gVcamSwitch) dispatch_async(dispatch_get_main_queue(),^{gVcamSwitch.on=gEnabled;});
}

%ctor {
    NSLog(@"[VCamJoy] Loaded!");
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    gStreamURL=[p stringForKey:@"streamURL"];
    if(gEnabled&&gStreamURL) [[VCamReceiver shared] startWithURL:gStreamURL];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,vcamPrefsChanged,CFSTR("com.vcamjoy.prefschanged"),NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    // Show bubble khi app khởi động
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [VCamBubble show];
    });
}

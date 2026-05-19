/*
 * VCamJoy — Tweak.x v3.1 (rootless compatible)
 * - Hook AVCaptureVideoDataOutput → inject MJPEG frame
 * - Floating bubble UI với panel điều khiển
 * - Tương thích: palera1n rootless, Dopamine, XinaA15
 */

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>

// ── Globals ──────────────────────────────────────────────────────────────
static BOOL           gEnabled  = NO;
static NSString      *gURL      = nil;
static UIImage       *gFrame    = nil;
static NSLock        *gLock     = nil;
static NSURLSession  *gSession  = nil;
static NSMutableData *gBuf      = nil;
static NSMapTable    *gProxies  = nil;

// Bubble UI
static UIWindow    *gBubbleWindow = nil;
static UIButton    *gBubbleBtn    = nil;
static UIView      *gPanel        = nil;
static UISwitch    *gSwitch       = nil;
static UITextField *gIPField      = nil;
static BOOL         gPanelVisible = NO;

// ── MJPEG Stream Receiver ─────────────────────────────────────────────────
@interface VCamStreamDelegate : NSObject <NSURLSessionDataDelegate>
@end
@implementation VCamStreamDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data {
    if (!gBuf) gBuf = [NSMutableData data];
    [gBuf appendData:data];
    uint8_t sB[2]={0xFF,0xD8}, eB[2]={0xFF,0xD9};
    NSData *SOI=[NSData dataWithBytes:sB length:2];
    NSData *EOI=[NSData dataWithBytes:eB length:2];
    while (YES) {
        NSRange rs=[gBuf rangeOfData:SOI options:0 range:NSMakeRange(0,gBuf.length)];
        if (rs.location==NSNotFound){[gBuf setLength:0];break;}
        NSRange re=[gBuf rangeOfData:EOI options:0 range:NSMakeRange(rs.location,gBuf.length-rs.location)];
        if (re.location==NSNotFound) break;
        NSData *jpg=[gBuf subdataWithRange:NSMakeRange(rs.location,re.location+2-rs.location)];
        UIImage *img=[UIImage imageWithData:jpg];
        if (img){[gLock lock];gFrame=img;[gLock unlock];}
        [gBuf replaceBytesInRange:NSMakeRange(0,re.location+2) withBytes:NULL length:0];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if (gEnabled && gURL) {
            NSURL *u=[NSURL URLWithString:gURL];
            if (u) [[gSession dataTaskWithURL:u] resume];
        }
    });
}
@end
static VCamStreamDelegate *gDelegate = nil;

static void startStream(NSString *urlStr) {
    if (!urlStr.length) return;
    NSURL *url=[NSURL URLWithString:urlStr];
    if (!url) return;
    [gSession invalidateAndCancel];
    if (!gLock)     gLock=[NSLock new];
    if (!gBuf)      gBuf=[NSMutableData data];
    if (!gDelegate) gDelegate=[VCamStreamDelegate new];
    NSURLSessionConfiguration *cfg=[NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest=10; cfg.timeoutIntervalForResource=86400;
    gSession=[NSURLSession sessionWithConfiguration:cfg delegate:gDelegate delegateQueue:nil];
    [[gSession dataTaskWithURL:url] resume];
    NSLog(@"[VCamJoy] Stream started: %@", urlStr);
}
static void stopStream(void) {
    [gSession invalidateAndCancel]; gSession=nil;
    [gLock lock]; gFrame=nil; [gLock unlock];
}

// ── VCamProxy ─────────────────────────────────────────────────────────────
@interface VCamProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> original;
@end
@implementation VCamProxy

static CMSampleBufferRef makeBuffer(UIImage *img) {
    CGImageRef cg=img.CGImage;
    size_t w=CGImageGetWidth(cg), h=CGImageGetHeight(cg);
    NSDictionary *a=@{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,
                      (id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
    CVPixelBufferRef pb=NULL;
    if(CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_32ARGB,
        (__bridge CFDictionaryRef)a,&pb)!=kCVReturnSuccess) return NULL;
    CVPixelBufferLockBaseAddress(pb,0);
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb),w,h,8,
        CVPixelBufferGetBytesPerRow(pb),cs,
        kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),cg);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pb,0);
    CMVideoFormatDescriptionRef fmt=NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pb,&fmt);
    if(!fmt){CVPixelBufferRelease(pb);return NULL;}
    CMSampleTimingInfo ti={CMTimeMake(1,30),kCMTimeZero,kCMTimeInvalid};
    CMSampleBufferRef sb=NULL;
    CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,pb,fmt,&ti,&sb);
    CFRelease(fmt); CVPixelBufferRelease(pb);
    return sb;
}

- (void)captureOutput:(AVCaptureOutput *)o didOutputSampleBuffer:(CMSampleBufferRef)sb
       fromConnection:(AVCaptureConnection *)c {
    if (gEnabled) {
        [gLock lock]; UIImage *img=gFrame; [gLock unlock];
        if (img) {
            CMSampleBufferRef fake=makeBuffer(img);
            if (fake) {
                [self.original captureOutput:o didOutputSampleBuffer:fake fromConnection:c];
                CFRelease(fake); return;
            }
        }
    }
    [self.original captureOutput:o didOutputSampleBuffer:sb fromConnection:c];
}
- (void)captureOutput:(AVCaptureOutput *)o didDropSampleBuffer:(CMSampleBufferRef)sb
       fromConnection:(AVCaptureConnection *)c {
    if ([self.original respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)])
        [self.original captureOutput:o didDropSampleBuffer:sb fromConnection:c];
}
- (BOOL)respondsToSelector:(SEL)s {
    return [super respondsToSelector:s]||[self.original respondsToSelector:s];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s {
    NSMethodSignature *sig=[super methodSignatureForSelector:s];
    return sig ?: [(id)self.original methodSignatureForSelector:s];
}
- (void)forwardInvocation:(NSInvocation *)inv {
    if ([self.original respondsToSelector:inv.selector]) [inv invokeWithTarget:self.original];
}
@end

// ── Bubble ────────────────────────────────────────────────────────────────
static void savePrefs(void);
static void togglePanel(void);

@interface VCamHandler : NSObject
+ (instancetype)sh;
- (void)tap;
- (void)pan:(UIPanGestureRecognizer *)g;
- (void)connect;
- (void)toggle:(UISwitch *)s;
@end
@implementation VCamHandler
+ (instancetype)sh {
    static VCamHandler *i; static dispatch_once_t t;
    dispatch_once(&t,^{i=[self new]}); return i;
}
- (void)tap { togglePanel(); }
- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint d=[g translationInView:gBubbleWindow];
    CGRect f=gBubbleBtn.frame;
    CGSize sc=[UIScreen mainScreen].bounds.size;
    f.origin.x=MAX(0,MIN(f.origin.x+d.x,sc.width-f.size.width));
    f.origin.y=MAX(20,MIN(f.origin.y+d.y,sc.height-f.size.height-20));
    gBubbleBtn.frame=f;
    [g setTranslation:CGPointZero inView:gBubbleWindow];
    if (!gPanel.hidden) {
        CGRect pf=gPanel.frame;
        pf.origin.x=MAX(8,MIN(f.origin.x-8,sc.width-pf.size.width-8));
        pf.origin.y=f.origin.y+f.size.height+10;
        if (pf.origin.y+pf.size.height>sc.height-20)
            pf.origin.y=f.origin.y-pf.size.height-10;
        gPanel.frame=pf;
    }
}
- (void)connect {
    NSString *s=[[gIPField.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (!s.length) return;
    gURL=s; savePrefs(); startStream(gURL);
    [gIPField resignFirstResponder];
}
- (void)toggle:(UISwitch *)sw {
    gEnabled=sw.on; savePrefs();
    if (gEnabled && gURL) startStream(gURL); else stopStream();
    [gBubbleBtn setTitle:(gEnabled?@"🟢":@"🎥") forState:UIControlStateNormal];
}
@end

static void togglePanel(void) {
    if (!gPanel) return;
    gPanelVisible=!gPanelVisible;
    gPanel.hidden=NO;
    [UIView animateWithDuration:0.22 animations:^{ gPanel.alpha=gPanelVisible?1:0; }
     completion:^(BOOL f){ if(!gPanelVisible) gPanel.hidden=YES; }];
}

static void savePrefs(void) {
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    [p setBool:gEnabled forKey:@"vcamEnabled"];
    if (gURL) [p setObject:gURL forKey:@"streamURL"];
    [p synchronize];
}

static void showBubble(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        if (gBubbleWindow) { gBubbleWindow.hidden=NO; return; }

        // Tạo window riêng — QUAN TRỌNG: rootViewController bắt buộc
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s; break;
            }
        }

        if (scene) {
            gBubbleWindow = [[UIWindow alloc] initWithWindowScene:scene];
        } else {
            gBubbleWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        gBubbleWindow.windowLevel = UIWindowLevelAlert + 200;
        gBubbleWindow.backgroundColor = [UIColor clearColor];

        // rootViewController bắt buộc cho iOS 13+
        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = [UIColor clearColor];
        gBubbleWindow.rootViewController = vc;
        [gBubbleWindow makeKeyAndVisible];

        CGFloat sw = [UIScreen mainScreen].bounds.size.width;
        VCamHandler *h = [VCamHandler sh];

        // Bubble button
        gBubbleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        gBubbleBtn.frame = CGRectMake(20, 120, 56, 56);
        gBubbleBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.88];
        gBubbleBtn.layer.cornerRadius = 28;
        gBubbleBtn.layer.shadowColor = [UIColor blackColor].CGColor;
        gBubbleBtn.layer.shadowRadius = 6;
        gBubbleBtn.layer.shadowOpacity = 0.6;
        gBubbleBtn.layer.shadowOffset = CGSizeMake(0,3);
        gBubbleBtn.titleLabel.font = [UIFont systemFontOfSize:24];
        [gBubbleBtn setTitle:@"🎥" forState:UIControlStateNormal];
        [gBubbleBtn addTarget:h action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:h action:@selector(pan:)];
        [gBubbleBtn addGestureRecognizer:pan];
        [vc.view addSubview:gBubbleBtn];

        // Panel
        gPanel = [[UIView alloc] initWithFrame:CGRectMake(12, 188, sw-24, 210)];
        gPanel.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.94];
        gPanel.layer.cornerRadius = 16;
        gPanel.layer.shadowColor = [UIColor blackColor].CGColor;
        gPanel.layer.shadowRadius = 12; gPanel.layer.shadowOpacity = 0.5;
        gPanel.hidden = YES; gPanel.alpha = 0;
        [vc.view addSubview:gPanel];

        // Title
        UILabel *ttl = [[UILabel alloc]initWithFrame:CGRectMake(16,12,sw-48,22)];
        ttl.text = @"VCamJoy — Camera Ảo";
        ttl.textColor = [UIColor whiteColor];
        ttl.font = [UIFont boldSystemFontOfSize:15];
        [gPanel addSubview:ttl];

        // IP Field
        gIPField = [[UITextField alloc]initWithFrame:CGRectMake(16,44,sw-56,40)];
        gIPField.placeholder = @"http://192.168.x.x:8080/stream";
        gIPField.text = gURL ?: @"";
        gIPField.textColor = [UIColor whiteColor];
        gIPField.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        gIPField.layer.cornerRadius = 8;
        gIPField.keyboardType = UIKeyboardTypeURL;
        gIPField.autocorrectionType = UITextAutocorrectionTypeNo;
        gIPField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        UIView *pad=[[UIView alloc]initWithFrame:CGRectMake(0,0,10,1)];
        gIPField.leftView=pad; gIPField.leftViewMode=UITextFieldViewModeAlways;
        [gPanel addSubview:gIPField];

        // Connect button
        UIButton *cb=[UIButton buttonWithType:UIButtonTypeCustom];
        cb.frame=CGRectMake(16,96,sw-56,40);
        cb.backgroundColor=[UIColor colorWithRed:0.18 green:0.56 blue:1 alpha:1];
        cb.layer.cornerRadius=8;
        [cb setTitle:@"Kết nối Stream" forState:UIControlStateNormal];
        [cb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        cb.titleLabel.font=[UIFont boldSystemFontOfSize:14];
        [cb addTarget:h action:@selector(connect) forControlEvents:UIControlEventTouchUpInside];
        [gPanel addSubview:cb];

        // Switch
        UILabel *sl=[[UILabel alloc]initWithFrame:CGRectMake(16,152,200,32)];
        sl.text=@"Bật Camera Ảo";
        sl.textColor=[UIColor whiteColor];
        sl.font=[UIFont systemFontOfSize:14];
        [gPanel addSubview:sl];

        gSwitch=[[UISwitch alloc]init];
        CGFloat ssx=sw-56-gSwitch.frame.size.width;
        gSwitch.frame=CGRectMake(ssx,152,gSwitch.frame.size.width,gSwitch.frame.size.height);
        gSwitch.on=gEnabled;
        gSwitch.onTintColor=[UIColor colorWithRed:0.2 green:0.82 blue:0.4 alpha:1];
        [gSwitch addTarget:h action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        [gPanel addSubview:gSwitch];

        NSLog(@"[VCamJoy] Bubble shown! windowLevel=%.0f", gBubbleWindow.windowLevel);
    });
}

// ── Theos Hooks ───────────────────────────────────────────────────────────
%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)d queue:(dispatch_queue_t)q {
    if (!d||[d isKindOfClass:[VCamProxy class]]){%orig;return;}
    if (!gProxies) gProxies=[NSMapTable weakToStrongObjectsMapTable];
    VCamProxy *p=[gProxies objectForKey:d];
    if (!p){p=[VCamProxy new];p.original=d;[gProxies setObject:p forKey:d];}
    NSLog(@"[VCamJoy] Hooked: %@",NSStringFromClass([d class]));
    %orig(p,q);
}
%end

// Hook UIWindowScene để bắt đúng thời điểm app active (iOS 13+)
%hook UIWindowScene
- (void)_didEnterForeground {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.7*NSEC_PER_SEC)),
        dispatch_get_main_queue(),^{ showBubble(); });
}
%end

// Fallback cho app không dùng Scene
%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),
        dispatch_get_main_queue(),^{ showBubble(); });
}
%end

// ── Prefs notification ────────────────────────────────────────────────────
static void onPrefsChanged(CFNotificationCenterRef c,void *o,CFStringRef n,
    const void *ob,CFDictionaryRef ui){
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    NSString *url=[p stringForKey:@"streamURL"];
    if (url) gURL=url;
    if (gEnabled&&gURL) startStream(gURL); else stopStream();
    dispatch_async(dispatch_get_main_queue(),^{
        if (gSwitch) gSwitch.on=gEnabled;
        if (gBubbleBtn) [gBubbleBtn setTitle:(gEnabled?@"🟢":@"🎥") forState:UIControlStateNormal];
    });
}

%ctor {
    NSLog(@"[VCamJoy] Tweak v3.1 loaded (rootless)");
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    gURL=[p stringForKey:@"streamURL"];
    if (gEnabled&&gURL) startStream(gURL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,onPrefsChanged,CFSTR("com.vcamjoy.prefschanged"),NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

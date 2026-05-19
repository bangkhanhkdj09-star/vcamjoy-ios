/*
 * VCamJoy — Tweak.x (v3.0 — bubble fix)
 * - Hook AVCaptureVideoDataOutput để inject frame từ MJPEG stream
 * - Bubble hiện trên UIWindowLevelAlert+100, đảm bảo luôn nổi
 * - Panel điều khiển: nhập IP, bật/tắt vcam
 */

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>

// ── Globals ──────────────────────────────────────────────────────────────
static BOOL          gEnabled   = NO;
static NSString     *gURL       = nil;
static UIImage      *gFrame     = nil;
static NSLock       *gLock      = nil;
static NSURLSession *gSession   = nil;
static NSMutableData *gBuf      = nil;
static NSMapTable   *gProxies   = nil;

// Bubble UI
static UIWindow         *gBubbleWindow   = nil;
static UIButton         *gBubbleBtn      = nil;
static UIView           *gPanel          = nil;
static UISwitch         *gSwitch         = nil;
static UITextField      *gIPField        = nil;
static BOOL              gPanelVisible   = NO;

// ── Forward declarations ──────────────────────────────────────────────────
static void startStream(NSString *urlStr);
static void stopStream(void);
static void updateBubbleDot(void);

// ── MJPEG Receiver ────────────────────────────────────────────────────────
@interface VCamSessionDelegate : NSObject <NSURLSessionDataDelegate>
@end
@implementation VCamSessionDelegate
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data {
    if (!gBuf) gBuf = [NSMutableData data];
    [gBuf appendData:data];

    const uint8_t soi[2] = {0xFF, 0xD8};
    const uint8_t eoi[2] = {0xFF, 0xD9};
    NSData *kSOI = [NSData dataWithBytes:soi length:2];
    NSData *kEOI = [NSData dataWithBytes:eoi length:2];

    while (YES) {
        NSRange rS = [gBuf rangeOfData:kSOI options:0
                                 range:NSMakeRange(0, gBuf.length)];
        if (rS.location == NSNotFound) { [gBuf setLength:0]; break; }
        NSRange rE = [gBuf rangeOfData:kEOI options:0
                                 range:NSMakeRange(rS.location, gBuf.length - rS.location)];
        if (rE.location == NSNotFound) break;

        NSRange jpegRange = NSMakeRange(rS.location, rE.location + 2 - rS.location);
        NSData *jpegData = [gBuf subdataWithRange:jpegRange];
        UIImage *img = [UIImage imageWithData:jpegData];
        if (img) {
            [gLock lock];
            gFrame = img;
            [gLock unlock];
        }
        [gBuf replaceBytesInRange:NSMakeRange(0, rE.location + 2) withBytes:NULL length:0];
    }
}
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    NSLog(@"[VCamJoy] Stream ended: %@", error.localizedDescription);
    // Auto-reconnect sau 2 giây nếu vẫn enabled
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (gEnabled && gURL) startStream(gURL);
    });
}
@end

static VCamSessionDelegate *gDelegate = nil;

static void startStream(NSString *urlStr) {
    if (!urlStr.length) return;
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    [gSession invalidateAndCancel];
    if (!gLock)     gLock     = [NSLock new];
    if (!gBuf)      gBuf      = [NSMutableData data];
    if (!gDelegate) gDelegate = [VCamSessionDelegate new];
    NSURLSessionConfiguration *cfg =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 10;
    cfg.timeoutIntervalForResource = 86400;
    gSession = [NSURLSession sessionWithConfiguration:cfg
                                             delegate:gDelegate
                                        delegateQueue:nil];
    [[gSession dataTaskWithURL:url] resume];
    NSLog(@"[VCamJoy] Stream started: %@", urlStr);
}

static void stopStream(void) {
    [gSession invalidateAndCancel];
    gSession = nil;
    [gLock lock]; gFrame = nil; [gLock unlock];
    NSLog(@"[VCamJoy] Stream stopped");
}

// ── VCamProxy ─────────────────────────────────────────────────────────────
@interface VCamProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> original;
@end

@implementation VCamProxy

static CMSampleBufferRef buildSampleBuffer(UIImage *img) {
    CGImageRef cgImg = img.CGImage;
    size_t w = CGImageGetWidth(cgImg);
    size_t h = CGImageGetHeight(cgImg);

    NSDictionary *attrs = @{
        (id)kCVPixelBufferCGImageCompatibilityKey:    @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    CVPixelBufferRef pxBuf = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                        kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)attrs, &pxBuf);
    if (!pxBuf) return NULL;

    CVPixelBufferLockBaseAddress(pxBuf, 0);
    void *base = CVPixelBufferGetBaseAddress(pxBuf);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(base, w, h, 8,
        CVPixelBufferGetBytesPerRow(pxBuf), cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(ctx, CGRectMake(0,0,w,h), cgImg);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pxBuf, 0);

    CMVideoFormatDescriptionRef fmt = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pxBuf, &fmt);
    if (!fmt) { CVPixelBufferRelease(pxBuf); return NULL; }

    CMSampleTimingInfo timing = {CMTimeMake(1,30), kCMTimeZero, kCMTimeInvalid};
    CMSampleBufferRef sb = NULL;
    CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
        pxBuf, fmt, &timing, &sb);
    CFRelease(fmt);
    CVPixelBufferRelease(pxBuf);
    return sb;
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sb
       fromConnection:(AVCaptureConnection *)conn {
    if (gEnabled) {
        [gLock lock];
        UIImage *img = gFrame;
        [gLock unlock];
        if (img) {
            CMSampleBufferRef fake = buildSampleBuffer(img);
            if (fake) {
                [self.original captureOutput:output
                       didOutputSampleBuffer:fake
                              fromConnection:conn];
                CFRelease(fake);
                return;
            }
        }
    }
    [self.original captureOutput:output
           didOutputSampleBuffer:sb
                  fromConnection:conn];
}

- (void)captureOutput:(AVCaptureOutput *)output
  didDropSampleBuffer:(CMSampleBufferRef)sb
       fromConnection:(AVCaptureConnection *)conn {
    if ([self.original respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)])
        [self.original captureOutput:output didDropSampleBuffer:sb fromConnection:conn];
}

- (BOOL)respondsToSelector:(SEL)sel {
    return [super respondsToSelector:sel] || [self.original respondsToSelector:sel];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    NSMethodSignature *sig = [super methodSignatureForSelector:sel];
    if (!sig) sig = [(id)self.original methodSignatureForSelector:sel];
    return sig;
}
- (void)forwardInvocation:(NSInvocation *)inv {
    if ([self.original respondsToSelector:inv.selector])
        [inv invokeWithTarget:self.original];
}

@end

// ── Bubble UI ─────────────────────────────────────────────────────────────
static void updateBubbleDot(void) {
    if (!gBubbleBtn) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *emoji = gEnabled ? @"🟢" : @"🎥";
        [gBubbleBtn setTitle:emoji forState:UIControlStateNormal];
    });
}

static void togglePanel(void);
static void savePrefs(void);

static void savePrefs(void) {
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    [p setBool:gEnabled forKey:@"vcamEnabled"];
    if (gURL) [p setObject:gURL forKey:@"streamURL"];
    [p synchronize];
    // Notify other processes
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vcamjoy.prefschanged"), NULL, NULL, YES);
}

static void togglePanel(void) {
    if (!gPanel) return;
    gPanelVisible = !gPanelVisible;
    [UIView animateWithDuration:0.25 animations:^{
        gPanel.alpha  = gPanelVisible ? 1.0 : 0.0;
        gPanel.hidden = NO;
    } completion:^(BOOL f) {
        if (!gPanelVisible) gPanel.hidden = YES;
    }];
}

static void makeBubble(void) {
    // Window riêng — level cao hơn alert để luôn nổi
    gBubbleWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    gBubbleWindow.windowLevel = UIWindowLevelAlert + 100;
    gBubbleWindow.backgroundColor = [UIColor clearColor];
    gBubbleWindow.userInteractionEnabled = YES;
    gBubbleWindow.hidden = NO;

    // Bubble button
    gBubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    gBubbleBtn.frame = CGRectMake(20, 100, 56, 56);
    gBubbleBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    gBubbleBtn.layer.cornerRadius = 28;
    gBubbleBtn.layer.shadowColor  = [UIColor blackColor].CGColor;
    gBubbleBtn.layer.shadowRadius = 6;
    gBubbleBtn.layer.shadowOpacity = 0.5;
    gBubbleBtn.layer.shadowOffset  = CGSizeMake(0,2);
    gBubbleBtn.titleLabel.font = [UIFont systemFontOfSize:26];
    [gBubbleBtn setTitle:@"🎥" forState:UIControlStateNormal];
    [gBubbleBtn addTarget:nil action:@selector(bubbleTapped)
         forControlEvents:UIControlEventTouchUpInside];

    // Drag gesture
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(bubblePanned:)];
    [gBubbleBtn addGestureRecognizer:pan];

    // Panel
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    gPanel = [[UIView alloc] initWithFrame:CGRectMake(20, 168, sw - 40, 200)];
    gPanel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    gPanel.layer.cornerRadius = 16;
    gPanel.layer.shadowColor  = [UIColor blackColor].CGColor;
    gPanel.layer.shadowRadius = 10;
    gPanel.layer.shadowOpacity = 0.6;
    gPanel.hidden = YES;
    gPanel.alpha  = 0;

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16,12,sw-72,24)];
    title.text = @"VCamJoy";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:16];
    [gPanel addSubview:title];

    // IP TextField
    gIPField = [[UITextField alloc] initWithFrame:CGRectMake(16,46,sw-72,40)];
    gIPField.placeholder = @"http://192.168.1.x:8080/stream";
    gIPField.text = gURL ?: @"";
    gIPField.textColor = [UIColor whiteColor];
    gIPField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    gIPField.layer.cornerRadius = 8;
    gIPField.keyboardType = UIKeyboardTypeURL;
    gIPField.autocorrectionType = UITextAutocorrectionTypeNo;
    gIPField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    // Padding
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,1)];
    gIPField.leftView = pad;
    gIPField.leftViewMode = UITextFieldViewModeAlways;
    [gPanel addSubview:gIPField];

    // Connect button
    UIButton *connectBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    connectBtn.frame = CGRectMake(16, 98, sw - 72, 40);
    connectBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1 alpha:1];
    connectBtn.layer.cornerRadius = 8;
    [connectBtn setTitle:@"Kết nối Stream" forState:UIControlStateNormal];
    [connectBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    connectBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [connectBtn addTarget:nil action:@selector(connectTapped)
         forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:connectBtn];

    // Switch row
    UILabel *swLabel = [[UILabel alloc] initWithFrame:CGRectMake(16,150,180,32)];
    swLabel.text = @"Bật Camera Ảo";
    swLabel.textColor = [UIColor whiteColor];
    swLabel.font = [UIFont systemFontOfSize:14];
    [gPanel addSubview:swLabel];

    gSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(sw-40-66,150,51,31)];
    gSwitch.on = gEnabled;
    gSwitch.onTintColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1];
    [gSwitch addTarget:nil action:@selector(switchChanged:)
      forControlEvents:UIControlEventValueChanged];
    [gPanel addSubview:gSwitch];

    [gBubbleWindow addSubview:gBubbleBtn];
    [gBubbleWindow addSubview:gPanel];
    [gBubbleWindow makeKeyAndVisible];

    // Bind actions via ViewController wrapper
    UIViewController *vc = [UIViewController new];
    vc.view = [[UIView alloc] initWithFrame:CGRectZero];
    gBubbleWindow.rootViewController = vc;

    NSLog(@"[VCamJoy] Bubble created on window level %.0f",
          gBubbleWindow.windowLevel);
}

// ── Action handler via swizzle target ─────────────────────────────────────
@interface VCamActionHandler : NSObject
@end
@implementation VCamActionHandler

+ (instancetype)shared {
    static VCamActionHandler *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (void)bubbleTapped { togglePanel(); }

- (void)bubblePanned:(UIPanGestureRecognizer *)gr {
    CGPoint delta = [gr translationInView:gBubbleWindow];
    CGRect f = gBubbleBtn.frame;
    f.origin.x += delta.x;
    f.origin.y += delta.y;
    // Clamp to screen
    CGSize sc = [UIScreen mainScreen].bounds.size;
    f.origin.x = MAX(0, MIN(f.origin.x, sc.width  - f.size.width));
    f.origin.y = MAX(20, MIN(f.origin.y, sc.height - f.size.height - 20));
    gBubbleBtn.frame = f;
    [gr setTranslation:CGPointZero inView:gBubbleWindow];

    // Move panel along
    if (!gPanel.hidden) {
        CGRect pf = gPanel.frame;
        pf.origin.x = MAX(8, MIN(f.origin.x - 8, sc.width - pf.size.width - 8));
        pf.origin.y = f.origin.y + f.size.height + 10;
        if (pf.origin.y + pf.size.height > sc.height - 20)
            pf.origin.y = f.origin.y - pf.size.height - 10;
        gPanel.frame = pf;
    }
}

- (void)connectTapped {
    NSString *urlStr = [gIPField.text stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!urlStr.length) return;
    gURL = urlStr;
    savePrefs();
    startStream(gURL);
    [gIPField resignFirstResponder];
}

- (void)switchChanged:(UISwitch *)sw {
    gEnabled = sw.on;
    savePrefs();
    if (gEnabled) {
        if (gURL) startStream(gURL);
    } else {
        stopStream();
    }
    updateBubbleDot();
}

@end

// Wire up selectors to handler after makeBubble
static void wireBubbleActions(void) {
    VCamActionHandler *h = [VCamActionHandler shared];
    // Re-add targets
    [gBubbleBtn removeTarget:nil action:NULL
            forControlEvents:UIControlEventTouchUpInside];
    [gBubbleBtn addTarget:h action:@selector(bubbleTapped)
        forControlEvents:UIControlEventTouchUpInside];

    for (UIGestureRecognizer *gr in gBubbleBtn.gestureRecognizers) {
        if ([gr isKindOfClass:[UIPanGestureRecognizer class]]) {
            [gr removeTarget:nil action:NULL];
            [gr addTarget:h action:@selector(bubblePanned:)];
        }
    }

    for (UIView *v in gPanel.subviews) {
        if ([v isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)v;
            NSString *t = [btn titleForState:UIControlStateNormal];
            if ([t containsString:@"nối"]) {
                [btn removeTarget:nil action:NULL
                 forControlEvents:UIControlEventTouchUpInside];
                [btn addTarget:h action:@selector(connectTapped)
                  forControlEvents:UIControlEventTouchUpInside];
            }
        }
        if ([v isKindOfClass:[UISwitch class]]) {
            UISwitch *sw = (UISwitch *)v;
            [sw removeTarget:nil action:NULL
                forControlEvents:UIControlEventValueChanged];
            [sw addTarget:h action:@selector(switchChanged:)
           forControlEvents:UIControlEventValueChanged];
        }
    }
}

static void showBubble(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gBubbleWindow) {
            gBubbleWindow.hidden = NO;
            [gBubbleWindow makeKeyAndVisible];
            return;
        }
        makeBubble();
        wireBubbleActions();
        updateBubbleDot();
        NSLog(@"[VCamJoy] Bubble shown!");
    });
}

// ── Theos Hooks ───────────────────────────────────────────────────────────
%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)d
                          queue:(dispatch_queue_t)q {
    if (!d || [d isKindOfClass:[VCamProxy class]]) { %orig; return; }
    if (!gProxies) gProxies = [NSMapTable weakToStrongObjectsMapTable];
    VCamProxy *proxy = [gProxies objectForKey:d];
    if (!proxy) {
        proxy = [VCamProxy new];
        proxy.original = d;
        [gProxies setObject:proxy forKey:d];
    }
    NSLog(@"[VCamJoy] Hooked output delegate: %@", NSStringFromClass([d class]));
    %orig(proxy, q);
}
%end

// Hook vào scene/window để show bubble khi app đã có window
%hook UIScene
- (void)_activateWithInfo:(id)info {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        showBubble();
    });
}
%end

// Fallback: hook UIApplication cho iOS 15 không dùng UIScene đúng cách
%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        showBubble();
    });
}
%end

// ── Prefs change notification ─────────────────────────────────────────────
static void vcamPrefsChanged(CFNotificationCenterRef c, void *o,
                              CFStringRef n, const void *ob, CFDictionaryRef ui) {
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled = [p boolForKey:@"vcamEnabled"];
    NSString *url = [p stringForKey:@"streamURL"];
    if (url) gURL = url;
    if (gEnabled && gURL) startStream(gURL);
    else stopStream();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gSwitch) gSwitch.on = gEnabled;
        updateBubbleDot();
    });
}

// ── Constructor ───────────────────────────────────────────────────────────
%ctor {
    NSLog(@"[VCamJoy] Tweak v3 loaded!");
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled = [p boolForKey:@"vcamEnabled"];
    gURL     = [p stringForKey:@"streamURL"];
    if (gEnabled && gURL) startStream(gURL);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        vcamPrefsChanged, CFSTR("com.vcamjoy.prefschanged"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

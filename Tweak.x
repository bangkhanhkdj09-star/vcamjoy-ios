/*
 * VCamJoy — Tweak.x v4.0
 * CHỈ hook camera — bubble UI nằm trong VCamJoy.app chạy nền
 * App và Tweak giao tiếp qua NSUserDefaults suite "com.vcamjoy.prefs"
 */

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

static BOOL           gEnabled = NO;
static NSString      *gURL     = nil;
static UIImage       *gFrame   = nil;
static NSLock        *gLock    = nil;
static NSURLSession  *gSession = nil;
static NSMutableData *gBuf     = nil;
static NSMapTable    *gProxies = nil;

// ── MJPEG receiver ────────────────────────────────────────────────────────
@interface VCJDelegate : NSObject <NSURLSessionDataDelegate>
@end
@implementation VCJDelegate
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t
    didReceiveData:(NSData *)data {
    if (!gBuf) gBuf = [NSMutableData data];
    [gBuf appendData:data];
    uint8_t sb[2]={0xFF,0xD8}, eb[2]={0xFF,0xD9};
    NSData *SOI=[NSData dataWithBytes:sb length:2];
    NSData *EOI=[NSData dataWithBytes:eb length:2];
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
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t
    didCompleteWithError:(NSError *)e {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),
        dispatch_get_main_queue(),^{
        if (gEnabled && gURL) {
            NSURL *u=[NSURL URLWithString:gURL];
            if (u) [[gSession dataTaskWithURL:u] resume];
        }
    });
}
@end
static VCJDelegate *gDel = nil;

static void vcjStart(NSString *url) {
    if (!url.length) return;
    NSURL *u=[NSURL URLWithString:url];
    if (!u) return;
    [gSession invalidateAndCancel];
    if (!gLock) gLock=[NSLock new];
    if (!gBuf)  gBuf=[NSMutableData data];
    if (!gDel)  gDel=[VCJDelegate new];
    NSURLSessionConfiguration *cfg=[NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest=10;
    cfg.timeoutIntervalForResource=86400;
    gSession=[NSURLSession sessionWithConfiguration:cfg delegate:gDel delegateQueue:nil];
    [[gSession dataTaskWithURL:u] resume];
}
static void vcjStop(void) {
    [gSession invalidateAndCancel]; gSession=nil;
    [gLock lock]; gFrame=nil; [gLock unlock];
}

// ── VCamProxy ─────────────────────────────────────────────────────────────
@interface VCJProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> orig;
@end
@implementation VCJProxy
static CMSampleBufferRef vcjMakeBuffer(UIImage *img) {
    CGImageRef cg=img.CGImage;
    size_t w=CGImageGetWidth(cg),h=CGImageGetHeight(cg);
    CVPixelBufferRef pb=NULL;
    NSDictionary *a=@{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,
                      (id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
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
            CMSampleBufferRef fake=vcjMakeBuffer(img);
            if (fake) {
                [self.orig captureOutput:o didOutputSampleBuffer:fake fromConnection:c];
                CFRelease(fake); return;
            }
        }
    }
    [self.orig captureOutput:o didOutputSampleBuffer:sb fromConnection:c];
}
- (void)captureOutput:(AVCaptureOutput *)o didDropSampleBuffer:(CMSampleBufferRef)sb
       fromConnection:(AVCaptureConnection *)c {
    if ([self.orig respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)])
        [self.orig captureOutput:o didDropSampleBuffer:sb fromConnection:c];
}
- (BOOL)respondsToSelector:(SEL)s {
    return [super respondsToSelector:s]||[self.orig respondsToSelector:s];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s {
    NSMethodSignature *sig=[super methodSignatureForSelector:s];
    return sig?:[(id)self.orig methodSignatureForSelector:s];
}
- (void)forwardInvocation:(NSInvocation *)inv {
    if ([self.orig respondsToSelector:inv.selector]) [inv invokeWithTarget:self.orig];
}
@end

// ── Theos Hook ────────────────────────────────────────────────────────────
%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)d
                          queue:(dispatch_queue_t)q {
    if (!d||[d isKindOfClass:[VCJProxy class]]){%orig;return;}
    if (!gProxies) gProxies=[NSMapTable weakToStrongObjectsMapTable];
    VCJProxy *p=[gProxies objectForKey:d];
    if (!p){p=[VCJProxy new];p.orig=d;[gProxies setObject:p forKey:d];}
    NSLog(@"[VCamJoy] Hooked: %@",NSStringFromClass([d class]));
    %orig(p,q);
}
%end

// ── Prefs notification ────────────────────────────────────────────────────
static void onPrefs(CFNotificationCenterRef c,void *o,CFStringRef n,
    const void *ob,CFDictionaryRef ui){
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    NSString *url=[p stringForKey:@"streamURL"];
    if (url) gURL=url;
    if (gEnabled&&gURL) vcjStart(gURL);
    else vcjStop();
    NSLog(@"[VCamJoy] Prefs updated — enabled:%d url:%@", (int)gEnabled, gURL);
}

%ctor {
    NSLog(@"[VCamJoy] Tweak v4.0 loaded");
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    gURL=[p stringForKey:@"streamURL"];
    if (gEnabled&&gURL) vcjStart(gURL);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,onPrefs,CFSTR("com.vcamjoy.prefschanged"),NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

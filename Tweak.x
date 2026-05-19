#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>

// ── Shared state ──────────────────────────────
static UIImage *gLatestFrame = nil;
static NSLock *gLock = nil;
static NSMutableData *gBuf = nil;
static NSData *kSOI = nil, *kEOI = nil;
static BOOL gEnabled = NO;
static NSURLSession *gSes = nil;
static NSURLSessionDataTask *gTask = nil;

// ── MJPEG receiver ────────────────────────────
@interface VCamStreamReceiver : NSObject <NSURLSessionDataDelegate>
+ (instancetype)shared;
- (void)startWithURL:(NSString *)urlStr;
- (void)stop;
@end

@implementation VCamStreamReceiver
+ (instancetype)shared {
    static VCamStreamReceiver *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    uint8_t s[]={0xFF,0xD8},e[]={0xFF,0xD9};
    kSOI=[NSData dataWithBytes:s length:2];
    kEOI=[NSData dataWithBytes:e length:2];
    gBuf=[NSMutableData data];
    gLock=[NSLock new];
    return self;
}
- (void)startWithURL:(NSString *)urlStr {
    [self stop];
    NSURL *url=[NSURL URLWithString:urlStr];
    if (!url) return;
    NSURLSessionConfiguration *cfg=[NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest=10;
    cfg.timeoutIntervalForResource=86400;
    gSes=[NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    gTask=[gSes dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
    [gTask resume];
    NSLog(@"[VCamJoy] Stream started: %@", urlStr);
}
- (void)stop {
    [gTask cancel]; gTask=nil;
    [gBuf setLength:0];
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t
didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h {
    [gBuf setLength:0]; h(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    [gBuf appendData:d];
    while (YES) {
        NSRange r1=[gBuf rangeOfData:kSOI options:0 range:NSMakeRange(0,gBuf.length)];
        if (r1.location==NSNotFound){[gBuf setLength:0];break;}
        NSRange sr=NSMakeRange(r1.location+2,gBuf.length-r1.location-2);
        NSRange r2=[gBuf rangeOfData:kEOI options:0 range:sr];
        if (r2.location==NSNotFound) break;
        NSUInteger end=r2.location+2;
        NSData *jpeg=[gBuf subdataWithRange:NSMakeRange(r1.location,end-r1.location)];
        [gBuf replaceBytesInRange:NSMakeRange(0,end) withBytes:NULL length:0];
        UIImage *img=[UIImage imageWithData:jpeg];
        if (!img) continue;
        [gLock lock]; gLatestFrame=img; [gLock unlock];
    }
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
    if (e && e.code!=NSURLErrorCancelled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
            NSString *url=[p stringForKey:@"streamURL"];
            if (url && gEnabled) [[VCamStreamReceiver shared] startWithURL:url];
        });
    }
}
@end

// ── UIImage → CMSampleBuffer ──────────────────
static CMSampleBufferRef imageToSampleBuffer(UIImage *image) CF_RETURNS_RETAINED {
    CGImageRef cg=image.CGImage; if (!cg) return NULL;
    size_t w=CGImageGetWidth(cg),h=CGImageGetHeight(cg);
    NSDictionary *a=@{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,
                      (id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
    CVPixelBufferRef pb=NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)a,&pb)!=kCVReturnSuccess) return NULL;
    CVPixelBufferLockBaseAddress(pb,0);
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb),w,h,8,
        CVPixelBufferGetBytesPerRow(pb),cs,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),cg);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pb,0);
    CMVideoFormatDescriptionRef fd=NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pb,&fd);
    if (!fd){CVPixelBufferRelease(pb);return NULL;}
    CMSampleTimingInfo ti={CMTimeMake(1,30),CMTimeMakeWithSeconds(CACurrentMediaTime(),90000),kCMTimeInvalid};
    CMSampleBufferRef sb=NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,pb,true,NULL,NULL,fd,&ti,&sb);
    CFRelease(fd); CVPixelBufferRelease(pb);
    return sb;
}

// ── Proxy delegate ────────────────────────────
@interface VCamProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> original;
@end

@implementation VCamProxy
- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (!gEnabled) {
        if ([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
            [self.original captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    [gLock lock]; UIImage *frame=gLatestFrame; [gLock unlock];
    if (!frame) {
        if ([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
            [self.original captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    CMSampleBufferRef fakeBuf=imageToSampleBuffer(frame);
    if (fakeBuf) {
        if ([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
            [self.original captureOutput:output didOutputSampleBuffer:fakeBuf fromConnection:connection];
        CFRelease(fakeBuf);
    }
}
- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sb fromConnection:(AVCaptureConnection *)c {
    if ([self.original respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)])
        [self.original captureOutput:output didDropSampleBuffer:sb fromConnection:c];
}
- (BOOL)respondsToSelector:(SEL)sel { return [super respondsToSelector:sel]||[self.original respondsToSelector:sel]; }
- (void)forwardInvocation:(NSInvocation *)inv { if ([self.original respondsToSelector:inv.selector]) [inv invokeWithTarget:self.original]; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [super methodSignatureForSelector:sel]?:[self.original methodSignatureForSelector:sel]; }
@end

// ── Hook ─────────────────────────────────────
static NSMapTable *gProxies = nil;

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue {
    if (!gProxies) gProxies=[NSMapTable weakToStrongObjectsMapTable];
    if (!delegate || [delegate isKindOfClass:[VCamProxy class]]) { %orig; return; }
    VCamProxy *proxy=[gProxies objectForKey:delegate];
    if (!proxy) {
        proxy=[VCamProxy new];
        proxy.original=delegate;
        [gProxies setObject:proxy forKey:delegate];
    }
    NSLog(@"[VCamJoy] Injected into: %@", NSStringFromClass([delegate class]));
    %orig(proxy, queue);
}
%end

// ── Init ──────────────────────────────────────
%ctor {
    NSLog(@"[VCamJoy Tweak] Loaded!");
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
    [p synchronize];
    gEnabled=[p boolForKey:@"vcamEnabled"];
    NSString *url=[p stringForKey:@"streamURL"];
    if (gEnabled && url) [[VCamStreamReceiver shared] startWithURL:url];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),NULL,
        (CFNotificationCallback)^(CFNotificationCenterRef c,void *o,CFStringRef n,const void *ob,CFDictionaryRef ui){
            NSUserDefaults *pp=[[NSUserDefaults alloc]initWithSuiteName:@"com.vcamjoy.prefs"];
            [pp synchronize];
            gEnabled=[pp boolForKey:@"vcamEnabled"];
            NSString *u=[pp stringForKey:@"streamURL"];
            if (gEnabled && u) [[VCamStreamReceiver shared] startWithURL:u];
            else [[VCamStreamReceiver shared] stop];
            NSLog(@"[VCamJoy] Prefs updated - enabled:%d", (int)gEnabled);
        },
        CFSTR("com.vcamjoy.prefschanged"),NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

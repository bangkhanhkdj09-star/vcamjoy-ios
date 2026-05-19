#import "VCamHook.h"
#import "VCamReceiver.h"
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>

static BOOL gEnabled = NO;

// ── UIImage → CMSampleBuffer ──────────────────
static CMSampleBufferRef imageToSampleBuffer(UIImage *image) CF_RETURNS_RETAINED {
    CGImageRef cg = image.CGImage;
    if (!cg) return NULL;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    NSDictionary *a = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    CVPixelBufferRef pb = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault, w, h,
        kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)a, &pb) != kCVReturnSuccess)
        return NULL;
    CVPixelBufferLockBaseAddress(pb, 0);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        CVPixelBufferGetBaseAddress(pb), w, h, 8,
        CVPixelBufferGetBytesPerRow(pb), cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pb, 0);
    CMVideoFormatDescriptionRef fd = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pb, &fd);
    if (!fd) { CVPixelBufferRelease(pb); return NULL; }
    CMSampleTimingInfo ti = {
        CMTimeMake(1, 30),
        CMTimeMakeWithSeconds(CACurrentMediaTime(), 90000),
        kCMTimeInvalid
    };
    CMSampleBufferRef sb = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pb, true, NULL, NULL, fd, &ti, &sb);
    CFRelease(fd); CVPixelBufferRelease(pb);
    return sb;
}

// ── Proxy Delegate ────────────────────────────
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
    // Lấy frame mới nhất từ VCamReceiver
    UIImage *frame = [[VCamReceiver sharedReceiver] latestImage];
    if (!frame) {
        if ([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
            [self.original captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }
    CMSampleBufferRef fake = imageToSampleBuffer(frame);
    if (fake) {
        if ([self.original respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)])
            [self.original captureOutput:output didOutputSampleBuffer:fake fromConnection:connection];
        CFRelease(fake);
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
  didDropSampleBuffer:(CMSampleBufferRef)sb
       fromConnection:(AVCaptureConnection *)c {
    if ([self.original respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)])
        [self.original captureOutput:output didDropSampleBuffer:sb fromConnection:c];
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

// ── Swizzle AVCaptureVideoDataOutput ─────────
@interface AVCaptureVideoDataOutput (VCamSwizzle)
@end

static NSMapTable *gProxies = nil;
static IMP gOrigSetDelegate = NULL;

static void vcam_setSampleBufferDelegate(id self, SEL _cmd,
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate,
    dispatch_queue_t queue) {
    if (!delegate || [delegate isKindOfClass:[VCamProxy class]]) {
        ((void(*)(id,SEL,id,dispatch_queue_t))gOrigSetDelegate)(self, _cmd, delegate, queue);
        return;
    }
    if (!gProxies) gProxies = [NSMapTable weakToStrongObjectsMapTable];
    VCamProxy *proxy = [gProxies objectForKey:delegate];
    if (!proxy) {
        proxy = [VCamProxy new];
        proxy.original = delegate;
        [gProxies setObject:proxy forKey:delegate];
    }
    NSLog(@"[VCamHook] Hooked delegate: %@", NSStringFromClass([delegate class]));
    ((void(*)(id,SEL,id,dispatch_queue_t))gOrigSetDelegate)(self, _cmd, proxy, queue);
}

// ── Public API ────────────────────────────────
@implementation VCamHook

+ (void)install {
    Class cls = [AVCaptureVideoDataOutput class];
    SEL sel = @selector(setSampleBufferDelegate:queue:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        gOrigSetDelegate = method_getImplementation(m);
        method_setImplementation(m, (IMP)vcam_setSampleBufferDelegate);
        NSLog(@"[VCamHook] Installed successfully");
    }
}

+ (void)setEnabled:(BOOL)enabled {
    gEnabled = enabled;
    NSLog(@"[VCamHook] Enabled: %d", (int)enabled);
}

+ (void)setStreamURL:(NSString *)url {
    if (url.length) {
        [[VCamReceiver sharedReceiver] startWithURL:[NSURL URLWithString:url]];
    } else {
        [[VCamReceiver sharedReceiver] stop];
    }
}

@end

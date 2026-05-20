#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "VCFrameProvider.h"

static void VCLog(NSString *message) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, message];
    NSString *path = @"/var/mobile/Library/Logs/VCamBubble.log";
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [data writeToFile:path atomically:YES];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

@interface VCCameraDelegateProxy : NSObject
@property (nonatomic, weak) id originalDelegate;
@end

@implementation VCCameraDelegateProxy

- (BOOL)respondsToSelector:(SEL)aSelector {
    if (aSelector == @selector(captureOutput:didOutputSampleBuffer:fromConnection:)) return YES;
    return [self.originalDelegate respondsToSelector:aSelector] || [super respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.originalDelegate respondsToSelector:aSelector]) return self.originalDelegate;
    return [super forwardingTargetForSelector:aSelector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *signature = [super methodSignatureForSelector:aSelector];
    if (!signature) signature = [(NSObject *)self.originalDelegate methodSignatureForSelector:aSelector];
    return signature;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    if ([self.originalDelegate respondsToSelector:invocation.selector]) {
        [invocation invokeWithTarget:self.originalDelegate];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    id delegate = self.originalDelegate;
    if (!delegate || ![delegate respondsToSelector:_cmd]) return;

    CMSampleBufferRef replacement = [[VCFrameProvider sharedProvider] newSampleBufferMatching:sampleBuffer];
    CMSampleBufferRef bufferToSend = replacement ?: sampleBuffer;

    void (*invoke)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *) =
        (void (*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))[delegate methodForSelector:_cmd];
    invoke(delegate, _cmd, output, bufferToSend, connection);

    if (replacement) CFRelease(replacement);
}

@end

static const void *VCProxyKey = &VCProxyKey;
static const void *VCPreviewLayerKey = &VCPreviewLayerKey;
static const void *VCPreviewTimerKey = &VCPreviewTimerKey;

static id VCProxyForDelegate(id delegate) {
    if (!delegate) return nil;
    VCCameraDelegateProxy *proxy = objc_getAssociatedObject(delegate, VCProxyKey);
    if (!proxy) {
        proxy = [VCCameraDelegateProxy new];
        proxy.originalDelegate = delegate;
        objc_setAssociatedObject(delegate, VCProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        VCLog([NSString stringWithFormat:@"camera delegate proxied in %@ delegate=%@", NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName, NSStringFromClass([delegate class])]);
    }
    return proxy;
}

%ctor {
    VCLog([NSString stringWithFormat:@"hook dylib loaded in %@", NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName]);
}

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    id proxy = VCProxyForDelegate(delegate);
    %orig(proxy ?: delegate, sampleBufferCallbackQueue);
}

%end

static void VCInstallPreviewLayer(AVCaptureVideoPreviewLayer *layer) {
    if (!layer) return;

    CALayer *overlay = objc_getAssociatedObject(layer, VCPreviewLayerKey);
    if (!overlay) {
        overlay = [CALayer layer];
        overlay.name = @"VCamJoyPreviewOverlay";
        overlay.contentsGravity = kCAGravityResizeAspect;
        overlay.backgroundColor = UIColor.blackColor.CGColor;
        overlay.masksToBounds = YES;
        objc_setAssociatedObject(layer, VCPreviewLayerKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [layer addSublayer:overlay];
        VCLog([NSString stringWithFormat:@"preview layer hooked in %@", NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName]);
    }

    overlay.frame = layer.bounds;
    CGImageRef image = [[VCFrameProvider sharedProvider] latestCGImage];
    overlay.hidden = image == nil;
    if (image) overlay.contents = (__bridge id)image;

    NSTimer *timer = objc_getAssociatedObject(layer, VCPreviewTimerKey);
    if (!timer) {
        timer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 30.0) repeats:YES block:^(__unused NSTimer *timer) {
            CALayer *currentOverlay = objc_getAssociatedObject(layer, VCPreviewLayerKey);
            if (!currentOverlay) return;
            currentOverlay.frame = layer.bounds;
            CGImageRef currentImage = [[VCFrameProvider sharedProvider] latestCGImage];
            currentOverlay.hidden = currentImage == nil;
            if (currentImage) currentOverlay.contents = (__bridge id)currentImage;
        }];
        objc_setAssociatedObject(layer, VCPreviewTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook AVCaptureVideoPreviewLayer

+ (instancetype)layerWithSession:(AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *layer = %orig(session);
    VCInstallPreviewLayer(layer);
    return layer;
}

- (instancetype)initWithSession:(AVCaptureSession *)session {
    self = %orig(session);
    VCInstallPreviewLayer((AVCaptureVideoPreviewLayer *)self);
    return self;
}

- (void)setSession:(AVCaptureSession *)session {
    %orig(session);
    VCInstallPreviewLayer((AVCaptureVideoPreviewLayer *)self);
}

- (void)layoutSublayers {
    %orig;
    VCInstallPreviewLayer((AVCaptureVideoPreviewLayer *)self);
}

%end

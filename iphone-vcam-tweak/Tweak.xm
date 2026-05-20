#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <stdlib.h>
#include <string.h>
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
static NSMutableSet<NSString *> *VCHookedRuntimeKeys;
static NSMutableDictionary<NSString *, NSValue *> *VCOriginalIMPs;

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

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    id proxy = VCProxyForDelegate(delegate);
    %orig(proxy ?: delegate, sampleBufferCallbackQueue);
}

%end

static CMSampleBufferRef VCReplacementForSample(CMSampleBufferRef sample) {
    if (!sample) return nil;
    return [[VCFrameProvider sharedProvider] newSampleBufferMatching:sample];
}

static NSString *VCIMPKey(id self, SEL selector) {
    return [NSString stringWithFormat:@"%@-%@", NSStringFromClass(object_getClass(self)), NSStringFromSelector(selector)];
}

static IMP VCOriginalIMP(id self, SEL selector) {
    return [VCOriginalIMPs[VCIMPKey(self, selector)] pointerValue];
}

static void repl_emitSampleBuffer(id self, SEL _cmd, CMSampleBufferRef sample) {
    CMSampleBufferRef replacement = VCReplacementForSample(sample);
    void (*orig)(id, SEL, CMSampleBufferRef) = (void *)VCOriginalIMP(self, _cmd);
    if (!orig) return;
    orig(self, _cmd, replacement ?: sample);
    if (replacement) CFRelease(replacement);
}

static void repl_setBGRASampleBuffer(id self, SEL _cmd, CMSampleBufferRef sample) {
    CMSampleBufferRef replacement = VCReplacementForSample(sample);
    void (*orig)(id, SEL, CMSampleBufferRef) = (void *)VCOriginalIMP(self, _cmd);
    if (!orig) return;
    orig(self, _cmd, replacement ?: sample);
    if (replacement) CFRelease(replacement);
}

static void repl_setYUVSampleBuffer(id self, SEL _cmd, CMSampleBufferRef sample) {
    CMSampleBufferRef replacement = VCReplacementForSample(sample);
    void (*orig)(id, SEL, CMSampleBufferRef) = (void *)VCOriginalIMP(self, _cmd);
    if (!orig) return;
    orig(self, _cmd, replacement ?: sample);
    if (replacement) CFRelease(replacement);
}

static void repl_renderSampleBufferForInput(id self, SEL _cmd, CMSampleBufferRef sample, id input) {
    CMSampleBufferRef replacement = VCReplacementForSample(sample);
    void (*orig)(id, SEL, CMSampleBufferRef, id) = (void *)VCOriginalIMP(self, _cmd);
    if (!orig) return;
    orig(self, _cmd, replacement ?: sample, input);
    if (replacement) CFRelease(replacement);
}

static CMSampleBufferRef repl_copyNextSampleBuffer(id self, SEL _cmd) {
    CMSampleBufferRef (*orig)(id, SEL) = (void *)VCOriginalIMP(self, _cmd);
    if (!orig) return nil;
    CMSampleBufferRef original = orig(self, _cmd);
    CMSampleBufferRef replacement = VCReplacementForSample(original);
    if (replacement) {
        if (original) CFRelease(original);
        return replacement;
    }
    return original;
}

static void VCHookSelector(Class cls, SEL selector, IMP replacement, NSString *typeName) {
    if (!cls || !selector || !class_getInstanceMethod(cls, selector)) return;
    NSString *key = [NSString stringWithFormat:@"%@-%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
    if ([VCHookedRuntimeKeys containsObject:key]) return;
    IMP original = NULL;
    MSHookMessageEx(cls, selector, replacement, &original);
    if (original) VCOriginalIMPs[key] = [NSValue valueWithPointer:original];
    [VCHookedRuntimeKeys addObject:key];
    VCLog([NSString stringWithFormat:@"runtime hook %@ %@", key, typeName]);
}

static void VCInstallMediaServerHooks(void) {
    NSString *process = NSProcessInfo.processInfo.processName;
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![process isEqualToString:@"mediaserverd"] && ![bundle isEqualToString:@"com.apple.mediaserverd"]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        VCHookedRuntimeKeys = [NSMutableSet set];
        VCOriginalIMPs = [NSMutableDictionary dictionary];
    });

    NSArray<NSString *> *classNames = @[
        @"BWNode",
        @"BWNodeOutput",
        @"BWPixelTransferNode",
        @"BWUBNode",
        @"BWStillImageScalerNode",
        @"BWPhotoEncoderNode",
        @"BWVideoOrientationMetadataNode"
    ];

    for (NSString *className in classNames) {
        Class cls = objc_getClass(className.UTF8String);
        VCHookSelector(cls, @selector(emitSampleBuffer:), (IMP)repl_emitSampleBuffer, @"emit");
        VCHookSelector(cls, @selector(setBGRASampleBuffer:), (IMP)repl_setBGRASampleBuffer, @"bgra");
        VCHookSelector(cls, @selector(setYUVSampleBuffer:), (IMP)repl_setYUVSampleBuffer, @"yuv");
        VCHookSelector(cls, @selector(renderSampleBuffer:forInput:), (IMP)repl_renderSampleBufferForInput, @"render");
        VCHookSelector(cls, @selector(copyNextSampleBuffer), (IMP)repl_copyNextSampleBuffer, @"copy");
    }

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    Class *classes = (Class *)calloc((size_t)classCount, sizeof(Class));
    classCount = objc_getClassList(classes, classCount);
    for (int i = 0; i < classCount; i++) {
        const char *name = class_getName(classes[i]);
        if (!name || strncmp(name, "BW", 2) != 0) continue;
        Class cls = classes[i];
        VCHookSelector(cls, @selector(emitSampleBuffer:), (IMP)repl_emitSampleBuffer, @"emit-scan");
        VCHookSelector(cls, @selector(setBGRASampleBuffer:), (IMP)repl_setBGRASampleBuffer, @"bgra-scan");
        VCHookSelector(cls, @selector(setYUVSampleBuffer:), (IMP)repl_setYUVSampleBuffer, @"yuv-scan");
        VCHookSelector(cls, @selector(renderSampleBuffer:forInput:), (IMP)repl_renderSampleBufferForInput, @"render-scan");
        VCHookSelector(cls, @selector(copyNextSampleBuffer), (IMP)repl_copyNextSampleBuffer, @"copy-scan");
    }
    free(classes);
}

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

%ctor {
    NSString *process = NSProcessInfo.processInfo.processName;
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    VCLog([NSString stringWithFormat:@"hook dylib loaded in %@ %@", process, bundle]);
    VCInstallMediaServerHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        VCInstallMediaServerHooks();
    });
}

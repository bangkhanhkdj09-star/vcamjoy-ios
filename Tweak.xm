#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "VCFrameSource.h"

static CMSampleBufferRef VCCopyReplacementForSampleBuffer(CMSampleBufferRef sampleBuffer);
static CMSampleBufferRef VCCopyReplacementNotingHook(NSString *hookName, CMSampleBufferRef sampleBuffer);
static void VCInstallRuntimeHooks(void);

@interface VCDelegateProxy : NSObject
@property(nonatomic, weak) id originalDelegate;
@end

@implementation VCDelegateProxy

- (instancetype)initWithDelegate:(id)delegate {
    self = [super init];
    if (self) {
        _originalDelegate = delegate;
    }
    return self;
}

- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(captureOutput:didOutputSampleBuffer:fromConnection:)) {
        return [_originalDelegate respondsToSelector:selector];
    }
    return [super respondsToSelector:selector] || [_originalDelegate respondsToSelector:selector];
}

- (id)forwardingTargetForSelector:(SEL)selector {
    return _originalDelegate;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [(NSObject *)_originalDelegate methodSignatureForSelector:selector] ?: [super methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    if (_originalDelegate) {
        [invocation invokeWithTarget:_originalDelegate];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    id delegate = _originalDelegate;
    if (!delegate || ![delegate respondsToSelector:_cmd]) {
        return;
    }

    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"AVCaptureVideoDataOutput.delegate", sampleBuffer);
    CMSampleBufferRef delivered = replacement ?: sampleBuffer;

    void (*send)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *) =
        (void (*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))objc_msgSend;
    send(delegate, _cmd, output, delivered, connection);

    if (replacement) {
        CFRelease(replacement);
    }
}

@end

static const void *VCDelegateProxyKey = &VCDelegateProxyKey;

static CMSampleBufferRef VCCopyReplacementForSampleBuffer(CMSampleBufferRef sampleBuffer) {
    return [[VCFrameSource sharedSource] copyFrameMatchingSampleBuffer:sampleBuffer];
}

static CMSampleBufferRef VCCopyReplacementNotingHook(NSString *hookName, CMSampleBufferRef sampleBuffer) {
    [[VCFrameSource sharedSource] noteHook:hookName sampleBuffer:sampleBuffer];
    return VCCopyReplacementForSampleBuffer(sampleBuffer);
}

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (!delegate) {
        objc_setAssociatedObject(self, VCDelegateProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig(nil, sampleBufferCallbackQueue);
        return;
    }

    VCDelegateProxy *proxy = [[VCDelegateProxy alloc] initWithDelegate:delegate];
    objc_setAssociatedObject(self, VCDelegateProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig((id<AVCaptureVideoDataOutputSampleBufferDelegate>)proxy, sampleBufferCallbackQueue);
}

%end

static NSMutableDictionary<NSString *, NSValue *> *VCOriginalIMPs;

static NSString *VCIMPKey(id self, SEL selector) {
    return [NSString stringWithFormat:@"%@.%@", NSStringFromClass([self class]), NSStringFromSelector(selector)];
}

static IMP VCOriginalIMP(id self, SEL selector) {
    return [VCOriginalIMPs[VCIMPKey(self, selector)] pointerValue];
}

static void repl_emitSampleBuffer(id self, SEL _cmd, CMSampleBufferRef sampleBuffer) {
    NSString *hookName = [NSString stringWithFormat:@"%@.%@", NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(hookName, sampleBuffer);
    void (*original)(id, SEL, CMSampleBufferRef) = (void (*)(id, SEL, CMSampleBufferRef))VCOriginalIMP(self, _cmd);
    if (!original) {
        return;
    }
    original(self, _cmd, replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

static void repl_setOneSampleBuffer(id self, SEL _cmd, CMSampleBufferRef sampleBuffer) {
    NSString *hookName = [NSString stringWithFormat:@"%@.%@", NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(hookName, sampleBuffer);
    void (*original)(id, SEL, CMSampleBufferRef) = (void (*)(id, SEL, CMSampleBufferRef))VCOriginalIMP(self, _cmd);
    if (!original) {
        return;
    }
    original(self, _cmd, replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

static void repl_renderSampleBufferForInput(id self, SEL _cmd, CMSampleBufferRef sampleBuffer, id input) {
    NSString *hookName = [NSString stringWithFormat:@"%@.%@", NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(hookName, sampleBuffer);
    void (*original)(id, SEL, CMSampleBufferRef, id) = (void (*)(id, SEL, CMSampleBufferRef, id))VCOriginalIMP(self, _cmd);
    if (!original) {
        return;
    }
    original(self, _cmd, replacement ?: sampleBuffer, input);
    if (replacement) {
        CFRelease(replacement);
    }
}

static BOOL VCHookClassSelector(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        return NO;
    }

    NSString *key = [NSString stringWithFormat:@"%@.%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
    if (VCOriginalIMPs[key]) {
        return NO;
    }

    IMP original = nil;
    MSHookMessageEx(cls, selector, replacement, &original);
    if (!original) {
        return NO;
    }
    VCOriginalIMPs[key] = [NSValue valueWithPointer:original];
    [[VCFrameSource sharedSource] noteEvent:[NSString stringWithFormat:@"runtime hook installed %@.%@",
                                             NSStringFromClass(cls),
                                             NSStringFromSelector(selector)]];
    return YES;
}

static void VCInstallRuntimeHooks(void) {
    if (!VCOriginalIMPs) {
        VCOriginalIMPs = [NSMutableDictionary dictionary];
    }

    NSArray<NSString *> *classNames = @[
        @"BWNodeOutput",
        @"BWNode",
        @"BWPixelTransferNode",
        @"BWStillImageScalerNode",
        @"FigCaptureSourceVideoDataSinkPipeline",
        @"FigCaptureSourceVideoDataSink",
        @"FigCaptureSource",
        @"FigCaptureSink",
        @"FigCaptureVideoDataSink"
    ];

    for (NSString *className in classNames) {
        Class cls = objc_getClass(className.UTF8String);
        if (!cls) {
            continue;
        }
        VCHookClassSelector(cls, @selector(emitSampleBuffer:), (IMP)repl_emitSampleBuffer);
        VCHookClassSelector(cls, @selector(setLiveSampleBuffer:), (IMP)repl_setOneSampleBuffer);
        VCHookClassSelector(cls, @selector(setLiveBGRASampleBuffer:), (IMP)repl_setOneSampleBuffer);
        VCHookClassSelector(cls, @selector(setBGRASampleBuffer:), (IMP)repl_setOneSampleBuffer);
        VCHookClassSelector(cls, @selector(setYUVSampleBuffer:), (IMP)repl_setOneSampleBuffer);
        VCHookClassSelector(cls, @selector(renderSampleBuffer:forInput:), (IMP)repl_renderSampleBufferForInput);
    }
}

%ctor {
    @autoreleasepool {
        [[VCFrameSource sharedSource] reloadConfiguration];
        [[VCFrameSource sharedSource] noteEvent:[NSString stringWithFormat:@"ctor loaded process=%@", NSProcessInfo.processInfo.processName]];
        VCInstallRuntimeHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VCInstallRuntimeHooks();
            [[VCFrameSource sharedSource] noteEvent:@"runtime hook rescan done"];
        });
    }
}

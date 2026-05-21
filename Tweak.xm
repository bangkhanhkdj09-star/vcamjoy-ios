#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "VCFrameSource.h"

static CMSampleBufferRef VCCopyReplacementForSampleBuffer(CMSampleBufferRef sampleBuffer);
static CMSampleBufferRef VCCopyReplacementNotingHook(NSString *hookName, CMSampleBufferRef sampleBuffer);

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

%hook BWNodeOutput

- (void)emitSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"BWNodeOutput.emitSampleBuffer", sampleBuffer);
    %orig(replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

%end

%hook BWNode

- (void)renderSampleBuffer:(CMSampleBufferRef)sampleBuffer forInput:(id)input {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"BWNode.renderSampleBuffer:forInput:", sampleBuffer);
    %orig(replacement ?: sampleBuffer, input);
    if (replacement) {
        CFRelease(replacement);
    }
}

%end

%hook BWPixelTransferNode

- (void)renderSampleBuffer:(CMSampleBufferRef)sampleBuffer forInput:(id)input {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"BWPixelTransferNode.renderSampleBuffer:forInput:", sampleBuffer);
    %orig(replacement ?: sampleBuffer, input);
    if (replacement) {
        CFRelease(replacement);
    }
}

%end

%hook FigCaptureSourceVideoDataSinkPipeline

- (void)setLiveSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"FigCaptureSourceVideoDataSinkPipeline.setLiveSampleBuffer:", sampleBuffer);
    %orig(replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

- (void)setLiveBGRASampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"FigCaptureSourceVideoDataSinkPipeline.setLiveBGRASampleBuffer:", sampleBuffer);
    %orig(replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

- (void)setBGRASampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"FigCaptureSourceVideoDataSinkPipeline.setBGRASampleBuffer:", sampleBuffer);
    %orig(replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

- (void)setYUVSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"FigCaptureSourceVideoDataSinkPipeline.setYUVSampleBuffer:", sampleBuffer);
    %orig(replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

%end

%hook FigCaptureSourceVideoDataSink

- (void)setLiveSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"FigCaptureSourceVideoDataSink.setLiveSampleBuffer:", sampleBuffer);
    %orig(replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

- (void)setLiveBGRASampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMSampleBufferRef replacement = VCCopyReplacementNotingHook(@"FigCaptureSourceVideoDataSink.setLiveBGRASampleBuffer:", sampleBuffer);
    %orig(replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

%end

%ctor {
    @autoreleasepool {
        [[VCFrameSource sharedSource] reloadConfiguration];
        [[VCFrameSource sharedSource] noteEvent:[NSString stringWithFormat:@"ctor loaded process=%@", NSProcessInfo.processInfo.processName]];
    }
}

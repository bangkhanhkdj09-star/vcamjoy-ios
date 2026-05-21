#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "VCFrameSource.h"

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

    [[VCFrameSource sharedSource] noteHook:@"AVCaptureVideoDataOutput.delegate" sampleBuffer:sampleBuffer];
    CMSampleBufferRef replacement = [[VCFrameSource sharedSource] copyFrameMatchingSampleBuffer:sampleBuffer];
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
    [[VCFrameSource sharedSource] noteHook:@"BWNodeOutput.emitSampleBuffer" sampleBuffer:sampleBuffer];
    CMSampleBufferRef replacement = VCCopyReplacementForSampleBuffer(sampleBuffer);
    %orig(replacement ?: sampleBuffer);
    if (replacement) {
        CFRelease(replacement);
    }
}

%end

%ctor {
    @autoreleasepool {
        [[VCFrameSource sharedSource] reloadConfiguration];
    }
}

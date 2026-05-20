#import <AVFoundation/AVFoundation.h>
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

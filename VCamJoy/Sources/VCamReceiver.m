#import "VCamReceiver.h"
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>

static NSData *kSOI, *kEOI;

@interface VCamReceiver ()
@property (strong) NSURLSession       *session;
@property (strong) NSURLSessionDataTask *task;
@property (strong) NSMutableData      *buf;
@property (assign) CMSampleBufferRef   latest;
@property (strong) NSLock             *lock;
@property (strong) dispatch_queue_t    decodeQ;
@property (assign) BOOL                connected;
@property (assign) NSUInteger          frameCount;
@property (assign) CFTimeInterval      fpsT;
@property (assign) NSUInteger          fpsC;
@property (assign) double              fps;
@property (strong) NSURL              *url;
@end

@implementation VCamReceiver

+ (instancetype)sharedReceiver {
    static VCamReceiver *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; }); return s;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    uint8_t soi[]={0xFF,0xD8}, eoi[]={0xFF,0xD9};
    kSOI = [NSData dataWithBytes:soi length:2];
    kEOI = [NSData dataWithBytes:eoi length:2];
    _buf     = [NSMutableData data];
    _lock    = [NSLock new];
    _decodeQ = dispatch_queue_create("vcam.decode", DISPATCH_QUEUE_SERIAL);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 10;
    cfg.timeoutIntervalForResource = 86400;
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    return self;
}

- (void)startWithURL:(NSURL *)url {
    [self stop]; self.url = url;
    self.task = [self.session dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
    [self.task resume];
}

- (void)stop {
    [self.task cancel]; self.task = nil; self.connected = NO;
    [self.buf setLength:0];
}

- (CMSampleBufferRef)copyLatestSampleBuffer {
    [self.lock lock];
    CMSampleBufferRef b = self.latest;
    if (b) CFRetain(b);
    [self.lock unlock];
    return b;
}

- (BOOL)isConnected { return _connected; }
- (double)currentFPS { return _fps; }

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t
didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h {
    self.connected = YES; [self.buf setLength:0]; h(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    [self.buf appendData:d];
    [self parse];
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
    self.connected = NO;
    if (e && e.code != NSURLErrorCancelled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if (self.url) [self startWithURL:self.url];
        });
    }
}

- (void)parse {
    while (YES) {
        NSRange r1 = [self.buf rangeOfData:kSOI options:0 range:NSMakeRange(0,self.buf.length)];
        if (r1.location == NSNotFound) { [self.buf setLength:0]; break; }
        NSRange sr = NSMakeRange(r1.location+2, self.buf.length-r1.location-2);
        NSRange r2 = [self.buf rangeOfData:kEOI options:0 range:sr];
        if (r2.location == NSNotFound) break;
        NSUInteger end = r2.location+2;
        NSData *jpeg = [self.buf subdataWithRange:NSMakeRange(r1.location, end-r1.location)];
        [self.buf replaceBytesInRange:NSMakeRange(0,end) withBytes:NULL length:0];
        dispatch_async(self.decodeQ, ^{ [self decode:jpeg]; });
    }
}

- (void)decode:(NSData *)jpeg {
    UIImage *img = [UIImage imageWithData:jpeg];
    if (!img) return;
    CMSampleBufferRef sb = [self makeSampleBuffer:img];
    if (!sb) return;
    [self.lock lock];
    if (self.latest) CFRelease(self.latest);
    self.latest = sb;
    [self.lock unlock];
    // FPS
    _fpsC++;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _fpsT >= 1.0) { _fps = _fpsC/(now-_fpsT); _fpsC=0; _fpsT=now; }
}

- (CMSampleBufferRef)makeSampleBuffer:(UIImage *)img CF_RETURNS_RETAINED {
    CGImageRef cg = img.CGImage; if (!cg) return NULL;
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    CVPixelBufferRef pb = NULL;
    NSDictionary *a = @{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,
                        (id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
    if (CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)a,&pb) != kCVReturnSuccess) return NULL;
    CVPixelBufferLockBaseAddress(pb,0);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb),w,h,8,
        CVPixelBufferGetBytesPerRow(pb),cs,
        kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(ctx,CGRectMake(0,0,w,h),cg);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    CVPixelBufferUnlockBaseAddress(pb,0);

    CMVideoFormatDescriptionRef fd = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pb,&fd);
    if (!fd) { CVPixelBufferRelease(pb); return NULL; }

    CMSampleTimingInfo ti = {
        CMTimeMake(1,30),
        CMTimeMakeWithSeconds(CACurrentMediaTime(),90000),
        kCMTimeInvalid
    };
    CMSampleBufferRef sb = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,pb,true,NULL,NULL,fd,&ti,&sb);
    CFRelease(fd); CVPixelBufferRelease(pb);
    return sb;
}
@end

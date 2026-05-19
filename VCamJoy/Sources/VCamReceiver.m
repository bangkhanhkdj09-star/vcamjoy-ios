#import "VCamReceiver.h"

static NSData *kSOI = nil;
static NSData *kEOI = nil;

@interface VCamReceiver ()
@property (strong) NSURLSession *session;
@property (strong) NSURLSessionDataTask *task;
@property (strong) NSMutableData *buf;
@property (assign) BOOL connected;
@property (strong) NSURL *streamURL;
@property (strong) UIImage *_latestImage;
@property (strong) NSLock *lock;
@end

@implementation VCamReceiver

+ (instancetype)sharedReceiver {
    static VCamReceiver *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    uint8_t s[] = {0xFF, 0xD8}, e[] = {0xFF, 0xD9};
    kSOI = [NSData dataWithBytes:s length:2];
    kEOI = [NSData dataWithBytes:e length:2];
    _buf  = [NSMutableData data];
    _lock = [NSLock new];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 10;
    cfg.timeoutIntervalForResource = 86400;
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    return self;
}

- (void)startWithURL:(NSURL *)url {
    [self stop];
    self.streamURL = url;
    self.task = [self.session dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
    [self.task resume];
    NSLog(@"[VCamReceiver] Start: %@", url);
}

- (void)stop {
    [self.task cancel]; self.task = nil;
    self.connected = NO;
    [self.buf setLength:0];
}

- (BOOL)isConnected { return _connected; }

- (UIImage *)latestImage {
    [self.lock lock];
    UIImage *img = self._latestImage;
    [self.lock unlock];
    return img;
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t
didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h {
    self.connected = YES;
    [self.buf setLength:0];
    h(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    [self.buf appendData:d];
    [self parse];
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
    self.connected = NO;
    if (e && e.code != NSURLErrorCancelled && self.streamURL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self startWithURL:self.streamURL];
        });
    }
}

- (void)parse {
    while (YES) {
        NSRange r1 = [self.buf rangeOfData:kSOI options:0 range:NSMakeRange(0, self.buf.length)];
        if (r1.location == NSNotFound) { [self.buf setLength:0]; break; }
        NSRange sr = NSMakeRange(r1.location+2, self.buf.length-r1.location-2);
        NSRange r2 = [self.buf rangeOfData:kEOI options:0 range:sr];
        if (r2.location == NSNotFound) break;
        NSUInteger end = r2.location + 2;
        NSData *jpeg = [self.buf subdataWithRange:NSMakeRange(r1.location, end-r1.location)];
        [self.buf replaceBytesInRange:NSMakeRange(0, end) withBytes:NULL length:0];
        UIImage *img = [UIImage imageWithData:jpeg];
        if (!img) continue;
        [self.lock lock];
        self._latestImage = img;
        [self.lock unlock];
    }
}

@end

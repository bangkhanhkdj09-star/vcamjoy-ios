#import "VCFrameProvider.h"
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <string.h>
#import <unistd.h>

static NSString * const VCPrefsPath = @"/var/mobile/Library/Preferences/local.vcambubble.plist";

@interface VCFrameProvider ()
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong) UIImage *latestImage;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation VCFrameProvider

+ (instancetype)sharedProvider {
    static VCFrameProvider *provider;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        provider = [VCFrameProvider new];
        [provider reloadPrefs];
        [provider startPolling];
    });
    return provider;
}

- (BOOL)isEnabled {
    [self reloadPrefs];
    return self.enabled && self.baseURL.length > 0 && self.latestImage != nil;
}

- (void)reloadPrefs {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCPrefsPath];
    self.enabled = [prefs[@"enabled"] boolValue];
    NSString *url = prefs[@"baseURL"];
    if ([url isKindOfClass:NSString.class]) self.baseURL = url;
}

- (void)startPolling {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.12 repeats:YES block:^(__unused NSTimer *timer) {
            [self fetchFrame];
        }];
    });
}

- (void)fetchFrame {
    [self reloadPrefs];
    if (!self.enabled || !self.baseURL.length) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *data = [self fetchSnapshotWithSocket];
        if (!data.length) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        self.latestImage = image;
    });
}

- (NSData *)fetchSnapshotWithSocket {
    NSURLComponents *components = [NSURLComponents componentsWithString:self.baseURL];
    NSString *host = components.host;
    NSInteger port = components.port ? components.port.integerValue : 8080;
    if (!host.length) return nil;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return nil;

    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host.UTF8String, &addr.sin_addr) != 1) {
        close(fd);
        return nil;
    }

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return nil;
    }

    NSString *request = [NSString stringWithFormat:@"GET /snapshot.jpg?t=%lld HTTP/1.1\r\nHost: %@\r\nConnection: close\r\n\r\n", (long long)(NSDate.date.timeIntervalSince1970 * 1000), host];
    NSData *requestData = [request dataUsingEncoding:NSUTF8StringEncoding];
    send(fd, requestData.bytes, requestData.length, 0);

    NSMutableData *response = [NSMutableData data];
    uint8_t buffer[8192];
    ssize_t count = 0;
    while ((count = recv(fd, buffer, sizeof(buffer), 0)) > 0) {
        [response appendBytes:buffer length:(NSUInteger)count];
    }
    close(fd);

    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange headerEnd = [response rangeOfData:separator options:0 range:NSMakeRange(0, response.length)];
    if (headerEnd.location == NSNotFound) return nil;
    NSUInteger bodyStart = headerEnd.location + headerEnd.length;
    if (bodyStart >= response.length) return nil;
    return [response subdataWithRange:NSMakeRange(bodyStart, response.length - bodyStart)];
}

- (CVPixelBufferRef)newPixelBufferWithWidth:(size_t)width height:(size_t)height {
    UIImage *image = self.latestImage;
    if (!image) return nil;

    NSDictionary *attrs = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };

    CVPixelBufferRef pixelBuffer = nil;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &pixelBuffer);
    if (status != kCVReturnSuccess || !pixelBuffer) return nil;

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *base = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(base, width, height, 8, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);

    if (!context) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        CVPixelBufferRelease(pixelBuffer);
        return nil;
    }

    CGContextClearRect(context, CGRectMake(0, 0, width, height));
    CGSize imageSize = image.size;
    CGFloat scale = MIN((CGFloat)width / imageSize.width, (CGFloat)height / imageSize.height);
    CGSize drawSize = CGSizeMake(imageSize.width * scale, imageSize.height * scale);
    CGRect drawRect = CGRectMake(((CGFloat)width - drawSize.width) / 2.0, ((CGFloat)height - drawSize.height) / 2.0, drawSize.width, drawSize.height);
    CGContextDrawImage(context, drawRect, image.CGImage);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return pixelBuffer;
}

- (CMSampleBufferRef)newSampleBufferMatching:(CMSampleBufferRef)templateBuffer {
    if (![self isEnabled] || !templateBuffer) return nil;

    CVImageBufferRef templateImage = CMSampleBufferGetImageBuffer(templateBuffer);
    if (!templateImage) return nil;

    size_t width = CVPixelBufferGetWidth(templateImage);
    size_t height = CVPixelBufferGetHeight(templateImage);
    CVPixelBufferRef pixelBuffer = [self newPixelBufferWithWidth:width height:height];
    if (!pixelBuffer) return nil;

    CMVideoFormatDescriptionRef format = nil;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &format);
    if (status != noErr || !format) {
        CVPixelBufferRelease(pixelBuffer);
        return nil;
    }

    CMSampleTimingInfo timing;
    if (CMSampleBufferGetSampleTimingInfo(templateBuffer, 0, &timing) != noErr) {
        timing.duration = CMTimeMake(1, 30);
        timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
        timing.decodeTimeStamp = kCMTimeInvalid;
    }

    CMSampleBufferRef sample = nil;
    status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixelBuffer, format, &timing, &sample);
    CFRelease(format);
    CVPixelBufferRelease(pixelBuffer);
    return status == noErr ? sample : nil;
}

@end

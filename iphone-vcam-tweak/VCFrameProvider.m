#import "VCFrameProvider.h"
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>

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

    NSString *urlString = [NSString stringWithFormat:@"%@/snapshot.jpg?t=%f", self.baseURL, NSDate.date.timeIntervalSince1970];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, __unused NSURLResponse *response, NSError *error) {
        if (error || !data.length) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        self.latestImage = image;
    }];
    [task resume];
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

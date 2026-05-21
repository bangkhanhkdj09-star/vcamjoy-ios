#import "VCFrameSource.h"

#import "VCSampleBufferTools.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>

static NSString *const VCPreferencePath = @"/var/mobile/Library/Preferences/com.local.cleanvcam.plist";
static NSString *const VCDefaultVideoPath = @"/var/mobile/Media/VCam/source.mp4";
static NSString *const VCDefaultImagePath = @"/var/mobile/Media/VCam/source.jpg";
static CFStringRef const VCReloadNotification = CFSTR("com.local.cleanvcam/reload");

@interface VCFrameSource ()
- (void)resetReaderLocked;
- (BOOL)startReaderLocked;
- (CMSampleBufferRef)copyNextVideoFrameLocked;
- (CMSampleBufferRef)copyStillImageFrameLockedMatchingSampleBuffer:(CMSampleBufferRef)sampleBuffer;
@end

@implementation VCFrameSource {
    dispatch_queue_t _queue;
    BOOL _enabled;
    NSString *_mediaPath;
    NSString *_mediaType;
    CGImageRef _stillImage;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_trackOutput;
}

+ (instancetype)sharedSource {
    static VCFrameSource *source;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        source = [[VCFrameSource alloc] initPrivate];
    });
    return source;
}

static void VCPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[VCFrameSource sharedSource] reloadConfiguration];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.local.cleanvcam.frames", DISPATCH_QUEUE_SERIAL);
        [self reloadConfiguration];
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self,
            VCPreferencesChanged,
            VCReloadNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
    return self;
}

- (void)dealloc {
    if (_stillImage) {
        CGImageRelease(_stillImage);
        _stillImage = nil;
    }
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self, VCReloadNotification, NULL);
}

- (BOOL)isEnabled {
    __block BOOL enabled = NO;
    dispatch_sync(_queue, ^{
        enabled = _enabled;
    });
    return enabled;
}

- (void)reloadConfiguration {
    dispatch_sync(_queue, ^{
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCPreferencePath] ?: @{};
        id enabledValue = prefs[@"enabled"];
        _enabled = enabledValue ? [enabledValue boolValue] : YES;

        NSString *configuredType = [prefs[@"mediaType"] isKindOfClass:NSString.class] ? prefs[@"mediaType"] : @"video";
        NSString *configuredPath = [prefs[@"mediaPath"] isKindOfClass:NSString.class] ? prefs[@"mediaPath"] : nil;
        if (!configuredPath.length) {
            configuredPath = [prefs[@"videoPath"] isKindOfClass:NSString.class] ? prefs[@"videoPath"] : nil;
        }

        NSString *nextType = [configuredType isEqualToString:@"image"] ? @"image" : @"video";
        NSString *nextPath = configuredPath.length > 0 ? configuredPath : ([nextType isEqualToString:@"image"] ? VCDefaultImagePath : VCDefaultVideoPath);
        if (![_mediaPath isEqualToString:nextPath] || ![_mediaType isEqualToString:nextType]) {
            _mediaPath = [nextPath copy];
            _mediaType = [nextType copy];
            if (_stillImage) {
                CGImageRelease(_stillImage);
                _stillImage = nil;
            }
            [self resetReaderLocked];
        }
    });
}

- (CMSampleBufferRef)copyFrameMatchingSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) {
        return nil;
    }

    __block CMSampleBufferRef replacement = nil;
    dispatch_sync(_queue, ^{
        if (!_enabled) {
            return;
        }

        CMSampleBufferRef sourceFrame = [_mediaType isEqualToString:@"image"]
            ? [self copyStillImageFrameLockedMatchingSampleBuffer:sampleBuffer]
            : [self copyNextVideoFrameLocked];
        if (!sourceFrame) {
            return;
        }

        replacement = VCCopyVideoSampleBufferWithTiming(sourceFrame, sampleBuffer);
        CFRelease(sourceFrame);
    });
    return replacement;
}

- (void)resetReaderLocked {
    [_reader cancelReading];
    _reader = nil;
    _trackOutput = nil;
}

- (BOOL)startReaderLocked {
    [self resetReaderLocked];

    NSURL *url = [NSURL fileURLWithPath:_mediaPath ?: VCDefaultVideoPath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) {
        return NO;
    }

    NSError *error = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (!reader || error) {
        return NO;
    }

    NSDictionary *settings = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
    output.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:output]) {
        return NO;
    }

    [reader addOutput:output];
    if (![reader startReading]) {
        return NO;
    }

    _reader = reader;
    _trackOutput = output;
    return YES;
}

- (CMSampleBufferRef)copyNextVideoFrameLocked {
    if (!_reader || _reader.status != AVAssetReaderStatusReading) {
        if (![self startReaderLocked]) {
            return nil;
        }
    }

    CMSampleBufferRef frame = [_trackOutput copyNextSampleBuffer];
    if (!frame) {
        if ([self startReaderLocked]) {
            frame = [_trackOutput copyNextSampleBuffer];
        }
    }
    return frame;
}

- (CMSampleBufferRef)copyStillImageFrameLockedMatchingSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!_stillImage) {
        NSURL *url = [NSURL fileURLWithPath:_mediaPath ?: VCDefaultImagePath];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (source) {
            _stillImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
            CFRelease(source);
        }
    }
    CGImageRef image = _stillImage;
    if (!image) {
        return nil;
    }

    CVImageBufferRef targetImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    size_t width = targetImageBuffer ? CVPixelBufferGetWidth(targetImageBuffer) : CGImageGetWidth(image);
    size_t height = targetImageBuffer ? CVPixelBufferGetHeight(targetImageBuffer) : CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        return nil;
    }

    NSDictionary *attrs = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };

    CVPixelBufferRef pixelBuffer = nil;
    CVReturn createResult = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attrs,
        &pixelBuffer
    );
    if (createResult != kCVReturnSuccess || !pixelBuffer) {
        return nil;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        baseAddress,
        width,
        height,
        8,
        bytesPerRow,
        colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    );
    CGColorSpaceRelease(colorSpace);

    if (!context) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        CVPixelBufferRelease(pixelBuffer);
        return nil;
    }

    CGContextSetRGBFillColor(context, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));

    CGFloat imageWidth = CGImageGetWidth(image);
    CGFloat imageHeight = CGImageGetHeight(image);
    CGFloat scale = MAX((CGFloat)width / imageWidth, (CGFloat)height / imageHeight);
    CGSize drawSize = CGSizeMake(imageWidth * scale, imageHeight * scale);
    CGRect drawRect = CGRectMake(
        ((CGFloat)width - drawSize.width) * 0.5,
        ((CGFloat)height - drawSize.height) * 0.5,
        drawSize.width,
        drawSize.height
    );

    CGContextDrawImage(context, drawRect, image);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    CMVideoFormatDescriptionRef formatDescription = nil;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDescription);
    if (status != noErr || !formatDescription) {
        CVPixelBufferRelease(pixelBuffer);
        return nil;
    }

    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, 30),
        .presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock()),
        .decodeTimeStamp = kCMTimeInvalid
    };

    CMSampleBufferRef imageSample = nil;
    status = CMSampleBufferCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        true,
        nil,
        nil,
        formatDescription,
        &timing,
        &imageSample
    );

    CFRelease(formatDescription);
    CVPixelBufferRelease(pixelBuffer);
    return status == noErr ? imageSample : nil;
}

@end

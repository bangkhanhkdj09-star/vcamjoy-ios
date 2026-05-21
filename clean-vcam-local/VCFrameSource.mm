#import "VCFrameSource.h"

#import "VCSampleBufferTools.h"

#import <AVFoundation/AVFoundation.h>

static NSString *const VCPreferencePath = @"/var/mobile/Library/Preferences/com.local.cleanvcam.plist";
static NSString *const VCDefaultVideoPath = @"/var/mobile/Media/VCam/source.mp4";

@implementation VCFrameSource {
    dispatch_queue_t _queue;
    BOOL _enabled;
    NSString *_videoPath;
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

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.local.cleanvcam.frames", DISPATCH_QUEUE_SERIAL);
        [self reloadConfiguration];
    }
    return self;
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

        NSString *configuredPath = [prefs[@"videoPath"] isKindOfClass:NSString.class] ? prefs[@"videoPath"] : nil;
        NSString *nextPath = configuredPath.length > 0 ? configuredPath : VCDefaultVideoPath;
        if (![_videoPath isEqualToString:nextPath]) {
            _videoPath = [nextPath copy];
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

        CMSampleBufferRef sourceFrame = [self copyNextVideoFrameLocked];
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

    NSURL *url = [NSURL fileURLWithPath:_videoPath ?: VCDefaultVideoPath];
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

@end

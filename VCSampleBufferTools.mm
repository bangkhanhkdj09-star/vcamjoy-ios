#import "VCSampleBufferTools.h"

#import <CoreVideo/CoreVideo.h>
#import <VideoToolbox/VideoToolbox.h>

static CVPixelBufferRef VCCreateConvertedPixelBuffer(CVPixelBufferRef sourceBuffer, CMSampleBufferRef timingSource) {
    CVPixelBufferRef targetBuffer = CMSampleBufferGetImageBuffer(timingSource);
    if (!targetBuffer) {
        return nil;
    }

    size_t width = CVPixelBufferGetWidth(targetBuffer);
    size_t height = CVPixelBufferGetHeight(targetBuffer);
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(targetBuffer);
    if (width == 0 || height == 0 || pixelFormat == 0) {
        return nil;
    }

    NSDictionary *attrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(pixelFormat),
        (id)kCVPixelBufferWidthKey: @(width),
        (id)kCVPixelBufferHeightKey: @(height),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferOpenGLESCompatibilityKey: @YES
    };

    CVPixelBufferRef convertedBuffer = nil;
    CVReturn createResult = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, (__bridge CFDictionaryRef)attrs, &convertedBuffer);
    if (createResult != kCVReturnSuccess || !convertedBuffer) {
        return nil;
    }

    VTPixelTransferSessionRef transferSession = nil;
    OSStatus status = VTPixelTransferSessionCreate(kCFAllocatorDefault, &transferSession);
    if (status == noErr && transferSession) {
        VTSessionSetProperty(transferSession, kVTPixelTransferPropertyKey_ScalingMode, kVTScalingMode_Trim);
        status = VTPixelTransferSessionTransferImage(transferSession, sourceBuffer, convertedBuffer);
        CFRelease(transferSession);
    }

    if (status != noErr) {
        CVPixelBufferRelease(convertedBuffer);
        return nil;
    }
    return convertedBuffer;
}

CMSampleBufferRef VCCopyVideoSampleBufferWithTiming(CMSampleBufferRef source, CMSampleBufferRef timingSource) {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(source);
    if (!imageBuffer) {
        return nil;
    }

    CVPixelBufferRef convertedBuffer = VCCreateConvertedPixelBuffer((CVPixelBufferRef)imageBuffer, timingSource);
    CVImageBufferRef outputBuffer = convertedBuffer ?: imageBuffer;

    CMVideoFormatDescriptionRef formatDescription = nil;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, outputBuffer, &formatDescription);
    if (status != noErr || !formatDescription) {
        if (convertedBuffer) {
            CVPixelBufferRelease(convertedBuffer);
        }
        return nil;
    }

    CMSampleTimingInfo timing = {
        .duration = CMSampleBufferGetDuration(timingSource),
        .presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(timingSource),
        .decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(timingSource)
    };

    if (CMTIME_IS_INVALID(timing.duration)) {
        timing.duration = CMTimeMake(1, 30);
    }
    if (CMTIME_IS_INVALID(timing.presentationTimeStamp)) {
        timing.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
    }

    CMSampleBufferRef replacement = nil;
    status = CMSampleBufferCreateForImageBuffer(
        kCFAllocatorDefault,
        outputBuffer,
        true,
        nil,
        nil,
        formatDescription,
        &timing,
        &replacement
    );
    CFRelease(formatDescription);
    if (convertedBuffer) {
        CVPixelBufferRelease(convertedBuffer);
    }

    return status == noErr ? replacement : nil;
}

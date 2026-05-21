#import "VCSampleBufferTools.h"

#import <CoreVideo/CoreVideo.h>

CMSampleBufferRef VCCopyVideoSampleBufferWithTiming(CMSampleBufferRef source, CMSampleBufferRef timingSource) {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(source);
    if (!imageBuffer) {
        return nil;
    }

    CMVideoFormatDescriptionRef formatDescription = nil;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &formatDescription);
    if (status != noErr || !formatDescription) {
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
        imageBuffer,
        true,
        nil,
        nil,
        formatDescription,
        &timing,
        &replacement
    );
    CFRelease(formatDescription);

    return status == noErr ? replacement : nil;
}

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@interface VCFrameProvider : NSObject
+ (instancetype)sharedProvider;
- (BOOL)isEnabled;
- (CGImageRef)latestCGImage;
- (CMSampleBufferRef)newSampleBufferMatching:(CMSampleBufferRef)templateBuffer;
@end

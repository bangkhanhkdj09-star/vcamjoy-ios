#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCFrameSource : NSObject
+ (instancetype)sharedSource;
- (BOOL)isEnabled;
- (void)reloadConfiguration;
- (nullable CMSampleBufferRef)copyFrameMatchingSampleBuffer:(CMSampleBufferRef)sampleBuffer CF_RETURNS_RETAINED;
@end

NS_ASSUME_NONNULL_END

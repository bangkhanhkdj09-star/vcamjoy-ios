#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCFrameSource : NSObject
+ (instancetype)sharedSource;
- (void)noteHook:(NSString *)hookName sampleBuffer:(CMSampleBufferRef _Nullable)sampleBuffer;
- (void)noteEvent:(NSString *)event;
- (BOOL)isEnabled;
- (void)reloadConfiguration;
- (nullable CMSampleBufferRef)copyFrameMatchingSampleBuffer:(CMSampleBufferRef)sampleBuffer CF_RETURNS_RETAINED;
@end

NS_ASSUME_NONNULL_END

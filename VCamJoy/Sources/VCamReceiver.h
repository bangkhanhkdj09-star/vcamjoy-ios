#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@interface VCamReceiver : NSObject <NSURLSessionDataDelegate>
+ (instancetype)sharedReceiver;
- (void)startWithURL:(NSURL *)url;
- (void)stop;
- (CMSampleBufferRef)copyLatestSampleBuffer CF_RETURNS_RETAINED;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) double currentFPS;
@end

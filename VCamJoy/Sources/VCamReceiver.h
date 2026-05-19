#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <UIKit/UIKit.h>

@interface VCamReceiver : NSObject <NSURLSessionDataDelegate>
+ (instancetype)sharedReceiver;
- (void)startWithURL:(NSURL *)url;
- (void)stop;
- (CMSampleBufferRef)copyLatestSampleBuffer CF_RETURNS_RETAINED;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) UIImage *latestImage;
@property (nonatomic, readonly) double currentFPS;
@end

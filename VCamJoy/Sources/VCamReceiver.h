#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface VCamReceiver : NSObject <NSURLSessionDataDelegate>
+ (instancetype)sharedReceiver;
- (void)startWithURL:(NSURL *)url;
- (void)stop;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) UIImage *latestImage;
@end

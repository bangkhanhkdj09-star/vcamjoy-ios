#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@interface VCamHook : NSObject
+ (void)install;
+ (void)setEnabled:(BOOL)enabled;
+ (void)setStreamURL:(NSString *)url;
@end

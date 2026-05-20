#import "VCAppDelegate.h"
#import "VCViewController.h"

@implementation VCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [VCViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

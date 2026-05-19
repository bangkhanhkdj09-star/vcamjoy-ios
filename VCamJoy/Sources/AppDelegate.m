#import "AppDelegate.h"
#import "MainViewController.h"

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:[[MainViewController alloc] init]];
    nav.navigationBar.barStyle    = UIBarStyleBlack;
    nav.navigationBar.translucent = NO;
    nav.navigationBar.tintColor   = [UIColor colorWithRed:0.55 green:0.36 blue:0.98 alpha:1];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

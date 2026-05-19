#import "AppDelegate.h"
#import "MainViewController.h"
#import "VCamHook.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // Install camera hook ngay khi app khởi động
    [VCamHook install];
    
    // Restore prefs
    NSUserDefaults *p = [[NSUserDefaults alloc] initWithSuiteName:@"com.vcamjoy.prefs"];
    [VCamHook setEnabled:[p boolForKey:@"vcamEnabled"]];
    NSString *url = [p stringForKey:@"streamURL"];
    if (url) [VCamHook setStreamURL:url];
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    MainViewController *main = [[MainViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:main];
    nav.navigationBarHidden = YES;
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {}
- (void)applicationDidEnterBackground:(UIApplication *)application {}
- (void)applicationWillEnterForeground:(UIApplication *)application {}
- (void)applicationDidBecomeActive:(UIApplication *)application {}

@end

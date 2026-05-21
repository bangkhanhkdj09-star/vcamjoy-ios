#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>

static NSString *const VCPreferencePath = @"/var/mobile/Library/Preferences/com.local.cleanvcam.plist";
static NSString *const VCMediaDirectory = @"/var/mobile/Media/VCam";
static NSString *const VCVideoPath = @"/var/mobile/Media/VCam/source.mp4";
static NSString *const VCImagePath = @"/var/mobile/Media/VCam/source.jpg";
static CFStringRef const VCReloadNotification = CFSTR("com.local.cleanvcam/reload");

@interface RootListController : PSListController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (NSDictionary *)preferences {
    return [NSDictionary dictionaryWithContentsOfFile:VCPreferencePath] ?: @{};
}

- (void)writePreferences:(NSDictionary *)preferences {
    [[NSFileManager defaultManager] createDirectoryAtPath:[VCPreferencePath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [preferences writeToFile:VCPreferencePath atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), VCReloadNotification, NULL, NULL, true);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *prefs = [self preferences];
    id value = prefs[specifier.properties[@"key"]];
    return value ?: specifier.properties[@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *prefs = [[self preferences] mutableCopy];
    prefs[specifier.properties[@"key"]] = value;
    [self writePreferences:prefs];
}

- (void)pickMedia {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
    if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(__unused PHAuthorizationStatus nextStatus) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self pickMedia];
            });
        }];
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self showMessage:@"Photos unavailable" body:@"Photo Library is not available in this process."];
        return;
    }

    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    picker.delegate = self;
    picker.allowsEditing = NO;
    [self.navigationController presentViewController:picker animated:YES completion:nil];
}

- (void)clearMedia {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:VCVideoPath error:nil];
    [fm removeItemAtPath:VCImagePath error:nil];

    NSMutableDictionary *prefs = [[self preferences] mutableCopy];
    [prefs removeObjectForKey:@"mediaPath"];
    [prefs removeObjectForKey:@"mediaType"];
    [self writePreferences:prefs];
    [self showMessage:@"Cleared" body:@"Clean VCam will pass through the real camera until you choose another photo or video."];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    BOOL isMovie = [mediaType containsString:@"movie"] || [mediaType containsString:@"video"];
    BOOL saved = NO;
    NSString *savedType = isMovie ? @"video" : @"image";
    NSString *savedPath = isMovie ? VCVideoPath : VCImagePath;

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:VCMediaDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [fm removeItemAtPath:savedPath error:nil];

    if (isMovie) {
        NSURL *mediaURL = info[UIImagePickerControllerMediaURL];
        if (mediaURL) {
            saved = [fm copyItemAtURL:mediaURL toURL:[NSURL fileURLWithPath:savedPath] error:nil];
        }
    } else {
        UIImage *image = info[UIImagePickerControllerOriginalImage];
        NSData *jpeg = UIImageJPEGRepresentation(image, 0.92);
        saved = [jpeg writeToFile:savedPath atomically:YES];
    }

    if (saved) {
        NSMutableDictionary *prefs = [[self preferences] mutableCopy];
        prefs[@"enabled"] = @YES;
        prefs[@"mediaType"] = savedType;
        prefs[@"mediaPath"] = savedPath;
        [self writePreferences:prefs];
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        [self showMessage:(saved ? @"Selected" : @"Import failed")
                    body:(saved ? @"Open Camera or a supported app. Clean VCam will inject the selected media." : @"Could not copy the selected media into /var/mobile/Media/VCam.")];
    }];
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.navigationController presentViewController:alert animated:YES completion:nil];
}

@end

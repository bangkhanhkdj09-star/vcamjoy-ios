#import "VCAppViewController.h"

#import <Photos/Photos.h>

static NSString *const VCPreferencePath = @"/var/mobile/Library/Preferences/com.local.cleanvcam.plist";
static NSString *const VCMediaDirectory = @"/var/mobile/Media/VCam";
static NSString *const VCVideoPath = @"/var/mobile/Media/VCam/source.mp4";
static NSString *const VCImagePath = @"/var/mobile/Media/VCam/source.jpg";
static CFStringRef const VCReloadNotification = CFSTR("com.local.cleanvcam/reload");

@interface VCAppViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UILabel *pathLabel;
@end

@implementation VCAppViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Clean VCam";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = @"Virtual Camera";
    titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    titleLabel.numberOfLines = 1;
    [stack addArrangedSubview:titleLabel];

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.text = @"Choose a local photo or video. Camera hooks will use it instead of the live camera feed.";
    subtitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.numberOfLines = 0;
    [stack addArrangedSubview:subtitleLabel];

    UIView *switchRow = [UIView new];
    UILabel *switchLabel = [UILabel new];
    switchLabel.text = @"Enabled";
    switchLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    switchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [switchRow addSubview:switchLabel];

    self.enabledSwitch = [UISwitch new];
    self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
    [switchRow addSubview:self.enabledSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [switchLabel.leadingAnchor constraintEqualToAnchor:switchRow.leadingAnchor],
        [switchLabel.centerYAnchor constraintEqualToAnchor:switchRow.centerYAnchor],
        [self.enabledSwitch.trailingAnchor constraintEqualToAnchor:switchRow.trailingAnchor],
        [self.enabledSwitch.centerYAnchor constraintEqualToAnchor:switchRow.centerYAnchor],
        [switchRow.heightAnchor constraintEqualToConstant:48.0]
    ]];
    [stack addArrangedSubview:switchRow];

    UIButton *pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [pickButton setTitle:@"Choose Photo or Video" forState:UIControlStateNormal];
    pickButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    pickButton.backgroundColor = UIColor.systemBlueColor;
    [pickButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    pickButton.layer.cornerRadius = 10.0;
    pickButton.contentEdgeInsets = UIEdgeInsetsMake(14, 16, 14, 16);
    [pickButton addTarget:self action:@selector(pickMedia) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:pickButton];

    UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearButton setTitle:@"Clear Selected Media" forState:UIControlStateNormal];
    clearButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [clearButton addTarget:self action:@selector(clearMedia) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:clearButton];

    self.statusLabel = [UILabel new];
    self.statusLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.statusLabel.numberOfLines = 0;
    [stack addArrangedSubview:self.statusLabel];

    self.pathLabel = [UILabel new];
    self.pathLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.pathLabel.textColor = UIColor.secondaryLabelColor;
    self.pathLabel.numberOfLines = 0;
    [stack addArrangedSubview:self.pathLabel];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:28.0]
    ]];

    [self reloadUI];
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
    [self reloadUI];
}

- (void)reloadUI {
    NSDictionary *prefs = [self preferences];
    BOOL enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
    NSString *type = [prefs[@"mediaType"] isKindOfClass:NSString.class] ? prefs[@"mediaType"] : nil;
    NSString *path = [prefs[@"mediaPath"] isKindOfClass:NSString.class] ? prefs[@"mediaPath"] : nil;

    self.enabledSwitch.on = enabled;
    if (path.length > 0) {
        self.statusLabel.text = [NSString stringWithFormat:@"Selected: %@", [type isEqualToString:@"image"] ? @"Photo" : @"Video"];
        self.pathLabel.text = path;
    } else {
        self.statusLabel.text = @"No media selected";
        self.pathLabel.text = @"Choose a photo or video before opening Camera.";
    }
}

- (void)enabledChanged:(UISwitch *)sender {
    NSMutableDictionary *prefs = [[self preferences] mutableCopy];
    prefs[@"enabled"] = @(sender.on);
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
        [self showMessage:@"Photos unavailable" body:@"Photo Library is not available."];
        return;
    }

    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    picker.delegate = self;
    picker.allowsEditing = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)clearMedia {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:VCVideoPath error:nil];
    [fm removeItemAtPath:VCImagePath error:nil];

    NSMutableDictionary *prefs = [[self preferences] mutableCopy];
    [prefs removeObjectForKey:@"mediaPath"];
    [prefs removeObjectForKey:@"mediaType"];
    [self writePreferences:prefs];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    BOOL isMovie = [mediaType containsString:@"movie"] || [mediaType containsString:@"video"];
    NSString *savedType = isMovie ? @"video" : @"image";
    NSString *savedPath = isMovie ? VCVideoPath : VCImagePath;
    BOOL saved = NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attributes = @{
        NSFilePosixPermissions: @(0755),
        NSFileOwnerAccountName: @"mobile",
        NSFileGroupOwnerAccountName: @"mobile"
    };
    [fm createDirectoryAtPath:VCMediaDirectory withIntermediateDirectories:YES attributes:attributes error:nil];
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
                    body:(saved ? @"Now open Camera or a supported app." : @"Could not copy the selected media.")];
    }];
}

- (void)showMessage:(NSString *)title body:(NSString *)body {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

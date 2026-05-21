# Clean VCam Local

Clean VCam Local is a source-only Theos tweak scaffold for replacing camera sample buffers with a local photo or video chosen from the Clean VCam Home Screen app.

It does not reuse binaries, domains, helper dylibs, or network behavior from any existing `.deb`.

## What It Does

- Hooks `AVCaptureVideoDataOutput` delegate assignment.
- Wraps the original sample-buffer delegate with a proxy.
- Hooks private `BWNodeOutput -emitSampleBuffer:` for the iOS 16.x Camera pipeline.
- Adds a Home Screen app named Clean VCam.
- Also includes a Settings panel when PreferenceLoader is available.
- Lets you choose a photo or video from the iOS photo library.
- When the app receives `captureOutput:didOutputSampleBuffer:fromConnection:`, the proxy tries to provide a replacement frame from local media.
- If replacement fails, it passes the real camera sample through unchanged.

Default local video path:

```text
/var/mobile/Media/VCam/source.mp4
```

Default local image path:

```text
/var/mobile/Media/VCam/source.jpg
```

Default config path:

```text
/var/mobile/Library/Preferences/com.local.cleanvcam.plist
```

Optional config:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>enabled</key>
  <true/>
  <key>mediaType</key>
  <string>video</string>
  <key>mediaPath</key>
  <string>/var/mobile/Media/VCam/source.mp4</string>
</dict>
</plist>
```

## Use

After installing the `.deb`:

1. Open the Clean VCam app from the Home Screen.
2. Enable the tweak.
3. Tap Choose Photo or Video.
4. Pick a photo or video from the library.
5. Open Camera or a supported app.

Optional Settings panel:

1. Open Settings.
2. Open Clean VCam, if the panel is visible.
3. Enable the tweak.
4. Tap Choose Photo or Video.
5. Pick a photo or video from the library.
6. Open Camera or a supported app.

The selected media is copied locally to `/var/mobile/Media/VCam`; no network connection is used.

## Build

Build on macOS or Linux with Theos and an iPhoneOS SDK:

```sh
make package THEOS_PACKAGE_SCHEME=rootless
```

Install the resulting package on a jailbroken iOS device.

## Notes

This scaffold targets both apps using `AVCaptureVideoDataOutput` and the iOS 16.x private camera path using `BWNodeOutput`. Some social apps use custom capture stacks and may still need app-specific hooks.

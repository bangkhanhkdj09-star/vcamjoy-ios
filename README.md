# Clean VCam Local

Clean VCam Local is a source-only Theos tweak scaffold for replacing camera sample buffers with frames from a local video file.

It does not reuse binaries, domains, helper dylibs, or network behavior from any existing `.deb`.

## What It Does

- Hooks `AVCaptureVideoDataOutput` delegate assignment.
- Wraps the original sample-buffer delegate with a proxy.
- Hooks private `BWNodeOutput -emitSampleBuffer:` for the iOS 16.x Camera pipeline.
- When the app receives `captureOutput:didOutputSampleBuffer:fromConnection:`, the proxy tries to provide a replacement frame from a local video.
- If replacement fails, it passes the real camera sample through unchanged.

Default local video path:

```text
/var/mobile/Media/VCam/source.mp4
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
  <key>videoPath</key>
  <string>/var/mobile/Media/VCam/source.mp4</string>
</dict>
</plist>
```

## Build

Build on macOS or Linux with Theos and an iPhoneOS SDK:

```sh
make package THEOS_PACKAGE_SCHEME=rootless
```

Install the resulting package on a jailbroken iOS device.

## Notes

This scaffold targets both apps using `AVCaptureVideoDataOutput` and the iOS 16.x private camera path using `BWNodeOutput`. Some social apps use custom capture stacks and may still need app-specific hooks.

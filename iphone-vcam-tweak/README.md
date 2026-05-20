# VCam Bubble Tweak

Tweak rootless cho iOS 16 tao bong bong noi de nhap IP PC, preview `/stream`, sync RGB tu `/status`, va hook `AVCaptureVideoDataOutput` de thay frame camera bang `/snapshot.jpg` tu PC.

## Build

```bash
make package
```

## Install

```bash
make install
```

Nếu dùng RootHide, build rootless trước rồi chuyển/cài theo workflow RootHide bạn đang dùng.

## GitHub build

Repo co san workflow `.github/workflows/build-tweak.yml`. Push len GitHub, vao **Actions**, chay **Build iPhone Tweak Deb**, roi tai artifact `VCamBubble-deb`.

## Files

- `Tweak.xm`: tao bubble trong SpringBoard va hook `AVCaptureVideoDataOutput`.
- `VCBubbleController.m`: bubble, panel nhap IP, web view stream, luu prefs.
- `VCFrameProvider.m`: tai `/snapshot.jpg`, tao `CMSampleBufferRef` thay frame camera.
- `Makefile`: cấu hình Theos rootless.
- `control`: metadata gói `.deb`.

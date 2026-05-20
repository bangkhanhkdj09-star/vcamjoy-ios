# VCamJoy iOS

Package nay gom:

- `VCamJoy.app`: app dieu khien tren man hinh chinh, dung de nhap IP PC, xem preview stream, bat/tat hook camera.
- `VCamBubble.dylib`: tweak hook `AVCaptureVideoDataOutput`, doc frame tu PC `/snapshot.jpg`.

Khong con bong bong SpringBoard, nen khong chan vuot/tap va khong lam lag giao dien he thong.

## Build local

```bash
make package THEOS_PACKAGE_SCHEME=rootless
```

## GitHub build

Push repo len GitHub, vao **Actions**, chay **Build iPhone Tweak Deb**, tai artifact `VCamBubble-deb`.

## Cach dung

1. Chay PC app, lay IP dang `192.168.1.xx`.
2. Cai `.deb` va `sbreload`.
3. Mo app **VCamJoy** tren iPhone.
4. Nhap IP, vi du `192.168.1.17`.
5. Bam `Connect`, bat `Bat Camera Ao`.
6. Dong app can dung camera roi mo lai app do.

Neu app bao `PC dang Stream OFF`, bam `Stream ON` tren PC. Ban moi nhat cua PC app se tu bat stream khi upload anh/video.

Luu y: app Camera mac dinh cua Apple co the dung pipeline rieng cua iOS, khong phai luc nao cung di qua `AVCaptureVideoDataOutput`. Hay kiem tra log de biet app nao da duoc hook.

## Kiem tra hook

Trong NewTerm:

```bash
cat /var/mobile/Library/Logs/VCamBubble.log
```

Neu hook vao app thanh cong se co dong:

```text
camera delegate proxied in ...
```

Neu khong co dong nay, app do khong di qua `AVCaptureVideoDataOutput` hoac tweak chua inject vao app.

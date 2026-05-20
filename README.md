# MyTweak — Bubble Test Panel

Tweak test cho **RootHide palera1n** iOS 16.7.11 / 16.7.12.

## Bubble Panel
Khi cài .deb xong, respring -> bong bóng xanh xuất hiện góc màn hình.
- Tap -> hiện alert xác nhận tweak hoạt động
- Kéo thả tự do trên màn hình

## Build qua GitHub Actions
1. Push code lên GitHub (repo public)
2. Actions tự chạy trên macOS runner (có Xcode sẵn, không cần tải SDK)
3. Tải .deb từ tab Actions > Artifacts hoặc Releases

## Cài lên thiết bị
```bash
dpkg -i *.deb
killall SpringBoard
```

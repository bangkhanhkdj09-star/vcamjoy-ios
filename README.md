# MyTweak — Bubble Test Panel

Tweak test cho **RootHide palera1n** iOS 16.7.11 / 16.7.12.

## Mục đích
Khi cài file `.deb`, một **bong bóng xanh** sẽ xuất hiện góc màn hình.  
- Tap vào bong bóng → hiện alert xác nhận tweak hoạt động ✅  
- Kéo thả bong bóng bất kỳ vị trí trên màn hình

## Build qua GitHub Actions

1. Fork/clone repo này lên GitHub
2. Push code → Actions tự chạy
3. Vào tab **Actions → build.yml** → tải file `.deb` từ Artifacts
4. Hoặc xem tab **Releases** để tải bản release

## Cài lên thiết bị

```bash
# Qua SSH / terminal
dpkg -i com.yourname.mytweak_1.0.0_iphoneos-arm64.deb
killall SpringBoard
```

Hoặc kéo file `.deb` vào **Filza** → tap Install.

## Kết quả kiểm tra

| Kết quả | Ý nghĩa |
|---|---|
| 🔵 Bong bóng xanh xuất hiện | .deb hoạt động ✅ |
| Tap → alert hiện | Hook SpringBoard thành công ✅ |
| Không có bong bóng | Kiểm tra `dpkg -l \| grep mytweak` |

## Cấu trúc

```
MyTweak/
├── .github/workflows/build.yml   # GitHub Actions CI
├── layout/DEBIAN/control         # Package metadata
├── Makefile                      # Theos build config
├── Tweak.x                       # Source code (Logos/ObjC)
└── README.md
```

## Yêu cầu (build local)
- [Theos](https://github.com/theos/theos)
- iOS 16.x SDK
- macOS hoặc Linux với LLVM/Clang arm64

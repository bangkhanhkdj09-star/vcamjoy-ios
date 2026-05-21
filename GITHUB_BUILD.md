# Build `.deb` With GitHub Actions

## 1. Create a New GitHub Repository

Create an empty repository on GitHub, for example:

```text
clean-vcam-local
```

Do not add a README from GitHub if you want to push this folder directly.

## 2. Push This Project

From inside this folder:

```sh
git init
git add .
git commit -m "Initial Clean VCam Local tweak"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/clean-vcam-local.git
git push -u origin main
```

## 3. Run the Build

Open the GitHub repository:

```text
Actions -> Build deb -> Run workflow
```

Choose:

```text
rootless
```

for most iOS 16 jailbreaks.

## 4. Download the `.deb`

After the workflow finishes:

```text
Actions -> latest build -> Artifacts -> CleanVCamLocal-...
```

Download the artifact zip and extract the `.deb`.

## 5. Install on Device

Copy the `.deb` to the jailbroken iPhone and install:

```sh
sudo dpkg -i com.local.cleanvcam_0.1.0_iphoneos-arm64.deb
sudo sbreload
```

## 6. Use the Tweak

1. Open the Clean VCam app from the Home Screen.
2. Enable the tweak.
3. Tap Choose Photo or Video.
4. Pick a photo or video from the library.
5. Open Camera or a supported app.

The panel copies selected media to `/var/mobile/Media/VCam/` and updates `/var/mobile/Library/Preferences/com.local.cleanvcam.plist`.

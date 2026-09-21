# SALU Remote

SALU Remote is the Android companion app for SALU. The phone connects to SALU on the
same local Wi-Fi and sends playback commands; SALU remains responsible for playback and
for the media itself.

## Current milestone

The current build contains the first working remote loop:

- pair by the SALU PC address and pairing code;
- reconnect to a remembered PC;
- play/pause, stop, previous/next, seek, volume and mute;
- shuffle, repeat and player/web mode commands;
- live playback state and connection feedback from the PC.

The Android permissions, API level, screen-awake channel and persistence dependency are
already applied in this checkout. The next product step is the QR pairing flow and the
three-tab interface (Play, Browse and Tune), after the first phone-to-PC test succeeds.

## Run from Android Studio

1. Open this repository as a Flutter project.
2. Connect an Android phone with USB debugging enabled.
3. From the repository root run `flutter pub get` once.
4. Select the phone and press **Run**.
5. Follow [`SETUP_STEP_BY_STEP.md`](SETUP_STEP_BY_STEP.md) to pair it with SALU.

`remote.md` is the PC-side protocol/implementation specification. `remote_apk_ui.md` is
the Android interface specification. They are design and implementation references, not
additional setup commands.

## Troubleshooting

### Error: `No Windows desktop project configured` when pressing Run

This project is **Android-only** (only the `android/` folder exists). That error means
Android Studio's device dropdown is set to **Windows (windows-x64)** instead of your phone.

**Fix — select your Android phone:**

1. Look at the top toolbar in Android Studio, center — there is a device selector dropdown. If it says `Windows` or `Chrome` or `Edge`, that's the problem.
2. Plug your phone in via USB. On the phone: enable **Developer options** → **USB debugging**, set USB mode to **File Transfer (MTP)**, and accept the **Allow USB debugging?** prompt (tick *Always allow*).
3. In Android Studio, click the device dropdown → you should now see your phone model (e.g. `sdk gphone` or `SM-A...` or `Redmi...`). Select it.
4. Press **Run** again.

**Verify from terminal:**

```bash
flutter devices
# You should see at least one android device, e.g.:
# sdk gphone ... • android-arm64 • Android 14

flutter pub get
flutter run -d <your-device-id>   # e.g. flutter run -d  emulator-5554  or  -d  192.168...
```

If `flutter devices` shows no Android device:

- Run `adb devices` — if empty, unplug/replug cable, try another USB port/cable, and re-allow debugging on phone.
- On Windows: `File > Settings > Appearance & Behavior > System Settings > Android SDK > SDK Tools` → check **Google USB Driver** → Apply.
- On Xiaomi/Redmi/POCO: also enable **Install via USB** and **USB debugging (Security settings)** in Developer options.

**If you actually want Windows support** (not needed for SALU Remote):

```bash
flutter config --enable-windows-desktop
flutter create --platforms=windows .
```

Then `windows/` folder will be generated and `flutter run -d windows` will work. For the SALU Remote phone app you don't need this — keep it Android-only.

### Warnings: `A restricted method in java.lang.System has been called` during Gradle build

You will see this when running on your phone:

```
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by net.rubygrapefruit.platform.internal.NativeLibraryLoader
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning
```

**This is NOT an error — it's a harmless warning from Gradle 9 + Java 21/24.** Your app is still building. The first `assembleDebug` can take **5-15 minutes** downloading dependencies.

Just **wait**. After the warnings you should see:

```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...
```

If the build hangs for >20 min or ends with a real error (red text `FAILURE` or `Exception`), copy the last 50 lines and send them.

**Fix already applied in this repo:** `android/settings.gradle.kts` now uses AGP `8.7.3` + Kotlin `2.1.0` and `gradle-wrapper.properties` uses Gradle `8.10.2` — the stable combo that removes the warning. After pulling:

```bash
cd salu-remote
flutter clean
flutter pub get
# delete old gradle cache if you had 9.3.1 before:
# On Windows: rmdir /s /q %USERPROFILE%\.gradle\wrapper\dists\gradle-9.3.1-all
flutter run -d ZPFU9LU8AEFISWPV
```

# SALU Remote

SALU Remote is the Android companion app for SALU. The phone connects to SALU on the
same local Wi-Fi and sends playback commands; SALU remains responsible for playback and
for the media itself.

## Current milestone

The current build contains the full v2 scope:

- **Pairing two ways** — in-app QR scan (camera, via `mobile_scanner`) and the
  `salu://pair` deep link, both landing in the connect sheet with the PC pre-filled;
- **the three-tab interface** (Play · Browse · Tune):
  - **Play** — one icon-only transport row (play/pause · stop · previous ·
    next · −10 s · +10 s · fullscreen), a repeat · shuffle icon row,
    realtime seek/volume sliders (they fire while dragging), mute + volume,
    the now-playing/queue card (tap a row to jump, ✕ clears the playlist),
    the mode pill, and the web body (url/iframe switch, back/forward/reload)
    with its own web volume;
  - **Browse** — Files (PC's own file tree, read-only) and Streams (saved
    streams with the PC's health verdict), greyed out while the PC is in web
    mode;
  - **Tune** — Equalizer (the PC's presets and curve, drag a band, speed
    chips), Subtitles (tracks, delay, search, file picker, auto-download) and
    Audio tracks; the tab becomes a **D-pad** in web mode when the PC
    advertises `web_key`;
- **focus mode** — Play with only the essential controls, one gesture away;
- the **connect sheet** (QR / manual / paste, diagnostics, remember me),
  **settings** (phone name + the show/hide checklist), reconnect to a
  remembered PC, live playback state and connection feedback from the PC.

The Android permissions, API level, screen-awake channel and persistence dependency are
already applied in this checkout. `flutter pub get` before the first run — the QR scanner
added one dependency (`mobile_scanner`).

## Run from Android Studio

Gradle in this checkout is pinned to the **Flutter 3.47 template set** — Gradle `9.3.1` + AGP `9.1.0`
+ Kotlin `2.4.0`, which runs on Java **17–25**. If your Java is 26+ (or you are on an old checkout
still on Gradle 8.10.2), see
[Troubleshooting § Java/Gradle incompatibility](#build-fails-gradle-build-failed-due-to-javagradle-incompatibility-java-2503).

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

**This is NOT an error — it's a harmless warning from Gradle 9 running on Java 24/25** (the JDK started restricting `System::load` from unnamed modules). Your app is still building. The first `assembleDebug` can take **5-15 minutes** downloading dependencies.

> **But check the tail of the log.** The warning is only harmless if the build *continues*. If the
> same log ends with `FAILURE: Build failed with an exception` / `Error: Gradle build failed due to
> Java/Gradle incompatibility`, the JDK and Gradle really do disagree — see the next section.

Just **wait**. After the warnings you should see:

```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...
```

If the build hangs for >20 min or ends with a real error (red text `FAILURE` or `Exception`), copy the last 50 lines and send them.

**Why you get it and why we keep it:** the warning can also be silenced by staying on Gradle 8.10.2
+ AGP 8.7.3 + Kotlin 2.1.0 — that is what this repo used to do, and it broke every machine on Java 24+
(see below), while Flutter 3.41+ now *errors* on those three versions anyway. The repo is back on the
Flutter template numbers; this warning is the cheap half of that trade. **Ignore it and wait** — the
first `assembleDebug` after a Gradle bump is slow.

### Build fails: `Gradle build failed due to Java/Gradle incompatibility` (Java 25.0.3)

> **Already fixed in this checkout:** the build is on the Flutter 3.47 template set — Gradle `9.3.1`,
> AGP `9.1.0`, Kotlin `2.4.0` — which runs on Java **17–25**. Pull and rebuild with
> [the repo-side fix](#the-repo-side-fix-already-applied). Read on for why, and use the
> [fallback](#fallback--keep-an-old-gradle-but-give-it-an-older-jdk) only for a checkout you are not
> allowed to touch.

Same log as the warning above, but the build stops. The giveaway is a `What went wrong:` block that
contains nothing but a Java version number:

```
FAILURE: Build failed with an exception.

* What went wrong:
25.0.3

* Try:
> Run with --stacktrace option to be more verbose.

BUILD FAILED in 50s
Error: Gradle build failed due to Java/Gradle incompatibility.
The Java version used for the build is 25.0.3, which is incompatible with Gradle 8.10.2.
```

**What it means:** the JDK that Flutter hands to Gradle is newer than the Gradle the project pins can
run on. Gradle prints the Java version as the entire error message — that is where the lone `25.0.3`
line comes from.

| Java version running Gradle | Oldest Gradle that supports it |
|---|---|
| 17 | 7.3 |
| 21 | 8.5 |
| 23 | 8.10 |
| 24 | 8.14 |
| 25 | 9.1.0 |
| 26 | 9.4.0 |

Source: [Gradle compatibility matrix](https://docs.gradle.org/current/userguide/compatibility.html#java).
This is about the JVM that *runs Gradle*, **not** about `compileOptions` / `jvmTarget = 17` in
`android/app/build.gradle.kts` — leave those at 17, they are your app's bytecode level.

Downgrading Gradle is not a durable escape hatch either — Flutter's own `DependencyVersionChecker`
picks its own fights. On **Flutter 3.47** it *errors* below Gradle `8.14.0`, AGP `8.11.1`, Kotlin
`2.2.20` and *warns* below `9.1.0` / `9.0.1` / `2.3.20` (Flutter 3.44 was one notch more lenient:
error floors `8.7.0` / `8.6.0` / `2.0.0`), while `gradle_utils.dart` caps what it knows at Gradle
`9.3.1`, AGP `9.2`, KGP `2.4.0`. The set this repo now pins — `9.3.1` / `9.1.0` / `2.4.0` — is exactly
the Flutter 3.47 template default, i.e. above every floor and inside every ceiling.

One more thing in that log that is not yours: `I/flutter … NtLifecycle->scheduledWakeUp tag:KeepAlive,
length:Instance of 'BluetoothHelper',Instance of 'NtWatchWorker'` is **not from SALU Remote** — nothing
in `lib/` logs those tags. It is logcat noise from another app on the phone, printed while Gradle was
working.

#### The repo-side fix (already applied)

Three pins move together and nothing else does:

| File | Was | Now |
|---|---|---|
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle `8.10.2-all` | Gradle `9.3.1-all` |
| `android/settings.gradle.kts` | AGP `8.7.3` | AGP `9.1.0` |
| `android/settings.gradle.kts` | Kotlin `2.1.0` | Kotlin `2.4.0` |

`9.3.1` is not arbitrary: AGP `9.1.x` requires Gradle ≥ `9.3.1`, Gradle ≥ `9.1.0` is what makes Java 25
runnable, `9.3.1` is Flutter 3.47's newest known-good, and Gradle `9.6+` drops internal APIs AGP 8.x
still used (irrelevant now, but it is why "just take the latest" was not chosen). No app code, manifest,
`compileSdk` or `minSdk` change. `android.newDsl=false` and `android.builtInKotlin=false` in
`android/gradle.properties` stay as they are — Flutter's own template ships those with AGP 9 so the
legacy `android { }` / `kotlin { compilerOptions { jvmTarget } }` blocks keep working.

Rebuild after pulling, from the repository root:

```powershell
git pull
flutter clean
cd android
.\gradlew.bat --stop      # kill daemons still holding Gradle 8.10.2
cd ..
flutter pub get
flutter run -d ZPFU9LU8AEFISWPV
```

Then in Android Studio: **File → Sync Project with Gradle Files** — or *Invalidate Caches… → Restart* if
the editor still shows stale errors — and press **Run ▶**.

What to expect on that first run:

- Gradle downloads `9.3.1` (a few hundred MB) plus new AGP/Kotlin artifacts: **3–10 minutes**.
- The `WARNING: A restricted method in java.lang.System has been called` lines come back. Harmless —
  that is Gradle 9 on Java 24/25, and silencing it by downgrading is what broke the build.
- Success is `✓ Built build\app\outputs\flutter-apk\app-debug.apk` followed by `Installing…`.
- The old `gradle-8.10.2-all` folder under `%USERPROFILE%\.gradle\wrapper\dists\` is dead weight;
  `rmdir /s /q` it whenever you like.

If you instead get *"Failed to install the following Android SDK components"* or a complaint about
*platform android-36* / *NDK 28.2*: Android Studio → **Settings → Languages & Frameworks → Android SDK**
→ install **Android 16 (API 36)** (tick *Show Package Details* for the NDK), accept the licences:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --licenses
```

(use the SDK folder `flutter doctor --verbose` prints under *Android SDK at*) and run the build again.

Optional, once, so the wrapper files themselves match the distribution (the 8.10.2 `gradle-wrapper.jar`
works fine, this only keeps Android Studio from nagging):

```powershell
cd android
.\gradlew.bat wrapper --gradle-version 9.3.1 --distribution-type all
cd ..
git diff --stat android/gradle android/gradlew   # then commit if it changed
```

To have Flutter audit a project's build versions instead of guessing (useful for other repos, and it
is the same checker these pins came from):

```bash
flutter analyze --suggestions
```

#### Fallback — keep an old Gradle but give it an older JDK

1. Find out which Java Flutter uses for Gradle:

   ```bash
   flutter doctor --verbose
   ```

   Under **Android toolchain** read `Java binary at:` and `Java version`. Flutter looks for a JDK in
   this order: `jdk-folder` set by `flutter config` → **the JDK bundled with your newest Android
   Studio** → `JAVA_HOME` → `java` on `PATH`. Because the Studio-bundled JDK beats `JAVA_HOME`,
   changing `JAVA_HOME` alone often looks like it did nothing — which is why the fix is `flutter config`.
   Java 25 there means either that bundled JBR *is* 25, or `JAVA_HOME` points at a JDK 25 you installed.

2. Find a JDK whose version is 17–23 and note its folder:

   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\java" -version    # newest Studio
   & "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\java" -version  # per-user Studio install
   dir "C:\Program Files\Eclipse Adoptium","C:\Program Files\Java" -ErrorAction SilentlyContinue
   ```

   If every candidate is too new, install one side by side and leave `JAVA_HOME` / `PATH` untouched:
   [Temurin 21 LTS MSI](https://adoptium.net/temurin/releases/?version=21). It must be a JDK, not a JRE
   (`bin\javac.exe` has to exist).

3. Tell Flutter to use it — one line covers the terminal *and* Android Studio's Run button, because
   Studio only runs the same `flutter … run` command:

   ```powershell
   flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-21.0.5.11-hotspot"
   ```

   Prefer a JDK you installed over Studio's `jbr` where you can: Studio updates replace the bundled
   JBR, so it moves to Java 26/27 whether you like it or not. To undo it, set the value to an empty
   string (`flutter config --jdk-dir ""`) — `flutter config` has no per-setting "clear" flag.

4. Same JDK in Studio, otherwise the Gradle tool window keeps showing red while the app builds fine:
   **File → Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK** → pick
   `jbr-17` / `jbr-21` / *Specified JDK…* → **Apply**. Skip if you only ever press Run ▶.

5. Clear daemons and rebuild: `flutter clean`, `.\gradlew.bat --stop` in `android/`, `flutter pub get`,
   `flutter run`. `flutter doctor --verbose` should then report a Java the pinned Gradle supports.

Machine-wide version of the same idea, for people who build from several terminals/IDEs: put it in
your **user** Gradle properties — `%USERPROFILE%\.gradle\gradle.properties` (create if missing):

```properties
# forward slashes; the ":" after the drive letter must stay escaped
org.gradle.java.home=C\:/Program Files/Eclipse Adoptium/jdk-21.0.5.11-hotspot
```

**Never** add that line to `android/gradle.properties`: that file is committed, and a
`C:\Users\mamun\…` path in it breaks the build on every other machine.
